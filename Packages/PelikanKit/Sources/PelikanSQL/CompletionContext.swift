import Foundation

/// Tabela (albo podzapytanie) w instrukcji SQL — do podpowiedzi kolumn po aliasie (PROMPT §3.1, UG 25.4).
public struct TableReference: Sendable, Hashable {
    public var owner: String?
    public var name: String
    public var alias: String?
    /// Tekst podzapytania `( … ) alias` — kolumny z jego listy SELECT.
    public var subquery: String?

    public init(owner: String? = nil, name: String, alias: String? = nil, subquery: String? = nil) {
        self.owner = owner; self.name = name; self.alias = alias; self.subquery = subquery
    }

    /// Czy odwołanie pasuje do kwalifikatora (alias, a bez aliasu — nazwa tabeli).
    public func matches(_ q: String) -> Bool {
        if let alias { return alias == q }
        return name == q
    }
}

/// Kontekst podpowiedzi w pozycji kursora (Code Assistant, UG 25.4) — analiza czysto tekstowa, bez bazy.
public struct CompletionContext: Sendable, Hashable {
    /// Wpisany fragment identyfikatora i zakres do zastąpienia wybranym elementem.
    public var prefix: String
    public var replaceRange: Range<Int>
    /// Kwalifikatory przed kropką (`e.` → ["E"], `scott.emp_api.` → ["SCOTT", "EMP_API"]); nazwy bez cudzysłowu wielkimi.
    public var qualifier: [String]
    /// `:new.` / `:old.` (kwalifikator z dwukropkiem).
    public var bindQualifier: Bool
    /// Po `@` — linki bazy danych.
    public var afterAt: Bool
    /// W literale albo komentarzu — bez podpowiedzi.
    public var inLiteralOrComment: Bool
    /// Tabele i podzapytania instrukcji, w której jest kursor.
    public var tables: [TableReference]
    /// Instrukcja jest zapytaniem/DML (kolumny tabel w podpowiedziach bez kwalifikatora).
    public var inSQLStatement: Bool
    /// Deklaracje widoczne w pozycji (zmienne, stałe, parametry, kursory, typy, podprogramy) — od najbliższego zakresu.
    public var declarations: [OutlineNode]
    /// Rekordy pętli `FOR r IN (zapytanie)` / `FOR r IN kursor` obejmujących pozycję: nazwa → zapytanie albo nazwa kursora.
    public var loopRecords: [String: String]
    /// Tabela wyzwalacza (dla `:new`/`:old`).
    public var triggerTable: TableReference?
    /// Tekst deklaracji typów lokalnych (`TYPE x IS RECORD (…)`) — nazwa wielkimi → tekst.
    public var typeDeclarations: [String: String]
    /// Zapytania kursorów w zasięgu (`CURSOR c IS zapytanie`) — nazwa wielkimi → zapytanie.
    public var cursorQueries: [String: String]

    struct Tok {
        let kind: TokenKind
        let start: Int
        let end: Int
        let upper: String
        let text: String
        var name: String { kind == .quotedIdentifier ? String(text.dropFirst().dropLast()) : upper }
        var isWord: Bool { kind == .identifier || kind == .quotedIdentifier || kind == .keyword }
    }

