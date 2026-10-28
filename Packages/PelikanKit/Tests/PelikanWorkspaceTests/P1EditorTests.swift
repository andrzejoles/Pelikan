import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@Suite("Edytor P1: status linii, wcięcia, zwijanie")
struct EditorP1Tests {
    @Test("Status linii: zmienione i nowe względem stanu bazowego, duża zmiana bez diffu")
    func lineStatus() {
        let base = "a\nb\nc\nd\n"
        #expect(TextDiff.lineStatus(baseline: base, current: base).isEmpty)
        #expect(TextDiff.lineStatus(baseline: base, current: "a\nB\nc\nd\n") == [1: .modified])
        #expect(TextDiff.lineStatus(baseline: base, current: "a\nb\nx\ny\nc\nd\n") == [2: .added, 3: .added])
        #expect(TextDiff.lineStatus(baseline: base, current: "a\n\nb\nc\nd\n") == [1: .added])
        #expect(TextDiff.lineStatus(baseline: base, current: "a\nc\nd\n").isEmpty)
        let big = (0..<3000).map { "l\($0)" }.joined(separator: "\n")
        let changed = (0..<3000).map { "m\($0)" }.joined(separator: "\n")
        let s = TextDiff.lineStatus(baseline: big, current: changed)
        #expect(s.count == 3000 && s[0] == .modified)
    }

    @Test("Interwał numeracji linii i znaki specjalne")
    func numbering() {
        #expect((0..<12).filter { LineNumbering.shows(line: $0, caretLine: 7, interval: 5) } == [0, 4, 7, 9])
        #expect((0..<3).allSatisfy { LineNumbering.shows(line: $0, caretLine: 0, interval: 1) })
        #expect([0x20, 0x09, 0x0A, 0x41].map { LineNumbering.specialMark(unichar($0)) } == ["·", "→", "¶", nil])
    }

    @Test("Podgląd zwiniętego obszaru: ukryte linie bez wspólnego wcięcia, ograniczenie liczby linii")
    func foldPreview() throws {
        let text = "begin\n  if a then\n    x := 1;\n  end if;\nend;\n"
        let r = try #require(CodeFolding.regions(text).first { $0.startLine == 0 })
        #expect(CodeFolding.preview(r, in: text) == "  if a then\n    x := 1;\n  end if;\nend;")
        #expect(CodeFolding.preview(r, in: text, maxLines: 2) == "if a then\n  x := 1;\n…")
    }

    @Test("Wcięcia: None/Automatic/Smart, wyrównanie END/ELSE, Backspace usuwa jednostkę")
    func indent() {
        #expect(SmartIndent.newlineIndent(lineBeforeCaret: "  x := 1;", mode: .none, unit: "  ") == "")
        #expect(SmartIndent.newlineIndent(lineBeforeCaret: "  begin", mode: .automatic, unit: "  ") == "  ")
        #expect(SmartIndent.newlineIndent(lineBeforeCaret: "  begin", mode: .smart, unit: "  ") == "    ")
        #expect(SmartIndent.newlineIndent(lineBeforeCaret: "if a > 1 then -- uwaga", mode: .smart, unit: "  ") == "  ")
        #expect(SmartIndent.newlineIndent(lineBeforeCaret: "  p(a,", mode: .smart, unit: "  ") == "  ")
        #expect(SmartIndent.newlineIndent(lineBeforeCaret: "  p(", mode: .smart, unit: "  ") == "    ")
        #expect(SmartIndent.newlineIndent(lineBeforeCaret: "  x := 'then'", mode: .smart, unit: "  ") == "  ")
        #expect(SmartIndent.reindentClosingLine("  end;", previous: "  null;", unit: "  ") == "end;")
        #expect(SmartIndent.reindentClosingLine("  end;", previous: "begin", unit: "  ") == "end;")
        #expect(SmartIndent.reindentClosingLine("    else", previous: "    a := 1;", unit: "  ") == "  else")
        #expect(SmartIndent.reindentClosingLine("end;", previous: "  null;", unit: "  ") == nil)
        #expect(SmartIndent.reindentClosingLine("  x := 1;", previous: "  null;", unit: "  ") == nil)
        #expect(SmartIndent.backspaceUnindent(lineBeforeCaret: "    ", unit: "  ") == 2)
        #expect(SmartIndent.backspaceUnindent(lineBeforeCaret: "   ", unit: "  ") == 1)
        #expect(SmartIndent.backspaceUnindent(lineBeforeCaret: "  x", unit: "  ") == nil)
        #expect(SmartIndent.backspaceUnindent(lineBeforeCaret: "    ", unit: "\t") == nil)
    }

