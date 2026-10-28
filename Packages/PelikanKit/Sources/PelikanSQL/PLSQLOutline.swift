import Foundation

/// Element zarysu kodu PL/SQL (Code Contents, Code Hierarchy, nawigacja — UG 25.6, ADR 0002).
public struct OutlineNode: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case package, packageBody, type, typeBody, procedure, function, trigger, block
        case variable, constant, cursor, typeDeclaration, exception, parameter, pragma
        case declareSection, beginSection, exceptionSection
    }
    public var kind: Kind
    public var name: String
    /// Szczegóły (typ zmiennej, typ zwracany).
    public var detail: String
    /// Zakres całego elementu (UTF-16) i pozycja nazwy.
    public var range: Range<Int>
    public var nameOffset: Int
    public var children: [OutlineNode]
    /// Element pakietu albo typu: true — publiczny (w specyfikacji; w ciele — zadeklarowany w specyfikacji), false —
    /// prywatny (tylko w ciele), nil — nie dotyczy albo nieznane (ciało bez specyfikacji w tekście).
    public var isPublic: Bool?

    public init(kind: Kind, name: String, detail: String = "", range: Range<Int>, nameOffset: Int, children: [OutlineNode] = []) {
        self.kind = kind; self.name = name; self.detail = detail; self.range = range; self.nameOffset = nameOffset; self.children = children
    }

    /// Rodzaj typu z deklaracji `TYPE`/`SUBTYPE` (szczegóły zaczynają się od słów po IS/AS): RECORD, TABLE, VARRAY,
    /// REF CURSOR, OBJECT, SUBTYPE albo pusto.
    public var typeShape: String {
        let up = detail.uppercased()
        for shape in ["RECORD", "REF CURSOR", "TABLE", "VARRAY", "OBJECT", "SUBTYPE"] where up.hasPrefix(shape) { return shape }
        return up.hasPrefix("VARYING") ? "VARRAY" : ""
    }

    /// Czy element jest podprogramem lub jednostką (zwijany, w Code Contents).
    public var isContainer: Bool { [.package, .packageBody, .type, .typeBody, .procedure, .function, .trigger, .block].contains(kind) }
}

/// Parser strukturalny PL/SQL (ADR 0002): tolerancyjny, na tokenach leksera — rozpoznaje jednostki, podprogramy,
/// deklaracje i bloki BEGIN…END (z IF/LOOP/CASE), nie wymaga poprawnego kodu.
public enum PLSQLOutline {
    /// Słowa przed PROCEDURE/FUNCTION w metodach typów obiektowych.
    static let methodModifiers: Set<String> = ["MEMBER", "STATIC", "CONSTRUCTOR", "MAP", "ORDER", "OVERRIDING", "FINAL", "INSTANTIABLE", "NOT"]
    /// Opcje funkcji po typie zwracanym (koniec typu).
    static let functionOptions = ["PIPELINED", "DETERMINISTIC", "RESULT_CACHE", "PARALLEL_ENABLE", "AGGREGATE", "SQL_MACRO"]

    struct Tok {
        let kind: TokenKind
        let start: Int
        let end: Int
        let upper: String
        let text: String
    }

