import PelikanSQL
import Testing

@Suite("JavaScript w modułach MLE (PD-PROG-014)")
struct JavaScriptLexerTests {
    @Test("Ciało modułu od AS do linii /; słowa kluczowe, napisy, komentarze, liczby; apostrof w komentarzu nie psuje reszty")
    func tokens() {
        let text = """
            create or replace mle module calc language javascript as
            // it's fine
            export function add(a, b) { return a + b * 2.5; }
            const s = `x ${1}`; /* koniec */
            /
            select 1 from dual;
            """
        let u = Array(text.utf16)
        let bodies = JavaScriptLexer.mleBodies(u)
        #expect(bodies.count == 1)
        let body = String(decoding: u[bodies[0]], as: UTF16.self)
        #expect(body.contains("export function") && !body.contains("select"))
        let toks = JavaScriptLexer.tokens(u, range: bodies[0])
        func words(_ k: TokenKind) -> [String] { toks.filter { $0.kind == k }.map { String(decoding: u[$0.start..<$0.end], as: UTF16.self) } }
        #expect(words(.keyword) == ["export", "function", "return", "const"])
        #expect(words(.lineComment) == ["// it's fine"] && words(.blockComment) == ["/* koniec */"])
        #expect(words(.string) == ["`x ${1}`"] && words(.number) == ["2.5"])
        #expect(JavaScriptLexer.mleBodies(Array("begin null; end;".utf16)).isEmpty)
        #expect(JavaScriptLexer.mleBodies(Array("create mle module m language javascript version 1.0 as\nexport const x = 1;".utf16)).count == 1)
    }
}
