import Foundation

/// Wyrównanie kolumn w wyniku formatera (D174): deklaracje, parametry, parametry nazwane, przypisania, aliasy,
/// UPDATE … SET i komentarze na końcu linii. Działa na gotowych liniach i dodaje wyłącznie spacje przed wybranymi
/// tokenami; pomija linie skopiowane bez zmian i linie wewnątrz albo z początkiem wieloliniowego literału czy
/// komentarza. Wynik i tak sprawdza `Beautifier.verify`.
struct BeautifierAligner {
    struct Tok {
        let kind: TokenKind
        let start: Int
        let end: Int
        let text: String
        var upper: String { text.uppercased() }
        var isWord: Bool { kind == .identifier || kind == .keyword }
    }

    /// Tokeny linii zapamiętane do jej zmiany (grupy sprawdzają te same linie wiele razy).
    final class TokenCache { var lines: [Int: [Tok]] = [:] }

    var lines: [String]
    var skip: Set<Int>
    let cache = TokenCache()
    let options: BeautifierOptions

    init(lines: [String], raw: Set<Int>, options: BeautifierOptions) {
        self.lines = lines
        self.options = options
        skip = raw
    }

    /// Linie z wieloliniowym tokenem (literał, identyfikator w cudzysłowie, komentarz blokowy) — od jego początku
    /// do końca — nie są wyrównywane.
    mutating func skipMultilineTokens() {
        let text = lines.joined(separator: "\n")
        let ns = text as NSString
        var lineStarts: [Int] = [0]
        for (k, c) in text.utf16.enumerated() where c == 0x0A { lineStarts.append(k + 1) }
        func line(of pos: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts[mid] <= pos { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }
        for t in Lexer(text).tokenize() where [.string, .quotedIdentifier, .blockComment, .hint].contains(t.kind) {
            guard ns.substring(with: NSRange(location: t.start, length: t.length)).contains("\n") else { continue }
            skip.formUnion(line(of: t.start)...line(of: t.end - 1))
        }
    }

    var enabled: Bool {
        options.alignDeclarations || options.alignParameters || options.alignNamedArguments || options.alignAssignments
            || options.alignAliases || options.alignSetValues || options.alignTrailingComments
    }

    func aligned() -> [String] {
        guard enabled else { return lines }
        var a = self
        a.skipMultilineTokens()
        if options.alignDeclarations { a.alignGroups(a.declarationGroups()) }
        if options.alignAssignments { a.alignGroups(a.assignmentGroups()) }
        if options.alignParameters { a.alignGroups(a.listGroups(kind: .parameters)) }
        if options.alignNamedArguments { a.alignGroups(a.listGroups(kind: .namedArguments)) }
        if options.alignAliases { a.alignGroups(a.clauseItemGroups(["SELECT", "FROM"], anchor: aliasAnchor)) }
        if options.alignSetValues { a.alignGroups(a.clauseItemGroups(["SET"], anchor: setAnchor)) }
        if options.alignTrailingComments { a.alignGroups(a.trailingCommentGroups()) }
        return a.lines
    }

    // MARK: Tokeny linii

    func tokens(_ k: Int) -> [Tok]? {
        guard !skip.contains(k) else { return nil }
        if let t = cache.lines[k] { return t }
        let lexer = Lexer(lines[k])
        let t = lexer.tokenize().filter { $0.kind != .whitespace && $0.kind != .newline }
            .map { Tok(kind: $0.kind, start: $0.start, end: $0.end, text: lexer.string($0)) }
        cache.lines[k] = t
        return t
    }

    /// Kolumna (znaki; tabulator wcięcia liczony jak `indent` spacji) początku tokenu.
    func column(_ k: Int, _ utf16: Int) -> Int {
        let prefix = (lines[k] as NSString).substring(to: utf16)
        return prefix.reduce(0) { $0 + ($1 == "\t" ? max(1, options.indent) : 1) }
    }

    func indent(_ k: Int) -> String { String(lines[k].prefix { $0 == " " || $0 == "\t" }) }

    // MARK: Wyrównanie grup

    /// Grupa: linie i dla każdej kolejne kotwice (indeks tokenu albo nil). Kotwica k wszystkich linii trafia w jedną
    /// kolumnę — najdalszą w grupie; spacje dochodzą przed tokenem kotwicy.
    typealias Group = [(line: Int, anchors: [Int?])]

    mutating func alignGroups(_ groups: [Group]) {
        for g in groups where g.count >= 2 {
            let n = g.map(\.anchors.count).max() ?? 0
            for a in 0..<n {
                var cols: [(line: Int, tok: Int, col: Int)] = []
                for (line, anchors) in g {
                    guard a < anchors.count, let idx = anchors[a], let toks = tokens(line), idx < toks.count else { continue }
                    cols.append((line, idx, column(line, toks[idx].start)))
                }
                guard cols.count >= 2, let target = cols.map(\.col).max() else { continue }
                for c in cols where c.col < target {
                    guard let toks = tokens(c.line) else { continue }
                    let at = toks[c.tok].start
                    lines[c.line] = (lines[c.line] as NSString).replacingCharacters(in: NSRange(location: at, length: 0),
                                                                                    with: String(repeating: " ", count: target - c.col))
                    cache.lines[c.line] = nil
                }
            }
        }
    }

    /// Kolejne linie spełniające warunek (z tym samym wcięciem, gdy `sameIndent`) jako grupy.
    func consecutive(sameIndent: Bool, _ anchors: (Int) -> [Int?]?) -> [Group] {
        var groups: [Group] = []
        var current: Group = []
        var currentIndent: String?
        for k in lines.indices {
            if let a = anchors(k), !sameIndent || currentIndent == nil || indent(k) == currentIndent {
                current.append((k, a))
                currentIndent = indent(k)
            } else {
                if current.count >= 2 { groups.append(current) }
                current = []
                currentIndent = nil
                if let a = anchors(k) { current = [(k, a)]; currentIndent = indent(k) }
            }
        }
        if current.count >= 2 { groups.append(current) }
        return groups
    }

    /// Koniec kodu w linii: indeks ostatniego tokenu przed komentarzem na końcu.
    static func codeEnd(_ toks: [Tok]) -> Int {
        var e = toks.count - 1
        while e >= 0, toks[e].kind == .lineComment || toks[e].kind == .blockComment { e -= 1 }
        return e
    }

    // MARK: Deklaracje i przypisania

    static let notDeclarations: Set<String> = [
        "BEGIN", "END", "PROCEDURE", "FUNCTION", "CURSOR", "TYPE", "SUBTYPE", "PRAGMA", "IF", "ELSIF", "ELSE", "FOR", "WHILE", "LOOP",
        "RETURN", "EXIT", "RAISE", "NULL", "OPEN", "CLOSE", "FETCH", "COMMIT", "ROLLBACK", "SAVEPOINT", "CREATE", "DECLARE", "WHEN",
        "EXCEPTION", "CASE", "GOTO", "CONTINUE", "PIPE", "FORALL", "SELECT", "INSERT", "UPDATE", "DELETE", "MERGE", "WITH", "EXECUTE",
    ]

    /// `nazwa [CONSTANT] typ [NOT NULL] [:= | DEFAULT wyrażenie];` — kotwice: typ, `:=`/DEFAULT.
    func declarationGroups() -> [Group] {
        consecutive(sameIndent: true) { k in
            guard let t = tokens(k), t.count >= 3 else { return nil }
            let e = Self.codeEnd(t)
            guard e >= 2, t[e].kind == .semicolon, t[0].kind == .identifier || t[0].kind == .quotedIdentifier,
                  !Self.notDeclarations.contains(t[0].upper), t[1].isWord, !Self.notDeclarations.contains(t[1].upper) else { return nil }
            let assign = (2..<e).first { t[$0].text == ":=" || t[$0].upper == "DEFAULT" }
            return [1, assign]
        }
    }

    /// `cel := wyrażenie;` w jednej linii — kotwica: `:=`.
    func assignmentGroups() -> [Group] {
        consecutive(sameIndent: true) { k in
            guard let t = tokens(k), t.count >= 3 else { return nil }
            let e = Self.codeEnd(t)
            guard e >= 2, t[e].kind == .semicolon, t[0].kind != .keyword || ["SELF"].contains(t[0].upper) else { return nil }
            var depth = 0
            for (j, x) in t[0..<e].enumerated() {
                if x.kind == .leftParen { depth += 1 } else if x.kind == .rightParen { depth -= 1 }
                if depth == 0, x.text == ":=" { return j > 0 && t[j - 1].kind != .keyword ? [j] : nil }
                if depth == 0, x.isWord, j > 0, t[j - 1].isWord { return nil }
            }
            return nil
        }
    }

    // MARK: Listy parametrów i parametrów nazwanych

    enum ListKind { case parameters, namedArguments }

    static let modes: Set<String> = ["IN", "OUT", "NOCOPY"]

    /// Element listy w nawiasie zawiniętej element w linii: pierwsza linia — po „(”, kolejne — od kolumny elementu
    /// (z przecinkiem na początku przy stylu „przecinek przed”). Grupa kończy się na linii z „)” zamykającym listę.
    func listGroups(kind: ListKind) -> [Group] {
        var groups: [Group] = []
        var k = 0
        while k < lines.count {
            let nextComma = k + 1 < lines.count && tokens(k + 1)?.first?.kind == .comma
            guard let t = tokens(k), let open = listOpen(t, kind: kind, wrapped: nextComma) else { k += 1; continue }
            let col = column(k, t[open + 1].start)
            var group: Group = []
            var depth = 0
            for x in t[open...] { if x.kind == .leftParen { depth += 1 } else if x.kind == .rightParen { depth -= 1 } }
            if let a = anchors(t, from: open + 1, kind: kind) { group.append((k, a)) }
            var j = k + 1
            while depth > 0, j < lines.count, let u = tokens(j), !u.isEmpty {
                let first = u[0].kind == .comma && u.count > 1 ? 1 : 0
                guard column(j, u[first].start) == col else { break }
                for x in u { if x.kind == .leftParen { depth += 1 } else if x.kind == .rightParen { depth -= 1 } }
                if let a = anchors(u, from: first, kind: kind) { group.append((j, a)) }
                j += 1
            }
            if group.count >= 2 { groups.append(group) }
            k = max(j, k + 1)
        }
        return groups
    }

    /// Nawias otwierający listę w linii, gdy linia kończy się przecinkiem albo następna zaczyna się od przecinka.
    func listOpen(_ t: [Tok], kind: ListKind, wrapped: Bool) -> Int? {
        let e = Self.codeEnd(t) + (wrapped ? 1 : 0)
        guard e >= 2, wrapped || t[e].kind == .comma else { return nil }
        switch kind {
        case .parameters:
            guard let p = t.firstIndex(where: { ["PROCEDURE", "FUNCTION"].contains($0.upper) }), p + 3 <= e else { return nil }
            var j = p + 1
            while j < e, t[j].kind != .leftParen { j += 1 }
            return j < e ? j : nil
        case .namedArguments:
            guard let open = t.firstIndex(where: { $0.kind == .leftParen }), open + 2 < e, t[open + 2].text == "=>" else { return nil }
            return open
        }
    }

    /// Kotwice elementu od indeksu `from`: parametr — tryb, typ, DEFAULT/`:=`; parametr nazwany — `=>`.
    func anchors(_ t: [Tok], from: Int, kind: ListKind) -> [Int?]? {
        guard from + 1 < t.count, t[from].kind == .identifier || t[from].kind == .quotedIdentifier else { return nil }
        switch kind {
        case .namedArguments:
            return t[from + 1].text == "=>" ? [from + 1] : nil
        case .parameters:
            var j = from + 1
            let mode: Int? = Self.modes.contains(t[j].upper) ? j : nil
            while j < t.count, Self.modes.contains(t[j].upper) { j += 1 }
            guard j < t.count, t[j].isWord else { return nil }
            let type = j
            var depth = 0
            var def: Int?
            while j < t.count {
                if t[j].kind == .leftParen { depth += 1 } else if t[j].kind == .rightParen { if depth == 0 { break }; depth -= 1 }
                if depth == 0, t[j].kind == .comma { break }
                if depth == 0, def == nil, t[j].text == ":=" || t[j].upper == "DEFAULT" { def = j }
                j += 1
            }
            return [mode, type, def]
        }
    }

    // MARK: Elementy klauzul

    /// Lista klauzuli (SELECT, FROM, SET): linia pierwszego elementu i kolejne od jego kolumny. Pierwszy element jest
    /// w linii klauzuli albo — gdy klauzula stoi sama w linii (układ „w osobnej linii”) — w następnej.
    func clauseItemGroups(_ clauses: Set<String>, anchor: ([Tok], Int, Int) -> Int?) -> [Group] {
        var groups: [Group] = []
        var k = 0
        while k < lines.count {
            guard var t = tokens(k), let c = t.firstIndex(where: { clauses.contains($0.upper) }) else { k += 1; continue }
            var first = c + 1
            if first < t.count, ["DISTINCT", "UNIQUE", "ALL"].contains(t[first].upper) { first += 1 }
            var start = k
            if first >= t.count {
                guard k + 1 < lines.count, let u = tokens(k + 1), !u.isEmpty, !clauses.contains(u[0].upper) else { k += 1; continue }
                start = k + 1
                t = u
                first = 0
            }
            let col = column(start, t[first].start)
            var group: Group = [(start, [itemAnchor(t, from: first, anchor: anchor)])]
            var j = start + 1
            while j < lines.count, let u = tokens(j), !u.isEmpty {
                let f = u[0].kind == .comma && u.count > 1 ? 1 : 0
                guard column(j, u[f].start) == col else { break }
                group.append((j, [itemAnchor(u, from: f, anchor: anchor)]))
                j += 1
            }
            if group.count >= 2 { groups.append(group) }
            k = j
        }
        return groups
    }

    /// Kotwica elementu kończącego się w tej linii (przecinkiem albo końcem linii).
    func itemAnchor(_ t: [Tok], from: Int, anchor: ([Tok], Int, Int) -> Int?) -> Int? {
        var e = Self.codeEnd(t)
        if e >= from, t[e].kind == .comma || t[e].kind == .semicolon { e -= 1 }
        guard e >= from else { return nil }
        var depth = 0
        for x in t[from...e] {
            if x.kind == .leftParen { depth += 1 } else if x.kind == .rightParen { depth -= 1 }
            if depth == 0, x.kind == .comma { return nil }
        }
        return depth == 0 ? anchor(t, from, e) : nil
    }

    /// Alias kolumny albo tabeli: `AS alias` albo ostatnie słowo po wyrażeniu (`count(*) cnt`, `emp e`).
    func aliasAnchor(_ t: [Tok], _ from: Int, _ e: Int) -> Int? {
        guard e > from, t[e].kind == .identifier || t[e].kind == .quotedIdentifier else { return nil }
        if t[e - 1].upper == "AS" { return e - 1 > from ? e - 1 : nil }
        let p = t[e - 1]
        if [.identifier, .quotedIdentifier, .number, .string, .rightParen].contains(p.kind) || ["END", "NULL"].contains(p.upper) { return e }
        return nil
    }

    /// UPDATE … SET kolumna = wartość — kotwica: pierwszy `=` poza nawiasami.
    func setAnchor(_ t: [Tok], _ from: Int, _ e: Int) -> Int? {
        var depth = 0
        for j in from...e {
            if t[j].kind == .leftParen { depth += 1 } else if t[j].kind == .rightParen { depth -= 1 }
            if depth == 0, t[j].text == "=" { return j }
        }
        return nil
    }

    // MARK: Komentarze na końcu linii

    func trailingCommentGroups() -> [Group] {
        consecutive(sameIndent: false) { k in
            guard let t = tokens(k), t.count >= 2, t.last?.kind == .lineComment, t[t.count - 2].kind != .lineComment else { return nil }
            return [t.count - 1]
        }
    }
}
