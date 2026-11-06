import PelikanSQL
import Testing

@Suite("Kategorie kolorowania i Pro*C (D227)")
struct SyntaxClassifierTests {
    func styles(_ sql: String) -> [String: SyntaxStyle] {
        let text = Array(sql.utf16)
        var out: [String: SyntaxStyle] = [:]
        for t in Lexer(utf16: text).tokenize() {
            if let s = SyntaxClassifier.style(t, in: text) { out[String(decoding: text[t.start..<t.end], as: UTF16.self)] = s }
        }
        return out
    }

    @Test("SQL: typy danych, funkcje przed „(”, pakiety przed „.”, słowa kluczowe, zmienne")
    func sql() {
        let s = styles("declare v varchar2(30) := nvl(:x, 'a'); n number; begin dbms_output.put_line(count); select count(*) into n from dual; end;")
        #expect(s["varchar2"] == .dataType && s["number"] == .dataType)
        #expect(s["nvl"] == .function && s["dbms_output"] == .package)
        #expect(s["count"] == .function)          // count(*) — funkcja; „count” bez nawiasu nie jest kolorowane jako funkcja
        #expect(s["declare"] == .keyword && s["select"] == .keyword && s[":x"] == .variable && s["'a'"] == .string)
        #expect(s["put_line"] == nil && s[";"] == .operator)
    }

    @Test("Pro*C: C, preprocesor, EXEC SQL do średnika, blok EXECUTE do END-EXEC, zmienne hosta")
    func proC() {
        let code = """
        #include <stdio.h>
        /* komentarz */
        int main(void) {
            VARCHAR name[30];
            EXEC SQL SELECT ename INTO :name FROM emp WHERE empno = 7839;
            printf("%s\\n", name.arr); // koniec
            EXEC SQL EXECUTE
              BEGIN dbms_output.put_line('x;y'); END;
            END-EXEC;
            return 0;
        }
        """
        let text = Array(code.utf16)
        var got: [String: SyntaxStyle] = [:]
        for sp in ProCLexer.spans(text) { got[String(decoding: text[sp.start..<(sp.start + sp.length)], as: UTF16.self)] = sp.style }
        #expect(got["#include <stdio.h>"] == .directive && got["/* komentarz */"] == .comment && got["// koniec"] == .comment)
        #expect(got["int"] == .dataType && got["VARCHAR"] == .dataType && got["return"] == .keyword && got["main"] == .function)
        #expect(got["printf"] == .function && got["\"%s\\n\""] == .string && got["0"] == .number)
        #expect(got["EXEC"] == .keyword && got["SELECT"] == .keyword && got[":name"] == .variable && got["7839"] == .number)
        #expect(got["dbms_output"] == .package && got["'x;y'"] == .string && got["END-EXEC"] == .keyword && got["BEGIN"] == .keyword)
        // Po wstawce znów C.
        #expect(got["return"] == .keyword)
        #expect(ProCLexer.fileExtensions.contains("pc"))
        // Dynamiczny SQL (metoda 2/3): EXECUTE s USING …; kończy się średnikiem — dalej znów C.
        let dyn = Array("EXEC SQL PREPARE s FROM :q;\nEXEC SQL EXECUTE s USING :a;\nreturn 1;\n".utf16)
        var d: [String: SyntaxStyle] = [:]
        for sp in ProCLexer.spans(dyn) { d[String(decoding: dyn[sp.start..<(sp.start + sp.length)], as: UTF16.self)] = sp.style }
        #expect(d["return"] == .keyword && d[":a"] == .variable && d["1"] == .number)
        // Nazwa polecenia zaczynająca się od „begin” nie jest blokiem PL/SQL.
        let named = Array("EXEC SQL EXECUTE begin_stmt USING :a;\nreturn 2;\n".utf16)
        var n: [String: SyntaxStyle] = [:]
        for sp in ProCLexer.spans(named) { n[String(decoding: named[sp.start..<(sp.start + sp.length)], as: UTF16.self)] = sp.style }
        #expect(n["return"] == .keyword && n["2"] == .number)
        // Komentarz i etykieta przed BEGIN — nadal blok do END-EXEC.
        let labeled = Array("EXEC SQL EXECUTE\n  -- aktualizacja\n  <<blk>> BEGIN x := 1; y := 2; END;\nEND-EXEC;\nreturn 3;\n".utf16)
        var b: [String: SyntaxStyle] = [:]
        for sp in ProCLexer.spans(labeled) { b[String(decoding: labeled[sp.start..<(sp.start + sp.length)], as: UTF16.self)] = sp.style }
        #expect(b["END-EXEC"] == .keyword && b["y"] == nil && b["return"] == .keyword && b["END"] == .keyword)
        // Klauzula AT przed EXECUTE.
        let at = Array("EXEC SQL AT :db EXECUTE BEGIN x := 1; y := 2; END; END-EXEC;\nreturn 4;\n".utf16)
        var a: [String: SyntaxStyle] = [:]
        for sp in ProCLexer.spans(at) { a[String(decoding: at[sp.start..<(sp.start + sp.length)], as: UTF16.self)] = sp.style }
        #expect(a["END-EXEC"] == .keyword && a["return"] == .keyword && a["4"] == .number)
        // Składowany PL/SQL do END-EXEC.
        let ddl = Array("EXEC SQL CREATE OR REPLACE PROCEDURE p AS BEGIN x := 1; y := 2; END; END-EXEC;\nreturn 5;\n".utf16)
        var c: [String: SyntaxStyle] = [:]
        for sp in ProCLexer.spans(ddl) { c[String(decoding: ddl[sp.start..<(sp.start + sp.length)], as: UTF16.self)] = sp.style }
        #expect(c["END-EXEC"] == .keyword && c["return"] == .keyword && c["5"] == .number && c["y"] == nil)
        // Specyfikacja typu kończy się średnikiem; AT ze zmienną strukturalną.
        let ty = Array("EXEC SQL CREATE TYPE num_tab AS TABLE OF NUMBER;\nreturn 6;\nEXEC SQL AT :ctx.db EXECUTE BEGIN x := 1; y := 2; END; END-EXEC;\nreturn 7;\n".utf16)
        var t: [String: SyntaxStyle] = [:]
        for sp in ProCLexer.spans(ty) { t[String(decoding: ty[sp.start..<(sp.start + sp.length)], as: UTF16.self)] = sp.style }
        #expect(t["6"] == .number && t["7"] == .number && t["END-EXEC"] == .keyword)
    }
}
