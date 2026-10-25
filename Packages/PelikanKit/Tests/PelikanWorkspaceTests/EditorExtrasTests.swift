import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Edytor: zakładki, znaczniki, kursory, AutoReplace, stan okna (Etap 8)")
struct EditorExtrasTests {
    @Test("Zakładki i znaczniki kolorów przesuwają się przy edycji; przełączanie, następna/poprzednia")
    func bookmarksAndMarks() {
        let ws = Workspace()
        let doc = ws.newDocument(.sql, text: "select 1 from dual;\nselect 2 from dual;\nselect 3 from dual;\n")
        doc.bookmarks = Bookmarks.toggle([], number: 5, at: 25, in: doc.text)
        #expect(doc.bookmarks == [Bookmark(number: 5, offset: 20)])
        doc.bookmarks = Bookmarks.toggle(doc.bookmarks, number: nil, at: 45, in: doc.text)
        #expect(doc.bookmarks.map(\.number) == [5, 1] && doc.bookmarks[1].offset == 40)
        doc.colorMarks = ColorMarks.apply([], range: 27..<33, color: 2)
        doc.text = "-- nagłówek\n" + doc.text
        #expect(doc.bookmarks.map(\.offset) == [32, 52] && doc.colorMarks == [ColorMark(range: 39..<45, color: 2)])
        #expect(Bookmarks.next(doc.bookmarks, from: 0, forward: true)?.number == 5)
        #expect(Bookmarks.next(doc.bookmarks, from: 40, forward: true)?.number == 1)
        #expect(Bookmarks.next(doc.bookmarks, from: 40, forward: false)?.number == 5)
        #expect(Bookmarks.toggle(doc.bookmarks, number: 5, at: 33, in: doc.text).map(\.number) == [1])
        // Kolor 0 usuwa fragment znacznika; nowy kolor dzieli istniejący.
        #expect(ColorMarks.apply(doc.colorMarks, range: 41..<43, color: 0) == [ColorMark(range: 39..<41, color: 2), ColorMark(range: 43..<45, color: 2)])
        #expect(EditorShift.Change(old: "abcdef", new: "abXYef").shift(1..<5) == 1..<5)
        #expect(EditorShift.Change(old: "abcdef", new: "abef").shift(2..<4) == nil)
    }

    @Test("Wiele kursorów: wstawianie, backspace, zaznaczenie kolumnowe, kursor powyżej i poniżej")
    func multiCursor() {
        let text = "abc\nde\nfghij\n"
        let ins = MultiCursor.insert("X", in: text, ranges: [1..<1, 5..<5, 9..<10])
        #expect(ins.text == "aXbc\ndXe\nfgXij\n" && ins.ranges == [2..<2, 7..<7, 12..<12])
        let del = MultiCursor.deleteBackward(in: ins.text, ranges: ins.ranges)
        #expect(del.text == "abc\nde\nfgij\n" && del.ranges == [1..<1, 5..<5, 9..<9])
        #expect(MultiCursor.deleteBackward(in: "a\nb", ranges: [2..<2]).text == "a\nb")
        // Kolumny 1–4 w trzech liniach (krótsza linia „de” — do końca).
        #expect(MultiCursor.column(in: text, from: 1, to: 11) == [1..<3, 5..<6, 8..<11])
        #expect(MultiCursor.addCursor(in: text, ranges: [2..<2], below: true) == [2..<2, 6..<6])
        #expect(MultiCursor.addCursor(in: text, ranges: [9..<9], below: false) == [6..<6, 9..<9])
        #expect(MultiCursor.addCursor(in: text, ranges: [1..<1], below: false) == [1..<1])
    }

