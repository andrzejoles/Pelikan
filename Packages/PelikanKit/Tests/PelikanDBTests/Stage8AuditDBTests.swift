import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Audyt Etapu 8 na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct Stage8AuditDBTests {
    @Test("ORA-04068: rekompilacja pakietu ze stanem w innej sesji — ostrzeżenie na pasku stanu, ponowne wykonanie działa")
    func discardedPackageState() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        let other = try await TestDatabase.connect()
        let spec = "create or replace package pelikan_state as n number := 0; procedure bump; end;"
        _ = try await other.execute(spec)
        _ = try await other.execute("create or replace package body pelikan_state as procedure bump is begin n := n + 1; end; end;")
        let doc = ws.newDocument(.sql, text: "begin pelikan_state.bump; end;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        #expect(try await SQLExecutor.execute(doc, scope: .standard, in: ws))
        _ = try await other.execute("create or replace package body pelikan_state as procedure bump is begin n := n + 2; end; end;")
        #expect(try await SQLExecutor.execute(doc, scope: .standard, in: ws) == false)
        #expect(doc.statusText?.hasPrefix("⚠️") == true && doc.statusText?.contains("ORA-04068") == true)
        #expect(try await SQLExecutor.execute(doc, scope: .standard, in: ws))
        _ = try await other.execute("drop package pelikan_state")
        await other.close()
        await ws.sessions.disconnectAll()
    }

    @Test("Test standardowy: zapis okna testu jako szablonu i zastosowanie do funkcji (%CALL%, zmienne szablonu)")
    func standardTest() async throws {
        let c = TestDatabase.config!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("std-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir, drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let other = try await TestDatabase.connect()
        _ = try await other.execute("create or replace function pelikan_twice(p_n number) return number is begin return p_n * 2; end;")
        let t = ws.newDocument(.test, text: "begin\n  dbms_output.put_line('start ' || :label);\n  %CALL%\nend;")
        t.testVariables = [TestVariable(name: "label", type: .string, value: "x")]
        _ = try await ws.invoke("test.saveAsStandard", CommandArguments(["name": "z etykietą"]))
        let r = try await ws.invoke("ob.standardTest", CommandArguments(["name": "z etykietą", "object": "pelikan_twice"]))
        let doc = try #require(ws.activeDocument)
        #expect(r.message != nil && doc.kind == .test && !doc.text.contains("%CALL%") && doc.text.lowercased().contains("pelikan_twice"))
        #expect(doc.text.contains("dbms_output.put_line('start ' || :label)"))
        #expect(doc.testVariables.contains { $0.name == "label" } && doc.testVariables.contains { $0.name.lowercased() == "p_n" })
        _ = try await other.execute("drop function pelikan_twice")
        await other.close()
        await ws.sessions.disconnectAll()
    }

    @Test("Menu połączenia: okno na połączeniu, pokaż i zamknij okna, ponowne połączenie, bieżący schemat")
    func connectionMenu() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        let args = CommandArguments(["connection": .string(def.id.uuidString), "kind": "sql"])
        _ = try await ws.invoke("connection.openWindow", args)
        _ = try await ws.invoke("connection.openWindow", args)
        let docs = ws.documents.filter { ws.effectiveConnection(of: $0) == def.id }
        #expect(docs.count == 2 && docs.allSatisfy(\.connectionPinned))
        ws.activate(docs[0].id)
        _ = try await ws.invoke("connection.showWindows", CommandArguments(["connection": .string(def.id.uuidString)]))
        #expect(ws.activeDocumentID == docs[1].id)
        _ = try await ws.session(for: docs[0])
        let r = try await ws.invoke("connection.reconnectWindows", CommandArguments(["connection": .string(def.id.uuidString)]))
        #expect(r.value == .int(1))
        let schema = try await ws.invoke("connection.setCurrentSchema", CommandArguments(["connection": .string(def.id.uuidString), "schema": .string(c.user.uppercased())]))
        #expect(schema.value == .string(c.user.uppercased()))
        await #expect(throws: (any Error).self) {
            try await ws.invoke("connection.setCurrentSchema", CommandArguments(["connection": .string(def.id.uuidString), "schema": "x; drop table emp"]))
        }
        let closed = try await ws.invoke("connection.closeWindows", CommandArguments(["connection": .string(def.id.uuidString)]))
        #expect(closed.value == .int(2) && ws.documents.allSatisfy { ws.effectiveConnection(of: $0) != def.id || !$0.connectionPinned })
        await ws.sessions.disconnectAll()
    }

    @Test("DBMS_TRACE w oknie testu: wywołania i wyjątki, historia przebiegów; uprawnienia debugera w oknie SQL")
    func trace() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let other = try await TestDatabase.connect()
        _ = try await other.execute("create or replace procedure pelikan_trc_p is begin null; end;")
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_trc_p;\n  begin raise no_data_found; exception when others then null; end;\nend;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        ws.activate(doc.id)
        _ = try await ws.invoke("test.trace", CommandArguments(["levels": "calls,exceptions"]))
        #expect(doc.traceLevel == [.allCalls, .allExceptions])
        _ = try await TestRunner.execute(doc, in: ws)
        #expect(doc.traceRun != nil && doc.traceEvents.contains { $0.unit.contains("PELIKAN_TRC_P") })
        #expect(doc.traceEvents.contains { $0.kind == "52" || $0.comment.lowercased().contains("exception") })
        let runs = try await ws.invoke("test.traceRuns")
        guard case .array(let list)? = runs.value else { Issue.record("brak historii"); return }
        #expect(!list.isEmpty)
        _ = try await ws.invoke("test.trace", CommandArguments(["levels": "off"]))
        #expect(doc.traceLevel == nil)
        let g = try await ws.invoke("debug.grantPrivileges")
        #expect(g.value.map { "\($0)".contains("debug connect session to \(c.user.uppercased())") } == true)
        _ = try await other.execute("drop procedure pelikan_trc_p")
        await other.close()
        await ws.sessions.disconnectAll()
    }
}
