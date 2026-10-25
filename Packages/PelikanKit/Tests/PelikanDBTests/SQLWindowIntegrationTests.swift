import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu: odpowiada na okno zmiennych podanymi wartościami.
@MainActor
final class TestUI: UIServices {
    var gridRequests: [GridToolRequest] = []
    func showGridTool(_ request: GridToolRequest) { gridRequests.append(request) }
    var variables: [String: VariableValue] = [:]
    var askedVariables: [VariableRequest] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    var askAnswer: Int? = 0
    var asked: [String] = []
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { asked.append(title); return askAnswer }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? {
        askedVariables = requests
        return variables
    }
    var clipboard: String?
    var savedFile: (name: String, ext: String, data: Data)?
    func copyToClipboard(_ text: String, html: String?) { clipboard = text }
    var largeData: LargeDataModel?
    var openURLs: [URL] = []
    var saveURL: URL?
    func chooseFilesToOpen() async -> [URL] { openURLs }
    var textAnswer: String?
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { textAnswer }
    func showFindReplace() {}
    var objectInfo: (String, [[String]])?
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) { objectInfo = (title, rows) }
    var clientHelp: String?
    func showClientMissingHelp(_ message: String) { clientHelp = message }
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { saveURL }
    func showLargeDataEditor(_ model: LargeDataModel) { largeData = model }
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool {
        savedFile = (suggestedName, fileExtension, data)
        return true
    }
}

