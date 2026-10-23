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
}
