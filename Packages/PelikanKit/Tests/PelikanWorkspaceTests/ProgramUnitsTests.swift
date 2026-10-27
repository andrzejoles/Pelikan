import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Jednostki programu")
struct ProgramUnitsTests {
    @Test("Specyfikacja i ciało pakietu, funkcja ze schematem, typ z ciałem, wyzwalacz; karty z nazw")
    func units() {
        let text = """
        create or replace package p as procedure x; end;
        /
        create or replace editionable package body p as procedure x is begin null; end; end;
        /
        CREATE FUNCTION scott."Mała" return number is begin return 1; end;
        /
        create or replace type t as object (a number);
        /
        create or replace trigger trg before insert on t2 for each row begin null; end;
        /
        """
        let u = ProgramCompiler.units(in: text)
        #expect(u.map(\.type) == [.package, .packageBody, .function, .type, .trigger])
        #expect(u[2].owner == "SCOTT" && u[2].name == "Mała")
        #expect(u.map(\.tabTitle).prefix(2) == ["p (specyfikacja)", "p (ciało)"])
        #expect(u[1].line == 2)
        #expect(ProgramCompiler.offset(line: 3, column: 5, in: text) == (text as NSString).range(of: "create or replace editionable").location + 4)
    }

    @Test("Kolumny w znakach jak Oracle, nie w UTF-16: emoji spoza BMP to jeden znak (APP2-23)")
    func columnsInCharacters() {
        let text = "a\n-- 😀 x := 1;\nb"
        let ns = text as NSString
        // Kolumna 6 (Oracle) wskazuje „x”: przed nim „-- 😀 ” = 5 znaków, 6 jednostek UTF-16.
        #expect(ProgramCompiler.offset(line: 2, column: 6, in: text) == ns.range(of: "x").location)
        #expect(ProgramCompiler.offset(line: 2, column: 99, in: text) == ns.range(of: ";").location + 1)
        #expect(TextEditing.characterCount(ns, range: NSRange(location: 2, length: ns.range(of: "x").location - 2)) == 5)
        #expect(TextEditing.characterCount(ns, range: NSRange(location: 0, length: ns.length)) == ns.length - 1)
        #expect(TextEditing.characterCount(ns, range: NSRange(location: 0, length: 0)) == 0)
    }

    @Test("JAVA SOURCE z ALL_SOURCE (sam kod Javy): nagłówek CREATE … JAVA SOURCE NAMED, jednostka rozpoznana, właściciel (R6-10)")
    func javaSourceHeader() {
        let java = "public class Hello {\n  public static String hi() { return \"hi\"; }\n}"
        let ddl = MetadataProvider.javaSourceDDL(name: "com/acme/Hello", source: java)
        #expect(ddl == "CREATE OR REPLACE AND COMPILE JAVA SOURCE NAMED \"com/acme/Hello\" AS\n" + java)
        let u = ProgramCompiler.units(in: ddl + "\n/\n")
        #expect(u.map(\.type) == [.javaSource] && u.first?.name == "com/acme/Hello" && u.first?.owner == nil)
        let owned = ProgramCompiler.withOwner(ddl, owner: "HR")
        #expect(owned.hasPrefix("CREATE OR REPLACE AND COMPILE JAVA SOURCE NAMED HR.\"com/acme/Hello\" AS\n"))
        #expect(ProgramCompiler.units(in: owned + "\n/\n").first?.owner == "HR")
    }
}
