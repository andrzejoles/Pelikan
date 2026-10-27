import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu z panelami narzędzi: zapisuje wywołania, zwraca klucz „bieżącego” narzędzia.
@MainActor
final class DockUI: UIServices {
    var current: String?
    var placed: [(String, ToolPlacement)] = []
    var toggled: [ToolPlacement] = []
    var closed: [String] = []
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
    func toggleToolDock(_ placement: ToolPlacement) { toggled.append(placement) }
    func placeTool(_ key: String?, at placement: ToolPlacement) -> String? {
        guard let k = key ?? current else { return nil }
        placed.append((k, placement))
        return k
    }
    func closeTool(_ key: String?) -> String? {
        guard let k = key ?? current else { return nil }
        closed.append(k)
        return k
    }
}

/// Dokowanie narzędzi w panelach okna głównego (PD-UI-003, D183).
@MainActor
@Suite("Panele narzędzi")
struct ToolDockTests {
    @Test("rodzaj narzędzia: klucze jednorazowe dzielą miejsce, pozostałe są rodzajem same w sobie")
    func kinds() {
        #expect(ToolDockSettings.kind(of: "diff-0A1B") == "diff")
        #expect(ToolDockSettings.kind(of: "table-APP.ORDERS") == "table")
        #expect(ToolDockSettings.kind(of: "debugger-42") == "debugger")
        #expect(ToolDockSettings.kind(of: "html-x") == "html")
        #expect(ToolDockSettings.kind(of: "sessions") == "sessions")
        #expect(ToolDockSettings.kind(of: "tableau") == "tableau")
    }

    @Test("domyślnie panel po prawej, zgoda agenta w osobnym oknie; wybór użytkownika ma pierwszeństwo")
    func placements() {
        var s = ToolDockSettings()
        #expect(s.placement(for: "sessions") == .right)
        #expect(s.placement(for: "diff-1") == .right)
        #expect(s.placement(for: "approval") == .floating)
        s.remember(.bottom, for: "diff-1")
        #expect(s.placement(for: "diff-2") == .bottom)
        s.remember(.right, for: "approval")
        #expect(s.placement(for: "approval") == .right)
        // Miejsce domyślne nie zostawia wpisu.
        s.remember(.right, for: "diff-3")
        s.remember(.floating, for: "approval")
        #expect(s.placements.isEmpty)
        // Miejsce domyślne z Preferencji (np. osobne okna jak przed D183); zgoda agenta zostaje w oknie.
        s.defaultPlacement = .floating
        #expect(s.placement(for: "sessions") == .floating)
        s.remember(.right, for: "sessions")
        #expect(s.placement(for: "sessions") == .right)
        s.remember(.floating, for: "sessions")
        #expect(s.placements.isEmpty)
        s.defaultPlacement = .bottom
        #expect(s.placement(for: "approval") == .floating)
    }

    @Test("ustawienia: zapis i odczyt, nieznane miejsce pominięte, brak pola — wartości domyślne")
    func coding() throws {
        var s = ToolDockSettings()
        s.remember(.floating, for: "sessions")
        s.autoHide = true
        s.defaultPlacement = .bottom
        let back = try JSONDecoder().decode(ToolDockSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let mixed = try JSONDecoder().decode(ToolDockSettings.self, from: Data(#"{"placements":{"a":"bottom","b":"left"}}"#.utf8))
        #expect(mixed.placements == ["a": .bottom])
        #expect(!mixed.autoHide && mixed.defaultPlacement == .right)
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(settings.toolDock == ToolDockSettings())
    }

    @Test("komendy: przeniesienie zapamiętuje miejsce rodzaju, brak narzędzia — błąd, autoukrywanie przełącza")
    func commands() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = DockUI()
        ws.ui = ui
        await #expect(throws: CommandError.self) { try await ws.invoke("view.dockToolBottom") }
        ui.current = "graph-77"
        _ = try await ws.invoke("view.dockToolBottom")
        #expect(ui.placed.last?.0 == "graph-77" && ui.placed.last?.1 == .bottom)
        #expect(ws.settings.toolDock.placement(for: "graph-1") == .bottom)
        _ = try await ws.invoke("view.floatTool", CommandArguments(["tool": .string("sessions")]))
        #expect(ws.settings.toolDock.placement(for: "sessions") == .floating)
        _ = try await ws.invoke("view.dockToolRight", CommandArguments(["tool": .string("sessions")]))
        #expect(ws.settings.toolDock.placements["sessions"] == nil)
        _ = try await ws.invoke("view.closeTool")
        #expect(ui.closed == ["graph-77"])
        _ = try await ws.invoke("view.toolDockRight")
        _ = try await ws.invoke("view.toolDockBottom")
        #expect(ui.toggled == [.right, .bottom])
        _ = try await ws.invoke("view.toolDockAutoHide")
        #expect(ws.settings.toolDock.autoHide)
        // Polecenia paneli nie są dostępne dla agenta AI.
        for id in ["view.toolDockRight", "view.dockToolRight", "view.floatTool", "view.closeTool", "view.toolDockAutoHide"] {
            #expect(ws.registry.command(CommandID(rawValue: id))?.descriptor.agentAccess == AgentAccess.none, "\(id)")
        }
    }
}
