import Foundation
import PelikanSQL
import Testing

/// Zarys skryptu okna SQL (D199): polecenia SQL między jednostkami i blokami PL/SQL.
@Suite("Zarys skryptu okna SQL")
struct PLSQLOutlineScriptTests {
    @Test("polecenia SQL, blok i jednostka w kolejności tekstu")
    func mixedScript() {
        let text = """
        -- raport pensji
        select empno, ename
          from emp;
        create table t (id number);
        create or replace procedure p is
        begin
          update emp set sal = sal;
        end;
        /
        declare
          x number;
        begin
          select 1 into x from dual;
        end;
        /
        commit;
        """
        let nodes = PLSQLOutline.parseScript(text)
        #expect(nodes.map(\.kind) == [.statement, .statement, .procedure, .block, .statement])
        let first = nodes[0]
        // Nazwa — pierwsze słowo po komentarzu (jak w tekście), szczegóły w jednej linii; zakres z komentarzem i „;”.
        #expect(first.name == "select" && first.detail == "empno, ename from emp")
        #expect(first.nameOffset == (text as NSString).range(of: "select").location)
        #expect(first.range.lowerBound == 0)
        #expect((text as NSString).substring(with: NSRange(location: first.range.lowerBound, length: first.range.count)).hasSuffix("from emp;"))
        #expect(nodes[1].name == "create" && nodes[1].detail == "table t (id number)")
        #expect(nodes[2].name == "p" && nodes[3].children.contains { $0.name == "x" })
        #expect(nodes[4].name == "commit" && nodes[4].detail.isEmpty)
        // Polecenia wewnątrz jednostek i bloków nie są osobnymi elementami.
        #expect(!nodes.contains { $0.kind == .statement && $0.name.lowercased() == "update" })
    }

    @Test("długie polecenie skrócone, pusty tekst i same komentarze — bez elementów")
    func longAndEmpty() {
        let long = "select " + Array(repeating: "kolumna_o_dlugiej_nazwie", count: 40).joined(separator: ", ") + " from t"
        let n = PLSQLOutline.parseScript(long)
        #expect(n.count == 1 && n[0].detail.hasSuffix("…") && n[0].detail.count <= 161)
        #expect(PLSQLOutline.parseScript("").isEmpty)
        #expect(PLSQLOutline.parseScript("-- tylko komentarz\n/* i blok */\n").isEmpty)
        // Pakiet bez „/” na końcu tekstu — jak w `parse`.
        let pkg = "create package a is procedure x; end;\n"
        #expect(PLSQLOutline.parseScript(pkg).map(\.kind) == PLSQLOutline.parse(pkg).map(\.kind))
    }
}
