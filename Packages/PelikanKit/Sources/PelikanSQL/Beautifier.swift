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
    /// Układ klauzul SQL (FROM, WHERE…): słowa do lewej z elementami w kolumnie, słowa do prawej („rzeka”: słowa
    /// kończą się w kolumnie SELECT) albo słowo w osobnej linii i elementy wcięte pod nim.
    public enum ClauseLayout: String, Sendable, Codable, Hashable, CaseIterable { case leftAligned, rightAligned, ownLine }
    /// AND/OR warunków na początku nowej linii albo na końcu poprzedniej.
    public enum OperatorPosition: String, Sendable, Codable, Hashable, CaseIterable { case lineStart, lineEnd }
    /// Wyrażenie CASE w jednej linii albo WHEN/ELSE/END w osobnych liniach.
    public enum CaseLayout: String, Sendable, Codable, Hashable, CaseIterable { case inline, multiline }

    public var indent = 2
    public var useTabs = false
    public var rightMargin = 100
    public var keywordCase: WordCase = .upper
    public var identifierCase: WordCase = .unchanged
    public var listLayout: ListLayout = .onePerLine
    /// Przecinek na początku kolejnej linii listy zamiast na końcu poprzedniej.
    public var commaBefore = false
    /// Osobne reguły list (UG 29.2): deklaracje parametrów podprogramów, parametry wywołań w PL/SQL, listy kolumn
    /// i wartości INSERT — do marginesu albo element w linii (wyrównany za nawiasem).
    public var parameterDeclarations: ListLayout = .fit
    public var callParameters: ListLayout = .fit
    public var insertLists: ListLayout = .fit
    /// Zachowanie pojedynczych pustych linii między instrukcjami (więcej pustych linii — jedna).
    public var keepBlankLines = true
    /// Najwięcej pustych linii z rzędu zachowanych ze źródła (przy `keepBlankLines`).
    public var maxBlankLines = 1
    /// Pusta linia przed każdym podprogramem w pakiecie i sekcji deklaracji.
    public var blankLineBetweenSubprograms = false

    // Klauzule i łamanie linii
    public var clauseLayout: ClauseLayout = .leftAligned
    public var andOrPosition: OperatorPosition = .lineStart
    /// JOIN … ON: warunek złączenia w nowej linii (wcięty) albo w linii JOIN.
    public var joinConditionOnNewLine = true
    /// IF/ELSIF … THEN: THEN w osobnej linii.
    public var thenOnNewLine = false
    public var caseLayout: CaseLayout = .inline

    // Odstępy
    /// Spacje wokół operatorów (=, <>, +, ||…); `:=` i `=>` zawsze ze spacjami.
    public var spaceAroundOperators = true
    public var spaceAfterComma = true
    /// Spacja po „(” i przed „)”.
    public var spaceInsideParentheses = false

    // Wyrównanie (UG 29.2 i formatery SQL Developer, Toad, Trivadis)
    /// Deklaracje zmiennych i stałych: typy i `:=`/DEFAULT w kolumnach.
    public var alignDeclarations = false
    /// Parametry podprogramów w osobnych liniach: tryb (IN/OUT), typ i DEFAULT w kolumnach.
    public var alignParameters = false
    /// Parametry nazwane wywołań w osobnych liniach: `=>` w kolumnie.
    public var alignNamedArguments = false
    /// Kolejne przypisania: `:=` w kolumnie.
    public var alignAssignments = false
    /// Aliasy kolumn i tabel w listach SELECT i FROM w osobnych liniach.
    public var alignAliases = false
    /// UPDATE … SET w osobnych liniach: `=` w kolumnie.
    public var alignSetValues = false
    /// Komentarze na końcu kolejnych linii w jednej kolumnie.
    public var alignTrailingComments = false

    // Wielkość liter grup słów (nil — jak słowa kluczowe dla typów, jak identyfikatory dla funkcji i pakietów)
    public var dataTypeCase: WordCase?
    public var functionCase: WordCase?
    public var packageCase: WordCase?

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
        parameterDeclarations = v(.parameterDeclarations, parameterDeclarations); callParameters = v(.callParameters, callParameters)
        insertLists = v(.insertLists, insertLists)
        maxBlankLines = v(.maxBlankLines, maxBlankLines); blankLineBetweenSubprograms = v(.blankLineBetweenSubprograms, blankLineBetweenSubprograms)
        clauseLayout = v(.clauseLayout, clauseLayout); andOrPosition = v(.andOrPosition, andOrPosition)
        joinConditionOnNewLine = v(.joinConditionOnNewLine, joinConditionOnNewLine); thenOnNewLine = v(.thenOnNewLine, thenOnNewLine)
        caseLayout = v(.caseLayout, caseLayout)
        spaceAroundOperators = v(.spaceAroundOperators, spaceAroundOperators); spaceAfterComma = v(.spaceAfterComma, spaceAfterComma)
        spaceInsideParentheses = v(.spaceInsideParentheses, spaceInsideParentheses)
        alignDeclarations = v(.alignDeclarations, alignDeclarations); alignParameters = v(.alignParameters, alignParameters)
        alignNamedArguments = v(.alignNamedArguments, alignNamedArguments); alignAssignments = v(.alignAssignments, alignAssignments)
        alignAliases = v(.alignAliases, alignAliases); alignSetValues = v(.alignSetValues, alignSetValues)
        alignTrailingComments = v(.alignTrailingComments, alignTrailingComments)
        dataTypeCase = v(.dataTypeCase, dataTypeCase); functionCase = v(.functionCase, functionCase); packageCase = v(.packageCase, packageCase)
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
        let out = unchecked(text, options: options)
        try verify(original: text, formatted: out)
        return out
    }

    static func unchecked(_ text: String, options: BeautifierOptions) -> String {
        var f = Formatter(source: text as NSString, options: options)
        return f.run()
    }

    /// Formatowanie fragmentu (zaznaczenia): całe linie, wcięcie pierwszej linii zachowane jako bazowe.
    public static func format(_ text: String, range: Range<Int>, options: BeautifierOptions = BeautifierOptions()) throws -> (text: String, range: Range<Int>) {
        let ns = text as NSString
        let lines = ns.lineRange(for: NSRange(location: range.lowerBound, length: max(0, range.count - (range.count > 0 && range.upperBound <= ns.length && range.upperBound > 0 && ns.character(at: range.upperBound - 1) == 0x0A ? 1 : 0))))
        let fragment = ns.substring(with: lines)
        let base = String(fragment.prefix { $0 == " " || $0 == "\t" })
        var formatted = indented(unchecked(fragment, options: options), base: base)
        if fragment.hasSuffix("\n"), !formatted.hasSuffix("\n") { formatted += "\n" }
        if !fragment.hasSuffix("\n"), formatted.hasSuffix("\n") { formatted.removeLast() }
        // Sprawdzenie po doklejeniu wcięcia — wynik trafia do dokumentu dokładnie w tej postaci.
        try verify(original: fragment, formatted: formatted)
        let result = ns.replacingCharacters(in: lines, with: formatted)
        return (result, lines.location..<(lines.location + (formatted as NSString).length))
    }

    /// Wcięcie bazowe zaznaczenia doklejane do linii wyniku — bez linii zaczynających się wewnątrz wieloliniowego
    /// literału, identyfikatora w cudzysłowie albo komentarza (to byłaby zmiana danych, nie układu).
    static func indented(_ text: String, base: String) -> String {
        guard !base.isEmpty else { return text }
        let ns = text as NSString
        var inside = Set<Int>()
        for t in Lexer(text).tokenize() where [.string, .quotedIdentifier, .blockComment, .hint].contains(t.kind) {
            for p in t.start..<t.end where ns.character(at: p) == 0x0A { inside.insert(p + 1) }
        }
        var out: [String] = []
        var pos = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            out.append(line.isEmpty || inside.contains(pos) ? String(line) : base + line)
            pos += line.utf16.count + 1
        }
        return out.joined(separator: "\n")
    }

    /// Porównanie tokenów (bez białych znaków; słowa bez cudzysłowu bez rozróżniania wielkości liter), podziału na
    /// polecenia skryptu (`;`, `/` sam w linii) i poleceń SQL*Plus — te porównywane jako cały tekst linii.
    public static func verify(original: String, formatted: String) throws {
        let a = signature(original), b = signature(formatted)
        func shown(_ x: String) -> String { String(x.drop { $0 != ":" }.dropFirst().prefix(30)) }
        if a.items != b.items {
            let i = (0..<min(a.items.count, b.items.count)).first { a.items[$0] != b.items[$0] } ?? min(a.items.count, b.items.count)
            var what = i < a.items.count ? shown(a.items[i]) : "EOF"
            if what.isEmpty, i < b.items.count { what = shown(b.items[i]) }
            throw BeautifierError.unsafe(what)
        }
        // Tokeny sklejone w źródle, których rozdzielenie mogłoby zmienić znaczenie (np. nieznana lekserowi konstrukcja
        // złożona z kilku znaków), muszą zostać sklejone.
        for i in a.items.indices where a.mustGlue[i] && !b.glued[i] {
            throw BeautifierError.unsafe(shown(a.items[i - 1]) + shown(a.items[i]))
        }
    }

    /// Sygnatura tekstu dla `verify`: polecenia wg ScriptSplitter w trybie Command Window (granice poleceń zależą
    /// od układu linii — `/` sam w linii kończy blok, polecenie SQL*Plus kończy koniec linii), w każdym tokeny bez
    /// białych znaków; polecenie SQL*Plus jako cały tekst (wielkość liter i podział linii mają w nim znaczenie).
    /// Dla każdego elementu: czy jest sklejony z poprzednim (bez białego znaku) i czy musi taki zostać.
    struct Signature {
        var items: [String] = []
        var glued: [Bool] = []
        var mustGlue: [Bool] = []
        mutating func append(_ s: String, glued g: Bool = false, must: Bool = false) {
            items.append(s); glued.append(g); mustGlue.append(must)
        }
    }

    static func signature(_ s: String) -> Signature {
        let text = Array(s.utf16)
        var out = Signature()
        func lex(_ from: Int, _ to: Int) {
            guard from < to else { return }
            let lexer = Lexer(utf16: Array(text[from..<to]))
            var prev: (kind: TokenKind, text: String, end: Int)?
            for t in lexer.tokenize() where t.kind != .whitespace && t.kind != .newline {
                let x = lexer.string(t)
                let glued = prev.map { $0.end == t.start } ?? false
                let must = glued && prev.map { !separable($0.kind, $0.text, t.kind, x) } == true
                switch t.kind {
                case .comma where out.items.last?.hasPrefix("c:") == true:
                    // Przecinek za komentarzem `--` jest równoważny przecinkowi przed nim (`a -- k\n, b` ≡ `a, -- k\n b`):
                    // formater może przenieść przecinek na tę stronę komentarza, po której stoi element.
                    var k = out.items.count
                    while k > 0, out.items[k - 1].hasPrefix("c:") { k -= 1 }
                    out.items.insert("\(t.kind.rawValue):,", at: k)
                    out.glued.insert(false, at: k)
                    out.mustGlue.insert(false, at: k)
                case .identifier, .keyword: out.append("w:" + x.uppercased(), glued: glued, must: must)
                case .lineComment: out.append("c:" + x.trimmingCharacters(in: .whitespaces), glued: glued, must: must)
                default: out.append("\(t.kind.rawValue):" + x, glued: glued, must: must)
                }
                prev = (t.kind, x, t.end)
            }
        }
        var pos = 0
        for st in ScriptSplitter.split(s, mode: .commandWindow) where st.start >= pos {
            lex(pos, st.start)
            if st.sqlplusCommand != nil {
                out.append("sqlplus:" + String(st.text.reversed().drop { $0 == " " || $0 == "\t" }.reversed()))
            } else {
                lex(st.start, st.end)
            }
            lex(st.end, st.fullEnd)
            out.append("|:")
            pos = st.fullEnd
        }
        lex(pos, text.count)
        return out
    }

    /// Operatory, które Oracle czyta jako całość i które można oddzielić spacją od sąsiadów.
    static let standaloneOperators: Set<String> = [
        ":=", "=>", "||", "**", "..", "<>", "!=", "^=", "~=", "<=", ">=", "<=>", "<->", "<#>", "=", "<", ">", "+", "-", "*",
        "<<", ">>", "?",
    ]

    /// Czy tokeny sklejone w źródle (`a` tuż przed `b`) można rozdzielić białym znakiem bez zmiany znaczenia.
    /// Nie wolno: kropki (`t.c`, `&x.`), znaki niebędące samodzielnymi operatorami (`$`, `#`, `@`, `%`, `:`, `!`…),
    /// dwa operatory obok siebie (mogą tworzyć nieznany lekserowi operator, np. `<=>` przed 23ai) — poza minusem i plusem
    /// jednoargumentowym, liczba z jednostką (`1M`), zmienne podstawiania sklejone z tekstem (`&x.y`, `a&x`).
    public static func separable(_ ak: TokenKind, _ a: String, _ bk: TokenKind, _ b: String) -> Bool {
        let free: Set<TokenKind> = [.comma, .semicolon, .leftParen, .rightParen, .lineComment, .blockComment, .hint]
        if free.contains(ak) || free.contains(bk) { return true }
        if ak == .dot || bk == .dot || ak == .unknown || bk == .unknown { return false }
        func isOp(_ k: TokenKind) -> Bool { k == .operator || k == .slash }
        func standalone(_ k: TokenKind, _ s: String) -> Bool { k == .slash || standaloneOperators.contains(s) }
        switch (isOp(ak), isOp(bk)) {
        case (true, true): return standalone(ak, a) && standalone(bk, b) && (b == "-" || b == "+" || b == "?" || a == "?")
        case (true, false): return standalone(ak, a)
        case (false, true): return standalone(bk, b)
        case (false, false):
            let bound: Set<TokenKind> = [.substitution, .jasperParameter, .directive]
            if bound.contains(ak) || bound.contains(bk) { return false }
            return !(ak == .number && (bk == .identifier || bk == .keyword))
        }
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

    /// `branch` — treść gałęzi WHEN … THEN / ELSE obsługi wyjątków i instrukcji CASE (poziom gałęzi + 1).
    enum FrameKind { case unit, declare, block, exception, ifStmt, loop, caseStmt, caseExpr, sql, paren, branch }
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
        /// SQL: pierwsze słowo instrukcji (SELECT, INSERT, MERGE…) i INSERT ALL / FIRST.
        var statement = ""
        var multiInsert = false
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
    /// Rodzaj jednostki CREATE (TYPE dla TYPE BODY — metody MEMBER/STATIC… jak podprogramy).
    var unitKind = ""
    var statementStart = true
    /// Polecenia skryptu (tryb Command Window) — polecenia SQL*Plus i kod Java/JavaScript kopiowane bez zmian.
    let statements: [ScriptStatement]
    /// Początek polecenia SQL*Plus → koniec (UTF-16).
    let sqlplusEnds: [Int: Int]
    /// Linie wyniku skopiowane bez zmian (SQL*Plus, Java/JavaScript, regiony bez formatowania) — bez wyrównywania.
    var rawLines = Set<Int>()
    /// Indeks tokenu `{` otwierającego kod JavaScript w MLE LANGUAGE JAVASCRIPT {{ … }} (kopiowany bez zmian).
    var rawFrom: Int?

    init(source: NSString, options: BeautifierOptions) {
        self.source = source
        self.options = options
        statements = ScriptSplitter.split(source as String, mode: .commandWindow)
        var ends: [Int: Int] = [:]
        for st in statements where st.sqlplusCommand != nil { ends[st.start] = st.end }
        sqlplusEnds = ends
        toks = Self.tokens(source, from: 0)
    }

    /// Tokeny bez białych znaków od pozycji `from` (leksowane od stanu początkowego).
    static func tokens(_ source: NSString, from: Int) -> [Tok] {
        var nl = 0
        var t: [Tok] = []
        Lexer(source as String).scan(range: from..<source.length, state: .normal) { k in
            switch k.kind {
            case .whitespace: break
            case .newline: nl += 1
            default:
                let s = source.substring(with: NSRange(location: k.start, length: k.length))
                t.append(Tok(kind: k.kind, start: k.start, end: k.start + k.length, text: s, upper: s.uppercased(), newlines: nl))
                nl = 0
            }
        }
        return t
    }

    /// Koniec polecenia skryptu zawierającego pozycję (bez terminatora) albo koniec tekstu.
    func statementEnd(containing pos: Int) -> Int {
        statements.first { $0.start <= pos && pos < $0.end }?.end ?? source.length
    }

    /// Fragment źródła kopiowany bez zmian (polecenie SQL*Plus, kod Java/JavaScript): od początku linii, jeśli
    /// przed nim są tylko odstępy, w osobnych liniach (albo w bieżącej — `sameLine`); dalej tokeny od `end`,
    /// leksowane od nowa, gdy token źródła przechodzi przez granicę (np. apostrof w PROMPT).
    mutating func copyRaw(from start: Int, to end: Int, sameLine: Bool = false) {
        var from = start
        if !sameLine {
            let lineStart = source.lineRange(for: NSRange(location: start, length: 0)).location
            let prefix = source.substring(with: NSRange(location: lineStart, length: start - lineStart))
            if prefix.allSatisfy({ $0 == " " || $0 == "\t" }) { from = lineStart }
            sourceBlankLines(toks[i])
        }
        var raw = source.substring(with: NSRange(location: from, length: max(0, end - from))).components(separatedBy: "\n")
        if sameLine, !raw.isEmpty { put(raw.removeFirst(), space: true); rawLines.insert(lines.count) }
        flush()
        rawLines.formUnion(lines.count..<(lines.count + raw.count))
        lines.append(contentsOf: raw)
        pendingBreak = indentColumns(level)
        statementStart = true
        var j = i
        while j < toks.count, toks[j].start < end { j += 1 }
        if j > 0, toks[j - 1].end > end { toks = Array(toks[..<j]) + Self.tokens(source, from: end) }
        i = j - 1
    }

    /// Znaczniki regionu bez formatowania: `-- NoFormat Start/End` (PL/SQL Developer) i `-- @formatter:off/on`.
    static func isFormatMarker(_ t: Tok, start: Bool) -> Bool {
        guard t.kind == .lineComment else { return false }
        let m = t.upper.replacingOccurrences(of: " ", with: "")
        return start ? m.hasPrefix("--NOFORMATSTART") || m.hasPrefix("--@FORMATTER:OFF") : m.hasPrefix("--NOFORMATEND") || m.hasPrefix("--@FORMATTER:ON")
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

    /// Puste linie ze źródła przed tokenem: najwyżej `maxBlankLines` z rzędu.
    mutating func sourceBlankLines(_ t: Tok) {
        guard options.keepBlankLines, t.newlines >= 2 else { return }
        flush()
        guard !lines.isEmpty else { return }
        let wanted = min(t.newlines - 1, max(1, options.maxBlankLines))
        let have = lines.reversed().prefix { $0.isEmpty }.count
        if have < wanted { lines.append(contentsOf: Array(repeating: "", count: wanted - have)) }
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
        let normal = Self.apply(rule(for: t), to: t)
        return Self.specialCasePattern(options.specialCase, word: normal) ?? normal
    }

    /// Pisownia specjalna ze wzorcem `%` albo `*` (UG 29.2, np. `DBA_%`): część stała wzorca w jego pisowni, reszta słowa
    /// według zwykłych reguł. Pierwszy pasujący wzorzec (z jednym znakiem wieloznacznym).
    static func specialCasePattern(_ patterns: [String], word: String) -> String? {
        for p in patterns {
            let parts = p.split(separator: "%", omittingEmptySubsequences: false).flatMap { $0.split(separator: "*", omittingEmptySubsequences: false) }
            guard parts.count == 2 else { continue }
            let prefix = String(parts[0]), suffix = String(parts[1])
            let u = word.uppercased()
            guard u.count >= prefix.count + suffix.count, u.hasPrefix(prefix.uppercased()), u.hasSuffix(suffix.uppercased()) else { continue }
            return prefix + String(word.dropFirst(prefix.count).dropLast(suffix.count)) + suffix
        }
        return nil
    }

    /// Słowa kluczowe, które nawet w pozycji nazwy zostają słowami kluczowymi (wartości, struktura bloku).
    static let keywordValues: Set<String> = [
        "TRUE", "FALSE", "SQLCODE", "SQLERRM", "SYSTIMESTAMP", "CURRENT_DATE", "CURRENT_TIMESTAMP", "LOCALTIMESTAMP",
        "DBTIMEZONE", "SESSIONTIMEZONE", "SELF", "OTHERS", "END", "CASE", "THEN", "ELSE", "LOOP", "IF", "BEGIN", "EXCEPTION",
        "CONNECT_BY_ROOT", "CONNECT_BY_ISLEAF", "NULLS", "FIRST", "LAST", "ROWS", "ONLY",
    ]

    /// Słowo kluczowe niezastrzeżone użyte jako nazwa (wielkość liter jak identyfikator): przy kropce (`h.path`,
    /// `l.DELETE`), etykieta w EXIT/CONTINUE/GOTO/END LOOP, nazwa kolumny albo alias w liście SELECT, element listy
    /// w nawiasie (`(empno, path)`).
    func keywordAsIdentifier(_ t: Tok) -> Bool {
        let p = token(before: t), n = token(after: t)
        if p?.text == "%" { return false }   // atrybut kursora: c%NOTFOUND, SQL%BULK_EXCEPTIONS
        if p?.kind == .dot { return true }
        if n?.kind == .dot, t.upper != "SELF", t.upper != "SQL" { return true }
        if let p, p.isWord, ["EXIT", "CONTINUE", "GOTO"].contains(p.upper), t.upper != "WHEN" { return true }
        if let p, p.upper == "LOOP", token(before: p)?.upper == "END" { return true }
        guard !Keywords.reserved.contains(t.upper), !SQLWords.dataTypes.contains(t.upper), !Self.keywordValues.contains(t.upper),
              let f = frames.last else { return false }
        let pk = p?.kind, nk = n?.kind, nu = n?.upper ?? ""
        if f.kind == .sql, f.clause == "SELECT" {
            let after = pk == .comma || p?.upper == "SELECT" || pk == .rightParen || pk == .identifier || pk == .quotedIdentifier
            return after && (nk == .comma || nu == "FROM" || nu == "INTO")
        }
        if f.kind == .paren {
            return (pk == .comma || pk == .leftParen) && (nk == .comma || nk == .rightParen)
        }
        return false
    }

    /// Poprzedni token przed `t` (wyszukiwanie binarne).
    func token(before t: Tok) -> Tok? {
        var lo = 0, hi = toks.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if toks[mid].start < t.start { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? toks[lo - 1] : nil
    }

    /// Reguła wielkości liter słowa: funkcja wbudowana (przed „(”), pakiet z bazą (przed „.”), typ danych, słowo
    /// kluczowe, identyfikator.
    func rule(for t: Tok) -> BeautifierOptions.WordCase {
        let base = t.kind == .keyword && !keywordAsIdentifier(t) ? options.keywordCase : options.identifierCase
        let next = token(after: t)
        if let c = options.functionCase, next?.kind == .leftParen, SQLWords.functions.contains(t.upper) { return c }
        if let c = options.packageCase, next?.kind == .dot, SQLWords.isPackage(t.upper) { return c }
        if SQLWords.dataTypes.contains(t.upper), next?.kind != .dot, next?.kind != .leftParen || Self.sizedTypes.contains(t.upper) {
            return options.dataTypeCase ?? options.keywordCase
        }
        return base
    }

    static let sizedTypes: Set<String> = ["NUMBER", "VARCHAR2", "VARCHAR", "CHAR", "NCHAR", "NVARCHAR2", "RAW", "TIMESTAMP", "FLOAT",
                                          "DECIMAL", "NUMERIC", "VECTOR", "INTERVAL", "UROWID"]

    /// Następny token po `t` (wyszukiwanie binarne — tokeny są uporządkowane).
    func token(after t: Tok) -> Tok? {
        var lo = 0, hi = toks.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if toks[mid].start < t.end { lo = mid + 1 } else { hi = mid }
        }
        return lo < toks.count ? toks[lo] : nil
    }

    static func apply(_ rule: BeautifierOptions.WordCase, to t: Tok) -> String {
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
        "RECORD", "OBJECT", "INSERT", "KEY", "CHECK", "REFERENCES", "UNIQUE", "PARTITION", "RANGE", "ROW", "ROWS",
        "GROUP", "SETS", "APPLY", "STORAGE", "INTERVAL", "THAN", "ADD", "MODIFY", "DROP", "UPDATE", "DELETE", "KEEP", "FILTER",
        "MATCH_RECOGNIZE", "COLUMNS", "LIST", "HASH", "SUBPARTITION", "FOREIGN", "PRIMARY", "CONSTRAINT",
    ]

    func needsSpace(_ prev: Tok?, _ t: Tok) -> Bool {
        guard let p = prev else { return false }
        // Sklejone w źródle i nierozdzielne (`$$x`, `1M`, `&x.y`, `a.b`…) — bez spacji (pilnuje tego też `verify`).
        if p.end == t.start, !Beautifier.separable(p.kind, p.text, t.kind, t.text) { return false }
        if t.kind == .rightParen { return options.spaceInsideParentheses && p.kind != .leftParen }
        if [.comma, .semicolon, .dot].contains(t.kind) { return false }
        if p.kind == .leftParen { return options.spaceInsideParentheses }
        if p.kind == .dot { return false }
        if t.text == "%" || p.text == "%" || t.text == "@" || p.text == "@" { return false }
        if t.text == ".." || p.text == ".." { return false }
        if t.kind == .leftParen {
            if p.kind == .identifier || p.kind == .quotedIdentifier { return false }
            // Metoda kolekcji (`l.EXISTS(i)`, `l.DELETE(1)`) — jak wywołanie, bez spacji.
            if p.kind == .keyword, prevPrev()?.kind == .dot { return false }
            if p.kind == .keyword { return Self.spacedBeforeParen.contains(p.upper) }
            return true
        }
        // Minus/plus jednoargumentowy: po operatorze, nawiasie, przecinku albo słowie kluczowym.
        if let pp = prevPrev(), ["-", "+"].contains(p.text), [.operator, .leftParen, .comma].contains(pp.kind) || (pp.kind == .keyword && Self.spacedBeforeParen.contains(pp.upper)) {
            return false
        }
        if p.kind == .comma { return options.spaceAfterComma }
        if !options.spaceAroundOperators, Self.isPlainOperator(t) || Self.isPlainOperator(p),
           p.kind != .keyword, t.kind != .keyword, Self.joinable(p, t) {
            return false
        }
        return true
    }

    /// Operator, wokół którego opcja „spacje wokół operatorów” działa (`:=` i `=>` zawsze ze spacjami).
    static func isPlainOperator(_ t: Tok) -> Bool {
        (t.kind == .operator || t.kind == .slash) && t.text != ":=" && t.text != "=>"
    }

    /// Dwa tokeny bez spacji między nimi dają te same tokeny (nie `--`, `/*`, `=>`, `<=`…).
    static func joinable(_ a: Tok, _ b: Tok) -> Bool {
        let lexer = Lexer(a.text + b.text)
        let parts = lexer.tokenize().filter { $0.kind != .whitespace && $0.kind != .newline }.map(lexer.string)
        return parts == [a.text, b.text]
    }

    func prevPrev() -> Tok? { i >= 2 ? toks[i - 2] : nil }

    // MARK: Przebieg

    mutating func run() -> String {
        while i < toks.count {
            step()
        }
        flush()
        while lines.last == "" { lines.removeLast() }
        lines = BeautifierAligner(lines: lines, raw: rawLines, options: options).aligned()
        return lines.joined(separator: "\n") + ((source as String).hasSuffix("\n") ? "\n" : "")
    }

    func peek(_ o: Int = 1) -> Tok? { i + o < toks.count ? toks[i + o] : nil }
    var prev: Tok? { i > 0 ? toks[i - 1] : nil }
    var inSQLAtTop: Bool { frames.last?.kind == .sql }

    func indentColumns(_ level: Int) -> Int { level * options.indent }

    /// Początek instrukcji w bloku: nowa linia na bieżącym poziomie (z pustą linią, jeśli była w źródle).
    mutating func beginStatementLine(_ t: Tok) {
        let col = pendingBreak ?? indentColumns(level)
        if !lines.isEmpty || !cur.isEmpty { sourceBlankLines(t) }
        lineBreak(col)
    }

    mutating func step() {
        let t = toks[i]
        defer { i += 1 }

        // Polecenia SQL*Plus (kończy je koniec linii, tekst bywa dowolny, np. PROMPT): kopiowane bez zmian.
        if let end = sqlplusEnds[t.start] {
            copyRaw(from: t.start, to: end)
            return
        }
        // Kod Java (CREATE JAVA SOURCE) i JavaScript (CREATE MLE MODULE, MLE LANGUAGE JAVASCRIPT {{ … }}) — bez zmian.
        if statementStart, t.upper == "CREATE", t.isWord {
            var j = i + 1
            while j < toks.count, ["OR", "REPLACE", "AND", "RESOLVE", "COMPILE", "FORCE", "NOFORCE", "EDITIONABLE", "NONEDITIONABLE"].contains(toks[j].upper) { j += 1 }
            if j < toks.count, ["JAVA", "MLE"].contains(toks[j].upper) {
                copyRaw(from: t.start, to: statementEnd(containing: t.start))
                return
            }
        }
        if i == rawFrom {
            rawFrom = nil
            copyRaw(from: t.start, to: statementEnd(containing: t.start), sameLine: true)
            return
        }

        // Kompilacja warunkowa `$IF … $END` (i `$ERROR … $END`): gałęzie bywają niepełnymi fragmentami składni —
        // region kopiowany bez zmian, w PL/SQL (poza instrukcją SQL i nawiasem) ze średnikiem tuż za `$END`.
        if t.kind == .directive, ["$IF", "$ERROR"].contains(t.upper) {
            var depth = 0
            var j = i
            while j < toks.count {
                if toks[j].kind == .directive {
                    if ["$IF", "$ERROR"].contains(toks[j].upper) { depth += 1 }
                    if toks[j].upper == "$END" { depth -= 1; if depth == 0 { break } }
                }
                j += 1
            }
            var end = j < toks.count ? toks[j].end : source.length
            if j + 1 < toks.count, toks[j + 1].newlines == 0, toks[j + 1].kind == .semicolon,
               !frames.contains(where: { $0.kind == .sql || $0.kind == .paren }) {
                end = toks[j + 1].end
            }
            let lineStart = source.lineRange(for: NSRange(location: t.start, length: 0)).location
            let before = source.substring(with: NSRange(location: lineStart, length: t.start - lineStart))
            let sameLine = !before.allSatisfy { $0 == " " || $0 == "\t" } && !(lines.isEmpty && cur.isEmpty)
            copyRaw(from: t.start, to: end, sameLine: sameLine)
            return
        }

        // Regiony bez formatowania: kopiowane bez zmian.
        if Self.isFormatMarker(t, start: true) {
            // Komentarz za kodem w tej samej linii: kod już jest w wyniku — kopia od komentarza, w bieżącej linii.
            let sameLine = t.newlines == 0 && !(lines.isEmpty && cur.isEmpty)
            sourceBlankLines(t)
            var j = i
            while j < toks.count, !Self.isFormatMarker(toks[j], start: false) { j += 1 }
            let end = j < toks.count ? toks[j].end : source.length
            let from = sameLine ? t.start : source.lineRange(for: NSRange(location: t.start, length: 0)).location
            var raw = source.substring(with: NSRange(location: from, length: end - from)).components(separatedBy: "\n")
            if sameLine { cur += (cur.isEmpty ? "" : " ") + raw.removeFirst() }
            if sameLine { rawLines.insert(lines.count) }
            flush()
            rawLines.formUnion(lines.count..<(lines.count + raw.count))
            lines.append(contentsOf: raw)
            i = j
            pendingBreak = indentColumns(level)
            statementStart = true
            return
        }

        // Komentarze.
        if t.kind == .lineComment || t.kind == .blockComment {
            let text = t.kind == .lineComment ? t.text.trimmingCharacters(in: .whitespaces) : t.text
            if t.newlines > 0 || cur.isEmpty && pendingBreak != nil {
                sourceBlankLines(t)
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
            } else if options.commaBefore, cur == ",", t.kind == .lineComment, let last = lines.indices.last,
                      !rawLines.contains(last), !lines[last].trimmingCharacters(in: .whitespaces).hasPrefix("--") {
                // Przecinek na początku linii przeniesiony przed komentarz końca linii (`a, -- opis`): komentarz zostaje
                // przy swoim elemencie w poprzedniej linii.
                lines[last] += " " + text
            } else {
                // Komentarz na końcu linii zostaje w niej (bez wykonania zaległego złamania linii).
                cur += (cur.isEmpty ? "" : " ") + text
                if t.kind == .lineComment, pendingBreak == nil { pendingBreak = statementStart ? indentColumns(level) : continuationColumn() }
            }
            return
        }

        if t.kind == .slash, t.newlines > 0 || lines.isEmpty && cur.isEmpty, peek().map({ $0.newlines > 0 }) ?? true {
            // Koniec jednostki w skrypcie: „/” sam w linii (w środku wyrażenia to dzielenie).
            lineBreak(0)
            cur = "/"
            flush()
            frames.removeAll()
            headerLevel = nil
            unitKind = ""
            ddlOptions = false
            statementStart = true
            pendingBreak = 0
            return
        }

        let w = t.kind == .keyword || t.kind == .identifier ? t.upper : ""
        let prevUpper = prev?.upper ?? ""

        // Etykieta `<<nazwa>>`: bez spacji, w osobnej linii przed instrukcją.
        if t.text == "<<", statementStart, let name = peek(), name.isWord, peek(2)?.text == ">>" {
            beginStatementLine(t)
            put("<<" + Self.apply(options.identifierCase, to: name) + ">>", space: false)
            i += 2
            pendingBreak = indentColumns(level)
            return
        }

        // MARK: Struktura PL/SQL (poza nawiasami i SQL)
        if !frames.contains(where: { $0.kind == .sql || $0.kind == .paren }) {
            if handlePLSQL(t, w, prevUpper) { return }
            if w == "FORALL", statementStart { forallPending = true }
            if w == "BETWEEN" { betweenPending = true }
            // Długi warunek IF/ELSIF/WHILE/EXIT WHEN: AND/OR w nowej linii, gdy reszta się nie mieści.
            if ["AND", "OR"].contains(w), let col = conditionColumn {
                if w == "AND", betweenPending {
                    betweenPending = false
                } else if column + 1 + segmentLength(from: i, stop: ["AND", "OR", "THEN", "LOOP"]) > options.rightMargin {
                    if options.andOrPosition == .lineEnd {
                        put(cased(t), space: true)
                        pendingBreak = col
                        return
                    }
                    lineBreak(col)
                    put(cased(t), space: false)
                    return
                }
            }
        }
        // Długie wyrażenie: łamanie przed operatorem (||, +, -), gdy następny składnik się nie mieści.
        if isBinaryOperator(t), !cur.isEmpty,
           column + 1 + t.text.count + 1 + segmentLength(from: i + 1, stop: []) > options.rightMargin,
           column > curIndentColumns + options.indent {
            lineBreak(expressionContinuationColumn())
            put(t.text, space: false)
            return
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
        // Zapytanie po IS/AS (kursor, widok, MV, CREATE TABLE … AS) i DML po nagłówku FORALL.
        let afterIsAs = ["IS", "AS"].contains(prevUpper) && ["SELECT", "WITH"].contains(w) && prev?.kind == .keyword
            && !frames.contains(where: { $0.kind == .sql || $0.kind == .paren })
        let afterForall = forallPending && ["INSERT", "UPDATE", "DELETE", "MERGE"].contains(w) && !frames.contains(where: { $0.kind == .sql || $0.kind == .paren })
        if ["SELECT", "WITH", "INSERT", "UPDATE", "DELETE", "MERGE"].contains(w), (statementStart || prev?.kind == .leftParen || afterIsAs || afterForall), !(w == "WITH" && !statementStart && prev?.kind != .leftParen && !afterIsAs) {
            if statementStart { beginStatementLine(t) }
            if afterIsAs {
                // Kursor w PL/SQL: zapytanie o wcięcie głębiej; widok, MV, tabela: w kolumnie instrukcji.
                lineBreak(frames.isEmpty ? indentColumns(level) : indentColumns(level + 1))
            } else if afterForall {
                lineBreak(curIndentColumns + options.indent)
            }
            forallPending = false
            var frame = Frame(kind: .sql, level: level, column: pendingBreak ?? column + (cur.isEmpty || prev?.kind == .leftParen ? 0 : 1), clause: w)
            frame.statement = w
            frame.multiInsert = w == "INSERT" && ["ALL", "FIRST"].contains(nextSignificant(i)?.upper ?? "")
            frames.append(frame)
            put(cased(t), space: needsSpace(prev, t))
            if w == "SELECT", let n = peek(), ["DISTINCT", "UNIQUE", "ALL"].contains(n.upper) { i += 1; put(cased(n), space: true) }
            statementStart = false
            alignAfterKeyword()
            return
        }
        if w == "CASE" {
            if statementStart { beginStatementLine(t); statementStart = false }
            openCase(t)
            return
        }
        if let f = frames.last, f.kind == .caseExpr, caseBranch(t, w, f) { return }
        if inSQLAtTop, let f = frames.last, sqlClause(t, w, f) { return }
        if t.kind == .comma {
            comma()
            return
        }
        if statementStart {
            beginStatementLine(t)
            statementStart = false
        }
        // CREATE TABLE/INDEX/MV: klauzule fizyczne (TABLESPACE, STORAGE, PARTITION BY…) w nowych liniach, gdy reszta
        // instrukcji nie mieści się w linii.
        if ddlOptions, t.kind == .keyword, Self.physicalOptions.contains(w), w != "PARTITION" || peek()?.upper == "BY",
           !frames.contains(where: { $0.kind == .sql || $0.kind == .paren }), column > indentColumns(level),
           column + 1 + remainingLength(from: i) > options.rightMargin {
            lineBreak(indentColumns(level))
        }
        put(cased(t), space: needsSpace(prev, t))
        if t.text == ":=" { operandColumn = column + 1 }
        if w == "WHEN", ["EXIT", "CONTINUE"].contains(prevUpper) || ["EXIT", "CONTINUE"].contains(prevPrev()?.upper ?? "") {
            conditionColumn = column + 1
        }
    }

    // MARK: Długie wyrażenia i warunki

    /// IF/ELSIF/WHILE/EXIT WHEN: kolumna początku warunku (kolejne AND/OR przy łamaniu).
    var conditionColumn: Int?
    /// Kolumna prawej strony `:=` (kontynuacja długiego wyrażenia).
    var operandColumn: Int?
    var forallPending = false
    /// Instrukcja CREATE TABLE/INDEX/VIEW (klauzule fizyczne łamane przy marginesie).
    var ddlOptions = false

    static let physicalOptions: Set<String> = [
        "TABLESPACE", "PCTFREE", "PCTUSED", "INITRANS", "MAXTRANS", "STORAGE", "LOGGING", "NOLOGGING", "COMPRESS",
        "NOCOMPRESS", "PARTITION", "SUBPARTITION", "LOB", "ORGANIZATION", "CACHE", "NOCACHE", "PARALLEL", "NOPARALLEL",
        "SEGMENT", "ONLINE", "LOCAL", "GLOBAL", "BUILD", "REFRESH",
    ]

    /// Długość reszty instrukcji od tokenu `start` w jednej linii (do średnika albo końca polecenia).
    func remainingLength(from start: Int) -> Int {
        let end = statementEnd(containing: toks[start].start)
        var len = 0, j = start
        while j < toks.count, toks[j].start < end, toks[j].kind != .semicolon {
            if toks[j].kind == .lineComment { return 1000 }
            len += toks[j].text.count + 1
            j += 1
        }
        return len
    }

    /// Operator dwuargumentowy o najniższym priorytecie (`||`, `+`, `-`), przed którym wolno złamać długie wyrażenie
    /// (nie minus jednoargumentowy).
    func isBinaryOperator(_ t: Tok) -> Bool {
        guard t.kind == .operator, ["||", "+", "-"].contains(t.text), let p = prev else { return false }
        switch p.kind {
        case .identifier, .number, .string, .rightParen, .bindVariable, .quotedIdentifier, .substitution, .directive: return true
        case .keyword: return !Self.spacedBeforeParen.contains(p.upper) && !["SELECT", "DISTINCT", "UNIQUE"].contains(p.upper)
        default: return false
        }
    }

    /// Długość fragmentu od tokenu `start` do najbliższego (na tej samej głębokości nawiasów) słowa z `stop`, przecinka,
    /// średnika albo nawiasu zamykającego; przy pustym `stop` — do następnego operatora dwuargumentowego albo słowa
    /// kluczowego. Komentarz liniowy — „nie mieści się”.
    func segmentLength(from start: Int, stop: Set<String>) -> Int {
        var depth = 0, len = 0, j = start
        var between = false
        while j < toks.count {
            let k = toks[j]
            if depth == 0, j > start {
                if k.kind == .comma || k.kind == .semicolon { break }
                if stop.isEmpty {
                    if k.kind == .operator, ["||", "+", "-"].contains(k.text) { break }
                    if k.kind == .keyword, toks.indices.contains(j + 1), toks[j + 1].kind != .leftParen { break }
                } else if k.isWord, stop.contains(k.upper), !(between && k.upper == "AND") {
                    break
                }
                if k.upper == "BETWEEN" { between = true } else if k.upper == "AND" { between = false }
            }
            if k.kind == .leftParen { depth += 1 }
            if k.kind == .rightParen { if depth == 0 { break }; depth -= 1 }
            if k.kind == .lineComment { return 1000 }
            len += k.text.count + (j > start ? 1 : 0)
            j += 1
        }
        return len
    }

    /// Kolumna kontynuacji długiego wyrażenia: w SQL — elementy klauzuli z wcięciem, w nawiasie zawijanym — za nawiasem,
    /// w PL/SQL — prawa strona `:=` albo wcięcie instrukcji.
    func expressionContinuationColumn() -> Int {
        if let f = frames.last {
            switch f.kind {
            case .sql: return listColumn(f) + options.indent
            case .paren: return f.column
            default: break
            }
        }
        if let c = operandColumn, c < options.rightMargin / 2 { return c }
        return indentColumns(level) + options.indent
    }

    /// Najbliższy token po `k` (albo przed) z pominięciem komentarzy i hintów.
    func nextSignificant(_ k: Int) -> Tok? {
        var j = k + 1
        while j < toks.count, [.lineComment, .blockComment, .hint].contains(toks[j].kind) { j += 1 }
        return j < toks.count ? toks[j] : nil
    }

    func prevSignificant(_ k: Int) -> Tok? {
        var j = k - 1
        while j >= 0, [.lineComment, .blockComment, .hint].contains(toks[j].kind) { j -= 1 }
        return j >= 0 ? toks[j] : nil
    }

    /// Wyrównanie elementów po słowie klauzuli do kolumny (SELECT␣ = 7 znaków): `FROM   emp`.
    mutating func alignAfterKeyword() {
        guard let f = frames.last, f.kind == .sql else { return }
        // INSERT INTO / MERGE INTO — bez wyrównania przed INTO.
        if nextSignificant(i)?.upper == "INTO", ["INSERT", "MERGE"].contains(toks[i].upper) { return }
        if options.clauseLayout == .ownLine {
            // Słowo klauzuli w osobnej linii, elementy wcięte pod nim.
            let col = f.column + options.indent
            frames[frames.count - 1].itemColumn = col
            let next = peek()
            if next?.kind == .semicolon || next?.kind == .rightParen || next == nil || next?.kind == .lineComment { return }
            pendingBreak = col
            return
        }
        let target = f.column + 7
        frames[frames.count - 1].itemColumn = max(target, column + 1)
        let next = peek()
        if next?.kind == .semicolon || next?.kind == .rightParen || next == nil { return }
        if column < target - 1 { cur += String(repeating: " ", count: target - 1 - column) }
    }

    func continuationColumn() -> Int {
        if let f = frames.last {
            switch f.kind {
            case .sql: return listColumn(f)
            case .paren: return f.wrap || f.subquery ? f.column : curIndentColumns + options.indent
            default: break
            }
        }
        return indentColumns(level) + options.indent
    }

    /// Kolumna elementów listy klauzuli (kolejne elementy po przecinku, warunki).
    func listColumn(_ f: Frame) -> Int {
        options.clauseLayout == .ownLine ? f.itemColumn : max(f.column + 7, f.itemColumn)
    }

    /// Kolumna słowa klauzuli: do lewej w kolumnie instrukcji, do prawej — kończy się w kolumnie końca SELECT.
    func clauseColumn(_ f: Frame, _ keyword: String) -> Int {
        options.clauseLayout == .rightAligned ? f.column + max(0, 6 - keyword.count) : f.column
    }

    static let clauseStarts: [[String]] = [
        ["FROM"], ["WHERE"], ["GROUP", "BY"], ["HAVING"], ["ORDER", "SIBLINGS", "BY"], ["ORDER", "BY"], ["CONNECT", "BY"], ["START", "WITH"],
        ["UNION", "ALL"], ["UNION"], ["INTERSECT"], ["MINUS"], ["EXCEPT"], ["INTO"], ["BULK", "COLLECT", "INTO"], ["VALUES"], ["SET"],
        ["RETURNING"], ["RETURN"], ["LEFT", "OUTER", "JOIN"], ["RIGHT", "OUTER", "JOIN"], ["FULL", "OUTER", "JOIN"], ["LEFT", "JOIN"],
        ["RIGHT", "JOIN"], ["FULL", "JOIN"], ["INNER", "JOIN"], ["CROSS", "JOIN"], ["NATURAL", "JOIN"], ["JOIN"], ["USING"],
        ["WHEN", "MATCHED"], ["WHEN", "NOT", "MATCHED"], ["FETCH"], ["OFFSET"], ["FOR", "UPDATE"], ["WINDOW"], ["LOG", "ERRORS"],
        ["CROSS", "APPLY"], ["OUTER", "APPLY"], ["PIVOT"], ["UNPIVOT"], ["MATCH_RECOGNIZE"],
    ]

    /// Słowo rozpoczynające klauzulę w instrukcji SQL na jej głębokości: nowa linia w kolumnie instrukcji.
    mutating func sqlClause(_ t: Tok, _ w: String, _ f: Frame) -> Bool {
        guard t.isWord else { return false }
        if w == "BETWEEN" { betweenPending = true }
        let setOperators: Set<String> = ["UNION", "ALL", "MINUS", "INTERSECT", "EXCEPT"]
        // Główne zapytanie po definicjach WITH (także po SEARCH/CYCLE), zapytanie po UNION/MINUS… i w INSERT … SELECT:
        // SELECT w nowej linii w kolumnie instrukcji.
        if w == "SELECT" || w == "WITH" && f.statement == "INSERT",
           prev?.kind == .rightParen || prev?.kind == .comma && f.clause == "WITH" || ["SEARCH", "CYCLE"].contains(f.clause)
            || f.kind == .sql && setOperators.contains(prevSignificant(i)?.upper ?? "") && setOperators.contains(f.clause)
            || f.statement == "INSERT" && prev?.kind != .leftParen {
            lineBreak(clauseColumn(f, w))
            put(cased(t), space: false)
            frames[frames.count - 1].clause = w
            alignAfterKeyword()
            return true
        }
        // SEARCH … SET / CYCLE … SET w zapytaniu rekurencyjnym — pod nazwą definicji WITH.
        if ["SEARCH", "CYCLE"].contains(w), ["WITH", "SEARCH"].contains(f.clause), prev?.kind == .rightParen || prev?.kind == .string || prev?.isWord == true {
            lineBreak(listColumn(f))
            put(cased(t), space: false)
            frames[frames.count - 1].clause = w
            return true
        }
        // Operator zbiorowy w osobnej linii (następny SELECT — od nowej linii).
        if setOperators.subtracting(["ALL"]).contains(w) {
            var text = cased(t)
            if w == "UNION", peek()?.upper == "ALL" { text += " " + cased(toks[i + 1]); i += 1 }
            lineBreak(clauseColumn(f, text))
            put(text, space: false)
            frames[frames.count - 1].clause = w
            if peek()?.kind != .leftParen { pendingBreak = clauseColumn(f, "SELECT") }
            return true
        }
        // INSERT ALL / FIRST: WHEN … THEN i ELSE w kolumnie instrukcji.
        if f.multiInsert, ["WHEN", "ELSE"].contains(w) {
            lineBreak(clauseColumn(f, w))
            put(cased(t), space: false)
            frames[frames.count - 1].clause = "WHEN"
            return true
        }
        // MERGE: ON (…) po USING — w osobnej linii jak klauzula; DELETE WHERE po UPDATE SET.
        if w == "ON", f.statement == "MERGE", f.clause == "USING" {
            lineBreak(clauseColumn(f, w))
            put(cased(t), space: false)
            frames[frames.count - 1].clause = "MERGEON"
            alignAfterKeyword()
            return true
        }
        if w == "DELETE", f.statement == "MERGE", peek()?.upper == "WHERE" {
            lineBreak(clauseColumn(f, w))
            put(cased(t) + " " + cased(toks[i + 1]), space: false)
            i += 1
            frames[frames.count - 1].clause = "WHERE"
            frames[frames.count - 1].itemColumn = column + 1
            return true
        }
        // WITH READ ONLY / WITH CHECK OPTION na końcu zapytania widoku.
        if w == "WITH", ["READ", "CHECK"].contains(peek()?.upper ?? "") {
            lineBreak(clauseColumn(f, w))
            put(cased(t), space: false)
            frames[frames.count - 1].clause = "WITHOPTION"
            return true
        }
        // RETURNING … INTO / BULK COLLECT INTO — jedna klauzula.
        if f.clause == "RETURNING", ["INTO", "BULK"].contains(w) { return false }
        if ["AND", "OR"].contains(w) {
            if w == "AND", betweenPending { betweenPending = false; return false }
            guard ["WHERE", "HAVING", "ON", "WHEN", "START", "CONNECT"].contains(f.clause) || f.clause.hasSuffix("JOIN") else { return false }
            // Warunek złączenia: kolejne warunki pod ON (słowo ON w kolumnie wcięcia złączenia).
            let onColumn = options.clauseLayout == .rightAligned ? clauseColumn(f, w) : f.column + options.indent
            // Na końcu linii — chyba że linię zamknął już komentarz (`-- …`): wtedy AND/OR nie zostaje sam w linii,
            // tylko jak przy układzie „na początku linii”.
            if options.andOrPosition == .lineEnd, prev?.kind != .lineComment {
                put(cased(t), space: true)
                pendingBreak = f.clause == "ON" && options.clauseLayout != .ownLine ? onColumn + 3 : listColumn(f)
                return true
            }
            if f.clause == "ON", options.clauseLayout != .ownLine {
                lineBreak(onColumn)
                put(cased(t), space: false)
                return true
            }
            if options.clauseLayout == .ownLine {
                lineBreak(f.column + options.indent)
                put(cased(t), space: false)
                return true
            }
            lineBreak(clauseColumn(f, w))
            put(cased(t), space: false)
            alignAfterKeyword()
            return true
        }
        if w == "ON", f.clause.hasSuffix("JOIN") {
            frames[frames.count - 1].clause = "ON"
            guard options.joinConditionOnNewLine else {
                put(cased(t), space: true)
                return true
            }
            lineBreak(options.clauseLayout == .rightAligned ? clauseColumn(f, w) : f.column + options.indent)
            put(cased(t), space: false)
            return true
        }
        // INTO po INSERT/MERGE zostaje w linii instrukcji.
        if w == "INTO", ["INSERT", "MERGE"].contains(prevSignificant(i)?.upper ?? "") { put(cased(t), space: true); return true }
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
            var text = cased(t)
            for k in 1..<words.count { text += " " + cased(toks[i + k]) }
            lineBreak(clauseColumn(f, text))
            put(text, space: false)
            i += words.count - 1
            frames[frames.count - 1].clause = words.contains("JOIN") ? "JOIN" : (w == "WHEN" ? "WHEN" : w == "INTO" && words.count == 1 ? "INTO" : words.last!)
            if words.first == "WHEN" { frames[frames.count - 1].clause = "WHEN" }
            alignAfterKeyword()
            return true
        }
        return false
    }

    /// Wyrażenie CASE: ramka z kolumną słowa CASE (WHEN/ELSE/END w osobnych liniach przy układzie wieloliniowym).
    mutating func openCase(_ t: Tok) {
        let text = cased(t)
        put(text, space: needsSpace(prev, t))
        frames.append(Frame(kind: .caseExpr, level: level, column: column - text.count))
    }

    mutating func caseBranch(_ t: Tok, _ w: String, _ f: Frame) -> Bool {
        switch w {
        case "END":
            frames.removeLast()
            if options.caseLayout == .multiline {
                lineBreak(f.column)
                put(cased(t), space: false)
            } else {
                put(cased(t), space: needsSpace(prev, t))
            }
            return true
        case "WHEN", "ELSE":
            guard options.caseLayout == .multiline else { return false }
            lineBreak(f.column + options.indent)
            put(cased(t), space: false)
            return true
        default:
            return false
        }
    }

    static let listClauses: Set<String> = ["SELECT", "FROM", "BY", "SET", "INTO", "RETURNING", "VALUES", "WITH"]

    mutating func comma() {
        // Przecinek za komentarzem `--` końca linii elementu (przecinek na końcu linii): przed komentarzem, przy
        // elemencie (`b, -- opis`), nie sam w następnej linii — `verify` traktuje oba położenia jako równoważne.
        if !options.commaBefore, let p = prev, p.kind == .lineComment, pendingBreak != nil {
            let comment = p.text.trimmingCharacters(in: .whitespaces)
            let before = String(cur.dropLast(comment.count)).trimmingCharacters(in: .whitespaces)
            if cur.hasSuffix(comment), !before.isEmpty, !before.hasSuffix(",") {
                cur = before + ", " + comment
                return
            }
        }
        put(",", space: false)
        guard let f = frames.last else { return }
        switch f.kind {
        case .sql:
            guard Self.listClauses.contains(f.clause) else { return }
            if options.listLayout == .onePerLine || column > options.rightMargin {
                breakForList(listColumn(f))
            }
        case .paren where f.wrap:
            breakForList(f.column)
        case .unit, .declare, .block, .exception, .ifStmt, .loop, .caseStmt, .caseExpr, .paren, .branch:
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
            // Reguła listy wg miejsca nawiasu: INSERT (kolumny, VALUES), nagłówek podprogramu, wywołanie w PL/SQL.
            var layout = BeautifierOptions.ListLayout.fit
            if let f = frames.last, f.kind == .sql {
                if ["INSERT", "VALUES"].contains(f.clause) { layout = options.insertLists }
            } else if frames.last?.kind != .paren {
                if headerLevel != nil { layout = options.parameterDeclarations } else if prev?.isWord == true { layout = options.callParameters }
            }
            // Rozmiar typu (`NUMBER(14, 2)`) nigdy nie jest łamany; argumenty PRAGMA — tylko przy marginesie.
            if let p = prev, p.isWord, Self.sizedTypes.contains(p.upper) { hasComma = false }
            if prevPrev()?.upper == "PRAGMA" { layout = .fit }
            wrap = hasComma && (layout == .onePerLine || column + length > options.rightMargin)
        }
        let inner = options.spaceInsideParentheses && next?.kind != .rightParen ? 1 : 0
        frames.append(Frame(kind: .paren, level: level, column: column + inner, clause: "", wrap: wrap, subquery: sub))
    }

    mutating func closeParen(_ t: Tok) {
        // Zamknięcie instrukcji SQL podzapytania i samego nawiasu.
        while let f = frames.last, f.kind == .sql { frames.removeLast() }
        if let f = frames.last, f.kind == .paren { frames.removeLast() }
        put(")", space: needsSpace(prev, t))
    }

    mutating func endStatement() {
        while let f = frames.last, f.kind == .sql || f.kind == .paren { frames.removeLast() }
        betweenPending = false
        conditionColumn = nil
        operandColumn = nil
        forallPending = false
        ddlOptions = false
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
                unitKind = headerKind
                if headerKind == "TRIGGER" { triggerHeaderLong = column + triggerHeaderLength(from: i) > options.rightMargin }
                statementStart = false
                put(cased(t), space: false)
                return true
            }
            unitKind = ""
            ddlOptions = toks[j...].prefix(4).contains { ["TABLE", "INDEX", "VIEW"].contains($0.upper) }
            return false
        }
        // Podprogram w sekcji deklaracji; w wyzwalaczu złożonym — sekcje BEFORE/AFTER/INSTEAD OF … IS.
        if statementStart, ["PROCEDURE", "FUNCTION"].contains(w) || (["MEMBER", "STATIC", "CONSTRUCTOR", "MAP", "ORDER", "OVERRIDING", "FINAL"].contains(w) && unitKind == "TYPE")
            || ["BEFORE", "AFTER", "INSTEAD"].contains(w) && unitKind == "COMPOUND" && frames.last?.kind == .declare {
            if options.blankLineBetweenSubprograms, frames.last?.kind == .declare {
                flush()
                if let last = lines.last?.trimmingCharacters(in: .whitespaces).uppercased(), !last.isEmpty,
                   !(last == "IS" || last == "AS" || last.hasSuffix(" IS") || last.hasSuffix(" AS") || last == "DECLARE"),
                   !last.hasPrefix("--"), !last.hasSuffix("*/") {
                    lines.append("")
                }
            }
            beginStatementLine(t)
            headerLevel = level
            headerKind = w
            statementStart = false
            put(cased(t), space: false)
            return true
        }
        // W nagłówku wyzwalacza AS należy do REFERENCING … AS (ciało zaczyna DECLARE/BEGIN/COMPOUND).
        if let h = headerLevel, headerKind != "TRIGGER", ["IS", "AS"].contains(w), !(w == "AS" && prevUpper == "SELF") {
            // Typ obiektowy / kolekcja / LANGUAGE / EXTERNAL — bez sekcji deklaracji (zwykła instrukcja do „;”).
            if headerKind == "TYPESPEC" || ["LANGUAGE", "EXTERNAL", "MLE"].contains(peek()?.upper ?? "") {
                headerLevel = nil
                // MLE LANGUAGE JAVASCRIPT {{ kod }} — kod od „{{” do końca jednostki bez zmian.
                if peek()?.upper == "MLE" {
                    var k = i + 1
                    while k < toks.count, toks[k].isWord { k += 1 }
                    if k + 1 < toks.count, toks[k].text == "{", toks[k + 1].text == "{" { rawFrom = k }
                }
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
            if w == "DECLARE" || w == "COMPOUND" {
                lineBreak(indentColumns(h))
                put(cased(t), space: false)
                if w == "COMPOUND", peek()?.upper == "TRIGGER" {
                    i += 1
                    put(cased(toks[i]), space: true)
                    unitKind = "COMPOUND"
                }
                frames.append(Frame(kind: .declare, level: h))
                statementStart = true
                pendingBreak = indentColumns(h + 1)
                return true
            }
            statementStart = true
        }
        // Długi nagłówek wyzwalacza: zdarzenia, ON, REFERENCING, FOR EACH ROW, FOLLOWS, WHEN — w osobnych liniach.
        if headerKind == "TRIGGER", let h = headerLevel, triggerHeaderLong, prevUpper != "INSTEAD",
           ["BEFORE", "AFTER", "INSTEAD", "FOR", "ON", "REFERENCING", "FOLLOWS", "PRECEDES", "WHEN", "ENABLE", "DISABLE"].contains(w) {
            lineBreak(indentColumns(h) + options.indent)
            put(cased(t), space: false)
            return true
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
                sourceBlankLines(t)
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
            if let f = frames.last, f.kind == .caseExpr { return caseBranch(t, w, f) }
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
            conditionColumn = column + 1
            statementStart = false
            return true
        case "ELSIF", "ELSE":
            if let f = frames.last, f.kind == .ifStmt {
                lineBreak(indentColumns(f.level))
                put(cased(t), space: false)
                statementStart = w == "ELSE"
                if w == "ELSE" { pendingBreak = indentColumns(f.level + 1) }
                conditionColumn = w == "ELSIF" ? column + 1 : nil
                return true
            }
            if w == "ELSE", statementStart { closeBranch() }
            if let f = frames.last, f.kind == .caseStmt {
                lineBreak(indentColumns(f.level + 1))
                put(cased(t), space: false)
                statementStart = true
                frames.append(Frame(kind: .branch, level: f.level + 1))
                pendingBreak = indentColumns(f.level + 2)
                return true
            }
            return false
        case "THEN":
            if let f = frames.last, [.ifStmt, .caseStmt, .exception].contains(f.kind) {
                conditionColumn = nil
                if options.thenOnNewLine, f.kind == .ifStmt {
                    lineBreak(indentColumns(f.level))
                    put(cased(t), space: false)
                } else {
                    put(cased(t), space: true)
                }
                statementStart = true
                // Treść gałęzi WHEN … THEN (wyjątki, instrukcja CASE): wszystkie instrukcje o poziom głębiej niż WHEN.
                if f.kind != .ifStmt { frames.append(Frame(kind: .branch, level: f.level + 1)) }
                pendingBreak = indentColumns(f.kind == .ifStmt ? f.level + 1 : f.level + 2)
                return true
            }
            return false
        case "WHEN":
            if statementStart { closeBranch() }
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
        case "CASE":
            // Wyrażenie CASE w instrukcji (x := CASE … END): z ramką — jego END nie zamyka bloku.
            openCase(t)
            return true
        case "LOOP":
            if prevUpper == "END" { return false }
            conditionColumn = nil
            if !statementStart { put(cased(t), space: true) } else { beginStatementLine(t); put(cased(t), space: false) }
            frames.append(Frame(kind: .loop, level: statementLevelForLoop()))
            statementStart = true
            pendingBreak = indentColumns(frames.last!.level + 1)
            return true
        case "FOR" where statementStart, "WHILE" where statementStart:
            beginStatementLine(t)
            loopStartLevel = level
            put(cased(t), space: false)
            if w == "WHILE" { conditionColumn = column + 1 }
            statementStart = false
            return true
        default:
            return false
        }
    }

    var loopStartLevel: Int?
    /// Nagłówek wyzwalacza nie mieści się w linii (klauzule w osobnych liniach).
    var triggerHeaderLong = false

    /// Długość nagłówka wyzwalacza od CREATE do DECLARE/BEGIN/COMPOUND/CALL (poza nawiasami) w jednej linii.
    func triggerHeaderLength(from start: Int) -> Int {
        var depth = 0, len = 0, j = start
        while j < toks.count {
            let k = toks[j]
            if depth == 0, j > start, k.isWord, ["DECLARE", "BEGIN", "COMPOUND", "CALL"].contains(k.upper) { break }
            if k.kind == .semicolon { break }
            if k.kind == .leftParen { depth += 1 }
            if k.kind == .rightParen { depth = max(0, depth - 1) }
            if k.kind == .lineComment { return 1000 }
            len += k.text.count + 1
            j += 1
        }
        return len
    }

    /// Koniec treści gałęzi WHEN/ELSE (następna gałąź tej samej obsługi wyjątków albo instrukcji CASE).
    mutating func closeBranch() {
        guard frames.count >= 2, frames[frames.count - 1].kind == .branch,
              [.exception, .caseStmt].contains(frames[frames.count - 2].kind) else { return }
        frames.removeLast()
    }

    mutating func statementLevelForLoop() -> Int {
        defer { loopStartLevel = nil }
        return loopStartLevel ?? level
    }
}