    public static func analyze(_ text: String, offset rawOffset: Int) -> CompletionContext {
        let ns = text as NSString
        let offset = min(max(0, rawOffset), ns.length)
        let all = Lexer(text).tokenize()
        // Literał / komentarz obejmujący kursor (koniec komentarza liniowego — do końca linii).
        let inLiteral = all.contains { t in
            [.string, .lineComment, .blockComment, .quotedIdentifier].contains(t.kind) && t.start < offset
                && (offset < t.start + t.length || (t.kind == .lineComment && offset == t.start + t.length)
                    || (t.kind == .string && offset == t.start + t.length && !ns.substring(with: NSRange(location: t.start, length: t.length)).hasSuffix("'")))
        }
        let toks: [Tok] = all.filter { ![.whitespace, .newline, .lineComment, .blockComment, .hint].contains($0.kind) }.map {
            let s = ns.substring(with: NSRange(location: $0.start, length: $0.length))
            return Tok(kind: $0.kind, start: $0.start, end: $0.start + $0.length, upper: s.uppercased(), text: s)
        }

        // Prefiks: znaki identyfikatora przed kursorem.
        func isIdent(_ c: unichar) -> Bool {
            guard let s = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(s) || c == 0x5F || c == 0x24 || c == 0x23
        }
        var a = offset
        while a > 0, isIdent(ns.character(at: a - 1)) { a -= 1 }
        var b = offset
        while b < ns.length, isIdent(ns.character(at: b)) { b += 1 }
        let prefix = ns.substring(with: NSRange(location: a, length: offset - a))
        // Kwalifikatory: identyfikator (albo "nazwa") przed kropką, wielokrotnie.
        var qualifier: [String] = []
        var bind = false
        var p = a
        while p > 0, ns.character(at: p - 1) == 0x2E {
            var e = p - 1
            if e > 0, ns.character(at: e - 1) == 0x22 {
                var s = e - 1
                while s > 0, ns.character(at: s - 1) != 0x22 { s -= 1 }
                guard s > 0 else { break }
                qualifier.insert(ns.substring(with: NSRange(location: s, length: e - 1 - s)), at: 0)
                p = s - 1
                continue
            }
            var s = e
            while s > 0, isIdent(ns.character(at: s - 1)) { s -= 1 }
            guard s < e else { break }
            qualifier.insert(ns.substring(with: NSRange(location: s, length: e - s)).uppercased(), at: 0)
            e = s
            p = s
            if s > 0, ns.character(at: s - 1) == 0x3A { bind = true; break }
        }
        let afterAt = a > 0 && ns.character(at: a - 1) == 0x40

        // Granice instrukcji: od poprzedniego `;` / BEGIN / DECLARE do następnego `;`.
        let idx = toks.lastIndex { $0.end <= a } ?? -1
        var startIdx = 0
        var i = idx
        while i >= 0 {
            let t = toks[i]
            if t.kind == .semicolon || t.kind == .slash || ["BEGIN", "DECLARE"].contains(t.upper) { startIdx = i + 1; break }
            i -= 1
        }
        var endIdx = toks.count
        i = max(idx + 1, 0)
        while i < toks.count {
            if toks[i].kind == .semicolon || toks[i].kind == .slash { endIdx = i; break }
            i += 1
        }
        let stmt = startIdx < endIdx ? Array(toks[startIdx..<endIdx]) : []
        let tables = tableReferences(stmt, source: ns)
        let sqlStart: Set<String> = ["SELECT", "INSERT", "UPDATE", "DELETE", "MERGE", "WITH"]
        let inSQL = stmt.contains { sqlStart.contains($0.upper) }

        // Deklaracje w zasięgu (zarys kodu).
        let outline = PLSQLOutline.parse(text)
        // Kod niedokończony: jednostki sięgają do końca tekstu (zakres bez końca) — kursor na końcu liczony od ostatniego znaku.
        let path = PLSQLOutline.path(at: offset == ns.length && offset > 0 ? offset - 1 : offset, in: outline)
        var decls: [OutlineNode] = []
        var types: [String: String] = [:]
        var cursors: [String: String] = [:]
        func addScope(_ n: OutlineNode) {
            for c in n.children where !(c.isContainer && c.kind == .block) {
                decls.append(c)
                let source = ns.substring(with: NSRange(location: c.range.lowerBound, length: c.range.count))
                if c.kind == .typeDeclaration, types[c.name.uppercased()] == nil { types[c.name.uppercased()] = source }
                if c.kind == .cursor, cursors[c.name.uppercased()] == nil,
                   let r = source.range(of: #"(?is)\bis\s+(.*?);?\s*$"#, options: .regularExpression) {
                    let q = source[r].replacingOccurrences(of: #"(?is)^is\s+"#, with: "", options: .regularExpression)
                    cursors[c.name.uppercased()] = q.hasSuffix(";") ? String(q.dropLast()) : q
                }
            }
        }
        for n in path.reversed() { addScope(n) }
        // Ciało pakietu widzi deklaracje specyfikacji z tego samego pliku.
        if let unit = path.first, unit.kind == .packageBody || unit.kind == .typeBody {
            for spec in outline where (spec.kind == .package || spec.kind == .type) && spec.name.uppercased() == unit.name.uppercased() { addScope(spec) }
        }

        // Rekordy pętli FOR … IN obejmujących pozycję (pętla zaczęta przed kursorem, niezamknięta przed nim).
        var loops: [String: String] = [:]
        var j = 0
        while j < toks.count, toks[j].end <= a {
            if toks[j].upper == "FOR", j + 2 < toks.count, toks[j + 1].isWord, toks[j + 2].upper == "IN" {
                let name = toks[j + 1].name
                var k = j + 3
                if k < toks.count, toks[k].upper == "REVERSE" { k += 1 }
                if k < toks.count, toks[k].kind == .leftParen {
                    var depth = 0
                    var m = k
                    while m < toks.count {
                        if toks[m].kind == .leftParen { depth += 1 }
                        if toks[m].kind == .rightParen { depth -= 1; if depth == 0 { break } }
                        m += 1
                    }
                    if m < toks.count {
                        loops[name] = ns.substring(with: NSRange(location: toks[k].end, length: toks[m].start - toks[k].end))
                    }
                } else if k < toks.count, toks[k].isWord, !(k + 1 < toks.count && toks[k + 1].text.hasPrefix("..")) {
                    // FOR r IN kursor[(…)] LOOP — zakres liczbowy (a..b) nie jest rekordem.
                    loops[name] = toks[k].name
                }
            }
            j += 1
        }

        // Tabela wyzwalacza: CREATE … TRIGGER x {BEFORE|AFTER|INSTEAD OF} … ON [owner.]tabela.
        var trigger: TableReference?
        if let unit = path.first, unit.kind == .trigger,
           let on = toks.firstIndex(where: { $0.start >= unit.range.lowerBound && $0.upper == "ON" }), on + 1 < toks.count {
            if on + 3 < toks.count, toks[on + 2].kind == .dot {
                trigger = TableReference(owner: toks[on + 1].name, name: toks[on + 3].name)
            } else {
                trigger = TableReference(name: toks[on + 1].name)
            }
        }

        return CompletionContext(prefix: prefix, replaceRange: a..<b, qualifier: qualifier, bindQualifier: bind, afterAt: afterAt,
                                 inLiteralOrComment: inLiteral, tables: tables, inSQLStatement: inSQL, declarations: decls,
                                 loopRecords: loops, triggerTable: trigger, typeDeclarations: types,
                                 cursorQueries: cursors)
    }

    /// Słowa kończące listę tabel (po nich nie ma aliasu).
    static let clauseWords: Set<String> = [
        "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "NATURAL", "ON", "USING", "GROUP", "ORDER",
        "HAVING", "CONNECT", "START", "UNION", "INTERSECT", "MINUS", "EXCEPT", "SET", "VALUES", "FETCH", "OFFSET", "FOR",
        "PARTITION", "SAMPLE", "PIVOT", "UNPIVOT", "MODEL", "WINDOW", "QUALIFY", "RETURNING", "RETURN", "LOG", "INTO",
        "WHEN", "THEN", "AS", "SELECT", "FROM", "LATERAL", "APPLY", "WITH", "BULK", "LIMIT", "IS",
    ]

    /// Tabele z FROM / JOIN / UPDATE / INSERT INTO / DELETE FROM / MERGE INTO … USING (z aliasami i podzapytaniami).
    static func tableReferences(_ t: [Tok], source ns: NSString) -> [TableReference] {
        var out: [TableReference] = []
        func alias(at k: inout Int) -> String? {
            if k < t.count, t[k].upper == "AS", k + 1 < t.count { k += 1 }
            guard k < t.count, t[k].isWord, !clauseWords.contains(t[k].upper),
                  t[k].kind != .keyword || !Keywords.reserved.contains(t[k].upper) else { return nil }
            defer { k += 1 }
            return t[k].name
        }
        /// Jedna pozycja listy tabel od indeksu k; zwraca indeks za nią.
        func item(_ k0: Int) -> Int {
            var k = k0
            guard k < t.count else { return k }
            if t[k].kind == .leftParen {
                var depth = 0
                var m = k
                while m < t.count {
                    if t[m].kind == .leftParen { depth += 1 }
                    if t[m].kind == .rightParen { depth -= 1; if depth == 0 { break } }
                    m += 1
                }
                let inner = m < t.count ? ns.substring(with: NSRange(location: t[k].end, length: t[m].start - t[k].end)) : ""
                k = m + 1
                let al = alias(at: &k)
                if inner.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("SELECT")
                    || inner.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("WITH") {
                    out.append(TableReference(name: "", alias: al, subquery: inner))
                }
                return k
            }
            guard t[k].isWord, !clauseWords.contains(t[k].upper) else { return k }
            if ["TABLE", "ONLY"].contains(t[k].upper), k + 1 < t.count, t[k + 1].kind == .leftParen { return item(k + 1) }
            var owner: String?
            var name = t[k].name
            k += 1
            if k + 1 < t.count, t[k].kind == .dot, t[k + 1].isWord { owner = name; name = t[k + 1].name; k += 2 }
            if k < t.count, t[k].text == "@" { k += 1; while k < t.count, t[k].isWord || t[k].kind == .dot { k += 1 } }
            let al = alias(at: &k)
            out.append(TableReference(owner: owner, name: name, alias: al))
            return k
        }
        let isMerge = t.contains { $0.upper == "MERGE" }
        var k = 0
        while k < t.count {
            let w = t[k].upper
            let prev = k > 0 ? t[k - 1].upper : ""
            if (w == "FROM" && prev != "DELETE") || w == "JOIN" || (w == "USING" && isMerge) {
                k += 1
                k = item(k)
                // Lista po przecinku tylko w FROM.
                while w == "FROM", k < t.count, t[k].kind == .comma { k = item(k + 1) }
                continue
            }
            if w == "UPDATE" || (w == "INTO" && ["INSERT", "MERGE"].contains(prev)) || (w == "FROM" && prev == "DELETE") {
                k = item(k + 1)
                continue
            }
            if w == "DELETE", k + 1 < t.count, t[k + 1].upper != "FROM", t[k + 1].isWord {
                k = item(k + 1)
                continue
            }
            k += 1
        }
        return out
    }
}
