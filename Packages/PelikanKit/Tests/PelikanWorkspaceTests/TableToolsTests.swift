import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@Suite("Narzędzia tabel: filtr wartości, kopia i eksport (D214)")
struct TableToolsTests {
    func match(_ filter: String, _ text: String, _ key: SortKey? = nil) -> Bool {
        ValueFilter.parse(filter)!.matches(text: text, key: key ?? text.sortKey)
    }

    @Test("Tekst: LIKE bez wielkości liter, % i _, bez znaków wieloznacznych — równość")
    func like() {
        #expect(match("abc%", "ABCDEF"))
        #expect(match("ABC%", "abcdef"))
        #expect(!match("abc%", "xabc"))
        #expect(match("%sys%", "PELIKAN_SYS_X"))
        #expect(match("a_c", "AbC"))
        #expect(!match("a_c", "abbc"))
        #expect(match("active", "ACTIVE"))
        #expect(!match("active", "INACTIVE"))
        #expect(match("not like %tmp%", "TABELA"))
        #expect(!match("not like %tmp%", "TMP_1"))
        #expect(match("like 'O''Brien'", "o'brien"))
    }

    @Test("Liczby: =, <>, >=, <, between; tekst liczbowy porównywany wg wartości")
    func numbers() {
        #expect(match("=5", "5"))
        #expect(match("= 5", "5.0"))
        #expect(!match("=5", "15"))
        #expect(match(">=6", "6"))
        #expect(match(">= 6", "10"))
        #expect(!match(">=6", "5,5"))
        #expect(match("<10", "9.99"))
        #expect(match("<>0", "1"))
        #expect(match("!=0", "1"))
        #expect(match("between 3 and 4", "3.5"))
        #expect(match("BETWEEN 3 AND 4", "4"))
        #expect(!match("between 3 and 4", "4.01"))
        #expect(match(">100", "", .number(150)))
        #expect(!match(">5", "abc"))
    }

    @Test("Daty YYYY-MM-DD: cały dzień, z czasem, between; klucz daty i tekst daty")
    func dates() {
        var c = DateComponents(year: 2026, month: 10, day: 3, hour: 14, minute: 30)
        c.calendar = Calendar(identifier: .gregorian)
        let d = c.date!
        #expect(match("= 2026-10-03", "", .date(d)))
        #expect(match("=2026-10-03", "2026-10-03 14:30:00"))
        #expect(!match("= 2026-10-04", "2026-10-03 14:30:00"))
        #expect(match("> 2026-10-02", "2026-10-03"))
        #expect(!match("> 2026-10-03", "2026-10-03 23:59:59"))
        #expect(match(">= 2026-10-03 14:00", "2026-10-03 14:30:00"))
        #expect(!match("> 2026-10-03 15:00", "", .date(d)))
        #expect(match("between 2026-10-01 and 2026-10-31", "2026-10-31 23:00:00"))
        #expect(!match("between 2026-10-01 and 2026-10-31", "2026-11-01"))
        #expect(ValueFilter.date("2026-02-30") == nil)
    }

    @Test("Puste wartości: is null, is not null; LIKE i porównania pomijają puste")
    func nulls() {
        #expect(match("is null", ""))
        #expect(!match("is null", "x"))
        #expect(match("is not null", "x"))
        #expect(!match("%", ""))
        #expect(!match("<>5", ""))
        #expect(!match("not like a%", ""))
        #expect(ValueFilter.parse("   ") == nil)
    }

    @Test("Filtr tabeli: warunki kolumn łącznie i szybki filtr w dowolnej kolumnie")
    func table() {
        let rows = [["SID": "12", "STATUS": "ACTIVE", "USER": "SCOTT"], ["SID": "7", "STATUS": "INACTIVE", "USER": "SYS"], ["SID": "30", "STATUS": "ACTIVE", "USER": "PELIKAN"]]
        func run(_ f: TableFilter) -> [String] {
            let c = f.compiled()
            return rows.filter { r in c.matches(all: ["SID", "STATUS", "USER"]) { id in (r[id] ?? "", (r[id] ?? "").sortKey) } }.map { $0["SID"]! }
        }
        #expect(run(TableFilter(columns: ["STATUS": "active"])) == ["12", "30"])
        #expect(run(TableFilter(columns: ["STATUS": "active", "SID": ">20"])) == ["30"])
        #expect(run(TableFilter(quick: "sco")) == ["12"])
        #expect(run(TableFilter(quick: "s%")) == ["12", "7"])
        #expect(!TableFilter(columns: ["SID": " "]).isActive)
        #expect(TableFilter(columns: ["SID": "=1"]).isActive)
    }

    @Test("Eksport tabeli: kolumny liczbowe, NULL, JSON, tekst wyrównany, CSV, xlsx")
    func export() throws {
        let d = TableExport.data(title: "Sesje", columns: ["SID", "USER", "OPIS"], rows: [["12", "SCOTT", "a \"b\"\nc"], ["7", "", "x"]])
        #expect(d.columns.map(\.type) == [.number, .varchar2, .varchar2])
        #expect(d.rows[1][1] == .null)
        let json = ResultExporter.text(.json, d)
        #expect(json.contains(#"{"SID": 12, "USER": "SCOTT", "OPIS": "a \"b\"\nc"}"#))
        #expect(json.contains(#""USER": null"#))
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        #expect(parsed?.count == 2)
        let text = ResultExporter.text(.text, d)
        #expect(text.hasPrefix("SID  USER   OPIS\n---  -----  -------\n 12  SCOTT  a \"b\" c\n  7         x\n"))
        #expect(ResultExporter.text(.csv, d).hasPrefix("SID,USER,OPIS\r\n12,SCOTT,\"a \"\"b\"\"\nc\"\r\n"))
        let xlsx = TableExport.file(.xlsx, d)
        #expect(xlsx.prefix(2) == Data("PK".utf8))
        #expect(TableExport.formats.contains(.json) && TableExport.formats.contains(.text) && TableExport.formats.contains(.html) && TableExport.formats.contains(.xml))
        #expect(ResultExporter.text(.json, TableExport.data(title: "", columns: ["N"], rows: [[".5"]])).contains(#""N": 0.5"#))
        let clip = TableExport.clipboard(d, header: false)
        #expect(clip.text.hasPrefix("12\tSCOTT\ta \"b\" c"))
        #expect(clip.html.contains("<td class=\"n\">12</td>"))
    }

    @Test("Tekst klucza sortowania: liczby całkowite, daty bez czasu o północy")
    func keyText() {
        #expect(SortKey.number(5).text == "5")
        #expect(SortKey.number(2.5).text == "2.5")
        #expect(SortKey.none.text == "")
        var c = DateComponents(year: 2026, month: 10, day: 3)
        c.calendar = Calendar(identifier: .gregorian)
        #expect(SortKey.date(c.date!).text == "2026-10-03")
    }
}
