import Foundation
@testable import PelikanSQL
import Testing

/// Poprawki układu formatera z rozpoznania (docs/research/formater.md, F1–F20; przypadki z korpusu
/// docs/research/formater/korpus.txt). Ustawienia domyślne, chyba że test mówi inaczej.
@Suite("Formater — poprawki układu")
struct BeautifierLayoutTests {
    func f(_ s: String, _ change: (inout BeautifierOptions) -> Void = { _ in }) throws -> String {
        var o = BeautifierOptions()
        change(&o)
        let out = try Beautifier.format(s, options: o)
        #expect(try Beautifier.format(out, options: o) == out, "nieidempotentne:\n\(out)")
        return out
    }

    @Test("F1: wszystkie instrukcje gałęzi WHEN … THEN obsługi wyjątków i instrukcji CASE z tym samym wcięciem")
    func branchBodies() throws {
        #expect(try f("begin null; exception when e1 or e2 then log(1); raise; when others then rollback; if a then b; else c; end if; end;") == """
            BEGIN
              NULL;
            EXCEPTION
              WHEN e1 OR e2 THEN
                log(1);
                RAISE;
              WHEN OTHERS THEN
                ROLLBACK;
                IF a THEN
                  b;
                ELSE
                  c;
                END IF;
            END;
            """)
        #expect(try f("begin case s when 'A' then x := 1; y := 2; else z := 3; exit when q; end case; end;") == """
            BEGIN
              CASE s
                WHEN 'A' THEN
                  x := 1;
                  y := 2;
                ELSE
                  z := 3;
                  EXIT WHEN q;
              END CASE;
            END;
            """)
    }

    @Test("F2: RETURN SELF AS RESULT w TYPE BODY nie otwiera deklaracji")
    func selfAsResult() throws {
        #expect(try f("create or replace type body t as constructor function t(a number) return self as result is begin return; end; end;\n/\n") == """
            CREATE OR REPLACE TYPE BODY t AS
              CONSTRUCTOR FUNCTION t(a NUMBER) RETURN SELF AS result IS
              BEGIN
                RETURN;
              END;
            END;
            /

            """)
    }

    @Test("F3: zapytanie kursora wcięte w nowej linii, widoku — w kolumnie instrukcji; WITH READ ONLY / CHECK OPTION")
    func queryAfterIsAs() throws {
        #expect(try f("declare cursor c(p number) is select a, b from t where x = p; begin null; end;") == """
            DECLARE
              CURSOR c(p NUMBER) IS
                SELECT a,
                       b
                FROM   t
                WHERE  x = p;
            BEGIN
              NULL;
            END;
            """)
        #expect(try f("create or replace view v as select a from t where b = 1 with read only;") == """
            CREATE OR REPLACE VIEW v AS
            SELECT a
            FROM   t
            WHERE  b = 1
            WITH READ ONLY;
            """)
        #expect(try f("create view v as with x as (select 1 a from dual) select a from x with check option;") == """
            CREATE VIEW v AS
            WITH   x AS (SELECT 1 a
                         FROM   dual)
            SELECT a
            FROM   x
            WITH CHECK OPTION;
            """)
    }

    @Test("F4: UNION ALL / MINUS w osobnej linii, następne zapytanie formatowane; SEARCH i CYCLE w CTE rekurencyjnym")
    func setOperators() throws {
        #expect(try f("select a, b from t union all select c, d from u minus select e, f from w order by 1;") == """
            SELECT a,
                   b
            FROM   t
            UNION ALL
            SELECT c,
                   d
            FROM   u
            MINUS
            SELECT e,
                   f
            FROM   w
            ORDER BY 1;
            """)
        let out = try f("with h (id, lvl) as (select id, 1 from t union all select t.id, h.lvl + 1 from t join h on t.p = h.id) search depth first by id set o cycle id set c to 'Y' default 'N' select id from h;")
        #expect(out.contains("                      UNION ALL\n                      SELECT t.id,\n"))
        #expect(out.hasSuffix(")\n       SEARCH DEPTH FIRST BY id SET o\n       CYCLE id SET c TO 'Y' DEFAULT 'N'\nSELECT id\nFROM   h;"))
    }

    @Test("F5: AND w warunku JOIN … ON pod ON, nie w kolumnie klauzul")
    func joinConditions() throws {
        #expect(try f("select a from t join u on u.id = t.id and u.x = 1 where t.y = 2;") == """
            SELECT a
            FROM   t
            JOIN   u
              ON u.id = t.id
              AND u.x = 1
            WHERE  t.y = 2;
            """)
        #expect(try f("select a from t join u on u.id = t.id and u.x = 1;") { $0.andOrPosition = .lineEnd } == """
            SELECT a
            FROM   t
            JOIN   u
              ON u.id = t.id AND
                 u.x = 1;
            """)
    }

    @Test("F6: MERGE — ON i DELETE WHERE jako klauzule; INSERT ALL — WHEN/ELSE w kolumnie instrukcji")
    func mergeAndMultiInsert() throws {
        #expect(try f("merge into t using (select id, v from s) s on (t.id = s.id) when matched then update set t.v = s.v where t.v <> s.v delete where s.v is null when not matched then insert (id, v) values (s.id, s.v);") == """
            MERGE INTO t
            USING  (SELECT id,
                           v
                    FROM   s) s
            ON     (t.id = s.id)
            WHEN MATCHED THEN UPDATE
            SET    t.v = s.v
            WHERE  t.v <> s.v
            DELETE WHERE s.v IS NULL
            WHEN NOT MATCHED THEN INSERT (id, v)
            VALUES (s.id, s.v);
            """)
        #expect(try f("insert all when sal > 3000 then into hi (id) values (id) else into lo (id) values (id) select id, sal from emp;") == """
            INSERT ALL
            WHEN sal > 3000 THEN
            INTO   hi(id)
            VALUES (id)
            ELSE
            INTO   lo(id)
            VALUES (id)
            SELECT id,
                   sal
            FROM   emp;
            """)
    }

    @Test("F7: długie wyrażenie łamane przed ||, + albo - (nie w argumentach funkcji), kontynuacja pod prawą stroną :=")
    func longExpressions() throws {
        let out = try f("begin v := 'Klient: ' || v_customer_name || ', adres: ' || v_street || ' ' || v_house_no || ', ' || v_postcode || ' ' || v_city || ', tel: ' || nvl(v_phone, 'brak'); end;")
        #expect(out == """
            BEGIN
              v := 'Klient: ' || v_customer_name || ', adres: ' || v_street || ' ' || v_house_no || ', '
                   || v_postcode || ' ' || v_city || ', tel: ' || nvl(v_phone, 'brak');
            END;
            """)
        // Przy marginesie łamane tylko przed operatorem o najniższym priorytecie (nie przed *).
        let m = try f("begin x := aaaaaaaaaa * bbbbbbbbbb + cccccccccc * dddddddddd + eeeeeeeeee * ffffffffff; end;") { $0.rightMargin = 60 }
        #expect(m == "BEGIN\n  x := aaaaaaaaaa * bbbbbbbbbb + cccccccccc * dddddddddd\n       + eeeeeeeeee * ffffffffff;\nEND;")
    }

    @Test("F8: długi warunek IF/ELSIF/WHILE — AND/OR w nowej linii pod początkiem warunku; BETWEEN … AND bez łamania")
    func longConditions() throws {
        let out = try f("begin if v_suma > c_limit and p_tryb = 'N' and p_data between 1 and 10 or p_procent is null and g_licznik < 10 then null; end if; end;") { $0.rightMargin = 60 }
        #expect(out == """
            BEGIN
              IF v_suma > c_limit AND p_tryb = 'N'
                 AND p_data BETWEEN 1 AND 10 OR p_procent IS NULL
                 AND g_licznik < 10 THEN
                NULL;
              END IF;
            END;
            """)
    }

    @Test("F9: długi nagłówek wyzwalacza w osobnych liniach; COMPOUND TRIGGER z sekcjami punktów czasowych")
    func triggers() throws {
        #expect(try f("create or replace trigger t_biu before insert or update of qty, price on order_items referencing old as o new as n for each row when (n.qty > 0) begin null; end;\n/\n") == """
            CREATE OR REPLACE TRIGGER t_biu
              BEFORE INSERT OR UPDATE OF qty, price
              ON order_items
              REFERENCING old AS o new AS n
              FOR EACH ROW
              WHEN (n.qty > 0)
            BEGIN
              NULL;
            END;
            /

            """)
        #expect(try f("create or replace trigger c for insert on t compound trigger g number; before statement is begin g := 0; end before statement; after each row is begin g := g + 1; end after each row; end c;\n/\n") == """
            CREATE OR REPLACE TRIGGER c FOR INSERT ON t
            COMPOUND TRIGGER
              g NUMBER;
              BEFORE STATEMENT IS
              BEGIN
                g := 0;
              END BEFORE STATEMENT;
              AFTER EACH ROW IS
              BEGIN
                g := g + 1;
              END AFTER EACH ROW;
            END c;
            /

            """)
    }

    @Test("F10: CREATE TABLE — klauzule fizyczne w nowych liniach, gdy się nie mieszczą; krótkie zostają w linii")
    func tableOptions() throws {
        let out = try f("create table t (a number(10), b varchar2(30)) tablespace data_ts pctfree 10 storage (initial 1m next 1m) partition by range (a) interval (1000) (partition p0 values less than (1000));")
        #expect(out == """
            CREATE TABLE t(a NUMBER(10), b VARCHAR2(30))
            TABLESPACE data_ts
            PCTFREE 10
            STORAGE (INITIAL 1m NEXT 1m)
            PARTITION BY RANGE (a) INTERVAL (1000) (PARTITION p0 VALUES LESS THAN (1000));
            """)
        #expect(try f("create index ix on t(a) tablespace idx_ts compress 1;") == "CREATE INDEX ix ON t(a) TABLESPACE idx_ts COMPRESS 1;")
    }

    @Test("F11: DML po nagłówku FORALL w nowej linii, sformatowany")
    func forall() throws {
        #expect(try f("begin forall i in 1 .. l.count save exceptions update t set a = l(i).a where id = l(i).id; end;") == """
            BEGIN
              FORALL i IN 1..l.count SAVE EXCEPTIONS
                UPDATE t
                SET    a = l(i).a
                WHERE  id = l(i).id;
            END;
            """)
    }

    @Test("F12: komentarz -- przy swoim elemencie listy, przecinek nie sam w linii (przecinek na końcu i na początku)")
    func commentsInLists() throws {
        let src = "select a, -- pierwszy\nb -- drugi\n, c from t;"
        #expect(try f(src) == "SELECT a, -- pierwszy\n       b, -- drugi\n       c\nFROM   t;")
        #expect(try f(src) { $0.commaBefore = true } == "SELECT a -- pierwszy\n     , b -- drugi\n     , c\nFROM   t;")
        // Przecinek przeniesiony na drugą stronę komentarza — równoważny dla weryfikacji; zmiana tokenu nie.
        try Beautifier.verify(original: "select a -- k\n, b from t", formatted: "select a, -- k\nb from t")
        #expect(throws: BeautifierError.self) { try Beautifier.verify(original: "select a -- k\n, b from t", formatted: "select a -- k\nb, from t") }
    }

    @Test("F13: rozmiar typu i argumenty PRAGMA nie są łamane przy „element w linii”")
    func typeSizes() throws {
        let out = try f("declare v number(14,2); e exception; pragma exception_init(e, -54); begin p(a, b); end;") { $0.callParameters = .onePerLine }
        #expect(out == """
            DECLARE
              v NUMBER(14, 2);
              e EXCEPTION;
              PRAGMA EXCEPTION_INIT(e, -54);
            BEGIN
              p(a,
                b);
            END;
            """)
    }

    @Test("F14: słowa kluczowe niezastrzeżone jako nazwy — wielkość jak identyfikator; atrybuty kursora i słowa DDL — jak słowa kluczowe")
    func keywordsAsNames() throws {
        #expect(try f("select h.path, trunc(d) day, path from hier h where c%notfound;") == "SELECT h.path,\n       trunc(d) day,\n       path\nFROM   hier h\nWHERE  c%NOTFOUND;")
        #expect(try f("with h (id, path) as (select 1, 'x' from dual) select id from h;").hasPrefix("WITH   h(id, path) AS"))
        #expect(try f("create bitmap index ix on t(a) local parallel 4;") == "CREATE BITMAP INDEX ix ON t(a) LOCAL PARALLEL 4;")
        #expect(try f("begin l.delete; x := l.first; end;") == "BEGIN\n  l.delete;\n  x := l.first;\nEND;")
    }

    @Test("F15: spacja przed nawiasem po WITHIN GROUP, GROUPING SETS, STORAGE, ADD, UPDATE (GRANT); metoda kolekcji bez spacji")
    func spacesBeforeParen() throws {
        #expect(try f("select listagg(a, ',') within group (order by a) from t group by grouping sets ((a), ());")
            == "SELECT listagg(a, ',') WITHIN GROUP (ORDER BY a)\nFROM   t\nGROUP BY GROUPING SETS ((a), ());")
        #expect(try f("alter table t add (a number);") == "ALTER TABLE t ADD (a NUMBER);")
        #expect(try f("grant select, update (a, b) on t to r;") == "GRANT SELECT, UPDATE (a, b) ON t TO r;")
        #expect(try f("begin if l.exists(1) then l.delete(1); end if; end;").contains("IF l.exists(1) THEN\n    l.delete(1);"))
        #expect(try f("create type t as varray(10) of number;") == "CREATE TYPE t AS VARRAY(10) OF NUMBER;")
    }

    @Test("F16: INSERT z hintem — INTO w linii INSERT; RETURNING … INTO jako jedna klauzula")
    func insertHintAndReturning() throws {
        #expect(try f("insert /*+ append */ into t select * from s;") == "INSERT /*+ append */ INTO t\nSELECT *\nFROM   s;")
        #expect(try f("begin update t set a = 1 where b = 2 returning c bulk collect into l; end;") == """
            BEGIN
              UPDATE t
              SET    a = 1
              WHERE  b = 2
              RETURNING c BULK COLLECT INTO l;
            END;
            """)
    }

    @Test("F17: etykieta <<nazwa>> bez spacji w osobnej linii; nazwa w EXIT/END LOOP jak identyfikator")
    func labels() throws {
        #expect(try f("begin <<outer>> for i in 1 .. 2 loop exit outer when i > 1; end loop outer; end;") == """
            BEGIN
              <<outer>>
              FOR i IN 1..2 LOOP
                EXIT outer WHEN i > 1;
              END LOOP outer;
            END;
            """)
    }

    @Test("F19: pisownia specjalna ze wzorcem % i *")
    func specialCasePatterns() throws {
        #expect(try f("select dba_tables.x from dba_tables, user_objects;") { $0.specialCase = ["DBA_%", "*_Objects"] }
            == "SELECT DBA_tables.x\nFROM   DBA_tables,\n       user_Objects;")
    }

    @Test("F20: CROSS/OUTER APPLY jak złączenie, PIVOT w nowej linii")
    func applyAndPivot() throws {
        #expect(try f("select d.a, x.b from d cross apply (select b from e where e.id = d.id) x;") == """
            SELECT d.a,
                   x.b
            FROM   d
            CROSS APPLY (SELECT b
                         FROM   e
                         WHERE  e.id = d.id) x;
            """)
        #expect(try f("select * from (select a, b from t) pivot (sum(a) for b in (1 as one, 2 as two));") == """
            SELECT *
            FROM   (SELECT a,
                           b
                    FROM   t)
            PIVOT  (sum(a) FOR b IN (1 AS one, 2 AS two));
            """)
    }
}
