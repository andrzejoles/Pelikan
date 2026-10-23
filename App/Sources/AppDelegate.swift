import AppKit
import PelikanDB
import PelikanODPI
import PelikanThin
import Sparkle
import PelikanSQL
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, UIServices {
    let workspace: Workspace
    private var mainWindow: MainWindowController?
    private var menuBuilder: MenuBuilder?
    private var palette: CommandPalette?
    private let prompts = ConnectionPrompts()
    private var connectionCheck: Timer?
    private var keyMonitor: Any?
    /// Aktualizacje Sparkle (kanał releases/latest/download/appcast.xml, podpis EdDSA). W kompilacji Debug wyłączone.
    #if DEBUG
    let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    #else
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif
    private var menuToken: ObservationToken?
    private var appearanceToken: ObservationToken?

    override init() {
        // Katalog danych: ~/Library/Application Support/<nazwa>; PELIKAN_DATA_DIR nadpisuje (testy interfejsu).
        let env = ProcessInfo.processInfo.environment
        let name = Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan"
        let dir = env["PELIKAN_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        workspace = Workspace(dataDirectory: dir, secrets: KeychainSecretStore())
        super.init()
        workspace.sessions.setDriver(ODPIDriver(libraryDirectory: workspace.settings.instantClientDirectory))
        workspace.sessions.setDriver(ThinDriver())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        workspace.ui = self
        workspace.sessions.prompter = prompts
        let builder = MenuBuilder(workspace: workspace)
        NSApp.mainMenu = builder.build()
        menuBuilder = builder
        // Wygląd z Preferencji (jak system / jasny / ciemny).
        appearanceToken = trackChanges { [weak self] in
            guard let self else { return }
            switch self.workspace.settings.appearance {
            case .system: NSApp.appearance = nil
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
        // Zmiana profilu albo własnych skrótów (Preferencje › Klawiatura) — menu z nowymi skrótami.
        menuToken = trackChanges { [weak self] in
            guard let self else { return }
            _ = self.workspace.keymap.bindings.count
            NSApp.mainMenu = self.menuBuilder?.build()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak builder] event in
            nonisolated(unsafe) let e = event   // monitor lokalny działa na wątku głównym
            let handled = MainActor.assumeIsolated { builder?.handleKeyDown(e) == true }
            return handled ? nil : event
        }
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

    @objc func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates(sender)
    }

    @objc func showPreferences(_ sender: Any?) {
        PreferencesWindowController.show(workspace: workspace)
    }

    /// Pliki otwierane z Findera, Docka albo `open -a` (typy z Info.plist).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do { try workspace.openFile(url) } catch { showError(error.localizedDescription) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let open = workspace.documents.filter(\.transactionOpen)
        let modified = workspace.documents.filter { $0.isModified && ($0.fileURL != nil || (workspace.settings.confirmSaveNewWindows && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
        if !modified.isEmpty {
            // Niezapisane okna: pytanie jak przy zamykaniu każdego okna (Zapisz / Nie zapisuj / Anuluj).
            Task { @MainActor in
                do {
                    for d in modified {
                        workspace.activate(d.id)
                        try await workspace.invoke("file.close")
                    }
                    NSApp.reply(toApplicationShouldTerminate: true)
                } catch {
                    NSApp.reply(toApplicationShouldTerminate: false)
                }
            }
            return .terminateLater
        }
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

    /// Procesy ssh tuneli kończą się razem z aplikacją.
    func applicationWillTerminate(_ notification: Notification) {
        workspace.sessions.tunnels.closeAll()
    }

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
        let view = LogonView(workspace: workspace) { [weak self] in
            if let sheet { window.endSheet(sheet) }
            self?.mainWindow?.documentArea.focusActiveDocument()
        }
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
                self.mainWindow?.documentArea.focusActiveDocument()
                cont.resume(returning: values)
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            sheet = w
            window.beginSheet(w)
        }
    }

    func copyToClipboard(_ text: String, html: String?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if let html { pb.setString(html, forType: .html) }
    }

    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool {
        guard let window = mainWindow?.window else { return false }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-") + "." + fileExtension
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]
        panel.canCreateDirectories = true
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    func chooseFilesToOpen() async -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["sql", "pck", "pks", "pkb", "spc", "bdy", "fnc", "prc", "trg", "typ", "tps", "tpb", "tst", "txt"]
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        guard let window = mainWindow?.window else { return panel.runModal() == .OK ? panel.urls : [] }
        return await panel.beginSheetModal(for: window) == .OK ? panel.urls : []
    }

    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-") + "." + fileExtension
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard let window = mainWindow?.window else { return panel.runModal() == .OK ? panel.url : nil }
        return await panel.beginSheetModal(for: window) == .OK ? panel.url : nil
    }

    func showLargeDataEditor(_ model: LargeDataModel) {
        LargeDataEditorController.show(model, workspace: workspace, relativeTo: mainWindow?.window)
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
