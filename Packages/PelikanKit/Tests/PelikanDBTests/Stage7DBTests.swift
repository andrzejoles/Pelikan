import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Etap 7 na bazie testowej: SQLFORMAT, filtr siatki, SQL z wierszy, kod z obiektu", .enabled(if: TestDatabase.isAvailable), .serialized)
struct Stage7DBTests {
    func workspace() throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    @Test("SET SQLFORMAT csv/json/insert w oknie poleceń, SHOW SQLFORMAT, powrót do domyślnego")
    func sqlFormat() async throws {
        let (ws, id) = try workspace()
        let doc = ws.newDocument(.command)
        doc.connectionID = id
        let e = ws.sqlplusEngine(for: doc)
        _ = await e.run("""
            set sqlformat csv
            select deptno, dname from dept where deptno = 10;
            set sqlformat json
            select deptno from dept where deptno = 10;
            set sqlformat insert
            select deptno, dname from dept where deptno = 10;
            show sqlformat
            set sqlformat default
            """)
        let out = doc.console.map(\.text)
        #expect(out.contains("\"DEPTNO\",\"DNAME\"") && out.contains { $0.hasPrefix("10,\"") }, "\(out)")
        #expect(out.contains { $0.contains("\"items\":[") } && out.contains { $0.contains("{\"deptno\":10}") })
        #expect(out.contains { $0.hasPrefix("INSERT INTO DEPT (DEPTNO,DNAME) VALUES (10,") })
        #expect(out.contains("SQL Format: insert") && e.state.sqlFormat == nil)
        await ws.sessions.disconnectAll()
    }

    @Test("Filtr i grupowanie na wyniku, SQL z wierszy po kluczu głównym, kod z tabeli i wywołanie procedury")
    func gridAndCode() async throws {
        let (ws, id) = try workspace()
        let doc = ws.newDocument(.sql, text: "select empno, ename, deptno from emp order by empno")
        doc.connectionID = id
        _ = try await SQLExecutor.execute(doc, scope: .allStatements, in: ws)
        let tab = try #require(doc.results.first)
        let grid = try #require(tab.grid)
        try await ws.invoke("grid.filterExpression", CommandArguments(["expression": "DEPTNO = 10"]))
        #expect(grid.rowCount > 0 && (0..<grid.rowCount).allSatisfy { grid.text(row: $0, column: 2) == "10" })
        let groups = try await ws.invoke("grid.groupBy", CommandArguments(["column": "DEPTNO"]))
        #expect(groups.value?.arrayValue?.count == 1)
        try await ws.invoke("grid.clearFilter")
        tab.selectedRows = [0]
        ws.activate(doc.id)
        let upd = try await ws.invoke("grid.generateSQL", CommandArguments(["kind": "update"]))
        #expect(upd.value?.stringValue?.contains("WHERE EMPNO = ") == true)
        let sel = try await ws.invoke("ob.generateCode", CommandArguments(["object": "dept", "kind": "select", "newWindow": true]))
        #expect(sel.value?.stringValue?.contains("WHERE DEPTNO = :deptno") == true)
        let call = try await ws.invoke("ob.generateCode", CommandArguments(["object": "emp_api", "type": "PACKAGE", "kind": "call", "member": "GET_SALARY", "newWindow": true]))
        #expect(call.value?.stringValue?.lowercased().contains("emp_api.get_salary") == true)
        await ws.sessions.disconnectAll()
    }
}
