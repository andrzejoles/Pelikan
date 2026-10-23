import Foundation

/// Reguły formatera PL/SQL (UG 29.1–29.2) — przechowywane w preferencjach.
public struct BeautifierOptions: Sendable, Codable, Hashable {
    public enum WordCase: String, Sendable, Codable, Hashable, CaseIterable { case unchanged, upper, lower, initCap }
    public enum ListLayout: String, Sendable, Codable, Hashable, CaseIterable {
        /// Element listy SELECT/SET/GROUP BY/ORDER BY w osobnej linii.
        case onePerLine
        /// Elementy w jednej linii, zawijane przy prawym marginesie.
        case fit
    }

    public var indent = 2
    public var useTabs = false
    public var rightMargin = 100
    public var keywordCase: WordCase = .upper
    public var identifierCase: WordCase = .unchanged
    public var listLayout: ListLayout = .onePerLine
    /// Przecinek na początku kolejnej linii listy zamiast na końcu poprzedniej.
    public var commaBefore = false
    /// Zachowanie pojedynczych pustych linii między instrukcjami (więcej pustych linii — jedna).
    public var keepBlankLines = true
    /// Wyrazy o zadanej pisowni (Special Case, np. `DBMS_Output`), niezależnie od reguł wielkości liter.
    public var specialCase: [String] = []
    /// Automatyczne formatowanie (UG 29.4): po wczytaniu z bazy, przed kompilacją, przed zapisem.
    public var afterLoad = false
    public var beforeCompile = false
    public var beforeSave = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ cur: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? cur }
        indent = v(.indent, indent); useTabs = v(.useTabs, useTabs); rightMargin = v(.rightMargin, rightMargin)
        keywordCase = v(.keywordCase, keywordCase); identifierCase = v(.identifierCase, identifierCase)
        listLayout = v(.listLayout, listLayout); commaBefore = v(.commaBefore, commaBefore); keepBlankLines = v(.keepBlankLines, keepBlankLines)
        specialCase = v(.specialCase, specialCase); afterLoad = v(.afterLoad, afterLoad); beforeCompile = v(.beforeCompile, beforeCompile)
        beforeSave = v(.beforeSave, beforeSave)
    }
}

public enum BeautifierError: Error, Equatable {
    /// Wynik różniłby się od źródła czymś więcej niż białymi znakami i wielkością liter — formatowanie przerwane
    /// (pierwszy różniący się token; komunikat dla użytkownika w warstwie aplikacji).
    case unsafe(String)
}

/// Formater PL/SQL (PL/SQL Beautifier, UG 29): przebudowuje układ linii i odstępów, wielkość liter słów kluczowych
/// i identyfikatorów; nigdy nie zmienia tokenów — wynik jest porównywany ze źródłem przed zwróceniem.
public enum Beautifier {
    public static func format(_ text: String, options: BeautifierOptions = BeautifierOptions()) throws -> String {
        var f = Formatter(source: text as NSString, options: options)
        let out = f.run()
        try verify(original: text, formatted: out)
        return out
    }

    /// Formatowanie fragmentu (zaznaczenia): całe linie, wcięcie pierwszej linii zachowane jako bazowe.
    public static func format(_ text: String, range: Range<Int>, options: BeautifierOptions = BeautifierOptions()) throws -> (text: String, range: Range<Int>) {
        let ns = text as NSString
        let lines = ns.lineRange(for: NSRange(location: range.lowerBound, length: max(0, range.count - (range.count > 0 && range.upperBound <= ns.length && range.upperBound > 0 && ns.character(at: range.upperBound - 1) == 0x0A ? 1 : 0))))
        let fragment = ns.substring(with: lines)
        let base = String(fragment.prefix { $0 == " " || $0 == "\t" })
        var formatted = try format(fragment, options: options)
        formatted = formatted.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : base + $0 }.joined(separator: "\n")
        if fragment.hasSuffix("\n"), !formatted.hasSuffix("\n") { formatted += "\n" }
        if !fragment.hasSuffix("\n"), formatted.hasSuffix("\n") { formatted.removeLast() }
        let result = ns.replacingCharacters(in: lines, with: formatted)
        return (result, lines.location..<(lines.location + (formatted as NSString).length))
    }

    /// Porównanie tokenów (bez białych znaków; słowa bez cudzysłowu bez rozróżniania wielkości liter).
    public static func verify(original: String, formatted: String) throws {
        func sig(_ s: String) -> [String] {
            let ns = s as NSString
            return Lexer(s).tokenize().compactMap { t -> String? in
                if t.kind == .whitespace || t.kind == .newline { return nil }
                let x = ns.substring(with: NSRange(location: t.start, length: t.length))
                switch t.kind {
                case .identifier, .keyword: return "w:" + x.uppercased()
                case .lineComment: return "c:" + x.trimmingCharacters(in: .whitespaces)
                default: return "\(t.kind.rawValue):" + x
                }
            }
        }
        let a = sig(original), b = sig(formatted)
        guard a != b else { return }
        let i = (0..<min(a.count, b.count)).first { a[$0] != b[$0] } ?? min(a.count, b.count)
        throw BeautifierError.unsafe(i < a.count ? String(a[i].drop { $0 != ":" }.dropFirst().prefix(30)) : "EOF")
    }
}

