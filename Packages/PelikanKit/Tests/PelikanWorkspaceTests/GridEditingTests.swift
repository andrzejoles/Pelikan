import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@Suite("Edycja siatki — bez bazy")
struct GridEditingUnitTests {
    @Test("Lista SELECT: gwiazdka, kwalifikatory, aliasy (AS i bez), wyrażenia, ROWID")
    func selectList() {
        let items = SelectListParser.items("select e.*, e.rowid, ename as nazwisko, d.dname, sal * 2 podwojna, count(*), \"Mała\" from emp e, dept d")
        #expect(items[0] == .init(qualifier: "E", isStar: true))
        #expect(items[1] == .init(qualifier: "E", isRowid: true))
        #expect(items[2] == .init(column: "ENAME", alias: "NAZWISKO"))
        #expect(items[3] == .init(qualifier: "D", column: "DNAME"))
        #expect(items[4] == .init(alias: "PODWOJNA"))
        #expect(items[5] == .init())
        #expect(items[6] == .init(column: "Mała"))
        #expect(SelectListParser.items("select distinct (select 1 from dual) x, rowid from t").map(\.alias) == ["X", nil])
        // Słowa kluczowe niezastrzeżone jako nazwy kolumn i aliasy.
        #expect(SelectListParser.items("select d.body, data, type, sal body from docs d").map(\.column) == ["BODY", "DATA", "TYPE", "SAL"])
        #expect(SelectListParser.items("select sal body from emp")[0].alias == "BODY")
    }

    @Test("Daty z tekstu wg maski Oracle (z czasem, bez czasu, AM/PM, ułamki)")
    func dates() {
        #expect(OracleTimestamp.parse("2024-02-29 13:05:09", mask: "YYYY-MM-DD HH24:MI:SS") == OracleTimestamp(year: 2024, month: 2, day: 29, hour: 13, minute: 5, second: 9))
        #expect(OracleTimestamp.parse("2024-02-29", mask: "YYYY-MM-DD HH24:MI:SS") == OracleTimestamp(year: 2024, month: 2, day: 29))
        #expect(OracleTimestamp.parse("29.02.2024", mask: "DD.MM.YYYY") == OracleTimestamp(year: 2024, month: 2, day: 29))
        #expect(OracleTimestamp.parse("01-JAN-24 01:30 PM", mask: "DD-MON-YY HH:MI AM") == OracleTimestamp(year: 2024, month: 1, day: 1, hour: 13, minute: 30))
        #expect(OracleTimestamp.parse("2024-01-01 00:00:00.123", mask: "YYYY-MM-DD HH24:MI:SS.FF")?.fsecond == 123_000_000)
        #expect(OracleTimestamp.parse("2024-13-01", mask: "YYYY-MM-DD") == nil)
        #expect(OracleTimestamp.parse("jutro", mask: "YYYY-MM-DD") == nil)
    }

    @Test("Wartość z komórki: liczba (przecinek dziesiętny), NULL, błąd; przekroczenie rozmiaru i precyzji")
    @MainActor
    func parseAndOverflow() throws {
        let num = ColumnInfo(name: "SAL", type: .number, typeName: "NUMBER(7,2)", precision: 7, scale: 2)
        #expect(try ResultGridModel.parse("1234,5", column: num, format: .default, decimal: ",") == .number("1234.5"))
        // Separator dziesiętny kropka (en_US): „1,000” to nie 1 — błąd zamiast cichej zmiany wartości.
        #expect(throws: GridEditError.self) { try ResultGridModel.parse("1,000", column: num, format: .default, decimal: ".") }
        #expect(try ResultGridModel.parse("12.5", column: num, format: .default, decimal: ".") == .number("12.5"))
        #expect(try ResultGridModel.parse("", column: num, format: .default) == .null)
        #expect(throws: GridEditError.self) { try ResultGridModel.parse("12a", column: num, format: .default) }
        #expect(ResultGridModel.exceedsColumn(.number("123456"), num))
        #expect(!ResultGridModel.exceedsColumn(.number("12345.67"), num))
        let txt = ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2(5)", size: 5)
        #expect(ResultGridModel.exceedsColumn(.text("żółwie"), txt))
        #expect(!ResultGridModel.exceedsColumn(.text("żółw"), txt))
    }

