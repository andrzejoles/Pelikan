import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Zakończenie sesji okna i SQL Trace na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(2)))
struct SessionKillTests {
    func workspace() throws -> (Workspace, ConnectionDefinition, TestUI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        return (ws, def, ui)
    }

    @Test("Kill: długie zapytanie w oknie przerwane przez zakończenie sesji z innej sesji; okno łączy się ponownie")
    func kill() async throws {
        let (ws, def, ui) = try workspace()
        let doc = ws.newDocument(.sql, text: "select count(*) from all_objects a, all_objects b, all_objects c")
        doc.connectionID = def.id
        doc.connectionPinned = true
        let key = ws.sessions.key(forDocument: doc.id, connection: def.id)
        let s = try await ws.sessions.session(key)
        let sid = try #require(ws.sessions.serverSessionIDs[key]?.sid)
        let running = Task { try await s.execute(doc.text) }
        try await Task.sleep(for: .seconds(2))
        ui.askAnswer = 0
        ws.activate(doc.id)
        let r = try await ws.invoke("session.kill")
        #expect(r.message?.contains(sid) == true && ui.asked.count == 1)
        await #expect(throws: (any Error).self) { _ = try await running.value }
        #expect(ws.sessions.existingSession(key) == nil)
        let s2 = try await ws.sessions.session(key)
        #expect(try await s2.scalar("select 1 from dual") == "1" && ws.sessions.serverSessionIDs[key]?.sid != nil)
        await ws.sessions.disconnectAll()
    }

    @Test("SQL Trace: włączenie podaje plik śladu, drugie wywołanie wyłącza")
    func trace() async throws {
        let (ws, def, _) = try workspace()
        let doc = ws.newDocument(.sql, text: "select 1 from dual")
        doc.connectionID = def.id
        doc.connectionPinned = true
        ws.activate(doc.id)
        let on = try await ws.invoke("session.sqlTrace")
        #expect(on.value == .bool(true) && on.message?.contains(".trc") == true)
        let off = try await ws.invoke("session.sqlTrace")
        #expect(off.value == .bool(false))
        await ws.sessions.disconnectAll()
    }
}
