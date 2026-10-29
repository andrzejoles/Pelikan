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

    @Test("słowo po kropce to nazwa: t.offset, t.fetch, t.window, r.end, r.when, r.loop — bez klauzul i bez odmowy")
    func wordsAfterDot() throws {
        #expect(try f("select t.offset, t.fetch, t.window from t where t.end = 1 order by t.when;") == """
            SELECT t.offset,
                   t.fetch,
                   t.window
              FROM t
             WHERE t.end = 1
             ORDER BY t.when;
            """)
        #expect(try f("begin r.end := 1; x := r.when; r.loop := r.if; end;") == "BEGIN\n  r.end  := 1;\n  x      := r.when;\n  r.loop := r.if;\nEND;")
    }

    @Test("$IF … $END w środku instrukcji SQL nie kończy instrukcji")
    func directiveInsideStatement() throws {
        #expect(try f("select a from t where $if dbms_db_version.ver_le_12 $then b = 1 $else c = 2 $end and d = 3;") == """
            SELECT a
              FROM t
             WHERE $if dbms_db_version.ver_le_12 $then b = 1 $else c = 2 $end
               AND d = 3;
            """)
    }

    @Test("przecinek na początku linii: komentarz nie jest doklejany do linii kończącej się komentarzem")
    func commaBeforeAfterComment() throws {
        #expect(try f("select a -- k1\n, -- k2\nb from t;") { $0.commaBefore = true } == "SELECT a -- k1\n     , -- k2\n       b\n  FROM t;")
        #expect(PelikanSQL.Formatter.endsWithLineComment("a -- k") && !PelikanSQL.Formatter.endsWithLineComment("a = '--x'"))
    }

    @Test("AND w CASE w warunku IF — reguła CASE WHEN (krótki CASE w linii); AND z BETWEEN w argumencie nie przecieka")
    func caseInsideConditionAndBetween() throws {
        #expect(try f("begin if case when a = 1 and b = 2 then 1 else 0 end = 1 and c = 3 then null; end if; end;") == """
            BEGIN
              IF CASE WHEN a = 1 AND b = 2 THEN 1 ELSE 0 END = 1
             AND c = 3 THEN
                NULL;
              END IF;
            END;
            """)
        #expect(try f("select a from t where f(x between 1 and 2, y) = 1 and z = 2;") == """
            SELECT a
              FROM t
             WHERE f(x BETWEEN 1 AND 2, y) = 1
               AND z = 2;
            """)
    }

    @Test("rzeka z najdłuższego słowa klauzuli: RETURNING, CONNECT BY, INTERSECT; WITH i MERGE wyrównane w prawo")
    func riverWidth() throws {
        #expect(try f("update t set a = 1 where b = 2 returning a into x;") == """
               UPDATE t
                  SET a = 1
                WHERE b = 2
            RETURNING a INTO x;
            """)
        #expect(try f("select a from t start with p is null connect by prior id = p intersect select b from u;") == """
               SELECT a
                 FROM t
                START WITH p IS NULL
              CONNECT BY PRIOR id = p
            INTERSECT
               SELECT b
                 FROM u;
            """)
        #expect(try f("with x as (select 1 a from dual) select a from x;").hasPrefix("  WITH x AS (\n"))
        #expect(try f("merge into t using s on (t.id = s.id) when matched then update set t.v = s.v;") == """
             MERGE INTO t
             USING s
                ON (t.id = s.id)
              WHEN MATCHED THEN UPDATE
               SET t.v = s.v;
            """)
    }

    @Test("słowa DDL jak słowa kluczowe tylko w DDL; jako nazwy kolumn w zapytaniu — bez zmian")
    func contextualKeywords() throws {
        #expect(try f("select query, schema, statement from t;") == "SELECT query,\n       schema,\n       statement\n  FROM t;")
        let mv = try f("create materialized view mv build immediate refresh fast on demand as select a from t;")
        #expect(mv.contains("BUILD IMMEDIATE") && mv.contains("REFRESH FAST ON DEMAND"))
    }

    @Test("migracja zapisu sprzed D202 (tylko z plików): wartości równe dawnym domyślnym → nowe; JSON bez znacznika w dekoderze — bieżący")
    func migration() throws {
        let old: [String: Any] = ["indent": 4, "clauseLayout": "leftAligned", "caseLayout": "inline", "alignDeclarations": false, "alignAssignments": false]
        let m = BeautifierOptions.migratingLegacy(old)
        #expect(m["clauseLayout"] as? String == "rightAligned" && m["caseLayout"] as? String == "auto")
        #expect(m["alignDeclarations"] as? Bool == true && m["alignAssignments"] as? Bool == true && m["indent"] as? Int == 4)
        #expect(m["defaultsVersion"] as? Int == BeautifierOptions.currentDefaultsVersion)
        let custom = BeautifierOptions.migratingLegacy(["clauseLayout": "ownLine", "caseLayout": "multiline"])
        #expect(custom["clauseLayout"] as? String == "ownLine" && custom["caseLayout"] as? String == "multiline")
        // Zapis ze znacznikiem — bez zmian.
        let marked = BeautifierOptions.migratingLegacy(["clauseLayout": "leftAligned", "defaultsVersion": 1])
        #expect(marked["clauseLayout"] as? String == "leftAligned")
        // Dekoder: częściowy JSON bez znacznika (komenda, agent, makro) — wartości bieżące, bez migracji.
        let partial = try JSONDecoder().decode(BeautifierOptions.self, from: Data(#"{"clauseLayout":"leftAligned","alignDeclarations":false}"#.utf8))
        #expect(partial.clauseLayout == .leftAligned && !partial.alignDeclarations && partial.defaultsVersion == BeautifierOptions.currentDefaultsVersion)
        // Przywróć domyślne — formatowanie automatyczne zostaje; pisownia specjalna — domyślnie też, na życzenie nie.
        var o = BeautifierOptions()
        o.clauseLayout = .leftAligned; o.beforeSave = true; o.afterLoad = true; o.specialCase = ["DBMS_Output"]
        let d = o.restoringDefaults()
        #expect(d.beforeSave && d.afterLoad && !d.beforeCompile && d.clauseLayout == .rightAligned && d.specialCase == ["DBMS_Output"])
        #expect(o.restoringDefaults(keepSpecialCase: false).specialCase.isEmpty)
    }

    @Test("rzeka od 6 do 9: RETURNING i INTERSECT poszerzają, MATCH_RECOGNIZE i przedrostki złączeń wiszą w lewo")
    func riverLimits() throws {
        #expect(try f("select a from t natural join u left outer join w on w.id = t.id;") == """
            SELECT a
              FROM t
            NATURAL JOIN u
              LEFT OUTER JOIN w
                ON w.id = t.id;
            """)
        let mr = try f("select a from t match_recognize (order by b measures c as d pattern (x) define x as b > 0) where a > 1;")
        #expect(mr.hasPrefix("SELECT a\n  FROM t\nMATCH_RECOGNIZE"))
        #expect(mr.contains("\n WHERE a > 1;"))
        // Dopisanie RETURNING przesuwa polecenie najwyżej do szerokości 9.
        let r = try f("update t set a = 1 where b = 2 returning a into x;")
        #expect(r.hasPrefix("   UPDATE t\n") && r.contains("\nRETURNING a INTO x;"))
    }

    @Test("słowa DDL: nie jako nazwy kolumn w liście ani w zapytaniu widoku/CTAS; SET TRANSACTION READ ONLY")
    func contextualKeywordPlaces() throws {
        #expect(try f("create table t (query varchar2(10), schema number) parallel 4;") == """
            CREATE TABLE t (query  VARCHAR2(10),
                            schema NUMBER) PARALLEL 4;
            """)
        #expect(try f("create table t2 parallel 4 as select query, schema from t;").contains("SELECT query,\n       schema"))
        #expect(try f("set transaction read only;") == "SET TRANSACTION READ ONLY;")
    }

    @Test("$IF w osobnych liniach w środku instrukcji — dalszy ciąg w kolumnie kontynuacji")
    func directiveOnOwnLines() throws {
        let out = try f("select a\nfrom t\nwhere x = 1\n$if dbms_db_version.ver_le_12 $then\nand y = 2\n$end\nand z = 3;")
        #expect(out.contains("$if dbms_db_version.ver_le_12 $then\nand y = 2\n$end\n"))
        #expect(out.hasSuffix("   AND z = 3;"))
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
