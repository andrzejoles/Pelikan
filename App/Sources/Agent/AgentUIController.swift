import AppKit
import PelikanAgent
import PelikanBridgeKit
import PelikanLog
import PelikanWorkspace
import SwiftTerm
import SwiftUI

/// Agenci AI w aplikacji (PROMPT §7.1): uruchamianie CLI w panelu agenta, okno zgody, macierz uprawnień sesji,
/// cofanie sesji i dziennik. Serwer gniazda działa tylko, gdy aplikacja ma katalog danych.
final class AgentUIController: ApprovalPresenter {
    let workspace: Workspace
    let controller: AgentController
    weak var mainWindow: MainWindowController?
    let pane: AgentPane
    private var approvalChain: Task<Void, Never>?
    private var logWindow: AgentLogWindowController?
    private var profilesToken: ObservationToken?
    private var registeredProfiles: [AgentProfile] = []
    private let runDirectory: URL

    init?(workspace: Workspace) {
        guard let data = workspace.dataDirectory else { return nil }
        self.workspace = workspace
        runDirectory = data.appendingPathComponent("run", isDirectory: true)
        controller = AgentController(workspace: workspace, socketURL: runDirectory.appendingPathComponent("agent.sock"),
                                     logDirectory: data.appendingPathComponent("agent-logs", isDirectory: true))
        pane = AgentPane(controller: controller)
        controller.approvals = self
        pane.onUndo = { [weak self] id in self?.undoSession(id) }
        pane.onClose = { [weak self] id in self?.endSession(id) }
        pane.onShowLog = { [weak self] in self?.showLog() }
        workspace.register(commands())
        // Lista CLI jest konfigurowalna (Preferencje › Agenci) — komendy uruchamiania nadążają za nią.
        profilesToken = trackChanges { [weak self] in
            guard let self else { return }
            let profiles = self.workspace.settings.agent.profiles
            if profiles != self.registeredProfiles { self.workspace.register(self.launchCommands(profiles)) }
        }
        do {
            try controller.start()
        } catch {
            Log.agent.error("Serwer agentów nie wystartował: \(error)")
        }
    }

    func stop() {
        pane.terminateAll()
        controller.stop()
    }

