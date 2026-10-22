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
        #expect(try ResultGridModel.parse("1234,5", column: num, format: .default) == .number("1234.5"))
        #expect(try ResultGridModel.parse("", column: num, format: .default) == .null)
        #expect(throws: GridEditError.self) { try ResultGridModel.parse("12a", column: num, format: .default) }
        #expect(ResultGridModel.exceedsColumn(.number("123456"), num))
        #expect(!ResultGridModel.exceedsColumn(.number("12345.67"), num))
        let txt = ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2(5)", size: 5)
        #expect(ResultGridModel.exceedsColumn(.text("żółwie"), txt))
        #expect(!ResultGridModel.exceedsColumn(.text("żółw"), txt))
    }

    @Test("Kolumna z komunikatu ORA-12899 / ORA-01400")
    @MainActor
    func errorColumn() {
        let cols = [ColumnInfo(name: "EMPNO", type: .number, typeName: "NUMBER"), ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2")]
        #expect(ResultGridModel.columnFromError("ORA-12899: value too large for column \"PELIKAN_TEST\".\"EMP\".\"ENAME\" (actual: 60, maximum: 40)", columns: cols) == 1)
        #expect(ResultGridModel.columnFromError("ORA-01400: cannot insert NULL into (\"PELIKAN_TEST\".\"EMP\".\"EMPNO\")", columns: cols) == 0)
    }
}
