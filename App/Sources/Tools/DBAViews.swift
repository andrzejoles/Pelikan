import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Panel DBA (SD-DBA-001): sekcje słownika, brak uprawnień jako komunikat, zmiany parametrów i kont po potwierdzeniu.
struct DBAPanelView: View {
    let workspace: Workspace
    @State private var connection: UUID?
    @State private var section: DBAPanel.Section? = .tablespaces
    @State private var result: DBASectionResult?
    @State private var filter = ""
    @State private var selection: Int?
    @State private var message = ""

    var body: some View {
        // HSplitView zamiast NavigationSplitView: ten dokłada pasek narzędzi okna i treść wchodziła pod tytuł.
        HSplitView {
            List(DBAPanel.Section.allCases, selection: $section) { Text($0.displayName).tag($0) }
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 240)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ToolConnectionPicker(workspace: workspace, connection: $connection)
                    TextField(L10n.tr("Filtr"), text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    Spacer()
                    if section == .parameters { Button(L10n.tr("Zmień wartość…")) { alterParameter() }.disabled(selected == nil) }
                    if section == .users {
                        Button(L10n.tr("Zablokuj")) { lock(true) }.disabled(selected == nil)
                        Button(L10n.tr("Odblokuj")) { lock(false) }.disabled(selected == nil)
                    }
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
                }
                switch result {
                case .rows(let cols, _):
                    let rows = filtered
                    DataTable(rows, selection: .single($selection)) {
                        for i in cols.indices {
                            DataColumn(cols[i], id: "\(i)", sortKey: { (r: DetailRow) in i < r.values.count ? r.values[i] : "" }) { (r: DetailRow) in Text(i < r.values.count ? r.values[i] : "").lineLimit(1) }
                        }
                    }
                case .noPrivilege(let m):
                    Label(m, systemImage: "lock").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let m):
                    Text(m).foregroundStyle(.red).frame(maxWidth: .infinity, maxHeight: .infinity)
                case nil:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(minWidth: 900, minHeight: 540)
        .environment(\.reportConnection, connection)

        .toolTask(id: connection) { await reload() }
        .onChange(of: section) { Task { await reload() } }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        _connection = State(initialValue: workspace.toolConnection())
    }

    private var filtered: [DetailRow] {
        let rows = result?.rows ?? []
        let f = filter.lowercased()
        return rows.indices.filter { f.isEmpty || rows[$0].contains { $0.lowercased().contains(f) } }.map { DetailRow(id: $0, values: rows[$0]) }
    }

    private var selected: [String]? { selection.flatMap { i in result?.rows.indices.contains(i) == true ? result?.rows[i] : nil } }

    private func reload() async {
        guard let section else { return }
        result = nil
        selection = nil
        do {
            let s = try await workspace.toolSession("dba", connection: connection)
            result = await DBAPanel.load(section, in: s)
            message = L10n.tr("Wierszy: \(result?.rows.count ?? 0)")
        } catch { result = .failed(error.localizedDescription) }
    }

    private func alterParameter() {
        guard let row = selected, let name = row.first else { return }
        Task {
            guard let v = await workspace.ui?.askText(L10n.tr("Parametr \(name)"), message: L10n.tr("Nowa wartość (ALTER SYSTEM SET … SCOPE=BOTH)"),
                                                     defaultValue: row.count > 1 ? row[1] : "") else { return }
            await run("dba.alterParameter", ["name": .string(name), "value": .string(v)])
        }
    }

    private func lock(_ lock: Bool) {
        guard let user = selected?.first else { return }
        // Nazwa ze słownika — w postaci SQL (`"app_User"` w cudzysłowie), argument komendy podniósłby zwykłą nazwę.
        Task { await run("dba.lockUser", ["user": .string(ResultExporter.identifier(user)), "lock": .bool(lock)]) }
    }

    private func run(_ id: CommandID, _ args: [String: JSONValue]) async {
        guard let connection else { return }
        do {
            var args = args
            args["connection"] = .string(connection.uuidString)
            message = try await workspace.invoke(id, CommandArguments(args)).message ?? ""
            await reload()
        } catch CommandError.cancelledByUser {
        } catch { message = error.localizedDescription }
    }
}

