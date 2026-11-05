/// Kolorowanie Pro*C (D227): C z preprocesorem, a wstawki `EXEC SQL … ;`, `EXEC ORACLE … ;`, `EXEC TOOLS … ;`
/// i bloki `EXEC SQL EXECUTE … END-EXEC;` leksowane jak SQL i PL/SQL (zmienne hosta `:x` jak zmienne wiązane).
/// Bez analizy składni — wystarczy do kolorów; kompiluje prekompilator proc.
public enum ProCLexer {
    public struct Span: Sendable, Hashable {
        public var start: Int
        public var length: Int
        public var style: SyntaxStyle
    }

    /// Rozszerzenia plików kolorowanych jak Pro*C.
    public static let fileExtensions: Set<String> = ["pc", "pcc", "c", "h"]

    static let keywords: Set<String> = [
        "auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern", "for", "goto", "if",
        "inline", "register", "restrict", "return", "sizeof", "static", "struct", "switch", "typedef", "union",
        "volatile", "while", "true", "false", "NULL",
    ]
    static let types: Set<String> = [
        "void", "char", "short", "int", "long", "float", "double", "signed", "unsigned", "_Bool", "bool", "size_t",
        "ssize_t", "FILE", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t",
        "VARCHAR", "varchar", "sql_context", "sql_cursor", "OCIClobLocator", "OCIBlobLocator", "OCIDate", "OCINumber",
    ]
    static let execTargets: Set<String> = ["SQL", "ORACLE", "TOOLS", "IAF"]

    public static func spans(_ text: [UInt16]) -> [Span] {
        var out: [Span] = []
        let end = text.count
        var i = 0
        var lineStart = true
        func at(_ k: Int) -> UInt16 { k < end ? text[k] : 0 }
        func isIdentStart(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 }
        func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
        func word(_ s: Int, _ e: Int) -> String { String(decoding: text[s..<e], as: UTF16.self) }
        func add(_ s: Int, _ e: Int, _ st: SyntaxStyle) { if e > s { out.append(Span(start: s, length: e - s, style: st)) } }
        func skipBlank(_ k: Int) -> Int { var k = k; while k < end, text[k] == 32 || text[k] == 9 || text[k] == 10 || text[k] == 13 { k += 1 }; return k }
        func identEnd(_ k: Int) -> Int { var k = k; while k < end, isIdentStart(text[k]) || isDigit(text[k]) { k += 1 }; return k }

        while i < end {
            let c = text[i]
            if c == 10 { lineStart = true; i += 1; continue }
            if c == 32 || c == 9 || c == 13 { i += 1; continue }
            let wasLineStart = lineStart
            lineStart = false
            if c == 35, wasLineStart {                                        // #include, #define … (z \ na końcu linii)
                let s = i
                while i < end, !(text[i] == 10 && at(i - 1) != 92) { i += 1 }
                add(s, i, .directive)
            } else if c == 47, at(i + 1) == 47 {                              // //
                let s = i
                while i < end, text[i] != 10 { i += 1 }
                add(s, i, .comment)
            } else if c == 47, at(i + 1) == 42 {                              // /* */
                let s = i
                i += 2
                while i < end, !(text[i] == 42 && at(i + 1) == 47) { i += 1 }
                i = min(i + 2, end)
                add(s, i, .comment)
            } else if c == 34 || c == 39 {                                    // "…" '…'
                let s = i
                i += 1
                while i < end, text[i] != c, text[i] != 10 { i += text[i] == 92 ? 2 : 1 }
                i = min(i + 1, end)
                add(s, i, .string)
            } else if isDigit(c) || (c == 46 && isDigit(at(i + 1))) {
                let s = i
                while i < end, isDigit(text[i]) || text[i] == 46 || isIdentStart(text[i]) { i += 1 }
                add(s, i, .number)
            } else if isIdentStart(c) {
                let s = i
                i = identEnd(i)
                let w = word(s, i)
                if w.uppercased() == "EXEC" {
                    let t0 = skipBlank(i)
                    let t1 = identEnd(t0)
                    if t1 > t0, execTargets.contains(word(t0, t1).uppercased()) {
                        let stop = execEnd(text, from: t1)
                        add(s, i, .keyword)
                        add(t0, t1, .keyword)
                        Lexer(utf16: text).scan(range: t1..<stop.body, state: .normal) { t in
                            if let st = SyntaxClassifier.style(t, in: text) { add(t.start, t.end, st) }
                        }
                        if stop.block, stop.body + 8 <= stop.end {
                            add(stop.body, stop.body + 8, .keyword)              // END-EXEC
                            add(stop.body + 8, stop.end, .operator)
                        } else {
                            add(stop.body, stop.end, .operator)
                        }
                        i = stop.end
                        continue
                    }
                }
                if types.contains(w) { add(s, i, .dataType) }
                else if keywords.contains(w) { add(s, i, .keyword) }
                else if at(skipBlank(i)) == 40 { add(s, i, .function) }
            } else if "+-*/%=<>!&|^~?:;,.()[]{}".utf16.contains(c) {
                add(i, i + 1, .operator)
                i += 1
            } else {
                i += 1
            }
        }
        return out
    }

    /// Koniec wstawki EXEC: `body` — koniec treści SQL (średnik albo `END-EXEC`), `end` — za średnikiem kończącym,
    /// `block` — blok PL/SQL zakończony `END-EXEC`. Blok `EXEC SQL EXECUTE` (bez IMMEDIATE) kończy się na `END-EXEC;`, pozostałe na
    /// pierwszym średniku poza napisami i komentarzami.
    static func execEnd(_ text: [UInt16], from start: Int) -> (body: Int, end: Int, block: Bool) {
        let end = text.count
        func at(_ k: Int) -> UInt16 { k < end ? text[k] : 0 }
        func up(_ c: UInt16) -> UInt16 { c >= 97 && c <= 122 ? c - 32 : c }
        func matches(_ k: Int, _ s: String) -> Bool {
            var k = k
            for u in s.utf16 { guard k < end, up(text[k]) == u else { return false }; k += 1 }
            return true
        }
        var k = start
        while k < end, text[k] == 32 || text[k] == 9 || text[k] == 10 || text[k] == 13 { k += 1 }
        var block = false
        if matches(k, "EXECUTE") {
            var j = k + 7
            while j < end, text[j] == 32 || text[j] == 9 || text[j] == 10 || text[j] == 13 { j += 1 }
            block = !matches(j, "IMMEDIATE")
        }
        var i = start
        while i < end {
            let c = text[i]
            if c == 39 {
                i += 1
                while i < end, text[i] != 39 { i += 1 }
                i += 1
            } else if c == 45, at(i + 1) == 45 {
                while i < end, text[i] != 10 { i += 1 }
            } else if c == 47, at(i + 1) == 42 {
                i += 2
                while i < end, !(text[i] == 42 && at(i + 1) == 47) { i += 1 }
                i += 2
            } else if block, up(c) == 69, matches(i, "END-EXEC") {
                var j = i + 8
                while j < end, text[j] == 32 || text[j] == 9 { j += 1 }
                return (i, at(j) == 59 ? j + 1 : i + 8, true)
            } else if !block, c == 59 {
                return (i, i + 1, false)
            } else {
                i += 1
            }
        }
        return (end, end, block)
    }
}
