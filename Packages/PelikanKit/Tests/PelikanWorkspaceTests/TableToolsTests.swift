import Foundation
import PelikanDB
import PelikanSQL
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

/// Tabela testowa dla komend `table.*`.
@MainActor
final class FakeTableHandle: TableHandle {
    var filter = TableFilter()
    var markedColumns: [String] = []
    let rows: [[String]]
    var selected: [Int]
    init(rows: [[String]], selected: [Int]) { self.rows = rows; self.selected = selected }
    func stableContents(_ live: TableContents, rows: [Int]?, columns: [String]?) -> TableContents { live }
    var contents: TableContents {
        TableContents(title: "T", columns: [("a", "A"), ("b", "B")], rowCount: rows.count,
                      cell: { [rows] r, id in rows[r][id == "a" ? 0 : 1] }, selectedRows: selected)
    }
}

@MainActor
final class EmptyColumnTable: TableHandle {
    func stableContents(_ live: TableContents, rows: [Int]?, columns: [String]?) -> TableContents { live }
    var filter = TableFilter()
    var markedColumns: [String] = []
    var contents: TableContents {
        TableContents(title: "T", columns: [("", ""), ("m", "Problem")], rowCount: 1, cell: { _, id in id.isEmpty ? "błąd" : "x" }, selectedRows: [])
    }
}

@MainActor
final class TableUI: UIServices {
    var clipboard: String?
    var saved: (name: String, ext: String, data: Data)?
    var table: (any TableHandle)?
    func focusedTable() -> (any TableHandle)? { table }
    func clipboardText() -> String? { nil }
    func copyToClipboard(_ text: String, html: String?) { clipboard = text }
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { 0 }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { [:] }
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { saved = (suggestedName, fileExtension, data); return true }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { nil }
}

@Suite("Narzędzia tabel: poprawki z przeglądu kodu (D224)")
struct TableToolsReviewTests {
    @Test("Data z ułamkami sekund: „tylko ta wartość” z tekstu do sekundy trafia")
    func dateSeconds() throws {
        var c = DateComponents(year: 2026, month: 11, day: 4, hour: 12, minute: 0, second: 1)
        c.calendar = Calendar(identifier: .gregorian)
        let d = try #require(c.date).addingTimeInterval(0.734)
        let f = try #require(ValueFilter.parse("= 2026-11-04 12:00:01"))
        #expect(f.matches(text: "2026-11-04 12:00:01", key: .date(d)))
        #expect(!ValueFilter.parse("<> 2026-11-04 12:00:01")!.matches(text: "2026-11-04 12:00:01", key: .date(d)))
    }

    @Test("Data wpisana z dokładnością do minuty obejmuje całą minutę")
    func dateMinute() throws {
        var c = DateComponents(year: 2026, month: 11, day: 4, hour: 12, minute: 0, second: 37)
        c.calendar = Calendar(identifier: .gregorian)
        let d = try #require(c.date)
        #expect(ValueFilter.parse("= 2026-11-04 12:00")!.matches(text: "2026-11-04 12:00:37", key: .date(d)))
        #expect(!ValueFilter.parse("<> 2026-11-04 12:00")!.matches(text: "2026-11-04 12:00:37", key: .date(d)))
        #expect(!ValueFilter.parse("= 2026-11-04 12:00:00")!.matches(text: "2026-11-04 12:00:37", key: .date(d)))
    }

    @Test("Szybki filtr: podkreślenie nie wyłącza szukania fragmentu, % — wzorzec całej wartości")
    func quickUnderscore() {
        func hit(_ q: String, _ text: String) -> Bool { TableFilter(quick: q).compiled().matches(all: ["x"]) { _ in (text, text.sortKey) } }
        #expect(hit("dba_us", "DBA_USERS"))
        #expect(hit("sql_id", "PREV_SQL_ID"))
        #expect(!hit("abc%", "xabc"))
        #expect(hit("abc%", "ABCD"))
    }

