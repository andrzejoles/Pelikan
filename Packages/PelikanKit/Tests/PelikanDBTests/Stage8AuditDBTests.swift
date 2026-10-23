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
}