    @Test("AutoReplace: skrót na granicy słowa, kursor z |, symbole, bez zamiany w literale")
    func autoReplace() {
        let rules = AutoReplaceRule.defaults + [AutoReplaceRule(abbreviation: "->", replacement: "→")]
        let a = try! #require(AutoReplace.apply(rules, text: "x := sf ", caret: 8))
        #expect(a.range == 5..<8 && a.replacement == "SELECT * FROM  " && a.caret == 20)
        let b = try! #require(AutoReplace.apply(rules, text: "begin dbo;", caret: 10))
        #expect(b.replacement == "dbms_output.put_line();" && b.caret == 6 + 21)
        #expect(AutoReplace.apply(rules, text: "xsf ", caret: 4) == nil)
        #expect(AutoReplace.apply(rules, text: "'sf ", caret: 4) == nil)
        #expect(AutoReplace.apply(rules, text: "a-> ", caret: 4)?.replacement == "→ ")
        #expect(AutoReplace.apply(rules, text: "sf", caret: 2) == nil)
    }

    @Test("Rozmiar czcionki: kolejne rozmiary, granice i domyślny")
    func zoom() {
        #expect(EditorZoom.next(13, step: 1) == 14 && EditorZoom.next(13, step: -1) == 12)
        #expect(EditorZoom.next(40, step: 1) == 40 && EditorZoom.next(8, step: -1) == 8 && EditorZoom.next(20, step: 0) == 13)
    }