    @Test("Liczba w filtrze porównywana z tekstem komórki (zaokrąglony klucz nie przeszkadza); wzorzec LIKE z pamięci")
    func shownNumber() {
        let f = ValueFilter.parse(TableExport.condition("12.35", exclude: false))!
        #expect(f.matches(text: "12.35", key: .number(12.345678)))
        #expect(!ValueFilter.parse("<> 12.35")!.matches(text: "12.35", key: .number(12.345678)))
        #expect(ValueFilter.parse("> 3")!.matches(text: "", key: .number(5)))   // bez tekstu — wartość klucza
        #expect(LikePattern("dba%").matches("DBA_USERS") && !LikePattern("dba%").matches("X"))
        // Porządek według klucza kolumny (jednolita skala przy jednostkach w tekście: „450 ms” obok „1.2 s”).
        #expect(ValueFilter.parse("< 1")!.matches(text: "450 ms", key: .number(0.45)))
        #expect(!ValueFilter.parse("< 1")!.matches(text: "1.2 s", key: .number(1.2)))
        #expect(ValueFilter.parse("> 1000")!.matches(text: "1,234", key: .number(1234)))
        #expect(ValueFilter.parse("= 1234")!.matches(text: "1,234", key: .number(1234)))
        // „Tylko ta wartość” z przecinkiem — tekst dosłownie (apostrofy), trafia w tę samą komórkę.
        #expect(ValueFilter.parse(TableExport.condition("1,234", exclude: false))!.matches(text: "1,234", key: .number(1234)))
        #expect(!ValueFilter.parse(TableExport.condition("1,234", exclude: true))!.matches(text: "1,234", key: .number(1234)))
        // Ta sama wartość dla wszystkich porównań: „= 12.35” i „>= 12.35” trafiają razem.
        #expect(ValueFilter.parse("= 12.35")!.matches(text: "12.35", key: .number(12.345678)))
        #expect(ValueFilter.parse(">= 12.35")!.matches(text: "12.35", key: .number(12.345678)))
        #expect(ValueFilter.parse("between 12.35 and 13")!.matches(text: "12.35", key: .number(12.345678)))
        // Klucz ułamkowy pokazany jako liczba całkowita („13” przy 12.6) — „tylko ta wartość” trafia.
        #expect(ValueFilter.parse("= 13")!.matches(text: "13", key: .number(12.6)))
        // between z apostrofami — tekst dosłownie, jak przy = < >.
        #expect(ValueFilter.parse("between '1,200' and '1,900'")!.matches(text: "1,500", key: .text("1,500")))
        // Kody z zerami wiodącymi i długie liczby — „tylko ta wartość” rozróżnia je; równość tekstu dokładna.
        #expect(!ValueFilter.parse(TableExport.condition("0012", exclude: false))!.matches(text: "12", key: .text("12")))
        #expect(ValueFilter.parse(TableExport.condition("0012", exclude: false))!.matches(text: "0012", key: .text("0012")))
        #expect(!ValueFilter.parse("= 'EMP2'")!.matches(text: "EMP02", key: .text("EMP02")))
        // „Tylko ta wartość” z wielkością liter („Emp” ≠ „EMP”); wpisany tekst bez apostrofów — bez wielkości liter.
        #expect(!ValueFilter.parse(TableExport.condition("Emp", exclude: false))!.matches(text: "EMP", key: .text("EMP")))
        #expect(ValueFilter.parse("= active")!.matches(text: "ACTIVE", key: .text("ACTIVE")))
        // „Tylko ta wartość” — zawsze tekst dosłownie: „19.10” ≠ „19.1”; =, <, between zgodne dla tekstu.
        #expect(!ValueFilter.parse(TableExport.condition("19.10", exclude: false))!.matches(text: "19.1", key: .text("19.1")))
        #expect(!ValueFilter.parse("between 'EMP02' and 'EMP02'")!.matches(text: "EMP2", key: .text("EMP2")))
        // Komórka bez klucza, ale z opisem (kolumna postępu) — nie jest pusta.
        #expect(ValueFilter.parse(TableExport.condition("Łączenie…", exclude: false))!.matches(text: "Łączenie…", key: .none))
        #expect(TableExport.isNumber("5."))
        // Liczba z zerami po przecinku (16 znaków, 8 cyfr znaczących) — liczba; kolumna zostaje liczbowa.
        #expect(TableExport.isNumber("-0.0000012345678"))
        #expect(ResultExporter.significantDigits("-123456789012.34") == 14)
        // Wartość z białymi znakami na brzegach — „tylko ta wartość” trafia w tę samą komórkę.
        #expect(ValueFilter.parse(TableExport.condition("abc\n", exclude: false))!.matches(text: "abc\n", key: .text("abc\n")))
        #expect(!ValueFilter.parse("= 19")!.matches(text: "19c", key: .text("19c")))
    }

    @Test("Eksport: zera wiodące i długie identyfikatory zostają tekstem")
    func exportNumbers() {
        #expect(TableExport.isNumber("12.35") && TableExport.isNumber("-0.5") && TableExport.isNumber("0") && TableExport.isNumber(".5"))
        #expect(!TableExport.isNumber("0012") && !TableExport.isNumber("123456789012345678") && !TableExport.isNumber("-") && !TableExport.isNumber(""))
        #expect(!TableExport.isNumber("E1") && !TableExport.isNumber("e5") && !TableExport.isNumber("-E2") && TableExport.isNumber("1e5"))
        #expect(TableExport.isNumber("123456789012345"))
        let d = TableExport.data(title: "", columns: ["kod"], rows: [["0012"], ["0100"]])
        #expect(d.columns[0].type == .varchar2)
    }

