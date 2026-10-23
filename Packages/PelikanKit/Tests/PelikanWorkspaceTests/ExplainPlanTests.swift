import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Explain Plan bez bazy")
struct ExplainPlanOfflineTests {
    @Test("Zmienne PL/SQL → wiązane, bez INTO i RETURNING, bez średnika; pola rekordów bez zmian")
    func prepare() {
        let body = """
            create or replace procedure p(p_dept number) is
              l_count number;
              r emp%rowtype;
            begin
              select count(*) into l_count from emp where deptno = p_dept and sal > r.sal;
              update emp set sal = sal where empno = l_count returning sal into l_count;
            end;
            """
        let ns = body as NSString
        let sel = ns.range(of: "select count(*)")
        let q = ExplainPlan.prepare("select count(*) into l_count from emp where deptno = p_dept and sal > r.sal;", plsqlContext: body, offset: sel.location)
        #expect(q == "select count(*) from emp where deptno = :p_dept and sal > r.sal")
        let u = ExplainPlan.prepare("update emp set sal = sal where empno = l_count returning sal into l_count", plsqlContext: body, offset: ns.range(of: "update emp").location)
        #expect(u == "update emp set sal = sal where empno = :l_count")
        #expect(ExplainPlan.prepare("select * from emp;") == "select * from emp")
        #expect(ExplainPlan.withGoal("with x as (select 1 a from dual) select * from x", .firstRows10) == "with x as (select 1 a from dual) select /*+ FIRST_ROWS(10) */ * from x")
    }

    @Test("Kolejność wykonania post-order i drzewo")
    func order() {
        func line(_ id: Int, _ parent: Int?, _ pos: Int) -> PlanLine {
            PlanLine(id: id, parentID: parent, depth: 0, position: pos, operation: "OP\(id)", options: "", objectOwner: "", objectName: "", optimizer: "",
                     accessPredicates: "", filterPredicates: "")
        }
        // 0 SELECT ← 1 HASH JOIN ← (2 TABLE A, 3 TABLE B)
        let lines = ExplainPlan.numberExecution([line(0, nil, 0), line(1, 0, 1), line(2, 1, 1), line(3, 1, 2)])
        #expect(lines.sorted { $0.executionOrder < $1.executionOrder }.map(\.id) == [2, 3, 1, 0])
        #expect(ExplainPlan.tree(lines).first?.children?.first?.children?.map(\.id) == [2, 3])
    }
}

@Suite("Narzędzia siatki bez bazy")
struct GridToolsOfflineTests {
    @Test("Zapytanie standardowe z SQL i dla obiektu; nazwy plików z szablonu bez znaków niedozwolonych")
    func offline() {
        let q = StandardQuery.from(sql: "select * from scott.emp where sal > 0", owner: "SCOTT", table: "EMP", name: "x")
        #expect(q.sql == "select * from [owner].[table] where sal > 0")
        #expect(StandardQuery(name: "a", sql: "select [columns] from [owner].[table] t").text(owner: "SCOTT", table: "EMP", columns: ["EMPNO", "Mixed"])
            == "select t.EMPNO,\n       t.\"Mixed\" from SCOTT.EMP t")
        #expect(GridTools.fileName("[NAME]/[#].txt", values: ["NAME": "a:b"], index: 3) == "a_b_3.txt")
        #expect(GridTools.fileName("[X]", values: ["X": ".hidden"], index: 1) == "_hidden")
    }
}
