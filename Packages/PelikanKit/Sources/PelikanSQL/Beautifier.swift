import Foundation

/// Reguły formatera PL/SQL (UG 29.1–29.2) — przechowywane w preferencjach.
public struct BeautifierOptions: Sendable, Codable, Hashable {
    public enum WordCase: String, Sendable, Codable, Hashable, CaseIterable { case unchanged, upper, lower, initCap }
    public enum ListLayout: String, Sendable, Codable, Hashable, CaseIterable {
        /// Element listy w osobnej linii.
        case onePerLine
        /// Listy klauzul (SELECT, SET…): elementy w linii, zawijane przy prawym marginesie. Listy w nawiasach
        /// (parametry, INSERT, IN…): w jednej linii, a gdy się nie mieści — element w linii (PL/SQL Developer
        /// „On one line if possible”).
        case fit
        /// Listy w nawiasach: elementy w linii, zawijane przy prawym marginesie (PL/SQL Developer „Fit”).
        case wrap
    }
    /// Układ klauzul SQL (FROM, WHERE…): słowa do lewej z elementami w kolumnie, słowa do prawej („rzeka”: słowa
    /// kończą się w kolumnie SELECT) albo słowo w osobnej linii i elementy wcięte pod nim.
    public enum ClauseLayout: String, Sendable, Codable, Hashable, CaseIterable { case leftAligned, rightAligned, ownLine }
    /// AND/OR warunków na początku nowej linii albo na końcu poprzedniej.
    public enum OperatorPosition: String, Sendable, Codable, Hashable, CaseIterable { case lineStart, lineEnd }
    /// Wyrażenie CASE w jednej linii, WHEN/ELSE/END w osobnych liniach albo wieloliniowo z wyjątkiem bardzo krótkich
    /// (jedna gałąź WHEN, całość do `caseInlineLimit` znaków).
    public enum CaseLayout: String, Sendable, Codable, Hashable, CaseIterable { case inline, multiline, auto }
    /// Podzapytanie w nawiasie: za nawiasem (treść w kolumnie po „(”) albo wcięte w nowej linii, „)” w osobnej linii.
    public enum SubqueryLayout: String, Sendable, Codable, Hashable, CaseIterable { case hanging, indented }
    /// Łamanie warunku przed AND/OR: każdy w osobnej linii, tylko gdy warunek się nie mieści, nigdy.
    public enum ConditionBreak: String, Sendable, Codable, Hashable, CaseIterable { case always, ifLong, never }
    /// Kolumna AND/OR w nowej linii: do słowa kluczowego („rzeka” — prawostronnie; w klauzulach SQL jak słowa klauzul),
    /// pod początkiem pierwszego warunku albo pod nim z wcięciem.
    public enum ConditionAlign: String, Sendable, Codable, Hashable, CaseIterable { case keyword, firstCondition, indent }
    /// Miejsca warunków logicznych z osobnymi regułami AND/OR.
    public enum ConditionContext: String, Sendable, Codable, Hashable, CaseIterable {
        case whereClause, having, joinOn, mergeOn, hierarchical, caseWhen, ifCondition, whileLoop, exitWhen, triggerWhen, check, nested
    }
    /// Reguła AND/OR w jednym miejscu (położenie nil — jak „AND / OR” ogólnie).
    public struct ConditionLayout: Sendable, Codable, Hashable {
        public var breaks: ConditionBreak
        public var position: OperatorPosition?
        public var align: ConditionAlign
        public init(breaks: ConditionBreak, position: OperatorPosition? = nil, align: ConditionAlign) {
            self.breaks = breaks; self.position = position; self.align = align
        }
    }

    /// Reguły domyślne (D202): każdy AND/OR w osobnej linii, wyrównany do słowa kluczowego („rzeka”); CHECK i nawiasy
    /// zagnieżdżone — łamane tylko, gdy się nie mieszczą, pod pierwszym warunkiem.
    public static func defaultCondition(_ c: ConditionContext) -> ConditionLayout {
        switch c {
        case .check, .nested: ConditionLayout(breaks: .ifLong, align: .firstCondition)
        default: ConditionLayout(breaks: .always, align: .keyword)
        }
    }

    public var indent = 2
    public var useTabs = false
    public var rightMargin = 100
    public var keywordCase: WordCase = .upper
    public var identifierCase: WordCase = .unchanged
    public var listLayout: ListLayout = .onePerLine
    /// UPDATE … SET i GROUP BY / ORDER BY — nil: jak listy SELECT.
    public var setList: ListLayout?
    public var groupOrderList: ListLayout?
    /// Przecinek na początku kolejnej linii listy zamiast na końcu poprzedniej.
    public var commaBefore = false
    /// Osobne reguły list (UG 29.2): deklaracje parametrów podprogramów, parametry wywołań w PL/SQL, listy kolumn
    /// i wartości INSERT — do marginesu albo element w linii (wyrównany za nawiasem).
    public var parameterDeclarations: ListLayout = .fit
    public var callParameters: ListLayout = .fit
    public var insertLists: ListLayout = .fit
    /// Listy w nawiasach w SQL (IN, argumenty funkcji) i nawiasy zagnieżdżone.
    public var parenthesisLists: ListLayout = .fit
    /// Kolumny i constrainty CREATE TABLE, ALTER TABLE … ADD/MODIFY (…), pola RECORD i atrybuty OBJECT.
    public var ddlColumns: ListLayout = .onePerLine
    /// Zachowanie pojedynczych pustych linii między instrukcjami (więcej pustych linii — jedna).
    public var keepBlankLines = true
    /// Najwięcej pustych linii z rzędu zachowanych ze źródła (przy `keepBlankLines`).
    public var maxBlankLines = 1
    /// Pusta linia przed każdym podprogramem w pakiecie i sekcji deklaracji.
    public var blankLineBetweenSubprograms = false

    // Klauzule i łamanie linii
    public var clauseLayout: ClauseLayout = .rightAligned
    public var andOrPosition: OperatorPosition = .lineStart
    /// Reguły AND/OR osobno dla miejsc warunków (klucz — `ConditionContext.rawValue`; brak — reguła domyślna).
    public var conditions: [String: ConditionLayout] = [:]
    /// JOIN … ON: warunek złączenia w nowej linii (wcięty) albo w linii JOIN.
    public var joinConditionOnNewLine = true
    /// IF/ELSIF … THEN: THEN w osobnej linii.
    public var thenOnNewLine = false
    public var caseLayout: CaseLayout = .auto
    /// Najdłuższe wyrażenie CASE z jedną gałęzią WHEN zostawiane w jednej linii (układ `auto`).
    public var caseInlineLimit = 50
    public var subqueryLayout: SubqueryLayout = .indented
    /// Długie wyrażenia: operator (||, +, -) na początku nowej linii albo na końcu poprzedniej.
    public var operatorPosition: OperatorPosition = .lineStart

