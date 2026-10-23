import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Przeglądarka sesji na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct SessionBrowserTests {
    @Test("Lista z filtrem, szczegóły z :sid (także sklejane), SQL Trace i zabicie własnej sesji")
    func browse() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let victim = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        let sid = Int(try await victim.scalar("select sys_context('userenv','sid') from dual") ?? "") ?? 0
        let tool = try await SessionCommands.toolSession(ws)
        let mine = ws.settings.sessionQueries.filters.first { $0.sql == "username = user" }!
        let rows = try await SessionBrowser.list(filter: mine.sql, in: tool)
        let row = try #require(rows.first { $0.sid == sid })
        #expect(row.values["USERNAME"] == c.user.uppercased() && rows.allSatisfy { $0.values["USERNAME"] == c.user.uppercased() })
        await #expect(throws: CommandError.self) { _ = try await SessionBrowser.list(filter: "1=1; drop table emp", in: tool) }
        for d in ws.settings.sessionQueries.details {
            let r = try await SessionBrowser.detail(d, sid: row.sid, serial: row.serial, in: tool)
            #expect(r.text != nil || !r.columns.isEmpty, "\(d.name)")
        }
        for a in ws.settings.sessionQueries.actions { try await SessionBrowser.perform(a, sid: row.sid, serial: row.serial, in: tool) }
        try await ws.invoke("sessions.kill", CommandArguments(["sid": .int(Int64(row.sid)), "serial": .int(Int64(row.serial))]))
        await #expect(throws: (any Error).self) { _ = try await victim.scalar("select 1 from dual") }
        await ws.sessions.disconnectAll()
    }
}
