import Foundation
@testable import PelikanSQL
import Testing

/// Domyślne zachowanie formatera wg decyzji właściciela (D202): przecinek na końcu, listy element w linii, IN/VALUES
/// w jednej linii, jeśli się mieszczą, CASE wieloliniowo (krótkie w linii), podzapytania wcięte z „)” w osobnej linii,
/// słowa klauzul i AND/OR „rzeką”, `INSERT INTO t (…)`, `DELETE FROM`, kolumny tabel w linii z wyrównaniem typów,
/// DEFAULT i NOT NULL, wyrównanie deklaracji i przypisań; reguły AND/OR osobno dla każdego miejsca warunku.
@Suite("Formater — ustawienia domyślne D202")
struct BeautifierDefaultsTests {
    func f(_ s: String, _ change: (inout BeautifierOptions) -> Void = { _ in }) throws -> String {
        var o = BeautifierOptions()
        change(&o)
        let out = try Beautifier.format(s, options: o)
        #expect(try Beautifier.format(out, options: o) == out, "nieidempotentne:\n\(out)")
        return out
    }

    @Test("SQL: rzeka, element w linii, przecinek na końcu, krótkie CASE i IN w linii, długie CASE wieloliniowo")
    func queries() throws {
        #expect(try f("select a, b from t where x = 1 and y = 2 order by a, b;") == """
            SELECT a,
                   b
              FROM t
             WHERE x = 1
               AND y = 2
            ORDER BY a,
                     b;
            """)
        #expect(try f("select case when a = 1 then 'x' else 'y' end b, case when a = 1 then 'x' when a = 2 then 'y' end c from t where a in (1, 2, 3);") == """
            SELECT CASE WHEN a = 1 THEN 'x' ELSE 'y' END b,
                   CASE
                     WHEN a = 1 THEN 'x'
                     WHEN a = 2 THEN 'y'
                   END c
              FROM t
             WHERE a IN (1, 2, 3);
            """)
        // Próg krótkiego CASE.
        #expect(try f("select case when a = 1 then 'x' else 'y' end b from t;") { $0.caseInlineLimit = 20 }.contains("SELECT CASE\n         WHEN"))
    }

    @Test("podzapytanie wcięte, „)” w osobnej linii; INSERT INTO t (…), DELETE FROM w jednej linii")
    func subqueriesAndDML() throws {
        #expect(try f("select a from (select a from t) x;") == """
            SELECT a
              FROM (
                     SELECT a
                       FROM t
                   ) x;
            """)
        #expect(try f("select a from (select a from t) x;") { $0.subqueryLayout = .hanging } == "SELECT a\n  FROM (SELECT a\n          FROM t) x;")
        #expect(try f("insert into hr.t (a) values (1);\ndelete from t where a = 1;") == "INSERT INTO hr.t (a)\nVALUES (1);\nDELETE FROM t\n WHERE a = 1;")
        #expect(try f("update t set a = 1, b = 2;") { $0.setList = .fit } == "UPDATE t\n   SET a = 1, b = 2;")
    }

    @Test("DDL: kolumny w linii z wyrównaniem typu, DEFAULT i NOT NULL; krótki CHECK w linii")
    func tables() throws {
        #expect(try f("create table t (id number not null, nazwa varchar2(100) default 'x', constraint t_ck check (id > 0 and id < 10));") == """
            CREATE TABLE t (id    NUMBER NOT NULL,
                            nazwa VARCHAR2(100) DEFAULT 'x',
                            CONSTRAINT t_ck CHECK (id > 0 AND id < 10));
            """)
        #expect(try f("declare type r is record (a number, bbb date := sysdate); begin null; end;").contains("RECORD (a   NUMBER,\n                    bbb DATE := SYSDATE);"))
    }

    @Test("PL/SQL: wyrównanie deklaracji i przypisań; AND/OR „rzeką” w IF, ELSIF, WHILE, EXIT WHEN i WHEN instrukcji CASE")
    func plsql() throws {
        let src = """
            declare v_id number; v_nazwa varchar2(10) := 'x'; begin v_id := 1; v_nazwa := 'y'; \
            if v_id = 1 and v_nazwa = 'y' then null; elsif v_id = 2 or v_id = 3 then null; end if; \
            while v_id < 10 and v_nazwa is not null loop v_id := v_id + 1; exit when v_id > 5 or v_nazwa is null; end loop; \
            case when v_id = 1 and v_nazwa = 'y' then null; else null; end case; end;
            """
        #expect(try f(src) == """
            DECLARE
              v_id    NUMBER;
              v_nazwa VARCHAR2(10) := 'x';
            BEGIN
              v_id    := 1;
              v_nazwa := 'y';
              IF v_id = 1
             AND v_nazwa = 'y' THEN
                NULL;
              ELSIF v_id = 2
                 OR v_id = 3 THEN
                NULL;
              END IF;
              WHILE v_id < 10
                AND v_nazwa IS NOT NULL LOOP
                v_id := v_id + 1;
                EXIT WHEN v_id > 5
                       OR v_nazwa IS NULL;
              END LOOP;
              CASE
                WHEN v_id = 1
                 AND v_nazwa = 'y' THEN
                  NULL;
                ELSE
                  NULL;
              END CASE;
            END;
            """)
    }

    @Test("warunki: JOIN … ON, MERGE … ON, HAVING, START WITH / CONNECT BY — rzeka; nawias zagnieżdżony krótki w linii")
    func sqlConditions() throws {
        #expect(try f("select a from t join u on u.id = t.id and u.x = 1 where (t.a = 1 or t.b = 2) and t.c = 3 group by a having count(*) > 1 and sum(b) > 0;") == """
            SELECT a
              FROM t
              JOIN u
                ON u.id = t.id
               AND u.x = 1
             WHERE (t.a = 1 OR t.b = 2)
               AND t.c = 3
            GROUP BY a
            HAVING count(*) > 1
               AND sum(b) > 0;
            """)
        #expect(try f("merge into t using s on (t.id = s.id and t.x = s.x) when matched then update set t.v = s.v;") == """
            MERGE INTO t
             USING s
                ON (t.id = s.id
               AND t.x = s.x)
            WHEN MATCHED THEN UPDATE
               SET t.v = s.v;
            """)
        #expect(try f("select level from emp start with mgr is null and deptno = 10 connect by prior empno = mgr and level < 5;") == """
            SELECT LEVEL
              FROM emp
            START WITH mgr IS NULL
               AND deptno = 10
            CONNECT BY PRIOR empno = mgr
               AND LEVEL < 5;
            """)
    }

    @Test("reguły AND/OR miejsca: nie łam, tylko gdy się nie mieści, na końcu linii, pod pierwszym warunkiem, z wcięciem; nawias zagnieżdżony długi — „)” w osobnej linii")
    func conditionRules() throws {
        let q = "select a from t where x = 1 and y = 2;"
        #expect(try f(q) { $0.setCondition(.whereClause, .init(breaks: .never, align: .keyword)) } == "SELECT a\n  FROM t\n WHERE x = 1 AND y = 2;")
        #expect(try f(q) { $0.setCondition(.whereClause, .init(breaks: .ifLong, align: .keyword)) } == "SELECT a\n  FROM t\n WHERE x = 1 AND y = 2;")
        #expect(try f(q) { $0.setCondition(.whereClause, .init(breaks: .always, position: .lineEnd, align: .keyword)) }
            == "SELECT a\n  FROM t\n WHERE x = 1 AND\n       y = 2;")
        #expect(try f(q) { $0.setCondition(.whereClause, .init(breaks: .always, align: .firstCondition)) } == "SELECT a\n  FROM t\n WHERE x = 1\n       AND y = 2;")
        #expect(try f(q) { $0.setCondition(.whereClause, .init(breaks: .always, align: .indent)) } == "SELECT a\n  FROM t\n WHERE x = 1\n         AND y = 2;")
        let nested = try f("select a from t where (aaaaaaaaaa = 1111111111 and bbbbbbbbbb = 2222222222 or cccccccccc = 3333333333 and dddddddddd = 4444444444);") { $0.rightMargin = 60 }
        #expect(nested == """
            SELECT a
              FROM t
             WHERE (aaaaaaaaaa = 1111111111
                    AND bbbbbbbbbb = 2222222222
                    OR cccccccccc = 3333333333
                    AND dddddddddd = 4444444444
                   );
            """)
        // Ustawienia zapisane: brak reguły = domyślna; zapisana reguła wraca po odczycie.
        var o = BeautifierOptions()
        o.setCondition(.ifCondition, .init(breaks: .never, position: .lineEnd, align: .indent))
        let back = try JSONDecoder().decode(BeautifierOptions.self, from: JSONEncoder().encode(o))
        #expect(back.condition(.ifCondition) == .init(breaks: .never, position: .lineEnd, align: .indent))
        #expect(back.condition(.check) == BeautifierOptions.defaultCondition(.check))
    }

    @Test("listy w nawiasach do marginesu (Fit) i element w linii")
    func parenthesisLists() throws {
        let s = "select a from t where b in (1111111111, 2222222222, 3333333333, 4444444444, 5555555555, 6666666666);"
        #expect(try f(s) { $0.rightMargin = 50; $0.parenthesisLists = .wrap } == """
            SELECT a
              FROM t
             WHERE b IN (1111111111, 2222222222, 3333333333,
                         4444444444, 5555555555, 6666666666);
            """)
        #expect(try f("select a from t where b in (1, 2);") { $0.parenthesisLists = .onePerLine } == "SELECT a\n  FROM t\n WHERE b IN (1,\n             2);")
    }
}
