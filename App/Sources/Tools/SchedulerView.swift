import AppKit
import PelikanWorkspace
import SwiftUI

/// DBMS Scheduler (UG 10, PD-SCHED-001..003): drzewo rodzajów obiektów, lista, View SQL, tworzenie/edycja/usuwanie
/// zadań, przebiegi z raportami i kolorami, uruchomione zadania ze Stop (Force).
struct SchedulerView: View {
    let workspace: Workspace
    @State private var connection: UUID?
    @State private var kind: SchedulerObjectKind? = .jobs
    @State private var objects: [SchedulerObject] = []
    @State private var selection: SchedulerObject.ID?
    @State private var tab = 0
    @State private var sql = ""
    @State private var message = ""
    @State private var editing: JobEditing?
    @State private var reportName = ""
    @State private var runs: (columns: [String], rows: [[String]]) = ([], [])
    @State private var running: (columns: [String], rows: [[String]]) = ([], [])
    @State private var runningSelection: Int?
    @State private var editingReports = false

    private var selected: SchedulerObject? { objects.first { $0.id == selection } }
    private var reports: [Scheduler.RunReport] { workspace.settings.schedulerReports }

    var body: some View {
        // HSplitView zamiast NavigationSplitView: ten dokłada pasek narzędzi okna i treść wchodziła pod tytuł.
        HSplitView {
            List(SchedulerObjectKind.allCases, id: \.self, selection: $kind) { Text($0.displayName) }
                .frame(minWidth: 170, idealWidth: 190, maxWidth: 260)
            VStack(alignment: .leading, spacing: 6) {
                ToolConnectionPicker(workspace: workspace, connection: $connection)
                Picker("", selection: $tab) {
                    Text(L10n.tr("Obiekty")).tag(0)
                    Text(L10n.tr("Przebiegi")).tag(1)
                    Text(L10n.tr("Uruchomione")).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch tab {
                case 0: objectsTab
                case 1: runsTab
                default: runningTab
                }
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { reportName = reports.first?.name ?? "" }
        .task(id: connection) {
            selection = nil
            await reload()
            await reloadTab()
        }
        .onChange(of: kind) { Task { await reload() } }
        .onChange(of: selection) { Task { await loadSQL() } }
        .onChange(of: tab) { Task { await reloadTab() } }
        .onChange(of: reportName) { Task { await reloadTab() } }
        .sheet(isPresented: $editingReports) {
            SchedulerReportsEditor(workspace: workspace) {
                editingReports = false
                if !reports.contains(where: { $0.name == reportName }) { reportName = reports.first?.name ?? "" }
                Task { await reloadTab() }
            }
        }
        .sheet(item: $editing) { e in
            JobEditor(original: e.job, isNew: e.isNew) { job in
                editing = nil
                guard let job else { return }
                let text = e.isNew ? Scheduler.createSQL(job) : Scheduler.alterSQL(from: e.job, to: job)
                guard !text.isEmpty else { return }
                run(text, then: { await reload() })
            }
        }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        _connection = State(initialValue: workspace.toolConnection())
    }

    private var objectsTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(L10n.tr("Nowe zadanie…")) { editing = JobEditing(job: SchedulerJob(name: "NOWE_ZADANIE", action: "begin\n  null;\nend;"), isNew: true) }
                Button(L10n.tr("Edytuj…")) { edit() }.disabled(selected?.kind != .jobs)
                Button(L10n.tr("Uruchom")) {
                    if let o = selected { run(Scheduler.runSQL(owner: o.owner, name: o.name)) }
                }.disabled(selected?.kind != .jobs)
                Button(L10n.tr("Usuń")) { drop() }.disabled(selected == nil)
                Spacer()
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
            }
            VSplitView {
                Table(objects, selection: $selection) {
                    TableColumn(L10n.tr("Właściciel")) { o in Text(o.owner) }.width(110)
                    TableColumn(L10n.tr("Nazwa")) { o in Text(o.name) }
                    TableColumn(L10n.tr("Stan")) { o in Text(o.state) }.width(100)
                    TableColumn(L10n.tr("Harmonogram / szczegóły")) { o in Text(o.detail).lineLimit(1) }
                    TableColumn(L10n.tr("Komentarz")) { o in Text(o.comments).lineLimit(1) }
                }
                .frame(minHeight: 180)
                ScrollView {
                    Text(sql.isEmpty ? L10n.tr("View SQL — zaznacz obiekt") : sql)
                        .font(.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                .frame(minHeight: 100)
            }
        }
    }

    private var runsTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker(L10n.tr("Raport"), selection: $reportName) { ForEach(reports) { Text($0.name).tag($0.name) } }.frame(maxWidth: 280)
                Button(L10n.tr("Raporty…")) { editingReports = true }
                Spacer()
                Button { Task { await reloadTab() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
            }
            grid(runs, colors: reports.first { $0.name == reportName }?.colors ?? [], selection: .constant(nil))
        }
    }

    private var runningTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(L10n.tr("Zatrzymaj")) { stop(force: false) }.disabled(runningSelection == nil)
                Button(L10n.tr("Zatrzymaj (Force)")) { stop(force: true) }.disabled(runningSelection == nil)
                Spacer()
                Button { Task { await reloadTab() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
            }
            grid(running, colors: [], selection: $runningSelection)
        }
    }

