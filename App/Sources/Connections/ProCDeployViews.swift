import AppKit
import PelikanProC
import PelikanRemote
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

/// Wdrożenia Pro*C w aplikacji: sesje SSH celów (sekret z Pęku kluczy przez `SSHTargetStore`), pipeline'y, historia.
@MainActor
@Observable
final class ProCDeployModel {
    let store: SSHTargetStore
    let workspace: Workspace
    let runDirectory: URL
    let center = DeployCenter()
    let history: DeployHistoryStore
    @ObservationIgnored private var sessions: [UUID: SSHSession] = [:]

    init(store: SSHTargetStore, workspace: Workspace, runDirectory: URL) {
        self.store = store
        self.workspace = workspace
        self.runDirectory = runDirectory
        history = DeployHistoryStore(directory: workspace.dataDirectory?.appendingPathComponent("proc-deploys", isDirectory: true))
        if let problem = history.loadProblem { Task { @MainActor in workspace.ui?.showError(problem) } }
    }

    /// Katalog lokalnego repo projektu (katalog otwartego projektu Pelikana).
    var repository: URL? { workspace.projectURL?.deletingLastPathComponent() }

    func target(named name: String?) -> PelikanSSHTarget? {
        guard let name else { return nil }
        return store.targets.first { $0.name == name }
    }

    /// Sesja SSH celu (ControlMaster; sekret tylko w pamięci domknięcia — z Pęku kluczy, z Touch ID przy D56).
    func session(for t: PelikanSSHTarget) async throws -> SSHSession {
        if let s = sessions[t.id], s.config == SSHTargetTester.sessionConfig(t) { return s }
        let secret: String? = t.auth == .agent ? nil : try await store.secret(for: t.id, in: workspace)
        let s = try SSHSession(config: SSHTargetTester.sessionConfig(t), runDirectory: runDirectory, secret: { secret })
        sessions[t.id] = s
        return s
    }

    /// Zamknięcie aplikacji: połączenia główne SSH (ControlPersist) nie zostają po niej na serwerach celów.
    func disconnectAll() {
        for s in sessions.values { s.disconnect() }
        sessions = [:]
    }

    /// Cele UAT w tym samym folderze co cel PROD (sprawdzenie, czy commit był już na UAT).
    func uatSiblings(of t: PelikanSSHTarget) -> [UUID] {
        store.targets.filter { $0.environment == .uat && $0.folderID == t.folderID && $0.id != t.id }.map(\.id)
    }

    func start(_ t: PelikanSSHTarget, operation: DeployPipeline.Operation) async throws {
        guard !center.isRunning(target: t.id) else { throw CommandError.notAvailable(L10n.tr("Na tym celu trwa już wdrożenie")) }
        let s = try await session(for: t)
        let p = DeployPipeline(target: t, operation: operation, plan: DeployPlan(owner: DeployPipeline.defaultOwner()), session: s, history: history)
        center.add(p)
        ProCDeployWindows.showConsole(self)
        await p.run()
    }

    /// Ścieżka lokalna pliku z komunikatu kompilatora (względna wobec repo na serwerze = względna wobec repo na Macu).
    func localURL(for m: BuildMessage, target t: PelikanSSHTarget) -> URL? {
        guard let file = m.file, let repo = repository,
              let rel = BuildMessageParser.projectRelativePath(file, makeDirectory: t.sourceDirectory, remoteRoot: t.effectiveWorkingCopy) else { return nil }
        return repo.appendingPathComponent(rel)
    }

    func open(_ m: BuildMessage, target t: PelikanSSHTarget) {
        guard let url = localURL(for: m, target: t), let d = try? workspace.openFile(url) else { NSSound.beep(); return }
        let o = ProgramCompiler.offset(line: m.line ?? 1, column: m.column ?? 1, in: d.text)
        d.selectedRange = o..<o
        ToolWindowController.showMainWindow()
    }