    @Test("Stan okna pliku: zapis przy zamknięciu, przywrócenie przy otwarciu; zmieniony plik — tylko kursor")
    func windowState() throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let f = try t.file("a.sql", "select 1 from dual;\nselect 2 from dual;\n")
        let doc = try ws.openFile(f)
        doc.selectedRange = 22..<26
        doc.bookmarks = [Bookmark(number: 3, offset: 20, name: "drugie")]
        doc.colorMarks = [ColorMark(range: 0..<6, color: 1)]
        doc.variableValues["x"] = .text("10")
        doc.isReadOnly = true
        ws.close(doc.id)
        let again = try ws.openFile(f)
        #expect(again.selectedRange == 22..<26 && again.bookmarks.first?.name == "drugie" && again.colorMarks.count == 1)
        #expect(again.variableValues["x"] == .text("10") && again.isReadOnly)
        let stateFiles = try FileManager.default.contentsOfDirectory(atPath: t.url.appendingPathComponent("WindowState").path)
        #expect(stateFiles.count == 1 && !stateFiles[0].contains("a.sql"))
        ws.close(again.id)
        try Data("select 1 from dual;\n".utf8).write(to: f)
        let changed = try ws.openFile(f)
        #expect(changed.bookmarks.isEmpty && changed.selectedRange == 20..<20)
    }

    @Test("Otwieranie: katalog — skrypty w kolejności nazw, bez ukrytych i innych plików; komenda z połączeniem")
    func openWithConnection() async throws {
        let t = try TempDirectory()
        _ = try t.file("dir/b.pkb", "x")
        _ = try t.file("dir/a.sql", "y")
        _ = try t.file("dir/notes.md", "z")
        _ = try t.file("dir/.hidden.sql", "h")
        let files = FileOpening.files(from: [t.url.appendingPathComponent("dir")])
        #expect(files.map(\.lastPathComponent) == ["a.sql", "b.pkb"])
        let ws = Workspace()
        let def = ConnectionDefinition(name: "Dev", target: ConnectionTarget(user: "scott", connectString: "db:1521/dev"))
        try ws.connections.upsert(def)
        let r = try await ws.invoke("file.openWithConnection", CommandArguments(["path": .string(t.url.appendingPathComponent("dir").path), "connection": "dev"]))
        #expect(r.value == .array(["a.sql", "b.pkb"]))
        #expect(ws.documents.allSatisfy { $0.connectionID == def.id && $0.connectionPinned })
        await #expect(throws: (any Error).self) {
            try await ws.invoke("file.openWithConnection", CommandArguments(["path": .string(t.url.path), "connection": "brak"]))
        }
    }

    @Test("Wyszukiwanie: opcje (wielkość liter, całe słowa, regex), wszystkie edytory i pliki w katalogach")
    func search() async throws {
        let text = "select EMP_ID from emp;\n-- emp\nupdate Emp set x = 1;"
        #expect(EditorSearch.find("emp", in: text, options: TextSearchOptions()).map(\.line) == [1, 1, 2, 3])
        #expect(EditorSearch.find("emp", in: text, options: TextSearchOptions(wholeWord: true)).map(\.column) == [20, 4, 8])
        #expect(EditorSearch.find("Emp", in: text, options: TextSearchOptions(caseSensitive: true, wholeWord: true)).count == 1)
        #expect(EditorSearch.find("e.p_", in: text, options: TextSearchOptions(regex: true)).first?.range == 7..<11)
        #expect(EditorSearch.find("(", in: text, options: TextSearchOptions(regex: true)).isEmpty)
        let t = try TempDirectory()
        _ = try t.file("src/p.pkb", "procedure p is begin null; end;\n-- emp\n")
        _ = try t.file("src/sub/q.sql", "select * from emp;")
        _ = try t.file("src/x.bin", "emp")
        let ws = Workspace()
        _ = ws.newDocument(.sql, text: text)
        _ = ws.newDocument(.program, text: "emp")
        #expect(EditorSearch.search("emp", scope: .allEditors, options: TextSearchOptions(wholeWord: true), in: ws).count == 4)
        let files = EditorSearch.search("emp", scope: .directories([t.url.appendingPathComponent("src")]), options: TextSearchOptions(), in: ws)
        #expect(Set(files.compactMap { $0.fileURL?.lastPathComponent }) == ["p.pkb", "q.sql"])
        // Ten sam wynik poza wątkiem głównym (okno Search Bar szuka w plikach w tle).
        let dir = t.url.appendingPathComponent("src")
        let detached = await Task.detached { EditorSearch.searchFiles("emp", in: [dir], options: TextSearchOptions()) }.value
        #expect(detached == files)
        let r = try await ws.invoke("edit.searchBar", CommandArguments(["query": "emp", "scope": "current", "wholeWord": true]))
        #expect(r.message == "Trafień: 1")
        await #expect(throws: (any Error).self) {
            try await ws.invoke("edit.searchBar", CommandArguments(["query": "emp", "scope": "files", "directories": .string(t.url.path)]),
                                invoker: .agent(sessionID: "s", agentName: "a"))
        }
    }

    @Test("Command Window: pliki po @ i START (z podkatalogiem), aliasy po CONNECT …@")
    func commandWindowAssist() throws {
        let t = try TempDirectory()
        _ = try t.file("scripts/install.sql", "")
        _ = try t.file("scripts/data.txt", "")
        _ = try t.file("setup.sql", "")
        _ = try t.file("image.png", "")
        let r = try #require(CommandWindowAssist.complete(line: "@s", offset: 2, directory: t.url, aliases: []))
        #expect(r.items.map(\.label) == ["scripts/", "setup.sql"] && r.replaceRange == 1..<2)
        let sub = try #require(CommandWindowAssist.complete(line: "start scripts/in", offset: 16, directory: t.url, aliases: []))
        #expect(sub.items.map(\.label) == ["install.sql"] && sub.prefix == "in")
        #expect(CommandWindowAssist.complete(line: "@x", offset: 2, directory: t.url, aliases: []) == nil)
        let c = try #require(CommandWindowAssist.complete(line: "connect scott@de", offset: 16, directory: t.url, aliases: ["DEV", "PROD", "DEV2"]))
        #expect(c.items.map(\.label) == ["DEV", "DEV2"] && c.replaceRange == 14..<16)
        #expect(CommandWindowAssist.complete(line: "select 1 from dual", offset: 18, directory: t.url, aliases: ["DEV"]) == nil)
    }

    @Test("Deklaracja w dymku: zmienna, parametr, kursor; słowo kluczowe i nieznana nazwa — nic")
    func hover() {
        let text = """
        create or replace procedure p(p_id in number) is
          v_name varchar2(30) := 'x';
          cursor c_emp is select * from emp;
        begin
          v_name := to_char(p_id);
          open c_emp;
        end;
        """
        let ns = text as NSString
        let v = ns.range(of: "v_name :=").location + 2
        #expect(DeclarationHover.text(at: v, in: text)?.hasPrefix("zmienna — linia 2\nv_name varchar2(30)") == true)
        #expect(DeclarationHover.text(at: ns.range(of: "p_id);").location + 1, in: text)?.hasPrefix("parametr") == true)
        #expect(DeclarationHover.text(at: ns.range(of: "c_emp;").location + 1, in: text)?.hasPrefix("kursor") == true)
        #expect(DeclarationHover.text(at: ns.range(of: "begin").location + 1, in: text) == nil)
        #expect(DeclarationHover.text(at: ns.range(of: "to_char").location + 1, in: text) == nil)
    }

    @Test("Długie identyfikatory: ostrzeżenie powyżej limitu, limit 0 wyłącza")
    func longIdentifiers() {
        let text = "declare a_very_long_identifier_name_exceeding_x number; begin null; end;"
        #expect(CodeInspections.inspect(text).contains { $0.code == "long-identifier" })
        #expect(!CodeInspections.inspect(text, identifierLimit: 0).contains { $0.code == "long-identifier" })
        #expect(!CodeInspections.inspect(text, identifierLimit: 128).contains { $0.code == "long-identifier" })
    }

    @Test("Komendy: zakładki, kolor, kursory, podział, rozmiar czcionki, tylko do odczytu")
    func commands() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.sql, text: "select 1 from dual;\nselect 2 from dual;\n")
        doc.selectedRange = 25..<25
        try await ws.invoke("edit.toggleBookmark", CommandArguments(["number": 4]))
        doc.selectedRange = 0..<0
        try await ws.invoke("edit.gotoBookmark", CommandArguments(["number": 4]))
        #expect(doc.selectedRange == 20..<20)
        try await ws.invoke("edit.renameBookmark", CommandArguments(["number": 4, "name": "druga"]))
        #expect(doc.bookmarks.first?.name == "druga")
        let list = try await ws.invoke("edit.bookmarkList")
        #expect(list.value == .array([.object(["window": .string(doc.title), "number": 4, "line": 2, "name": "druga"])]))
        doc.selectedRange = 0..<6
        try await ws.invoke("edit.colorMark", CommandArguments(["color": 3]))
        #expect(doc.colorMarks == [ColorMark(range: 0..<6, color: 3)])
        doc.selectedRange = 2..<2
        try await ws.invoke("edit.addCursorBelow")
        #expect(doc.selectedRange == 2..<2 && doc.additionalSelections == [22..<22])
        try await ws.invoke("edit.singleCursor")
        #expect(doc.additionalSelections.isEmpty)
        try await ws.invoke("view.splitEditor")
        #expect(doc.splitEditor)
        ws.settings.editorFontSize = 13
        try await ws.invoke("view.zoomIn")
        try await ws.invoke("view.zoomIn")
        #expect(ws.settings.editorFontSize == 16)
        try await ws.invoke("view.zoomReset")
        #expect(ws.settings.editorFontSize == 13)
        try await ws.invoke("file.readOnly")
        #expect(doc.isReadOnly)
        doc.selectedRange = 7..<8
        await #expect(throws: (any Error).self) { try await ws.invoke("edit.extractLocalConstant", CommandArguments(["name": "c_one"])) }
        await #expect(throws: (any Error).self) { try await ws.invoke("edit.uppercase") }
        #expect(doc.text.hasPrefix("select 1"))
    }
}

