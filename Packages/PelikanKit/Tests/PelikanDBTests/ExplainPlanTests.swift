import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Explain Plan na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ExplainPlanDBTests {
    @Test("F5 z okna SQL: okno planu z drzewem, kolejnością wykonania i formatami; cel optymalizatora; transakcja okna nietknięta")
    func explain() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let sql = ws.newDocument(.sql, text: "select e.ename, d.dname from emp e join dept d on d.deptno = e.deptno where e.sal > 1000;\nselect 1 from dual;")
        sql.connectionID = def.id
        sql.selectedRange = 5..<5
        try await ws.invoke("tools.explainPlan")
        let doc = try #require(ws.documents.last)
        #expect(doc.kind == .explainPlan && !doc.text.hasSuffix(";") && doc.text.contains("join dept"))
        let plan = try #require(doc.plan)
        #expect(plan.lines.count >= 3 && plan.roots.count == 1 && plan.roots[0].operation == "SELECT STATEMENT")
        #expect(plan.executionOrder.last?.id == 0 && plan.lines.contains { $0.objectName == "EMP" })
        #expect(plan.text.contains("Plan hash value") && plan.html.lowercased().contains("<html") && plan.xml.contains("<plan"))
        doc.planGoal = .firstRows1
        ws.activate(doc.id)
        try await ws.invoke("tools.explainPlan")
        #expect(doc.plan?.lines.first?.optimizer.contains("FIRST_ROWS") == true)
        await ws.sessions.disconnectAll()
    }
}
