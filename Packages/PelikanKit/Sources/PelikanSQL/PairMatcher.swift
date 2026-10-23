import Foundation

/// Pary do podświetlenia przy kursorze (UG 23.12, NF14): nawiasy oraz BEGIN / IF / LOOP / CASE ↔ END
/// (poza literałami i komentarzami).
public enum PairMatcher {
    /// Zakresy (UTF-16) obu elementów pary obok kursora albo pusta lista.
    public static func pairs(_ text: String, offset: Int) -> [Range<Int>] {
        let toks = Lexer(text).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment, .hint].contains($0.kind) }
        // Nawias tuż przed albo tuż za kursorem.
        if let i = toks.firstIndex(where: { ($0.kind == .leftParen || $0.kind == .rightParen) && ($0.start == offset || $0.start + $0.length == offset) }) {
            let open = toks[i].kind == .leftParen
            var depth = 0
            var j = i
            while j >= 0 && j < toks.count {
                if toks[j].kind == .leftParen { depth += open ? 1 : -1 }
                if toks[j].kind == .rightParen { depth += open ? -1 : 1 }
                if depth == 0 { return [toks[i].start..<(toks[i].start + 1), toks[j].start..<(toks[j].start + 1)] }
                j += open ? 1 : -1
            }
            return []
        }
        // Słowo kluczowe struktury pod kursorem: zakres zwijania zaczynający się albo kończący na nim.
        let ns = text as NSString
        guard let w = toks.first(where: { $0.kind == .keyword && $0.start <= offset && offset <= $0.start + $0.length }) else { return [] }
        let word = ns.substring(with: NSRange(location: w.start, length: w.length)).uppercased()
        guard ["BEGIN", "IF", "LOOP", "CASE", "END"].contains(word) else { return [] }
        for r in PLSQLOutline.foldingRanges(text) {
            let startWord = r.lowerBound..<(r.lowerBound + w.length)
            if r.lowerBound == w.start {
                return [startWord, endWord(r, in: ns)]
            }
            let e = endWord(r, in: ns)
            if e.lowerBound <= w.start, w.start < r.upperBound, word == "END" || ["IF", "LOOP", "CASE"].contains(word) {
                let startLen = ns.substring(from: r.lowerBound).prefix { $0.isLetter }.count
                return [r.lowerBound..<(r.lowerBound + startLen), e]
            }
        }
        return []
    }

    /// Zakres „END …” na końcu zakresu (END, END IF, END LOOP, END CASE, END nazwa).
    static func endWord(_ r: Range<Int>, in ns: NSString) -> Range<Int> {
        let tail = ns.substring(with: NSRange(location: r.lowerBound, length: r.count))
        guard let endRange = tail.range(of: "end", options: [.caseInsensitive, .backwards]) else { return r.upperBound..<r.upperBound }
        let start = r.lowerBound + (tail[..<endRange.lowerBound] as Substring).utf16.count
        return start..<r.upperBound
    }
}