    static func tokens(_ text: String) -> [Tok] {
        let ns = text as NSString
        return Lexer(text).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment, .hint].contains($0.kind) }.map {
            let s = ns.substring(with: NSRange(location: $0.start, length: $0.length))
            return Tok(kind: $0.kind, start: $0.start, end: $0.start + $0.length, upper: s.uppercased(), text: s)
        }
    }

    /// Zarys całego tekstu (wiele jednostek w pliku).
    public static func parse(_ text: String) -> [OutlineNode] {
        let t = tokens(text)
        var p = Parser(t: t, i: 0, length: (text as NSString).length, source: text as NSString)
        return markVisibility(p.parseTop())
    }

    /// Klucz podprogramu do porównania specyfikacji z ciałem: rodzaj, nazwa i nazwy parametrów (przeciążenia).
    static func signature(_ n: OutlineNode) -> String {
        ([n.kind.rawValue, n.name.uppercased()] + n.children.filter { $0.kind == .parameter }.map { $0.name.uppercased() }).joined(separator: "|")
    }

    /// Elementy publiczne i prywatne (Code Contents): wszystko w specyfikacji pakietu/typu jest publiczne; w ciele
    /// publiczne są podprogramy i kursory zadeklarowane w specyfikacji z tego samego tekstu, pozostałe — prywatne.
    static func markVisibility(_ roots: [OutlineNode]) -> [OutlineNode] {
        var specs: [String: OutlineNode] = [:]
        for r in roots where [.package, .type].contains(r.kind) { specs[r.name.uppercased()] = r }
        let skipped: Set<OutlineNode.Kind> = [.block, .declareSection, .beginSection, .exceptionSection, .pragma, .parameter]
        return roots.map { r in
            var r = r
            switch r.kind {
            case .package, .type:
                r.children = r.children.map { var c = $0; if !skipped.contains(c.kind) { c.isPublic = true }; return c }
            case .packageBody, .typeBody:
                guard let spec = specs[r.name.uppercased()] else { break }
                let exact = Set(spec.children.map(signature))
                // Inne nazwy parametrów w ciele niż w specyfikacji (błąd kompilacji) — dopasowanie po samej nazwie, gdy
                // i specyfikacja, i ciało mają jedną wersję podprogramu (inaczej prywatne przeciążenie byłoby publiczne).
                var counts: [String: Int] = [:]
                for c in spec.children { counts[c.kind.rawValue + "|" + c.name.uppercased(), default: 0] += 1 }
                var bodyCounts: [String: Int] = [:]
                for c in r.children { bodyCounts[c.kind.rawValue + "|" + c.name.uppercased(), default: 0] += 1 }
                r.children = r.children.map { c in
                    var c = c
                    guard !skipped.contains(c.kind) else { return c }
                    let key = c.kind.rawValue + "|" + c.name.uppercased()
                    c.isPublic = exact.contains(signature(c))
                        || (counts[key] == 1 && bodyCounts[key] == 1 && [.procedure, .function, .cursor].contains(c.kind))
                    return c
                }
            default: break
            }
            return r
        }
    }

    /// Ścieżka elementów zawierających pozycję (Code Hierarchy): od jednostki do najgłębszego podprogramu/bloku.
    public static func path(at offset: Int, in nodes: [OutlineNode]) -> [OutlineNode] {
        var out: [OutlineNode] = []
        var level = nodes
        while let n = level.first(where: { $0.isContainer && $0.range.contains(offset) }) {
            out.append(n)
            level = n.children
        }
        return out
    }

    /// Deklaracja identyfikatora widoczna w pozycji (Go to declaration — lokalnie: od najgłębszego zakresu w górę).
    public static func declaration(of name: String, at offset: Int, in nodes: [OutlineNode]) -> OutlineNode? {
        let up = name.uppercased()
        let scopes = path(at: offset, in: nodes)
        for scope in scopes.reversed() {
            if let d = scope.children.first(where: { $0.name.uppercased() == up && !$0.isContainer && $0.kind != .pragma }) { return d }
            if let d = scope.children.first(where: { $0.name.uppercased() == up && $0.kind != .pragma }) { return d }
        }
        func search(_ list: [OutlineNode]) -> OutlineNode? {
            for n in list {
                if n.name.uppercased() == up, n.kind != .pragma { return n }
                if let d = search(n.children) { return d }
            }
            return nil
        }
        return search(nodes)
    }

    /// Zakresy do zwijania kodu: podprogramy, bloki i struktury sterujące (IF, LOOP, CASE) — linie od…do.
    public static func foldingRanges(_ text: String) -> [Range<Int>] {
        let t = tokens(text)
        var stack: [(String, Int)] = []
        var out: [Range<Int>] = []
        var i = 0
        while i < t.count {
            let k = t[i]
            guard k.kind == .keyword || k.kind == .identifier else { i += 1; continue }
            switch k.upper {
            case "BEGIN", "LOOP", "CASE", "IF":
                if k.upper == "IF", i > 0, t[i - 1].upper == "END" { break }
                if k.upper == "LOOP", i > 0, t[i - 1].upper == "END" { break }
                if k.upper == "CASE", i > 0, t[i - 1].upper == "END" { break }
                stack.append((k.upper, k.start))
            case "END":
                let next = i + 1 < t.count ? t[i + 1].upper : ""
                let explicit = ["IF", "LOOP", "CASE"].contains(next)
                // Samo END zamyka najbliższy BEGIN albo wyrażenie CASE (CASE ... END bez słowa CASE).
                let found = explicit ? stack.lastIndex(where: { $0.0 == next }) : stack.lastIndex(where: { $0.0 == "BEGIN" || $0.0 == "CASE" })
                if let j = found {
                    let wasCase = stack[j].0 == "CASE"
                    let start = stack[j].1
                    stack.removeSubrange(j...)
                    var end = explicit ? t[i + 1].end : k.end
                    if !explicit, !wasCase, i + 1 < t.count, t[i + 1].kind == .identifier { end = t[i + 1].end }
                    if explicit || !wasCase { out.append(start..<end) }
                }
            default: break
            }
            i += 1
        }
        return out.sorted { $0.lowerBound < $1.lowerBound }
    }

    struct Parser {
        let t: [Tok]
        var i: Int
        let length: Int
        let source: NSString

        /// Tekst źródła między tokenami (z oryginalnymi odstępami, białe znaki zwinięte).
        func text(from a: Tok, to b: Tok) -> String {
            source.substring(with: NSRange(location: a.start, length: b.end - a.start))
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }

        func peek(_ o: Int = 0) -> Tok? { i + o < t.count ? t[i + o] : nil }
        func isWord(_ o: Int, _ w: String) -> Bool { peek(o)?.upper == w }

        mutating func parseTop() -> [OutlineNode] {
            var out: [OutlineNode] = []
            while i < t.count {
                if isWord(0, "CREATE") {
                    let start = t[i].start
                    i += 1
                    while let k = peek(), ["OR", "REPLACE", "EDITIONABLE", "NONEDITIONABLE", "FORCE", "NOFORCE"].contains(k.upper) { i += 1 }
                    if let u = parseUnit(start: start) { out.append(u) }
                } else if isWord(0, "DECLARE") || isWord(0, "BEGIN") {
                    out.append(parseAnonymous())
                } else {
                    i += 1
                }
            }
            return out
        }

        /// Nazwa (opcjonalnie ze schematem) — zwraca nazwę i offset.
        mutating func name() -> (String, Int)? {
            guard var k = peek(), k.kind == .identifier || k.kind == .quotedIdentifier || k.kind == .keyword else { return nil }
            i += 1
            if isWord(0, "."), let n = peek(1) { i += 2; k = n }
            let s = k.kind == .quotedIdentifier ? String(k.text.dropFirst().dropLast()) : k.text
            return (s, k.start)
        }

        mutating func parseUnit(start: Int) -> OutlineNode? {
            guard let kw = peek() else { return nil }
            var kind: OutlineNode.Kind
            switch kw.upper {
            case "PACKAGE": kind = .package
            case "TYPE": kind = .type
            case "PROCEDURE": kind = .procedure
            case "FUNCTION": kind = .function
            case "TRIGGER": kind = .trigger
            default: return nil
            }
            i += 1
            if isWord(0, "BODY") { kind = kind == .package ? .packageBody : .typeBody; i += 1 }
            guard let (n, off) = name() else { return nil }
            switch kind {
            case .procedure, .function:
                return parseSubprogram(kind: kind, name: n, nameOffset: off, start: start)
            case .trigger:
                // Do bloku wyzwalacza: DECLARE / BEGIN / COMPOUND TRIGGER / CALL — bez wyjścia poza polecenie
                // (`;`, `/`; nawiasy warunku WHEN mogą zawierać dzielenie).
                var depth = 0
                while let k = peek() {
                    if k.kind == .leftParen { depth += 1 } else if k.kind == .rightParen { depth -= 1 }
                    else if depth <= 0, ["DECLARE", "BEGIN", "COMPOUND", "CALL"].contains(k.upper) || k.kind == .semicolon || k.kind == .slash { break }
                    i += 1
                }
                var node = OutlineNode(kind: .trigger, name: n, range: start..<length, nameOffset: off)
                if isWord(0, "COMPOUND") {
                    i += isWord(1, "TRIGGER") ? 2 : 1
                    let body = parseCompoundBody()
                    node.children = body.children
                    node.range = start..<body.end
                    return node
                }
                if !isWord(0, "DECLARE"), !isWord(0, "BEGIN") {
                    // CALL procedura — do końca polecenia.
                    depth = 0
                    while let k = peek() {
                        if k.kind == .leftParen { depth += 1 } else if k.kind == .rightParen { depth -= 1 }
                        else if depth <= 0, k.kind == .semicolon || k.kind == .slash { break }
                        i += 1
                    }
                    node.range = start..<(peek()?.kind == .semicolon ? t[i].end : t[i - 1].end)
                    if peek()?.kind == .semicolon { i += 1 }
                    return node
                }
                let body = parseBlockBody(allowDeclare: true)
                node.children = body.children
                node.range = start..<body.end
                return node
            default:
                return parseSpecOrBody(kind: kind, name: n, nameOffset: off, start: start)
            }
        }

        /// Pakiet/typ: deklaracje do END [nazwa]; (ciało pakietu może mieć sekcję inicjalizacji BEGIN).
        mutating func parseSpecOrBody(kind: OutlineNode.Kind, name: String, nameOffset: Int, start: Int) -> OutlineNode {
            // Do AS/IS (typ obiektowy: AS OBJECT (…)).
            while let k = peek(), !["AS", "IS"].contains(k.upper), k.kind != .semicolon { i += 1 }
            if isWord(0, "AS") || isWord(0, "IS") { i += 1 }
            var node = OutlineNode(kind: kind, name: name, range: start..<length, nameOffset: nameOffset)
            if kind == .type, isWord(0, "OBJECT") || isWord(0, "TABLE") || isWord(0, "VARRAY") || isWord(0, "VARYING") {
                // Typ obiektowy / kolekcja — do końca polecenia: atrybuty jako zmienne, metody jako podprogramy.
                let isObject = isWord(0, "OBJECT")
                var depth = 0
                while let k = peek(), k.kind != .semicolon, k.kind != .slash {
                    if k.kind == .leftParen { depth += 1; i += 1; continue }
                    if k.kind == .rightParen { depth -= 1; i += 1; continue }
                    let prev = i > 0 ? t[i - 1] : nil
                    let elementStart = depth == 1 && (prev?.kind == .leftParen || prev?.kind == .comma)
                    if isObject, elementStart, PLSQLOutline.methodModifiers.contains(k.upper) || ["PROCEDURE", "FUNCTION"].contains(k.upper) {
                        let mStart = k.start
                        while let m = peek(), PLSQLOutline.methodModifiers.contains(m.upper) { i += 1 }
                        guard let w = peek(), ["PROCEDURE", "FUNCTION"].contains(w.upper) else { continue }
                        i += 1
                        guard let (n, off) = self.name() else { continue }
                        node.children.append(parseMethodSpec(kind: w.upper == "PROCEDURE" ? .procedure : .function, name: n, nameOffset: off, start: mStart))
                        continue
                    }
                    if elementStart, k.kind == .identifier || k.kind == .quotedIdentifier {
                        // Atrybut: nazwa i typ do przecinka albo nawiasu zamykającego listę.
                        i += 1
                        var first: Tok?, last: Tok?
                        var d = 0
                        while let a = peek(), !(d == 0 && (a.kind == .comma || a.kind == .rightParen)), a.kind != .semicolon, a.kind != .slash {
                            if a.kind == .leftParen { d += 1 } else if a.kind == .rightParen { d -= 1 }
                            if first == nil { first = a }
                            last = a
                            i += 1
                        }
                        let n = k.kind == .quotedIdentifier ? String(k.text.dropFirst().dropLast()) : k.text
                        node.children.append(OutlineNode(kind: .variable, name: n, detail: first.flatMap { a in last.map { text(from: a, to: $0) } } ?? "",
                                                         range: k.start..<(last?.end ?? k.end), nameOffset: k.start))
                        continue
                    }
                    i += 1
                }
                node.range = start..<(peek()?.end ?? length)
                return node
            }
            node.children = parseDeclarations(untilEnd: true)
            if isWord(0, "BEGIN") {
                // Sekcja inicjalizacji ciała pakietu kończy się END nazwa; całej jednostki.
                let b = parseBlockBody(allowDeclare: false)
                node.children.append(contentsOf: b.children)
                node.range = start..<b.end
                return node
            }
            // END [nazwa] ;
            if isWord(0, "END") {
                i += 1
                if let k = peek(), k.kind == .identifier || k.kind == .quotedIdentifier { i += 1 }
                if let k = peek(), k.kind == .semicolon { node.range = start..<k.end; i += 1 } else { node.range = start..<(t[i - 1].end) }
            } else {
                node.range = start..<(peek()?.start ?? length)
            }
            return node
        }

        /// Metoda w specyfikacji typu obiektowego: parametry i typ zwracany, do przecinka albo nawiasu kończącego listę.
        mutating func parseMethodSpec(kind: OutlineNode.Kind, name: String, nameOffset: Int, start: Int) -> OutlineNode {
            var node = OutlineNode(kind: kind, name: name, range: start..<length, nameOffset: nameOffset)
            if peek()?.kind == .leftParen { node.children = parseParameters() }
            var first: Tok?, last: Tok?
            var returns = false
            var d = 0
            while let k = peek(), !(d == 0 && (k.kind == .comma || k.kind == .rightParen)), k.kind != .semicolon, k.kind != .slash {
                if k.kind == .leftParen { d += 1 } else if k.kind == .rightParen { d -= 1 }
                if d == 0, k.upper == "RETURN" {
                    returns = true
                } else if d == 0, PLSQLOutline.functionOptions.contains(k.upper) {
                    returns = false
                } else if returns {
                    if first == nil { first = k }
                    last = k
                }
                i += 1
            }
            if let a = first, let b = last { node.detail = text(from: a, to: b) }
            node.range = start..<(i > 0 ? t[i - 1].end : start)
            return node
        }

        /// Lista parametrów w nawiasach: nazwa, tryb i typ (bez wartości domyślnej).
        mutating func parseParameters() -> [OutlineNode] {
            var params: [OutlineNode] = []
            var depth = 0
            var expectName = true
            var detailStart: Tok?
            var detailEnd: Tok?
            func flush() {
                if let a = detailStart, let b = detailEnd, let last = params.indices.last {
                    // Typ parametru bez wartości domyślnej.
                    var d = text(from: a, to: b)
                    for marker in [" DEFAULT ", " default ", " := "] { if let r = d.range(of: marker) { d = String(d[..<r.lowerBound]) } }
                    params[last].detail = d.trimmingCharacters(in: .whitespaces)
                }
                detailStart = nil
                detailEnd = nil
            }
            while let k = peek() {
                if k.kind == .leftParen { depth += 1; i += 1; if depth == 1 { expectName = true } else { detailEnd = k }; continue }
                if k.kind == .rightParen { depth -= 1; i += 1; if depth == 0 { flush(); break }; detailEnd = k; continue }
                if k.kind == .semicolon || k.kind == .slash { flush(); break }
                if depth == 1, k.kind == .comma { flush(); expectName = true; i += 1; continue }
                if depth == 1, expectName, k.kind == .identifier || k.kind == .quotedIdentifier || k.kind == .keyword {
                    params.append(OutlineNode(kind: .parameter, name: k.text, range: k.start..<k.end, nameOffset: k.start))
                    expectName = false
                } else if !expectName {
                    if detailStart == nil { detailStart = k }
                    detailEnd = k
                }
                i += 1
            }
            return params
        }

        /// Podprogram: parametry, RETURN, deklaracja (;) albo IS/AS + deklaracje + blok.
        mutating func parseSubprogram(kind: OutlineNode.Kind, name: String, nameOffset: Int, start: Int) -> OutlineNode {
            var node = OutlineNode(kind: kind, name: name, range: start..<length, nameOffset: nameOffset)
            if peek()?.kind == .leftParen { node.children = parseParameters() }
            if isWord(0, "RETURN") {
                i += 1
                var first: Tok?
                var last: Tok?
                if isWord(0, "SELF"), isWord(1, "AS"), isWord(2, "RESULT") {
                    node.detail = text(from: t[i], to: t[i + 2])
                    i += 3
                } else {
                    while let k = peek(), k.kind != .semicolon, !(["IS", "AS", "AUTHID", "ACCESSIBLE"] + PLSQLOutline.functionOptions).contains(k.upper) {
                        if first == nil { first = k }
                        last = k
                        i += 1
                    }
                    if let a = first, let b = last { node.detail = text(from: a, to: b) }
                }
            }
            while let k = peek(), k.kind != .semicolon, !["IS", "AS"].contains(k.upper) { i += 1 }
            if let k = peek(), k.kind == .semicolon {
                // Deklaracja w specyfikacji.
                node.range = start..<k.end
                i += 1
                return node
            }
            i += 1   // IS/AS
            if isWord(0, "LANGUAGE") || isWord(0, "EXTERNAL") || isWord(0, "MLE") {
                while let k = peek(), k.kind != .semicolon { i += 1 }
                node.range = start..<(peek()?.end ?? length)
                i += 1
                return node
            }
            node.children += parseDeclarations(untilEnd: false)
            let body = parseBlockBody(allowDeclare: false)
            node.children += body.children
            node.range = start..<body.end
            return node
        }

        /// Deklaracje: zmienne, stałe, kursory, typy, wyjątki, podprogramy — do BEGIN (albo END dla specyfikacji;
        /// w wyzwalaczu złożonym także do punktu czasowego BEFORE/AFTER/INSTEAD OF).
        mutating func parseDeclarations(untilEnd: Bool, timingPoints: Bool = false) -> [OutlineNode] {
            var out: [OutlineNode] = []
            while let k = peek() {
                if k.upper == "BEGIN" { break }
                if k.upper == "END" { break }
                if k.kind == .slash { break }
                if timingPoints, ["BEFORE", "AFTER", "INSTEAD"].contains(k.upper) { break }
                // Metody w ciele typu: MEMBER, STATIC, CONSTRUCTOR, MAP/ORDER, OVERRIDING, FINAL… przed PROCEDURE/FUNCTION.
                if PLSQLOutline.methodModifiers.contains(k.upper) {
                    var j = i
                    while j < t.count, PLSQLOutline.methodModifiers.contains(t[j].upper) { j += 1 }
                    if j < t.count, ["PROCEDURE", "FUNCTION"].contains(t[j].upper) {
                        let start = k.start
                        let kw = t[j]
                        i = j + 1
                        guard let (n, off) = name() else { continue }
                        out.append(parseSubprogram(kind: kw.upper == "PROCEDURE" ? .procedure : .function, name: n, nameOffset: off, start: start))
                        continue
                    }
                }
                switch k.upper {
                case "PROCEDURE", "FUNCTION":
                    let start = k.start
                    i += 1
                    guard let (n, off) = name() else { continue }
                    out.append(parseSubprogram(kind: k.upper == "PROCEDURE" ? .procedure : .function, name: n, nameOffset: off, start: start))
                case "CURSOR":
                    let start = k.start
                    i += 1
                    guard let (n, off) = name() else { continue }
                    // Szczegóły: parametry i typ zwracany (bez zapytania po IS).
                    let first = peek()
                    var last: Tok?
                    var d = 0
                    while let c = peek(), c.kind != .semicolon, !(d == 0 && c.upper == "IS") {
                        if c.kind == .leftParen { d += 1 } else if c.kind == .rightParen { d -= 1 }
                        last = c
                        i += 1
                    }
                    let detail = last.flatMap { l in first.map { text(from: $0, to: l) } } ?? ""
                    let end = skipStatement()
                    out.append(OutlineNode(kind: .cursor, name: n, detail: detail, range: start..<end, nameOffset: off))
                case "TYPE", "SUBTYPE":
                    let start = k.start
                    let sub = k.upper == "SUBTYPE"
                    i += 1
                    guard let (n, off) = name() else { continue }
                    // Szczegóły: definicja po IS/AS (RECORD (…), TABLE OF …, REF CURSOR…); podtyp — „SUBTYPE typ bazowy”.
                    if isWord(0, "IS") || isWord(0, "AS") { i += 1 }
                    let first = peek()
                    let end = skipStatement()
                    var detail = ""
                    if let a = first, a.start < end {
                        detail = source.substring(with: NSRange(location: a.start, length: max(0, end - a.start)))
                            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                        if detail.hasSuffix(";") { detail.removeLast() }
                        if sub { detail = "SUBTYPE " + detail }
                    }
                    out.append(OutlineNode(kind: .typeDeclaration, name: n, detail: detail, range: start..<end, nameOffset: off))
                case "PRAGMA":
                    // PRAGMA AUTONOMOUS_TRANSACTION, EXCEPTION_INIT(…), SERIALLY_REUSABLE, RESTRICT_REFERENCES(…), INLINE…
                    let start = k.start
                    i += 1
                    guard let p = peek() else { continue }
                    let first = i
                    let end = skipStatement()
                    var args = ""
                    if let open = t[first..<i].firstIndex(where: { $0.kind == .leftParen }), t[open].start < end {
                        args = source.substring(with: NSRange(location: t[open].start, length: max(0, end - t[open].start)))
                            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                        if args.hasSuffix(";") { args.removeLast() }
                    }
                    out.append(OutlineNode(kind: .pragma, name: p.text, detail: args, range: start..<end, nameOffset: p.start))
                default:
                    if k.kind == .identifier || k.kind == .quotedIdentifier {
                        let start = k.start
                        i += 1
                        var kind: OutlineNode.Kind = .variable
                        var first: Tok?
                        var last: Tok?
                        if isWord(0, "CONSTANT") { kind = .constant; i += 1 }
                        if isWord(0, "EXCEPTION") { kind = .exception }
                        while let d = peek(), d.kind != .semicolon, d.upper != ":=", d.upper != "DEFAULT" {
                            if first == nil { first = d }
                            last = d
                            i += 1
                        }
                        let end = skipStatement()
                        let n = k.kind == .quotedIdentifier ? String(k.text.dropFirst().dropLast()) : k.text
                        let detail = first.flatMap { a in last.map { text(from: a, to: $0) } } ?? ""
                        out.append(OutlineNode(kind: kind, name: n, detail: kind == .exception ? "" : detail,
                                               range: start..<end, nameOffset: k.start))
                    } else {
                        i += 1
                    }
                }
            }
            return out
        }

        /// Do średnika na głębokości 0 (włącznie); zwraca koniec.
        mutating func skipStatement() -> Int {
            var depth = 0
            while let k = peek() {
                if k.kind == .leftParen { depth += 1 }
                if k.kind == .rightParen { depth -= 1 }
                i += 1
                if depth <= 0, k.kind == .semicolon { return k.end }
            }
            return length
        }

        /// Blok BEGIN … [EXCEPTION …] END [nazwa]; — zagnieżdżone bloki (DECLARE/BEGIN) jako dzieci; struktury IF/LOOP/CASE
        /// liczone, żeby END IF/END LOOP/END CASE nie kończyły bloku.
        mutating func parseBlockBody(allowDeclare: Bool) -> (children: [OutlineNode], end: Int) {
            var children: [OutlineNode] = []
            if allowDeclare, isWord(0, "DECLARE") {
                i += 1
                children += parseDeclarations(untilEnd: false)
            }
            guard isWord(0, "BEGIN") else { return (children, peek()?.start ?? length) }
            i += 1
            while let k = peek() {
                if k.upper == "END" {
                    let next = peek(1)?.upper ?? ""
                    if ["IF", "LOOP", "CASE"].contains(next) { i += 2; continue }
                    i += 1
                    if let n = peek(), n.kind == .identifier || n.kind == .quotedIdentifier { i += 1 }
                    var end = t[i - 1].end
                    if let s = peek(), s.kind == .semicolon { end = s.end; i += 1 }
                    return (children, end)
                }
                if k.upper == "DECLARE" || (k.upper == "BEGIN") {
                    let start = k.start
                    let inner = parseBlockBody(allowDeclare: true)
                    children.append(OutlineNode(kind: .block, name: "BEGIN", range: start..<inner.end, nameOffset: start, children: inner.children))
                    continue
                }
                // CASE jako wyrażenie albo instrukcja — obie kończą się END [CASE]; wyrażenie END bez CASE.
                if k.upper == "CASE" {
                    i += 1
                    var depth = 1
                    while let c = peek(), depth > 0 {
                        if c.upper == "CASE" { depth += 1 }
                        if c.upper == "END" {
                            depth -= 1
                            if peek(1)?.upper == "CASE" { i += 1 }
                        }
                        i += 1
                    }
                    continue
                }
                i += 1
            }
            return (children, length)
        }

        /// Ciało wyzwalacza złożonego: deklaracje wspólne, punkty czasowe `BEFORE STATEMENT IS BEGIN … END BEFORE
        /// STATEMENT;`, na końcu END [nazwa];
        mutating func parseCompoundBody() -> (children: [OutlineNode], end: Int) {
            var children: [OutlineNode] = []
            while let k = peek() {
                if ["BEFORE", "AFTER", "INSTEAD"].contains(k.upper) {
                    while let s = peek(), s.upper != "BEGIN", s.upper != "END", s.kind != .semicolon, s.kind != .slash { i += 1 }
                    guard isWord(0, "BEGIN") else {
                        if peek()?.kind == .semicolon { i += 1 }
                        continue
                    }
                    children += parseBlockBody(allowDeclare: false).children
                    // END punkt_czasowy; — słowa punktu po END.
                    if t[i - 1].kind != .semicolon {
                        while let s = peek(), s.kind != .semicolon, s.kind != .slash { i += 1 }
                        if peek()?.kind == .semicolon { i += 1 }
                    }
                    continue
                }
                if k.upper == "END" {
                    i += 1
                    if let n = peek(), n.kind == .identifier || n.kind == .quotedIdentifier { i += 1 }
                    var end = t[i - 1].end
                    if let s = peek(), s.kind == .semicolon { end = s.end; i += 1 }
                    return (children, end)
                }
                if k.kind == .slash { return (children, i > 0 ? t[i - 1].end : k.start) }
                let before = i
                children += parseDeclarations(untilEnd: true, timingPoints: true)
                if i == before { i += 1 }
            }
            return (children, length)
        }

        mutating func parseAnonymous() -> OutlineNode {
            let start = t[i].start
            let b = parseBlockBody(allowDeclare: true)
            return OutlineNode(kind: .block, name: "BEGIN", range: start..<b.end, nameOffset: start, children: b.children)
        }
    }
}
