import Foundation
@testable import PelikanWorkspace
import Testing

/// Czynności interfejsu przeniesione do rejestru komend (R4-18): przypięcie połączenia okna, czyszczenie ostatnich
/// plików, wszystkie punkty przerwania naraz.
@MainActor
@Suite("Czynności interfejsu jako komendy")
struct UIActionCommandsTests {
    @Test("przypięcie połączenia okna: przełącza i bez własnego połączenia bierze połączenie główne")
    func pinWindowConnection() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.sql)
        #expect(!doc.connectionPinned)
        try await ws.invoke("session.pinWindowConnection")
        #expect(doc.connectionPinned)
        #expect(doc.connectionID == ws.sessions.mainConnectionID)
        try await ws.invoke("session.pinWindowConnection")
        #expect(!doc.connectionPinned)
    }

    @Test("czyszczenie listy ostatnich plików")
    func clearRecent() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.settings.recentFiles = ["/tmp/a.sql", "/tmp/b.sql"]
        try await ws.invoke("file.clearRecent")
        #expect(ws.settings.recentFiles.isEmpty)
    }

    @Test("włącz, wyłącz i usuń wszystkie punkty przerwania")
    func allBreakpoints() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.breakpoints = [Breakpoint(owner: "A", unit: "P", type: .procedure, line: 3), Breakpoint(owner: "A", unit: "P", type: .procedure, line: 7)]
        ws.breakpoints[1].enabled = false
        try await ws.invoke("debug.enableAllBreakpoints")
        #expect(ws.breakpoints.allSatisfy { $0.enabled })
        try await ws.invoke("debug.disableAllBreakpoints")
        #expect(ws.breakpoints.allSatisfy { !$0.enabled })
        #expect(ws.breakpoints.count == 2)
        try await ws.invoke("debug.removeAllBreakpoints")
        #expect(ws.breakpoints.isEmpty)
    }

    @Test("przypinanie nowych okien (Preferencje): okno SQL przypięte do połączenia głównego, bez głównego — nieprzypięte")
    func pinNewWindowsByDefault() {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.settings.pinWindowConnectionsByDefault = true
        let before = ws.newDocument(.sql)
        #expect(!before.connectionPinned && before.connectionID == nil)
        let main = UUID()
        ws.sessions.setMainConnection(main)
        let sql = ws.newDocument(.sql)
        #expect(sql.connectionPinned && sql.connectionID == main)
        #expect(!ws.newDocument(.diagram).connectionPinned)
        ws.settings.pinWindowConnectionsByDefault = false
        #expect(!ws.newDocument(.program).connectionPinned)
    }
}