    private func grid(_ data: (columns: [String], rows: [[String]]), colors: [Scheduler.RunReport.ColorRule], selection: Binding<Int?>) -> some View {
        Table(data.rows.indices.map { DetailRow(id: $0, values: data.rows[$0]) }, selection: selection) {
            TableColumnForEach(data.columns.indices.map { $0 }, id: \.self) { i in
                TableColumn(data.columns[i]) { (r: DetailRow) in
                    let rule = colors.first { c in data.columns.firstIndex(of: c.column.uppercased()).map { $0 < r.values.count && r.values[$0] == c.value } ?? false }
                    Text(i < r.values.count ? r.values[i] : "").lineLimit(1)
                        .foregroundStyle(rule.map { Color(red: $0.color.red, green: $0.color.green, blue: $0.color.blue) } ?? .primary)
                }
            }
        }
    }

    private func reload() async {
        guard let kind else { return }
        do {
            objects = try await Scheduler.objects(kind, in: try await SchedulerCommands.session(workspace, connection: connection).1)
            message = L10n.tr("\(kind.displayName): \(objects.count)")
        } catch { message = error.localizedDescription }
    }

    private func reloadTab() async {
        do {
            let s = try await SchedulerCommands.session(workspace, connection: connection).1
            if tab == 1, let r = reports.first(where: { $0.name == reportName }) { runs = try await Scheduler.runs(r, in: s) }
            if tab == 2 { running = try await Scheduler.running(in: s) }
        } catch { message = error.localizedDescription }
    }

    private func loadSQL() async {
        guard let o = selected else { sql = ""; return }
        do {
            let s = try await SchedulerCommands.session(workspace, connection: connection).1
            sql = o.kind == .jobs ? Scheduler.createSQL(try await Scheduler.job(owner: o.owner, name: o.name, in: s))
                : try await Scheduler.ddl(owner: o.owner, name: o.name, in: s)
        } catch { sql = error.localizedDescription }
    }

    private func edit() {
        guard let o = selected else { return }
        Task {
            do {
                let j = try await Scheduler.job(owner: o.owner, name: o.name, in: try await SchedulerCommands.session(workspace, connection: connection).1)
                editing = JobEditing(job: j, isNew: false)
            } catch { message = error.localizedDescription }
        }
    }

    private func drop() {
        guard let o = selected, let kind else { return }
        Task {
            guard await workspace.ui?.ask(L10n.tr("Usunąć \(o.owner).\(o.name)?"), message: kind.displayName, buttons: [L10n.tr("Usuń"), L10n.tr("Anuluj")]) == 0 else { return }
            run(Scheduler.dropSQL(kind, owner: o.owner, name: o.name, force: true), then: { await reload() })
        }
    }

    private func stop(force: Bool) {
        guard let i = runningSelection, i < running.rows.count, running.rows[i].count > 1 else { return }
        run(Scheduler.stopSQL(owner: running.rows[i][0], name: running.rows[i][1], force: force), then: { await reloadTab() })
    }

    private func run(_ text: String, then: (() async -> Void)? = nil) {
        Task {
            do {
                try await SchedulerCommands.execute(text, connection: connection, in: workspace)
                message = L10n.tr("Wykonano")
                await then?()
            } catch CommandError.cancelledByUser {
            } catch { message = error.localizedDescription }
        }
    }
}

/// Własne raporty przebiegów (PD-SCHED-003): nazwa, warunek WHERE na ALL_SCHEDULER_JOB_RUN_DETAILS i kolory wierszy
/// (kolumna = wartość → kolor). Zapis do ustawień (`schedulerReports`) po „Zapisz”.
struct SchedulerReportsEditor: View {
    /// Wiersze edytora z własnym identyfikatorem — nazwa raportu zmienia się w trakcie edycji.
    struct Rule: Identifiable {
        let id = UUID()
        var column: String
        var value: String
        var color: Color
    }

    struct Draft: Identifiable {
        let id = UUID()
        var name: String
        var condition: String
        var rules: [Rule]
    }

