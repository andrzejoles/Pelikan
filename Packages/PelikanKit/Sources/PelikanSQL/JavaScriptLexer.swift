import Foundation

/// Podświetlanie JavaScriptu w modułach MLE (PD-PROG-014): proste tokeny bez analizy składni — słowa kluczowe,
/// napisy `'…'`, `"…"`, `` `…` `` (z `${…}` jako częścią napisu), komentarze `//` i `/* */`, liczby. Wyrażenia
/// regularne nie są rozpoznawane (wystarczy do kolorów; kompilację robi baza).
public enum JavaScriptLexer {
    static let keywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do",
        "else", "export", "extends", "false", "finally", "for", "from", "function", "if", "import", "in", "instanceof",
        "let", "new", "null", "of", "return", "static", "super", "switch", "this", "throw", "true", "try", "typeof",
        "undefined", "var", "void", "while", "with", "yield",
    ]

    /// Tokeny (tylko te z kolorem: słowa kluczowe, napisy, komentarze, liczby) w zakresie `range` tekstu UTF-16.
    public static func tokens(_ text: [UInt16], range: Range<Int>) -> [Token] {
        var out: [Token] = []
        var i = range.lowerBound
        let end = min(range.upperBound, text.count)
        func at(_ k: Int) -> UInt16 { k < end ? text[k] : 0 }
        func isIdentStart(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127 }
        func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
        while i < end {
            let c = text[i]
            if c == 47, at(i + 1) == 47 {                                   // //
                let s = i
                while i < end, text[i] != 10 { i += 1 }
                out.append(Token(kind: .lineComment, start: s, length: i - s))
            } else if c == 47, at(i + 1) == 42 {                            // /* */
                let s = i
                i += 2
                while i < end, !(text[i] == 42 && at(i + 1) == 47) { i += 1 }
                i = min(i + 2, end)
                out.append(Token(kind: .blockComment, start: s, length: i - s))
            } else if c == 39 || c == 34 || c == 96 {                       // ' " `
                let s = i
                i += 1
                while i < end, text[i] != c {
                    if text[i] == 92 { i += 1 }                             // \ ucieczka
                    else if text[i] == 10, c != 96 { break }                // napis w linii (poza `…`)
                    i += 1
                }
                i = min(i + 1, end)
                out.append(Token(kind: .string, start: s, length: i - s))
            } else if isDigit(c) || (c == 46 && isDigit(at(i + 1))) {
                let s = i
                while i < end, isDigit(text[i]) || text[i] == 46 || text[i] == 95 || isIdentStart(text[i]) { i += 1 }
                out.append(Token(kind: .number, start: s, length: i - s))
            } else if isIdentStart(c) {
                let s = i
                while i < end, isIdentStart(text[i]) || isDigit(text[i]) { i += 1 }
                let word = String(decoding: text[s..<i], as: UTF16.self)
                if keywords.contains(word) { out.append(Token(kind: .keyword, start: s, length: i - s)) }
            } else {
                i += 1
            }
        }
        return out
    }

    /// Zakresy ciała modułów MLE (`CREATE … MLE MODULE … LANGUAGE JAVASCRIPT AS` do linii `/` albo końca tekstu).
    public static func mleBodies(_ text: [UInt16]) -> [Range<Int>] {
        // Szybki filtr bez alokacji (podświetlanie po każdej zmianie): bez „mle” w tekście nie ma modułu.
        var found = false
        var k = 0
        while k + 2 < text.count {
            if text[k] | 0x20 == 109, text[k + 1] | 0x20 == 108, text[k + 2] | 0x20 == 101 { found = true; break }
            k += 1
        }
        guard found else { return [] }
        let s = String(decoding: text, as: UTF16.self)
        let ns = s as NSString
        guard let re = try? NSRegularExpression(pattern: #"(?is)\bmle\s+module\b.*?\blanguage\s+javascript\b(?:\s+version\s+\S+)?\s+(?:using\s+.*?\s+)?as\b"#) else { return [] }
        var out: [Range<Int>] = []
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let start = m.range.location + m.range.length
            // Koniec: linia zawierająca tylko `/`.
            var end = ns.length
            if let slash = try? NSRegularExpression(pattern: #"(?m)^\s*/\s*$"#),
               let e = slash.firstMatch(in: s, range: NSRange(location: start, length: ns.length - start)) { end = e.range.location }
            if start < end { out.append(start..<end) }
        }
        return out
    }
}