    @Test("Post: UPDATE/DELETE bez zmienionego wiersza — błąd; wstawienie bez wartości — DEFAULT dla każdej kolumny")
    @MainActor
    func postRowsAffected() async throws {
        let columns = [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER"), ColumnInfo(name: "NAME", type: .varchar2, typeName: "VARCHAR2(20)"),
                       ColumnInfo(name: "ROWID", type: .rowid, typeName: "ROWID")]
        let rows: [[OracleValue]] = [[.number("1"), .text("a"), .text("AAA1")]]
        // Atrapa zwraca rowsAffected = 0 — jak po zmianie wiersza przez inną sesję.
        let g = ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession(rows), sql: "select id, name, rowid from t", format: ValueFormat())
        await g.fetchAll()
        g.edit.target = EditTarget(owner: "U", table: "T", rowidColumn: 2, editableColumns: [0, 1], tableColumn: [0: "ID", 1: "NAME"])
        g.edit.isEditing = true
        try g.setText("b", row: 0, column: 1)
        await #expect(throws: GridEditError.self) { try await g.postChanges() }
        #expect(g.edit.changed[0] != nil)
        g.revertRows([0])
        _ = try g.insertRecord()
        #expect(g.changesSQL() == "INSERT INTO U.T (ID, NAME) VALUES (DEFAULT, DEFAULT);")
    }

    @Test("Kolumna z komunikatu ORA-12899 / ORA-01400")
    @MainActor
    func errorColumn() {
        let cols = [ColumnInfo(name: "EMPNO", type: .number, typeName: "NUMBER"), ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2")]
        #expect(ResultGridModel.columnFromError("ORA-12899: value too large for column \"PELIKAN_TEST\".\"EMP\".\"ENAME\" (actual: 60, maximum: 40)", columns: cols) == 1)
        #expect(ResultGridModel.columnFromError("ORA-01400: cannot insert NULL into (\"PELIKAN_TEST\".\"EMP\".\"EMPNO\")", columns: cols) == 0)
    }
}

@Suite("Large Data Editor — bez bazy")
struct LargeDataUnitTests {
    @Test("Rozpoznanie formatu po sygnaturze i początku tekstu")
    func detect() {
        #expect(LargeDataFormat.detect(text: "  <?xml version=\"1.0\"?><a/>", bytes: nil) == .xml)
        #expect(LargeDataFormat.detect(text: "<!DOCTYPE html><html>", bytes: nil) == .html)
        #expect(LargeDataFormat.detect(text: "{\"a\":1}", bytes: nil) == .json)
        #expect(LargeDataFormat.detect(text: "zwykły tekst", bytes: nil) == .text)
        #expect(LargeDataFormat.detect(text: nil, bytes: Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(LargeDataFormat.detect(text: nil, bytes: Data("%PDF-1.7".utf8)) == .pdf)
        #expect(LargeDataFormat.detect(text: nil, bytes: Data([0, 1, 2, 3])) == .binary)
        #expect(LargeDataFormat.detect(text: nil, bytes: Data("<a>tekst w BLOB</a>".utf8)) == .xml)
    }

    @Test("Podgląd hex: offset, bajty, ASCII, ograniczenie długości")
    func hex() {
        let d = Data("Pelikan".utf8) + Data([0, 255])
        #expect(LargeDataModel.hexDump(d) == "00000000  50 65 6C 69 6B 61 6E 00 FF" + String(repeating: "   ", count: 7) + "  Pelikan..\n")
        #expect(LargeDataModel.hexDump(Data(count: 100), limit: 32).hasSuffix("(pokazano 32 z 100 bajtów)\n"))
    }
}