    @Test("Stan bazowy dokumentu: otwarcie, edycja, zapis")
    @MainActor
    func baseline() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-p1e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ws = Workspace(dataDirectory: dir)
        let doc = ws.newDocument(.sql, text: "select 1 from dual;\n")
        #expect(doc.baselineText == "select 1 from dual;\n")
        doc.text = "select 2 from dual;\n"
        #expect(doc.baselineText == "select 1 from dual;\n" && doc.isModified)
        try ws.save(doc, to: dir.appendingPathComponent("a.sql"))
        #expect(doc.baselineText == "select 2 from dual;\n")
    }
}

@MainActor
@Suite("Okno programu P1: jednostki, Java/MLE, Revert")
struct ProgramP1Tests {
    func workspace() -> (Workspace, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-p1p-\(UUID().uuidString)")
        return (Workspace(dataDirectory: dir), dir)
    }

    @Test("Szablony Java i MLE w jednostkach programów; nagłówki CREATE AND COMPILE JAVA SOURCE i MLE MODULE")
    func javaAndMLE() async throws {
        let (ws, dir) = workspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        let units = TemplateLibrary.builtIn.filter { $0.folder == TemplateLibrary.programFolder }.map(\.name)
        #expect(units.contains("Źródło Java") && units.contains("Moduł MLE (JavaScript)"))
        try await ws.invoke("file.newFromTemplate", CommandArguments(["template": .string("Źródło Java"), "values": .object(["Klasa": .string("Pomocnik")])]))
        let java = try #require(ws.activeDocument)
        #expect(java.kind == .program && java.text.contains("public class Pomocnik"))
        #expect(ProgramCompiler.units(in: java.text).map(\.type) == [.javaSource])
        #expect(ProgramCompiler.units(in: java.text).first?.name == "Pomocnik")
        try await ws.invoke("file.newFromTemplate", CommandArguments(["template": .string("Moduł MLE (JavaScript)"), "values": .object(["Nazwa": .string("narzedzia")])]))
        let mle = try #require(ws.activeDocument)
        #expect(ProgramCompiler.units(in: mle.text).map(\.type) == [.mleModule])
        #expect(ProgramCompiler.units(in: mle.text).first?.name == "NARZEDZIA")
    }

    @Test("Dodanie jednostki z szablonu i z tekstu, usunięcie karty z ukośnikiem")
    func addRemove() async throws {
        let (ws, dir) = workspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        
        try await ws.invoke("file.newFromTemplate", CommandArguments(["template": .string("Pakiet"), "values": .object(["Nazwa": .string("kadry")])]))
        let doc = try #require(ws.activeDocument)
        try await ws.invoke("prog.addUnit", CommandArguments(["template": .string("Funkcja"), "values": .object(["Nazwa": .string("premia")])]))
        #expect(ProgramCompiler.units(in: doc.text).map(\.name) == ["KADRY", "KADRY", "PREMIA"])
        try await ws.invoke("prog.addUnit", CommandArguments(["text": .string("create or replace procedure log_it is\nbegin\n  null;\nend;")]))
        let units = ProgramCompiler.units(in: doc.text)
        #expect(units.map(\.name) == ["KADRY", "KADRY", "PREMIA", "LOG_IT"])
        // Bez „/” (D192): szablony i dodana jednostka bez kończącego ukośnika.
        #expect(doc.text.hasSuffix("end;\n") && !doc.text.contains("\n/\n"))
        try await ws.invoke("prog.removeUnit", CommandArguments(["unit": .string("kadry body")]))
        #expect(ProgramCompiler.units(in: doc.text).map(\.type) == [.package, .function, .procedure])
        #expect(!doc.text.contains("package body"))
        doc.selectedRange = (doc.text as NSString).length - 3..<(doc.text as NSString).length - 3
        try await ws.invoke("prog.removeUnit")
        #expect(ProgramCompiler.units(in: doc.text).map(\.name) == ["KADRY", "PREMIA"])
        #expect(!doc.text.contains("\n\n\n"))
        await #expect(throws: CommandError.self) { try await ws.invoke("prog.removeUnit", CommandArguments(["unit": .string("brak")])) }
    }