    @Test("Komendy table.*: komórka, wiersze, kolumny zaznaczone, filtr wartością, eksport; bez tabeli — niedostępne")
    @MainActor func commands() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = TableUI()
        ws.ui = ui
        #expect(ws.registry.command("table.copyAll")?.validate?(ws) == false)
        let t = FakeTableHandle(rows: [["1", "x"], ["2", "y"], ["3", "z"]], selected: [1])
        ui.table = t
        func run(_ id: String, _ args: [String: JSONValue] = [:], target: AnyObject? = nil) async throws {
            _ = try await ws.registry.command(CommandID(rawValue: id))!.run(CommandContext(workspace: ws, invoker: .user, arguments: CommandArguments(args), target: target))
        }
        try await run("table.copyCell", ["column": "B"])
        #expect(ui.clipboard == "y")
        let header = TableExport.copyHeader
        defer { TableExport.copyHeader = header }
        TableExport.copyHeader = false
        try await run("table.copyRows", ["rows": "1,3"])
        await #expect(throws: CommandError.self) { try await run("table.copyCell", ["column": "a", "row": "x"]) }
        #expect(ui.clipboard == "1\tx\n3\tz")
        try await run("table.markColumn", ["column": "b"])
        try await run("table.copyMarkedColumns")
        // Kolejność zaznaczania kolumn (b, potem a) — w kopii b przed a.
        try await run("table.markColumn", ["column": "a"])
        try await run("table.copyMarkedColumns", ["rows": "1"])
        #expect(ui.clipboard == "x\t1")
        try await run("table.markColumn", ["column": "a", "marked": false])
        try await run("table.copyMarkedColumns")
        #expect(ui.clipboard == "x\ny\nz")
        try await run("table.filterByValue", ["column": "a", "exclude": true])
        #expect(t.filter.columns["a"] == "<> '2'")
        try await run("table.clearFilter")
        #expect(!t.filter.isActive)
        try await run("table.export", ["format": "csv"])
        #expect(ui.saved?.ext == "csv")
        await #expect(throws: CommandError.self) { try await run("table.copyRows", ["rows": "9"]) }
        // Kolumna bez tytułu (pusty identyfikator) — od razu, bez pytania o kolumnę.
        let icons = EmptyColumnTable()
        ui.table = icons
        try await run("table.copyCell", ["column": "", "row": 1])
        #expect(ui.clipboard == "błąd")
        #expect(ws.registry.command("file.new.sql")?.descriptor.parameters.map(\.name) == ["text"])
        #expect(ws.registry.command("file.new.program")?.descriptor.parameters.isEmpty == true)
        // Agent nie wpisuje tekstu przez file.new.sql (tylko agent.openEditor — zgoda i dziennik zmian).
        await #expect(throws: (any Error).self) {
            _ = try await ws.registry.command("file.new.sql")!.run(CommandContext(workspace: ws, invoker: .agent(sessionID: "s", agentName: "test"), arguments: CommandArguments(["text": "delete from emp"])))
        }
        // Menu tabeli wskazuje ją identyfikatorem — działa na niej, choć fokus ma inna tabela; bez tabeli — przełącznik nagłówka.
        let other = FakeTableHandle(rows: [["9", "q"]], selected: [0])
        ui.table = other
        try await run("table.copyCell", ["column": "b", "row": 2], target: t)
        #expect(ui.clipboard == "y")
        // Wiersze menu, których już nie ma, i zamknięta tabela — błąd zamiast zaznaczenia albo innej tabeli.
        await #expect(throws: CommandError.self) { try await run("table.copyRows", ["rows": ""]) }
        await #expect(throws: CommandError.self) { try await run("table.copyCell", ["column": "a", "row": 0]) }
        await #expect(throws: CommandError.self) { try await run("table.copyAll", target: NSObject()) }
        try await run("table.copyMarkedColumns", ["selected": true], target: t)
        // Znacznik menu „wiersze zniknęły” — komunikat; wartości umowne w publicznych argumentach to zwykły błąd argumentu.
        #expect(ui.clipboard == "y")
        // Kolumna podana argumentem — nic do uzupełnienia w makrze.
        // Filtr z menu — do makra wartość, nie numer wiersza; odtworzenie z wartością nie czyta wierszy.
        let r = try await ws.registry.command("table.filterByValue")!.run(CommandContext(workspace: ws, invoker: .user, arguments: CommandArguments(["column": "a", "row": 1]), target: t))
        #expect(r.resolvedArguments?.string("value") == "1")
        try await run("table.filterByValue", ["column": "b", "value": "q", "row": 99], target: t)
        #expect(t.filter.columns["b"] == "= 'q'")
        // Zaznaczenie kolumny w makrze — stan docelowy.
        try await run("table.markColumn", ["column": "a", "marked": true], target: t)
        try await run("table.markColumn", ["column": "a", "marked": true], target: t)
        #expect(t.markedColumns.contains("a"))
        try await run("table.clearFilter", target: t)
        ui.table = nil
        let before = TableExport.copyHeader
        try await run("table.toggleCopyHeader")
        #expect(TableExport.copyHeader == !before)
    }
}
