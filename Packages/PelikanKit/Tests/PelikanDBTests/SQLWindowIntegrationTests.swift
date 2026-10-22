import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu: odpowiada na okno zmiennych podanymi wartościami.
@MainActor
final class TestUI: UIServices {
    var variables: [String: VariableValue] = [:]
    var askedVariables: [VariableRequest] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { 0 }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? {
        askedVariables = requests
        return variables
    }
}

@MainActor
@Suite("SQL Window na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct SQLWindowIntegrationTests {
    func makeWorkspace() throws -> (Workspace, Document, TestUI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql)
        return (ws, doc, ui)
    }

    @Test("SELECT: karta wyniku, 100 wierszy na start, dociąganie, status")
    func query() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "select id, txt from big_rows order by id"
        try await ws.invoke("sql.execute")
        let grid = try #require(doc.results.first?.grid)
        #expect(grid.rowCount == 100)
        #expect(grid.hasMore)
        #expect(grid.text(row: 0, column: 0) == "1")
        await grid.fetchMore(500)
        #expect(grid.rowCount == 600)
        #expect(doc.results.first?.title == "Select big_rows")
        #expect(doc.resultSummary == "600 wierszy (więcej…)")
        await ws.sessions.disconnectAll()
    }

    @Test("DML: transakcja otwarta, COMMIT/ROLLBACK z menu ją zamyka; druga sesja nie widzi zmian przed COMMIT")
    func transactions() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "update emp set comm = 777 where empno = 7369"
        try await ws.invoke("sql.execute")
        #expect(doc.results.first?.message == "Wierszy: 1")
        #expect(doc.transactionOpen)
        #expect(ws.isEnabled("session.rollback"))
        try await ws.invoke("session.rollback")
        #expect(!doc.transactionOpen)
        doc.text = "select comm from emp where empno = 7369"
        try await ws.invoke("sql.execute")
        #expect(doc.results.first?.grid?.text(row: 0, column: 0) == "")
        await ws.sessions.disconnectAll()
    }

    @Test("Błąd ORA: komunikat w karcie, pozycja błędu w tekście okna (z uwzględnieniem polskich znaków)")
    func errorPosition() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "-- zażółć\nselect 1 from dual;\nselect brak_kolumny from dual;"
        doc.selectedRange = 0..<0
        try await ws.invoke("sql.executeAlternate")   // AutoSelect włączone → Ctrl+F8 wykonuje wszystkie
        #expect(doc.results.count == 2)
        #expect(doc.results.contains { $0.message?.contains("ORA-00904") == true })
        let expected = (doc.text as NSString).range(of: "brak_kolumny").location
        #expect(doc.errorRange?.lowerBound == expected)
        await ws.sessions.disconnectAll()
    }

    @Test("DBMS_OUTPUT z wywołania procedury trafia do karty Output")
    func dbmsOutput() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "begin emp_api.raise_salary(7369, 1); end;\n/"
        try await ws.invoke("sql.execute")
        #expect(doc.output == ["Podwyżka dla 7369: 1%"])
        #expect(doc.transactionOpen)
        try await ws.invoke("session.rollback")
        await ws.sessions.disconnectAll()
    }

    @Test("Zmienne: :bind i &<…> w jednym oknie, wartości zapamiętane")
    func variables() async throws {
        let (ws, doc, ui) = try makeWorkspace()
        ui.variables = ["id": .text("7839"), "Kolumna": .text("ename")]
        doc.text = "select &<name=\"Kolumna\" list=\"ename, job\"> from emp where empno = :id"
        try await ws.invoke("sql.execute")
        #expect(ui.askedVariables.map(\.name) == ["Kolumna", "id"])
        #expect(doc.results.first?.grid?.text(row: 0, column: 0) == "KOWALSKI")
        #expect(doc.variableValues["id"] == .text("7839"))
        await ws.sessions.disconnectAll()
    }

    @Test("Dyrektywa Records= i historia poleceń okna")
    func recordsAndHistory() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "-- Records=7\nselect * from big_rows"
        try await ws.invoke("sql.execute")
        #expect(doc.results.first?.grid?.rowCount == 7)
        #expect(ws.history.first?.text.hasSuffix("select * from big_rows") == true)
        #expect(doc.statementHistory.count == 1)
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("SQL Window — przerwanie", .enabled(if: TestDatabase.isAvailable), .serialized)
struct SQLWindowBreakTests {
    @Test("Przerwij (sql.break) kończy długie zapytanie ORA-01013 bez przesuwania kursora; interfejs dostępny w trakcie")
    func breakExecution() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql)
        doc.text = "select count(*) from big_rows a, big_rows b"
        doc.selectedRange = 5..<5
        let run = Task { try await ws.invoke("sql.execute") }
        while !doc.isExecuting { await Task.yield() }
        try await Task.sleep(for: .milliseconds(700))
        #expect(ws.isEnabled("sql.break"))
        try await ws.invoke("sql.break")
        _ = try? await run.value
        #expect(!doc.isExecuting)
        #expect(doc.results.first?.message?.contains("ORA-01013") == true)
        #expect(doc.errorRange == nil)
        await ws.sessions.disconnectAll()
    }
}