@Suite("Refaktoryzacja PL/SQL (PD-CA-014)")
struct RefactoringTests {
    @Test("Stała lokalna w procedurze i w bloku bez DECLARE; typ z wyrażenia albo podany")
    func localConstant() throws {
        let proc = "create or replace procedure p is\n  v number;\nbegin\n  v := 42 * 2;\nend;\n"
        let sel = (proc as NSString).range(of: "42")
        let e = try CodeRefactoring.extractLocalConstant(proc, selection: sel.location..<(sel.location + 2), name: "c_answer")
        #expect(e.text == "create or replace procedure p is\n  v number;\n  c_answer CONSTANT NUMBER := 42;\nbegin\n  v := c_answer * 2;\nend;\n")
        #expect((e.text as NSString).substring(with: NSRange(location: e.selection.lowerBound, length: e.selection.count)) == "c_answer")
        let block = "begin\n  dbms_output.put_line('Witaj');\nend;\n"
        let s = (block as NSString).range(of: "'Witaj'")
        let b = try CodeRefactoring.extractLocalConstant(block, selection: s.location..<(s.location + s.length), name: "c_msg")
        #expect(b.text == "DECLARE\n  c_msg CONSTANT VARCHAR2(5) := 'Witaj';\nbegin\n  dbms_output.put_line(c_msg);\nend;\n")
        let f = "begin\n  x := sysdate + 1;\nend;\n"
        let fs = (f as NSString).range(of: "sysdate + 1")
        #expect(throws: RefactoringError.self) { try CodeRefactoring.extractLocalConstant(f, selection: fs.location..<(fs.location + fs.length), name: "c_d") }
        let typed = try CodeRefactoring.extractLocalConstant(f, selection: fs.location..<(fs.location + fs.length), name: "c_d", type: "DATE")
        #expect(typed.text.contains("c_d CONSTANT DATE := sysdate + 1;") && typed.text.contains("x := c_d;"))
        #expect(throws: RefactoringError.self) { try CodeRefactoring.extractLocalConstant(f, selection: fs.location..<(fs.location + fs.length), name: "begin", type: "DATE") }
    }

