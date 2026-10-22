import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@Suite("Command Window — bez bazy")
struct SQLPlusUnitTests {
    @Test("Podstawianie: &x, &&x (zapamiętywane), &1, kropka łącząca, znak escape, SET DEFINE OFF i inny znak")
    func substitution() {
        var s = SQLPlusState()
        let text = "select * from &tab._audit where id = &&id and x = '&1' and y = \\&nie"
        #expect(SQLPlusSubstitution.references(in: text, state: s).map(\.name) == ["TAB", "ID", "1", "NIE"])
        #expect(SQLPlusSubstitution.references(in: text, state: s)[1].persistent)
        s.escapeChar = "\\"
        #expect(SQLPlusSubstitution.substitute(text, state: s, values: ["TAB": "EMP", "ID": "7", "1": "a"])
                == "select * from EMP_audit where id = 7 and x = 'a' and y = &nie")
        s.defineEnabled = false
        #expect(SQLPlusSubstitution.references(in: "&x", state: s).isEmpty)
        s.defineEnabled = true
        s.defineChar = "^"
        #expect(SQLPlusSubstitution.substitute("a ^b & c", state: s, values: ["B": "1"]) == "a 1 & c")
    }

    @Test("Słowa polecenia z cudzysłowami")
    func words() {
        #expect(SQLPlusEngine.words("column ename heading 'Nazwisko pracownika' format a20") == ["column", "ename", "heading", "Nazwisko pracownika", "format", "a20"])
        #expect(SQLPlusEngine.words("set colsep '|'") == ["set", "colsep", "|"])
        #expect(SQLPlusEngine.words("prompt ''") == ["prompt", ""])
    }

    @Test("Wynik tekstowy: nagłówki, podkreślenie, liczby do prawej, COLSEP, powtarzanie nagłówków co PAGESIZE")
    func formatter() {
        var s = SQLPlusState()
        s.pageSize = 2
        s.colSep = " | "
        s.columns["ENAME"] = .init(heading: "Nazwisko")
        let cols = [ColumnInfo(name: "EMPNO", type: .number, typeName: "NUMBER"), ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2(10)")]
        var f = TextResultFormatter(columns: cols, state: s, format: .default)
        let lines = f.lines([[.number("7369"), .text("Nowak")], [.number("10"), .null], [.number("1"), .text("Ąę")]], first: true)
        #expect(lines == ["     EMPNO | Nazwisko", "---------- | --------", "      7369 | Nowak", "        10 |", "",
                          "     EMPNO | Nazwisko", "---------- | --------", "         1 | Ąę"])
        #expect(TextResultFormatter.number(1234.5, format: "9,999.99") == "1,234.50")
        #expect(TextResultFormatter.number(123456, format: "999") == "###")
    }

    @Test("Komunikaty DDL")
    func ddl() {
        #expect(SQLPlusEngine.ddlMessage("create or replace package body p as") == "Utworzono: PACKAGE BODY.")
        #expect(SQLPlusEngine.ddlMessage("drop table t purge") == "Usunięto: TABLE.")
        #expect(SQLPlusEngine.ddlMessage("create unique index i on t(x)") == "Utworzono: INDEX.")
    }
}
