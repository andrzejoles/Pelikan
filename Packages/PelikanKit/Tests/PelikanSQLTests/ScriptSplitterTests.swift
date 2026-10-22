import PelikanSQL
import Testing

@Suite("Dzielenie skryptu na polecenia")
struct ScriptSplitterTests {
    @Test("Polecenia SQL rozdzielone średnikami, bez średnika w tekście")
    func sqlStatements() {
        let s = ScriptSplitter.split("select 1 from dual;\nselect 2 from dual ;\n\nupdate t set x = 1")
        #expect(s.map(\.text) == ["select 1 from dual", "select 2 from dual", "update t set x = 1"])
        #expect(s.map(\.line) == [0, 1, 3])
        #expect(s.map(\.terminator) == [.semicolon, .semicolon, .endOfText])
        #expect(s.map(\.category) == [.query, .query, .dml])
    }

    @Test("Blok PL/SQL kończy tylko / w osobnej linii; średniki w środku nie dzielą")
    func plsqlBlock() {
        let script = """
        BEGIN
          dbms_output.put_line('a; b');
          x := 1 / 2;
        END;
        /
        select 1 from dual;
        """
        let s = ScriptSplitter.split(script)
        #expect(s.count == 2)
        #expect(s[0].isPLSQL)
        #expect(s[0].text.hasSuffix("END;"))
        #expect(s[0].terminator == .slash)
        #expect(s[1].text == "select 1 from dual")
        #expect(s[1].line == 5)
    }

    @Test("CREATE OR REPLACE z ciałem, typy, wyzwalacze, MLE — jako PL/SQL")
    func createPLSQL() {
        let script = """
        create or replace editionable package body p as
          procedure x is begin null; end;
        end p;
        /
        CREATE TYPE t AS OBJECT (a NUMBER);
        /
        CREATE OR REPLACE TRIGGER trg BEFORE INSERT ON t FOR EACH ROW BEGIN :new.a := 1; END;
        /
        CREATE OR REPLACE MLE MODULE m LANGUAGE JAVASCRIPT AS
        export function f() { return 1; }
        /
        create table x (a number);
        """
        let s = ScriptSplitter.split(script)
        #expect(s.map(\.isPLSQL) == [true, true, true, true, false])
        #expect(s.map(\.category) == [.ddl, .ddl, .ddl, .ddl, .ddl])
        #expect(s[4].text == "create table x (a number)")
    }

    @Test("/ po poleceniu zakończonym ; nie tworzy pustego polecenia")
    func slashAfterSemicolon() {
        let s = ScriptSplitter.split("create table a (x number);\n/\nselect 1 from dual\n/\n")
        #expect(s.map(\.text) == ["create table a (x number)", "select 1 from dual"])
    }

    @Test("Średnik w literale, komentarzu i nawiasie nie dzieli")
    func semicolonInside() {
        let s = ScriptSplitter.split("select ';' /* ; */ -- ;\n from dual; select 2 from dual")
        #expect(s.count == 2)
        #expect(s[0].text == "select ';' /* ; */ -- ;\n from dual")
    }

    @Test("Komentarz przed poleceniem należy do polecenia, kategoria wg pierwszego słowa")
    func leadingComment() {
        let s = ScriptSplitter.split("-- opis\n/* x */ delete from t;")
        #expect(s.count == 1)
        #expect(s[0].category == .dml)
        #expect(s[0].text.hasPrefix("-- opis"))
    }

    @Test("Same komentarze nie są poleceniem")
    func onlyComments() {
        #expect(ScriptSplitter.split("-- nic\n/* tu */\n").isEmpty)
    }

    @Test("WITH FUNCTION (12c) to blok kończony /")
    func withFunction() {
        let s = ScriptSplitter.split("WITH FUNCTION f RETURN NUMBER IS BEGIN RETURN 1; END;\nSELECT f FROM dual\n/\nselect 3 from dual;")
        #expect(s.count == 2)
        #expect(s[0].category == .query)
        #expect(s[0].isPLSQL)
    }

    @Test("Command Window: polecenia SQL*Plus jednoliniowe, z kontynuacją -")
    func commandWindow() {
        let script = """
        SET SERVEROUTPUT ON
        PROMPT Don't panic
        COLUMN ename -
          FORMAT A20
        @@inne.sql
        select 1 from dual;
        set transaction read only;
        exec dbms_output.put_line('x')
        """
        let s = ScriptSplitter.split(script, mode: .commandWindow)
        #expect(s.map(\.sqlplusCommand) == ["SET", "PROMPT", "COLUMN", "@@", nil, nil, "EXECUTE"])
        #expect(s[1].text == "PROMPT Don't panic")
        #expect(s[2].text.contains("FORMAT A20"))
        #expect(s[4].text == "select 1 from dual")
        #expect(s[5].category == .transactionControl)
    }

    @Test("Polecenie pod kursorem")
    func statementAtCursor() {
        let script = "select 1 from dual;\n\nselect 2 from dual;"
        let s = ScriptSplitter.split(script)
        #expect(ScriptSplitter.statement(at: 3, in: s)?.text == "select 1 from dual")
        #expect(ScriptSplitter.statement(at: 25, in: s)?.text == "select 2 from dual")
        #expect(ScriptSplitter.statement(at: 20, in: s)?.text == "select 1 from dual")
    }
}

@Suite("Klasyfikacja poleceń")
struct ClassifierTests {
    @Test("Kategorie podstawowe", arguments: [
        ("select * from t", StatementCategory.query),
        ("with a as (select 1 x from dual) select * from a", .query),
        ("insert into t values (1)", .dml),
        ("merge into t using s on (1=1) when matched then update set x=1", .dml),
        ("begin null; end;", .plsql),
        ("call p()", .plsql),
        ("create table t (x number)", .ddl),
        ("truncate table t", .ddl),
        ("grant select on t to u", .ddl),
        ("alter session set nls_date_format = 'YYYY'", .sessionControl),
        ("alter system kill session '1,2'", .systemControl),
        ("commit", .transactionControl),
        ("set transaction read only", .transactionControl),
        ("blah blah", .unknown),
    ])
    func categories(sql: String, expected: StatementCategory) {
        #expect(StatementClassifier.classify(sql).category == expected)
    }

    @Test("SELECT … FOR UPDATE blokuje wiersze; kilka poleceń — najwyższe ryzyko")
    func flags() {
        let c = StatementClassifier.classify("select * from emp for update")
        #expect(c.category == .query)
        #expect(c.locksRows)
        let m = StatementClassifier.classify("select 1 from dual; drop table t")
        #expect(m.statementCount == 2)
        #expect(m.category == .ddl)
    }

    @Test("Polecenia systemu operacyjnego w Command Window")
    func osCommands() {
        #expect(StatementClassifier.classify("host ls", mode: .commandWindow).touchesOperatingSystem)
        #expect(StatementClassifier.classify("spool /tmp/x.txt", mode: .commandWindow).touchesOperatingSystem)
        #expect(!StatementClassifier.classify("select 1 from dual", mode: .commandWindow).touchesOperatingSystem)
    }
}