    @Test("Stała globalna w ciele pakietu")
    func globalConstant() throws {
        let pkg = "create or replace package body emp_api is\n  procedure p is\n  begin\n    raise_application_error(-20001, 'x');\n  end;\nend emp_api;\n"
        let s = (pkg as NSString).range(of: "-20001")
        let e = try CodeRefactoring.extractGlobalConstant(pkg, selection: s.location..<(s.location + s.length), name: "c_err")
        #expect(e.text.hasPrefix("create or replace package body emp_api is\n  c_err CONSTANT NUMBER := -20001;\n  procedure p is"))
        #expect(e.text.contains("raise_application_error(c_err, 'x');"))
        #expect(throws: RefactoringError.self) { try CodeRefactoring.extractGlobalConstant("begin x := 1; end;", selection: 11..<12, name: "c") }
    }

    @Test("Wydzielenie procedury: parametry IN i IN OUT z użytych deklaracji, wywołanie w miejscu instrukcji")
    func extractProcedure() throws {
        let src = """
        create or replace procedure p(p_id in number) is
          v_total number := 0;
          c_rate constant number := 2;
        begin
          v_total := p_id * c_rate;
          dbms_output.put_line(v_total);
        end;
        """
        let ns = src as NSString
        let start = ns.range(of: "  v_total := p_id").location
        let end = NSMaxRange(ns.range(of: "put_line(v_total);"))
        let e = try CodeRefactoring.extractProcedure(src, selection: start..<end, name: "compute")
        #expect(e.text.contains("  PROCEDURE compute(v_total IN OUT number, p_id IN number, c_rate IN number) IS\n  BEGIN\n    v_total := p_id * c_rate;\n    dbms_output.put_line(v_total);\n  END compute;\nbegin"))
        #expect(e.text.contains("begin\n  compute(v_total, p_id, c_rate);\nend;"))
    }

    @Test("Przypisanie na początku ciała → inicjalizacja; wewnątrz IF albo z wartością początkową — błąd")
    func replaceAssignment() throws {
        let src = "declare\n  v_count number;\nbegin\n  v_count := 0;\n  null;\nend;\n"
        let at = (src as NSString).range(of: "v_count := 0").location + 1
        let e = try CodeRefactoring.replaceAssignmentWithInitialization(src, at: at)
        #expect(e.text == "declare\n  v_count number := 0;\nbegin\n  null;\nend;\n")
        let nested = "declare\n  v number;\nbegin\n  if true then\n    v := 1;\n  end if;\nend;\n"
        #expect(throws: RefactoringError.self) { try CodeRefactoring.replaceAssignmentWithInitialization(nested, at: (nested as NSString).range(of: "v := 1").location) }
        let initialized = "declare\n  v number := 5;\nbegin\n  v := 1;\nend;\n"
        #expect(throws: RefactoringError.self) { try CodeRefactoring.replaceAssignmentWithInitialization(initialized, at: (initialized as NSString).range(of: "v := 1").location) }
    }
}

