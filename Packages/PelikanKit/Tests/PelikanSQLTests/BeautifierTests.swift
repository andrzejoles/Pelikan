import Foundation
import PelikanSQL
import Testing

@Suite("Formater PL/SQL")
struct BeautifierTests {
    static let query = "select e.ename,d.dname, count(*) cnt from emp e join dept d on d.deptno=e.deptno where e.sal>1000 and e.job in ('A','B') and e.sal between 1 and 5 group by e.ename,d.dname order by 1;"

    static let body = """
        create or replace package body emp_api as
        g number := 0; -- licznik
        procedure dodaj(p_id in number, p_nazwa varchar2 default 'x') is
        v number;
        begin
        if p_id is null then raise_application_error(-20001,'brak'); elsif p_id < 0 then null; else
        insert into emp(empno,ename) values(p_id,p_nazwa);
        end if;
        for r in (select empno from emp where deptno=10) loop
        update emp set sal=sal*1.1, comm = 0 where empno=r.empno;
        end loop;

        -- NoFormat Start
          x   :=    1  ;
        -- NoFormat End
        exception when no_data_found then null; when others then raise;
        end dodaj;
        end emp_api;
        /
        """

    static let misc = """
        create or replace package p as
        type t_rec is record (a number, b varchar2(10));
        procedure x(p_bardzo_dlugi_parametr_pierwszy in number, p_bardzo_dlugi_parametr_drugi in varchar2, p_trzeci out date);
        function f return number;
        end p;
        /
        create or replace trigger trg before insert on emp for each row
        declare v number; begin :new.sal := nvl(:new.sal,0); case when :new.sal > 10 then v := 1; else v := 2; end case; end;
        /
        declare cursor c is select * from dept; begin begin null; exception when others then null; end;
        with x as (select 1 a from dual) select a, case when a=1 then 'jeden' else 'inny' end opis from x;
        merge into t using s on (t.id=s.id) when matched then update set t.v=s.v when not matched then insert (id,v) values (s.id,s.v);
        while i < 10 loop i := i + 1; end loop;
        for i in 1..10 loop null; end loop;
        end;
        """

