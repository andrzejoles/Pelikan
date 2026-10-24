import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Test Manager na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct TestManagerTests {
    func set() -> TestSet {
        var s = TestSet(name: "Przykład")
        s.globals = ["DZIAL": "10"]
        s.cases = [
            TestCase(name: "Suma", block: "begin :r := 2 + 2; end;", variables: [TestCaseVariable(name: "r", type: .integer, expected: TestExpectation(.equals, "4"))]),
            TestCase(name: "Zły wzorzec", block: "begin :r := 'abc'; end;", variables: [TestCaseVariable(name: "r", type: .string, expected: TestExpectation(.like, "x%"))]),
            {
                var c = TestCase(name: "Globalna i wyjście", block: "begin select count(*) into :n from emp where deptno = :d; dbms_output.put_line('dział ' || :d); end;",
                                 variables: [TestCaseVariable(name: "d", type: .integer, input: "&DZIAL"),
                                             TestCaseVariable(name: "n", type: .integer, expected: TestExpectation(.isNotNull))])
                c.expectedOutput = "dział 10%"
                return c
            }(),
        ]
        return s
    }

    @Test("Zestaw: oczekiwania =, LIKE, NOT NULL, zmienna globalna, DBMS_OUTPUT; zapis i RUNTESTSET w oknie poleceń")
    func run() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let results = await TestManager.run(set(), connectionID: def.id, in: ws)
        #expect(results.map(\.passed) == [true, false, true], "\(results.map(\.failures))")
        #expect(results[1].failures.first?.contains("LIKE x%") == true)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-\(UUID().uuidString.prefix(6)).pts")
        defer { try? FileManager.default.removeItem(at: file) }
        try set().encoded().write(to: file)
        let doc = ws.newDocument(.command)
        doc.connectionID = def.id
        _ = await ws.sqlplusEngine(for: doc).run("runtestset \(file.path)")
        #expect(doc.console.contains { $0.text.contains("udane: 2, nieudane: 1") }, "\(doc.console.map(\.text))")
        await ws.sessions.disconnectAll()
    }
}