    @Test("Usuwanie jednostki: ukośnik i puste linie za nią, sąsiednie jednostki bez zmian")
    func removing() throws {
        let text = "create procedure a is begin null; end;\n/\n\ncreate procedure b is begin null; end;\n/\n"
        let units = ProgramCompiler.units(in: text)
        #expect(ProgramCompiler.removing(units[0], from: text) == "create procedure b is begin null; end;\n/\n")
        #expect(ProgramCompiler.removing(units[1], from: text) == "create procedure a is begin null; end;\n/\n\n")
    }

    @Test("Revert: tekst z chwili otwarcia, okno niezmienione; bez zmian — niedostępne")
    func revert() async throws {
        let (ws, dir) = workspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = ws.newDocument(.program, text: "create procedure a is begin null; end;\n/\n")
        #expect(ws.isEnabled("prog.revert") == false)
        doc.text = "create procedure a is begin raise; end;\n/\n"
        doc.selectedRange = 30..<30
        #expect(ws.isEnabled("prog.revert"))
        try await ws.invoke("prog.revert")
        #expect(doc.text == "create procedure a is begin null; end;\n/\n" && !doc.isModified)
        #expect(doc.selectedRange == 30..<30)
    }
}

@MainActor
@Suite("Code Contents: sortowanie i menu")
struct CodeContentsTests {
    static let text = """
        create or replace package body kadry as
          g_limit number := 10;
          procedure zwolnij(p_id number) is
          begin
            null;
          end;
          function awans(p_id number) return number is
          begin
            return 1;
          end;
        end kadry;
        /
        """

    @Test("Sortowanie: źródło, nazwa, rodzaj")
    func sort() {
        let roots = PLSQLOutline.parse(Self.text)
        let names = { (o: CodeContents.Order) in CodeContents.sorted(roots, order: o)[0].children.map(\.name).filter { $0 != "" } }
        #expect(names(.source).prefix(3) == ["g_limit", "zwolnij", "awans"])
        #expect(names(.name).prefix(3) == ["awans", "g_limit", "zwolnij"])
        #expect(names(.kind).prefix(3) == ["g_limit", "awans", "zwolnij"])
    }

    @Test("Zaznacz, kopiuj, wytnij element; cel testu podprogramu pakietu")
    func actions() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-cc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        let doc = ws.newDocument(.program, text: Self.text)
        
        let at = (Self.text as NSString).range(of: "awans").location
        let copied = try await ws.invoke("codeContents.copy", CommandArguments(["offset": .int(Int64(at))]))
        #expect(copied.value?.stringValue == "  function awans(p_id number) return number is\n  begin\n    return 1;\n  end;\n")
        try await ws.invoke("codeContents.select", CommandArguments(["offset": .int(Int64(at))]))
        let sel = (doc.text as NSString).substring(with: NSRange(location: doc.selectedRange.lowerBound, length: doc.selectedRange.count))
        #expect(sel.hasPrefix("  function awans") && sel.hasSuffix("end;\n"))
        let roots = PLSQLOutline.parse(doc.text)
        let node = try #require(CodeContents.element(at: at, in: roots))
        let target = try #require(CodeContents.testTarget(for: node, in: roots))
        #expect(target.object == "kadry" && target.member == "awans")
        try await ws.invoke("codeContents.cut", CommandArguments(["offset": .int(Int64(at))]))
        #expect(!doc.text.contains("awans") && doc.text.contains("zwolnij") && doc.text.contains("end kadry;"))
    }
}

@MainActor
@Suite("Code Assistant P1: notacja nazwana, kolekcje, SELF, deklaracje w oknach")
struct CodeAssistantP1Tests {
    static let proc = """
        declare
          procedure podwyzka(p_emp number, p_procent number, p_data date) is begin null; end;
        begin
          podwyzka(
        """

