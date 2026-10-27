import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@Suite("Eksport wyniku")
struct ResultExportTests {
    let data = ExportData(
        title: "Pracownicy",
        columns: [ColumnInfo(name: "EMPNO", type: .number, typeName: "NUMBER(4)"),
                  ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2(30)"),
                  ColumnInfo(name: "HIREDATE", type: .date, typeName: "DATE"),
                  ColumnInfo(name: "COMM", type: .number, typeName: "NUMBER(7,2)")],
        rows: [[.number("7369"), .text("Szymańska, \"Ola\""), .timestamp(OracleTimestamp(year: 2020, month: 12, day: 17), .date), .null],
               [.number("7499"), .text("O'Brien\nNowy"), .timestamp(OracleTimestamp(year: 2021, month: 2, day: 20, hour: 8, minute: 5), .date), .number("300.5")]],
        tableName: "PELIKAN_TEST.EMP")

    @Test("CSV: cudzysłowy przy przecinku, cudzysłowie i nowej linii; NULL pusty")
    func csv() {
        let s = ResultExporter.text(.csv, data)
        #expect(s.hasPrefix("EMPNO,ENAME,HIREDATE,COMM\r\n"))
        #expect(s.contains("7369,\"Szymańska, \"\"Ola\"\"\",2020-12-17 00:00:00,\r\n"))
        #expect(s.contains("\"O'Brien\nNowy\""))
    }

    @Test("TSV: tabulatory, nowe linie w wartościach zamienione na spacje")
    func tsv() {
        let s = ResultExporter.text(.tsv, data)
        #expect(s.components(separatedBy: "\n").count == 3)
        #expect(s.contains("7499\tO'Brien Nowy\t2021-02-20 08:05:00\t300.5"))
    }

    @Test("HTML i XML: znaki specjalne, NULL pominięty w XML, nazwy elementów z nazw kolumn")
    func markup() {
        let h = ResultExporter.text(.html, data)
        #expect(h.contains("<th>ENAME</th>"))
        #expect(h.contains("Szymańska, &quot;Ola&quot;"))
        #expect(h.contains("<td class=\"null\"></td>"))
        let x = ResultExporter.text(.xml, data)
        #expect(x.contains("<ENAME>O&apos;Brien\nNowy</ENAME>"))
        #expect(!x.contains("<COMM></COMM>"))
        #expect(ResultExporter.xmlName("COUNT(*)") == "COUNT_x0028__x002A__x0029_")
        #expect(ResultExporter.xmlName("1ST") == "_x0031_ST")
    }

    @Test("SQL: INSERT z literałami dat, apostrofami, NULL; tabela ze schematem")
    func inserts() {
        let s = ResultExporter.text(.sql, data)
        #expect(s.contains("INSERT INTO PELIKAN_TEST.EMP (EMPNO, ENAME, HIREDATE, COMM) VALUES (7499, 'O''Brien\nNowy', TO_DATE('2021-02-20 08:05:00', 'YYYY-MM-DD HH24:MI:SS'), 300.5);"))
        #expect(s.contains("VALUES (7369, 'Szymańska, \"Ola\"', TO_DATE('2020-12-17 00:00:00', 'YYYY-MM-DD HH24:MI:SS'), NULL);"))
        #expect(ResultExporter.identifier("Mała") == "\"Mała\"")
        #expect(ResultExporter.identifier("SELECT") == "\"SELECT\"")
    }

    @Test("CLOB dłuższy niż 4000 bajtów składany z kawałków TO_CLOB")
    func clob() {
        let long = String(repeating: "ż", count: 3000)    // 6000 bajtów
        let lit = ResultExporter.literal(.lob(LOBValue(kind: .clob, text: long, length: 3000, truncated: false)))
        #expect(lit.components(separatedBy: "TO_CLOB(").count - 1 == 2)
        #expect(ResultExporter.literal(.lob(LOBValue(kind: .blob, length: 10_000, truncated: true))) == "NULL /* BLOB 10000 */")
    }

    @Test("Lista wyrażeń: jedna kolumna i wiele kolumn, bez powtórzeń")
    func expressionList() {
        let one = ExportData(title: "", columns: [data.columns[0]], rows: [[.number("7788")], [.number("7902")], [.number("7788")]])
        #expect(ResultExporter.text(.expressionList, one) == "EMPNO IN (7788, 7902)")
        let two = ExportData(title: "", columns: Array(data.columns[0...1]), rows: data.rows.map { Array($0[0...1]) })
        #expect(ResultExporter.text(.expressionList, two).hasPrefix("(EMPNO, ENAME) IN ((7369, 'Szymańska"))
    }

    @Test("Tabela z zapytania: schemat, cudzysłów, podzapytanie w liście kolumn")
    func tableName() {
        #expect(ResultExporter.tableName(fromQuery: "select e.*, rowid from emp e") == "EMP")
        #expect(ResultExporter.tableName(fromQuery: "select (select 1 from dual) x from scott.\"Emp Tab\" t where 1=1") == "SCOTT.Emp Tab")
        #expect(ResultExporter.tableName(fromQuery: "select 1") == nil)
    }

    @Test("xlsx: poprawny ZIP (CRC), arkusz na wynik, liczby i daty jako wartości")
    func xlsx() throws {
        let book = ResultExporter.xlsx([data, ExportData(title: "Pracownicy", columns: [data.columns[0]], rows: [[.number("1")]], sql: "select 1 from dual")], includeSQL: true)
        #expect(book.prefix(2) == Data("PK".utf8))
        #expect(ResultExporter.columnLetter(0) == "A" && ResultExporter.columnLetter(25) == "Z" && ResultExporter.columnLetter(26) == "AA")
        #expect(abs((ResultExporter.excelSerial(OracleTimestamp(year: 2020, month: 1, day: 1, hour: 12)) ?? 0) - 43831.5) < 1e-9)
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-\(UUID().uuidString).xlsx")
        try book.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        func unzip(_ args: [String]) throws -> (Int32, String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try p.run()
            let out = String(decoding: (try? pipe.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)
            p.waitUntilExit()
            return (p.terminationStatus, out)
        }
        #expect(try unzip(["-t", url.path]).0 == 0)
        let wb = try unzip(["-p", url.path, "xl/workbook.xml"]).1
        #expect(wb.contains("name=\"Pracownicy\"") && wb.contains("name=\"Pracownicy 2\"") && wb.contains("name=\"SQL\""))
        let sheet = try unzip(["-p", url.path, "xl/worksheets/sheet1.xml"]).1
        #expect(sheet.contains("<c r=\"A2\"><v>7369</v></c>"))
        #expect(sheet.contains("<c r=\"C2\" s=\"3\"><v>44182.0</v></c>"))
        #expect(!sheet.contains("r=\"D2\""))   // NULL — brak komórki
    }
}
