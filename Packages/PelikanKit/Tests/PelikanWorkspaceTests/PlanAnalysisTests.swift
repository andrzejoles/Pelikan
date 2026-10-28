import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Etap 7 bez bazy: plany, DBA, zadania w tle")
struct PlanAnalysisTests {
    func line(_ id: Int, _ parent: Int?, _ depth: Int, _ op: String, cost: Int64?, card: Int64? = nil, object: String = "") -> PlanLine {
        var l = PlanLine(id: id, parentID: parent, depth: depth, position: id, operation: op, options: "", objectOwner: "", objectName: object, optimizer: "",
                         cost: cost, cardinality: card, accessPredicates: "", filterPredicates: "")
        l.executionOrder = 0
        return l
    }

    var plan: [PlanLine] {
        ExplainPlan.numberExecution([line(0, nil, 0, "SELECT STATEMENT", cost: 10), line(1, 0, 1, "HASH JOIN", cost: 10),
                                     line(2, 1, 2, "TABLE ACCESS", cost: 2, card: 4, object: "DEPT"), line(3, 1, 2, "TABLE ACCESS", cost: 6, card: 14, object: "EMP")])
    }

    @Test("Diagram: wiersz na węzeł, kolumna = głębokość; flame graph proporcjonalny do kosztu")
    func diagramAndFlame() {
        let roots = ExplainPlan.tree(plan)
        let nodes = PlanGraph.layout(roots)
        #expect(nodes.map(\.id) == [0, 1, 2, 3] && nodes.map(\.column) == [0, 1, 2, 2] && nodes[3].parentID == 1)
        let bars = PlanGraph.flame(roots)
        let dept = bars.first { $0.id == 2 }!, emp = bars.first { $0.id == 3 }!
        #expect(bars.first { $0.id == 0 }?.width == 1)
        #expect(abs(dept.width - 0.2) < 1e-9 && abs(emp.width - 0.6) < 1e-9 && abs(emp.start - 0.2) < 1e-9)
        // Bez kosztów — równy podział.
        let noCost = PlanGraph.flame(ExplainPlan.tree([line(0, nil, 0, "A", cost: nil), line(1, 0, 1, "B", cost: nil), line(2, 0, 1, "C", cost: nil)]))
        #expect(noCost.filter { $0.depth == 1 }.allSatisfy { abs($0.width - 0.5) < 1e-9 })
    }

    @Test("Porównanie planów: zmieniony koszt, dodana i usunięta operacja")
    func compare() {
        var right = plan
        right[3].cost = 9
        right.append(line(4, 1, 2, "INDEX RANGE SCAN", cost: 1, object: "EMP_IX"))
        let left = plan.filter { $0.id != 2 }
        let c = PlanCompare.compare(left, ExplainPlan.numberExecution(right))
        #expect(c.rows.contains { $0.status == .onlyRight && $0.right?.objectName == "DEPT" })
        #expect(c.rows.contains { $0.status == .onlyRight && $0.right?.objectName == "EMP_IX" })
        #expect(c.rows.contains { $0.status == .changed && $0.right?.objectName == "EMP" && $0.differences.contains { $0.contains("koszt 6 → 9") } })
        #expect(PlanCompare.compare(plan, plan).rows.allSatisfy { $0.status == .same })
    }

    @Test("Autotrace: wskazówka i znacznik, różnica statystyk (kluczowe pierwsze), rozbieżność szacunku")
    func autotraceHelpers() {
        let s = Autotrace.instrument("with x as (select 1 a from dual) select * from x", tag: "T1")
        #expect(s.contains("select /*+ GATHER_PLAN_STATISTICS */ /* T1 */ * from x"))
        let d = Autotrace.delta(before: ["consistent gets": 10, "x": 1, "y": 5], after: ["consistent gets": 15, "x": 1, "y": 9, "recursive calls": 2])
        #expect(d.map(\.name) == ["recursive calls", "consistent gets", "y"])
        let a = ActualPlanLine(id: 1, depth: 1, operation: "TABLE ACCESS", options: "FULL", object: "EMP", estimatedRows: 1, actualRows: 50, starts: 1)
        #expect(a.misestimated)
    }

