import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@Suite("Raporty bez bazy")
struct ReportOfflineTests {
    let data = ReportData(columns: ["DEPT", "ENAME", "SAL", "HIRED"], rows: [
        [.text("10"), .text("KING"), .number(5000, "5000"), .date(Date(timeIntervalSince1970: 0))],
        [.text("10"), .text("<CLARK>"), .number(2450.5, "2450.5"), .null],
        [.text("20"), .text("SMITH"), .number(800, "800"), .null],
    ])

    @Test("Tabela: nagłówki, wyrównanie liczb, escape HTML, NULL, formaty liczb i dat, styl i tło")
    func table() {
        var def = ReportDefinition(title: "Pracownicy & płace", sql: "select …")
        var sal = ReportColumnFormat(column: "sal"); sal.numberFormat = "#,##0.00"; sal.heading = "Pensja"
        var hired = ReportColumnFormat(column: "HIRED"); hired.dateFormat = "yyyy-MM-dd"
        def.columns = [sal, hired]
        def.background = "#fafafa"
        def.styleName = ReportStyle.library[1].name
        let html = ReportRenderer.html(def, data: data, locale: Locale(identifier: "en_US_POSIX"))
        #expect(html.contains("<title>Pracownicy &amp; płace</title>") && html.contains("&lt;CLARK&gt;"))
        #expect(html.contains(">Pensja</th>") && html.contains("text-align:right\">5,000.00</td>") && html.contains("2,450.50"))
        #expect(html.contains(">1970-01-01</td>") && html.contains("class=\"null\""))
        #expect(html.contains("background: #fafafa") && html.contains("#1b6b3a"))
        def.background = "red; } body { display:none"
        #expect(!ReportRenderer.html(def, data: data).contains("display:none"))
    }

    @Test("Break (master-detail) z sumą grupy i sumą końcową; ukryta kolumna; podział stron")
    func breaks() {
        var def = ReportDefinition(title: "T", sql: "")
        var d = ReportColumnFormat(column: "DEPT"); d.breakGroup = true
        var s = ReportColumnFormat(column: "SAL"); s.sum = true
        var h = ReportColumnFormat(column: "HIRED"); h.hidden = true
        def.columns = [d, s, h]
        def.pageBreakOnGroup = true
        let html = ReportRenderer.html(def, data: data, locale: Locale(identifier: "en_US_POSIX"))
        #expect(html.components(separatedBy: "class=\"break\"").count == 3)
        #expect(html.contains("DEPT: 10") && html.contains("DEPT: 20") && !html.contains(">HIRED<"))
        #expect(html.contains(">7450.5</td>") && html.contains(">8250.5</td>"))
        #expect(html.contains("break-after: page"))
        // Suma końcowa w tabeli ostatniej grupy (wspólne kolumny), nie w osobnej tabeli.
        #expect(html.components(separatedBy: "<table>").count == 3)
        #expect(html.range(of: "Razem")!.lowerBound < html.range(of: "</table>", options: .backwards)!.lowerBound)
        def.pageBreakOnGroup = false
        let one = ReportRenderer.html(def, data: data, locale: Locale(identifier: "en_US_POSIX"))
        #expect(one.components(separatedBy: "<table>").count == 2 && one.components(separatedBy: "class=\"break\"").count == 3)
        #expect(one.contains("<td>Razem</td>") && !one.contains("class=\"group\""))
    }

    @Test("Układ formularza i nagłówek ze zmiennymi; zapis i odczyt definicji")
    func formAndFile() throws {
        var def = ReportDefinition(title: "Raport", sql: "select 1 from dual")
        def.layout = .form
        def.header = "#title — #Dział — #user"
        def.locked = true
        let html = ReportRenderer.html(def, data: data, values: ["Dział": "10", "user": "SCOTT"])
        #expect(html.contains("Raport — 10 — SCOTT") && html.contains("class=\"form record\"") && html.contains("<td class=\"label\">ENAME</td>"))
        let back = try ReportDefinition.decode(def.encoded())
        #expect(back == def)
        #expect(try ReportDefinition.decode(Data("{\"title\":\"x\",\"sql\":\"y\"}".utf8)).styleName == ReportStyle.library[0].name)
    }

    @Test("Dodatkowy CSS z pliku .rep nie zamyka <style>; nagłówek CSP bez skryptów")
    func cssInjection() {
        var def = ReportDefinition(title: "T", sql: "")
        def.extraCSS = "td { color: red; } </style><script>alert(1)</script><style>"
        let html = ReportRenderer.html(def, data: data)
        #expect(!html.contains("</style><script>") && html.components(separatedBy: "</style>").count == 2)
        #expect(html.contains("<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\">"))
    }

    @Test("Styl raportu: w pliku stały identyfikator; stare pliki z polską nazwą stylu i identyfikator odczytywane")
    func styleKey() throws {
        var def = ReportDefinition(title: "T", sql: "")
        def.styleName = ReportStyle.library[1].name
        let json = String(decoding: try def.encoded(), as: UTF8.self)
        #expect(json.contains("\"styleName\" : \"green\""))
        #expect(try ReportDefinition.decode(def.encoded()) == def)
        let old = try ReportDefinition.decode(Data("{\"title\":\"x\",\"sql\":\"y\",\"styleName\":\"Zielony\"}".utf8))
        #expect(old.styleName == ReportStyle.library[1].name && old.style.key == "green")
        #expect(try ReportDefinition.decode(Data("{\"styleName\":\"compact\"}".utf8)).style.key == "compact")
        #expect(try ReportDefinition.decode(Data("{\"styleName\":\"nieznany\"}".utf8)).style.key == "standard")
    }

    @MainActor
    @Test("Raporty standardowe: unikalne identyfikatory, zmienne w raportach z parametrami")
    func standard() {
        let ids = StandardReports.all.map(\.id)
        #expect(Set(ids).count == ids.count && ids.contains("reports.compilationErrors"))
        let recent = StandardReports.all.first { $0.id == "reports.recentChanges" }!.definition
        #expect(SQLExecutor.variableRequests(ScriptSplitter.split(recent.sql), remembered: [:]).map(\.name) == ["Dni"])
    }
}
