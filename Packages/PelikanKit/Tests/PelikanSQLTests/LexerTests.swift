import PelikanSQL
import Testing

@Suite("Lekser SQL/PL/SQL")
struct LexerTests {
    func kinds(_ s: String) -> [(TokenKind, String)] {
        let l = Lexer(s)
        return l.tokenize().filter { $0.kind != .whitespace }.map { ($0.kind, l.string($0)) }
    }

    @Test("Słowa kluczowe, identyfikatory, liczby, operatory")
    func basics() {
        let t = kinds("SELECT e.ename, 1.5e3, .5, 10f FROM emp e WHERE x >= :p AND y := 1")
        #expect(t.map(\.0) == [.keyword, .identifier, .dot, .identifier, .comma, .number, .comma, .number, .comma, .number,
                               .keyword, .identifier, .identifier, .keyword, .identifier, .operator, .bindVariable, .keyword,
                               .identifier, .operator, .number])
        #expect(t[16].1 == ":p")
    }

    @Test("Literały: '' w środku, N'…', q'[…]', nq'{…}'")
    func strings() {
        let t = kinds("'it''s' N'zażółć' q'[a ' b]' nq'{x}' Q'!y!'")
        #expect(t.allSatisfy { $0.0 == .string })
        #expect(t.map(\.1) == ["'it''s'", "N'zażółć'", "q'[a ' b]'", "nq'{x}'", "Q'!y!'"])
    }

    @Test("Komentarze i wskazówki optymalizatora")
    func comments() {
        let t = kinds("SELECT /*+ FULL(e) */ 1 -- koniec\n/* blok\n wieloliniowy */ FROM dual")
        #expect(t.map(\.0) == [.keyword, .hint, .number, .lineComment, .newline, .blockComment, .keyword, .identifier])
    }

    @Test("Identyfikatory w cudzysłowie i z $ # _ oraz polskimi literami")
    func identifiers() {
        let t = kinds("\"Moja Tabela\" v$session x#y_z zażółć")
        #expect(t.map(\.0) == [.quotedIdentifier, .identifier, .identifier, .identifier])
    }

    @Test("Zmienne podstawiania & i &&, z kropką kończącą nazwę")
    func substitution() {
        let t = kinds("SELECT &kol, &&tab..x, a & b FROM &&tab.")
        #expect(t.filter { $0.0 == .substitution }.map(\.1) == ["&kol", "&&tab.", "&&tab."])
    }

    @Test("Parametry JasperReports $P{}, $P!{}, $X{}")
    func jasper() {
        let t = kinds("WHERE a = $P{Id} AND $X{IN, dept, Depts} ORDER BY $P!{SortCol} AND v$x = 1")
        #expect(t.filter { $0.0 == .jasperParameter }.map(\.1) == ["$P{Id}", "$X{IN, dept, Depts}", "$P!{SortCol}"])
        #expect(t.contains { $0.0 == .identifier && $0.1 == "v$x" })
    }

    @Test("Przyrostowo: stan niedomkniętego komentarza i literału przechodzi do następnej linii")
    func incremental() {
        let l = Lexer("a /* x\ny */ b 'q\nr' c")
        let lines = [0..<7, 7..<17, 17..<21]
        var state = LexState.normal
        var states: [LexState] = []
        for r in lines {
            state = l.scan(range: r, state: state) { _ in }
            states.append(state)
        }
        #expect(states == [.blockComment(hint: false), .string(quote: nil), .normal])
    }

    @Test("Niedomknięte konstrukcje nie wywracają leksera")
    func tolerant() {
        for s in ["'abc", "q'[abc", "/* abc", "\"abc", ":", "&", "$P{", "$X{IN", "1e", "1..10", "\u{1F600} x"] {
            let t = Lexer(s).tokenize()
            #expect(t.last.map { $0.end } == s.utf16.count, "\(s)")
        }
    }

    @Test("Zakres 1..10 to dwie liczby i operator")
    func range() {
        #expect(kinds("1..10").map(\.0) == [.number, .operator, .number])
    }
}
