import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Agent na bazie testowej: zmiany i cofanie (SECURITY §5)", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(4)))
struct AgentChangesTests {
    static let gate = AllowingGate()

    func workspace() throws -> (Workspace, ConnectionDefinition, Invoker) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "Testowa", target: ConnectionTarget(user: c.user, connectString: c.connectString), environment: .test)
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        ws.agentGate = Self.gate
        return (ws, def, .agent(sessionID: "c\(UUID().uuidString.prefix(6).lowercased())", agentName: "test"))
    }

    @Test("DML agenta niezatwierdzone: druga sesja nie widzi zmian do COMMIT; DDL odrzucone przy otwartej transakcji; ROLLBACK przy zamknięciu")
    func uncommittedDML() async throws {
        let (ws, def, agent) = try workspace()
        let user = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        let count = { try await user.scalar("select count(*) from dept where deptno in (96, 95)") }
        let r = try await ws.invoke("agent.execute", CommandArguments(["sql": "insert into dept (deptno, dname) select 96, 'AGENT' from dual"]), invoker: agent).value
        #expect(r?["pendingTransaction"] == .bool(true) && r?["pendingRows"] == .int(1))
        #expect(try await count() == "0")
        let preview = try await ws.preview("agent.commit", invoker: agent)
        #expect(preview.estimatedRows == 1 && preview.irreversible)
        await #expect(throws: AgentDenial.self) {
            try await ws.invoke("agent.execute", CommandArguments(["sql": "create table pelikan_agent_x (id number)"]), invoker: agent)
        }
        try await ws.invoke("agent.commit", invoker: agent)
        #expect(try await count() == "1")
        _ = try await ws.invoke("agent.execute", CommandArguments(["sql": "delete from dept where deptno = 96"]), invoker: agent)
        _ = try await ws.invoke("agent.execute", CommandArguments(["sql": "insert into dept (deptno, dname) values (95, 'X')"]), invoker: agent)
        await ws.closeAgentDatabase(session: agent.agentSessionID!)
        #expect(try await count() == "1")                      // ROLLBACK: usunięcie i wstawienie wycofane
        _ = try await user.execute("delete from dept where deptno = 96")
        try await user.commit()
        await ws.sessions.disconnectAll()
    }

    @Test("Podgląd: polecenia, tabela i plan z szacunkiem wierszy; DDL na tabeli nieodwracalne; COMMIT w skrypcie odrzucony")
    func preview() async throws {
        let (ws, _, agent) = try workspace()
        let p = try await ws.preview("agent.execute", CommandArguments(["sql": "update emp set sal = sal where deptno = 10"]), invoker: agent)
        #expect(p.statements.count == 1 && p.affectedObjects.contains { $0.hasSuffix(".EMP") } && p.estimatedRows != nil && p.plan != nil && !p.irreversible)
        let d = try await ws.preview("agent.execute", CommandArguments(["sql": "drop table emp"]), invoker: agent)
        #expect(d.irreversible)
        await #expect(throws: (any Error).self) {
            try await ws.invoke("agent.executeScript", CommandArguments(["script": "update emp set sal = sal;\ncommit;"]), invoker: agent)
        }
        await ws.sessions.disconnectAll()
    }

    @Test("Historia kodu: cofnięcie sesji przywraca poprzednią wersję i usuwa obiekt utworzony przez agenta; zmiana późniejsza = konflikt")
    func codeHistoryAndUndo() async throws {
        let (ws, def, agent) = try workspace()
        let user = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await user.execute("create or replace function pelikan_agent_f return number is begin return 1; end;")
        _ = try await user.execute("create or replace function pelikan_agent_g return number is begin return 1; end;")
        let script = """
            create or replace function pelikan_agent_f return number is begin return 2; end;
            /
            create or replace procedure pelikan_agent_p is begin null; end;
            /
            create or replace function pelikan_agent_g return number is begin return 2; end;
            /
            """
        let r = try await ws.invoke("agent.executeScript", CommandArguments(["script": .string(script)]), invoker: agent).value
        #expect(r?["results"]?.arrayValue?.count == 3 && r?["stoppedOnError"] == nil)
        #expect(ws.agentCodeChanges.count == 3)
        // Użytkownik zmienia G po agencie — konflikt.
        _ = try await user.execute("create or replace function pelikan_agent_g return number is begin return 3; end;")
        let report = await ws.undoAgentSession(agent.agentSessionID!)
        #expect(report.objectsRestored == 2 && report.conflicts.count == 1 && report.errors.isEmpty, "\(report)")
        #expect(try await user.scalar("select pelikan_agent_f from dual") == "1")
        #expect(try await user.scalar("select count(*) from all_objects where object_name = 'PELIKAN_AGENT_P'") == "0")
        #expect(try await user.scalar("select pelikan_agent_g from dual") == "3")
        for o in ["function pelikan_agent_f", "function pelikan_agent_g", "procedure pelikan_agent_p"] { _ = try? await user.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }

    @Test("Kompilacja okna, szkielet testu w bazie i uruchomienie testów w sesjach agenta")
    func compileGenerateRun() async throws {
        let (ws, def, agent) = try workspace()
        let user = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await user.execute("create or replace package pelikan_agent_pkg as procedure a; end;")
        let doc = ws.newDocument(.program, text: "create or replace package body pelikan_agent_pkg as procedure a is begin nul; end; end;\n/\n")
        doc.connectionID = def.id
        let r = try await ws.invoke("agent.compile", CommandArguments(["window": .string(Workspace.agentWindowID(doc))]), invoker: agent).value
        #expect(r?["results"]?.arrayValue?.first?["compileErrors"] != nil)
        let g = try await ws.invoke("agent.generateTest", CommandArguments(["package": "pelikan_agent_pkg"]), invoker: agent).value
        #expect(g?["window"] != nil)
        let schema = c(ws)
        let t = try await ws.invoke("agent.runTests", CommandArguments(["paths": .string("\(schema).test_pelikan_agent_pkg")]), invoker: agent).value
        #expect(t?["content"]?["failure"] == .int(1))
        let report = await ws.undoAgentSession(agent.agentSessionID!)
        #expect(report.conflicts.isEmpty && report.objectsRestored >= 3, "\(report)")
        #expect(try await user.scalar("select count(*) from all_objects where object_name in ('TEST_PELIKAN_AGENT_PKG') ") == "0")
        _ = try? await user.execute("drop package pelikan_agent_pkg")
        await ws.closeAgentDatabase(session: agent.agentSessionID!)
        await ws.sessions.disconnectAll()
    }

    func c(_ ws: Workspace) -> String { TestDatabase.config!.user.uppercased() }
}
