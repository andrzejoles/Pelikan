import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Funkcje zaznaczenia edytora")
struct TextEditingTests {
    let sql = "select a,\n  b\nfrom t;"

    @Test("Komentarz linii: dodanie na wspólnym wcięciu i zdjęcie")
    func comment() {
        let e = TextEditing.toggleLineComment(sql, selection: 0..<12)
        #expect(e.text == "-- select a,\n--   b\nfrom t;")
        let back = TextEditing.toggleLineComment(e.text, selection: e.selection)
        #expect(back.text == sql)
        #expect(TextEditing.toggleLineComment("  x\n  y", selection: 0..<0).text == "  -- x\n  y")
    }

    @Test("Wcięcie i cofnięcie wcięcia zaznaczonych linii")
    func indent() {
        let e = TextEditing.indent(sql, selection: 0..<12)
        #expect(e.text == "  select a,\n    b\nfrom t;")
        #expect(TextEditing.indent(e.text, selection: e.selection, outdent: true).text == sql)
    }

    @Test("Wielkie i małe litery z pominięciem literałów i identyfikatorów w cudzysłowie")
    func caseChange() {
        let t = "select 'Ala ma kota', \"Mała\" from dual where x = 'b'"
        let up = TextEditing.changeCase(t, selection: 0..<(t as NSString).length, upper: true)
        #expect(up.text == "SELECT 'Ala ma kota', \"Mała\" FROM DUAL WHERE X = 'b'")
        #expect(TextEditing.changeCase(up.text, selection: up.selection, upper: false).text == t)
    }

    @Test("Usunięcie końcowych spacji, powielenie linii, przejście do linii")
    func misc() {
        #expect(TextEditing.removeTrailingSpaces("a  \nb\t\n c ", selection: 0..<0).text == "a\nb\n c")
        let d = TextEditing.duplicateLines("x\ny\nz", selection: 2..<2)
        #expect(d.text == "x\ny\ny\nz" && d.selection == 4..<4)
        #expect(TextEditing.offset(ofLine: 3, in: sql) == 14)
        #expect(TextEditing.offset(ofLine: 99, in: sql) == 14)
        #expect(TextEditing.offset(ofLine: 1, in: sql) == 0)
    }
}

@Suite("Znajdź i zamień")
struct TextSearchTests {
    let text = "select emp_name, EMP_NO from emp -- emp w komentarzu\nwhere x = 'emp';"

    @Test("Tekst bez rozróżniania wielkości liter, całe słowa, następne z zawinięciem")
    func find() throws {
        var s = TextSearch(pattern: "emp")
        #expect(try s.matches(in: text).count == 5)
        s.wholeWords = true
        #expect(try s.matches(in: text).count == 3)
        s.caseSensitive = true
        #expect(try s.next(in: text, from: 30)?.lowerBound == 36)
        #expect(try s.next(in: text, from: 70)?.lowerBound == 29)          // zawinięcie na początek
    }

    @Test("Szukanie tylko w kodzie / w komentarzach / w literałach")
    func scopes() throws {
        var s = TextSearch(pattern: "emp")
        s.wholeWords = true
        s.inComments = false
        s.inStrings = false
        #expect(try s.matches(in: text) == [29..<32])
        s.inCode = false
        s.inComments = true
        #expect(try s.matches(in: text) == [36..<39])
    }

    @Test("Wyrażenie regularne z $1 i \\t, zachowanie wielkości liter, zamiana w zaznaczeniu")
    func replace() throws {
        var s = TextSearch(pattern: "(\\w+)_no")
        s.regex = true
        s.replacement = "$1\\tnr"
        #expect(try s.replaceAll(in: "emp_no, dept_no").text == "emp\tnr, dept\tnr")
        var p = TextSearch(pattern: "emp")
        p.replacement = "pracownik"
        p.preserveCase = true
        p.wholeWords = true
        #expect(try p.replaceAll(in: "emp EMP Emp").text == "pracownik PRACOWNIK Pracownik")
        let r = try p.replaceAll(in: "emp emp emp", within: 4..<11)
        #expect(r.text == "emp pracownik pracownik" && r.count == 2)
        #expect(try p.replace(in: "x emp", selection: 2..<5)?.text == "x pracownik")
        #expect(try p.replace(in: "x emp", selection: 0..<1) == nil)
    }
}

@MainActor
@Suite("Komendy edycji")
struct EditCommandTests {
    @Test("Komentarz, wielkie litery, Przejdź do linii (argument i pytanie), Znajdź następne/poprzednie")
    func commands() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let doc = ws.newDocument(.sql)
        doc.text = "select 1 from dual;\nselect 'x' from emp;\nselect 3 from emp;"
        doc.selectedRange = 0..<0
        try await ws.invoke("edit.commentLine")
        #expect(doc.text.hasPrefix("-- select 1 from dual;\n"))
        try await ws.invoke("edit.commentLine")
        doc.selectedRange = 20..<40
        try await ws.invoke("edit.uppercase")
        #expect(doc.text.contains("SELECT 'x' FROM EMP;"))
        try await ws.invoke("edit.gotoLine", CommandArguments(["line": .int(3)]))
        #expect(doc.selectedRange == 41..<41)
        ui.textAnswer = "2"
        try await ws.invoke("edit.gotoLine")
        #expect(doc.selectedRange == 20..<20)
        var s = TextSearch(pattern: "emp")
        s.wholeWords = true
        ws.lastSearch = s
        try await ws.invoke("edit.findNext")
        #expect((doc.text as NSString).substring(with: NSRange(location: doc.selectedRange.lowerBound, length: doc.selectedRange.count)).lowercased() == "emp")
        let first = doc.selectedRange
        try await ws.invoke("edit.findNext")
        #expect(doc.selectedRange.lowerBound > first.lowerBound)
        try await ws.invoke("edit.findPrevious")
        #expect(doc.selectedRange == first)
    }
}

