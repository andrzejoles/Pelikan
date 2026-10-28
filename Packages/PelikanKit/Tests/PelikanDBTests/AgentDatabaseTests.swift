import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Agent na bazie testowej: sesja i odczyt (SECURITY §5)", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct AgentDatabaseTests {
    static let agent = Invoker.agent(sessionID: "t\(UUID().uuidString.prefix(6).lowercased())", agentName: "test")
    /// Bramka trzymana przez cały test (Workspace trzyma ją słabo).
    static let gate = AllowingGate()

    func workspace(_ configure: (inout ConnectionDefinition) -> Void = { _ in }) throws -> (Workspace, ConnectionDefinition) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        var def = ConnectionDefinition(name: "dev_testowa", target: ConnectionTarget(user: c.user, connectString: c.connectString), environment: .test)
        configure(&def)
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        ws.agentGate = Self.gate
        return (ws, def)
    }

    func call(_ ws: Workspace, _ id: CommandID, _ args: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await ws.invoke(id, CommandArguments(args), invoker: Self.agent).value ?? .null
    }

    func content(_ v: JSONValue) -> JSONValue {
        #expect(v["untrusted_content"] == .bool(true))
        return v["content"] ?? .null
    }

    @Test("Własna sesja agenta: nie widzi niezatwierdzonej transakcji użytkownika; MODULE i CLIENT_INFO; ROLLBACK przy zamknięciu")
    func ownSession() async throws {
        let (ws, def) = try workspace()
        let user = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        _ = try await user.execute("insert into dept (deptno, dname) values (97, 'AGENT')")
        let r = content(try await call(ws, "agent.query", ["sql": "select count(*) n, sys_context('userenv','module') m, sys_context('userenv','client_info') c from dept where deptno = 97"]))
        let row = r["rows"]?.arrayValue?.first?.arrayValue ?? []
        #expect(row.first == .string("0"))
        #expect(row.dropFirst().first == .string("Pelikan agent") && row.last?.stringValue?.hasPrefix("Pelikan agent t") == true)
        #expect(r["readOnlyTransaction"] == .bool(true))
        try await user.rollback()
        #expect(!ws.sessions.keys(purpose: .agent(Self.agent.agentSessionID!)).isEmpty)
        await ws.closeAgentDatabase(session: Self.agent.agentSessionID!)
        #expect(ws.sessions.keys(purpose: .agent(Self.agent.agentSessionID!)).isEmpty)
        await ws.sessions.disconnectAll()
    }

    @Test("run_query: tylko jedno SELECT/WITH, bez FOR UPDATE i funkcji w WITH; limit wierszy; maskowanie kolumn")
    func queryRules() async throws {
        let (ws, _) = try workspace { $0.agent.maskedColumns = ["PELIKAN_TEST.EMP.SAL", "COMM"] }
        for bad in ["delete from emp", "select 1 from dual; select 2 from dual", "select * from emp for update",
                    "with function f return number is begin return 1; end; select f from dual", "begin null; end;",
                    "select sal * 2 from emp", "select \"COMM\" from emp"] {
            await #expect(throws: (any Error).self, "\(bad)") { _ = try await call(ws, "agent.query", ["sql": .string(bad)]) }
        }
        let r = content(try await call(ws, "agent.query", ["sql": "select * from emp order by empno", "maxRows": 3]))
        #expect(r["rowCount"] == .int(3) && r["truncated"] == .bool(true))
        let cols = r["columns"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        let sal = try #require(cols.firstIndex(of: "SAL"))
        #expect(r["rows"]?.arrayValue?.allSatisfy { $0.arrayValue?[sal] == .string("***") } == true)
        #expect(r["rows"]?.arrayValue?.first?.arrayValue?[cols.firstIndex(of: "ENAME")!] != .string("***"))
        await ws.sessions.disconnectAll()
    }

    @Test("Użytkownik bazy agenta przez proxy: sesja z uprawnieniami tylko tego użytkownika")
    func proxyUser() async throws {
        let c = TestDatabase.config!
        let (ws, _) = try workspace { $0.agent.agentUser = c.agentUser }
        let r = content(try await call(ws, "agent.query", ["sql": "select user u, sys_context('userenv','proxy_user') p from dual"]))
        let row = r["rows"]?.arrayValue?.first?.arrayValue ?? []
        #expect(row.first == .string(c.agentUser.uppercased()) && row.last == .string(c.user.uppercased()))
        await ws.sessions.disconnectAll()
    }

    @Test("Narzędzia odczytu: wyszukiwanie, opis, źródło, DDL, zależności, użycia, plan, błędy, testy, otwarcie obiektu")
    func readTools() async throws {
        let (ws, _) = try workspace()
        let found = content(try await call(ws, "agent.searchObjects", ["name": "EMP%", "type": "PACKAGE"]))
        #expect(found.arrayValue?.contains { $0["object_name"] == .string("EMP_API") } == true)
        let table = content(try await call(ws, "agent.describe", ["object": "emp"]))
        #expect(table["type"] == .string("TABLE") && table["columns"]?.arrayValue?.contains { $0["column_name"] == .string("ENAME") } == true)
        let pkg = content(try await call(ws, "agent.describe", ["object": "emp_api"]))
        #expect(pkg["arguments"]?.arrayValue?.isEmpty == false)
        let src = content(try await call(ws, "agent.source", ["object": "emp_api"]))
        #expect(src["source"]?.stringValue?.contains("CREATE OR REPLACE PACKAGE BODY") == true)
        // Bez „/” domyślnie (D192) — agent może zapisać źródło do pliku w repozytorium.
        #expect(src["source"]?.stringValue?.components(separatedBy: "\n").contains("/") == false)
        let ddl = content(try await call(ws, "agent.ddl", ["object": "dept"]))
        #expect(ddl["ddl"]?.stringValue?.uppercased().contains("CREATE TABLE") == true)
        let deps = content(try await call(ws, "agent.dependencies", ["object": "emp_api"]))
        #expect(deps["usedBy"]?.arrayValue?.contains { $0["name"] == .string("TEST_EMP_API") } == true)
        let usages = content(try await call(ws, "agent.findUsages", ["object": "emp_api"]))
        #expect(usages.arrayValue?.isEmpty == false)
        let plan = content(try await call(ws, "agent.explain", ["sql": "update emp set sal = sal where deptno = 10"]))
        #expect(plan["plan"]?.stringValue?.contains("UPDATE") == true && plan["estimatedRows"] != .null)
        let errors = content(try await call(ws, "agent.compileErrors", ["object": "broken_pkg", "type": "PACKAGE BODY"]))
        #expect(errors.arrayValue?.isEmpty == false)
        let tests = content(try await call(ws, "agent.listTests"))
        #expect(tests.arrayValue?.contains { $0["object_name"] == .string("TEST_EMP_API") } == true)
        let before = ws.documents.count
        _ = try await call(ws, "agent.openObject", ["object": "emp_api", "line": 3])
        #expect(ws.documents.count == before + 1 && ws.documents.last?.kind == .program)
        await ws.sessions.disconnectAll()
    }
}
