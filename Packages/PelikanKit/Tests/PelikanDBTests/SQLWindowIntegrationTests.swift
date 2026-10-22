import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu: odpowiada na okno zmiennych podanymi wartościami.
@MainActor
final class TestUI: UIServices {
    var variables: [String: VariableValue] = [:]
    var askedVariables: [VariableRequest] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { 0 }
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
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
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
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
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
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
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
        try? await ws.invoke("session.rollback")
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
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
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