    /// Ręczne zdjęcie blokady: pokazuje właściciela, pyta o potwierdzenie (PROD — nazwa celu).
    func releaseLock(_ t: PelikanSSHTarget, info: [String]) async -> String? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Zdjąć blokadę wdrożenia na celu „\(t.name)”?")
        alert.informativeText = (info.isEmpty ? L10n.tr("Brak informacji o właścicielu blokady.") : info.joined(separator: "\n"))
            + "\n\n" + L10n.tr("Zdejmij tylko wtedy, gdy masz pewność, że nikt teraz nie wdraża.")
        alert.addButton(withTitle: L10n.tr("Zdejmij blokadę"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard await ProductionConfirmation.confirm(t, operation: L10n.tr("zdjęcie blokady"), ask: SSHTargetPrompts.askTargetName) else {
            return L10n.tr("Nie potwierdzono nazwy celu PROD")
        }
        do {
            try await DeployPipeline.forceReleaseLock(t, session: try await session(for: t))
            return L10n.tr("Blokada zdjęta")
        } catch { return SSHTargetTester.describe(error) }
    }
}

/// Okna wdrożeń.
@MainActor
enum ProCDeployWindows {
    static func showConsole(_ model: ProCDeployModel) {
        ToolWindowController.show(key: "procConsole", title: L10n.tr("Konsola wdrożenia"), size: NSSize(width: 1000, height: 620)) {
            DeployConsoleView(model: model)
        }
    }

    /// Wdrożenie i wycofanie na wskazany cel: inny cel niż w otwartym narzędziu — nowa zawartość; bez celu — przywołanie.
    static func showStart(_ model: ProCDeployModel, target: String?) {
        ToolWindowController.show(key: "procDeploy", for: target, title: L10n.tr("Wdrożenie"), size: NSSize(width: 760, height: 560)) {
            DeployStartView(model: model, selection: model.target(named: target)?.id ?? model.store.targets.first?.id)
        }
    }

    static func showRollback(_ model: ProCDeployModel, target: String?) {
        ToolWindowController.show(key: "procRollback", for: target, title: L10n.tr("Wycofanie binarki"), size: NSSize(width: 620, height: 460)) {
            RollbackView(model: model, selection: model.target(named: target)?.id ?? model.store.targets.first?.id)
        }
    }

    static func showHistory(_ model: ProCDeployModel) {
        ToolWindowController.show(key: "procHistory", title: L10n.tr("Historia wdrożeń"), size: NSSize(width: 980, height: 560)) {
            DeployHistoryView(model: model)
        }
    }

    static func showGitStatus(_ model: ProCDeployModel) {
        ToolWindowController.show(key: "procGit", title: L10n.tr("Stan git i wdrożeń"), size: NSSize(width: 760, height: 480)) {
            GitDeployStatusView(model: model)
        }
    }
}

/// Wybór celu i podsumowanie przed startem (commit serwer → remote, commity, pliki, ostrzeżenia).
struct DeployStartView: View {
    let model: ProCDeployModel
    @State var selection: UUID?
    @State private var summary: DeploySummary?
    @State private var loading = false
    @State private var message: String?

