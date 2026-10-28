import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Pliki jednostek bez „/” (konwencja właściciela, D192): jednostki rozpoznawane po nagłówkach CREATE na początku
/// linii, z „/” i bez; zapis i nowe jednostki bez dopisywanego „/”.
@MainActor
@Suite("Okno programu: jednostki bez „/”")
struct ProgramUnitsWithoutSlashTests {
    static let noSlash = """
    -- pakiet kadr
    CREATE OR REPLACE PACKAGE kadry AS
      PROCEDURE a;
      c CONSTANT VARCHAR2(30) := 'create package x';
    END kadry;

    /* create or replace package body w komentarzu */
    CREATE OR REPLACE
    PACKAGE BODY kadry AS
      PROCEDURE a IS
      BEGIN
        EXECUTE IMMEDIATE 'create table t (x number)';
      END a;
    END kadry;
    """

    func line(_ n: Int, _ text: String) -> Int { TextEditing.offset(ofLine: n, in: text) }

    @Test("bez „/”: dwie jednostki po nagłówkach CREATE (literały i komentarze nie są nagłówkami), linie i tekst do kompilacji")
    func unitsWithoutSlash() throws {
        let units = ProgramCompiler.units(in: Self.noSlash)
        #expect(units.map(\.type) == [.package, .packageBody])
        #expect(units.map(\.name) == ["KADRY", "KADRY"])
        // Tekst jednostki do kompilacji: od CREATE do „END kadry;” — bez komentarza przed następną jednostką.
        #expect(units[0].text.hasPrefix("CREATE OR REPLACE PACKAGE kadry AS") && units[0].text.hasSuffix("END kadry;"))
        #expect(units[1].text.hasPrefix("CREATE OR REPLACE\nPACKAGE BODY") && units[1].text.hasSuffix("END kadry;"))
        // Linie (od 0): CREATE ciała w linii 7, słowo typu (linia 1 ALL_ERRORS) w linii 8 (D189).
        #expect(units[1].line == 7 && units[1].sourceLine == 8)
        // Karty: komentarz przed CREATE i pusta linia — na karcie ciała.
        let tabs = ProgramUnitTabs.tabs(units, in: Self.noSlash)
        #expect(tabs.count == 2)
        #expect(tabs[1].segment.lowerBound == line(6, Self.noSlash))
        // Code Contents: specyfikacja i ciało osobno, procedura publiczna.
        let outline = PLSQLOutline.parse(Self.noSlash)
        #expect(outline.map(\.kind) == [.package, .packageBody])
        #expect(outline[1].children.first { $0.name == "a" }?.isPublic == true)
    }

    @Test("z „/” bez zmian; plik mieszany (jedna jednostka z „/”, następna bez) — trzy jednostki")
    func withAndMixed() throws {
        let slash = "create package p as end;\n/\ncreate package body p as end;\n/\n"
        let su = ProgramCompiler.units(in: slash)
        #expect(su.map(\.type) == [.package, .packageBody])
        #expect(su.map(\.text) == ["create package p as end;", "create package body p as end;"])
        let mixed = "create procedure a is begin null; end;\n/\ncreate procedure b is begin null; end;\ncreate function c return number is begin return 1; end;\n"
        #expect(ProgramCompiler.units(in: mixed).map(\.name) == ["A", "B", "C"])
        #expect(ProgramText.usesSlash(slash) && ProgramText.usesSlash(mixed) && !ProgramText.usesSlash(Self.noSlash))
        // Źródło Java: słowo „create” w kodzie nie jest nagłówkiem (nie na początku linii albo bez typu jednostki).
        let java = "create or replace and compile java source named \"A\" as\npublic class A {\n  static A create() { return new A(); }\n}\n"
        #expect(ProgramCompiler.units(in: java).count == 1)
    }