@MainActor
@Suite("SQL Window na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct SQLWindowIntegrationTests {
    func makeWorkspace() throws -> (Workspace, Document, TestUI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql)
        return (ws, doc, ui)
    }

    @Test("SELECT: karta wyniku, 100 wierszy na start, dociąganie, status")
    func query() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "select id, txt from big_rows order by id"
        try await ws.invoke("sql.execute")
        let grid = try #require(doc.results.first?.grid)
        #expect(grid.rowCount == 100)
        #expect(grid.hasMore)
        #expect(grid.text(row: 0, column: 0) == "1")
        await grid.fetchMore(500)
        #expect(grid.rowCount == 600)
        #expect(doc.results.first?.title == "Select big_rows")
        #expect(doc.resultSummary == "600 wierszy (więcej…)")
        await ws.sessions.disconnectAll()
    }

    @Test("DML: transakcja otwarta, COMMIT/ROLLBACK z menu ją zamyka; druga sesja nie widzi zmian przed COMMIT")
    func transactions() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "update emp set comm = 777 where empno = 7369"
        try await ws.invoke("sql.execute")
        #expect(doc.results.first?.message == "Wierszy: 1")
        #expect(doc.transactionOpen)
        #expect(ws.isEnabled("session.rollback"))
        try await ws.invoke("session.rollback")
        #expect(!doc.transactionOpen)
        doc.text = "select comm from emp where empno = 7369"
        try await ws.invoke("sql.execute")
        #expect(doc.results.first?.grid?.text(row: 0, column: 0) == "")
        await ws.sessions.disconnectAll()
    }

    @Test("Błąd ORA: komunikat w karcie, pozycja błędu w tekście okna (z uwzględnieniem polskich znaków)")
    func errorPosition() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "-- zażółć\nselect 1 from dual;\nselect brak_kolumny from dual;"
        doc.selectedRange = 0..<0
        try await ws.invoke("sql.executeAlternate")   // AutoSelect włączone → Ctrl+F8 wykonuje wszystkie
        #expect(doc.results.count == 2)
        #expect(doc.results.contains { $0.message?.contains("ORA-00904") == true })
        let expected = (doc.text as NSString).range(of: "brak_kolumny").location
        #expect(doc.errorRange?.lowerBound == expected)
        await ws.sessions.disconnectAll()
    }

    @Test("DBMS_OUTPUT z wywołania procedury trafia do karty Output")
    func dbmsOutput() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "begin emp_api.raise_salary(7369, 1); end;\n/"
        try await ws.invoke("sql.execute")
        #expect(doc.output == ["Podwyżka dla 7369: 1%"])
        #expect(doc.transactionOpen)
        try await ws.invoke("session.rollback")
        await ws.sessions.disconnectAll()
    }

    @Test("Zmienne: :bind i &<…> w jednym oknie, wartości zapamiętane")
    func variables() async throws {
        let (ws, doc, ui) = try makeWorkspace()
        ui.variables = ["id": .text("7839"), "Kolumna": .text("ename")]
        doc.text = "select &<name=\"Kolumna\" list=\"ename, job\"> from emp where empno = :id"
        try await ws.invoke("sql.execute")
        #expect(ui.askedVariables.map(\.name) == ["Kolumna", "id"])
        #expect(doc.results.first?.grid?.text(row: 0, column: 0) == "KOWALSKI")
        #expect(doc.variableValues["id"] == .text("7839"))
        await ws.sessions.disconnectAll()
    }

    @Test("Komendy siatki: następna i ostatnia strona, sortowanie, kopiowanie zaznaczenia, eksport INSERT i xlsx")
    func gridCommands() async throws {
        let (ws, doc, ui) = try makeWorkspace()
        doc.text = "select empno, ename, sal from emp order by empno"
        try await ws.invoke("sql.execute")
        #expect(!ws.isEnabled("grid.nextPage"))          // 8 wierszy — wszystko pobrane
        let tab = try #require(doc.results.first)
        tab.grid!.toggleSort(column: 2)
        tab.grid!.toggleSort(column: 2)                   // malejąco po SAL
        tab.selectedRows = [0, 1]
        try await ws.invoke("grid.copyWithHeader")
        #expect(ui.clipboard == "EMPNO\tENAME\tSAL\n7839\tKOWALSKI\t5000\n7788\tKAMIŃSKI\t3000")
        try await ws.invoke("grid.copyExpressionList")
        #expect(ui.clipboard?.hasPrefix("(EMPNO, ENAME, SAL) IN ((7839, 'KOWALSKI', 5000)") == true)
        tab.selectedRows = nil
        try await ws.invoke("grid.export", CommandArguments(["format": .string("sql")]))
        let sql = String(decoding: ui.savedFile!.data, as: UTF8.self)
        #expect(sql.components(separatedBy: "INSERT INTO EMP (EMPNO, ENAME, SAL) VALUES").count == 9)
        try await ws.invoke("grid.copyToExcel")
        #expect(ui.savedFile?.ext == "xlsx")

        doc.text = "select * from big_rows"
        try await ws.invoke("sql.execute")
        #expect(ws.isEnabled("grid.nextPage"))
        try await ws.invoke("grid.nextPage")
        #expect(doc.results.first?.grid?.rowCount == 200)
        try await ws.invoke("grid.lastPage")
        #expect(doc.results.first?.grid?.rowCount == 200_000)
        #expect(!ws.isEnabled("grid.lastPage"))
        await ws.sessions.disconnectAll()
    }

    @Test("Dyrektywa Records= i historia poleceń okna")
    func recordsAndHistory() async throws {
        let (ws, doc, _) = try makeWorkspace()
        doc.text = "-- Records=7\nselect * from big_rows"
        try await ws.invoke("sql.execute")
        #expect(doc.results.first?.grid?.rowCount == 7)
        #expect(ws.history.first?.text.hasSuffix("select * from big_rows") == true)
        #expect(doc.statementHistory.count == 1)
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("SQL Window — przerwanie", .enabled(if: TestDatabase.isAvailable), .serialized)
struct SQLWindowBreakTests {
    @Test("Przerwij (sql.break) kończy długie zapytanie ORA-01013 bez przesuwania kursora; interfejs dostępny w trakcie")
    func breakExecution() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql)
        doc.text = "select count(*) from big_rows a, big_rows b"
        doc.selectedRange = 5..<5
        let run = Task { try await ws.invoke("sql.execute") }
        while !doc.isExecuting { await Task.yield() }
        try await Task.sleep(for: .milliseconds(700))
        #expect(ws.isEnabled("sql.break"))
        try await ws.invoke("sql.break")
        _ = try? await run.value
        #expect(!doc.isExecuting)
        #expect(doc.results.first?.message?.contains("ORA-01013") == true)
        #expect(doc.errorRange == nil)
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Edycja siatki na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct GridEditingIntegrationTests {
    func open(_ sql: String) async throws -> (Workspace, Document, ResultGridModel) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql)
        doc.text = sql
        try await ws.invoke("sql.execute")
        return (ws, doc, try #require(doc.results.first?.grid))
    }

    @Test("UPDATE po ROWID: kolumny edytowalne, wartość z wyzwalacza po zapisie, transakcja otwarta, anulowanie")
    func update() async throws {
        let (ws, doc, g) = try await open("select e.*, e.rowid from emp e order by empno")
        try await ws.invoke("grid.edit")
        let t = try #require(g.edit.target)
        #expect(t.table == "EMP")
        #expect(!t.editableColumns.contains(g.rowidColumn!))
        let comm = g.columns.firstIndex { $0.name == "COMM" }!
        let sal = g.columns.firstIndex { $0.name == "SAL" }!
        #expect(t.editableColumns.isSuperset(of: [comm, sal]))
        try g.setText("123,5", row: 0, column: comm)
        #expect(g.cellState(row: 0, column: comm) == .modified)
        #expect(g.changesSQL().hasPrefix("UPDATE PELIKAN_TEST.EMP SET COMM = 123.5 WHERE ROWID = '"))
        try await ws.invoke("grid.post")
        #expect(!g.edit.hasChanges)
        #expect(doc.transactionOpen)
        #expect(g.text(row: 0, column: comm) == "123.5")
        // Druga zmiana i anulowanie przywraca wartość.
        try g.setText("9999", row: 1, column: sal)
        g.cancelChanges()
        #expect(g.text(row: 1, column: sal) == "1600")
        try await ws.invoke("session.rollback")
        await ws.sessions.disconnectAll()
    }

    @Test("INSERT z RETURNING ROWID i DELETE; wstawiony i usunięty przed zapisem znika bez SQL")
    func insertDelete() async throws {
        let (ws, doc, g) = try await open("select d.rowid, d.* from dept d order by deptno")
        try await ws.invoke("grid.edit")
        let before = g.rowCount
        let row = try g.insertRecord()
        try g.setText("99", row: row, column: 1)
        try g.setText("TESTY", row: row, column: 2)
        try g.setText("Kraków", row: row, column: 3)
        #expect(g.cellState(row: row, column: 1) == .inserted)
        try await ws.invoke("grid.post")
        #expect(g.rowCount == before + 1)
        #expect(!g.value(row: row, column: 0).isNull)          // ROWID z RETURNING
        try g.deleteRecords([row])
        #expect(g.cellState(row: row, column: 1) == .deleted)
        #expect(g.changesSQL().hasPrefix("DELETE FROM PELIKAN_TEST.DEPT WHERE ROWID = '"))
        try await ws.invoke("grid.post")
        #expect(g.rowCount == before)
        let tmp = try g.insertRecord()
        try g.deleteRecords([tmp])
        #expect(g.rowCount == before && !g.edit.hasChanges)
        #expect(doc.transactionOpen)
        try await ws.invoke("session.rollback")
        await ws.sessions.disconnectAll()
    }

    @Test("Złączenie: edytowalne tylko kolumny tabeli z ROWID; kolumna z aliasem tylko do odczytu")
    func joinAndAlias() async throws {
        let (ws, _, g) = try await open("select e.ename, d.dname, e.sal pensja, e.rowid from emp e join dept d on d.deptno = e.deptno")
        try await ws.invoke("grid.edit")
        #expect(g.edit.target?.editableColumns == [0])
        #expect(throws: GridEditError.self) { try g.setText("X", row: 0, column: 1) }
        await ws.sessions.disconnectAll()
    }

    @Test("Bez ROWID: edycja niedostępna z wyjaśnieniem")
    func noRowid() async throws {
        let (ws, _, g) = try await open("select * from emp")
        #expect(!ws.isEnabled("grid.edit"))
        await #expect(throws: GridEditError.self) { try await g.beginEditing() }
        #expect(g.edit.notEditableReason?.contains("ROWID") == true)
        await ws.sessions.disconnectAll()
    }

    @Test("Za długa wartość: czerwony znacznik, błąd ORA-12899 wskazuje wiersz i kolumnę")
    func overflowError() async throws {
        let (ws, _, g) = try await open("select ename, rowid from emp order by empno")
        try await ws.invoke("grid.edit")
        try g.setText(String(repeating: "x", count: 60), row: 2, column: 0)
        #expect(g.isOverflow(row: 2, column: 0))
        await #expect(throws: CommandError.self) { try await ws.invoke("grid.post") }
        let tab = ws.activeDocument!.results.first!
        #expect(tab.selectedRows == [2])
        #expect(tab.focusedColumn == 0)
        _ = try? await ws.invoke("session.rollback")
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Large Data Editor na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct LargeDataIntegrationTests {
    @Test("CLOB, BLOB i JSON: format, podgląd hex; CLOB obcięty w siatce pobierany w całości; zmiana CLOB i BLOB zatwierdzana przez Post")
    func lobs() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql)
        // CLOB 2,2 mln znaków — więcej niż limit pobierania w siatce (1 MB).
        doc.text = """
        declare c clob; begin dbms_lob.createtemporary(c, true);
          for i in 1 .. 70 loop dbms_lob.writeappend(c, 32000, rpad('x', 32000, 'x')); end loop;
          update docs set body = c where id = 1; end;
        /
        """
        try await ws.invoke("sql.execute")
        doc.text = "select d.rowid, d.id, d.body, d.data, d.meta from docs d where id = 1"
        try await ws.invoke("sql.execute")
        let tab = try #require(doc.results.first)
        let grid = try #require(tab.grid)
        #expect(grid.text(row: 0, column: 2) == "<CLOB>")
        tab.selectedRows = [0]
        tab.currentColumn = 2
        try await ws.invoke("grid.largeData")
        let clob = try #require(ui.largeData)
        #expect(clob.text?.count == 2_240_000)
        #expect(!clob.truncated)
        #expect(clob.format == .text)

        tab.currentColumn = 3
        try await ws.invoke("grid.largeData")
        let blob = try #require(ui.largeData)
        #expect(blob.bytes == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(LargeDataModel.hexDump(blob.bytes!).hasPrefix("00000000  DE AD BE EF"))

        let json = LargeDataModel(grid: grid, row: 0, column: 4)
        #expect(json.format == .json)
        #expect(LargeDataModel.prettyJSON(json.text ?? "")?.contains("\n") == true)

        // Edycja: CLOB i BLOB z Large Data Editor, zapis przez Post.
        try await ws.invoke("grid.edit")
        let e1 = LargeDataModel(grid: grid, row: 0, column: 2)
        #expect(e1.isEditable)
        e1.setText("Nowa treść ✓")
        try e1.apply()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 7, count: 100_000)
        let e2 = LargeDataModel(grid: grid, row: 0, column: 3)
        e2.setBytes(png)
        #expect(e2.format == .png)
        try e2.apply()
        try await ws.invoke("grid.post")
        let s = try await ws.session(for: doc)
        let (_, r) = try await s.queryAll("select dbms_lob.getlength(body), dbms_lob.getlength(data), dbms_lob.substr(body, 20, 1) from docs where id = 1")
        #expect(r.first?[0].displayText == "12")
        #expect(r.first?[1].displayText == "100008")
        #expect(r.first?[2].displayText == "Nowa treść ✓")
        try await ws.invoke("session.rollback")
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Command Window na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct CommandWindowIntegrationTests {
    func make() throws -> (Workspace, Document, TestUI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, ws.newDocument(.command), ui)
    }

    func output(_ doc: Document) -> String { doc.console.map(\.text).joined(separator: "\n") }

    @Test("Skrypt: SET, DEFINE, VARIABLE/EXEC/PRINT, SELECT jako tekst, SERVEROUTPUT, PROMPT, TIMING, FEEDBACK")
    func script() async throws {
        let (ws, doc, _) = try make()
        doc.text = """
        set feedback on
        set serveroutput on
        define dept = 10
        prompt Pracownicy działu &dept
        variable cnt number
        exec select count(*) into :cnt from emp where deptno = &dept
        print cnt
        column ename heading 'Nazwisko' format a12
        select empno, ename from emp where deptno = &dept order by empno;
        begin dbms_output.put_line('Zażółć'); end;
        /
        set timing on
        select 1 x from dual;
        """
        try await ws.invoke("sql.execute")
        let out = output(doc)
        #expect(out.contains("Pracownicy działu 10"))
        #expect(out.contains("Procedura PL/SQL została zakończona pomyślnie."))
        #expect(out.contains("       CNT\n----------\n         2"))
        #expect(out.contains("     EMPNO Nazwisko\n---------- ------------\n      7782 WÓJCIK\n      7839 KOWALSKI"))
        #expect(out.contains("Wybrano wierszy: 2"))
        #expect(out.contains("Zażółć"))
        #expect(out.contains("Czas: 00:00:"))
        #expect(out.contains("stara: ") && out.contains("nowa: "))       // VERIFY ON
        await ws.sessions.disconnectAll()
    }

    @Test("Niezdefiniowana zmienna — pytanie w oknie Zmienne; && zapamiętuje; ACCEPT z DEFAULT")
    func substitutionPrompt() async throws {
        let (ws, doc, ui) = try make()
        ui.variables = ["NR": .text("7839"), "A": .text("x")]
        doc.text = "set verify off\nselect ename from emp where empno = &&nr;\nselect ename from emp where empno = &nr;\naccept a prompt 'Podaj A' default q\nprompt A=&a"
        try await ws.invoke("sql.execute")
        #expect(ui.askedVariables.map(\.name) == ["A"])          // ostatnie pytanie: ACCEPT; NR zapamiętane po pierwszym
        #expect(output(doc).components(separatedBy: "KOWALSKI").count == 3)
        #expect(output(doc).contains("A=x"))
        await ws.sessions.disconnectAll()
    }

    @Test("Kompilacja z błędami, SHOW ERRORS, DESCRIBE tabeli i pakietu, błąd ORA bez przerywania skryptu")
    func compileAndDescribe() async throws {
        let (ws, doc, _) = try make()
        doc.text = """
        create or replace procedure pelikan_cw_bad as begin brak_procedury; end;
        /
        show errors
        desc emp
        describe emp_api
        select * from tabela_ktorej_nie_ma;
        prompt dalej
        drop procedure pelikan_cw_bad;
        """
        try await ws.invoke("sql.execute")
        let out = output(doc)
        #expect(out.contains("Ostrzeżenie: utworzono z błędami kompilacji."))
        #expect(out.contains("PLS-00201"))
        #expect(out.contains("LINE/COL ERROR"))
        #expect(out.contains(" EMPNO") && out.contains("NOT NULL") && out.contains("NUMBER(6)"))
        #expect(out.contains("PROCEDURE RAISE_SALARY"))
        #expect(out.contains("ORA-00942"))
        #expect(out.contains("dalej"))
        #expect(out.contains("Usunięto: PROCEDURE."))
        await ws.sessions.disconnectAll()
    }

    @Test("@plik z parametrami, @@ względem skryptu, SPOOL do pliku, WHENEVER SQLERROR EXIT ROLLBACK")
    func filesAndWhenever() async throws {
        let (ws, doc, ui) = try make()
        ui.askAnswer = 1        // EXIT zamyka okno: „Nie zapisuj” skryptu z karty Edytor
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-cw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "prompt main &1 &2\n@@inner".write(to: dir.appendingPathComponent("sub/main.sql"), atomically: true, encoding: .utf8)
        try "prompt inner".write(to: dir.appendingPathComponent("sub/inner.sql"), atomically: true, encoding: .utf8)
        let spool = dir.appendingPathComponent("wynik.lst")
        doc.text = """
        cd \(dir.path)
        spool wynik
        @sub/main a b
        spool off
        whenever sqlerror exit rollback
        update emp set comm = 1 where empno = 7369;
        select * from brak_tabeli;
        prompt tego nie będzie
        """
        try await ws.invoke("sql.execute")
        let out = output(doc)
        #expect(out.contains("main a b"))
        #expect(out.contains("inner"))
        #expect(!out.contains("tego nie będzie"))
        let spooled = try String(contentsOf: spool, encoding: .utf8)
        #expect(spooled.contains("main a b") && spooled.contains("inner"))
        #expect(ws.documents.isEmpty)        // EXIT zamknął okno; ROLLBACK wycofał UPDATE
        await ws.sessions.disconnectAll()
    }

    @Test("CONNECT do zapisanego połączenia, SHOW USER, linia z karty Dialog i historia linii")
    func connectAndDialog() async throws {
        let (ws, doc, _) = try make()
        let c = TestDatabase.config!
        let agent = ConnectionDefinition(name: "dev_agent_test", target: ConnectionTarget(user: c.agentUser, connectString: c.connectString))
        try ws.connections.upsert(agent, password: c.agentPassword)
        try await ws.invoke("cmd.executeLine", CommandArguments(["line": .string("connect dev_agent_test")]))
        try await ws.invoke("cmd.executeLine", CommandArguments(["line": .string("show user")]))
        #expect(output(doc).contains("USER to „\(c.agentUser.uppercased())”"))
        #expect(doc.commandLineHistory == ["connect dev_agent_test", "show user"])
        #expect(doc.console.contains { $0.kind == .prompt && $0.text == "SQL> show user" })
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Tunel SSH do bazy testowej", .serialized,
       .enabled(if: TestDatabase.isAvailable && TestDatabase.config?.sshPort != nil
                && FileManager.default.fileExists(atPath: (TestDatabase.config?.sshDirectory ?? "") + "/id_ed25519")))
struct SSHTunnelIntegrationTests {
    func workspace(identity: String) throws -> (Workspace, ConnectionDefinition) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let dir = c.sshDirectory!
        ws.sessions.tunnels.extraOptions = ["-o", "UserKnownHostsFile=\(dir)/known_hosts", "-o", "StrictHostKeyChecking=yes", "-F", "/dev/null"]
        // Baza widziana z bastionu (sieć Docker), nie z Maca.
        var def = ConnectionDefinition(name: "dev_przez_ssh", target: ConnectionTarget(user: c.user, connectString: "\(c.sshDBHost ?? "pelikan-testdb"):1521/FREEPDB1"))
        def.sshTunnel = SSHTunnel(host: "127.0.0.1", port: c.sshPort!, user: "tunnel", identityFile: identity)
        try ws.connections.upsert(def, password: c.password)
        return (ws, def)
    }

    @Test("Połączenie przez tunel: zapytanie działa, tunel współdzielony przez sesje, zamykany z ostatnią sesją")
    func tunnel() async throws {
        let c = TestDatabase.config!
        let (ws, def) = try workspace(identity: c.sshDirectory! + "/id_ed25519")
        let s1 = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        let s2 = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .compile))
        #expect(ws.sessions.tunnels.isOpen(def.id))
        let (_, rows) = try await s1.queryAll("select count(*) from emp")
        #expect(rows.first?.first?.displayText == "8")
        #expect(s2.info.sessionUser == c.user.uppercased())
        await ws.sessions.close(SessionKey(connectionID: def.id, purpose: .main))
        #expect(ws.sessions.tunnels.isOpen(def.id))
        await ws.sessions.close(SessionKey(connectionID: def.id, purpose: .compile))
        #expect(!ws.sessions.tunnels.isOpen(def.id))
    }

    @Test("Tunel z hasłem SSH z Pęku kluczy (askpass przez kolejkę); złe hasło — czytelny błąd (DB-SSH-001)",
          .enabled(if: TestDatabase.config?.sshPassword != nil))
    func passwordTunnel() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let dir = c.sshDirectory!
        ws.sessions.tunnels.extraOptions = ["-o", "UserKnownHostsFile=\(dir)/known_hosts", "-o", "StrictHostKeyChecking=yes", "-F", "/dev/null"]
        var def = ConnectionDefinition(name: "dev_ssh_haslo", target: ConnectionTarget(user: c.user, connectString: "\(c.sshDBHost ?? "pelikan-testdb"):1521/FREEPDB1"))
        def.sshTunnel = SSHTunnel(host: "127.0.0.1", port: c.sshPort!, user: "haslo", usesPassword: true)
        try ws.connections.upsert(def, password: c.password)
        await #expect(throws: (any Error).self) { _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main)) }
        try ws.connections.setSSHPassword(c.sshPassword!, for: def.id)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(try await s.queryAll("select 1 from dual").rows.first?.first?.displayText == "1")
        await ws.sessions.close(SessionKey(connectionID: def.id, purpose: .main))
        try ws.connections.setSSHPassword("zle-haslo", for: def.id)
        do {
            _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
            Issue.record("złe hasło nie powinno otworzyć tunelu")
        } catch {
            #expect("\(error)".contains("Permission denied") && !"\(error)".contains("zle-haslo"))
        }
        #expect(!ws.sessions.tunnels.isOpen(def.id))
        await ws.sessions.disconnectAll()
    }

    @Test("Zły klucz: czytelny błąd ssh, bez wiszącego procesu")
    func wrongKey() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = dir.appendingPathComponent("zly").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        p.arguments = ["-q", "-t", "ed25519", "-N", "", "-f", key]
        try p.run()
        p.waitUntilExit()
        let (ws, def) = try workspace(identity: key)
        do {
            _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
            Issue.record("połączenie nie powinno się udać")
        } catch {
            #expect(error.localizedDescription.contains("Tunel SSH nie powstał"))
            #expect(error.localizedDescription.contains("Permission denied"))
        }
        #expect(!ws.sessions.tunnels.isOpen(def.id))
    }
}