@MainActor
@Suite("Code Assistant: preferencje, (all), parametry (PD-CA-006, PD-CA-007)")
struct CodeAssistantOptionsTests {
    @Test("Dopasowanie „zawiera”, wielkość liter, minimum znaków, funkcje standardowe")
    func options() async throws {
        var o = CompletionOptions()
        let items = [CompletionItem(label: "EMP_NAME", kind: .column), CompletionItem(label: "NAME", kind: .column), CompletionItem(label: "DEPT", kind: .column)]
        #expect(CodeAssistant.filter(items, prefix: "name").map(\.label) == ["NAME"])
        #expect(CodeAssistant.filter(items, prefix: "name", match: .contains).map(\.label) == ["NAME", "EMP_NAME"])
        #expect(CodeAssistant.applyCase(items[0], prefix: "e", letterCase: .upper).insertText == "EMP_NAME")
        #expect(CodeAssistant.applyCase(items[0], prefix: "E", letterCase: .initCap).insertText == "Emp_Name")
        #expect(CodeAssistant.applyCase(items[0], prefix: "E", letterCase: .lower).insertText == "emp_name")
        #expect(CodeAssistant.applyCase(CompletionItem(label: "MixedName", kind: .column), prefix: "", letterCase: .upper).insertText == "MixedName")
        let fn = try #require(await CodeAssistant.complete(text: "select nvl", offset: 10, metadata: nil, options: o))
        #expect(fn.items.contains { $0.label == "NVL" && $0.kind == .function } && fn.items.contains { $0.label == "NVL2" })
        o.standardFunctions = false
        #expect(await CodeAssistant.complete(text: "select nvl", offset: 10, metadata: nil, options: o)?.items.contains { $0.kind == .function } != true)
        o.minimumCharacters = 4
        #expect(await CodeAssistant.complete(text: "select nvl", offset: 10, metadata: nil, options: o)?.items.contains { $0.kind == .keyword } != true)
    }

    @Test("(all): wszystkie pola po kwalifikatorze — w linii i po jednym w linii z przecinkiem na początku")
    func all() async throws {
        let text = "select e. from (select a, b, c from dual) e"
        let r = try #require(await CodeAssistant.complete(text: text, offset: 9, metadata: nil))
        #expect(r.items.first?.label == "(all)" && r.items.first?.insertText == "a, e.b, e.c")
        var o = CompletionOptions()
        o.allPerLine = true
        o.commaFirst = true
        let p = try #require(await CodeAssistant.complete(text: "  select e. from (select a, b from dual) e", offset: 11, metadata: nil, options: o))
        #expect(p.items.first?.insertText == "a\n       , e.b")
    }

    @Test("Parametry podprogramu lokalnego: pozycje „p => ” i (all) z wyrównaniem")
    func parameters() async throws {
        let text = """
        declare
          procedure log_it(p_message in varchar2, p_level in number default 1) is begin null; end;
        begin
          log_it(
        end;
        """
        let offset = (text as NSString).range(of: "log_it(\nend").location + 7
        let r = try #require(await CodeAssistant.complete(text: text, offset: offset, metadata: nil))
        #expect(r.items.map(\.label) == ["(all)", "p_message", "p_level"])
        #expect(r.items[0].insertText == "p_message => , p_level => " && r.items[1].insertText == "p_message => ")
        var o = CompletionOptions()
        o.allPerLine = true
        let aligned = try #require(await CodeAssistant.complete(text: text, offset: offset, metadata: nil, options: o))
        #expect(aligned.items[0].insertText == "p_message => ,\n         p_level   => ")
    }
}