/// Instance Viewer (SD-DBA-004): pulpit instancji z odświeżaniem.
struct InstanceViewerView: View {
    let workspace: Workspace
    /// Auto-odświeżanie pomija narzędzie niewidoczne (karta w tle, zwinięty panel, zminimalizowane okno).
    @Environment(\.toolLifetime) private var lifetime
    @State private var connection: UUID?
    @State private var snap: InstanceSnapshot?
    @State private var auto = true
    @State private var interval = 5.0
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Szeroko: połączenie, opis instancji i odświeżanie w jednym wierszu; w wąskim panelu doku — opis pod spodem.
            ViewThatFits(in: .horizontal) {
                HStack {
                    ToolConnectionPicker(workspace: workspace, connection: $connection)
                    if let s = snap { instanceInfo(s) }
                    Spacer()
                    refreshControls
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ToolConnectionPicker(workspace: workspace, connection: $connection)
                        Spacer(minLength: 4)
                        refreshControls
                    }
                    if let s = snap { instanceInfo(s) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ToolConnectionPicker(workspace: workspace, connection: $connection)
                    refreshControls
                    if let s = snap { instanceInfo(s) }
                }
            }
            if let s = snap {
                // Wykresy obok siebie, w wąskim panelu jeden pod drugim (D222).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { charts(s) }
                    VStack(alignment: .leading, spacing: 10) { charts(s) }
                }
                Text(L10n.tr("Najdroższe SQL (czas)")).font(.uiSecondary.bold())
                DataTable(s.topSQL) {
                    DataColumn("SQL_ID", sortKey: { t in t.sqlID }) { t in Text(t.sqlID).font(.code) }.width(min: 90, ideal: 110)
                    DataColumn(L10n.tr("Wykonania"), sortKey: { t in t.executions }) { t in Text("\(t.executions)").monospacedDigit() }.width(min: 50, ideal: 80)
                    DataColumn.digits(L10n.tr("Czas s"), sortKey: { t in t.elapsedSeconds }, text: { t in String(format: "%.2f", t.elapsedSeconds) }).width(min: 45, ideal: 70)
                    DataColumn.digits("CPU s", sortKey: { t in t.cpuSeconds }, text: { t in String(format: "%.2f", t.cpuSeconds) }).width(min: 45, ideal: 70)
                    DataColumn(L10n.tr("Bufory"), sortKey: { t in t.bufferGets }) { t in Text("\(t.bufferGets)").monospacedDigit() }.width(min: 50, ideal: 90)
                    DataColumn("SQL", sortKey: { t in t.text }) { t in Text(t.text).lineLimit(1) }
                }
                ForEach(s.unavailable, id: \.self) { Text($0).font(.uiSecondary).foregroundStyle(.orange) }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .padding(10)
        .frame(minWidth: 360, minHeight: 560)
        .environment(\.reportConnection, connection)
        .onChange(of: connection) { snap = nil; Task { await refresh() } }
        .task(id: auto ? interval : 0) {
            await refresh()
            while auto, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if lifetime?.isVisible ?? true { await refresh() }
            }
        }
    }

    private func instanceInfo(_ s: InstanceSnapshot) -> some View {
        VStack(alignment: .leading) {
            Text("\(s.instanceName ?? "—") · \(s.status ?? "") · \(s.databaseRole ?? "") · \(s.logMode ?? "")").font(.uiHeadline)
            Text(s.version ?? "").font(.uiSecondary).foregroundStyle(.secondary)
            Text(L10n.tr("Czas pracy: \(uptime(s.uptime)) · sesje: \(s.sessionsTotal.map(String.init) ?? "—"), aktywne: \(s.sessionsActive.map(String.init) ?? "—")")).font(.uiSecondary)
        }
        .lineLimit(2)
    }

    private var refreshControls: some View {
        HStack(spacing: 6) {
            Toggle(L10n.tr("Odświeżaj co"), isOn: $auto).toggleStyle(.checkbox)
            Stepper("\(Int(interval)) s", value: $interval, in: 2...120).fixedSize()
            Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
        }
        .fixedSize()
    }

    /// Oczekiwania (przyrost od poprzedniego odświeżenia) i pule SGA.
    @ViewBuilder private func charts(_ s: InstanceSnapshot) -> some View {
        InstanceBarChart(title: L10n.tr("Oczekiwania (s/s, bez Idle)"),
                         items: s.waitClasses.map { BarItem(name: $0.name, value: $0.rate ?? 0) },
                         format: { String(format: "%.2f", $0) }, empty: L10n.tr("Przyrost oczekiwań po następnym odświeżeniu"))
            .frame(minWidth: 300)
        InstanceBarChart(title: L10n.tr("SGA (MB)") + (s.pgaAllocatedMB.map { " · PGA \($0) MB" } ?? ""),
                         items: s.sga.prefix(8).map { BarItem(name: $0.0, value: $0.1) },
                         format: { String(format: "%.0f", $0) }, empty: "")
            .frame(minWidth: 300)
    }

    private func refresh() async {
        do {
            let s = try await workspace.toolSession("instance", connection: connection)
            snap = await InstanceViewer.snapshot(in: s, previous: snap)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        _connection = State(initialValue: workspace.toolConnection())
    }

    private func uptime(_ t: TimeInterval?) -> String {
        guard let t else { return "—" }
        let d = Int(t) / 86400, h = Int(t) % 86400 / 3600, m = Int(t) % 3600 / 60
        return d > 0 ? "\(d) d \(h) h" : "\(h) h \(m) min"
    }
}

struct BarItem: Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

/// Wykres słupkowy poziomy (D222): w każdym wierszu nazwa (osobna kolumna), słupek proporcjonalny do największej
/// wartości (zaokrąglony koniec, jeden kolor) i wartość — tekst nigdy nie nachodzi na słupek; malejąco.
struct InstanceBarChart: View {
    let title: String
    let items: [BarItem]
    let format: (Double) -> String
    let empty: String

