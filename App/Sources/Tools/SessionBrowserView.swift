import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Przeglądarka sesji (UG 16, PD-TOOL-015/016): filtr, lista sesji, automatyczne odświeżanie, karty szczegółów
/// zaznaczonej sesji, zabijanie sesji i akcje (SQL Trace), edycja zapytań (Define Session Queries). Lista, szczegóły,
/// zabijanie i akcje na połączeniu okna (ustalonym przy otwarciu) — SID/SERIAL# zawsze z tej samej bazy.
struct SessionBrowserView: View {
    let workspace: Workspace
    /// Auto-odświeżanie pomija narzędzie niewidoczne (karta w tle, zwinięty panel, zminimalizowane okno).
    @Environment(\.toolLifetime) private var lifetime
    @State private var connection: UUID?
    @State private var filter = ""
    @State private var rows: [SessionRow] = []
    @State private var selection: SessionRow.ID?
    @State private var detailName = ""
    @State private var detail: SessionBrowser.Detail?
    @State private var message = ""
    @State private var autoRefresh = false
    @State private var interval = 10.0
    @State private var editing = false

    private let shown = ["SID", "SERIAL#", "USERNAME", "STATUS", "OSUSER", "MACHINE", "PROGRAM", "MODULE", "ACTION", "SQL_ID", "PREV_SQL_ID", "EVENT", "LOGON_TIME"]
    private var queries: SessionQueries { workspace.settings.sessionQueries }
    private var selected: SessionRow? { rows.first { $0.id == selection } }

    @ViewBuilder private var sourceControls: some View {
        ToolConnectionPicker(workspace: workspace, connection: $connection)
        Picker(L10n.tr("Filtr"), selection: $filter) {
            ForEach(queries.filters) { Text($0.name).tag($0.sql) }
        }
        .frame(minWidth: 120, maxWidth: 260)
    }

    private var refreshControls: some View {
        AutoRefreshControls(auto: $autoRefresh, interval: $interval, range: 2...300) { Task { await reload() } }
    }

    private var detailPicker: some View {
        Picker("", selection: $detailName) {
            ForEach(queries.details) { Text($0.name).tag($0.name) }
            Text(Self.planTab).tag(Self.planTab)
        }
        .labelsHidden()
    }

    /// Czynności sesji w jednym menu (wąski panel doku).
    private var sessionMenu: some View {
        Menu(L10n.tr("Sesja")) {
            Button(L10n.tr("Zakończ sesję (Kill)")) { kill(immediate: false) }
            Button(L10n.tr("Zakończ natychmiast")) { kill(immediate: true) }
            if !queries.actions.isEmpty {
                Divider()
                ForEach(queries.actions) { a in Button(a.name) { perform(a) } }
            }
        }
        .fixedSize()
        .disabled(selected == nil)
    }