    @Test("tekst z bazy: bez „/” domyślnie, z „/” przy preferencji; zapis nie dopisuje „/”; nowa jednostka w konwencji pliku")
    func joinSaveAndAdd() async throws {
        #expect(ProgramText.join(["create package p as end;\n", "create package body p as end;"], slash: false)
                == "create package p as end;\n\ncreate package body p as end;\n")
        #expect(ProgramText.join(["create package p as end;"], slash: true) == "create package p as end;\n/\n")
        let ws = Workspace()
        #expect(ws.settings.programUnitSlash == false)
        let doc = ws.newDocument(.program, text: Self.noSlash)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-noslash-\(UUID().uuidString).pck")
        defer { try? FileManager.default.removeItem(at: url) }
        try ws.save(doc, to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.noSlash)
        // Dodaj jednostkę: plik bez „/” — nowa bez „/”; plik z „/” — z „/”.
        ws.activate(doc.id)
        try await ws.invoke("prog.addUnit", CommandArguments(["template": .string("Funkcja"), "values": .object(["Nazwa": .string("premia")])]))
        #expect(!doc.text.components(separatedBy: "\n").contains("/"))
        #expect(ProgramCompiler.units(in: doc.text).map(\.name) == ["KADRY", "KADRY", "PREMIA"])
        let withSlash = ws.newDocument(.program, text: "create procedure a is begin null; end;\n/\n")
        ws.activate(withSlash.id)
        try await ws.invoke("prog.addUnit", CommandArguments(["text": .string("create procedure b is begin null; end;")]))
        #expect(withSlash.text == "create procedure a is begin null; end;\n/\n\ncreate procedure b is begin null; end;\n/\n")
    }

    @Test("Java i MLE bez „/”: treść nie jest leksowana jak PL/SQL; GRANT i SHOW ERRORS za jednostką nie doklejają się")
    func foreignAndNonUnits() {
        let java = "create or replace and compile java source named \"A\" as\npublic class A {\n  // don't stop\n  String s = \"it's\";\n}\ncreate or replace procedure p is begin null; end;\n"
        #expect(ProgramCompiler.units(in: java).map(\.type) == [.javaSource, .procedure])
        let mle = "create or replace mle module m language javascript as\nexport function f() { return `don't`; }\ncreate or replace function g return number is begin return 1; end;\n"
        #expect(ProgramCompiler.units(in: mle).map(\.type) == [.mleModule, .function])
        // Komentarze PL/SQL między jednostkami nie trafiają do źródła Java/JS.
        let commented = "create or replace and compile java source named \"A\" as\npublic class A {\n  /* metoda */\n  int x;\n}\n\n-- procedura\n/* opis\n   wielu linii */\ncreate or replace procedure p is begin null; end;\n"
        #expect(ProgramCompiler.units(in: commented).first?.text.hasSuffix("int x;\n}") == true)
        let grants = "create procedure p is begin null; end;\ngrant execute on p to scott;\nshow errors\ncreate procedure q is begin null; end;\n"
        let units = ProgramCompiler.units(in: grants)
        #expect(units.map(\.name) == ["P", "Q"])
        #expect(units.first?.text == "create procedure p is begin null; end;")
        // Zmienna „show” w PL/SQL to nie SHOW ERRORS.
        let body = "create procedure p is\n  show number;\nbegin\n  show := 1;\nend;\n"
        #expect(ProgramCompiler.units(in: body).first?.text.hasSuffix("end;") == true)
    }

    @Test("wydajność: plik bez „/” z 600 jednostkami — podział liniowy, linie i teksty jednostek")
    func manyUnits() {
        var text = ""
        for i in 0..<600 { text += "create or replace procedure p\(i) is\nbegin\n  null;\nend p\(i);\n\n" }
        let start = Date()
        let units = ProgramCompiler.units(in: text)
        let elapsed = Date().timeIntervalSince(start)
        #expect(units.count == 600)
        #expect(units.last?.line == 599 * 5 && units.last?.text.hasSuffix("end p599;") == true)
        #expect(elapsed < 3, "\(elapsed) s")
    }

    @Test("szablon jednostek w oknie SQL: jednostki zakończone „/” (blok PL/SQL), kursor przesunięty; w oknie programu bez „/”")
    func templateInSQLWindow() async throws {
        let ws = Workspace()
        let sql = ws.newDocument(.sql, text: "")
        ws.activate(sql.id)
        let pkg = TemplateLibrary.programFolder + "/" + L10n.tr("Pakiet")
        try await ws.invoke("edit.insertTemplate", CommandArguments(["template": .string(pkg), "values": .object(["Nazwa": .string("kadry")])]))
        #expect(sql.text.components(separatedBy: "\n").filter { $0 == "/" }.count == 2)
        #expect(ScriptSplitter.split(sql.text).count == 2)
        #expect((sql.text as NSString).substring(from: sql.selectedRange.lowerBound).hasPrefix("null;"))
        let prog = ws.newDocument(.program, text: "")
        ws.activate(prog.id)
        try await ws.invoke("edit.insertTemplate", CommandArguments(["template": .string(pkg), "values": .object(["Nazwa": .string("kadry")])]))
        #expect(!prog.text.components(separatedBy: "\n").contains("/"))
        #expect(ProgramCompiler.units(in: prog.text).count == 2)
    }
}
