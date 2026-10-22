import PelikanSQL
import Testing

@Suite("Leksowanie przyrostowe")
struct IncrementalLexerTests {
    static let sample = """
    create or replace package body p as
      /* komentarz
         blokowy */
      procedure a is
        s varchar2(100) := 'tekst; z ''apostrofem''';
      begin
        null; -- koniec
        s := q'[nawias ] ' w środku]';
      end;
    end;
    /
    select :b, &x from dual;
    """

    /// Stan po przyrostowej zmianie ma być taki sam jak po pełnym leksowaniu nowego tekstu.
    func check(_ text: [UInt16], _ inc: IncrementalLexer, file: String = #filePath, line: Int = #line) {
        let full = IncrementalLexer()
        full.lexAll(text, onLine: { _ in }, onToken: { _ in })
        #expect(inc.lineStarts == full.lineStarts)
        for i in full.lineStarts.indices { #expect(inc.state(atLine: i) == full.state(atLine: i), "linia \(i)") }
    }

    func apply(_ text: inout [UInt16], _ inc: IncrementalLexer, replace range: Range<Int>, with s: String) -> Range<Int> {
        let new = Array(s.utf16)
        text.replaceSubrange(range, with: new)
        return inc.relex(text, editedRange: range.lowerBound..<(range.lowerBound + new.count), delta: new.count - range.count,
                         onLine: { _ in }, onToken: { _ in })
    }

    @Test("Wpisanie znaku w środku linii przeleksowuje tylko tę linię")
    func singleLine() {
        var text = Array(Self.sample.utf16)
        let inc = IncrementalLexer()
        inc.lexAll(text, onLine: { _ in }, onToken: { _ in })
        let at = inc.lineStarts[6] + 4
        let relexed = apply(&text, inc, replace: at..<at, with: "x")
        #expect(relexed == inc.lineStarts[6]..<inc.lineStarts[7])
        check(text, inc)
    }

    @Test("Otwarcie komentarza blokowego zmienia stan kolejnych linii; zamknięcie przywraca")
    func blockComment() {
        var text = Array(Self.sample.utf16)
        let inc = IncrementalLexer()
        inc.lexAll(text, onLine: { _ in }, onToken: { _ in })
        let at = inc.lineStarts[5]
        _ = apply(&text, inc, replace: at..<at, with: "/*")
        check(text, inc)
        #expect(inc.state(atLine: 8) != .normal)
        _ = apply(&text, inc, replace: at..<(at + 2), with: "")
        check(text, inc)
    }

    @Test("Losowe wstawienia i usunięcia (w tym znaków nowej linii) — zgodność z pełnym leksowaniem")
    func randomEdits() {
        var text = Array(Self.sample.utf16)
        let inc = IncrementalLexer()
        inc.lexAll(text, onLine: { _ in }, onToken: { _ in })
        var rng = SplitMix(seed: 42)
        let pieces = ["\n", "'", "/*", "*/", "--", "x", " ", ";\n/\n", "q'[", "]'", "\"", "\n\n", "&", ":"]
        for _ in 0..<400 {
            let a = Int(rng.next() % UInt64(text.count + 1))
            let len = min(Int(rng.next() % 4), text.count - a)
            let s = rng.next() % 3 == 0 ? "" : pieces[Int(rng.next() % UInt64(pieces.count))]
            _ = apply(&text, inc, replace: a..<(a + len), with: s)
        }
        check(text, inc)
    }
}

/// Deterministyczny generator dla testów.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