    var bridgePath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/pelikan-mcp").path
    }

    // MARK: Komendy (tylko dla użytkownika — poziom agenta „Brak”)

    private static var submenu: String { L10n.tr("Agent AI") }

    private func launchCommands(_ profiles: [AgentProfile]) -> [Command] {
        registeredProfiles = profiles
        return profiles.map { profile in
            Command(CommandDescriptor(
                id: CommandID(rawValue: "agent.launch.\(profile.id)"), title: L10n.tr("Uruchom \(profile.name)"), category: .tools,
                submenu: Self.submenu, agent: .none, effect: .external,
                summary: L10n.tr("Uruchamia \(profile.name) w panelu agenta z serwerem MCP Pelikana tylko dla tej sesji; najpierw macierz uprawnień sesji."),
                feature: "AI-PANEL-001")
            ) { [weak self] _ in
                try await self?.launch(profile)
                return .ok
            }
        }
    }

    private func commands() -> [Command] {
        var list = launchCommands(workspace.settings.agent.profiles)
        list.append(Command(CommandDescriptor(
            id: "agent.togglePane", title: L10n.tr("Panel agenta"), category: .view,
            agent: .none, effect: .uiState, summary: L10n.tr("Pokazuje lub ukrywa panel agenta z terminalem i aktywnością."),
            feature: "AI-PANEL-002")
        ) { [weak self] _ in
            self?.togglePane()
            return .ok
        })
        list.append(Command(CommandDescriptor(
            id: "agent.undoSession", title: L10n.tr("Cofnij sesję agenta…"), category: .tools, submenu: Self.submenu,
            agent: .none, effect: .modifiesEditor,
            summary: L10n.tr("Cofa zmiany wybranej sesji agenta: tekst okien, okna otwarte przez agenta; z podglądem i wykrywaniem konfliktów."),
            feature: "AI-SEC-008")
        ) { [weak self] _ in
            guard let self, let id = self.pane.selectedSessionID else { throw CommandError.notAvailable(L10n.tr("Brak sesji agenta")) }
            self.undoSession(id)
            return .ok
        })
        list.append(Command(CommandDescriptor(
            id: "agent.endSession", title: L10n.tr("Zakończ sesję agenta"), category: .tools, submenu: Self.submenu,
            agent: .none, effect: .external,
            summary: L10n.tr("Kończy proces CLI, unieważnia token sesji, wycofuje niezatwierdzone zmiany agenta i zamyka jego sesje bazy."),
            feature: "AI-PANEL-001")
        ) { [weak self] _ in
            if let self, let id = self.pane.selectedSessionID { self.endSession(id) }
            return .ok
        })
        list.append(Command(CommandDescriptor(
            id: "agent.showLog", title: L10n.tr("Dziennik agentów…"), category: .tools, submenu: Self.submenu,
            agent: .none, effect: .uiState, summary: L10n.tr("Przeglądarka dziennika wywołań narzędzi agentów (JSONL)."),
            feature: "AI-LOG-001")
        ) { [weak self] _ in
            self?.showLog()
            return .ok
        })
        return list
    }

    // MARK: Uruchamianie

    func launch(_ profile: AgentProfile) async throws {
        guard FileManager.default.isExecutableFile(atPath: bridgePath) else {
            throw CommandError.notAvailable(L10n.tr("Brak mostu pelikan-mcp w pakiecie aplikacji."))
        }
        guard let executable = await Self.which(profile.executable) else {
            throw CommandError.notAvailable(L10n.tr("Nie znaleziono polecenia „\(profile.executable)” w PATH powłoki logowania."))
        }
        guard let overrides = await askPermissions(profile) else { throw CommandError.cancelledByUser }
        if profile.flavor == .antigravity { try await ensureAntigravityRegistration(executable: executable) }
        let settings = workspace.settings.agent

        // Katalog roboczy: folder pliku aktywnego okna (projekt) albo katalog tymczasowy sesji.
        let projectDirectory = workspace.activeDocument?.fileURL?.deletingLastPathComponent().path
        let (session, token) = controller.createSession(profile: profile, directory: projectDirectory ?? "", accessOverrides: overrides)
        let sessionDir = runDirectory.appendingPathComponent("session-\(session.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directory = projectDirectory ?? sessionDir.path
        let spec = AgentLauncher.spec(profile: profile, bridge: bridgePath, socket: controller.socketURL.path, token: token,
                                      directory: directory, strict: settings.strictMode, sessionDirectory: sessionDir.path,
                                      executable: executable)
        for (path, contents) in spec.files {
            try Data(contents.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
            chmod(path, 0o600)
        }

        var env = ProcessInfo.processInfo.environment
        // Znaczniki sesji CLI, z której ewentualnie uruchomiono aplikację, nie mogą przeciekać do agenta.
        for key in env.keys where key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") || key.hasPrefix("CODEX_") || key == Bridge.tokenVariable {
            env.removeValue(forKey: key)
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        for (k, v) in spec.environment { env[k] = v }
        let terminal = pane.addSession(session: session, warnings: spec.warnings, command: spec.displayCommand) { [weak self] in
            self?.controller.closeSession(session.id)
            try? FileManager.default.removeItem(at: sessionDir)
        }
        showPane()
        terminal.startProcess(executable: spec.shell, args: spec.shellArguments, environment: env.map { "\($0.key)=\($0.value)" },
                              execName: nil, currentDirectory: directory)
        session.cliPID = terminal.process.shellPid
        terminal.window?.makeFirstResponder(terminal)
    }

    /// Ścieżka polecenia w PATH powłoki logowania użytkownika.
    static func which(_ name: String) async -> String? {
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || "-_./".contains($0) }) else { return nil }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-l", "-c", "command -v \(name)"]
        // Wyjście czytane równolegle z czekaniem; limit — powłoka logowania, która utknęła (np. pytanie w profilu).
        guard let r = try? await p.runCapturingOutput(timeout: 15), !r.timedOut, r.status == 0 else { return nil }
        let path = String(decoding: r.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }

    /// Antigravity nie ma konfiguracji MCP na sesję — jednorazowa rejestracja tylko za zgodą (PROMPT §7.1, §13).
    private func ensureAntigravityRegistration(executable: String) async throws {
        let bridge = bridgePath
        let lister = Process()
        lister.executableURL = URL(fileURLWithPath: executable)
        lister.arguments = ["mcp", "list"]
        let listed = try? await lister.runCapturingOutput(includeErrors: true, timeout: 30)
        let list = listed.map { String(decoding: $0.output, as: UTF8.self) } ?? ""
        if list.contains(bridge) { return }
        let answer = await workspace.ui?.ask(
            L10n.tr("Zarejestrować serwer MCP w Antigravity?"),
            message: L10n.tr("Antigravity nie pozwala podać serwera MCP tylko dla jednej sesji. Pelikan doda na stałe serwer „pelikan” (agy mcp add). Bez tokenu sesji most odrzuca każde połączenie, więc poza sesjami uruchomionymi z Pelikana serwer jest bezużyteczny."),
            buttons: [L10n.tr("Zarejestruj"), L10n.tr("Anuluj")])
        guard answer == 0 else { throw CommandError.cancelledByUser }
        let profile = workspace.settings.agent.profiles.first { $0.flavor == .antigravity } ?? AgentProfile.builtIn[3]
        let args = AgentLauncher.spec(profile: profile, bridge: bridge, socket: controller.socketURL.path, token: "", directory: "/",
                                      strict: true, sessionDirectory: "/").persistentRegistration ?? []
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        var status: Int32 = -1
        if (try? p.run()) != nil, await p.waitForExitAsync(timeout: 60) { status = p.terminationStatus }
        guard status == 0 else { throw CommandError.notAvailable(L10n.tr("agy mcp add zakończył się błędem (\(status))")) }
    }

    // MARK: Macierz uprawnień

    private func askPermissions(_ profile: AgentProfile) async -> [CommandID: AgentAccess]? {
        let rows = PermissionMatrix.rows(registry: workspace.registry, settings: workspace.settings.agent)
        return await presentSheet { finish in
            PermissionMatrixView(profileName: profile.name, rows: rows) { finish($0) }
        } ?? nil
    }

    /// Arkusz SwiftUI na oknie głównym z wynikiem przekazanym przez `finish` (nil — brak okna).
    private func presentSheet<V: View, R: Sendable>(_ content: (@escaping (R) -> Void) -> V) async -> R? {
        guard let window = mainWindow?.window else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<R?, Never>) in
            var sheet: NSWindow?
            var done = false
            let view = content { result in
                guard !done else { return }
                done = true
                if let sheet { window.endSheet(sheet) }
                sheet = nil  // zrywa cykl okno → widok → domknięcie → okno
                cont.resume(returning: result)
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view.interfaceFont()))
            sheet = w
            window.beginSheet(w)
        }
    }

    // MARK: Sesje

    func endSession(_ id: String) {
        pane.terminateSession(id)
        controller.closeSession(id)
        if !pane.hasRunningSessions(excluding: id) { mainWindow?.setAgentPane(visible: false) }
    }

    func undoSession(_ id: String) {
        let edits = workspace.agentEdits.filter { $0.session == id }
        let code = workspace.agentCodeChanges.filter { $0.session == id }
        let objects = Set(code.map { "\($0.object.type.rawValue) \($0.object.qualifiedName)" }).sorted()
        let conflicts = edits.compactMap { e -> String? in
            guard let d = workspace.documents.first(where: { $0.id == e.document }), d.text != e.after else { return nil }
            return d.fullTitle
        }
        Task {
            let alert = NSAlert()
            alert.messageText = L10n.tr("Cofnąć sesję agenta \(id)?")
            var info = L10n.tr("Zmiany okien: \(edits.count). Okna otwarte przez agenta zostaną zamknięte.")
            if !objects.isEmpty {
                info += "\n" + L10n.tr("Kod obiektów do przywrócenia (obiekty utworzone przez agenta zostaną usunięte): \(objects.joined(separator: ", "))")
            }
            info += "\n" + L10n.tr("Niezatwierdzone zmiany danych agenta zostaną wycofane (ROLLBACK). Zmian po COMMIT i DDL na tabelach nie da się cofnąć.")
            if !conflicts.isEmpty {
                info += "\n" + L10n.tr("Konflikty (okno zmienione później): \(Set(conflicts).sorted().joined(separator: ", "))")
            }
            alert.informativeText = info
            alert.addButton(withTitle: L10n.tr("Cofnij"))
            alert.addButton(withTitle: L10n.tr("Cofnij z wymuszeniem"))
            alert.addButton(withTitle: L10n.tr("Anuluj"))
            let response = await present(alert)
            let force: Bool
            switch response {
            case .alertFirstButtonReturn: force = false
            case .alertSecondButtonReturn: force = true
            default: return
            }
            // Konflikty kodu obiektów (zmienionych później przez kogoś innego) wychodzą dopiero przy porównaniu z bazą.
            let r = await workspace.undoAgentSession(id, force: force)
            var messages = [L10n.tr("Cofnięto zmian okien: \(r.editsUndone), przywrócono obiektów: \(r.objectsRestored)")]
            if r.rolledBack { messages.append(L10n.tr("Wycofano niezatwierdzone zmiany danych agenta.")) }
            if !r.conflicts.isEmpty { messages.append(L10n.tr("Pominięto (konflikty): \(r.conflicts.joined(separator: ", "))")) }
            messages += r.errors
            let done = NSAlert()
            done.alertStyle = .informational
            done.messageText = L10n.tr("Sesja agenta cofnięta")
            done.informativeText = messages.joined(separator: "\n")
            _ = await present(done)
        }
    }

    // MARK: Zatwierdzanie

    func requestApproval(_ request: ApprovalRequest) async -> Bool {
        // Kolejne prośby czekają, aż poprzednia zostanie rozpatrzona.
        let previous = approvalChain
        let task = Task<Bool, Never> {
            await previous?.value
            return await showApproval(request)
        }
        approvalChain = Task { _ = await task.value }
        return await task.value
    }

    private func showApproval(_ r: ApprovalRequest) async -> Bool {
        showPane()
        NSApp.requestUserAttention(.criticalRequest)
        return await presentSheet { finish in ApprovalView(request: r) { finish($0) } } ?? false
    }

    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window = mainWindow?.window, window.attachedSheet == nil else { return alert.runModal() }
        return await withCheckedContinuation { c in alert.beginSheetModal(for: window) { c.resume(returning: $0) } }
    }

    // MARK: Panel i dziennik

    func togglePane() {
        if mainWindow?.isAgentPaneVisible == true { mainWindow?.setAgentPane(visible: false) } else { showPane() }
    }

    func showPane() {
        mainWindow?.setAgentPane(visible: true)
    }

    func showLog() {
        if logWindow == nil { logWindow = AgentLogWindowController(directory: controller.logDirectory) }
        logWindow?.showWindow(nil)
        logWindow?.reload()
    }
}
