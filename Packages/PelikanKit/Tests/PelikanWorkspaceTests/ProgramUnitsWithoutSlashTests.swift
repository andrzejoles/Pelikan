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
}
