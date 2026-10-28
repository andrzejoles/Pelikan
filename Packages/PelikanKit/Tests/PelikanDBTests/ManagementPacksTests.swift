import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@Suite("Licencje pakietów zarządzania bez bazy")
struct ManagementPacksOfflineTests {
    @Test("Parametr bazy i deklaracja: NONE blokuje, DIAGNOSTIC bez Tuning, brak deklaracji — pytanie")
    func evaluate() {
        #expect(ManagementPacks.evaluate(parameter: "NONE", declared: .diagnosticsAndTuning, need: .diagnostics) != nil)
        if case .failure = ManagementPacks.evaluate(parameter: "DIAGNOSTIC", declared: .diagnosticsAndTuning, need: .tuning)! {} else { Issue.record("tuning przy DIAGNOSTIC") }
        #expect(ManagementPacks.evaluate(parameter: "DIAGNOSTIC+TUNING", declared: nil, need: .diagnostics) == nil)
        if case .success = ManagementPacks.evaluate(parameter: "DIAGNOSTIC+TUNING", declared: .diagnostics, need: .diagnostics)! {} else { Issue.record("diagnostics") }
        if case .failure = ManagementPacks.evaluate(parameter: "DIAGNOSTIC+TUNING", declared: .diagnostics, need: .tuning)! {} else { Issue.record("tuning bez licencji") }
        if case .failure = ManagementPacks.evaluate(parameter: "DIAGNOSTIC+TUNING", declared: ManagementPackLicense.none, need: .diagnostics)! {} else { Issue.record("brak licencji") }
    }

    @Test("Użytkownik w poleceniu GRANT: zwykła nazwa bez cudzysłowów, inna w cudzysłowach, pusta — zamiennik")
    func grantee() {
        #expect(ManagementPacks.grantee("SCOTT") == "SCOTT")
        #expect(ManagementPacks.grantee("APP_USER$1#") == "APP_USER$1#")
        #expect(ManagementPacks.grantee("scott") == "\"scott\"")
        #expect(ManagementPacks.grantee("C##ADMIN") == "C##ADMIN" && ManagementPacks.grantee("1ABC") == "\"1ABC\"")
        #expect(ManagementPacks.grantee("A\"B") == "\"A\"\"B\"")
        #expect(ManagementPacks.grantee("") == L10n.tr("<użytkownik>"))
    }
}

@MainActor
@Suite("Diagnostics/Tuning Pack na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(4)))
struct ManagementPacksTests {
    @Test("Pytanie o licencję zapamiętane; agent odrzucony; AWR, ASH, ADDM, SQL Monitor i Tuning Advisor")
    func reports() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .tool("packs")))
        await #expect(throws: AgentDenial.self) {
            try await ManagementPacks.require(.diagnostics, connection: def.id, session: s, in: ws, invoker: .agent(sessionID: "x", agentName: "t"))
        }
        ui.askAnswer = 0
        try await ManagementPacks.require(.tuning, connection: def.id, session: s, in: ws, invoker: .user)
        #expect(ws.connections.connection(def.id)?.managementPacks == .diagnosticsAndTuning && ui.asked.count == 1)
        try await ManagementPacks.require(.diagnostics, connection: def.id, session: s, in: ws, invoker: .user)
        #expect(ui.asked.count == 1)

        _ = try await s.execute("begin dbms_workload_repository.create_snapshot; end;")
        _ = try await s.execute("begin for r in (select count(*) from all_objects) loop null; end loop; end;")
        _ = try await s.execute("begin dbms_workload_repository.create_snapshot; end;")
        let snaps = try #require(try await ManagementPacks.lastSnapshots(in: s))
        #expect(try await ManagementPacks.awrReport(s, dbid: snaps.dbid, instance: snaps.instance, begin: snaps.begin, end: snaps.end).lowercased().contains("<html"))
        #expect(try await ManagementPacks.ashReport(s, minutes: 30).lowercased().contains("<html"))
        #expect(!(try await ManagementPacks.addmReport(s, begin: snaps.begin, end: snaps.end)).isEmpty)
        let r = try await s.execute("select /*+ MONITOR */ count(*) from all_objects")
        if let rs = r.resultSet { _ = try await s.fetch(rs.id, maxRows: 10); await s.closeResultSet(rs.id) }
        let mon = try await ManagementPacks.monitoredSQL(s)
        if let id = mon.rows.first?.first { #expect(try await ManagementPacks.sqlMonitorReport(s, sqlID: id).lowercased().contains("<html")) }
        let tune = try await ManagementPacks.tuningReport(s, sql: "select * from emp where ename = 'KING'", timeLimitSeconds: 30)
        #expect(tune.uppercased().contains("GENERAL INFORMATION"))
        await ws.sessions.disconnectAll()
    }

    @Test("Bez EXECUTE do DBMS_WORKLOAD_REPOSITORY: czytelny komunikat z poleceniem GRANT zamiast ORA-00904 (#113, #114)")
    func reportsWithoutPrivilege() async throws {
        let c = TestDatabase.config!
        let s = try await ODPISession.connect(target: ConnectionTarget(user: c.agentUser, connectString: c.connectString),
                                              credentials: Credentials(password: c.agentPassword), options: ConnectOptions())
        defer { Task { await s.close() } }
        for report in [{ _ = try await ManagementPacks.ashReport(s, minutes: 5) },
                       { _ = try await ManagementPacks.awrReport(s, dbid: "1", instance: "1", begin: "1", end: "2") }] {
            do {
                try await report()
                Issue.record("raport bez uprawnień")
            } catch let CommandError.notAvailable(m) {
                #expect(m.contains("DBMS_WORKLOAD_REPOSITORY") && m.contains("GRANT EXECUTE"), "\(m)")
            }
        }
    }

    @Test("Komendy AWR i ADDM bez uprawnień: komunikat z GRANT przed odczytem migawek (nie ORA-00942)")
    func reportCommandsWithoutPrivilege() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        var def = ConnectionDefinition(name: "dev_agent_test", target: ConnectionTarget(user: c.agentUser, connectString: c.connectString))
        def.managementPacks = .diagnosticsAndTuning
        try ws.connections.upsert(def, password: c.agentPassword)
        ws.sessions.setMainConnection(def.id)
        // DBMS_ADDM bywa nadany PUBLIC — ADDM sprawdza najpierw dostęp do repozytorium AWR.
        for (id, package) in [("tools.awrReport", "DBMS_WORKLOAD_REPOSITORY"), ("tools.addmReport", "DBMS_WORKLOAD_REPOSITORY")] {
            do {
                try await ws.invoke(CommandID(rawValue: id))
                Issue.record("\(id) bez uprawnień")
            } catch let CommandError.notAvailable(m) {
                #expect(m.contains("GRANT EXECUTE ON SYS.\(package) TO \(c.agentUser.uppercased());") && !m.contains("ORA-"), "\(id): \(m)")
            } catch {
                Issue.record("\(id): \(error)")
            }
        }
        await ws.sessions.disconnectAll()
    }
}
