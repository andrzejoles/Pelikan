import AppKit
import PelikanDB
import PelikanODPI
import PelikanSQL
import PelikanWorkspace
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, UIServices {
    let workspace: Workspace
    private var mainWindow: MainWindowController?
    private var menuBuilder: MenuBuilder?
    private var palette: CommandPalette?
    private let prompts = ConnectionPrompts()
    private var connectionCheck: Timer?

    override init() {
        // Katalog danych: ~/Library/Application Support/<nazwa>; PELIKAN_DATA_DIR nadpisuje (testy interfejsu).
        let env = ProcessInfo.processInfo.environment
        let name = Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan"
        let dir = env["PELIKAN_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        workspace = Workspace(dataDirectory: dir, secrets: KeychainSecretStore())
        super.init()
        workspace.sessions.setDriver(ODPIDriver(libraryDirectory: workspace.settings.instantClientDirectory))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        workspace.ui = self
        workspace.sessions.prompter = prompts
        let builder = MenuBuilder(workspace: workspace)
        NSApp.mainMenu = builder.build()
        menuBuilder = builder
        let window = MainWindowController(workspace: workspace)
        window.showWindow(nil)
        mainWindow = window
        prompts.window = window.window
        // Pierwsze okno SQL jak we wzorcu po zalogowaniu (bez połączenia do Etapu 1).
        if workspace.documents.isEmpty {
            workspace.perform("file.new.sql")
        }
        NSApp.activate()
        startConnectionCheck()
        // Jak we wzorcu: okno logowania przy starcie (można anulować), chyba że są połączenia „Połącz przy starcie”.
        let auto = workspace.connections.connections.filter(\.connectOnStartup)
        if let first = auto.first {
            workspace.perform("connection.connectAsMain", CommandArguments(["connection": .string(first.id.uuidString)]))
        } else {
            showLogon()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let open = workspace.documents.filter(\.transactionOpen)
        guard !open.isEmpty else { return .terminateNow }
        Task { @MainActor in
            let answer = await ask(L10n.tr("Niezatwierdzone zmiany"),
                                   message: L10n.tr("Okna z otwartą transakcją: \(open.map(\.fullTitle).joined(separator: ", ")). Co zrobić przed zamknięciem?"),
                                   buttons: [L10n.tr("Zatwierdź (COMMIT)"), L10n.tr("Wycofaj (ROLLBACK)")])
            guard let answer else { NSApp.reply(toApplicationShouldTerminate: false); return }
            try? await workspace.endTransactions(of: open, commit: answer == 0)
            await workspace.sessions.disconnectAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: UIServices

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Nie udało się wykonać polecenia")
        alert.informativeText = message
        if let window = mainWindow?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func showCommandPalette() {
        if palette == nil { palette = CommandPalette(workspace: workspace) }
        palette?.show(relativeTo: mainWindow?.window)
    }

    /// Sprawdzanie połączeń co n s (UG 23.1 „Check connection”); utracone — komunikat o wycofanej transakcji.
    private func startConnectionCheck() {
        let interval = TimeInterval(max(15, workspace.settings.checkConnectionIntervalSeconds))
        connectionCheck = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let lost = await self.workspace.sessions.checkConnections()
                guard !lost.isEmpty else { return }
                let names = Set(lost.compactMap { self.workspace.connections.connection($0.connectionID)?.displayName })
                for d in self.workspace.documents where d.transactionOpen && lost.contains(where: { $0.connectionID == self.workspace.effectiveConnection(of: d) }) {
                    d.transactionOpen = false
                }
                self.showError(L10n.tr("Połączenie utracone: \(names.sorted().joined(separator: ", ")). Niezatwierdzone zmiany zostały wycofane przez serwer. Kolejne polecenie połączy się ponownie."))
            }
        }
    }

    func showConnectionEditor(connectionID: UUID?) {
        ConnectionEditorPresenter.present(workspace: workspace, connectionID: connectionID, in: mainWindow?.window)
    }

    func showLogon() {
        guard let window = mainWindow?.window else { return }
        var sheet: NSWindow?
        let view = LogonView(workspace: workspace) { if let sheet { window.endSheet(sheet) } }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = w
        window.beginSheet(w)
    }

    func askVariables(_ requests: [VariableRequest], document: PelikanWorkspace.Document) async -> [String: VariableValue]? {
        guard let window = mainWindow?.window else { return nil }
        let model = VariablesModel(requests: requests, workspace: workspace, document: document)
        return await withCheckedContinuation { cont in
            var sheet: NSWindow?
            var finished = false
            let view = VariablesView(model: model) { values in
                guard !finished else { return }
                finished = true
                if let sheet { window.endSheet(sheet) }
                cont.resume(returning: values)
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            sheet = w
            window.beginSheet(w)
        }
    }

    func ask(_ title: String, message: String, buttons: [String]) async -> Int? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for b in buttons { alert.addButton(withTitle: b) }
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return index < buttons.count ? index : nil
    }
}