@MainActor
@Suite("Przejdź do deklaracji")
struct GotoDeclarationTests {
    @Test("Zmienna lokalna, parametr i podprogram z zarysu kodu; identyfikator z kropkami")
    func local() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.program, text: """
            create or replace package body p as
              g number;
              procedure helper(p_x number) is begin null; end;
              procedure main(p_a number) is
                v number;
              begin
                v := p_a + g;
                helper(v);
              end;
            end;
            /
            """)
        let ns = doc.text as NSString
        doc.selectedRange = (ns.range(of: "p_a + g").location + 1)..<(ns.range(of: "p_a + g").location + 1)
        try await ws.invoke("edit.gotoDeclaration")
        #expect(doc.selectedRange.lowerBound == ns.range(of: "p_a number").location)
        let gUse = ns.range(of: "+ g;").location + 2
        doc.selectedRange = gUse..<gUse
        try await ws.invoke("edit.gotoDeclaration")
        #expect(doc.selectedRange.lowerBound == ns.range(of: "g number").location)
        let call = ns.range(of: "helper(v)").location + 2
        doc.selectedRange = call..<call
        try await ws.invoke("edit.gotoDeclaration")
        #expect(doc.selectedRange.lowerBound == ns.range(of: "helper(p_x").location)
        #expect(BuiltinCommands.identifier(at: 6, in: "x := scott.emp_api.f(1)")?.0 == "scott.emp_api.f")
    }
}

@MainActor
@Suite("Komendy zwijania")
struct FoldCommandTests {
    @Test("Zwiń w linii kursora, kursor poza ukrytym tekstem, rozwiń, zwiń i rozwiń wszystko, przesunięcie po edycji")
    func commands() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.program, text: "begin\n  if a then\n    x := 1;\n  end if;\nend;\n")
        let ns = doc.text as NSString
        let x = ns.range(of: "x := 1").location
        doc.selectedRange = x..<x
        try await ws.invoke("edit.fold")
        let ifStart = ns.range(of: "if a").location
        #expect(doc.foldedStarts == [ifStart])
        #expect(doc.selectedRange == ifStart..<ifStart)
        try await ws.invoke("edit.unfold")
        #expect(doc.foldedStarts.isEmpty)
        try await ws.invoke("edit.foldAll")
        #expect(doc.foldedStarts.count == 2)
        doc.text = "-- c\n" + doc.text
        #expect(doc.foldedStarts.contains(ifStart + 5))
        try await ws.invoke("edit.unfoldAll")
        #expect(doc.foldedStarts.isEmpty)
    }
}

@MainActor
@Suite("Code Assistant bez bazy")
struct CodeAssistantOfflineTests {
    @Test("Deklaracje lokalne, pola rekordu, aliasy podzapytań, słowa kluczowe, brak w literale")
    func offline() async {
        let text = """
            declare
              type t_rec is record (id number, nazwa varchar2(10));
              v_rec t_rec;
              v_licznik number;
            begin
              v_
            """
        let r = await CodeAssistant.complete(text: text, offset: (text as NSString).length, metadata: nil)
        #expect(r?.items.map(\.label) == ["v_rec", "v_licznik"])     // kolejność deklaracji
        let f = await CodeAssistant.complete(text: text + "rec.", offset: (text as NSString).length + 4, metadata: nil)
        #expect(f?.items.map(\.label) == ["id", "nazwa"])
        let sub = "select s.| from (select 1 as jeden, x.dwa from t x) s"
        let si = await CodeAssistant.complete(text: sub.replacingOccurrences(of: "|", with: ""), offset: 9, metadata: nil)
        #expect(si?.items.map(\.insertText) == ["jeden", "dwa"])
        let kw = await CodeAssistant.complete(text: "sel", offset: 3, metadata: nil)
        #expect(kw?.items.first?.insertText == "select")
        #expect(await CodeAssistant.complete(text: "select 'v_", offset: 10, metadata: nil) == nil)
    }
}

@MainActor
@Suite("Komenda formatera")
struct BeautifyCommandTests {
    @Test("Całe źródło, zaznaczenie, formatowanie przed zapisem")
    func beautify() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.program, text: "begin null; end;")
        try await ws.invoke("edit.beautify")
        #expect(doc.text == "BEGIN\n  NULL;\nEND;")
        doc.text = "begin\n  select a,b from t;\nend;"
        let s = (doc.text as NSString).range(of: "select").location
        doc.selectedRange = s..<(s + 3)
        try await ws.invoke("edit.beautify")
        #expect(doc.text == "begin\n  SELECT a,\n         b\n  FROM   t;\nend;")
        var settings = ws.settings
        settings.beautifier.beforeSave = true
        ws.settings = settings
        doc.text = "begin null; end;"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-beautify-\(UUID().uuidString).pck")
        defer { try? FileManager.default.removeItem(at: url) }
        try ws.save(doc, to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "BEGIN\n  NULL;\nEND;")
    }
}