struct Formatter {
    struct Tok {
        let kind: TokenKind
        let start: Int
        let end: Int
        let text: String
        let upper: String
        /// Liczba znaków nowej linii przed tokenem w źródle.
        let newlines: Int
        var isWord: Bool { kind == .identifier || kind == .keyword }
    }

    enum FrameKind { case unit, declare, block, exception, ifStmt, loop, caseStmt, sql, paren }
    struct Frame {
        var kind: FrameKind
        /// Poziom wcięcia linii BEGIN/END/ELSE (jednostki wcięcia).
        var level: Int
        /// SQL: kolumna początku instrukcji; nawias: kolumna po „(” przy zawijaniu.
        var column = 0
        /// SQL: bieżąca klauzula (SELECT, FROM, WHERE…).
        var clause = ""
        /// Nawias: zawijanie po przecinkach / podzapytanie.
        var wrap = false
        var subquery = false
        /// SQL: kolumna elementów bieżącej klauzuli (po słowie klauzuli).
        var itemColumn = 0
    }

    let source: NSString
    let options: BeautifierOptions
    var toks: [Tok] = []
    var lines: [String] = []
    var cur = ""
    var curIndentColumns = 0
    var frames: [Frame] = []
    var i = 0
    /// Następny token zaczyna nową linię z tym wcięciem (kolumny).
    var pendingBreak: Int?
    var betweenPending = false
    /// Nagłówek jednostki/podprogramu: IS/AS otwiera deklaracje (poziom).
    var headerLevel: Int?
    var headerKind = ""
    var statementStart = true

    init(source: NSString, options: BeautifierOptions) {
        self.source = source
        self.options = options
        var nl = 0
        var t: [Tok] = []
        for k in Lexer(source as String).tokenize() {
            switch k.kind {
            case .whitespace: continue
            case .newline: nl += 1; continue
            default:
                let s = source.substring(with: NSRange(location: k.start, length: k.length))
                t.append(Tok(kind: k.kind, start: k.start, end: k.start + k.length, text: s, upper: s.uppercased(), newlines: nl))
                nl = 0
            }
        }
        toks = t
    }

    // MARK: Emisja

    var level: Int { frames.last.map(contentLevel) ?? 0 }

    func contentLevel(_ f: Frame) -> Int {
        switch f.kind {
        case .sql, .paren: f.level
        default: f.level + 1
        }
    }

    func pad(_ columns: Int) -> String {
        if options.useTabs, options.indent > 0 {
            return String(repeating: "\t", count: columns / options.indent) + String(repeating: " ", count: columns % options.indent)
        }
        return String(repeating: " ", count: columns)
    }

    var column: Int { curIndentColumns + cur.count }

    mutating func flush() {
        if !cur.isEmpty { lines.append(pad(curIndentColumns) + cur) }
        cur = ""
    }

    mutating func lineBreak(_ indentColumns: Int) {
        flush()
        curIndentColumns = indentColumns
        pendingBreak = nil
    }

    mutating func blankLine() {
        flush()
        if let last = lines.last, !last.isEmpty { lines.append("") }
    }

    mutating func put(_ s: String, space: Bool) {
        if let p = pendingBreak {
            lineBreak(p)
            pendingBreak = nil
        }
        if !cur.isEmpty, space { cur += " " }
        cur += s
    }