    private var sessionActions: some View {
        HStack(spacing: 6) {
            Button(L10n.tr("Zakończ sesję (Kill)")) { kill(immediate: false) }.disabled(selected == nil)
            Button(L10n.tr("Zakończ natychmiast")) { kill(immediate: true) }.disabled(selected == nil)
            Menu(L10n.tr("Akcje")) {
                ForEach(queries.actions) { a in Button(a.name) { perform(a) } }
            }
            .fixedSize()
            .disabled(selected == nil)
            Button(L10n.tr("Zapytania…")) { editing = true }
        }
        .fixedSize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Szeroko — jeden wiersz; w wąskim panelu doku — połączenie i filtr, odświeżanie, czynności w osobnych wierszach.
            ViewThatFits(in: .horizontal) {
                HStack { sourceControls; refreshControls; Spacer(); sessionActions }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { sourceControls; refreshControls }
                    HStack { sessionActions; Spacer() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    sourceControls
                    HStack { refreshControls; Spacer() }
                    HStack { sessionActions; Spacer() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    sourceControls
                    HStack { refreshControls; Spacer() }
                    HStack { sessionMenu; Button(L10n.tr("Zapytania…")) { editing = true }; Spacer() }
                }
            }
            VSplitView {
                DataTable(rows, title: L10n.tr("Sesje"), selection: .single($selection)) {
                    for name in shown {
                        DataColumn(name, text: { (r: SessionRow) in r.values[name] ?? "" })
                    }
                }
                .frame(minHeight: 160)
                VStack(alignment: .leading, spacing: 4) {
                    // Karty szczegółów: segmenty, a w wąskim panelu doku — lista rozwijana.
                    ViewThatFits(in: .horizontal) {
                        detailPicker.pickerStyle(.segmented)
                        detailPicker.pickerStyle(.menu).fixedSize()
                    }
                    detailView
                }
                .frame(minHeight: 120)
            }
            Text(message).font(.uiSecondary).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 340, minHeight: 520)
        .environment(\.reportConnection, connection)

        .toolTask(id: 0) {
            filter = queries.filters.first { $0.sql == "type = 'USER'" }?.sql ?? queries.filters.first?.sql ?? ""
            detailName = queries.details.first?.name ?? ""
            await reload()
        }
        .task(id: autoRefresh ? interval : 0) {
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if lifetime?.isVisible ?? true { await reload() }
            }
        }
        .onChange(of: filter) { Task { await reload() } }
        .onChange(of: connection) {
            selection = nil
            Task { await reload() }
        }
        .onChange(of: selection) { Task { await loadDetail() } }
        .onChange(of: detailName) { Task { await loadDetail() } }
        .sheet(isPresented: $editing) { SessionQueriesEditor(workspace: workspace, done: { editing = false }) }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        _connection = State(initialValue: workspace.toolConnection())
    }

    private func session() async throws -> any DatabaseSession {
        try await workspace.toolSession("sessions", connection: connection)
    }

    /// Karta planu bieżącego zapytania sesji (D220): SQL_ID, a gdy sesja nic nie wykonuje — PREV_SQL_ID.
    static let planTab = L10n.tr("Plan wykonania")

    @ViewBuilder private var detailView: some View {
        if detailName == Self.planTab {
            if let r = selected {
                let current = (r.values["SQL_ID"] ?? "").trimmingCharacters(in: .whitespaces)
                let id = current.isEmpty ? (r.values["PREV_SQL_ID"] ?? "").trimmingCharacters(in: .whitespaces) : current
                let child = Int(current.isEmpty ? r.values["PREV_CHILD_NUMBER"] ?? "" : r.values["SQL_CHILD_NUMBER"] ?? "")
                if SQLIdentity.isSQLID(id), let connection {
                    SessionPlanView(workspace: workspace, connection: connection, sqlID: id, child: child, previous: current.isEmpty)
                        .id("\(id)/\(child ?? -1)")
                } else {
                    Text(L10n.tr("Sesja nie ma bieżącego ani poprzedniego zapytania")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text(L10n.tr("Zaznacz sesję")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let d = detail {
            if let text = d.text {
                CodePreview(text: text)
            } else {
                DataTable(d.rows.indices.map { DetailRow(id: $0, values: d.rows[$0]) }, title: detailName) {
                    for i in d.columns.indices {
                        DataColumn(d.columns[i], id: "\(i)", text: { (r: DetailRow) in i < r.values.count ? r.values[i] : "" })
                    }
                }
            }
        } else {
            Text(L10n.tr("Zaznacz sesję")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reload() async {
        do {
            let s = try await session()
            rows = try await SessionBrowser.list(filter: filter, in: s)
            message = L10n.tr("Sesje: \(rows.count)")
            await loadDetail()
        } catch { message = error.localizedDescription }
    }

    private func loadDetail() async {
        guard detailName != Self.planTab else { detail = nil; return }
        guard let r = selected, let item = queries.details.first(where: { $0.name == detailName }) else { detail = nil; return }
        do {
            detail = try await SessionBrowser.detail(item, sid: r.sid, serial: r.serial, in: try await session())
        } catch { message = error.localizedDescription; detail = nil }
    }

    private func kill(immediate: Bool) {
        guard let r = selected, let connection else { return }
        Task {
            do {
                try await workspace.invoke("sessions.kill", CommandArguments(["sid": .int(Int64(r.sid)), "serial": .int(Int64(r.serial)), "immediate": .bool(immediate),
                                                                               "connection": .string(connection.uuidString)]))
                await reload()
            } catch CommandError.cancelledByUser {
            } catch { message = error.localizedDescription }
        }
    }

    private func perform(_ a: SessionQueries.Item) {
        guard let r = selected, let connection else { return }
        Task {
            do {
                try await workspace.invoke("sessions.action", CommandArguments(["sid": .int(Int64(r.sid)), "serial": .int(Int64(r.serial)), "action": .string(a.name),
                                                                                 "connection": .string(connection.uuidString)]))
                message = L10n.tr("Wykonano: \(a.name)")
            } catch CommandError.cancelledByUser {
            } catch { message = error.localizedDescription }
        }
    }
}

struct DetailRow: Identifiable {
    let id: Int
    let values: [String]
}

/// Edycja zapytań przeglądarki sesji (UG 16.2).
struct SessionQueriesEditor: View {
    let workspace: Workspace
    let done: () -> Void
    @State private var queries = SessionQueries.standard
    @State private var section = 0
    @State private var selected: String?

    private var items: Binding<[SessionQueries.Item]> {
        switch section {
        case 0: $queries.filters
        case 1: $queries.details
        default: $queries.actions
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $section) {
                Text(L10n.tr("Filtry (warunek WHERE)")).tag(0)
                Text(L10n.tr("Szczegóły (:sid, /* concatenate */)")).tag(1)
                Text(L10n.tr("Akcje (:sid, :serial#)")).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            List {
                ForEach(items) { $item in
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(L10n.tr("Nazwa"), text: $item.name).font(.uiHeadline)
                        TextField("SQL", text: $item.sql, axis: .vertical).font(.code).lineLimit(1...4)
                    }
                }
                .onDelete { items.wrappedValue.remove(atOffsets: $0) }
            }
            HStack {
                Button(L10n.tr("Dodaj")) { items.wrappedValue.append(SessionQueries.Item(name: L10n.tr("Nowe"), sql: "")) }
                Button(L10n.tr("Domyślne")) { queries = .standard }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { done() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Zapisz")) {
                    workspace.settings.sessionQueries = queries
                    done()
                }
            }
        }
        .padding(14)
        .windowSize(width: 720, height: 460)
        .onAppear { queries = workspace.settings.sessionQueries }
    }
}

/// Plan bieżącego zapytania sesji (D220, D221): z pamięci kursorów (DBMS_XPLAN), format wyniku HTML/tekst/XML i format
/// planu do wyboru; raporty dla SQL_ID jednym przyciskiem.
struct SessionPlanView: View {
    let workspace: Workspace
    let connection: UUID
    let sqlID: String
    let child: Int?
    let previous: Bool
    @AppStorage("sessionPlan.format") private var formatRaw = ReportFormat.html.rawValue
    @AppStorage("sessionPlan.planFormat") private var planFormat = "ALLSTATS LAST +PEEKED_BINDS"
    @State private var output: PerfReportOutput?
    @State private var file: URL?
    @State private var message = ""
    @State private var busy = false

    /// Bez ACTIVE: Oracle nie udostępnia już przeglądarki aktywnego raportu planu (xplan — błąd 404 na serwerze Oracle; D221).
    private var format: ReportFormat { ReportFormat(rawValue: formatRaw).flatMap { $0 == .active ? nil : $0 } ?? .html }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(previous ? L10n.tr("Poprzednie zapytanie \(sqlID)") : L10n.tr("Bieżące zapytanie \(sqlID)")).font(.code).textSelection(.enabled)
                Picker(L10n.tr("Wynik"), selection: $formatRaw) {
                    ForEach([ReportFormat.html, .text, .xml], id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
                .fixedSize()
                Picker(L10n.tr("Plan"), selection: $planFormat) {
                    ForEach(PerfReportParameters.planFormats, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.tr("Raporty dla SQL_ID…")) {
                    SQLReportLauncher.open(SQLReportTarget(target: .sqlID(sqlID), origin: L10n.tr("okno sesji"), connection: connection))
                }
            }
            .controlSize(.small)
            .font(.uiSecondary)
            if let o = output {
                switch o.format {
                case .active: if let file { ActiveReportView(file: file).id(file) }
                case .html: HTMLPreview(html: o.content)
                default: HighlightedCodeView(text: o.content, highlight: false)
                }
            } else {
                Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(formatRaw)|\(planFormat)") { await load() }
    }

    private func load() async {
        busy = true
        defer { busy = false }
        do {
            let s = try await workspace.toolSession("sessions", connection: connection)
            var q = PerfReportRequest(reportID: "sql.planCursor", sqlID: sqlID, format: format)
            q.source = .cursorCache
            q.child = child
            q.planFormat = planFormat
            let out = try await PerfReportRunner.run(q, availability: nil, license: .unlicensed, in: s)
            file = out.format == .active ? PerfReportPresenter.write(out) : nil
            output = out
        } catch {
            output = nil
            message = error.localizedDescription
        }
    }
}