    @Test("Parametry w notacji nazwanej po nawiasie i po przecinku, bez podanych; prefiks przed zmiennymi")
    func named() async throws {
        let first = try #require(await CodeAssistant.complete(text: Self.proc, offset: (Self.proc as NSString).length, metadata: nil))
        #expect(first.items.map(\.label) == ["(all)", "p_emp", "p_procent", "p_data"])
        let after = Self.proc + "p_procent => 5, "
        let second = try #require(await CodeAssistant.complete(text: after, offset: (after as NSString).length, metadata: nil))
        #expect(second.items.map(\.label) == ["p_emp", "p_data"] && second.items[0].insertText == "p_emp => ")
        let typed = Self.proc + "1, p_d"
        let third = try #require(await CodeAssistant.complete(text: typed, offset: (typed as NSString).length, metadata: nil))
        #expect(third.items.first?.label == "p_data" && third.replaceRange.count == 3)
        // Argument wartości (po =>) — bez listy parametrów.
        let value = Self.proc + "p_emp => "
        #expect(CodeAssistant.callContext(text: value, offset: (value as NSString).length) == nil)
        let nested = Self.proc + "nvl(a, b), "
        #expect(CodeAssistant.callContext(text: nested, offset: (nested as NSString).length)?.parts == ["PODWYZKA"])
    }

    @Test("Metody kolekcji: tablica zagnieżdżona, VARRAY, tablica asocjacyjna")
    func collections() async throws {
        let text = """
            declare
              type t_lista is table of number;
              type t_mapa is table of varchar2(10) index by pls_integer;
              type t_tab is varray(5) of date;
              l t_lista;
              m t_mapa;
              v t_tab;
            begin
              l.
            """
        let r = try #require(await CodeAssistant.complete(text: text, offset: (text as NSString).length, metadata: nil))
        #expect(Set(r.items.map(\.label)).isSuperset(of: ["COUNT", "FIRST", "LAST", "NEXT", "EXISTS", "EXTEND", "TRIM", "DELETE"]))
        #expect(!r.items.contains { $0.label == "LIMIT" })
        let m = text.replacingOccurrences(of: "  l.", with: "  m.")
        let rm = try #require(await CodeAssistant.complete(text: m, offset: (m as NSString).length, metadata: nil))
        #expect(!rm.items.contains { $0.label == "EXTEND" } && rm.items.contains { $0.label == "COUNT" })
        let v = text.replacingOccurrences(of: "  l.", with: "  v.")
        let rv = try #require(await CodeAssistant.complete(text: v, offset: (v as NSString).length, metadata: nil))
        #expect(rv.items.contains { $0.label == "LIMIT" })
    }

    @Test("SELF w ciele typu: atrybuty i metody ze specyfikacji w oknie")
    func selfMembers() async throws {
        let text = """
            create or replace type punkt as object (
              x number,
              y number, -- współrzędna
              member function odleglosc(p punkt) return number,
              member procedure przesun(dx number)
            );
            /
            create or replace type body punkt as
              member procedure przesun(dx number) is
              begin
                self.
            """
        let r = try #require(await CodeAssistant.complete(text: text, offset: (text as NSString).length, metadata: nil))
        #expect(r.items.map(\.label) == ["(all)", "x", "y", "odleglosc", "przesun"])
        #expect(r.items.first { $0.label.lowercased() == "odleglosc" }?.kind == .function)
        #expect(CodeAssistant.enclosingTypeBody(text, offset: (text as NSString).length)?.name == "PUNKT")
        #expect(CodeAssistant.enclosingTypeBody(text + "\nend;\nend;\n/\nbegin ", offset: (text as NSString).length + 22) == nil)
    }

    @Test("Deklaracja w źródle i w innych oknach przed bazą")
    func declarationInWindows() async throws {
        let spec = "create or replace package kadry as\n  procedure zwolnij(p number);\nend;\n/\n"
        let body = "create or replace package body kadry as\n  procedure zwolnij(p number) is begin null; end;\nend;\n/\n"
        let hit = try #require(DeclarationLookup.find(["KADRY", "ZWOLNIJ"], in: ["begin kadry.zwolnij(1); end;", spec + body]))
        #expect(hit.documentIndex == 1)
        #expect(hit.range.lowerBound == ((spec + body) as NSString).range(of: "zwolnij", options: .backwards).location)
        #expect(DeclarationLookup.find(["KADRY"], in: [spec + body])?.range.lowerBound == (spec as NSString).range(of: "kadry").location)
        #expect(DeclarationLookup.find(["EMP"], in: [spec]) == nil)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-decl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        let program = ws.newDocument(.program, text: spec + body)
        let sql = ws.newDocument(.sql, text: "begin kadry.zwolnij(1); end;")
        sql.selectedRange = 14..<14
        try await ws.invoke("edit.gotoDeclaration")
        #expect(ws.activeDocument?.id == program.id)
        #expect((program.text as NSString).substring(with: NSRange(location: program.selectedRange.lowerBound, length: program.selectedRange.count)) == "zwolnij")
    }

