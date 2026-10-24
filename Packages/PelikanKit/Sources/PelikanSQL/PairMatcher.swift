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

    /// Wystąpienia identyfikatora pod kursorem albo zaznaczonego słowa (PD-EDIT-018): ta sama nazwa bez rozróżniania
    /// wielkości liter (nazwa w cudzysłowie — dokładnie), poza literałami i komentarzami; słowa kluczowe pomijane.
    /// Pusta lista, gdy wystąpienie jest tylko jedno.
    public static func occurrences(_ text: String, selection: Range<Int>) -> [Range<Int>] {
        let lexer = Lexer(text)
        let toks = lexer.tokenize().filter { $0.kind == .identifier || $0.kind == .quotedIdentifier }
        let target: Token?
        if selection.isEmpty {
            target = toks.first { $0.start <= selection.lowerBound && selection.lowerBound <= $0.end }
        } else {
            target = toks.first { $0.start == selection.lowerBound && $0.end == selection.upperBound }
        }
        guard let t = target else { return [] }
        let key = t.kind == .quotedIdentifier ? lexer.string(t) : lexer.upper(t)
        let hits = toks.filter { ($0.kind == .quotedIdentifier ? lexer.string($0) : lexer.upper($0)) == key }.map { $0.start..<$0.end }
        return hits.count > 1 ? hits : []
    }

    /// INSERT INTO t (k1, k2) VALUES (w1, w2): kursor w kolumnie albo wartości — zakresy obu elementów pary
    /// (PD-EDIT-018). Pozycje liczone po przecinkach najwyższego poziomu nawiasów.
    public static func insertValuesPair(_ text: String, offset: Int) -> [Range<Int>] {
        let lexer = Lexer(text)
        let toks = lexer.tokenize().filter { !$0.isTrivia && $0.kind != .hint }
        // Elementy listy w nawiasie zaczynającym się od indeksu `open`: zakresy i indeks za nawiasem zamykającym.
        func items(from open: Int) -> (items: [Range<Int>], next: Int)? {
            guard open < toks.count, toks[open].kind == .leftParen else { return nil }
            var depth = 0, out: [Range<Int>] = [], first: Int?, last = 0
            var i = open
            while i < toks.count {
                let k = toks[i].kind
                if k == .leftParen { depth += 1; if depth == 1 { i += 1; continue } }
                if k == .rightParen {
                    depth -= 1
                    if depth == 0 { if let f = first { out.append(f..<last) }; return (out, i + 1) }
                }
                if depth == 1, k == .comma {
                    if let f = first { out.append(f..<last) }
                    first = nil
                } else if depth >= 1 {
                    if first == nil { first = toks[i].start }
                    last = toks[i].end
                }
                if k == .semicolon { return nil }
                i += 1
            }
            return nil
        }
        var i = 0
        while i < toks.count {
            defer { i += 1 }
            guard lexer.upper(toks[i]) == "INSERT", i + 1 < toks.count, lexer.upper(toks[i + 1]) == "INTO" else { continue }
            // Nazwa tabeli (z kropkami) i opcjonalny alias, potem lista kolumn.
            var j = i + 2
            while j < toks.count, toks[j].kind != .leftParen, toks[j].kind != .semicolon, lexer.upper(toks[j]) != "VALUES",
                  lexer.upper(toks[j]) != "SELECT" { j += 1 }
            guard let cols = items(from: j), cols.next < toks.count, lexer.upper(toks[cols.next]) == "VALUES",
                  let vals = items(from: cols.next + 1), cols.items.count == vals.items.count else { continue }
            for (c, v) in zip(cols.items, vals.items) where c.contains(offset) || c.upperBound == offset || v.contains(offset) || v.upperBound == offset {
                return [c, v]
            }
        }
        return []
    }

    /// Polecenia transakcyjne COMMIT / ROLLBACK / SAVEPOINT (PD-PROG-015): zakres od słowa do końca polecenia (bez
    /// średnika). Tylko na początku polecenia — `ON COMMIT` w DDL i `ROLLBACK SEGMENT` się nie liczą.
    public static func transactionStatements(_ text: String) -> [Range<Int>] {
        let lexer = Lexer(text)
        let toks = lexer.tokenize().filter { !$0.isTrivia && $0.kind != .hint }
        let starts: Set<String> = ["BEGIN", "THEN", "ELSE", "LOOP", "DECLARE", "IS", "AS"]
        var out: [Range<Int>] = []
        for (i, t) in toks.enumerated() where t.kind == .keyword || t.kind == .identifier {
            let w = lexer.upper(t)
            guard ["COMMIT", "ROLLBACK", "SAVEPOINT"].contains(w) else { continue }
            if i > 0 {
                let p = toks[i - 1]
                guard p.kind == .semicolon || p.kind == .slash || starts.contains(lexer.upper(p)) else { continue }
            }
            if i + 1 < toks.count, lexer.upper(toks[i + 1]) == "SEGMENT" { continue }
            var end = t.end
            var j = i + 1
            while j < toks.count, toks[j].kind != .semicolon, toks[j].kind != .slash { end = toks[j].end; j += 1 }
            out.append(t.start..<end)
        }
        return out
    }

    /// Zakres „END …” na końcu zakresu (END, END IF, END LOOP, END CASE, END nazwa).
    static func endWord(_ r: Range<Int>, in ns: NSString) -> Range<Int> {
        let tail = ns.substring(with: NSRange(location: r.lowerBound, length: r.count))
        guard let endRange = tail.range(of: "end", options: [.caseInsensitive, .backwards]) else { return r.upperBound..<r.upperBound }
        let start = r.lowerBound + (tail[..<endRange.lowerBound] as Substring).utf16.count
        return start..<r.upperBound
    }
}
