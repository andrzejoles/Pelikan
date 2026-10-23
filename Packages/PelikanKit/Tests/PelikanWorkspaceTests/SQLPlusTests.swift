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

    @Test("Linia poleceń: kiedy polecenie jest kompletne (SQL*Plus od razu, SQL po ;, PL/SQL po /)")
    func complete() {
        #expect(SQLPlusEngine.isComplete("desc emp"))
        #expect(SQLPlusEngine.isComplete("set echo on"))
        #expect(!SQLPlusEngine.isComplete("select * from emp"))
        #expect(SQLPlusEngine.isComplete("select * from emp\n where 1=1;"))
        #expect(!SQLPlusEngine.isComplete("begin\n null;\nend;"))
        #expect(SQLPlusEngine.isComplete("begin\n null;\nend;\n/"))
        #expect(!SQLPlusEngine.isComplete("create or replace procedure p as begin null; end;"))
        #expect(SQLPlusEngine.isComplete("/"))
    }

    @Test("SET z kilkoma opcjami i SERVEROUTPUT z SIZE/FORMAT")
    @MainActor
    func setMany() async {
        let ws = Workspace()
        let e = ws.sqlplusEngine(for: ws.newDocument(.command))
        await e.run("set feedback off timing on heading off\nset serveroutput on size unlimited format wrapped pagesize 0")
        #expect(e.state.feedback == 0 && e.state.timing && !e.state.heading)
        #expect(e.state.serverOutput && e.state.pageSize == 0)
    }

    @Test("Komunikaty DDL")
    func ddl() {
        #expect(SQLPlusEngine.ddlMessage("create or replace package body p as") == "Utworzono: PACKAGE BODY.")
        #expect(SQLPlusEngine.ddlMessage("drop table t purge") == "Usunięto: TABLE.")
        #expect(SQLPlusEngine.ddlMessage("create unique index i on t(x)") == "Utworzono: INDEX.")
    }
}

@MainActor
@Suite("Command Window: HOST i krokowanie skryptu")
struct SQLPlusHostStepTests {
    @Test("HOST po potwierdzeniu: wyjście w oknie, katalog CD; anulowanie nic nie uruchamia")
    func host() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let doc = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: doc)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("host-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        engine.state.directory = dir
        ui.answers = [0]
        _ = await engine.run("host echo witaj; pwd")
        let out = doc.console.map(\.text).joined(separator: "\n")
        #expect(out.contains("witaj") && out.contains(dir.lastPathComponent) && ui.asked.contains("Wykonać polecenie systemu?"))
        ui.answers = [1]
        _ = await engine.run("! touch \(dir.path)/nie")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("nie").path))
    }

    @Test("SET EXECPAUSE ON: pytanie przed poleceniem; Wykonaj resztę i Przerwij")
    func stepping() async {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let doc = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: doc)
        engine.state.execPause = true
        ui.answers = [0, 1]
        _ = await engine.run("prompt jeden\nprompt dwa\nprompt trzy")
        #expect(doc.console.map(\.text).filter { ["jeden", "dwa", "trzy"].contains($0) } == ["jeden", "dwa", "trzy"])
        #expect(ui.asked.filter { $0 == "Następne polecenie" }.count == 2)
        doc.console.removeAll()
        ui.answers = [2]
        let o = await engine.run("prompt cztery")
        #expect(o == .stopped && !doc.console.map(\.text).contains("cztery"))
    }
}
