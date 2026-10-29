import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu: stan lewej kolumny i wybór z listy (D204).
@MainActor
final class SidebarUI: UIServices {
    var sidebar: Bool? = true
    var offered: [String] = []
    var choice: String?
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { nil }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { [:] }
    func copyToClipboard(_ text: String, html: String?) {}
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { true }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { nil }
    func chooseValue(_ title: String, values: [String]) async -> String? {
        offered = values
        return choice
    }
    func isSidebarVisible() -> Bool? { sidebar }
    func setSidebar(visible: Bool) { sidebar = visible }
}

/// Lewa kolumna pokaż/ukryj i usuwanie pustych folderów połączeń (D204).
@MainActor
@Suite("Panel po lewej i foldery połączeń")
struct SidebarAndFolderTests {
    @Test("view.toggleSidebar przełącza lewą kolumnę, argument ustawia stan, makro dostaje stan; bez okna — błąd")
    func toggleSidebar() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        await #expect(throws: CommandError.self) { try await ws.invoke("view.toggleSidebar") }
        let ui = SidebarUI()
        ws.ui = ui
        let r = try await ws.invoke("view.toggleSidebar")
        #expect(ui.sidebar == false)
        #expect(r.value == .bool(false))
        #expect(r.resolvedArguments?.bool("visible") == false)
        _ = try await ws.invoke("view.toggleSidebar")
        #expect(ui.sidebar == true)
        _ = try await ws.invoke("view.toggleSidebar", CommandArguments(["visible": .bool(true)]))
        #expect(ui.sidebar == true)
        _ = try await ws.invoke("view.toggleSidebar", CommandArguments(["visible": .bool(false)]))
        #expect(ui.sidebar == false)
        let d = try #require(ws.registry.command("view.toggleSidebar")?.descriptor)
        #expect(d.agentAccess == AgentAccess.none)
        #expect(d.effect == .uiState)
        let chord = try #require(KeyChord(string: "ctrl+cmd+s"))
        #expect(d.shortcuts[.macOS] == [chord])
        #expect(d.shortcuts[.plsqlDeveloper] == [chord])
        #expect(ws.keymap.command(for: chord) == "view.toggleSidebar")
        #expect(ToolbarModel.paletteCommands.contains("view.toggleSidebar"))
    }

    @Test("układ okna: schowana lewa kolumna zapamiętana, starszy układ bez pola — widoczna")
    func layoutCollapsed() throws {
        let l = WindowLayout(frame: "{{0, 0}, {1200, 800}}", sidebarWidth: 300, sidebarPane: 1, agentPaneVisible: false, sidebarCollapsed: true)
        let back = try JSONDecoder().decode(WindowLayout.self, from: JSONEncoder().encode(l))
        #expect(back.isSidebarCollapsed && back.sidebarWidth == 300)
        let old = #"{"frame":"{{0, 0}, {1200, 800}}","sidebarWidth":260,"sidebarPane":0,"agentPaneVisible":false}"#
        #expect(try JSONDecoder().decode(WindowLayout.self, from: Data(old.utf8)).isSidebarCollapsed == false)
        // Widoczna kolumna nie dopisuje pola (pliki układu jak dotąd).
        let visible = WindowLayout(frame: "", sidebarWidth: 260, sidebarPane: 0, agentPaneVisible: false)
        #expect(!String(decoding: try JSONEncoder().encode(visible), as: UTF8.self).contains("sidebarCollapsed"))
    }

    @Test("usunięcie folderu: pusty usuwa (zapis), niepusty odmawia z liczbą połączeń i podfolderów")
    func deleteEmptyFolder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-folders-\(UUID().uuidString)/connections.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConnectionStore(fileURL: url, secrets: MemorySecretStore())
        let full = ConnectionFolder(name: "Produkcja")
        let sub = ConnectionFolder(name: "Klienci", parentID: full.id)
        let empty = ConnectionFolder(name: "Pusty")
        for f in [full, sub, empty] { try store.upsert(folder: f) }
        let def = ConnectionDefinition(name: "prod", folderID: full.id, target: ConnectionTarget(user: "u", connectString: "c"))
        try store.upsert(def)

        #expect(store.deletionBlocker(folder: empty.id) == nil)
        #expect(store.deletionBlocker(folder: sub.id) == nil)
        let reason = try #require(store.deletionBlocker(folder: full.id))
        #expect(reason.contains("Produkcja") && reason.contains("1"))
        #expect(throws: CommandError.notAvailable(reason)) { try store.removeEmpty(folder: full.id) }
        #expect(store.folders.count == 3)

        try store.removeEmpty(folder: empty.id)
        try store.removeEmpty(folder: sub.id)
        #expect(store.folders.map(\.name) == ["Produkcja"])
        // Folder z samymi połączeniami — nadal nie.
        #expect(store.deletionBlocker(folder: full.id) != nil)
        // Trwale w connections.json.
        let reopened = ConnectionStore(fileURL: url, secrets: MemorySecretStore())
        #expect(reopened.folders.map(\.name) == ["Produkcja"])
        #expect(reopened.connection(def.id)?.folderID == full.id)
    }

    @Test("connection.deleteFolder: nazwa albo id, niepusty i specjalne odmawiają, wybór z listy ze ścieżką, makro z id")
    func deleteFolderCommand() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let parent = ConnectionFolder(name: "Zespół")
        let child = ConnectionFolder(name: "Archiwum", parentID: parent.id)
        let rule = ConnectionFolder(name: "SYS", userPattern: "sys*")
        for f in [parent, child, rule] { try ws.connections.upsert(folder: f) }

        // Folder z podfolderem — odmowa, nic nie znika.
        await #expect(throws: CommandError.self) {
            try await ws.invoke("connection.deleteFolder", CommandArguments(["folder": .string("zespół")]))
        }
        // Folder z regułą — nieusuwalny, także pusty.
        #expect(ws.connections.deletionBlocker(folder: rule.id) != nil)
        await #expect(throws: CommandError.self) {
            try await ws.invoke("connection.deleteFolder", CommandArguments(["folder": .string(rule.id.uuidString)]))
        }
        // „Ostatnie” — folder automatyczny; nieznany folder — błąd argumentu.
        do {
            _ = try await ws.invoke("connection.deleteFolder", CommandArguments(["folder": .string("Ostatnie")]))
            Issue.record("Ostatnie usunięte")
        } catch let CommandError.notAvailable(m) {
            #expect(m.contains(L10n.tr("Ostatnie")))
        }
        await #expect(throws: CommandError.invalidArgument("folder", L10n.tr("nieznany folder"))) {
            try await ws.invoke("connection.deleteFolder", CommandArguments(["folder": .string("brak")]))
        }
        // Bez argumentu i bez okna (skrypt, agent) — brak argumentu.
        await #expect(throws: CommandError.missingArgument("folder")) { try await ws.invoke("connection.deleteFolder") }
        #expect(ws.connections.folders.count == 3)

        // Użytkownik bez argumentu: lista folderów ze ścieżkami, wybór podfolderu.
        let ui = SidebarUI()
        ws.ui = ui
        ui.choice = "Zespół / Archiwum"
        let cmd = try #require(ws.registry.command("connection.deleteFolder"))
        let r = try await cmd.run(CommandContext(workspace: ws, invoker: .user, arguments: .empty))
        #expect(ui.offered == ["SYS", "Zespół", "Zespół / Archiwum"])
        #expect(r.resolvedArguments?.string("folder") == child.id.uuidString)
        // Teraz rodzic jest pusty.
        _ = try await ws.invoke("connection.deleteFolder", CommandArguments(["folder": .string("Zespół")]))
        #expect(ws.connections.folders.map(\.name) == ["SYS"])
        // Anulowany wybór.
        ui.choice = nil
        await #expect(throws: CommandError.cancelledByUser) {
            _ = try await cmd.run(CommandContext(workspace: ws, invoker: .user, arguments: .empty))
        }
        let d = cmd.descriptor
        #expect(d.agentAccess == AgentAccess.none && d.effect == .settings)
        #expect(d.agentAccess == ws.registry.command("connection.newFolder")?.descriptor.agentAccess)
    }
}
