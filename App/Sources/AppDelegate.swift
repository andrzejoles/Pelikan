import AppKit
import PelikanWorkspace

final class AppDelegate: NSObject, NSApplicationDelegate, UIServices {
    let workspace = Workspace(profile: .plsqlDeveloper)
    private var mainWindow: MainWindowController?
    private var menuBuilder: MenuBuilder?
    private var palette: CommandPalette?

    func applicationDidFinishLaunching(_ notification: Notification) {
        workspace.ui = self
        let builder = MenuBuilder(workspace: workspace)
        NSApp.mainMenu = builder.build()
        menuBuilder = builder
        let window = MainWindowController(workspace: workspace)
        window.showWindow(nil)
        mainWindow = window
        // Pierwsze okno SQL jak we wzorcu po zalogowaniu (bez połączenia do Etapu 1).
        if workspace.documents.isEmpty {
            workspace.perform("file.new.sql")
        }
        NSApp.activate()
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
