import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@Suite("Kod jako HTML (Quick Look, druk)")
struct CodeHTMLTests {
    @Test("Kolory tokenów, numery linii poza kolorami w komentarzu wieloliniowym, escape HTML")
    func highlighting() {
        let html = CodeHTML.pre("select 'a<b' from dual; /* x\ny */\n:p", lineNumbers: true)
        #expect(html.contains("<span class=\"kw\">select</span>") && html.contains("<span class=\"str\">'a&lt;b'</span>"))
        #expect(html.contains("<span class=\"cmt\">/* x</span>\n<span class=\"ln\">2</span><span class=\"cmt\">y */</span>"))
        #expect(html.contains("<span class=\"ln\">3</span><span class=\"var\">:p</span>"))
        #expect(!CodeHTML.pre("x", lineNumbers: false).contains("class=\"ln\""))
        #expect(CodeHTML.document("begin null; end;", title: "a&b.pkb").contains("<title>a&amp;b.pkb</title>"))
    }

    @Test("Dekodowanie pliku: UTF-8, BOM, ISO-8859-2, Windows-1250")
    func decoding() {
        #expect(CodeHTML.decode(Data("zażółć".utf8)) == "zażółć")
        #expect(CodeHTML.decode(Data([0xEF, 0xBB, 0xBF] + Array("ą".utf8))) == "ą")
        #expect(CodeHTML.decode("-- ąść".data(using: .isoLatin2)!) == "-- ąść")
        #expect(CodeHTML.decode("-- śćź „x”".data(using: .windowsCP1250)!) == "-- śćź „x”")
    }
}

@MainActor
@Suite("Wydruk okna")
struct PrintLayoutTests {
    @Test("Nagłówek z połączeniem i datą, kod z kolorami, tabela siatki z liczbą wierszy")
    func layout() {
        var c = PrintLayout.Content(title: "SQL Window – emp.sql", connection: "scott@dev", code: "select * from emp")
        c.grid = ExportData(title: "emp", columns: [ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2"),
                                                     ColumnInfo(name: "SAL", type: .number, typeName: "NUMBER")],
                            rows: [[.text("KING"), .number("5000")], [.text("<A&B>"), .null]])
        c.gridIsSelection = true
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let html = PrintLayout.html(c, printed: date)
        #expect(html.contains("<h1>SQL Window – emp.sql</h1>") && html.contains("scott@dev · "))
        #expect(html.contains("<span class=\"kw\">select</span>"))
        #expect(html.contains("Zaznaczone wiersze: 2") && html.contains("<th>ENAME</th>") && html.contains("&lt;A&amp;B&gt;"))
        #expect(html.contains("<td class=\"n\">5000</td>") && html.contains("<td class=\"null\">"))
        #expect(!PrintLayout.html(PrintLayout.Content(title: "x"), printed: date).contains("<table>"))
    }

    @Test("Komenda Drukuj: okno programu — kod bez siatki; wynik HTML do okna druku")
    func command() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        _ = ws.newDocument(.program, text: "create package p as end;")
        let r = try await ws.invoke("file.print")
        guard case .string(let html)? = r.value else { Issue.record("brak HTML"); return }
        #expect(html.contains("<span class=\"kw\">create</span>") && !html.contains("<table>"))
        #expect(ui.printed.count == 1)
    }
}