    public func condition(_ c: ConditionContext) -> ConditionLayout { conditions[c.rawValue] ?? Self.defaultCondition(c) }
    public mutating func setCondition(_ c: ConditionContext, _ l: ConditionLayout) { conditions[c.rawValue] = l }

    // Odstępy
    /// Spacje wokół operatorów (=, <>, +, ||…); `:=` i `=>` zawsze ze spacjami.
    public var spaceAroundOperators = true
    public var spaceAfterComma = true
    /// Spacja po „(” i przed „)”.
    public var spaceInsideParentheses = false

    // Wyrównanie (UG 29.2 i formatery SQL Developer, Toad, Trivadis)
    /// Deklaracje zmiennych i stałych: typy i `:=`/DEFAULT w kolumnach.
    public var alignDeclarations = true
    /// Parametry podprogramów w osobnych liniach: tryb (IN/OUT), typ i DEFAULT w kolumnach.
    public var alignParameters = false
    /// Parametry nazwane wywołań w osobnych liniach: `=>` w kolumnie.
    public var alignNamedArguments = false
    /// Kolejne przypisania: `:=` w kolumnie.
    public var alignAssignments = true
    /// Kolumny tabel, pola rekordów i atrybuty typów w osobnych liniach: typ, DEFAULT, NOT NULL w kolumnach.
    public var alignColumnDefinitions = true
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
    /// Formatowanie podczas pisania (D205): po Enter opuszczana linia w swoich granicach i wcięcie nowej linii.
    public var formatOnEnter = true