    let workspace: Workspace
    let done: () -> Void
    @State private var drafts: [Draft] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach($drafts) { $d in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField(L10n.tr("Nazwa"), text: $d.name).font(.uiHeadline)
                            Button { drafts.removeAll { $0.id == d.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).iconLabel(L10n.tr("Usuń"))
                        }
                        TextField(L10n.tr("Warunek"), text: $d.condition, prompt: Text("status <> 'SUCCEEDED'"))
                            .font(.system(size: 12, design: .monospaced))
                        Text(L10n.tr("Kolory wierszy")).font(.uiSecondary).foregroundStyle(.secondary)
                        ForEach($d.rules) { $r in
                            HStack {
                                TextField(L10n.tr("Kolumna"), text: $r.column, prompt: Text("STATUS")).frame(width: 160)
                                TextField(L10n.tr("Wartość"), text: $r.value, prompt: Text("FAILED"))
                                ColorPicker(L10n.tr("Kolor"), selection: $r.color, supportsOpacity: false).labelsHidden()
                                Button { d.rules.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).iconLabel(L10n.tr("Usuń regułę"))
                            }
                        }
                        Button(L10n.tr("Dodaj regułę")) { d.rules.append(Rule(column: "STATUS", value: "", color: .red)) }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Button(L10n.tr("Dodaj")) { drafts.append(Draft(name: L10n.tr("Nowy raport"), condition: "", rules: [])) }
                Button(L10n.tr("Domyślne")) { drafts = Self.drafts(Scheduler.RunReport.standard) }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { done() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Zapisz")) {
                    workspace.settings.schedulerReports = Scheduler.RunReport.normalized(drafts.map(Self.report))
                    done()
                }
            }
        }
        .padding(14)
        .windowSize(width: 720, height: 480)
        .onAppear { drafts = Self.drafts(workspace.settings.schedulerReports) }
    }

    static func drafts(_ reports: [Scheduler.RunReport]) -> [Draft] {
        reports.map { r in
            Draft(name: r.name, condition: r.condition,
                  rules: r.colors.map { Rule(column: $0.column, value: $0.value, color: Color(red: $0.color.red, green: $0.color.green, blue: $0.color.blue)) })
        }
    }

    static func report(_ d: Draft) -> Scheduler.RunReport {
        Scheduler.RunReport(name: d.name, condition: d.condition, colors: d.rules.map { r in
            let n = NSColor(r.color).usingColorSpace(.sRGB) ?? .systemRed
            return .init(column: r.column, value: r.value, color: RGBColor(red: n.redComponent, green: n.greenComponent, blue: n.blueComponent))
        })
    }
}

struct JobEditing: Identifiable {
    let id = UUID()
    let job: SchedulerJob
    let isNew: Bool
}

/// Edycja zadania: akcja, harmonogram wbudowany albo nazwany, klasa, powiadomienia e-mail, podgląd SQL.
struct JobEditor: View {
    let original: SchedulerJob
    let isNew: Bool
    let done: (SchedulerJob?) -> Void
    @State private var job = SchedulerJob(name: "", action: "")
    @State private var named = false
    @State private var hasStart = false
    @State private var recipients = ""

    private var result: SchedulerJob {
        var j = job
        if named { j.repeatInterval = nil; j.startDate = nil } else { j.scheduleName = nil; if !hasStart { j.startDate = nil } }
        j.emailRecipients = recipients.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return j
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Form {
                TextField(L10n.tr("Nazwa"), text: $job.name).disabled(!isNew)
                Picker(L10n.tr("Typ"), selection: $job.type) { ForEach(SchedulerJob.JobType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField(L10n.tr("Akcja"), text: $job.action, axis: .vertical).font(.code).lineLimit(3...8)
                Toggle(L10n.tr("Harmonogram nazwany"), isOn: $named)
                if named {
                    TextField(L10n.tr("Harmonogram"), text: Binding(get: { job.scheduleName ?? "" }, set: { job.scheduleName = $0 }))
                } else {
                    Toggle(L10n.tr("Początek"), isOn: $hasStart)
                    if hasStart { DatePicker("", selection: Binding(get: { job.startDate ?? Date() }, set: { job.startDate = $0 })) }
                    TextField(L10n.tr("Powtarzanie (np. FREQ=DAILY;BYHOUR=3)"), text: Binding(get: { job.repeatInterval ?? "" }, set: { job.repeatInterval = $0.isEmpty ? nil : $0 }))
                }
                TextField(L10n.tr("Klasa zadania"), text: Binding(get: { job.jobClass ?? "" }, set: { job.jobClass = $0.isEmpty ? nil : $0 }))
                Toggle(L10n.tr("Włączone"), isOn: $job.enabled)
                Toggle(L10n.tr("Usuń po zakończeniu"), isOn: $job.autoDrop)
                TextField(L10n.tr("Komentarz"), text: $job.comments)
                TextField(L10n.tr("Powiadomienia e-mail (adresy po przecinku)"), text: $recipients)
            }
            Text(L10n.tr("SQL")).font(.uiSecondary.bold())
            ScrollView {
                Text(isNew ? Scheduler.createSQL(result) : Scheduler.alterSQL(from: original, to: result))
                    .font(.code).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
            HStack {
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button(isNew ? L10n.tr("Utwórz") : L10n.tr("Zapisz")) { done(result) }
            }
        }
        .padding(14)
        .frame(minWidth: 620, idealWidth: 620, maxWidth: .infinity)
        .onAppear {
            job = original
            named = original.scheduleName != nil
            hasStart = original.startDate != nil
            recipients = original.emailRecipients.joined(separator: ", ")
        }
    }
}
