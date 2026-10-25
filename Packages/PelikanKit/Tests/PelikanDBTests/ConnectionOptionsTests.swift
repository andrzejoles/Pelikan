import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Opcje połączenia na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ConnectionOptionsTests {
    @Test("Edition (EBR) z definicji połączenia; eksport i import definicji przez komendy (bez haseł)")
    func editionAndExport() async throws {
        let c = TestDatabase.config!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("conn-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir, drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        var target = ConnectionTarget(user: c.user, connectString: c.connectString)
        target.edition = "ORA$BASE"
        let def = ConnectionDefinition(name: "dev_edycja", target: target)
        try ws.connections.upsert(def, password: c.password)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(try await s.scalar("select sys_context('userenv', 'current_edition_name') from dual") == "ORA$BASE")
        let file = dir.appendingPathComponent("conn.json")
        _ = try await ws.invoke("connection.export", CommandArguments(["file": .string(file.path)]))
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("dev_edycja") && !text.contains(c.password))
        let r = try await ws.invoke("connection.import", CommandArguments(["file": .string(file.path)]))
        #expect(r.value == .int(1) && ws.connections.connections.filter { $0.name == "dev_edycja" }.count == 2)
        await ws.sessions.disconnectAll()
    }

    @Test("Workspace Manager z definicji połączenia: sesja po połączeniu jest w przestrzeni roboczej (DBMS_WM)")
    func workspaceManager() async throws {
        let c = TestDatabase.config!
        let probe = try await TestDatabase.connect()
        let installed = try await probe.scalar("select count(*) from all_workspaces where workspace = 'DEV_PELIKAN_WS'") == "1"
        await probe.close()
        // Bez `scripts/testdb.sh owm` baza testowa nie ma WMSYS — test nie ma czego sprawdzić.
        guard installed else { return }
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let target = ConnectionTarget(user: c.user, connectString: c.connectString)
        let wm = ConnectionDefinition(name: "dev_wm", target: target, workspaceManager: "DEV_PELIKAN_WS")
        let plain = ConnectionDefinition(name: "dev_live", target: target)
        try ws.connections.upsert(wm, password: c.password)
        try ws.connections.upsert(plain, password: c.password)
        let s = try await ws.sessions.session(SessionKey(connectionID: wm.id, purpose: .main))
        #expect(try await s.scalar("select dbms_wm.getworkspace from dual") == "DEV_PELIKAN_WS")
        let p = try await ws.sessions.session(SessionKey(connectionID: plain.id, purpose: .main))
        #expect(try await p.scalar("select dbms_wm.getworkspace from dual") == "LIVE")
        // Nieistniejąca przestrzeń: połączenie kończy się błędem DBMS_WM, nie cichym pozostaniem w LIVE.
        let bad = ConnectionDefinition(name: "dev_wm_brak", target: target, workspaceManager: "DEV_BRAK_TAKIEJ")
        try ws.connections.upsert(bad, password: c.password)
        await #expect(throws: (any Error).self) { _ = try await ws.sessions.session(SessionKey(connectionID: bad.id, purpose: .main)) }
        await ws.sessions.disconnectAll()
    }

    @Test("NLS sesji z Preferencji; zamykanie bezczynnych sesji okien bez transakcji, z transakcją — zostaje")
    func nlsAndIdle() async throws {
        #expect(SessionManager.nlsStatement(["nls_date_format": "DD.MM.YYYY", "BAD": "x", "NLS_SORT": "it's"]) == "ALTER SESSION SET NLS_DATE_FORMAT = 'DD.MM.YYYY'")
        #expect(SessionManager.nlsStatement([:]) == nil)
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        ws.settings.sessionNLS = ["NLS_DATE_FORMAT": "DD.MM.YYYY", "NLS_NUMERIC_CHARACTERS": ", "]
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        let a = ws.newDocument(.sql), b = ws.newDocument(.sql)
        let ka = ws.sessions.key(forDocument: a.id, connection: def.id), kb = ws.sessions.key(forDocument: b.id, connection: def.id)
        let sa = try await ws.sessions.session(ka), sb = try await ws.sessions.session(kb)
        #expect(try await sa.scalar("select value from nls_session_parameters where parameter = 'NLS_DATE_FORMAT'") == "DD.MM.YYYY")
        #expect(try await sa.scalar("select to_char(1.5) from dual") == "1,5")
        _ = try await sb.execute("update dept set loc = loc where deptno = 10")
        let later = Date().addingTimeInterval(3600)
        #expect(await ws.sessions.closeIdleSessions(olderThan: 30, now: later) == 1)
        #expect(ws.sessions.existingSession(ka) == nil && ws.sessions.existingSession(kb) != nil)
        _ = try await sb.execute("rollback")
        #expect(await ws.sessions.closeIdleSessions(olderThan: 0, now: later) == 0)
        await ws.sessions.disconnectAll()
    }

    @Test("Karta Statystyki SQL Window: różnica V$MYSTAT z wykonania (preferencja)")
    func statistics() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        let doc = ws.newDocument(.sql, text: "select count(*) from all_objects")
        doc.connectionID = def.id
        doc.connectionPinned = true
        _ = try await SQLExecutor.execute(doc, scope: .standard, in: ws)
        #expect(doc.statistics.isEmpty)
        ws.settings.sqlWindowStatistics = true
        _ = try await SQLExecutor.execute(doc, scope: .standard, in: ws)
        #expect(doc.statistics.contains { $0.name == "session logical reads" && $0.value > 0 })
        await ws.sessions.disconnectAll()
    }
}