    @Test("Zapytanie: klauzule w kolumnie instrukcji, wyrównanie elementów, AND, BETWEEN, JOIN … ON")
    func query() throws {
        #expect(try Beautifier.format(Self.query) == """
            SELECT e.ename,
                   d.dname,
                   count(*) cnt
            FROM   emp e
            JOIN   dept d
              ON d.deptno = e.deptno
            WHERE  e.sal > 1000
            AND    e.job IN ('A', 'B')
            AND    e.sal BETWEEN 1 AND 5
            GROUP BY e.ename,
                     d.dname
            ORDER BY 1;
            """)
    }

    @Test("Ciało pakietu: deklaracje, bloki, IF/ELSIF/ELSE, pętla z podzapytaniem, UPDATE, wyjątki, NoFormat, komentarz w linii")
    func packageBody() throws {
        #expect(try Beautifier.format(Self.body) == """
            CREATE OR REPLACE PACKAGE BODY emp_api AS
              g NUMBER := 0; -- licznik
              PROCEDURE dodaj(p_id IN NUMBER, p_nazwa VARCHAR2 DEFAULT 'x') IS
                v NUMBER;
              BEGIN
                IF p_id IS NULL THEN
                  raise_application_error(-20001, 'brak');
                ELSIF p_id < 0 THEN
                  NULL;
                ELSE
                  INSERT INTO emp(empno, ename)
                  VALUES (p_id, p_nazwa);
                END IF;
                FOR r IN (SELECT empno
                          FROM   emp
                          WHERE  deptno = 10) LOOP
                  UPDATE emp
                  SET    sal = sal * 1.1,
                         comm = 0
                  WHERE  empno = r.empno;
                END LOOP;

            -- NoFormat Start
              x   :=    1  ;
            -- NoFormat End
              EXCEPTION
                WHEN no_data_found THEN
                  NULL;
                WHEN OTHERS THEN
                  RAISE;
              END dodaj;
            END emp_api;
            /
            """)
    }

    @Test("Specyfikacja z zawijaniem parametrów, wyzwalacz z CASE, blok zagnieżdżony, WITH, MERGE, pętle")
    func misc() throws {
        let out = try Beautifier.format(Self.misc)
        #expect(out.contains("""
              PROCEDURE x(p_bardzo_dlugi_parametr_pierwszy IN NUMBER,
                          p_bardzo_dlugi_parametr_drugi IN VARCHAR2,
                          p_trzeci OUT DATE);
            """))
        #expect(out.contains("CREATE OR REPLACE TRIGGER trg BEFORE INSERT ON emp FOR EACH ROW\nDECLARE\n  v NUMBER;\nBEGIN\n"))
        #expect(out.contains("  CASE\n    WHEN :new.sal > 10 THEN\n      v := 1;\n    ELSE\n      v := 2;\n  END CASE;\n"))
        #expect(out.contains("  WITH   x AS (SELECT 1 a\n               FROM   dual)\n  SELECT a,\n"))
        #expect(out.contains("  MERGE INTO t\n  USING  s ON (t.id = s.id)\n"))
        #expect(out.contains("  FOR i IN 1..10 LOOP\n    NULL;\n  END LOOP;\n"))
    }

    @Test("Idempotencja: ponowne formatowanie nie zmienia wyniku")
    func idempotent() throws {
        for s in [Self.query, Self.body, Self.misc] {
            let once = try Beautifier.format(s)
            #expect(try Beautifier.format(once) == once)
        }
    }

    @Test("Opcje: małe słowa kluczowe, wcięcie 4, tabulatory, przecinek przed, lista w linii, Special Case")
    func options() throws {
        var o = BeautifierOptions()
        o.keywordCase = .lower
        o.indent = 4
        o.specialCase = ["DBMS_Output"]
        let a = try Beautifier.format("BEGIN dbms_output.put_line('x'); END;", options: o)
        #expect(a == "begin\n    DBMS_Output.put_line('x');\nend;")
        o.useTabs = true
        #expect(try Beautifier.format("begin null; end;", options: o) == "begin\n\tnull;\nend;")
        var c = BeautifierOptions()
        c.commaBefore = true
        #expect(try Beautifier.format("select a, b from t", options: c) == "SELECT a\n     , b\nFROM   t")
        c.commaBefore = false
        c.listLayout = .fit
        #expect(try Beautifier.format("select a, b from t", options: c) == "SELECT a, b\nFROM   t")
        c.identifierCase = .upper
        #expect(try Beautifier.format("select a from \"MixedCase\"", options: c) == "SELECT A\nFROM   \"MixedCase\"")
    }

    @Test("Zaznaczenie: tylko wybrane linie, wcięcie bazowe zachowane")
    func selection() throws {
        let text = "begin\n    select a,b from t where x=1;\n  null;\nend;\n"
        let start = (text as NSString).range(of: "select").location
        let (out, range) = try Beautifier.format(text, range: start..<(start + 10))
        #expect(out == "begin\n    SELECT a,\n           b\n    FROM   t\n    WHERE  x = 1;\n  null;\nend;\n")
        #expect((out as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count)).hasPrefix("    SELECT"))
    }

    @Test("Bezpieczeństwo: zmiana tokenu wykryta; literały, identyfikatory w cudzysłowie i komentarze bez zmian")
    func safety() throws {
        #expect(throws: BeautifierError.self) { try Beautifier.verify(original: "select a from t", formatted: "select b from t") }
        let s = "select 'MiXeD  text', \"Quoted Name\" /* Ko  ment */ from dual -- uwaga  na  spacje"
        let out = try Beautifier.format(s)
        #expect(out.contains("'MiXeD  text'") && out.contains("\"Quoted Name\"") && out.contains("/* Ko  ment */") && out.contains("-- uwaga  na  spacje"))
    }

    @Test("Wydajność: pakiet 50 000 linii")
    func performance() throws {
        var s = "create or replace package body big as\n"
        for i in 1...5000 {
            s += "procedure p\(i)(a number) is v number; begin if a > 0 then v := a; end if; for r in 1..2 loop null; end loop; select count(*) into v from dual where 1=1; end p\(i);\n"
        }
        s += "end big;\n/\n"
        let clock = ContinuousClock()
        var lines = 0
        let t = try clock.measure { lines = try Beautifier.format(s).components(separatedBy: "\n").count }
        #expect(lines > 50_000)
        #expect(t < (ProcessInfo.processInfo.environment["PELIKAN_PERF_STRICT"] == "1" ? .seconds(2) : .seconds(20)), "\(t)")
    }
}
