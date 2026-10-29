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
        // Nazwa — pierwsze słowo po komentarzu (jak w tekście), szczegóły z liniami i wcięciami; zakres z komentarzem i „;”.
        #expect(first.name == "select" && first.detail == "empno, ename\n  from emp")
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
        #expect(n.count == 1 && n[0].detail.hasSuffix("…") && (n[0].detail as NSString).length <= PLSQLOutline.statementDetailLimit + 1)
        #expect((n[0].detail as NSString).length > 900)
        #expect(PLSQLOutline.parseScript("").isEmpty)
        #expect(PLSQLOutline.parseScript("-- tylko komentarz\n/* i blok */\n").isEmpty)
        // Pakiet bez „/” na końcu tekstu — jak w `parse`.
        let pkg = "create package a is procedure x; end;\n"
        #expect(PLSQLOutline.parseScript(pkg).map(\.kind) == PLSQLOutline.parse(pkg).map(\.kind))
    }

    @Test("komentarz dłuższy niż 600 znaków przed poleceniem i w środku — polecenie zostaje, komentarz nie trafia do szczegółów")
    func longComment() {
        let comment = "/* " + String(repeating: "opis ", count: 200) + "*/\n"
        let text = comment + "select a, -- kolumna a\n b /* i b */ from t;\nselect 2 from dual;\n"
        let nodes = PLSQLOutline.parseScript(text)
        #expect(nodes.map(\.name) == ["select", "select"])
        #expect(nodes[0].nameOffset == (comment as NSString).length)
        #expect(nodes[0].detail == "a,\n b from t")
        #expect(nodes[1].detail == "2 from dual")
    }

    @Test("niedokończony blok albo błąd składni nie ukrywa reszty skryptu")
    func brokenBlock() {
        let text = "begin\n  if x then\n    null;\n/\nselect 1 from dual;\ncreate procedure p is\nbegin\n/\nupdate t set a = 1;\n"
        let nodes = PLSQLOutline.parseScript(text)
        #expect(nodes.map(\.kind) == [.block, .statement, .procedure, .statement])
        let ns = text as NSString
        // Zakres jednostki nie wychodzi poza jej polecenie (przed „/”).
        #expect(nodes[0].range.upperBound <= ns.range(of: "/").location)
        #expect(nodes[2].range.upperBound <= ns.range(of: "/", options: .backwards).location)
    }

    @Test("literały q'[ ; ]' i z „;”/„/” nie dzielą polecenia")
    func literals() {
        let text = "select q'[ a ; b / c ]' from dual;\nselect 'x;/y', \"Kol;\" from dual;\nbegin\n  v := q'{ ; / }';\nend;\n/\n"
        let nodes = PLSQLOutline.parseScript(text)
        #expect(nodes.map(\.kind) == [.statement, .statement, .block])
        #expect(nodes[0].detail == "q'[ a ; b / c ]' from dual")
        #expect(nodes[1].detail == "'x;/y', \"Kol;\" from dual")
    }

    @Test("polskie znaki i emoji: pozycja nazwy i długość zaznaczenia w UTF-16")
    func unicodeNames() {
        let text = "-- zażółć gęślą jaźń 😀\nSELECT 'ą😀' FROM dual;\ncreate or replace procedure \"Żółw😀\" is\nbegin\n  null;\nend;\n/\n"
        let ns = text as NSString
        let nodes = PLSQLOutline.parseScript(text)
        #expect(nodes.map(\.kind) == [.statement, .procedure])
        for n in nodes {
            // Klik w panelu zaznacza nameOffset..<nameOffset+długość nazwy (UTF-16) — w tekście musi być tam nazwa.
            let shown = ns.substring(with: NSRange(location: n.nameOffset, length: (n.name as NSString).length))
            #expect(shown == n.name || "\"" + n.name + "\"" == ns.substring(with: NSRange(location: n.nameOffset, length: (n.name as NSString).length + 2)))
        }
        #expect(nodes[0].name == "SELECT" && nodes[0].detail == "'ą😀' FROM dual")
        #expect(nodes[1].name == "Żółw😀")
    }

    @Test("ponad limit poleceń SQL — tylko jednostki i bloki, z liczbą pominiętych")
    func statementLimit() {
        let text = String(repeating: "select 1 from dual;\n", count: 12) + "begin\n  null;\nend;\n/\n"
        let full = PLSQLOutline.parseScriptOutline(text, statementLimit: 12)
        #expect(full.nodes.count == 13 && full.omittedStatements == 0)
        let cut = PLSQLOutline.parseScriptOutline(text, statementLimit: 10)
        #expect(cut.nodes.map(\.kind) == [.block] && cut.omittedStatements == 12)
        var calls = 0
        let stopped = PLSQLOutline.parseScriptOutline(text) { calls += 1; return true }
        #expect(stopped.nodes.isEmpty && calls == 1)
    }
}