    func cased(_ t: Tok) -> String {
        guard t.isWord else { return t.text }
        if let special = options.specialCase.first(where: { $0.uppercased() == t.upper }) { return special }
        let rule = t.kind == .keyword ? options.keywordCase : options.identifierCase
        switch rule {
        case .unchanged: return t.text
        case .upper: return t.upper
        case .lower: return t.text.lowercased()
        case .initCap:
            return t.text.lowercased().split(separator: "_", omittingEmptySubsequences: false)
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "_")
        }
    }

    // MARK: Odstępy

    static let spacedBeforeParen: Set<String> = [
        "IN", "VALUES", "AND", "OR", "NOT", "EXISTS", "AS", "IS", "SELECT", "FROM", "WHERE", "ON", "USING", "INTO", "THEN",
        "ELSE", "RETURN", "WHEN", "CURSOR", "BY", "SET", "UNION", "ALL", "ANY", "SOME", "LIKE", "BETWEEN", "OF", "HAVING",
        "IF", "ELSIF", "WHILE", "TABLE", "JOIN", "CASE", "END", "LOOP", "DEFAULT", "PIVOT", "UNPIVOT", "OVER", "WITH",
        "RECORD", "OBJECT", "INSERT", "VARRAY", "KEY", "CHECK", "REFERENCES", "UNIQUE", "PARTITION", "RANGE", "ROW", "ROWS",
    ]

    func needsSpace(_ prev: Tok?, _ t: Tok) -> Bool {
        guard let p = prev else { return false }
        if [.comma, .semicolon, .rightParen, .dot].contains(t.kind) { return false }
        if p.kind == .leftParen || p.kind == .dot { return false }
        if t.text == "%" || p.text == "%" || t.text == "@" || p.text == "@" { return false }
        if t.text == ".." || p.text == ".." { return false }
        if t.kind == .leftParen {
            if p.kind == .identifier || p.kind == .quotedIdentifier { return false }
            if p.kind == .keyword { return Self.spacedBeforeParen.contains(p.upper) }
            return true
        }
        // Minus/plus jednoargumentowy: po operatorze, nawiasie, przecinku albo słowie kluczowym.
        if let pp = prevPrev(), ["-", "+"].contains(p.text), [.operator, .leftParen, .comma].contains(pp.kind) || (pp.kind == .keyword && Self.spacedBeforeParen.contains(pp.upper)) {
            return false
        }
        return true
    }

    func prevPrev() -> Tok? { i >= 2 ? toks[i - 2] : nil }

    // MARK: Przebieg

    mutating func run() -> String {
        while i < toks.count {
            step()
        }
        flush()
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + ((source as String).hasSuffix("\n") ? "\n" : "")
    }

    func peek(_ o: Int = 1) -> Tok? { i + o < toks.count ? toks[i + o] : nil }
    var prev: Tok? { i > 0 ? toks[i - 1] : nil }
    var parenDepth: Int { frames.filter { $0.kind == .paren }.count }
    var innermostSQL: Frame? { frames.last(where: { $0.kind == .sql }) }
    var inSQLAtTop: Bool { frames.last?.kind == .sql }

    func indentColumns(_ level: Int) -> Int { level * options.indent }

    /// Początek instrukcji w bloku: nowa linia na bieżącym poziomie (z pustą linią, jeśli była w źródle).
    mutating func beginStatementLine(_ t: Tok) {
        let col = pendingBreak ?? indentColumns(level)
        if options.keepBlankLines, t.newlines >= 2, !lines.isEmpty || !cur.isEmpty { blankLine() }
        lineBreak(col)
    }

    mutating func step() {
        let t = toks[i]
        defer { i += 1 }

        // Regiony bez formatowania: kopiowane bez zmian.
        if t.kind == .lineComment, t.upper.replacingOccurrences(of: " ", with: "").hasPrefix("--NOFORMATSTART") {
            if options.keepBlankLines, t.newlines >= 2 { blankLine() }
            flush()
            var j = i
            while j < toks.count, !(toks[j].kind == .lineComment && toks[j].upper.replacingOccurrences(of: " ", with: "").hasPrefix("--NOFORMATEND")) { j += 1 }
            let end = j < toks.count ? toks[j].end : source.length
            let lineStart = source.lineRange(for: NSRange(location: t.start, length: 0)).location
            let raw = source.substring(with: NSRange(location: lineStart, length: end - lineStart))
            lines.append(contentsOf: raw.components(separatedBy: "\n"))
            i = j
            pendingBreak = indentColumns(level)
            statementStart = true
            return
        }

        // Komentarze.
        if t.kind == .lineComment || t.kind == .blockComment {
            let text = t.kind == .lineComment ? t.text.trimmingCharacters(in: .whitespaces) : t.text
            if t.newlines > 0 || cur.isEmpty && pendingBreak != nil {
                if options.keepBlankLines, t.newlines >= 2 { blankLine() }
                let col = pendingBreak ?? (statementStart ? indentColumns(level) : curIndentColumns)
                lineBreak(col)
                pendingBreak = nil
                if t.kind == .blockComment, text.contains("\n") {
                    flush()
                    lines.append(contentsOf: (pad(col) + text).components(separatedBy: "\n"))
                } else {
                    cur = text
                }
                pendingBreak = statementStart ? indentColumns(level) : col
            } else {
                // Komentarz na końcu linii zostaje w niej (bez wykonania zaległego złamania linii).
                cur += (cur.isEmpty ? "" : " ") + text
                if t.kind == .lineComment, pendingBreak == nil { pendingBreak = statementStart ? indentColumns(level) : continuationColumn() }
            }
            return
        }

        if t.kind == .slash, cur.isEmpty || t.newlines > 0 {
            // Koniec jednostki w skrypcie: „/” w osobnej linii.
            lineBreak(0)
            cur = "/"
            flush()
            frames.removeAll()
            headerLevel = nil
            statementStart = true
            pendingBreak = 0
            if let n = peek(), n.newlines >= 2 || true { _ = n }
            return
        }

        let w = t.kind == .keyword || t.kind == .identifier ? t.upper : ""
        let prevUpper = prev?.upper ?? ""

        // MARK: Struktura PL/SQL (poza nawiasami i SQL)
        if !frames.contains(where: { $0.kind == .sql || $0.kind == .paren }) {
            if handlePLSQL(t, w, prevUpper) { return }
        }

        // MARK: SQL
        if t.kind == .leftParen {
            openParen(t)
            return
        }
        if t.kind == .rightParen {
            closeParen(t)
            return
        }
        if t.kind == .semicolon {
            put(";", space: false)
            endStatement()
            return
        }
        if ["SELECT", "WITH", "INSERT", "UPDATE", "DELETE", "MERGE"].contains(w), (statementStart || prev?.kind == .leftParen || ["IS", "AS"].contains(prevUpper) && t.upper == "SELECT"), !(w == "WITH" && !statementStart && prev?.kind != .leftParen) {
            if statementStart { beginStatementLine(t) }
            frames.append(Frame(kind: .sql, level: level, column: pendingBreak ?? column + (cur.isEmpty || prev?.kind == .leftParen ? 0 : 1), clause: w))
            put(cased(t), space: needsSpace(prev, t))
            if w == "SELECT", let n = peek(), ["DISTINCT", "UNIQUE", "ALL"].contains(n.upper) { i += 1; put(cased(n), space: true) }
            statementStart = false
            alignAfterKeyword()
            return
        }
        if inSQLAtTop, let f = frames.last, sqlClause(t, w, f) { return }
        if t.kind == .comma {
            comma()
            return
        }
        if statementStart {
            beginStatementLine(t)
            statementStart = false
        }
        put(cased(t), space: needsSpace(prev, t))
    }

    /// Wyrównanie elementów po słowie klauzuli do kolumny (SELECT␣ = 7 znaków): `FROM   emp`.
    mutating func alignAfterKeyword() {
        guard let f = frames.last, f.kind == .sql else { return }
        // INSERT INTO / MERGE INTO — bez wyrównania przed INTO.
        if peek()?.upper == "INTO", ["INSERT", "MERGE"].contains(toks[i].upper) { return }
        let target = f.column + 7
        frames[frames.count - 1].itemColumn = max(target, column + 1)
        let next = peek()
        if next?.kind == .semicolon || next?.kind == .rightParen || next == nil { return }
        if column < target - 1 { cur += String(repeating: " ", count: target - 1 - column) }
    }

    func continuationColumn() -> Int {
        if let f = frames.last {
            switch f.kind {
            case .sql: return max(f.column + 7, f.itemColumn)
            case .paren: return f.wrap || f.subquery ? f.column : curIndentColumns + options.indent
            default: break
            }
        }
        return indentColumns(level) + options.indent
    }

    static let clauseStarts: [[String]] = [
        ["FROM"], ["WHERE"], ["GROUP", "BY"], ["HAVING"], ["ORDER", "SIBLINGS", "BY"], ["ORDER", "BY"], ["CONNECT", "BY"], ["START", "WITH"],
        ["UNION", "ALL"], ["UNION"], ["INTERSECT"], ["MINUS"], ["EXCEPT"], ["INTO"], ["BULK", "COLLECT", "INTO"], ["VALUES"], ["SET"],
        ["RETURNING"], ["RETURN"], ["LEFT", "OUTER", "JOIN"], ["RIGHT", "OUTER", "JOIN"], ["FULL", "OUTER", "JOIN"], ["LEFT", "JOIN"],
        ["RIGHT", "JOIN"], ["FULL", "JOIN"], ["INNER", "JOIN"], ["CROSS", "JOIN"], ["NATURAL", "JOIN"], ["JOIN"], ["USING"],
        ["WHEN", "MATCHED"], ["WHEN", "NOT", "MATCHED"], ["FETCH"], ["OFFSET"], ["FOR", "UPDATE"], ["WINDOW"], ["LOG", "ERRORS"],
    ]

    /// Słowo rozpoczynające klauzulę w instrukcji SQL na jej głębokości: nowa linia w kolumnie instrukcji.
    mutating func sqlClause(_ t: Tok, _ w: String, _ f: Frame) -> Bool {
        guard t.isWord else { return false }
        if w == "BETWEEN" { betweenPending = true }
        // Główne zapytanie po definicjach WITH: SELECT w nowej linii w kolumnie instrukcji.
        if w == "SELECT", prev?.kind == .rightParen || prev?.kind == .comma && f.clause == "WITH" {
            lineBreak(f.column)
            put(cased(t), space: false)
            frames[frames.count - 1].clause = "SELECT"
            alignAfterKeyword()
            return true
        }
        if ["AND", "OR"].contains(w) {
            if w == "AND", betweenPending { betweenPending = false; return false }
            guard ["WHERE", "HAVING", "ON", "WHEN", "START", "CONNECT"].contains(f.clause) || f.clause.hasSuffix("JOIN") else { return false }
            lineBreak(f.column)
            put(cased(t), space: false)
            alignAfterKeyword()
            return true
        }
        if w == "ON", f.clause.hasSuffix("JOIN") {
            lineBreak(f.column + options.indent)
            put(cased(t), space: false)
            frames[frames.count - 1].clause = "ON"
            return true
        }
        // INTO po INSERT/MERGE zostaje w linii instrukcji.
        if w == "INTO", ["INSERT", "MERGE"].contains(prev?.upper ?? "") { put(cased(t), space: true); return true }
        // USING w MERGE jest klauzulą; w JOIN … USING (…) — nie.
        if w == "USING", f.clause != "MERGE", f.clause != "INTO" { return false }
        // RETURN tylko w RETURNING … INTO (PL/SQL) — poza SQL nie trafia tutaj.
        if w == "RETURN" { return false }
        if w == "FOR", peek()?.upper != "UPDATE" { return false }
        if w == "SET", f.clause != "UPDATE", f.clause != "MATCHED" && f.clause != "WHEN" { return false }
        for words in Self.clauseStarts where words.first == w {
            var ok = true
            for (k, x) in words.enumerated() where peek(k)?.upper != x { ok = false; break }
            guard ok else { continue }
            lineBreak(f.column)
            var text = cased(t)
            for k in 1..<words.count { text += " " + cased(toks[i + k]) }
            put(text, space: false)
            i += words.count - 1
            frames[frames.count - 1].clause = words.contains("JOIN") ? "JOIN" : (w == "WHEN" ? "WHEN" : w == "INTO" && words.count == 1 ? "INTO" : words.last!)
            if words.first == "WHEN" { frames[frames.count - 1].clause = "WHEN" }
            alignAfterKeyword()
            return true
        }
        return false
    }

    mutating func comma() {
        put(",", space: false)
        guard let f = frames.last else { return }
        switch f.kind {
        case .sql:
            let listClauses: Set<String> = ["SELECT", "FROM", "BY", "SET", "INTO", "RETURNING", "VALUES", "WITH"]
            guard listClauses.contains(f.clause) else { return }
            if options.listLayout == .onePerLine || column > options.rightMargin {
                breakForList(max(f.column + 7, f.itemColumn))
            }
        case .paren where f.wrap:
            breakForList(f.column)
        case .unit, .declare, .block, .exception, .ifStmt, .loop, .caseStmt, .paren:
            if column > options.rightMargin { pendingBreak = continuationColumn() }
        }
    }

    mutating func breakForList(_ col: Int) {
        if options.commaBefore {
            cur.removeLast()
            lineBreak(max(0, col - 2))
            cur = ","
        } else {
            pendingBreak = col
        }
    }

    mutating func openParen(_ t: Tok) {
        let space = needsSpace(prev, t)
        put("(", space: space)
        let next = peek()
        let sub = next.map { ["SELECT", "WITH"].contains($0.upper) } ?? false
        // Zawijanie po przecinkach, gdy zawartość nawiasu nie mieści się do prawego marginesu.
        var wrap = false
        if !sub {
            var depth = 0
            var length = 0
            var j = i
            var hasComma = false
            while j < toks.count {
                let k = toks[j]
                if k.kind == .leftParen { depth += 1 }
                if k.kind == .rightParen { depth -= 1; if depth == 0 { break } }
                if depth == 1, k.kind == .comma { hasComma = true }
                if k.kind == .lineComment { length += 1000 }
                length += k.text.count + 1
                j += 1
            }
            wrap = hasComma && column + length > options.rightMargin
        }
        frames.append(Frame(kind: .paren, level: level, column: column, clause: "", wrap: wrap, subquery: sub))
    }

    mutating func closeParen(_ t: Tok) {
        // Zamknięcie instrukcji SQL podzapytania i samego nawiasu.
        while let f = frames.last, f.kind == .sql { frames.removeLast() }
        if let f = frames.last, f.kind == .paren { frames.removeLast() }
        put(")", space: false)
    }

    mutating func endStatement() {
        while let f = frames.last, f.kind == .sql || f.kind == .paren { frames.removeLast() }
        betweenPending = false
        statementStart = true
        pendingBreak = indentColumns(level)
    }

    // MARK: PL/SQL

    /// Struktura bloków PL/SQL; true — token obsłużony.
    mutating func handlePLSQL(_ t: Tok, _ w: String, _ prevUpper: String) -> Bool {
        guard t.isWord else {
            if t.kind == .semicolon, headerLevel != nil {
                // Deklaracja podprogramu bez ciała (specyfikacja) albo koniec nagłówka bez IS.
                headerLevel = nil
            }
            return false
        }
        // Nagłówek jednostki: CREATE [OR REPLACE] … PACKAGE/PROCEDURE/FUNCTION/TYPE/TRIGGER.
        if statementStart, w == "CREATE" {
            var j = i + 1
            while j < toks.count, ["OR", "REPLACE", "EDITIONABLE", "NONEDITIONABLE", "FORCE", "NOFORCE"].contains(toks[j].upper) { j += 1 }
            if j < toks.count, ["PACKAGE", "PROCEDURE", "FUNCTION", "TYPE", "TRIGGER"].contains(toks[j].upper) {
                beginStatementLine(t)
                headerLevel = level
                headerKind = toks[j].upper == "TYPE" && j + 1 < toks.count && toks[j + 1].upper != "BODY" ? "TYPESPEC" : toks[j].upper
                statementStart = false
                put(cased(t), space: false)
                return true
            }
            return false
        }
        // Podprogram w sekcji deklaracji.
        if statementStart, ["PROCEDURE", "FUNCTION"].contains(w) || (["MEMBER", "STATIC", "CONSTRUCTOR", "MAP", "ORDER", "OVERRIDING", "FINAL"].contains(w) && headerKind == "TYPE") {
            beginStatementLine(t)
            headerLevel = level
            headerKind = w
            statementStart = false
            put(cased(t), space: false)
            return true
        }
        if let h = headerLevel, ["IS", "AS"].contains(w) {
            // Typ obiektowy / kolekcja / LANGUAGE / EXTERNAL — bez sekcji deklaracji (zwykła instrukcja do „;”).
            if headerKind == "TYPESPEC" || ["LANGUAGE", "EXTERNAL", "MLE"].contains(peek()?.upper ?? "") {
                headerLevel = nil
                return false
            }
            put(cased(t), space: true)
            frames.append(Frame(kind: .declare, level: h))
            headerLevel = nil
            statementStart = true
            pendingBreak = indentColumns(h + 1)
            return true
        }
        if headerKind == "TRIGGER", let h = headerLevel, ["DECLARE", "BEGIN", "COMPOUND"].contains(w) {
            headerLevel = nil
            if w == "DECLARE" {
                lineBreak(indentColumns(h))
                put(cased(t), space: false)
                frames.append(Frame(kind: .declare, level: h))
                statementStart = true
                pendingBreak = indentColumns(h + 1)
                return true
            }
            statementStart = true
        }
        if headerLevel != nil { return false }

        switch w {
        case "DECLARE" where statementStart:
            beginStatementLine(t)
            put(cased(t), space: false)
            frames.append(Frame(kind: .declare, level: level))
            pendingBreak = indentColumns(level)
            return true
        case "BEGIN":
            if let f = frames.last, f.kind == .declare {
                frames[frames.count - 1].kind = .block
                if options.keepBlankLines, t.newlines >= 2 { blankLine() }
                lineBreak(indentColumns(f.level))
            } else {
                beginStatementLine(t)
                frames.append(Frame(kind: .block, level: level))
            }
            put(cased(t), space: false)
            statementStart = true
            pendingBreak = indentColumns(level)
            return true
        case "EXCEPTION" where statementStart && frames.last.map { [.block, .exception].contains($0.kind) } == true:
            let f = frames[frames.count - 1]
            frames[frames.count - 1].kind = .exception
            lineBreak(indentColumns(f.level))
            put(cased(t), space: false)
            statementStart = true
            pendingBreak = indentColumns(f.level + 1)
            return true
        case "END":
            let next = peek()?.upper ?? ""
            if ["IF", "LOOP", "CASE"].contains(next) {
                if let idx = frames.lastIndex(where: { $0.kind == (next == "IF" ? .ifStmt : next == "LOOP" ? .loop : .caseStmt) }) {
                    let f = frames[idx]
                    frames.removeSubrange(idx...)
                    lineBreak(indentColumns(f.level))
                    put(cased(t) + " " + cased(toks[i + 1]), space: false)
                    i += 1
                    statementStart = false
                    return true
                }
                return false
            }
            if let idx = frames.lastIndex(where: { [.block, .exception, .declare, .caseStmt].contains($0.kind) }) {
                let f = frames[idx]
                frames.removeSubrange(idx...)
                lineBreak(indentColumns(f.level))
                put(cased(t), space: false)
                statementStart = false
                return true
            }
            return false
        case "IF" where statementStart:
            beginStatementLine(t)
            frames.append(Frame(kind: .ifStmt, level: level))
            put(cased(t), space: false)
            statementStart = false
            return true
        case "ELSIF", "ELSE":
            if let f = frames.last, f.kind == .ifStmt {
                lineBreak(indentColumns(f.level))
                put(cased(t), space: false)
                statementStart = w == "ELSE"
                if w == "ELSE" { pendingBreak = indentColumns(f.level + 1) }
                return true
            }
            if let f = frames.last, f.kind == .caseStmt {
                lineBreak(indentColumns(f.level + 1))
                put(cased(t), space: false)
                statementStart = true
                pendingBreak = indentColumns(f.level + 2)
                return true
            }
            return false
        case "THEN":
            if let f = frames.last, [.ifStmt, .caseStmt, .exception].contains(f.kind) {
                put(cased(t), space: true)
                statementStart = true
                pendingBreak = indentColumns(f.kind == .ifStmt ? f.level + 1 : f.level + 2)
                return true
            }
            return false
        case "WHEN":
            if let f = frames.last, f.kind == .exception || f.kind == .caseStmt, statementStart || f.kind == .caseStmt {
                lineBreak(indentColumns(f.level + 1))
                put(cased(t), space: false)
                statementStart = false
                return true
            }
            return false
        case "CASE" where statementStart:
            beginStatementLine(t)
            frames.append(Frame(kind: .caseStmt, level: level))
            put(cased(t), space: false)
            statementStart = false
            return true
        case "LOOP":
            if prevUpper == "END" { return false }
            if !statementStart { put(cased(t), space: true) } else { beginStatementLine(t); put(cased(t), space: false) }
            frames.append(Frame(kind: .loop, level: statementLevelForLoop()))
            statementStart = true
            pendingBreak = indentColumns(frames.last!.level + 1)
            return true
        case "FOR" where statementStart, "WHILE" where statementStart:
            beginStatementLine(t)
            loopStartLevel = level
            put(cased(t), space: false)
            statementStart = false
            return true
        default:
            return false
        }
    }

    var loopStartLevel: Int?

    mutating func statementLevelForLoop() -> Int {
        defer { loopStartLevel = nil }
        return loopStartLevel ?? level
    }
}
