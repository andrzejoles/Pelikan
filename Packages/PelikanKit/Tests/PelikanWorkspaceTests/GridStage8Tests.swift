import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Siatka i SQL Window — Etap 8 (bez bazy)")
struct GridStage8Tests {
    let columns = [ColumnInfo(name: "EMPNO", type: .number, typeName: "NUMBER", nullable: false),
                   ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2(10)"),
                   ColumnInfo(name: "SAL", type: .number, typeName: "NUMBER"),
                   ColumnInfo(name: "HIREDATE", type: .date, typeName: "DATE"),
                   ColumnInfo(name: "NOTES", type: .clob, typeName: "CLOB")]

    var rows: [[OracleValue]] {
        [[.number("1"), .text("KING"), .number("5000"), .timestamp(OracleTimestamp(year: 1981, month: 11, day: 17), .date), .null],
         [.number("2"), .text("adams"), .number("1100.5"), .timestamp(OracleTimestamp(year: 1987, month: 5, day: 23), .date), .null],
         [.number("3"), .text("Blake"), .null, .null, .null]]
    }

    func grid(_ rows: [[OracleValue]]? = nil) async -> ResultGridModel {
        let g = ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession(rows ?? self.rows), sql: "select * from emp", format: ValueFormat())
        await g.fetchAll()
        return g
    }

    @Test("Sumy: suma, liczba, średnia, min, max; dyrektywa Totals= z funkcjami i kolumnami")
    func totals() async {
        let g = await grid()
        let v = Dictionary(uniqueKeysWithValues: ColumnTotals.compute(g, column: 2, ColumnAggregate.allCases).map { ($0.0, $0.1) })
        #expect(v[.sum] == "6100.5" && v[.count] == "2" && v[.avg] == "3050.25" && v[.min] == "1100.5" && v[.max] == "5000")
        let names = Dictionary(uniqueKeysWithValues: ColumnTotals.compute(g, column: 1, [.min, .max, .count]).map { ($0.0, $0.1) })
        #expect(names[.min] == "adams" && names[.max] == "KING" && names[.count] == "3")
        let parsed = ColumnTotals.parse("sum+avg: sal; count:ename, nieznana", columns: columns)
        #expect(parsed[2] == [.sum, .avg] && parsed[1] == [.count] && parsed.count == 2)
        #expect(ColumnTotals.parse("sal", columns: columns)[2] == [.sum])
        #expect(ColumnTotals.summary(g, totals: [2: [.sum]]).hasPrefix("SAL: "))
    }

    @Test("Filtr kolumn: fragmenty nazw z wklejonej listy, typy, obowiązkowe, klucze")
    func columnFilter() {
        #expect(ColumnFilter.names(from: "ename\nsal,\thire") == ["ename", "sal", "hire"])
        #expect(ColumnFilter(names: ["NAM", "sal"]).visible(columns) == [1, 2])
        #expect(ColumnFilter(types: [.date, .lob]).visible(columns) == [3, 4])
        #expect(ColumnFilter(mandatoryOnly: true).visible(columns) == [0])
        #expect(ColumnFilter(mandatoryOnly: true).visible(columns, mandatory: ["ENAME"]) == [0, 1])
        #expect(ColumnFilter(keys: [.primary]).visible(columns, keyInfo: ["EMPNO": [.primary]]) == [0])
        #expect(ColumnFilter().isEmpty && !ColumnFilter(names: ["x"]).isEmpty)
    }

    @Test("Wyrównanie: wg nagłówka, treści i obu; szablon z kolejnością i szerokościami wg nazw")
    func align() async {
        let g = await grid()
        #expect(GridAlign.widths(g, mode: .header)[0] == 5 && GridAlign.widths(g, mode: .content)[0] == 2)
        #expect(GridAlign.widths(g, mode: .both)[3] == 19)
        #expect(GridAlign.key(for: "SELECT *\n  FROM emp;") == "select * from emp")
        let tab = ResultTab(title: "t", statementRange: 0..<0, grid: g)
        tab.columnOrder = [2, 0, 1, 3, 4]
        tab.columnWidths = [2: 12]
        let t = GridAlign.template(g, tab: tab)
        #expect(t.order.first == "SAL" && t.widths["SAL"] == 12)
        let other = ResultTab(title: "u", statementRange: 0..<0, grid: g)
        GridAlign.apply(AlignTemplate(order: ["SAL", "BRAK"], widths: ["ENAME": 30]), to: g, tab: other)
        #expect(other.columnOrder == [2, 0, 1, 3, 4] && other.columnWidths == [1: 30])
    }

    @Test("Query By Example: wartości, wzorce, operatory, IN, BETWEEN, NULL, daty bez czasu, wielkość liter, błędy")
    func qbe() throws {
        let e = columns[1], n = columns[2], d = columns[3]
        #expect(try QueryByExample.predicate(column: e, expression: "king") == #"UPPER(x.ENAME) = UPPER('king')"#)
        #expect(try QueryByExample.predicate(column: e, expression: "K%", options: QBEOptions(caseInsensitive: false)) == #"x.ENAME LIKE 'K%'"#)
        #expect(try QueryByExample.predicate(column: e, expression: "ing", options: QBEOptions(caseInsensitive: false, autoContains: true)) == #"x.ENAME LIKE '%ing%'"#)
        #expect(try QueryByExample.predicate(column: n, expression: ">= 1000") == #"x.SAL >= 1000"#)
        #expect(try QueryByExample.predicate(column: n, expression: "!=5") == #"x.SAL <> 5"#)
        #expect(try QueryByExample.predicate(column: n, expression: "in (1, 2,3)") == #"x.SAL IN (1, 2, 3)"#)
        #expect(try QueryByExample.predicate(column: e, expression: "not in ('A', b)", options: QBEOptions(caseInsensitive: false)) == #"x.ENAME NOT IN ('A', 'b')"#)
        #expect(try QueryByExample.predicate(column: n, expression: "between 1 and 2") == #"x.SAL BETWEEN 1 AND 2"#)
        #expect(try QueryByExample.predicate(column: n, expression: "null") == #"x.SAL IS NULL"#)
        #expect(try QueryByExample.predicate(column: n, expression: "not null") == #"x.SAL IS NOT NULL"#)
        #expect(try QueryByExample.predicate(column: d, expression: "1981-11-17") == #"TRUNC(x.HIREDATE) = TO_DATE('1981-11-17', 'YYYY-MM-DD')"#)
        #expect(try QueryByExample.predicate(column: d, expression: "> 1981-11-17 10:00") == #"x.HIREDATE > TO_DATE('1981-11-17 10:00', 'YYYY-MM-DD HH24:MI')"#)
        #expect(try QueryByExample.predicate(column: e, expression: "O'Neil", options: QBEOptions(caseInsensitive: false)) == #"x.ENAME = 'O''Neil'"#)
        #expect(throws: QueryByExample.Failure.self) { try QueryByExample.predicate(column: n, expression: "abc") }
        #expect(throws: QueryByExample.Failure.self) { try QueryByExample.predicate(column: n, expression: "1; drop table emp") }
        // Apostrof w dacie podwojony; przecinek dziesiętny tylko przy takim separatorze regionalnym.
        #expect(try QueryByExample.literal("2024-01'-01", column: d).sql == "TO_DATE('2024-01''-01', 'YYYY-MM-DD')")
        #expect(try QueryByExample.literal("1,5", column: n, decimal: ",").sql == "1.5")
        #expect(throws: QueryByExample.Failure.self) { try QueryByExample.literal("1,000", column: n, decimal: ".") }
        let sql = try QueryByExample.apply(sql: "select * from emp;", criteria: [(n, ">1000"), (e, "  ")])
        #expect(sql == "select * from (\nselect * from emp\n) x\n where x.SAL > 1000")
        #expect(try QueryByExample.apply(sql: "select 1 from dual", criteria: []) == "select 1 from dual")
    }

    @Test("Dyrektywy Excel=/CSV=: zmienne nazwy pliku, ścieżka względna")
    func exportPath() {
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 24, hour: 7, minute: 5, second: 9).date!
        let u = ExportDirectives.path("raporty/%dbuser%_%date%_%time%_%&dept%.xlsx", user: "SCOTT", database: "db1", values: ["DEPT": .text("10")],
                                      now: now, base: URL(fileURLWithPath: "/tmp/b"))
        #expect(u.path == "/tmp/b/raporty/SCOTT_2026-10-24_070509_10.xlsx")
        #expect(ExportDirectives.path("/x/%dbname%.csv", user: "", database: "host:1521/svc", values: [:], now: now, base: URL(fileURLWithPath: "/b")).path
                == "/x/host-1521/svc.csv")
    }

    @Test("Lista wartości z CHECK … IN (…): cudzysłowy, liczby, apostrof w wartości; inny warunek — nil")
    func checkValues() {
        #expect(GridDictionary.checkValues("status IN ('A','B', 'C''D')", column: "STATUS") == ["A", "B", "C'D"])
        #expect(GridDictionary.checkValues("(\"LEVEL\" in (1, 2, 3))", column: "LEVEL") == ["1", "2", "3"])
        #expect(GridDictionary.checkValues("sal > 0", column: "SAL") == nil)
        #expect(GridDictionary.checkValues("other in ('x')", column: "SAL") == nil)
        let info = ColumnDictionaryInfo(type: "NUMBER(4)", nullable: false, comment: "Numer", keys: [.primary], values: [])
        #expect(info.statusLine == "NUMBER(4) NOT NULL · PK — Numer")
    }

    @Test("Limit rozmiaru wyniku: po przekroczeniu pytanie; odmowa zatrzymuje, zgoda pobiera dalej")
    func sizeLimit() async {
        let many = (0..<300).map { [OracleValue.number(String($0)), .text(String(repeating: "x", count: 200)), .null, .null, .null] }
        let g = ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession(many), sql: "select * from emp", format: ValueFormat())
        g.sizeLimitBytes = 10_000
        var asked = 0
        g.confirmSizeLimit = { _ in asked += 1; return false }
        await g.fetchMore(100)
        await g.fetchAll()
        #expect(g.rowCount == 100 && g.stoppedAtSizeLimit && asked == 1 && g.approximateBytes > 10_000)
        g.confirmSizeLimit = { _ in asked += 1; return true }
        await g.fetchMore(100)
        await g.fetchAll()
        #expect(g.rowCount == 300 && !g.stoppedAtSizeLimit && asked == 2)
    }

    @Test("Numer wiersza w kopii, kolumny ukryte filtrem pominięte; przypinanie i czyszczenie kart")
    func copyAndPin() async throws {
        let ws = Workspace()
        let ui = GridUI()
        ws.ui = ui
        let doc = ws.newDocument(.sql, text: "select * from emp")
        let g = await grid()
        let tab = ResultTab(title: "Select emp", statementRange: 0..<17, grid: g)
        tab.hiddenColumns = [3, 4]
        let msg = ResultTab(title: "Update", statementRange: 0..<0, message: "Wierszy: 1")
        doc.results = [tab, msg]
        doc.activeResultID = tab.id
        tab.selectedRows = [1]
        ws.settings.rowNumbersInCopyExport = true
        try await ws.invoke("grid.copyWithHeader")
        #expect(ui.clipboard?.hasPrefix("#\tEMPNO\tENAME\tSAL\n2\t2\tadams\t1100.5") == true)
        try await ws.invoke("grid.toggleRowNumbers")
        try await ws.invoke("grid.copy")
        #expect(ui.clipboard?.hasPrefix("2\tadams") == true)
        try await ws.invoke("sql.pinResult")
        #expect(tab.pinned)
        try await ws.invoke("sql.clearResults")
        #expect(doc.results.map(\.id) == [tab.id])
        try await ws.invoke("sql.clearResults", CommandArguments(["all": .bool(true)]))
        #expect(doc.results.isEmpty)
    }

    @Test("Czcionka siatki, sumy kolumn zapamiętane w oknie, filtr kolumn i wyrównanie z komend")
    func gridCommands() async throws {
        let ws = Workspace()
        let ui = GridUI()
        ws.ui = ui
        let doc = ws.newDocument(.sql, text: "select * from emp")
        let g = await grid()
        let tab = ResultTab(title: "t", statementRange: 0..<17, grid: g)
        doc.results = [tab]
        doc.activeResultID = tab.id
        try await ws.invoke("grid.fontLarger")
        try await ws.invoke("grid.fontLarger")
        #expect(ws.settings.gridFontSize == 14)
        try await ws.invoke("grid.fontReset")
        #expect(ws.settings.gridFontSize == 12)
        let r = try await ws.invoke("grid.totals", CommandArguments(["column": "sal", "functions": "sum,max"]))
        #expect(r.value == .object(["sum": .string("6100.5"), "max": .string("5000")]) && doc.columnTotals["SAL"] == [.sum, .max])
        try await ws.invoke("grid.columnFilter", CommandArguments(["names": "name\nsal", "types": "number,text"]))
        #expect(tab.hiddenColumns == [0, 3, 4] && ws.settings.columnFilterHistory.first == "name\nsal")
        try await ws.invoke("grid.clearColumnFilter")
        #expect(tab.hiddenColumns.isEmpty)
        try await ws.invoke("grid.align", CommandArguments(["mode": "header"]))
        #expect(tab.columnWidths?[1] == 5)
        try await ws.invoke("grid.saveAlignTemplate")
        #expect(ws.settings.alignTemplates["select * from emp"]?.widths["ENAME"] == 5)
        await #expect(throws: (any Error).self) { try await ws.invoke("grid.align", CommandArguments(["mode": "zle"])) }
    }

    @Test("Listy zależne: :zmienna i &zmienna z wartości innych zmiennych; pusta zależność — lista pusta")
    func dependentLists() {
        let q = "select ename from emp where deptno = :dept and job like '&job%'"
        #expect(VariableLists.dependencies(of: q) == ["dept", "job"])
        #expect(VariableLists.prepare(q, values: ["dept": "10"]) == nil)
        let p = VariableLists.prepare(q, values: ["dept": "10", "job": "CLERK"])
        #expect(p?.sql == "select ename from emp where deptno = :dept and job like 'CLERK%'" && p?.binds.first?.name == "dept")
    }

    @Test("Workset zapamiętuje wartości zmiennych okna (tekst, lista, NULL)")
    func worksetVariables() throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let doc = ws.newDocument(.sql, text: "select :a, &b from dual")
        doc.variableValues = ["a": .text("1"), "b": .list(["x", "y"]), "c": .null]
        let snap = ws.worksetSnapshot()
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(Workset.self, from: data)
        ws.applyWorkset(back)
        let restored = try #require(ws.documents.first)
        #expect(restored.variableValues == ["a": .text("1"), "b": .list(["x", "y"]), "c": .null])
    }

    @Test("Wklejenie jako nowe SQL Window")
    func pasteAsWindow() async throws {
        let ws = Workspace()
        let ui = GridUI()
        ws.ui = ui
        ui.text = "select 1 from dual"
        try await ws.invoke("file.pasteAsSQLWindow")
        #expect(ws.activeDocument?.kind == .sql && ws.activeDocument?.text == "select 1 from dual")
        ui.text = nil
        await #expect(throws: (any Error).self) { try await ws.invoke("file.pasteAsSQLWindow") }
    }
}

@MainActor
final class GridUI: UIServices {
    var text: String?
    var clipboard: String?
    func clipboardText() -> String? { text }
    func copyToClipboard(_ text: String, html: String?) { clipboard = text }
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { 0 }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { [:] }
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { true }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { nil }
}
