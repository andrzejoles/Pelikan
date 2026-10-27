import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Transakcje okien i sesje (przegląd 3) na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(2)))
struct SessionTransactionDBTests {
    func workspace() throws -> (Workspace, ConnectionDefinition, TestUI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def, ui)
    }

    @Test("Okno testu: blok z DML oznacza otwartą transakcję (COMMIT/ROLLBACK włączone); drugie wykonanie przyjmuje znacznik czasu z pierwszego")
    func testWindowTransaction() async throws {
        let (ws, _, _) = try workspace()
        let doc = ws.newDocument(.test, text: "begin\n  update emp set comm = comm where empno = 7369;\n  :t := :t + interval '1' second;\nend;")
        TestRunner.synchronize(doc)
        doc.testVariables[0].type = .timestamp
        doc.testVariables[0].value = "2026-10-26 12:00:00"
        doc.testVariables[0].isNull = false
        try await ws.invoke("sql.execute")
        #expect(doc.transactionOpen && ws.isEnabled("session.rollback"))
        try await ws.invoke("sql.execute")                                    // wartość w formacie wyświetlania (z .FF)
        #expect(doc.testVariables[0].value.hasPrefix("2026-10-26 12:00:02"))
        try await ws.invoke("session.rollback")
        #expect(!doc.transactionOpen)
        await ws.sessions.disconnectAll()
    }

    @Test("Notatnik: blok PL/SQL z DML oznacza transakcję, DDL po nim ją zamyka")
    func notebookTransaction() async throws {
        let (ws, _, _) = try workspace()
        let doc = ws.newDocument(.notebook)
        doc.notebook.cells = [NotebookCell(kind: .sql, text: "begin update emp set comm = comm where empno = 7369; end;\n/"),
                              NotebookCell(kind: .sql, text: "rollback")]
        await NotebookRunner.run(cell: 0, in: doc, ws: ws)
        #expect(doc.notebook.cells[0].result?.error == nil && doc.transactionOpen)
        await NotebookRunner.run(cell: 1, in: doc, ws: ws)
        #expect(!doc.transactionOpen)
        await ws.sessions.disconnectAll()
    }

    @Test("Debuger: program z DML zostawia otwartą transakcję okna")
    func debuggerTransaction() async throws {
        let (ws, _, _) = try workspace()
        let doc = ws.newDocument(.test, text: "begin\n  update emp set comm = comm where empno = 7369;\nend;")
        TestRunner.synchronize(doc)
        let d = ws.debugger(for: doc)
        try await d.start()
        try await d.step(.run)
        #expect(d.state == .finished && doc.transactionOpen)
        try await ws.invoke("session.rollback")
        await ws.sessions.disconnectAll()
    }

    @Test("Tryb Dual: wyłączenie wyzwalacza (DDL) w sesji kompilacji — transakcja okna nie jest zatwierdzana; widok zmaterializowany o nazwie z małymi literami")
    func dualModeObjectCommands() async throws {
        let (ws, def, _) = try workspace()
        ws.settings.sessionMode = .dual
        let compile = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await compile.execute("create or replace trigger pelikan_tx_trg before update on dept for each row begin null; end;")
        let doc = ws.newDocument(.sql, text: "update emp set comm = comm where empno = 7369")
        try await ws.invoke("sql.execute")
        #expect(doc.transactionOpen)
        _ = try await ws.invoke("ob.disable", CommandArguments(["object": "pelikan_tx_trg"]))
        let main = try #require(ws.sessions.existingSession(SessionKey(connectionID: def.id, purpose: .main)))
        #expect(try await SessionUtilities.transactionOpen(main))
        try await ws.invoke("session.rollback")
        _ = try await compile.execute("drop trigger pelikan_tx_trg")

        _ = try? await compile.execute(#"drop materialized view "PelikanTxMv""#)
        _ = try await compile.execute(#"create materialized view "PelikanTxMv" refresh complete on demand as select deptno from dept"#)
        _ = try await ws.invoke("ob.refreshMV", CommandArguments(["object": "\"PelikanTxMv\"", "type": "MATERIALIZED VIEW"]))
        #expect(try await compile.scalar("select last_refresh_type from user_mviews where mview_name = 'PelikanTxMv'") == "COMPLETE")
        _ = try await compile.execute(#"drop materialized view "PelikanTxMv""#)
        await ws.sessions.disconnectAll()
    }

    @Test("Zakończenie sesji okna: numer seryjny zapamiętany przy otwarciu; SID z innym numerem — „sesja już nie istnieje”")
    func killChecksSerial() async throws {
        let (ws, def, _) = try workspace()
        let key = SessionKey(connectionID: def.id, purpose: .document(DocumentID()))
        _ = try await ws.sessions.session(key)
        let id = try #require(ws.sessions.serverSessionIDs[key])
        #expect(id.serial?.isEmpty == false)
        let tool = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .tool("kill")))
        let stale = String((Int(id.serial ?? "0") ?? 0) + 1)
        await #expect(throws: CommandError.self) { try await SessionKiller.kill(sid: id.sid, serial: stale, instance: id.instance, using: tool) }
        #expect(ws.sessions.existingSession(key) != nil)
        await ws.sessions.disconnectAll()
    }

    @Test("Test łącza: zapytanie przez łącze nie zostawia transakcji rozproszonej w sesji głównej (tryb Dual)")
    func linkTestLeavesNoTransaction() async throws {
        let c = TestDatabase.config!
        let (ws, def, _) = try workspace()
        ws.settings.sessionMode = .dual
        let main = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        let schema = try await ws.metadata()!.currentSchema()
        // Łącze do tej samej bazy (z wnętrza kontenera: port 1521) — hasło testowe tylko w poleceniu do bazy testowej.
        _ = try? await main.execute("drop database link pelikan_tx_loop")
        _ = try await main.execute("create database link pelikan_tx_loop connect to \(c.user) identified by \"\(c.password)\" using 'localhost:1521/FREEPDB1'")
        ws.selectedObject = DBObject(owner: schema, name: "PELIKAN_TX_LOOP", type: .databaseLink)
        let r = try await ws.invoke("ob.testLink", CommandArguments())
        #expect(r.message?.isEmpty == false)
        #expect(try await !SessionUtilities.transactionOpen(main))
        _ = try? await main.execute("drop database link pelikan_tx_loop")
        await ws.sessions.disconnectAll()
    }
}
