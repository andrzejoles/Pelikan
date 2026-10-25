import AppKit
import PelikanWorkspace
import SwiftUI

/// DBMS Scheduler (UG 10, PD-SCHED-001..003): drzewo rodzajów obiektów, lista, View SQL, tworzenie/edycja/usuwanie
/// zadań, przebiegi z raportami i kolorami, uruchomione zadania ze Stop (Force).
struct SchedulerView: View {
    let workspace: Workspace
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

    private var selected: SchedulerObject? { objects.first { $0.id == selection } }
    private var reports: [Scheduler.RunReport] { workspace.settings.schedulerReports }

    var body: some View {
        // HSplitView zamiast NavigationSplitView: ten dokłada pasek narzędzi okna i treść wchodziła pod tytuł.
        HSplitView {
            List(SchedulerObjectKind.allCases, id: \.self, selection: $kind) { Text($0.displayName) }
                .frame(minWidth: 170, idealWidth: 190, maxWidth: 260)
            VStack(alignment: .leading, spacing: 6) {
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
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { reportName = reports.first?.name ?? ""; await reload() }
        .onChange(of: kind) { Task { await reload() } }
        .onChange(of: selection) { Task { await loadSQL() } }
        .onChange(of: tab) { Task { await reloadTab() } }
        .onChange(of: reportName) { Task { await reloadTab() } }
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
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
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
            objects = try await Scheduler.objects(kind, in: try await SchedulerCommands.session(workspace).1)
            message = L10n.tr("\(kind.displayName): \(objects.count)")
        } catch { message = error.localizedDescription }
    }

    private func reloadTab() async {
        do {
            let s = try await SchedulerCommands.session(workspace).1
            if tab == 1, let r = reports.first(where: { $0.name == reportName }) { runs = try await Scheduler.runs(r, in: s) }
            if tab == 2 { running = try await Scheduler.running(in: s) }
        } catch { message = error.localizedDescription }
    }

    private func loadSQL() async {
        guard let o = selected else { sql = ""; return }
        do {
            let s = try await SchedulerCommands.session(workspace).1
            sql = o.kind == .jobs ? Scheduler.createSQL(try await Scheduler.job(owner: o.owner, name: o.name, in: s))
                : try await Scheduler.ddl(owner: o.owner, name: o.name, in: s)
        } catch { sql = error.localizedDescription }
    }

    private func edit() {
        guard let o = selected else { return }
        Task {
            do {
                let j = try await Scheduler.job(owner: o.owner, name: o.name, in: try await SchedulerCommands.session(workspace).1)
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
                try await SchedulerCommands.execute(text, in: workspace)
                message = L10n.tr("Wykonano")
                await then?()
            } catch CommandError.cancelledByUser {
            } catch { message = error.localizedDescription }
        }
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
                TextField(L10n.tr("Akcja"), text: $job.action, axis: .vertical).font(.system(size: 11, design: .monospaced)).lineLimit(3...8)
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
            Text(L10n.tr("SQL")).font(.caption.bold())
            ScrollView {
                Text(isNew ? Scheduler.createSQL(result) : Scheduler.alterSQL(from: original, to: result))
                    .font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
            HStack {
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button(isNew ? L10n.tr("Utwórz") : L10n.tr("Zapisz")) { done(result) }
            }
        }
        .padding(14)
        .frame(width: 620)
        .onAppear {
            job = original
            named = original.scheduleName != nil
            hasStart = original.startDate != nil
            recipients = original.emailRecipients.joined(separator: ", ")
        }
    }
}
