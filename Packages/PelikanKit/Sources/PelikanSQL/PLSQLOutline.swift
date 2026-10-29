import Foundation

/// Element zarysu kodu PL/SQL (Code Contents, Code Hierarchy, nawigacja — UG 25.6, ADR 0002).
public struct OutlineNode: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case package, packageBody, type, typeBody, procedure, function, trigger, block
        case variable, constant, cursor, typeDeclaration, exception, parameter, pragma
        case declareSection, beginSection, exceptionSection
        /// Polecenie SQL skryptu okna SQL (zapytanie, DML, DDL) — tylko w `parseScript` (D199).
        case statement
        /// Struktury sterujące (D203, tylko z `controlFlow`): IF z gałęziami ELSIF/ELSE, pętle LOOP/FOR/WHILE, FORALL,
        /// instrukcja CASE z gałęziami WHEN/ELSE, obsługa wyjątków WHEN w sekcji EXCEPTION, punkt czasowy wyzwalacza
        /// złożonego. Nazwa — słowo otwierające (wielkimi literami), szczegóły — dalszy nagłówek (warunek, zakres pętli).
        case ifStatement, elsifBranch, elseBranch, loop, forall, caseStatement, whenBranch, exceptionHandler, timingPoint

        /// Struktura sterująca albo sekcja bloku (EXCEPTION, BEGIN inicjalizacji pakietu) — w zarysie tylko z
        /// `controlFlow` (bez niej jej dzieci, np. bloki zagnieżdżone, należą do elementu nadrzędnego).
        public var isControlFlow: Bool {
            switch self {
            case .ifStatement, .elsifBranch, .elseBranch, .loop, .forall, .caseStatement, .whenBranch, .exceptionHandler,
                 .timingPoint, .exceptionSection, .beginSection: true
            default: false
            }
        }
    }
    public var kind: Kind
    public var name: String
    /// Szczegóły (typ zmiennej, typ zwracany).
    public var detail: String
    /// Zakres całego elementu (UTF-16) i pozycja nazwy.
    public var range: Range<Int>
    public var nameOffset: Int
    public var children: [OutlineNode]
    /// Etykieta `<<nazwa>>` przed blokiem albo strukturą sterującą (D203).
    public var label: String?
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
/// deklaracje, bloki BEGIN…END i struktury sterujące (IF, pętle, CASE, EXCEPTION — D203), nie wymaga poprawnego kodu.
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
        return significant(text).map { tok($0, ns) }
    }

    /// Tokeny bez odstępów, komentarzy i podpowiedzi optymalizatora — bez tekstu (tani przebieg przez cały skrypt).
    static func significant(_ text: String) -> [Token] {
        Lexer(text).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment, .hint].contains($0.kind) }
    }

    static func tok(_ t: Token, _ ns: NSString) -> Tok {
        let s = ns.substring(with: NSRange(location: t.start, length: t.length))
        return Tok(kind: t.kind, start: t.start, end: t.start + t.length, upper: s.uppercased(), text: s)
    }

    /// Zarys całego tekstu (wiele jednostek w pliku). `controlFlow` — także struktury sterujące (IF, pętle, CASE,
    /// sekcje EXCEPTION z obsługami wyjątków, punkty czasowe wyzwalacza złożonego — D203); bez niej zarys jak
    /// `withoutControlFlow` z nimi (bloki zagnieżdżone należą do podprogramu).
    public static func parse(_ text: String, controlFlow: Bool = false) -> [OutlineNode] {
        let t = withoutDirectives(tokens(text))
        var p = Parser(t: t, i: 0, length: (text as NSString).length, source: text as NSString, controlFlow: controlFlow)
        return markVisibility(p.parseTop())
    }

    /// Zarys bez struktur sterujących: każda struktura zastąpiona swoimi dziećmi (bloki zagnieżdżone, deklaracje bloku).
    public static func withoutControlFlow(_ nodes: [OutlineNode]) -> [OutlineNode] {
        var out: [OutlineNode] = []
        out.reserveCapacity(nodes.count)
        for n in nodes {
            if n.kind.isControlFlow {
                out += withoutControlFlow(n.children)
            } else if n.children.isEmpty {
                out.append(n)
            } else {
                var n = n
                n.children = withoutControlFlow(n.children)
                out.append(n)
            }
        }
        return out
    }

    /// Słowa dyrektyw kompilacji warunkowej (`$IF … $THEN`, `$ELSIF`, `$ELSE`, `$END`, `$ERROR … $END`).
    static let directiveWords: Set<String> = ["IF", "THEN", "ELSIF", "ELSE", "END", "ERROR"]

    /// Dyrektywa kompilacji warunkowej w pozycji `i`: słowo i liczba tokenów — `$` sklejony ze słowem (dwa tokeny)
    /// albo jeden token `$IF` (lekser rozpoznający dyrektywy).
    static func directive(_ t: [Tok], _ i: Int) -> (word: String, count: Int)? {
        let k = t[i]
        if k.upper == "$" {
            guard i + 1 < t.count, t[i + 1].start == k.end, directiveWords.contains(t[i + 1].upper) else { return nil }
            return (t[i + 1].upper, 2)
        }
        guard k.upper.hasPrefix("$"), !k.upper.hasPrefix("$$") else { return nil }
        let w = String(k.upper.dropFirst())
        return directiveWords.contains(w) ? (w, 1) : nil
    }

    /// Słowa kończące pomijanie warunku `$IF`/`$ELSIF` i komunikatu `$ERROR` bez dyrektywy zamykającej.
    static let directiveStops: Set<String> = ["BEGIN", "END", "DECLARE", "LOOP", "IF", "THEN", "ELSIF", "ELSE", "PROCEDURE",
                                              "FUNCTION", "CREATE", "EXCEPTION"]

    /// Tokeny bez dyrektyw kompilacji warunkowej (`$IF warunek $THEN`, `$ELSIF warunek $THEN`, `$ELSE`, `$END`,
    /// `$ERROR … $END`) — kod obu gałęzi zostaje, `$END` nie zamyka bloku, a `$IF` nie jest instrukcją IF.
    static func withoutDirectives(_ t: [Tok]) -> [Tok] {
        guard t.contains(where: { $0.upper.hasPrefix("$") }) else { return t }
        var out: [Tok] = []
        out.reserveCapacity(t.count)
        var i = 0
        while i < t.count {
            guard let d = directive(t, i) else { out.append(t[i]); i += 1; continue }
            i += d.count
            // Warunek do $THEN, komunikat $ERROR do $END — pomijane razem z dyrektywą.
            guard let stop = ["IF": "THEN", "ELSIF": "THEN", "ERROR": "END"][d.word] else { continue }
            // Niedomknięta dyrektywa (pisany kod, literówka „$THN”) nie pochłania reszty: pomijanie kończy się przed
            // średnikiem, inną dyrektywą albo słowem, które nie występuje w warunku statycznym ani komunikacie.
            while i < t.count {
                if let e = directive(t, i) {
                    if e.word == stop { i += e.count }
                    break
                }
                // Słowo sklejone z `$` to flaga zapytania (`$$begin`, `$$loop`), nie koniec warunku.
                let inquiry = i > 0 && t[i - 1].upper == "$" && t[i - 1].end == t[i].start
                if t[i].kind == .semicolon || (!inquiry && directiveStops.contains(t[i].upper)) { break }
                i += 1
            }
        }
        return out
    }

    /// Zarys skryptu okna SQL: elementy i liczba poleceń SQL pominiętych ponad limit (bardzo duże skrypty).
    public struct ScriptOutline: Sendable, Hashable {
        public var nodes: [OutlineNode]
        /// Polecenia SQL pominięte, bo skrypt ma ich więcej niż limit (0 — wszystkie w zarysie).
        public var omittedStatements: Int
        public init(nodes: [OutlineNode], omittedStatements: Int = 0) { self.nodes = nodes; self.omittedStatements = omittedStatements }
    }

    /// Najwięcej poleceń SQL w zarysie skryptu — powyżej tylko jednostki i bloki PL/SQL (panel i tak byłby nieczytelny).
    public static let scriptStatementLimit = 5000
    /// Najwięcej znaków początku polecenia w szczegółach (podpowiedź panelu).
    public static let statementDetailLimit = 1000

    /// Zarys skryptu okna SQL (D199) — elementy `parseScriptOutline`.
    public static func parseScript(_ text: String, controlFlow: Bool = false) -> [OutlineNode] {
        parseScriptOutline(text, controlFlow: controlFlow).nodes
    }

    /// Zarys skryptu okna SQL (D199) według podziału na polecenia (`ScriptSplitter`, jak przy wykonaniu): każde polecenie
    /// PL/SQL (`CREATE` jednostki, blok anonimowy) parsowane osobno — niedokończony blok albo błąd składni nie zabiera
    /// reszty skryptu; polecenia SQL (zapytania, DML, DDL) jako elementy `.statement`. Nazwa polecenia to pierwsze słowo
    /// po komentarzach (jak w tekście — klik zaznacza je w edytorze), szczegóły — dalszy początek polecenia (najwyżej
    /// `statementDetailLimit` znaków, z liniami i wcięciami, komentarze zastąpione odstępem). Tekst leksowany raz.
    /// `isCancelled` — przerwanie analizy w tle (wynik wtedy niepełny, do odrzucenia).
    public static func parseScriptOutline(_ text: String, statementLimit: Int = scriptStatementLimit, controlFlow: Bool = false,
                                          isCancelled: () -> Bool = { false }) -> ScriptOutline {
        let ns = text as NSString
        // Tekst tokenów tylko tam, gdzie potrzebny (polecenia PL/SQL, początek polecenia SQL) — skrypt z dziesiątkami
        // tysięcy poleceń bez milionów podciągów.
        // Anulowanie sprawdzane między fazami (leksowanie i podział to łącznie kilkadziesiąt ms w Release dla 50 000 linii).
        let all = significant(text)
        if isCancelled() { return ScriptOutline(nodes: []) }
        let statements = ScriptSplitter.split(text).filter { $0.end > $0.start }
        if isCancelled() { return ScriptOutline(nodes: []) }
        let sqlCount = statements.reduce(0) { $0 + ($1.isPLSQL ? 0 : 1) }
        let withSQL = sqlCount <= statementLimit
        var out: [OutlineNode] = []
        var ti = 0
        for (n, s) in statements.enumerated() {
            if n % 256 == 0, isCancelled() { break }
            // Pierwszy token znaczący polecenia (tokeny bez komentarzy, w kolejności tekstu — wskaźnik tylko rośnie).
            while ti < all.count, all[ti].start < s.start { ti += 1 }
            guard ti < all.count, all[ti].start < s.end, s.isPLSQL || withSQL else { continue }
            let first = tok(all[ti], ns)
            if s.isPLSQL {
                var j = ti
                while j < all.count, all[j].start < s.fullEnd { j += 1 }
                var p = Parser(t: withoutDirectives(all[ti..<j].map { tok($0, ns) }), i: 0, length: min(s.end, ns.length), source: ns,
                               controlFlow: controlFlow)
                let units = p.parseTop()
                if !units.isEmpty { out += units; continue }
            }
            // Szczegóły: tokeny za pierwszym słowem do końca polecenia (bez „;”) — odstępy jak w tekście, komentarz
            // zastąpiony odstępem albo końcem linii.
            var detail = ""
            var length = 0
            var prevEnd = first.end
            var k = ti + 1
            while k < all.count, all[k].start < s.end {
                let t = all[k]
                if length + (t.start - prevEnd) + t.length > statementDetailLimit { detail += "…"; break }
                if length > 0, t.start > prevEnd {
                    let gap = ns.substring(with: NSRange(location: prevEnd, length: t.start - prevEnd))
                    // Komentarz w odstępie: koniec linii z wcięciem następnej linii albo spacja.
                    let sep = gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? gap
                        : gap.lastIndex(where: \.isNewline).map { "\n" + gap[gap.index(after: $0)...].prefix(while: { $0 == " " || $0 == "\t" }) } ?? " "
                    detail += sep
                    length += (sep as NSString).length
                }
                detail += ns.substring(with: NSRange(location: t.start, length: t.length))
                length += t.length
                prevEnd = t.start + t.length
                k += 1
            }
            out.append(OutlineNode(kind: .statement, name: first.text, detail: detail, range: s.start..<max(s.fullEnd, s.end), nameOffset: first.start))
        }
        return ScriptOutline(nodes: markVisibility(out), omittedStatements: withSQL ? 0 : sqlCount)
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
        func isSkipped(_ k: OutlineNode.Kind) -> Bool { skipped.contains(k) || k.isControlFlow }
        return roots.map { r in
            var r = r
            switch r.kind {
            case .package, .type:
                r.children = r.children.map { var c = $0; if !isSkipped(c.kind) { c.isPublic = true }; return c }
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
                    guard !isSkipped(c.kind) else { return c }
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
    /// Struktury sterujące (zarys z `controlFlow`) są przezroczyste — ścieżka jak w zarysie bez nich.
    public static func path(at offset: Int, in nodes: [OutlineNode]) -> [OutlineNode] {
        var out: [OutlineNode] = []
        var level = nodes
        while let n = level.first(where: { ($0.isContainer || $0.kind.isControlFlow) && $0.range.contains(offset) }) {
            if n.isContainer { out.append(n) }
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
        /// Struktury sterujące w zarysie (D203); bez nich ich dzieci trafiają do elementu nadrzędnego.
        var controlFlow = false
        /// Otwarte bloki i struktury (BLOCK, EXC, IF, LOOP, CASE) — do dopasowania END i gałęzi niedokończonych struktur.
        var open: [String] = []

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
                let begin = t[i]
                let b = parseBlockBody(allowDeclare: false)
                emit(OutlineNode(kind: .beginSection, name: begin.upper, range: begin.start..<b.end, nameOffset: begin.start, children: b.children),
                     &node.children)
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
                    while let k = peek(), k.kind != .semicolon, !(["IS", "AS", "AUTHID", "ACCESSIBLE"] + PLSQLOutline.functionOptions).contains(k.upper),
                          !Self.declarationStops.contains(k.upper) {
                        if first == nil { first = k }
                        last = k
                        i += 1
                    }
                    if let a = first, let b = last { node.detail = text(from: a, to: b) }
                }
            }
            // ACCESSIBLE BY (PACKAGE a, FUNCTION b) — słowa podprogramów w nawiasie nie kończą nagłówka.
            var depth = 0
            while let k = peek(), k.kind != .semicolon, !["IS", "AS"].contains(k.upper), !(depth == 0 && Self.declarationStops.contains(k.upper)) {
                if k.kind == .leftParen { depth += 1 } else if k.kind == .rightParen { depth = max(0, depth - 1) }
                i += 1
            }
            // Deklaracja bez średnika przed następnym podprogramem albo blokiem (pisany kod) — kończy się przed nim.
            if let k = peek(), Self.declarationStops.contains(k.upper) {
                node.range = start..<previousEnd
                return node
            }
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
                if k.kind == .slash || k.upper == "CREATE" { break }
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
                    while let c = peek(), c.kind != .semicolon, !(d == 0 && c.upper == "IS"), !Self.declarationStops.contains(c.upper) {
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
                        while let d = peek(), d.kind != .semicolon, d.upper != ":=", d.upper != "DEFAULT", !Self.declarationStops.contains(d.upper) {
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
        /// Słowa, przed którymi kończy się deklaracja bez średnika (pisany kod): nagłówek następnego podprogramu,
        /// początek bloku, następna jednostka.
        static let declarationStops: Set<String> = ["PROCEDURE", "FUNCTION", "BEGIN", "CREATE"]

        mutating func skipStatement() -> Int {
            var depth = 0
            while let k = peek() {
                if Self.declarationStops.contains(k.upper) { return previousEnd }
                if k.kind == .leftParen { depth += 1 }
                if k.kind == .rightParen { depth -= 1 }
                i += 1
                if depth <= 0, k.kind == .semicolon { return k.end }
            }
            return length
        }

        // MARK: Bloki i struktury sterujące (D203)

        /// Koniec ostatniego przeczytanego tokenu — koniec struktury niedokończonej przed granicą.
        var previousEnd: Int { i > 0 ? t[i - 1].end : (peek()?.start ?? length) }

        /// Element do listy dzieci: struktura sterująca tylko z `controlFlow`, inaczej jej dzieci (bloki zagnieżdżone).
        func emit(_ n: OutlineNode, _ out: inout [OutlineNode]) {
            if controlFlow || !n.kind.isControlFlow { out.append(n) } else { out += n.children }
        }

        /// Słowo kończące albo dzielące strukturę na początku instrukcji: END [IF|LOOP|CASE], ELSIF, ELSE, WHEN, EXCEPTION.
        func closer() -> String? {
            guard let k = peek() else { return nil }
            switch k.upper {
            case "END":
                if let n = peek(1), ["IF", "LOOP", "CASE"].contains(n.upper) { return "END " + n.upper }
                return "END"
            case "ELSIF", "ELSE", "WHEN", "EXCEPTION": return k.upper
            default: return nil
            }
        }

        /// Czy otwarta struktura (`open`) obsługuje słowo `closer`.
        static func accepts(_ open: String, _ closer: String) -> Bool {
            switch open {
            case "BLOCK": closer == "END" || closer == "EXCEPTION"
            case "EXC": closer == "WHEN"
            case "IF": closer == "ELSIF" || closer == "ELSE" || closer == "END IF"
            case "LOOP": closer == "END LOOP"
            case "CASE": closer == "WHEN" || closer == "ELSE" || closer == "END CASE"
            default: false
            }
        }

        /// Słowo należy do struktury zewnętrznej — bieżąca jest niedokończona (np. brak END IF przed END bloku).
        func belongsOutside(_ c: String) -> Bool { open.dropLast().contains { Self.accepts($0, c) } }

        /// Granica jednostki na początku instrukcji: `/`, CREATE, nagłówek następnego podprogramu — kończy wszystkie
        /// otwarte struktury (niedokończony podprogram nie zabiera następnych).
        func atBoundary() -> Bool {
            guard let k = peek() else { return true }
            if k.kind == .slash { return true }
            switch k.upper {
            case "CREATE", "PROCEDURE", "FUNCTION": return true
            default:
                guard PLSQLOutline.methodModifiers.contains(k.upper) else { return false }
                var j = i
                while j < t.count, PLSQLOutline.methodModifiers.contains(t[j].upper) { j += 1 }
                return j < t.count && ["PROCEDURE", "FUNCTION"].contains(t[j].upper)
            }
        }

        /// Etykieta po END (END nazwa;, END LOOP etykieta;): identyfikator albo słowo kluczowe przed średnikiem.
        mutating func skipEndLabel() {
            guard let n = peek() else { return }
            if n.kind == .identifier || n.kind == .quotedIdentifier { i += 1; return }
            if n.kind == .keyword, peek(1)?.kind == .semicolon, closer() == nil { i += 1 }
        }

        /// Zamknięcie struktury (słowa END …, etykieta, średnik) — zwraca koniec.
        mutating func closeStructure(words: Int) -> Int {
            i += words
            skipEndLabel()
            var end = t[i - 1].end
            if let s = peek(), s.kind == .semicolon { end = s.end; i += 1 }
            return end
        }

        /// Słowo bez dopasowania (END IF bez IF, ELSE poza IF i CASE) — pomijane razem z etykietą i średnikiem.
        mutating func skipStray(_ c: String) {
            if c.hasPrefix("END") { _ = closeStructure(words: c == "END" ? 1 : 2) } else { i += 1 }
        }

        /// Słowa, przed którymi kończy się instrukcja bez średnika i nagłówek struktury (pisany kod).
        static let statementStops: Set<String> = ["BEGIN", "DECLARE", "IF", "ELSIF", "EXCEPTION", "CREATE"]

        /// Nagłówek struktury (warunek, zakres pętli, wybór CASE) do jednego ze słów `until` poza nawiasami
        /// i wyrażeniami CASE; `consume` — wskaźnik za słowem. nil — brak słowa przed końcem instrukcji (wskaźnik bez zmian).
        mutating func header(until words: Set<String>, consume: Bool = true) -> (first: Tok?, last: Tok?)? {
            var j = i
            var depth = 0
            var caseDepth = 0
            var first: Tok?, last: Tok?
            while j < t.count {
                let k = t[j]
                if k.kind == .semicolon { return nil }
                if k.kind == .leftParen { depth += 1 } else if k.kind == .rightParen { depth = max(0, depth - 1) }
                else if k.upper == "CASE" { caseDepth += 1 }
                else if k.upper == "END" { if caseDepth > 0 { caseDepth -= 1 } else { return nil } }
                else if caseDepth == 0 {
                    if depth == 0, words.contains(k.upper) { i = consume ? j + 1 : j; return (first, last) }
                    if Self.statementStops.contains(k.upper) { return nil }
                    // Gałąź struktury zewnętrznej (pisany kod: brak THEN/LOOP przed ELSE albo WHEN).
                    if depth == 0, k.upper == "ELSE" || k.upper == "WHEN" { return nil }
                }
                if first == nil { first = k }
                last = k
                j += 1
            }
            return nil
        }

        /// Instrukcja bez struktury (przypisanie, wywołanie, SQL) do średnika; wyrażenia CASE … END w środku;
        /// bez średnika — do END albo słowa z `statementStops` (pisany kod), a także przed ELSE i WHEN gałęzi
        /// struktury — poza instrukcjami, w których te słowa są częścią SQL albo instrukcji (INSERT ALL/FIRST … WHEN …
        /// ELSE, MERGE … WHEN, EXIT/CONTINUE … WHEN). Zawsze co najmniej jeden token.
        mutating func skipSimpleStatement() {
            let first = peek()?.upper ?? ""
            let stopsAtElse = first != "INSERT"
            let stopsAtWhen = !["INSERT", "MERGE", "EXIT", "CONTINUE"].contains(first)
            // Pusta instrukcja (sam średnik, np. po pominiętej dyrektywie).
            if peek()?.kind == .semicolon { i += 1; return }
            i += 1
            var caseDepth = 0
            while let k = peek() {
                if k.kind == .semicolon { i += 1; return }
                if k.upper == "CASE" { caseDepth += 1 }
                else if k.upper == "END" { if caseDepth > 0 { caseDepth -= 1 } else { return } }
                else if caseDepth == 0 {
                    if Self.statementStops.contains(k.upper) { return }
                    if (k.upper == "ELSE" && stopsAtElse) || (k.upper == "WHEN" && stopsAtWhen) { return }
                }
                i += 1
            }
        }

        /// Element struktury: słowo otwierające jako nazwa, nagłówek w szczegółach (białe znaki zwinięte, najwyżej
        /// `statementDetailLimit` znaków).
        func control(_ kind: OutlineNode.Kind, _ kw: Tok, _ h: (first: Tok?, last: Tok?)?, label: String? = nil) -> OutlineNode {
            var detail = ""
            if let a = h?.first, let b = h?.last, b.end > a.start {
                let limit = PLSQLOutline.statementDetailLimit
                let end = min(b.end, a.start + limit * 2)
                detail = source.substring(with: NSRange(location: a.start, length: end - a.start))
                    .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                if detail.count > limit || end < b.end { detail = String(detail.prefix(limit)) + "…" }
            }
            var n = OutlineNode(kind: kind, name: kw.upper, detail: detail, range: kw.start..<kw.end, nameOffset: kw.start)
            n.label = label
            return n
        }

        /// Etykieta `<<nazwa>>` przed strukturą: nazwa i początek `<<` (początek zakresu struktury).
        typealias Label = (name: String, start: Int)

        /// Instrukcje do słowa kończącego strukturę (END…, ELSIF, ELSE, WHEN, EXCEPTION), granicy jednostki albo końca
        /// tekstu: struktury sterujące (`emit`) i bloki zagnieżdżone; etykieta `<<nazwa>>` trafia do następnej struktury.
        mutating func statements() -> [OutlineNode] {
            var out: [OutlineNode] = []
            var label: Label?
            while let k = peek() {
                if closer() != nil || atBoundary() { break }
                if k.upper == "<<" {
                    i += 1
                    if let n = peek(), n.upper != ">>", n.kind == .identifier || n.kind == .quotedIdentifier || n.kind == .keyword {
                        // Kilka etykiet z rzędu — nazwa ostatniej, zakres od pierwszej.
                        label = (n.kind == .quotedIdentifier ? String(n.text.dropFirst().dropLast()) : n.text, label?.start ?? k.start)
                        i += 1
                    }
                    if isWord(0, ">>") { i += 1 }
                    continue
                }
                let lbl = label
                label = nil
                switch k.upper {
                case "DECLARE", "BEGIN":
                    let inner = parseBlockBody(allowDeclare: true)
                    var node = OutlineNode(kind: .block, name: "BEGIN", range: (lbl?.start ?? k.start)..<inner.end, nameOffset: k.start,
                                           children: inner.children)
                    node.label = lbl?.name
                    out.append(node)
                case "IF":
                    if let n = parseIf(label: lbl) { emit(n, &out) } else { skipSimpleStatement() }
                case "LOOP", "FOR", "WHILE":
                    if let n = parseLoop(label: lbl) { emit(n, &out) } else { skipSimpleStatement() }
                case "CASE":
                    if let n = parseCaseStatement(label: lbl) { emit(n, &out) } else { skipSimpleStatement() }
                case "FORALL":
                    let save = i
                    i += 1
                    if let h = header(until: ["INSERT", "UPDATE", "DELETE", "MERGE", "EXECUTE"], consume: false) {
                        var n = control(.forall, k, h, label: lbl?.name)
                        skipSimpleStatement()
                        n.range = (lbl?.start ?? k.start)..<previousEnd
                        emit(n, &out)
                    } else {
                        i = save
                        skipSimpleStatement()
                    }
                default:
                    skipSimpleStatement()
                }
            }
            return out
        }

        /// IF warunek THEN … [ELSIF warunek THEN …] [ELSE …] END IF; — gałęzie ELSIF i ELSE jako dzieci. nil — bez THEN
        /// przed końcem instrukcji (pisany kod: instrukcja zwykła).
        mutating func parseIf(label: Label?) -> OutlineNode? {
            let kw = t[i]
            let start = label?.start ?? kw.start
            let save = i
            i += 1
            guard let h = header(until: ["THEN"]) else { i = save; return nil }
            var node = control(.ifStatement, kw, h, label: label?.name)
            open.append("IF")
            defer { open.removeLast() }
            var children = statements()
            var branch: OutlineNode?
            var branchChildren: [OutlineNode] = []
            func finish(_ end: Int) {
                guard var b = branch else { return }
                b.range = b.range.lowerBound..<max(b.range.upperBound, end)
                b.children = branchChildren
                emit(b, &children)
                branch = nil
                branchChildren = []
            }
            while true {
                if peek() == nil { finish(length); node.range = start..<length; break }
                guard !atBoundary(), let c = closer() else { finish(previousEnd); node.range = start..<previousEnd; break }
                if c == "ELSIF" || c == "ELSE" {
                    finish(previousEnd)
                    let b = t[i]
                    i += 1
                    let h = c == "ELSE" ? nil : header(until: ["THEN"])
                    branch = control(c == "ELSE" ? .elseBranch : .elsifBranch, b, h)
                    branchChildren = statements()
                    continue
                }
                if c == "END IF" {
                    finish(previousEnd)
                    node.range = start..<closeStructure(words: 2)
                    break
                }
                if belongsOutside(c) { finish(previousEnd); node.range = start..<previousEnd; break }
                skipStray(c)
                if branch == nil { children += statements() } else { branchChildren += statements() }
            }
            node.children = children
            return node
        }

        /// LOOP …, FOR … LOOP …, WHILE … LOOP … END LOOP [etykieta]; nil — FOR/WHILE bez LOOP (instrukcja zwykła).
        mutating func parseLoop(label: Label?) -> OutlineNode? {
            let kw = t[i]
            let start = label?.start ?? kw.start
            let save = i
            i += 1
            var h: (first: Tok?, last: Tok?)?
            if kw.upper != "LOOP" {
                guard let x = header(until: ["LOOP"]) else { i = save; return nil }
                h = x
            }
            var node = control(.loop, kw, h, label: label?.name)
            open.append("LOOP")
            defer { open.removeLast() }
            var children = statements()
            while true {
                if peek() == nil { node.range = start..<length; break }
                guard !atBoundary(), let c = closer() else { node.range = start..<previousEnd; break }
                if c == "END LOOP" { node.range = start..<closeStructure(words: 2); break }
                if belongsOutside(c) { node.range = start..<previousEnd; break }
                skipStray(c)
                children += statements()
            }
            node.children = children
            return node
        }

        /// Instrukcja CASE [wybór] WHEN … THEN … [ELSE …] END CASE; (wyrażenie CASE … END w instrukcji pomija
        /// `skipSimpleStatement`). Gałęzie WHEN i ELSE jako dzieci. nil — bez WHEN (instrukcja zwykła).
        mutating func parseCaseStatement(label: Label?) -> OutlineNode? {
            let kw = t[i]
            let start = label?.start ?? kw.start
            let save = i
            i += 1
            guard let h = header(until: ["WHEN"], consume: false) else { i = save; return nil }
            var node = control(.caseStatement, kw, h, label: label?.name)
            open.append("CASE")
            defer { open.removeLast() }
            var children = statements()
            var branch: OutlineNode?
            var branchChildren: [OutlineNode] = []
            func finish(_ end: Int) {
                guard var b = branch else { return }
                b.range = b.range.lowerBound..<max(b.range.upperBound, end)
                b.children = branchChildren
                emit(b, &children)
                branch = nil
                branchChildren = []
            }
            while true {
                if peek() == nil { finish(length); node.range = start..<length; break }
                guard !atBoundary(), let c = closer() else { finish(previousEnd); node.range = start..<previousEnd; break }
                if c == "WHEN" || c == "ELSE" {
                    finish(previousEnd)
                    let b = t[i]
                    i += 1
                    let h = c == "ELSE" ? nil : header(until: ["THEN"])
                    branch = control(c == "ELSE" ? .elseBranch : .whenBranch, b, h)
                    branchChildren = statements()
                    continue
                }
                if c == "END CASE" {
                    finish(previousEnd)
                    node.range = start..<closeStructure(words: 2)
                    break
                }
                if belongsOutside(c) { finish(previousEnd); node.range = start..<previousEnd; break }
                skipStray(c)
                if branch == nil { children += statements() } else { branchChildren += statements() }
            }
            node.children = children
            return node
        }

        /// Sekcja EXCEPTION bloku: obsługi WHEN wyjątek [OR wyjątek] THEN … do END bloku.
        mutating func parseExceptionSection() -> OutlineNode {
            let kw = t[i]
            i += 1
            open.append("EXC")
            defer { open.removeLast() }
            var section = OutlineNode(kind: .exceptionSection, name: kw.upper, range: kw.start..<kw.end, nameOffset: kw.start)
            var children = statements()
            var handler: OutlineNode?
            var handlerChildren: [OutlineNode] = []
            func finish(_ end: Int) {
                guard var h = handler else { return }
                h.range = h.range.lowerBound..<max(h.range.upperBound, end)
                h.children = handlerChildren
                emit(h, &children)
                handler = nil
                handlerChildren = []
            }
            var end = length
            while true {
                if peek() == nil { finish(length); break }
                guard !atBoundary(), let c = closer() else { end = previousEnd; finish(end); break }
                if c == "WHEN" {
                    finish(previousEnd)
                    let w = t[i]
                    i += 1
                    let h = header(until: ["THEN"])
                    handler = control(.exceptionHandler, w, h)
                    handlerChildren = statements()
                    continue
                }
                if belongsOutside(c) { end = previousEnd; finish(end); break }
                skipStray(c)
                if handler == nil { children += statements() } else { handlerChildren += statements() }
            }
            section.range = kw.start..<max(kw.end, end)
            section.children = children
            return section
        }

        /// Blok [DECLARE …] BEGIN … [EXCEPTION …] END [nazwa]; — bloki zagnieżdżone (DECLARE/BEGIN) jako dzieci,
        /// struktury sterujące (`emit`); END IF/END LOOP/END CASE nie kończą bloku. Niedokończony blok kończy się na
        /// granicy jednostki (`atBoundary`) albo przed słowem struktury zewnętrznej.
        mutating func parseBlockBody(allowDeclare: Bool) -> (children: [OutlineNode], end: Int) {
            var children: [OutlineNode] = []
            if allowDeclare, isWord(0, "DECLARE") {
                i += 1
                children += parseDeclarations(untilEnd: false)
            }
            guard isWord(0, "BEGIN") else { return (children, peek()?.start ?? length) }
            i += 1
            open.append("BLOCK")
            defer { open.removeLast() }
            children += statements()
            while true {
                guard peek() != nil else { return (children, length) }
                guard !atBoundary(), let c = closer() else { return (children, previousEnd) }
                switch c {
                case "END":
                    return (children, closeStructure(words: 1))
                case "EXCEPTION":
                    let section = parseExceptionSection()
                    emit(section, &children)
                default:
                    if belongsOutside(c) { return (children, previousEnd) }
                    skipStray(c)
                }
                children += statements()
            }
        }

        /// Ciało wyzwalacza złożonego: deklaracje wspólne, punkty czasowe `BEFORE STATEMENT IS BEGIN … END BEFORE
        /// STATEMENT;` (z `controlFlow` — elementy `timingPoint`), na końcu END [nazwa];
        mutating func parseCompoundBody() -> (children: [OutlineNode], end: Int) {
            var children: [OutlineNode] = []
            while let k = peek() {
                if ["BEFORE", "AFTER", "INSTEAD"].contains(k.upper) {
                    // Nazwa punktu: słowo otwierające i dalsze słowa do IS (STATEMENT, EACH ROW, OF EACH ROW).
                    let first = i
                    var last = i
                    i += 1
                    while let s = peek(), s.upper != "IS", s.upper != "BEGIN", s.upper != "END", s.kind != .semicolon, s.kind != .slash {
                        last = i
                        i += 1
                    }
                    if isWord(0, "IS") { i += 1 }
                    guard isWord(0, "BEGIN") else {
                        if peek()?.kind == .semicolon { i += 1 }
                        continue
                    }
                    var node = control(.timingPoint, k, last > first ? (t[first + 1], t[last]) : nil)
                    let body = parseBlockBody(allowDeclare: false)
                    // END punkt_czasowy; — słowa punktu po END.
                    if t[i - 1].kind != .semicolon {
                        while let s = peek(), s.kind != .semicolon, s.kind != .slash { i += 1 }
                        if peek()?.kind == .semicolon { i += 1 }
                    }
                    node.range = k.start..<max(body.end, previousEnd)
                    node.children = body.children
                    emit(node, &children)
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
