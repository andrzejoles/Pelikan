import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
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

    @Test("Rozwiń/Zwiń wszystko: gałęzie aktywnego okna planu; po zwinięciu zostaje korzeń, ponowny plan nie zmienia rozwinięcia")
    @MainActor func expandCollapse() async throws {
        func line(_ id: Int, _ parent: Int?) -> PlanLine {
            PlanLine(id: id, parentID: parent, depth: 0, position: id, operation: "OP\(id)", options: "", objectOwner: "", objectName: "", optimizer: "",
                     accessPredicates: "", filterPredicates: "")
        }
        func plan(_ id: String, _ lines: [PlanLine]) -> ExplainPlanResult {
            let l = ExplainPlan.numberExecution(lines)
            return ExplainPlanResult(statementID: id, roots: ExplainPlan.tree(l), lines: l, text: "", html: "", xml: "")
        }
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.explainPlan, text: "select * from dual")
        ws.activate(doc.id)
        // Bez planu komendy niedostępne; w oknie SQL też.
        #expect(!ws.isEnabled("plan.expandAll") && !ws.isEnabled("plan.collapseAll"))
        // 0 ← 1 ← (2 ← 4, 3)
        doc.plan = plan("a", [line(0, nil), line(1, 0), line(2, 1), line(3, 1), line(4, 2)])
        #expect(ws.isEnabled("plan.expandAll"))
        _ = try await ws.invoke("plan.expandAll")
        #expect(doc.planExpanded == [0, 1, 2])
        _ = try await ws.invoke("plan.collapseAll")
        #expect(doc.planExpanded.isEmpty && doc.plan?.roots.map(\.id) == [0])
        // Ponowne wyznaczenie planu zachowuje rozwinięte gałęzie (jak dotąd w drzewie), nowe gałęzie zwinięte.
        doc.planExpanded = [0]
        doc.plan = plan("b", [line(0, nil), line(1, 0), line(2, 1)])
        #expect(doc.planExpanded == [0])
        // Inne okno aktywne — komendy nie działają na oknie planu w tle.
        let sql = ws.newDocument(.sql, text: "select 1 from dual")
        ws.activate(sql.id)
        #expect(!ws.isEnabled("plan.expandAll"))
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

@Suite("Test Manager bez bazy")
struct TestManagerOfflineTests {
    @Test("Oczekiwania i zmienne globalne")
    func expectations() {
        #expect(TestExpectation(.like, "ab%").matches("abc") && !TestExpectation(.like, "ab_").matches("abcd"))
        #expect(TestExpectation(.inList, "1, 2,3").matches("2") && !TestExpectation(.inList, "1,2").matches("3"))
        #expect(TestExpectation(.isNull).matches(nil) && TestExpectation(.isNotNull).matches("x"))
        #expect(TestManager.resolve("&A-&AB", globals: ["A": "1", "AB": "2"]) == "1-2")
        // Wielolinijkowe DBMS_OUTPUT: `%` obejmuje znaki nowej linii.
        #expect(TestExpectation(.like, "a%c").matches("a\nb\nc") && TestExpectation(.like, "a_c").matches("a\nc"))
        #expect(!TestExpectation(.like, "A%").matches("abc"))
    }

    @Test("Tryb jednej sesji: test w osobnej sesji, wycofany i zamknięty; sesja główna nietknięta, bez AutoCommit")
    @MainActor func ownSession() async throws {
        let driver = FakeDriver()
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: driver])
        ws.settings.sessionMode = .single
        ws.settings.autoCommitTestWindow = true
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        let main = try #require(try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main)) as? FakeSession)
        let r = await TestManager.run(TestCase(name: "t", block: "begin null; end;"), globals: [:], connectionID: def.id, in: ws)
        #expect(r.passed)
        #expect(!main.closedFlag.withLock { $0 } && main.transactions.withLock { $0 }.isEmpty)
        #expect(!main.executed.withLock { $0 }.contains("begin null; end;"))
        let sessions = driver.sessions.withLock { $0 }
        #expect(sessions.count == 2)
        let own = try #require(sessions.last)
        #expect(own.executed.withLock { $0 }.contains("begin null; end;"))
        #expect(own.transactions.withLock { $0 } == ["rollback"] && own.closedFlag.withLock { $0 })
        #expect(ws.sessions.openSessionCount == 1)
    }
}

@Suite("Maska plików okna poleceń")
struct FileMaskTests {
    @Test("* i ? bez wielkości liter")
    @MainActor func mask() {
        #expect(SQLPlusEngine.matches("*.SQL", "a.sql") && SQLPlusEngine.matches("a?c.txt", "abc.txt") && !SQLPlusEngine.matches("*.pck", "a.sql"))
        #expect(!SQLPlusEngine.matches("a.b", "aXb"))
    }
}