    public init() {}

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ cur: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? cur }
        indent = v(.indent, indent); useTabs = v(.useTabs, useTabs); rightMargin = v(.rightMargin, rightMargin)
        keywordCase = v(.keywordCase, keywordCase); identifierCase = v(.identifierCase, identifierCase)
        listLayout = v(.listLayout, listLayout); commaBefore = v(.commaBefore, commaBefore); keepBlankLines = v(.keepBlankLines, keepBlankLines)
        specialCase = v(.specialCase, specialCase); afterLoad = v(.afterLoad, afterLoad); beforeCompile = v(.beforeCompile, beforeCompile)
        beforeSave = v(.beforeSave, beforeSave); formatOnEnter = v(.formatOnEnter, formatOnEnter)
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
        setList = v(.setList, setList); groupOrderList = v(.groupOrderList, groupOrderList)
        parenthesisLists = v(.parenthesisLists, parenthesisLists); ddlColumns = v(.ddlColumns, ddlColumns)
        conditions = v(.conditions, conditions); caseInlineLimit = v(.caseInlineLimit, caseInlineLimit)
        subqueryLayout = v(.subqueryLayout, subqueryLayout); operatorPosition = v(.operatorPosition, operatorPosition)
        alignColumnDefinitions = v(.alignColumnDefinitions, alignColumnDefinitions)
        // Brak znacznika (częściowy JSON z komendy, agenta, makra) — wartości bieżące, bez migracji. Migrację zapisów
        // sprzed D202 robi odczyt plików (`PreferenceSets.migratingLegacyBeautifier` w PelikanWorkspace).
        defaultsVersion = v(.defaultsVersion, Self.currentDefaultsVersion)
    }

    /// Wersja domyślnych ustawień (1 — D202), zapisywana z ustawieniami.
    public static let currentDefaultsVersion = 1
    public var defaultsVersion = BeautifierOptions.currentDefaultsVersion

    /// Ustawienia domyślne z zachowaniem formatowania automatycznego (także przy Enter) i — opcjonalnie — pisowni specjalnej (przycisk
    /// „Przywróć domyślne”).
    public func restoringDefaults(keepSpecialCase: Bool = true) -> BeautifierOptions {
        var o = BeautifierOptions()
        o.afterLoad = afterLoad; o.beforeCompile = beforeCompile; o.beforeSave = beforeSave; o.formatOnEnter = formatOnEnter
        if keepSpecialCase { o.specialCase = specialCase }
        return o
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
        func shown(_ x: String) -> String { String(x.drop { $0 != ":" && $0 != "=" }.dropFirst().prefix(30)) }
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
                // Słowo, którego wielkie litery mają inną długość (ß → SS) — porównanie dokładne (D205).
                case .identifier, .keyword:
                    if x.uppercased().utf16.count != x.utf16.count {
                        out.append("w=" + x, glued: glued, must: must)
                    } else {
                        out.append("w:" + x.uppercased(), glued: glued, must: must)
                    }
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
        /// Nawias: elementy do marginesu; podzapytanie wcięte z „)” w osobnej linii (kolumna nawiasu).
        var fill = false
        var indentedFrom: Int?
        /// Warunek z AND/OR (klauzula, nawias, WHEN w CASE) i czy w nim złamano linię.
        var cond: Cond?
        var condBroke = false
        /// Wyrażenie CASE: WHEN/ELSE/END w osobnych liniach.
        var multiline = false
        /// SQL: szerokość „rzeki” — najdłuższe (pierwsze) słowo klauzuli instrukcji, co najmniej 6 (SELECT).
        var river = 6
        /// Indeks tokenu, przy którym ramka powstała (formatowanie linii przy Enter — kotwica wyrównania, D205).
        var opener = -1
    }

    /// Nowa ramka (z tokenem, który ją otworzył).
    mutating func push(_ frame: Frame) {
        var f = frame
        f.opener = i
        frames.append(f)
    }

    /// Warunek logiczny w toku: miejsce, kolumna i długość słowa kluczowego, kolumna pierwszego warunku, czy cały
    /// warunek się nie mieści (reguła „tylko gdy się nie mieści”), czy słowo jest słowem klauzuli SQL (wyrównanie
    /// jak słowa klauzul) i czy wyrównanie do słowa jest prawostronne.
    struct Cond {
        var context: BeautifierOptions.ConditionContext
        var keywordColumn: Int
        var keywordLength: Int
        var firstColumn: Int
        var long: Bool
        var sqlClause = false
        var river = true
    }

    /// Śledzenie przebiegu dla formatowania linii przy Enter (D205): miejsce każdego tokenu w wyniku, ramka w chwili
    /// tokenów obserwowanych, stan po ostatnim tokenie opuszczanej linii i fragmenty kopiowane bez zmian.
    struct Trace {
        struct Placed {
            var line: Int
            var column: Int
            var text: String
            var startsLine: Bool
        }
        struct State {
            var nextColumn: Int
        }
        var placed: [Placed?]
        /// Tokeny, dla których zapisać token otwierający bieżącą ramkę i to, czy zaczynały instrukcję.
        var watch: Set<Int> = []
        /// Ramka w chwili tokenu obserwowanego: token otwierający, czy to instrukcja SQL, jej kolumna (przed przesunięciem
        /// słowa otwierającego do rzeki).
        struct FrameInfo {
            var opener: Int
            var isSQL: Bool
            var column: Int
        }
        var frame: [Int: FrameInfo] = [:]
        var statementStart: [Int: Bool] = [:]
        /// Stan zapisywany po przetworzeniu tokenu `after` (przed następnym); przebieg kończy się po tokenie `stop`.
        var after = -1
        var stop = Int.max
        var state: State?
        var raw: [Range<Int>] = []
    }
    var trace: Trace?

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
        // Wyszukiwanie binarne — polecenia są uporządkowane i rozłączne.
        var lo = 0, hi = statements.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if statements[mid].end <= pos { lo = mid + 1 } else { hi = mid }
        }
        return lo < statements.count && statements[lo].start <= pos ? statements[lo].end : source.length
    }

    /// Fragment źródła kopiowany bez zmian (polecenie SQL*Plus, kod Java/JavaScript): od początku linii, jeśli
    /// przed nim są tylko odstępy, w osobnych liniach (albo w bieżącej — `sameLine`); dalej tokeny od `end`,
    /// leksowane od nowa, gdy token źródła przechodzi przez granicę (np. apostrof w PROMPT). Wynik: fragment został
    /// w bieżącej, otwartej linii (`sameLine` i bez znaku nowej linii).
    @discardableResult
    mutating func copyRaw(from start: Int, to end: Int, sameLine: Bool = false) -> Bool {
        trace?.raw.append(start..<max(start, end))
        var from = start
        if !sameLine {
            let lineStart = source.lineRange(for: NSRange(location: start, length: 0)).location
            let prefix = source.substring(with: NSRange(location: lineStart, length: start - lineStart))
            if prefix.allSatisfy({ $0 == " " || $0 == "\t" }) { from = lineStart }
            sourceBlankLines(toks[i])
        }
        var raw = source.substring(with: NSRange(location: from, length: max(0, end - from))).components(separatedBy: "\n")
        if sameLine, !raw.isEmpty { put(raw.removeFirst(), space: needsSpace(prev, toks[i])); rawLines.insert(lines.count) }
        // Fragment w jednej linii w bieżącej linii — linia zostaje otwarta (dalszy ciąg może do niej dołączyć).
        let inLine = sameLine && raw.isEmpty
        if !inLine {
            flush()
            rawLines.formUnion(lines.count..<(lines.count + raw.count))
            lines.append(contentsOf: raw)
        }
        pendingBreak = indentColumns(level)
        statementStart = true
        var j = i
        while j < toks.count, toks[j].start < end { j += 1 }
        if j > 0, toks[j - 1].end > end { toks = Array(toks[..<j]) + Self.tokens(source, from: end) }
        i = j - 1
        return inLine
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
        if trace != nil { place(s, column: column, startsLine: cur.isEmpty) }
        cur += s
    }

    /// Zapis położenia tokenów tekstu `s` (jeden albo kilka tokenów, np. `END IF`, `UNION ALL`, `<<x>>`) — przy
    /// bieżącym tokenie albo kończący się na nim (UNION ALL przesuwa indeks przed wstawieniem).
    mutating func place(_ s: String, column col: Int, startsLine: Bool) {
        guard i < toks.count else { return }
        // Zwykle jeden token (bez leksowania).
        if s.utf16.count == toks[i].end - toks[i].start, s.uppercased() == toks[i].upper {
            trace?.placed[i] = Trace.Placed(line: lines.count, column: col, text: s, startsLine: startsLine)
            return
        }
        let lexer = Lexer(s)
        let pieces = lexer.tokenize().filter { $0.kind != .whitespace && $0.kind != .newline }
        guard !pieces.isEmpty else { return }
        func matches(_ base: Int) -> Bool {
            guard base >= 0, base + pieces.count <= toks.count else { return false }
            return pieces.indices.allSatisfy { lexer.string(pieces[$0]).uppercased() == toks[base + $0].upper }
        }
        guard let base = [i, i - pieces.count + 1].first(where: matches) else { return }
        for (k, p) in pieces.enumerated() {
            trace?.placed[base + k] = Trace.Placed(line: lines.count, column: col + p.start, text: lexer.string(p), startsLine: startsLine && k == 0)
        }
    }

    func cased(_ t: Tok) -> String {
        guard t.isWord else { return t.text }
        // Słowo, którego wielkie litery mają inną długość (ß) — w pisowni źródła (`verify` porównuje je dokładnie).
        if t.upper.utf16.count != t.text.utf16.count { return t.text }
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

    /// Linia kończy się komentarzem `--` (leksowana — `--` w literale nie jest komentarzem). Linia z niedomkniętym
    /// literałem albo komentarzem blokowym — też (nie wolno do niej nic doklejać).
    static func endsWithLineComment(_ line: String) -> Bool {
        let lexer = Lexer(line)
        var last: TokenKind?
        let state = lexer.scan(range: 0..<lexer.text.count, state: .normal) { t in
            if t.kind != .whitespace && t.kind != .newline { last = t.kind }
        }
        return last == .lineComment || state != .normal
    }

    /// Identyfikator zapisywany jak słowo kluczowe w kontekście formatera (`Keywords.formatterContextual`): atrybut
    /// kursora po `%`, słowa DDL (tabela, indeks, widok, MV, ALTER), nagłówek wyzwalacza, STATEMENT w sekcjach wyzwalacza
    /// złożonego, READ w `WITH READ ONLY`, MATCH_RECOGNIZE przed „(”.
    func contextualKeyword(_ t: Tok) -> Bool {
        let p = token(before: t)
        if p?.text == "%" { return Keywords.cursorAttributes.contains(t.upper) }
        guard Keywords.formatterContextual.contains(t.upper), p?.kind != .dot, token(after: t)?.kind != .dot else { return false }
        switch t.upper {
        case "MATCH_RECOGNIZE": return token(after: t)?.kind == .leftParen
        case "READ": return ["WITH", "TRANSACTION"].contains(p?.upper ?? "")
        case "STATEMENT": return unitKind == "COMPOUND" && ["BEFORE", "AFTER"].contains(p?.upper ?? "")
        default:
            if headerKind == "TRIGGER", headerLevel != nil { return true }
            // DDL: nie w zapytaniu (widok, CTAS) i nie jako nazwa kolumny w liście (`(query …`, `, schema …`).
            guard ddlObject != "", !frames.contains(where: { $0.kind == .sql }) else { return false }
            return p?.kind != .leftParen && p?.kind != .comma
        }
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
        // Po kropce — nazwa (pole, kolumna, element pakietu): reguła identyfikatora, nie typu ani słowa kluczowego
        // (`j.doc.date`); znane nazwy — pakiet przed kropką, funkcja wbudowana przed nawiasem — jak bez kwalifikatora,
        // a po `SYS.` (`sys.XMLTYPE`) wszystkie reguły jak bez kwalifikatora.
        if let dot = token(before: t), dot.kind == .dot, token(before: dot)?.upper != "SYS" {
            let next = token(after: t)
            if let c = options.functionCase, next?.kind == .leftParen, SQLWords.functions.contains(t.upper) { return c }
            if let c = options.packageCase, next?.kind == .dot, SQLWords.isPackage(t.upper) { return c }
            return options.identifierCase
        }
        let keyword = t.kind == .keyword ? !keywordAsIdentifier(t) : contextualKeyword(t)
        let base = keyword ? options.keywordCase : options.identifierCase
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
        // Przecinek na początku linii przeniesiony przed komentarz poprzedniego elementu: odstęp jak po przecinku.
        if p.kind == .lineComment, cur == "," { return options.spaceAfterComma }
        if t.kind == .rightParen { return options.spaceInsideParentheses && p.kind != .leftParen }
        if [.comma, .semicolon, .dot].contains(t.kind) { return false }
        if p.kind == .leftParen { return options.spaceInsideParentheses }
        if p.kind == .dot { return false }
        if t.text == "%" || p.text == "%" || t.text == "@" || p.text == "@" { return false }
        if t.text == ".." || p.text == ".." { return false }
        if t.kind == .leftParen {
            // Nazwa tabeli, widoku albo CTE przed listą kolumn — ze spacją (`INSERT INTO emp (…)`, PL/SQL Developer).
            // Słowo DDL spoza wspólnego zbioru słów kluczowych (`LESS THAN (…)`) — jak słowo kluczowe.
            if p.kind == .identifier, Keywords.formatterContextual.contains(p.upper), Self.spacedBeforeParen.contains(p.upper) { return true }
            if p.kind == .identifier || p.kind == .quotedIdentifier { return isObjectNameBeforeColumns() }
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

    /// Nazwa obiektu (z właścicielem) tuż przed „(” jest nazwą tabeli, widoku albo CTE z listą kolumn: INSERT INTO t,
    /// CREATE TABLE t, CREATE VIEW v, REFERENCES t, CREATE INDEX … ON t, WITH x (…).
    func isObjectNameBeforeColumns() -> Bool {
        var j = i - 1
        while j >= 2, toks[j - 1].kind == .dot { j -= 2 }
        guard j >= 1 else { return false }
        let before = toks[j - 1]
        switch before.upper {
        case "INTO": return ["INSERT", "MERGE"].contains(frames.last?.statement ?? "")
        case "TABLE": return ddlObject == "TABLE"
        case "VIEW": return ddlObject == "VIEW"
        case "REFERENCES": return true
        case "ON": return ddlObject == "INDEX"
        case "WITH": return frames.last?.statement == "WITH" || frames.last?.clause == "WITH"
        default: return before.kind == .comma && frames.last?.kind == .sql && frames.last?.clause == "WITH"
        }
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
        if trace != nil { observe() }

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
            // W środku instrukcji SQL albo nawiasu region nie kończy instrukcji: dalej bez nowej instrukcji i złamania.
            let inStatement = frames.contains { $0.kind == .sql || $0.kind == .paren }
            let wasStatementStart = statementStart
            let inLine = copyRaw(from: t.start, to: end, sameLine: sameLine)
            if inStatement {
                statementStart = wasStatementStart
                // Dalszy ciąg instrukcji w kolumnie kontynuacji; przecinek i nawias zamykający — w linii regionu, gdy
                // region był w jednej linii (zaczęty w środku linii, ale wieloliniowy — też kontynuacja).
                let next = i + 1 < toks.count ? toks[i + 1].kind : nil
                let column = frames.last.map { $0.kind == .paren ? $0.column : continuationColumn() } ?? continuationColumn()
                pendingBreak = inLine && (next == .comma || next == .rightParen) ? nil : column
            }
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
            trace?.raw.append(t.start..<end)
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
                      !rawLines.contains(last), !Self.endsWithLineComment(lines[last]) {
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

        // Słowo po kropce to nazwa (`t.offset`, `l.delete`, `r.end`, `x.when`) — nigdy klauzula ani struktura bloku.
        if t.isWord, prev?.kind == .dot {
            put(cased(t), space: needsSpace(prev, t))
            return
        }
        if w == "BETWEEN" { betweenPending = true }
        // MARK: Struktura PL/SQL (poza nawiasami i SQL)
        if !frames.contains(where: { $0.kind == .sql || $0.kind == .paren }) {
            if handlePLSQL(t, w, prevUpper) { return }
            if w == "FORALL", statementStart { forallPending = true }
            if w == "ALTER", statementStart { ddlObject = "ALTER" }
            // Warunek IF/ELSIF/WHILE/EXIT WHEN/WHEN instrukcji CASE: AND/OR wg reguły miejsca.
            // AND/OR wewnątrz wyrażenia CASE w warunku — reguła CASE WHEN (ramka CASE), nie reguła IF/WHILE.
            if ["AND", "OR"].contains(w), frames.last?.kind != .caseExpr, let c = plCond, conditionBreak(t, w, c) { return }
        }
        // AND/OR w warunku w nawiasie (CHECK, WHEN wyzwalacza, ON w MERGE, nawias zagnieżdżony) i w WHEN wyrażenia CASE.
        if ["AND", "OR"].contains(w), let f = frames.last, f.kind == .paren || f.kind == .caseExpr, let c = f.cond {
            if conditionBreak(t, w, c) { frames[frames.count - 1].condBroke = true; return }
        }
        // Długie wyrażenie: łamanie przed operatorem (||, +, -), gdy następny składnik się nie mieści.
        if isBinaryOperator(t), !cur.isEmpty,
           column + 1 + t.text.count + 1 + segmentLength(from: i + 1, stop: []) > options.rightMargin,
           column > curIndentColumns + options.indent {
            let col = expressionContinuationColumn()
            if options.operatorPosition == .lineEnd {
                put(t.text, space: true)
                pendingBreak = col
            } else {
                lineBreak(col)
                put(t.text, space: false)
            }
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
            // Rzeka: kolumna z najdłuższego słowa klauzuli instrukcji (RETURNING, CONNECT, INTERSECT…); słowo
            // rozpoczynające instrukcję wyrównane do niej w prawo (`  WITH`, ` MERGE`) — gdy zaczyna linię.
            if options.clauseLayout == .rightAligned, pendingBreak != nil || cur.isEmpty {
                frame.river = riverWidth(from: i, statement: w)
                let shift = max(0, frame.river - t.text.count)
                if let p = pendingBreak { pendingBreak = p + shift } else { curIndentColumns += shift }
            }
            push(frame)
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
        if ddlOptions, t.isWord, Self.physicalOptions.contains(w), w != "PARTITION" || peek()?.upper == "BY",
           !frames.contains(where: { $0.kind == .sql || $0.kind == .paren }), column > indentColumns(level),
           column + 1 + remainingLength(from: i) > options.rightMargin {
            lineBreak(indentColumns(level))
        }
        // AND z BETWEEN … AND, którego nie obsłużyła reguła warunku (np. w argumencie funkcji) — nie przecieka dalej.
        if w == "AND" { betweenPending = false }
        put(cased(t), space: needsSpace(prev, t))
        if t.text == ":=" { operandColumn = column + 1 }
        if w == "WHEN", ["EXIT", "CONTINUE"].contains(prevUpper) || ["EXIT", "CONTINUE"].contains(prevPrev()?.upper ?? "") {
            plCond = newCond(.exitWhen, keywordLength: 4, stops: [])
        }
    }

    // MARK: Długie wyrażenia i warunki

    /// Warunek zaczynający się po właśnie wstawionym słowie kluczowym (`keywordLength` znaków przed bieżącą kolumną).
    func newCond(_ context: BeautifierOptions.ConditionContext, keywordLength: Int, stops: Set<String>, sqlClause: Bool = false,
                 river: Bool = true, firstColumn: Int? = nil) -> Cond {
        let first = firstColumn ?? column + 1
        return Cond(context: context, keywordColumn: max(0, column - keywordLength), keywordLength: keywordLength, firstColumn: first,
                    long: first + conditionLength(from: i + 1, stops: stops) > options.rightMargin, sqlClause: sqlClause, river: river)
    }

    /// Długość warunku od tokenu `start` do słowa z `stops` (na głębokości 0), średnika albo nawiasu zamykającego.
    func conditionLength(from start: Int, stops: Set<String>) -> Int {
        var depth = 0, len = 0, j = start
        while j < toks.count {
            let k = toks[j]
            if depth == 0, k.kind == .semicolon || k.kind == .comma && stops.contains(",") { break }
            if depth == 0, k.isWord, stops.contains(k.upper) { break }
            if k.kind == .leftParen { depth += 1 }
            if k.kind == .rightParen { if depth == 0 { break }; depth -= 1 }
            if k.kind == .lineComment { return 1000 }
            len += k.text.count + (j > start ? 1 : 0)
            j += 1
        }
        return len
    }

    /// AND/OR warunku wg reguły miejsca (`BeautifierOptions.conditions`): nowa linia z AND/OR na początku (w kolumnie
    /// słowa kluczowego — „rzeka”, pierwszego warunku albo wcięcia) albo na końcu linii; true — token obsłużony.
    mutating func conditionBreak(_ t: Tok, _ w: String, _ c: Cond) -> Bool {
        if w == "AND", betweenPending { betweenPending = false; return false }
        let rule = options.condition(c.context)
        if rule.breaks == .never || rule.breaks == .ifLong && !c.long { return false }
        let position = rule.position ?? options.andOrPosition
        let text = cased(t)
        let col: Int
        switch rule.align {
        case .keyword: col = c.river ? max(0, c.keywordColumn + c.keywordLength - text.count) : c.keywordColumn
        case .firstCondition: col = c.firstColumn
        case .indent: col = c.firstColumn + options.indent
        }
        if position == .lineEnd, prev?.kind != .lineComment {
            put(text, space: true)
            pendingBreak = rule.align == .indent ? col : c.firstColumn
            return true
        }
        lineBreak(col)
        put(text, space: false)
        return true
    }
    /// Kolumna prawej strony `:=` (kontynuacja długiego wyrażenia).
    var operandColumn: Int?
    var forallPending = false
    /// Instrukcja CREATE TABLE/INDEX/VIEW (klauzule fizyczne łamane przy marginesie).
    var ddlOptions = false
    /// Rodzaj obiektu instrukcji DDL (TABLE, INDEX, VIEW; ALTER) i czy był już nawias (lista kolumn).
    var ddlObject = ""
    var ddlParenSeen = false
    /// Warunek PL/SQL w toku (IF, ELSIF, WHILE, EXIT/CONTINUE WHEN, WHEN instrukcji CASE).
    var plCond: Cond?

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
        if nextSignificant(i)?.upper == "FROM", toks[i].upper == "DELETE" { return }
        if options.clauseLayout == .ownLine {
            // Słowo klauzuli w osobnej linii, elementy wcięte pod nim.
            let col = f.column + options.indent
            frames[frames.count - 1].itemColumn = col
            let next = peek()
            if next?.kind == .semicolon || next?.kind == .rightParen || next == nil || next?.kind == .lineComment { return }
            pendingBreak = col
            return
        }
        let target = f.column + f.river + 1
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
        options.clauseLayout == .ownLine ? f.itemColumn : max(f.column + f.river + 1, f.itemColumn)
    }

    /// Kolumna słowa klauzuli: do lewej w kolumnie instrukcji, do prawej — kończy się w kolumnie końca SELECT.
    func clauseColumn(_ f: Frame, _ keyword: String) -> Int {
        // Rzeka: pierwsze słowo klauzuli (ORDER w ORDER BY, LEFT w LEFT JOIN) kończy się w kolumnie końca SELECT.
        options.clauseLayout == .rightAligned ? f.column + max(0, f.river - (keyword.split(separator: " ").first?.count ?? keyword.count)) : f.column
    }

    static let clauseStarts: [[String]] = [
        ["FROM"], ["WHERE"], ["GROUP", "BY"], ["HAVING"], ["ORDER", "SIBLINGS", "BY"], ["ORDER", "BY"], ["CONNECT", "BY"], ["START", "WITH"],
        ["UNION", "ALL"], ["UNION"], ["INTERSECT"], ["MINUS"], ["EXCEPT"], ["INTO"], ["BULK", "COLLECT", "INTO"], ["VALUES"], ["SET"],
        ["RETURNING"], ["RETURN"], ["LEFT", "OUTER", "JOIN"], ["RIGHT", "OUTER", "JOIN"], ["FULL", "OUTER", "JOIN"], ["LEFT", "JOIN"],
        ["RIGHT", "JOIN"], ["FULL", "JOIN"], ["INNER", "JOIN"], ["CROSS", "JOIN"], ["NATURAL", "JOIN"], ["JOIN"], ["USING"],
        ["WHEN", "MATCHED"], ["WHEN", "NOT", "MATCHED"], ["FETCH"], ["OFFSET"], ["FOR", "UPDATE"], ["WINDOW"], ["LOG", "ERRORS"],
        ["CROSS", "APPLY"], ["OUTER", "APPLY"], ["PIVOT"], ["UNPIVOT"], ["MATCH_RECOGNIZE"],
    ]

    /// Szerokość rzeki instrukcji zaczynającej się na tokenie `start`: najdłuższe pierwsze słowo jej klauzul (na tej
    /// samej głębokości nawiasów, do końca instrukcji), od 6 (SELECT) do `maxRiver` (RETURNING, INTERSECT). Dłuższe słowa
    /// (MATCH_RECOGNIZE) i przedrostki złączeń (NATURAL, INNER, LEFT OUTER…) rzeki nie poszerzają — „wiszą” w lewo od
    /// kolumny polecenia, więc dopisanie klauzuli przesuwa polecenie najwyżej do szerokości 9.
    static let maxRiver = 9

    func riverWidth(from start: Int, statement: String) -> Int {
        var width = 6, depth = 0, j = start + 1
        let end = statementEnd(containing: toks[start].start)
        let simple: Set<String> = ["FROM", "WHERE", "HAVING", "INTO", "VALUES", "RETURNING", "WINDOW", "OFFSET", "FETCH", "UNION",
                                   "INTERSECT", "MINUS", "EXCEPT", "PIVOT", "UNPIVOT", "SELECT"]
        while j < toks.count, toks[j].start < end {
            let k = toks[j]
            if k.kind == .leftParen { depth += 1 }
            if k.kind == .rightParen { if depth == 0 { break }; depth -= 1 }
            if k.kind == .semicolon, depth == 0 { break }
            if depth == 0, k.isWord {
                let next = j + 1 < toks.count ? toks[j + 1].upper : ""
                var clause = simple.contains(k.upper)
                switch k.upper {
                case "GROUP", "ORDER", "CONNECT": clause = ["BY", "SIBLINGS"].contains(next)
                case "START": clause = next == "WITH"
                case "SET": clause = ["UPDATE", "MERGE"].contains(statement)
                case "USING", "ON", "WHEN": clause = statement == "MERGE"
                case "LOG": clause = next == "ERRORS"
                case "FOR": clause = next == "UPDATE"
                case "WITH": clause = ["READ", "CHECK"].contains(next)
                default: break
                }
                if clause, k.text.count <= Self.maxRiver { width = max(width, k.text.count) }
            }
            j += 1
        }
        return width
    }

    /// Pierwsze słowa klauzul i słowa kończące element listy albo warunek.
    static let clauseWords: Set<String> = Set(clauseStarts.map { $0[0] }).union(["THEN", "LOOP", "END", "AND", "OR", "WHEN", "ELSE", "SELECT", "CONNECT", "START"])

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
            if w == "WHEN" { frames[frames.count - 1].cond = newCond(.whereClause, keywordLength: 4, stops: ["THEN"], sqlClause: true) }
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
            frames[frames.count - 1].cond = newCond(.whereClause, keywordLength: 5, stops: Self.conditionStops)
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
            guard let c = f.cond else { return false }
            let rule = options.condition(c.context)
            // Na końcu linii — chyba że linię zamknął już komentarz (`-- …`): wtedy AND/OR nie zostaje sam w linii,
            // tylko jak przy układzie „na początku linii”.
            let atStart = (rule.position ?? options.andOrPosition) == .lineStart || prev?.kind == .lineComment
            // Warunek klauzuli SQL wyrównany do słowa: AND/OR jak słowa klauzul (rzeka, do lewej z elementami w kolumnie,
            // w osobnej linii — wcięte).
            if c.sqlClause, rule.align == .keyword, atStart {
                if rule.breaks == .never || rule.breaks == .ifLong && !c.long { return false }
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
            return conditionBreak(t, w, c)
        }
        if w == "ON", f.clause.hasSuffix("JOIN") {
            frames[frames.count - 1].clause = "ON"
            if options.joinConditionOnNewLine {
                lineBreak(options.clauseLayout == .rightAligned ? clauseColumn(f, w) : f.column + options.indent)
                put(cased(t), space: false)
            } else {
                put(cased(t), space: true)
            }
            frames[frames.count - 1].cond = newCond(.joinOn, keywordLength: 2, stops: Self.conditionStops, river: options.clauseLayout == .rightAligned)
            return true
        }
        // DELETE FROM w jednej linii (PL/SQL Developer).
        if w == "FROM", f.statement == "DELETE", prevSignificant(i)?.upper == "DELETE" {
            put(cased(t), space: true)
            frames[frames.count - 1].clause = "FROM"
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
            let keywordColumn = clauseColumn(f, text)
            lineBreak(keywordColumn)
            put(text, space: false)
            i += words.count - 1
            frames[frames.count - 1].clause = words.contains("JOIN") ? "JOIN" : (w == "WHEN" ? "WHEN" : w == "INTO" && words.count == 1 ? "INTO" : words.last!)
            if words.first == "WHEN" { frames[frames.count - 1].clause = "WHEN" }
            alignAfterKeyword()
            // Warunek klauzuli: WHERE, HAVING, START WITH, CONNECT BY.
            let context: BeautifierOptions.ConditionContext? = switch w {
            case "WHERE": .whereClause
            case "HAVING": .having
            case "START", "CONNECT": .hierarchical
            default: nil
            }
            frames[frames.count - 1].cond = context.map {
                var c = newCond($0, keywordLength: text.count, stops: Self.conditionStops, sqlClause: true,
                                firstColumn: frames[frames.count - 1].itemColumn)
                c.keywordColumn = keywordColumn
                return c
            }
            return true
        }
        return false
    }

    /// Słowa kończące warunek klauzuli SQL (następna klauzula).
    static let conditionStops: Set<String> = clauseWords.subtracting(["AND", "OR"])

    /// Wyrażenie CASE: ramka z kolumną słowa CASE (WHEN/ELSE/END w osobnych liniach przy układzie wieloliniowym).
    mutating func openCase(_ t: Tok) {
        let text = cased(t)
        put(text, space: needsSpace(prev, t))
        var frame = Frame(kind: .caseExpr, level: level, column: column - text.count)
        switch options.caseLayout {
        case .inline: frame.multiline = false
        case .multiline: frame.multiline = true
        case .auto:
            // Wieloliniowo, z wyjątkiem bardzo krótkich: jedna gałąź WHEN i całość do progu znaków.
            let (length, whens) = caseExtent(from: i)
            frame.multiline = whens > 1 || length > options.caseInlineLimit
        }
        push(frame)
    }

    /// Długość wyrażenia CASE … END w jednej linii i liczba jego gałęzi WHEN (bez zagnieżdżonych CASE).
    func caseExtent(from start: Int) -> (length: Int, whens: Int) {
        var depth = 0, len = 0, whens = 0, j = start
        while j < toks.count {
            let k = toks[j]
            if k.isWord, k.upper == "CASE" { depth += 1 }
            if k.isWord, k.upper == "WHEN", depth == 1 { whens += 1 }
            if k.kind == .lineComment { len += 1000 }
            len += k.text.count + (j > start ? 1 : 0)
            if k.isWord, k.upper == "END" { depth -= 1; if depth == 0 { break } }
            if k.kind == .semicolon { break }
            j += 1
        }
        return (len, whens)
    }

    mutating func caseBranch(_ t: Tok, _ w: String, _ f: Frame) -> Bool {
        switch w {
        case "END":
            frames.removeLast()
            if f.multiline {
                lineBreak(f.column)
                put(cased(t), space: false)
            } else {
                put(cased(t), space: needsSpace(prev, t))
            }
            return true
        case "WHEN", "ELSE":
            guard f.multiline else { return false }
            lineBreak(f.column + options.indent)
            put(cased(t), space: false)
            // Warunek gałęzi WHEN … THEN: AND/OR wg reguły „CASE WHEN”.
            if w == "WHEN" { frames[frames.count - 1].cond = newCond(.caseWhen, keywordLength: 4, stops: ["THEN"]) }
            return true
        case "THEN":
            frames[frames.count - 1].cond = nil
            return false
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
            let layout = f.clause == "SET" ? options.setList ?? options.listLayout
                : f.clause == "BY" ? options.groupOrderList ?? options.listLayout : options.listLayout
            if layout == .onePerLine || column + 1 + itemLength(from: i + 1) > options.rightMargin {
                breakForList(listColumn(f))
            }
        case .paren where f.wrap:
            breakForList(f.column)
        case .paren where f.fill:
            // Do marginesu: następny element w nowej linii, gdy się nie mieści.
            if column + 1 + itemLength(from: i + 1) > options.rightMargin { breakForList(f.column) }
        case .unit, .declare, .block, .exception, .ifStmt, .loop, .caseStmt, .caseExpr, .paren, .branch:
            if column > options.rightMargin { pendingBreak = continuationColumn() }
        }
    }

    /// Długość elementu listy od tokenu `start` do przecinka, średnika albo nawiasu zamykającego listę.
    func itemLength(from start: Int) -> Int {
        var depth = 0, len = 0, j = start
        while j < toks.count {
            let k = toks[j]
            if depth == 0, k.kind == .comma || k.kind == .semicolon { break }
            if depth == 0, j > start, k.kind == .keyword, Self.clauseWords.contains(k.upper) { break }
            if k.kind == .leftParen { depth += 1 }
            if k.kind == .rightParen { if depth == 0 { len += 1; break }; depth -= 1 }
            if k.kind == .lineComment { return 1000 }
            len += k.text.count + (j > start ? 1 : 0)
            j += 1
        }
        return len
    }

    mutating func breakForList(_ col: Int) {
        if options.commaBefore {
            cur.removeLast()
            lineBreak(max(0, col - 2))
            if trace != nil { place(",", column: column, startsLine: true) }
            cur = ","
        } else {
            pendingBreak = col
        }
    }

    mutating func openParen(_ t: Tok) {
        let space = needsSpace(prev, t)
        // Kolumna słowa przed nawiasem (CHECK, WHEN wyzwalacza, ON w MERGE) — wyrównanie warunku do słowa.
        let keywordColumn = column - (prev?.text.count ?? 0)
        let outer = frames.last
        put("(", space: space)
        let next = peek()
        let sub = next.map { ["SELECT", "WITH"].contains($0.upper) } ?? false
        var frame = Frame(kind: .paren, level: level, column: column, clause: "", wrap: false, subquery: sub)
        if sub, options.subqueryLayout == .indented {
            // Podzapytanie wcięte: treść od nowej linii o wcięcie głębiej niż element klauzuli (albo linia), „)” pod nim.
            let base: Int
            if let o = outer, o.kind == .sql { base = listColumn(o) } else if let o = outer, o.kind == .paren { base = o.column } else { base = curIndentColumns }
            frame.column = base + options.indent
            frame.indentedFrom = base
            pendingBreak = base + options.indent
        }
        if !sub {
            var depth = 0
            var length = 0
            var j = i
            var hasComma = false
            var hasAndOr = false
            while j < toks.count {
                let k = toks[j]
                if k.kind == .leftParen { depth += 1 }
                if k.kind == .rightParen { depth -= 1; if depth == 0 { break } }
                if depth == 1, k.kind == .comma { hasComma = true }
                if depth == 1, k.isWord, ["AND", "OR"].contains(k.upper) { hasAndOr = true }
                if depth == 1, k.isWord, ["SELECT", "CASE"].contains(k.upper) { hasAndOr = false }
                if k.kind == .lineComment { length += 1000 }
                length += k.text.count + 1
                j += 1
            }
            // Reguła listy wg miejsca nawiasu: INSERT (kolumny, VALUES), nagłówek podprogramu, kolumny tabeli, pola
            // rekordu i atrybuty typu, wywołanie w PL/SQL, inne listy w nawiasach.
            let pu = prev?.upper ?? ""
            var layout = options.parenthesisLists
            if let f = outer, f.kind == .sql {
                if ["INSERT", "VALUES"].contains(f.clause) { layout = options.insertLists }
            } else if ["RECORD", "OBJECT"].contains(pu) || ddlObject == "TABLE" && outer?.kind != .paren && !ddlParenSeen
                        && (prev?.kind == .identifier || prev?.kind == .quotedIdentifier) || ddlObject == "ALTER" && ["ADD", "MODIFY"].contains(pu) {
                layout = options.ddlColumns
            } else if outer?.kind != .paren {
                if headerLevel != nil && headerKind != "TRIGGER" { layout = options.parameterDeclarations } else if prev?.isWord == true { layout = options.callParameters }
            }
            if ddlObject != "" { ddlParenSeen = true }
            // Rozmiar typu (`NUMBER(14, 2)`) nigdy nie jest łamany; argumenty PRAGMA — tylko przy marginesie.
            if let p = prev, p.isWord, Self.sizedTypes.contains(p.upper) { hasComma = false }
            if prevPrev()?.upper == "PRAGMA" { layout = .fit }
            frame.wrap = hasComma && (layout == .onePerLine || layout == .fit && column + length > options.rightMargin)
            frame.fill = hasComma && layout == .wrap
            // Warunek w nawiasie: CHECK, WHEN wyzwalacza, ON w MERGE, nawias zagnieżdżony.
            if hasAndOr, !hasComma {
                let context: BeautifierOptions.ConditionContext
                var kc = keywordColumn, kl = prev?.text.count ?? 1
                if pu == "CHECK" {
                    context = .check
                } else if pu == "WHEN", headerKind == "TRIGGER", headerLevel != nil {
                    context = .triggerWhen
                } else if let f = outer, f.kind == .sql, f.clause == "MERGEON" {
                    context = .mergeOn
                    kc = clauseColumn(f, "ON"); kl = 2
                } else {
                    context = .nested
                    kc = column - 1; kl = 1
                }
                frame.cond = Cond(context: context, keywordColumn: max(0, kc), keywordLength: kl, firstColumn: column,
                                  long: column + length > options.rightMargin,
                                  river: context != .mergeOn || options.clauseLayout == .rightAligned)
            }
        }
        if options.spaceInsideParentheses, next?.kind != .rightParen, frame.indentedFrom == nil { frame.column += 1 }
        push(frame)
    }

    mutating func closeParen(_ t: Tok) {
        // Zamknięcie instrukcji SQL podzapytania i samego nawiasu.
        while let f = frames.last, f.kind == .sql { frames.removeLast() }
        if let f = frames.last, f.kind == .paren {
            frames.removeLast()
            // Podzapytanie wcięte i warunek zagnieżdżony złamany w linie: „)” w osobnej linii pod początkiem.
            if let base = f.indentedFrom {
                lineBreak(base)
                put(")", space: false)
                return
            }
            if f.condBroke, f.cond?.context == .nested {
                lineBreak(max(0, f.cond!.firstColumn - 1))
                put(")", space: false)
                return
            }
        }
        put(")", space: needsSpace(prev, t))
    }

    mutating func endStatement() {
        while let f = frames.last, f.kind == .sql || f.kind == .paren { frames.removeLast() }
        betweenPending = false
        operandColumn = nil
        forallPending = false
        ddlOptions = false
        ddlObject = ""
        plCond = nil
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
            ddlObject = toks[j...].prefix(4).first { ["TABLE", "INDEX", "VIEW"].contains($0.upper) }?.upper ?? ""
            ddlParenSeen = false
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
            push(Frame(kind: .declare, level: h))
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
                push(Frame(kind: .declare, level: h))
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
            push(Frame(kind: .declare, level: level))
            pendingBreak = indentColumns(level)
            return true
        case "BEGIN":
            if let f = frames.last, f.kind == .declare {
                frames[frames.count - 1].kind = .block
                sourceBlankLines(t)
                lineBreak(indentColumns(f.level))
            } else {
                beginStatementLine(t)
                push(Frame(kind: .block, level: level))
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
            push(Frame(kind: .ifStmt, level: level))
            put(cased(t), space: false)
            plCond = newCond(.ifCondition, keywordLength: 2, stops: ["THEN"])
            statementStart = false
            return true
        case "ELSIF", "ELSE":
            if let f = frames.last, f.kind == .ifStmt {
                lineBreak(indentColumns(f.level))
                put(cased(t), space: false)
                statementStart = w == "ELSE"
                if w == "ELSE" { pendingBreak = indentColumns(f.level + 1) }
                plCond = w == "ELSIF" ? newCond(.ifCondition, keywordLength: 5, stops: ["THEN"]) : nil
                return true
            }
            if w == "ELSE", statementStart { closeBranch() }
            if let f = frames.last, f.kind == .caseStmt {
                lineBreak(indentColumns(f.level + 1))
                put(cased(t), space: false)
                statementStart = true
                push(Frame(kind: .branch, level: f.level + 1))
                pendingBreak = indentColumns(f.level + 2)
                return true
            }
            return false
        case "THEN":
            if let f = frames.last, [.ifStmt, .caseStmt, .exception].contains(f.kind) {
                plCond = nil
                if options.thenOnNewLine, f.kind == .ifStmt {
                    lineBreak(indentColumns(f.level))
                    put(cased(t), space: false)
                } else {
                    put(cased(t), space: true)
                }
                statementStart = true
                // Treść gałęzi WHEN … THEN (wyjątki, instrukcja CASE): wszystkie instrukcje o poziom głębiej niż WHEN.
                if f.kind != .ifStmt { push(Frame(kind: .branch, level: f.level + 1)) }
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
                // Warunek gałęzi instrukcji CASE (nie lista wyjątków WHEN e1 OR e2).
                if f.kind == .caseStmt { plCond = newCond(.caseWhen, keywordLength: 4, stops: ["THEN"]) }
                return true
            }
            return false
        case "CASE" where statementStart:
            beginStatementLine(t)
            push(Frame(kind: .caseStmt, level: level))
            put(cased(t), space: false)
            statementStart = false
            return true
        case "CASE":
            // Wyrażenie CASE w instrukcji (x := CASE … END): z ramką — jego END nie zamyka bloku.
            openCase(t)
            return true
        case "LOOP":
            if prevUpper == "END" { return false }
            plCond = nil
            if !statementStart { put(cased(t), space: true) } else { beginStatementLine(t); put(cased(t), space: false) }
            push(Frame(kind: .loop, level: statementLevelForLoop()))
            statementStart = true
            pendingBreak = indentColumns(frames.last!.level + 1)
            return true
        case "FOR" where statementStart, "WHILE" where statementStart:
            beginStatementLine(t)
            loopStartLevel = level
            put(cased(t), space: false)
            if w == "WHILE" { plCond = newCond(.whileLoop, keywordLength: 5, stops: ["LOOP"]) }
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