    @Test("Menu obiektu na nazwie w edytorze: komendy z rejestru, nazwa spod kursora")
    func objectMenu() {
        let ids = Set(BuiltinCommands.all.map(\.descriptor.id))
        for a in EditorObjectMenu.actions { #expect(ids.contains(a.command), "\(a.command.rawValue)") }
        #expect(EditorObjectMenu.objectName(at: 16, in: "select * from scott.emp") == "scott.emp")
        #expect(EditorObjectMenu.objectName(at: 2, in: "select * from emp") == nil)
    }
}

@Suite("Formater P1: osobne reguły parametrów i INSERT")
struct BeautifierP1Tests {
    @Test("Deklaracje parametrów, wywołania i listy INSERT element w linii")
    func lists() throws {
        var o = BeautifierOptions()
        o.keywordCase = .lower
        let src = "create or replace procedure p(a number, b number) is\nbegin\nq(1, 2);\ninsert into t (x, y) values (1, 2);\nend;\n/\n"
        let fit = try Beautifier.format(src, options: o)
        #expect(fit.contains("procedure p(a number, b number)") && fit.contains("q(1, 2);"))
        o.parameterDeclarations = .onePerLine
        let decl = try Beautifier.format(src, options: o)
        #expect(decl.contains("procedure p(a number,\n") && decl.contains("q(1, 2);"))
        o.callParameters = .onePerLine
        let call = try Beautifier.format(src, options: o)
        #expect(call.contains("q(1,\n"))
        o.insertLists = .onePerLine
        let ins = try Beautifier.format(src, options: o)
        #expect(ins.contains("(x,\n") && ins.contains("(1,\n"))
        let decoded = try JSONDecoder().decode(BeautifierOptions.self, from: JSONEncoder().encode(o))
        #expect(decoded == o)
    }
}

/// Atrapa interfejsu: przechwytuje przeglądarkę różnic z funkcją Reload.
@MainActor
final class DiffUI: UIServices {
    var reload: DiffReload?
    var shown: [(String, String)] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { 0 }
    func askWithSuppression(_ title: String, message: String, buttons: [String]) async -> (Int?, Bool) { (0, false) }
    func openURL(_ url: URL) {}
    func openInApplication(_ file: URL, application: String?) {}
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { [:] }
    func copyToClipboard(_ text: String, html: String?) {}
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { true }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { nil }
    func showDiff(left: String, right: String, leftTitle: String, rightTitle: String, reload: DiffReload?) {
        shown.append((left, right))
        self.reload = reload
    }
}

@MainActor
@Suite("Przeglądarka różnic: Reload")
struct DiffReloadTests {
    @Test("Porównanie plików i okna z plikiem — Reload wczytuje aktualne teksty")
    func reload() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-diff-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ws = Workspace(dataDirectory: dir)
        let ui = DiffUI()
        ws.ui = ui
        let a = dir.appendingPathComponent("a.sql"), b = dir.appendingPathComponent("b.sql")
        try "select 1 from dual;\n".write(to: a, atomically: true, encoding: .utf8)
        try "select 2 from dual;\n".write(to: b, atomically: true, encoding: .utf8)
        try await ws.invoke("tools.compareFiles", CommandArguments(["left": .string(a.path), "right": .string(b.path)]))
        #expect(ui.shown.count == 1)
        try "select 3 from dual;\n".write(to: b, atomically: true, encoding: .utf8)
        let reloaded = try #require(try await ui.reload?())
        #expect(reloaded.left == "select 1 from dual;\n" && reloaded.right == "select 3 from dual;\n")

        let doc = ws.newDocument(.sql, text: "select 9 from dual;\n")
        try await ws.invoke("prog.compareWithFile", CommandArguments(["file": .string(a.path)]))
        doc.text = "select 10 from dual;\n"
        let again = try #require(try await ui.reload?())
        #expect(again.right == "select 10 from dual;\n")
    }
}