    var body: some View {
        let sorted = items.sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
        let maxValue = sorted.first?.value ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.uiSecondary.bold())
            if maxValue <= 0, !empty.isEmpty {
                Text(empty).font(.uiSecondary).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                ForEach(sorted) { item in
                    GridRow {
                        Text(item.name).font(.uiSecondary).lineLimit(1).gridColumnAlignment(.trailing)
                        GeometryReader { g in
                            let w = maxValue > 0 ? g.size.width * CGFloat(item.value / maxValue) : 0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.08))
                                UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: 4, topTrailing: 4))
                                    .fill(Color.accentColor)
                                    .frame(width: max(w, item.value > 0 ? 2 : 0))
                            }
                        }
                        .frame(height: 12)
                        Text(format(item.value)).font(.uiSecondary).monospacedDigit().foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Task Monitor (SD-MON-002): zadania w tle ze stanem, czasem i anulowaniem.
struct TaskMonitorView: View {
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr("Zadania: \(workspace.tasks.tasks.count), w toku: \(workspace.tasks.tasks.filter(\.isRunning).count)")).font(.uiSecondary)
                Spacer()
                Button(L10n.tr("Usuń zakończone")) { workspace.tasks.clearFinished() }
            }
            DataTable(workspace.tasks.tasks) {
                DataColumn(L10n.tr("Zadanie"), sortKey: { t in t.title }) { t in Text(t.title) }
                DataColumn(L10n.tr("Rodzaj"), sortKey: { t in t.kind }) { t in Text(t.kind).foregroundStyle(.secondary) }.width(90)
                DataColumn(L10n.tr("Stan"), sortKey: { t in status(t) }) { t in Text(status(t)).foregroundStyle(color(t)) }.width(160)
                // Czas zadania w toku odświeża sama komórka (co sekundę) — bez przebudowy tabeli (przewinięcie, „Anuluj”).
                DataColumn(L10n.tr("Czas"), sortKey: { t in t.duration }, text: { t in String(format: "%.1f s", t.duration) }) { t in
                    if t.isRunning {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in Text(String(format: "%.1f s", t.duration)).monospacedDigit() }
                    } else {
                        Text(String(format: "%.1f s", t.duration)).monospacedDigit()
                    }
                }.width(70)
                DataColumn(L10n.tr("Postęp"), sortKey: { t in t.progress ?? -1 }, text: { t in t.progress.map { String(format: "%.0f%%", $0 * 100) } ?? (t.message ?? "") }) { t in
                    if let p = t.progress { ProgressView(value: p) } else { Text(t.message ?? "").font(.uiSecondary).lineLimit(1) }
                }
                DataColumn("", sortKey: { t in t.isRunning }, text: { _ in "" }) { t in
                    if t.isRunning { Button(L10n.tr("Anuluj")) { t.cancel() } }
                }.width(70)
            }
        }
        .padding(10)
        .frame(minWidth: 680, minHeight: 320)
    }

    private func status(_ t: WorkspaceTask) -> String {
        switch t.status {
        case .running: L10n.tr("w toku")
        case .succeeded: L10n.tr("zakończone")
        case .failed(let m): L10n.tr("błąd: \(m)")
        case .cancelled: L10n.tr("anulowane")
        }
    }

    private func color(_ t: WorkspaceTask) -> Color {
        switch t.status {
        case .running: .accentColor
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}

/// Generowanie dokumentacji schematu (SD-DOC-001).
struct SchemaDocView: View {
    let workspace: Workspace
    @State private var owner = ""
    @State private var includeSource = false
    @State private var message = ""
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.tr("Schemat (puste — bieżący)"), text: $owner).textFieldStyle(.roundedBorder)
            Toggle(L10n.tr("Dołącz kod źródłowy programów"), isOn: $includeSource).toggleStyle(.checkbox)
            Text(L10n.tr("Tabele z kolumnami i komentarzami, ograniczenia, indeksy, widoki, programy z parametrami, sekwencje — strony HTML w wybranym katalogu."))
                .font(.uiSecondary).foregroundStyle(.secondary)
            HStack {
                Text(message).font(.uiSecondary)
                Spacer()
                Button(L10n.tr("Generuj…")) { generate() }.disabled(running)
            }
        }
        .padding(14)
        .frame(minWidth: 520, idealWidth: 520, maxWidth: .infinity)
    }

    private func generate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.tr("Generuj")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        running = true
        Task {
            defer { running = false }
            var args: [String: JSONValue] = ["directory": .string(dir.path), "source": .bool(includeSource)]
            if !owner.trimmingCharacters(in: .whitespaces).isEmpty { args["owner"] = .string(owner) }
            do {
                message = try await workspace.invoke("tools.schemaDoc", CommandArguments(args)).message ?? ""
                NSWorkspace.shared.open(dir.appendingPathComponent("index.html"))
            } catch { message = error.localizedDescription }
        }
    }
}
