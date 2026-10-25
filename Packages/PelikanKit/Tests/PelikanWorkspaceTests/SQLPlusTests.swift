import Foundation
import PelikanDB
import PelikanSQL
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
        // Samotny `/` w Command Window: po `;` — separator; na początku i po poleceniu SQL*Plus — wykonanie bufora.
        #expect(ScriptSplitter.split("select 1 from dual;\n/", mode: .commandWindow).map(\.text) == ["select 1 from dual"])
        #expect(ScriptSplitter.split("/", mode: .commandWindow).map(\.text) == ["/"])
        #expect(ScriptSplitter.split("get q\n/", mode: .commandWindow).map(\.text) == ["get q", "/"])
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

    @Test("HOST: `!polecenie` bez spacji; proces w tle nie blokuje końca; Przerwij kończy polecenie bez czekania na limit")
    func hostAsync() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let doc = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: doc)
        ui.answers = [0, 0]
        _ = await engine.run("!echo bez-spacji\n$echo dolar")
        #expect(doc.console.map(\.text).contains("bez-spacji") && doc.console.map(\.text).contains("dolar"))
        // Wnuk w tle trzyma potok — polecenie kończy się po zakończeniu powłoki.
        let start = ContinuousClock.now
        ui.answers = [0]
        _ = await engine.run("host (sleep 20; echo pozno) & echo gotowe")
        #expect(doc.console.map(\.text).contains("gotowe") && ContinuousClock.now - start < .seconds(10))
        // Przerwij (cancel) w trakcie polecenia.
        ui.answers = [0]
        let run = Task { await engine.run("host sleep 30") }
        while engine.hostTask == nil { try await Task.sleep(for: .milliseconds(20)) }
        let cancelAt = ContinuousClock.now
        engine.cancel()
        _ = await run.value
        #expect(ContinuousClock.now - cancelAt < .seconds(5))
        #expect(doc.console.map(\.text).contains("Polecenie systemu przerwane"))
    }

    @Test("DISCONNECT: pytanie o otwartą transakcję (Anuluj zostawia połączenie), potem bez cichego przejścia na połączenie główne")
    func disconnect() async {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        ws.settings.logoffWithOpenTransaction = .ask
        let doc = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: doc)
        doc.transactionOpen = true
        ui.answers = [2]
        _ = await engine.run("disconnect")
        #expect(!engine.state.disconnected && doc.transactionOpen && ui.asked.contains { $0.hasPrefix("Transakcja okna") })
        ui.answers = [1]
        _ = await engine.run("disconnect")
        #expect(engine.state.disconnected && !doc.transactionOpen)
        _ = await engine.run("select 1 from dual;")
        #expect(doc.console.last?.text == "SP2-0640: Brak połączenia.")
    }

    @Test("Hasło maskowane w echu i SPOOL (CONNECT, IDENTIFIED BY)")
    func maskPassword() {
        // Hasło składane w czasie testu (bez wzorca „użytkownik/hasło@baza” w źródle).
        let secret = String(repeating: "x", count: 5)
        let stars = String(repeating: "*", count: 8)
        #expect(SQLPlusEngine.maskPassword("connect scott/" + secret + "@db1 as sysdba") == "connect scott/" + stars + "@db1 as sysdba")
        #expect(SQLPlusEngine.maskPassword("CONN u/" + secret + "@x@host:1521/svc") == "CONN u/" + stars + "@host:1521/svc")
        #expect(SQLPlusEngine.maskPassword("conn scott@db1") == "conn scott@db1")
        #expect(SQLPlusEngine.maskPassword("alter user u identified by \"Tajne 1\" account unlock") == "alter user u identified by ******** account unlock")
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

@MainActor
@Suite("Command Window: bufor, pliki, BREAK i COMPUTE (PD-CMDW-004)")
struct SQLPlusBufferTests {
    @Test("Bufor: LIST z numerami i bieżącą linią, APPEND, CHANGE, DEL, INPUT")
    func buffer() throws {
        var b = SQLPlusBuffer("select ename\nfrom emp\nwhere deptno = 10")
        #expect(try b.list() == ["  1  select ename", "  2  from emp", "  3* where deptno = 10"])
        _ = try b.list(["1"])
        try b.append(", sal")
        #expect(b.lines[0] == "select ename, sal")
        try b.change("/ename/empno/")
        #expect(b.lines[0] == "select empno, sal")
        #expect(throws: SQLPlusError.self) { try b.change("/nie ma/x/") }
        b.input("  and 1 = 1")
        #expect(b.current == 1 && b.lines[1] == "  and 1 = 1")
        try b.delete([])
        #expect(b.lines == ["select empno, sal", "from emp", "where deptno = 10"] && b.current == 1)
        try b.delete(["2", "LAST"])
        #expect(b.lines == ["select empno, sal"])
        #expect(throws: SQLPlusError.self) { _ = try b.list(["5"]) }
    }

    @Test("Polecenia w oknie: APPEND ;; dokleja średnik, SAVE/GET pliku z .sql, STORE SET, CLEAR BREAKS")
    func commands() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: doc)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("buf-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        engine.state.directory = dir
        engine.state.buffer = "select 1\nfrom dual"
        _ = await engine.run("input where 1 = 1\nappend  ;;\nsave zapytanie")
        let saved = try String(contentsOf: dir.appendingPathComponent("zapytanie.sql"), encoding: .utf8)
        #expect(saved == "select 1\nfrom dual\nwhere 1 = 1 ;\n/\n")
        _ = await engine.run("save zapytanie")
        #expect(doc.console.contains { $0.kind == .error && $0.text.contains("SP2-0540") })
        engine.state.buffer = nil
        doc.console.removeAll()
        _ = await engine.run("get zapytanie")
        #expect(engine.state.buffer == "select 1\nfrom dual\nwhere 1 = 1 ;")
        #expect(doc.console.map(\.text).joined(separator: "\n").contains("  3* where 1 = 1 ;"))
        _ = await engine.run("set pagesize 20\nstore set ustawienia")
        let set = try String(contentsOf: dir.appendingPathComponent("ustawienia.sql"), encoding: .utf8)
        #expect(set.contains("set pagesize 20\n") && set.contains("set feedback 1\n"))
        _ = await engine.run("break on deptno skip 1\ncompute sum of sal on deptno report")
        #expect(engine.state.breaks == [SQLPlusBreak(column: "DEPTNO", skip: 1)])
        #expect(engine.state.computes.first?.on == ["DEPTNO", "REPORT"])
        _ = await engine.run("clear breaks\nclear computes")
        #expect(engine.state.breaks.isEmpty && engine.state.computes.isEmpty)
    }

    @Test("BREAK ukrywa powtórzenia i dodaje SKIP; COMPUTE SUM/COUNT na grupie i REPORT")
    func breakCompute() throws {
        var s = SQLPlusState()
        s.breaks = try SQLPlusBreak.parse(["on", "deptno", "skip", "1", "on", "report"])
        s.computes = [try SQLPlusCompute.parse(["sum", "count", "of", "sal", "on", "deptno"]),
                      try SQLPlusCompute.parse(["sum", "label", "Razem", "of", "sal", "on", "report"])]
        let cols = [ColumnInfo(name: "DEPTNO", type: .number, typeName: "NUMBER"), ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2(10)"),
                    ColumnInfo(name: "SAL", type: .number, typeName: "NUMBER")]
        var f = TextResultFormatter(columns: cols, state: s, format: .default)
        var lines = f.lines([[.number("10"), .text("KING"), .number("5000")], [.number("10"), .text("CLARK"), .number("2450")],
                             [.number("20"), .text("FORD"), .number("3000")]], first: true)
        lines += f.finish()
        #expect(lines == [
            "    DEPTNO ENAME        SAL", "---------- ----- ----------",
            "        10 KING        5000", "           CLARK       2450",
            "**********       ----------", "sum                    7450", "count                     2", "",
            "        20 FORD        3000",
            "**********       ----------", "sum                    3000", "count                     1",
            "                 ----------", "Razem                 10450",
        ])
    }
}