    private var target: PelikanSSHTarget? { selection.flatMap(model.store.target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker(L10n.tr("Cel"), selection: $selection) {
                    ForEach(model.store.targets) { t in Text("\(t.name) · \(t.environment.rawValue)").tag(UUID?.some(t.id)) }
                }
                .frame(maxWidth: 380)
                if let t = target { Text(t.environment.rawValue).bold().foregroundStyle(t.environment.color) }
                Spacer()
                Button(L10n.tr("Odśwież podsumowanie")) { Task { await load() } }.disabled(target == nil || loading)
            }
            Text(model.repository.map { L10n.tr("Lokalne repo: \($0.path)") } ?? L10n.tr("Brak otwartego projektu — bez lokalnego repo"))
                .font(.uiSecondary).foregroundStyle(.secondary)
            if loading { ProgressView().controlSize(.small) }
            if let s = summary {
                GroupBox(L10n.tr("Podsumowanie")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("Na serwerze: \(s.serverHead.map { String($0.prefix(12)) } ?? "?")  →  remote: \(s.remoteHead.map { String($0.prefix(12)) } ?? "?")"))
                            .font(.code)
                        if s.isUpToDate { Text(L10n.tr("Serwer ma już ten commit — wdrożenie przebuduje i zainstaluje binarki")).font(.uiSecondary) }
                        ScrollView {
                            Text((s.commits + (s.diffStat.isEmpty ? [] : ["", s.diffStat])).joined(separator: "\n"))
                                .font(.code).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120)
                        ForEach(s.warnings, id: \.self) { w in Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.uiSecondary) }
                    }
                }
            }
            if let message { Text(message).foregroundStyle(.red).font(.uiSecondary) }
            Spacer()
            HStack {
                Spacer()
                Button(L10n.tr("Wdróż")) { Task { await deploy() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(target == nil || summary == nil || loading)
            }
        }
        .padding(14)
        .frame(minWidth: 680, minHeight: 460)
        .toolTask(id: selection) { await load() }
    }

    private func load() async {
        guard let t = target else { return }
        loading = true
        message = nil
        defer { loading = false }
        do {
            let s = try await model.session(for: t)
            summary = await DeploySummary.prepare(target: t, session: s, repo: model.repository, history: model.history, uatTargets: model.uatSiblings(of: t))
        } catch {
            summary = nil
            message = SSHTargetTester.describe(error)
        }
    }

    private func deploy() async {
        guard let t = target else { return }
        let errors = t.validationErrors
        guard errors.isEmpty else { message = errors.joined(separator: "\n"); return }
        guard await ProductionConfirmation.confirm(t, operation: L10n.tr("wdrożenie"), ask: SSHTargetPrompts.askTargetName) else {
            message = L10n.tr("Nie potwierdzono nazwy celu PROD")
            return
        }
        ToolWindowController.close(key: "procDeploy")
        do { try await model.start(t, operation: .deploy) } catch { NSAlert(error: error).runModal() }
    }
}

/// Konsola: kroki ze statusem i czasem, wyjście z kolorowaniem, filtr błędów, klikalne komunikaty, Stop, zapis logu.
struct DeployConsoleView: View {
    let model: ProCDeployModel
    @State private var errorsOnly = false
    @State private var lockMessage: String?

    var body: some View {
        let center = model.center
        VStack(spacing: 6) {
            HStack {
                Picker(L10n.tr("Wdrożenie"), selection: Binding(get: { center.selected?.id }, set: { center.selectedID = $0 })) {
                    ForEach(center.pipelines) { p in Text("\(p.target.name) · \(p.record.started.formatted(date: .omitted, time: .standard))").tag(String?.some(p.id)) }
                }
                .frame(maxWidth: 380)
                Toggle(L10n.tr("Tylko błędy i ostrzeżenia"), isOn: $errorsOnly)
                Spacer()
                if let p = center.selected {
                    if [.locked, .staleLock].contains(p.outcome) {
                        Button(L10n.tr("Zdejmij blokadę…")) {
                            Task { lockMessage = await model.releaseLock(p.target, info: p.progress.lockInfo) }
                        }
                    }
                    Button(L10n.tr("Zapisz log…")) { save(p) }
                    Button(L10n.tr("Stop")) { p.stop() }.disabled(!p.running || p.stopRequested).keyboardShortcut(".", modifiers: .command)
                }
            }
            if let p = center.selected {
                DeployRunView(model: model, pipeline: p, errorsOnly: errorsOnly)
            } else {
                Text(L10n.tr("Brak wdrożeń w tej sesji")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let lockMessage { Text(lockMessage).font(.uiSecondary) }
        }
        .padding(10)
        .frame(minWidth: 820, minHeight: 460)
    }

    private func save(_ p: DeployPipeline) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "wdrozenie-\(p.id).log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(p.progress.logText.utf8).write(to: url, options: .atomic) } catch { model.workspace.ui?.showError(error.localizedDescription) }
    }
}

struct DeployRunView: View {
    let model: ProCDeployModel
    let pipeline: DeployPipeline
    let errorsOnly: Bool