    @Test("SQL zmian DBA: parametr (literał tylko dla tekstu), blokada konta, odrzucenie nieprawidłowych nazw")
    func dbaSQL() throws {
        #expect(try DBAPanel.alterParameterSQL(name: "open_cursors", value: "500") == "alter system set open_cursors = 500 scope = both")
        #expect(try DBAPanel.alterParameterSQL(name: "nls_date_format", value: "YYYY-MM-DD", scope: "SPFILE") == "alter system set nls_date_format = 'YYYY-MM-DD' scope = spfile")
        #expect(try DBAPanel.lockUserSQL("scott", lock: true) == "alter user SCOTT account lock")
        #expect(throws: CommandError.self) { try DBAPanel.lockUserSQL("x; drop user y", lock: false) }
        #expect(try DBAPanel.lockUserSQL("\"app_User\"", lock: false) == "alter user \"app_User\" account unlock")
        #expect(throws: CommandError.self) { try DBAPanel.alterParameterSQL(name: "a", value: "1", scope: "ALL") }
    }

    @Test("Task Monitor: zadanie zakończone, nieudane i anulowane")
    func tasks() async {
        let center = WorkspaceTaskCenter()
        let ok = center.run("ok", kind: "t") { t in t.progress = 1 }
        await center.wait(ok)
        let bad = center.run("bad", kind: "t") { _ in throw CommandError.notAvailable("boom") }
        await center.wait(bad)
        let long = center.run("long", kind: "t") { _ in try await Task.sleep(for: .seconds(30)) }
        long.cancel()
        await center.wait(long)
        #expect(ok.status == .succeeded && bad.status == .failed("boom") && long.status == .cancelled)
        #expect(center.tasks.map(\.title) == ["long", "bad", "ok"] && long.finished != nil)
        center.clearFinished()
        #expect(center.tasks.isEmpty)
    }

    @Test("Dokumentacja: znaki HTML i nazwy plików")
    func docHelpers() {
        #expect(SchemaDoc.esc("<a & \"b\">") == "&lt;a &amp; &quot;b&quot;&gt;")
        #expect(SchemaDoc.fileName("PACKAGE BODY", "EMP_API") == "package_body-emp_api.html")
        let special = SchemaDoc.fileName("PACKAGE BODY", "Emp$Api")
        #expect(special.hasPrefix("package_body-emp_api-") && special.hasSuffix(".html"))
        // Nazwy różniące się wielkością liter albo znakiem specjalnym — różne pliki (R7-20).
        let names = ["EMP", "Emp", "emp", "A$B", "A#B", "A_B"].map { SchemaDoc.fileName("TABLE", $0) }
        #expect(Set(names).count == names.count)
    }

    @Test("Autotrace przy wyłączonym podstawianiu: `&` bez pytania i bez zmian, zmienne wiązane z wartościami (jak okno SQL)")
    func autotraceVariables() {
        let sql = "select 'R&D', '&&x' from emp where deptno = :d and ename = :D"
        let off = Stage7PlanCommands.autotraceRequests(sql, substitution: false, remembered: ["d": .text("10")])
        #expect(off.map(\.name) == ["d"] && off.first?.kind == .bind && off.first?.value == .text("10"))
        let prepared = Stage7PlanCommands.autotracePrepared(sql, substitution: false, values: ["D": .text("10")])
        #expect(prepared.sql == sql)
        #expect(prepared.binds.map(\.name) == ["d"] && prepared.binds.first?.value == .text("10"))
        // Włączone podstawianie — pytanie także o `&` (jak dotąd).
        let on = Stage7PlanCommands.autotraceRequests(sql, substitution: true, remembered: [:])
        #expect(on.contains { $0.kind == .substitution })
    }
}