@MainActor
@Suite("Sesje okien na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct WindowSessionsIntegrationTests {
    func make() throws -> (Workspace, ConnectionDefinition, TestUI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def, ui)
    }

    @Test("Dwa okna wykonują się równolegle w osobnych sesjach (tryb Multi)")
    func parallel() async throws {
        let (ws, _, _) = try make()
        let a = ws.newDocument(.sql)
        a.text = "select count(*) from big_rows x, (select level from dual connect by level <= 20)"
        let b = ws.newDocument(.sql)
        b.text = "select count(*) from big_rows x, (select level from dual connect by level <= 20)"
        let clock = ContinuousClock()
        let single = try await clock.measure { _ = try await SQLExecutor.execute(a, scope: .standard, in: ws) }
        let both = try await clock.measure {
            async let r1 = SQLExecutor.execute(a, scope: .standard, in: ws)
            async let r2 = SQLExecutor.execute(b, scope: .standard, in: ws)
            _ = try await (r1, r2)
        }
        #expect(a.results.first?.grid?.rowCount == 1 && b.results.first?.grid?.rowCount == 1)
        #expect(ws.sessions.openSessionCount >= 2)
        #expect(both < single * 1.8)       // nie sekwencyjnie
        await ws.sessions.disconnectAll()
    }

    @Test("Wylogowanie z otwartą transakcją pyta o COMMIT/ROLLBACK (domyślnie pytaj) i wycofuje po wyborze")
    func logoffWithTransaction() async throws {
        let (ws, _, ui) = try make()
        let doc = ws.newDocument(.sql)
        doc.text = "update emp set comm = 11 where empno = 7369"
        try await ws.invoke("sql.execute")
        #expect(doc.transactionOpen)
        ui.askAnswer = 1            // Wycofaj (ROLLBACK)
        try await ws.invoke("session.logoff")
        #expect(ui.asked.contains("Niezatwierdzone zmiany"))
        #expect(!doc.transactionOpen)
        #expect(ws.sessions.openSessionCount == 0)
        ws.sessions.setMainConnection(ws.connections.connections.first!.id)
        doc.text = "select comm from emp where empno = 7369"
        try await ws.invoke("sql.execute")
        #expect(doc.results.first?.grid?.text(row: 0, column: 0) == "")
        await ws.sessions.disconnectAll()
    }

    @Test("Rola SYSDBA (konto SYS kontenera testowego)")
    func sysdba() async throws {
        let c = TestDatabase.config!
        var target = ConnectionTarget(user: "SYS", connectString: c.connectString)
        target.role = .sysdba
        let s = try await ODPIDriver().connect(target: target, credentials: Credentials(password: c.systemPassword), options: ConnectOptions())
        #expect(try await s.scalar("select sys_context('USERENV', 'ISDBA') from dual") == "TRUE")
        await s.close()
    }
}

@Suite("Alias TNS z katalogu połączenia (Instant Client)", .enabled(if: TestDatabase.isAvailable))
struct ConfigDirectoryIntegrationTests {
    @Test("Połączenie po aliasie z tnsnames.ora w katalogu konfiguracji połączenia")
    func alias() async throws {
        let c = TestDatabase.config!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-tnsdir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let parts = c.connectString.split(separator: "/")
        let hp = parts[0].split(separator: ":")
        try "PELIKAN_TEST_ALIAS = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=\(hp[0]))(PORT=\(hp[1])))(CONNECT_DATA=(SERVICE_NAME=\(parts[1]))))"
            .write(to: dir.appendingPathComponent("tnsnames.ora"), atomically: true, encoding: .utf8)
        let s = try await ODPIDriver().connect(target: ConnectionTarget(user: c.user, connectString: "pelikan_test_alias", configDirectory: dir.path),
                                               credentials: Credentials(password: c.password), options: ConnectOptions())
        #expect(try await s.scalar("select 1 from dual") == "1")
        await s.close()
    }
}