    var body: some View {
        let progress = pipeline.progress
        HSplitView {
            List(progress.steps) { s in
                HStack {
                    Image(systemName: icon(s.status)).foregroundStyle(color(s.status))
                    Text(s.title)
                    Spacer()
                    if let d = s.duration { Text(String(format: "%.1f s", d)).font(.uiSecondary).monospacedDigit().foregroundStyle(.secondary) }
                }
            }
            .frame(minWidth: 220, maxWidth: 300)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(pipeline.target.name) · \(pipeline.target.environment.rawValue)").bold().foregroundStyle(pipeline.target.environment.color)
                    if pipeline.running { ProgressView().controlSize(.small) }
                    Spacer()
                    if let o = pipeline.outcome { Text(o.title).foregroundStyle(o == .success ? .green : .red) }
                    if progress.errorCount > 0 { Text(L10n.tr("Błędy kompilacji: \(progress.errorCount)")).foregroundStyle(.red) }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visible(progress)) { line in
                                row(line, message: progress.messageLines[line.id]).id(line.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Przyklejenie do końca w trakcie wdrożenia.
                    .onChange(of: progress.lines.count) { _, n in
                        if pipeline.running, n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func visible(_ p: DeployProgress) -> [DeployConsoleLine] {
        guard errorsOnly else { return p.lines }
        return p.lines.filter { $0.kind == .step || $0.kind == .error || p.messageLines[$0.id] != nil }
    }

    @ViewBuilder private func row(_ line: DeployConsoleLine, message: BuildMessage?) -> some View {
        switch line.kind {
        case .step:
            Text(line.text).font(.uiHeadline).padding(.top, 6).padding(.bottom, 2)
        case .info:
            Text(line.text).font(.code).foregroundStyle(.secondary)
        case .output, .error:
            let text = Text(line.text).font(.code)
                .foregroundStyle(message.map { $0.isError ? Color.red : Color.orange } ?? (line.kind == .error ? .red : .primary))
            if let message {
                // Przycisk zamiast gestu — dostępny dla VoiceOver i klawiatury (R4-15).
                Button { model.open(message, target: pipeline.target) } label: { text.underline() }
                    .buttonStyle(.plain)
                    .help(L10n.tr("Otwórz plik w miejscu błędu"))
            } else {
                text.textSelection(.enabled)
            }
        }
    }

    private func icon(_ s: DeployStep.Status) -> String {
        switch s {
        case .running: "circle.dotted"
        case .ok: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .stopped: "stop.circle.fill"
        }
    }

    private func color(_ s: DeployStep.Status) -> Color {
        switch s {
        case .running: .blue
        case .ok: .green
        case .failed: .red
        case .stopped: .orange
        }
    }
}

/// Wycofanie: binarka, źródło (.prev albo kopia z listy z serwera), potwierdzenie.
struct RollbackView: View {
    let model: ProCDeployModel
    @State var selection: UUID?
    @State private var binary = ""
    @State private var backups: [BackupEntry] = []
    @State private var source: String = ".prev"
    @State private var message: String?

    private var target: PelikanSSHTarget? { selection.flatMap(model.store.target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L10n.tr("Cel"), selection: $selection) {
                ForEach(model.store.targets) { t in Text("\(t.name) · \(t.environment.rawValue)").tag(UUID?.some(t.id)) }
            }
            if let t = target {
                Picker(L10n.tr("Binarka"), selection: $binary) {
                    ForEach(t.effectiveBinaries, id: \.self) { Text($0).tag($0) }
                }
                Picker(L10n.tr("Źródło"), selection: $source) {
                    Text(L10n.tr("Poprzednia wersja (.prev)")).tag(".prev")
                    ForEach(backups.filter { $0.binary == binary }) { b in Text("\(b.timestamp) · \(b.commit)\(b.compression == .none ? "" : " · \(b.compression.rawValue)")").tag(b.fileName) }
                }
            }
            if let message { Text(message).font(.uiSecondary).foregroundStyle(.red) }
            Spacer()
            HStack {
                Button(L10n.tr("Odśwież kopie")) { Task { await load() } }
                Spacer()
                Button(L10n.tr("Wycofaj")) { Task { await rollback() } }.disabled(target == nil || binary.isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 300)
        .toolTask(id: selection) { await load() }
    }

    private func load() async {
        guard let t = target else { return }
        if !t.effectiveBinaries.contains(binary) { binary = t.effectiveBinaries.first ?? "" }
        do { backups = try await DeployPipeline.backups(t, session: try await model.session(for: t)); message = nil } catch {
            backups = []
            message = SSHTargetTester.describe(error)
        }
    }

    private func rollback() async {
        guard let t = target else { return }
        let alert = NSAlert()
        alert.messageText = L10n.tr("Wycofać binarkę \(binary) na celu „\(t.name)”?")
        alert.informativeText = source == ".prev" ? L10n.tr("Bieżąca binarka zamieni się miejscami z .prev.") : L10n.tr("Binarka zostanie zastąpiona kopią \(source); bieżąca trafi do .prev.")
        alert.addButton(withTitle: L10n.tr("Wycofaj"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard await ProductionConfirmation.confirm(t, operation: L10n.tr("wycofanie binarki"), ask: SSHTargetPrompts.askTargetName) else {
            message = L10n.tr("Nie potwierdzono nazwy celu PROD")
            return
        }
        ToolWindowController.close(key: "procRollback")
        let src: RollbackSource = source == ".prev" ? .previous : .backup(source)
        do { try await model.start(t, operation: .rollback(binary: binary, source: src)) } catch { NSAlert(error: error).runModal() }
    }
}

/// Historia lokalna (z logami) i z serwera wybranego celu.
struct DeployHistoryView: View {
    let model: ProCDeployModel
    @State private var selection: DeployRecord.ID?
    @State private var serverTarget: UUID?
    @State private var server: [ServerHistoryEntry] = []
    @State private var message: String?

    var body: some View {
        VSplitView {
            VStack(alignment: .leading) {
                Table(model.history.records, selection: $selection) {
                    TableColumn(L10n.tr("Kiedy")) { r in Text(r.started.formatted(date: .numeric, time: .shortened)) }.width(130)
                    TableColumn(L10n.tr("Cel")) { r in Text("\(r.targetName) · \(r.environment.rawValue)").foregroundStyle(r.environment.color) }
                    TableColumn(L10n.tr("Rodzaj")) { r in Text(r.kind == .deploy ? L10n.tr("wdrożenie") : L10n.tr("wycofanie")) }.width(90)
                    TableColumn(L10n.tr("Kto"), value: \.owner)
                    TableColumn(L10n.tr("Commit przed → po")) { r in
                        Text("\(r.headBefore.map { String($0.prefix(8)) } ?? "—") → \(r.headAfter.map { String($0.prefix(8)) } ?? "—")").font(.code)
                    }
                    TableColumn(L10n.tr("Wynik")) { r in Text(r.outcome?.title ?? "—").foregroundStyle(r.outcome == .success ? .green : .red) }
                }
                ScrollView {
                    Text(selection.flatMap { model.history.log($0) } ?? "").font(.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120)
            }
            VStack(alignment: .leading) {
                HStack {
                    Picker(L10n.tr("Historia z serwera"), selection: $serverTarget) {
                        ForEach(model.store.targets) { t in Text(t.name).tag(UUID?.some(t.id)) }
                    }
                    .frame(maxWidth: 360)
                    Button(L10n.tr("Pobierz")) { Task { await loadServer() } }.disabled(serverTarget == nil)
                    if let message { Text(message).font(.uiSecondary).foregroundStyle(.red) }
                }
                Table(server) {
                    TableColumn(L10n.tr("Czas"), value: \.timestamp).width(130)
                    TableColumn(L10n.tr("Rodzaj"), value: \.kind).width(80)
                    TableColumn(L10n.tr("Kto"), value: \.owner)
                    TableColumn(L10n.tr("Przed → po")) { e in Text("\(e.headBefore.prefix(8)) → \(e.headAfter.prefix(8))").font(.code) }
                    TableColumn(L10n.tr("Wynik")) { e in Text(e.succeeded ? L10n.tr("powodzenie") : "\(e.step) \(e.code)").foregroundStyle(e.succeeded ? .green : .red) }
                }
            }
            .frame(minHeight: 160)
        }
        .padding(10)
        .frame(minWidth: 860, minHeight: 480)
    }

    private func loadServer() async {
        guard let t = serverTarget.flatMap(model.store.target) else { return }
        do { server = try await DeployPipeline.serverHistory(t, session: try await model.session(for: t)); message = nil } catch {
            message = SSHTargetTester.describe(error)
        }
    }
}

/// „Gdzie co jest”: lokalne repo i commit wdrożony na każdym celu (historia + `git rev-parse HEAD` na serwerze).
struct GitDeployStatusView: View {
    let model: ProCDeployModel
    @State private var local: LocalGitStatus?
    @State private var serverHeads: [UUID: String] = [:]
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.repository?.path ?? L10n.tr("Brak otwartego projektu")).font(.uiSecondary).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("git fetch i odśwież")) { Task { await load(fetch: true) } }.disabled(model.repository == nil)
                Button(L10n.tr("Commity na serwerach")) { Task { await loadServers() } }
            }
            if let s = local {
                Text(L10n.tr("Gałąź: \(s.branch) · niezatwierdzone: \(s.uncommitted.count) · niewypchnięte: \(s.ahead.map(String.init) ?? "?") · do pobrania: \(s.behind.map(String.init) ?? "?")"))
                ForEach(s.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.uiSecondary) }
            }
            Table(model.store.targets) {
                TableColumn(L10n.tr("Cel")) { t in Text("\(t.name) · \(t.environment.rawValue)").foregroundStyle(t.environment.color) }
                TableColumn(L10n.tr("Ostatnie wdrożenie (historia)")) { t in
                    Text(model.history.lastSuccess(target: t.id)?.headAfter.map { String($0.prefix(12)) } ?? "—").font(.code)
                }
                TableColumn(L10n.tr("HEAD na serwerze")) { t in Text(serverHeads[t.id].map { String($0.prefix(12)) } ?? "—").font(.code) }
                TableColumn(L10n.tr("HEAD zdalnej gałęzi")) { t in Text(local?.remoteHead.map { String($0.prefix(12)) } ?? "—").font(.code) }
            }
            if let message { Text(message).font(.uiSecondary).foregroundStyle(.red) }
        }
        .padding(12)
        .frame(minWidth: 680, minHeight: 360)
        .toolTask(id: 0) { await load(fetch: false) }
    }

    private func load(fetch: Bool) async {
        guard let repo = model.repository else { return }
        let t = model.store.targets.first
        let remote = t?.remote ?? "origin", branch = t?.branch ?? "MASTER"
        let r: Result<LocalGitStatus, any Error> = await Task.detached {
            Result {
                if fetch { try LocalGit.fetch(repo: repo, remote: remote) }
                return try LocalGit.status(repo: repo, remote: remote, branch: branch)
            }
        }.value
        switch r {
        case .success(let s): local = s; message = nil
        case .failure(let e): message = e.localizedDescription
        }
    }

    private func loadServers() async {
        for t in model.store.targets {
            guard let s = try? await model.session(for: t) else { continue }
            let head: String? = await Task.detached {
                guard let r = try? s.run(DeployScripts.serverHeadCommand(t), timeout: 60), r.status == 0 else { return nil }
                return String(decoding: r.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }.value
            serverHeads[t.id] = head
        }
    }
}
