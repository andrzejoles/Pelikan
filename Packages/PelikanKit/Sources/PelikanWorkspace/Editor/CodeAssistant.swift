import Foundation
import PelikanDB
import PelikanSQL

/// Element listy podpowiedzi Code Assistant (UG 25.4).
public struct CompletionItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case column, table, view, synonym, package, procedure, function, sequence, type, trigger, schema, object
        case variable, constant, parameter, cursor, localType, exception, field, alias, keyword, pseudoColumn, databaseLink
    }
    public var label: String
    public var insertText: String
    public var kind: Kind
    public var detail: String
    public var id: String { "\(kind.rawValue):\(label)" }

    public init(label: String, insertText: String? = nil, kind: Kind, detail: String = "") {
        self.label = label; self.insertText = insertText ?? label; self.kind = kind; self.detail = detail
    }
}

/// Dopasowanie nazw do wpisanego tekstu (PD-CA-007).
public enum CompletionMatch: String, Sendable, Codable, CaseIterable { case startsWith, contains }

/// Wielkość liter wstawianych nazw (PD-CA-007): jak we wpisanym tekście (auto), wielkie, małe, pierwsza wielka, oryginalna.
public enum CompletionCase: String, Sendable, Codable, CaseIterable { case auto, upper, lower, initCap, original }

/// Preferencje Code Assistant (PD-CA-006, PD-CA-007).
public struct CompletionOptions: Sendable, Hashable {
    public var match: CompletionMatch = .startsWith
    public var letterCase: CompletionCase = .auto
    public var minimumCharacters = 1
    public var standardFunctions = true
    /// Pozycja „(all)”: każdy element w osobnej linii, przecinek na początku linii.
    public var allPerLine = false
    public var commaFirst = false
    public init() {}

    public init(_ s: Settings) {
        match = s.codeAssistantMatch; letterCase = s.codeAssistantCase; minimumCharacters = max(1, s.codeAssistantMinChars)
        standardFunctions = s.codeAssistantStandardFunctions; allPerLine = s.codeAssistantAllPerLine; commaFirst = s.codeAssistantCommaFirst
    }
}

/// Wynik podpowiedzi: zakres tekstu do zastąpienia i elementy (już przefiltrowane prefiksem).
public struct CompletionResult: Sendable, Hashable {
    public var replaceRange: Range<Int>
    public var prefix: String
    public var items: [CompletionItem]
}

/// Code Assistant (UG 25.4, PD-CA-001…004): elementy po `obiekt.` (kolumny tabeli i aliasu, elementy pakietu,
/// pola rekordu, %ROWTYPE, kursora, rekordu pętli, `:new`/`:old`, NEXTVAL/CURRVAL, obiekty schematu), a bez
/// kwalifikatora — deklaracje w zasięgu, aliasy i kolumny tabel instrukcji, obiekty schematu i słowa kluczowe.
@MainActor
public enum CodeAssistant {
    /// Minimalna liczba znaków prefiksu dla obiektów schematu i słów kluczowych bez kwalifikatora.
    public static let minimumPrefix = 1

    public static func complete(text: String, offset: Int, metadata: MetadataProvider?, options: CompletionOptions = CompletionOptions()) async -> CompletionResult? {
        if let ut = utplsql(text: text, offset: offset) { return ut }
        let c = CompletionContext.analyze(text, offset: offset)
        guard !c.inLiteralOrComment else { return nil }
        let named = await parameters(text: text, offset: offset, metadata: metadata, options: options)
        if let named, named.prefix.isEmpty { return named }
        var items: [CompletionItem] = []
        if c.afterAt {
            items = (try? await metadata?.databaseLinks())?.map { CompletionItem(label: $0, kind: .databaseLink) } ?? []
        } else if !c.qualifier.isEmpty {
            items = await members(of: c, metadata: metadata, text: text, offset: offset)
        } else {
            items = await unqualified(c, metadata: metadata, options: options)
        }
        var filtered = filter(items, prefix: c.prefix, match: options.match).map { applyCase($0, prefix: c.prefix, letterCase: options.letterCase) }
        // Parametry w notacji nazwanej pasujące do prefiksu — przed zmiennymi i obiektami (PD-CA-001).
        if let named, named.prefix == c.prefix { filtered = named.items + filtered }
        guard !filtered.isEmpty else { return nil }
        // „(all)” — wszystkie kolumny/pola po kwalifikatorze (PD-CA-006).
        let columns = filtered.filter { [.column, .field].contains($0.kind) }
        if !c.qualifier.isEmpty, c.prefix.isEmpty, columns.count >= 2 {
            let ns = text as NSString
            let dot = c.replaceRange.lowerBound
            let qualifierText = qualifier(before: dot, in: ns)
            let q = dot - (qualifierText as NSString).length
            let lineStart = ns.lineRange(for: NSRange(location: q, length: 0)).location
            let indent = String(ns.substring(with: NSRange(location: lineStart, length: q - lineStart)).map { $0 == "\t" ? "\t" : " " })
            filtered.insert(allItem(columns.map(\.insertText), qualifier: qualifierText, indent: indent, options: options), at: 0)
        }
        return CompletionResult(replaceRange: c.replaceRange, prefix: c.prefix, items: filtered)
    }

    /// Kwalifikator z kropką przed pozycją `dot` (np. `e.`, `scott.emp.`, `:new.`) — powtarzany przed kolejnymi
    /// elementami „(all)”.
    static func qualifier(before dot: Int, in ns: NSString) -> String {
        var q = dot - 1
        while q > 0, let s = UnicodeScalar(ns.character(at: q - 1)), CharacterSet.alphanumerics.contains(s) || "_$#.\":".unicodeScalars.contains(s) { q -= 1 }
        return ns.substring(with: NSRange(location: q, length: dot - q))
    }

    /// Pozycja „(all)”: pierwszy element bez kwalifikatora (już wpisany), kolejne z nim; w jednej linii albo po
    /// jednym w linii (z przecinkiem na końcu albo na początku linii).
    static func allItem(_ names: [String], qualifier: String, indent: String, options: CompletionOptions) -> CompletionItem {
        var text = names[0]
        for n in names.dropFirst() {
            if options.allPerLine {
                text += options.commaFirst ? "\n" + String(indent.dropLast(min(2, indent.count))) + ", " + qualifier + n : ",\n" + indent + qualifier + n
            } else {
                text += ", " + qualifier + n
            }
        }
        return CompletionItem(label: L10n.tr("(all)"), insertText: text, kind: .keyword, detail: L10n.tr("Elementów: \(names.count)"))
    }

    /// Wywołanie podprogramu wokół kursora: nazwa przed niezamkniętym „(”, parametry już podane w notacji nazwanej,
    /// wpisywany prefiks bieżącego argumentu i czy to pierwszy argument (PD-CA-001).
    struct CallContext {
        var parts: [String]
        var used: Set<String>
        var prefix: String
        var first: Bool
    }

    static func callContext(text: String, offset: Int) -> CallContext? {
        let ns = text as NSString
        let o = min(offset, ns.length)
        let start = max(0, o - 2000)
        let window = ns.substring(with: NSRange(location: start, length: o - start))
        let wns = window as NSString
        let toks = Lexer(window).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment, .hint].contains($0.kind) }
        func str(_ t: Token) -> String { wns.substring(with: NSRange(location: t.start, length: t.length)) }
        // Bieżący argument: pusty albo sam identyfikator (prefiks nazwy parametru).
        var k = toks.count - 1
        var prefix = ""
        if k >= 0, [.identifier, .keyword].contains(toks[k].kind), toks[k].end == wns.length {
            prefix = str(toks[k])
            k -= 1
        }
        guard k >= 0, [.leftParen, .comma].contains(toks[k].kind) else { return nil }
        // Niezamknięty nawias wywołania i przecinki na jego poziomie.
        var depth = 0
        var open: Int?
        var j = k
        while j >= 0 {
            switch toks[j].kind {
            case .rightParen: depth += 1
            case .leftParen:
                if depth == 0 { open = j } else { depth -= 1 }
            case .semicolon: return nil
            default: break
            }
            if open != nil { break }
            j -= 1
        }
        guard let open, open > 0 else { return nil }
        var parts: [String] = []
        var n = open - 1
        while n >= 0, [.identifier, .quotedIdentifier, .keyword].contains(toks[n].kind) {
            parts.insert(str(toks[n]).uppercased(), at: 0)
            if n > 0, toks[n - 1].kind == .dot { n -= 2 } else { break }
        }
        guard let name = parts.last, !Keywords.isKeyword(name) || parts.count > 1 else { return nil }
        // Parametry już podane: `nazwa =>` na poziomie wywołania.
        var used = Set<String>()
        depth = 0
        var i = open + 1
        while i < toks.count {
            let t = toks[i]
            if t.kind == .leftParen { depth += 1 } else if t.kind == .rightParen { depth -= 1 }
            if depth == 0, t.kind == .operator, str(t) == "=>", i > open + 1, [.identifier, .keyword].contains(toks[i - 1].kind) {
                used.insert(str(toks[i - 1]).uppercased())
            }
            i += 1
        }
        return CallContext(parts: parts, used: used, prefix: prefix, first: k == open)
    }

    /// Parametry podprogramu (lokalnego z zarysu kodu albo z bazy): nazwa i opis.
    static func parameterList(_ parts: [String], text: String, metadata m: MetadataProvider?) async -> [(String, String)] {
        guard let name = parts.last else { return [] }
        var params: [(String, String)] = []
        func collect(_ nodes: [OutlineNode]) {
            for n in nodes {
                if [.procedure, .function].contains(n.kind), n.name.uppercased() == name, params.isEmpty, parts.count == 1 {
                    params = n.children.filter { $0.kind == .parameter }.map { ($0.name, $0.detail) }
                }
                collect(n.children)
            }
        }
        collect(PLSQLOutline.parse(text))
        if params.isEmpty, let m {
            params = (try? await m.arguments(owner: parts.count == 3 ? parts[0] : nil, package: parts.count >= 2 ? parts[parts.count - 2] : nil, name: name)) ?? []
        }
        // Konstruktor typu obiektowego (`typ(` albo `schemat.typ(`): atrybuty typu w kolejności (PD-CA-006).
        if params.isEmpty, let m, parts.count <= 2 {
            params = (try? await m.typeAttributes(owner: parts.count == 2 ? parts[0] : nil, name: name)) ?? []
        }
        return params
    }

    /// Parametry w notacji nazwanej po `nazwa(` i po przecinku w wywołaniu: pozycje `parametr => ` (bez podanych
    /// wcześniej) i — przy pierwszym argumencie — „(all)” z wyrównaniem `=>` (PD-CA-001, PD-CA-006). Z wpisanym
    /// prefiksem pozycje parametrów trafiają na początek zwykłej listy (zmienne jako argumenty pozycyjne zostają).
    static func parameters(text: String, offset: Int, metadata m: MetadataProvider?, options: CompletionOptions) async -> CompletionResult? {
        guard let call = callContext(text: text, offset: offset) else { return nil }
        let ns = text as NSString
        let o = min(offset, ns.length)
        let params = await parameterList(call.parts, text: text, metadata: m).filter { !call.used.contains($0.0.uppercased()) }
        guard !params.isEmpty else { return nil }
        let letterCase: CompletionCase = options.letterCase == .auto ? (call.prefix.isEmpty || call.prefix != call.prefix.uppercased() ? .lower : .upper) : options.letterCase
        let names = params.map { applyCase(CompletionItem(label: $0.0, kind: .column), prefix: "", letterCase: letterCase).insertText }
        var items = zip(names, params).map { CompletionItem(label: $0.0, insertText: $0.0 + " => ", kind: .parameter, detail: $0.1.1) }
        let start = o - (call.prefix as NSString).length
        if !call.prefix.isEmpty {
            items = filter(items, prefix: call.prefix, match: options.match)
            return items.isEmpty ? nil : CompletionResult(replaceRange: start..<o, prefix: call.prefix, items: items)
        }
        if params.count >= 2, call.first {
            let width = names.map(\.count).max() ?? 0
            let lineStart = ns.lineRange(for: NSRange(location: o, length: 0)).location
            let indent = String(repeating: " ", count: o - lineStart)
            let aligned = names.map { $0.padding(toLength: width, withPad: " ", startingAt: 0) + " => " }
            let text = options.allPerLine
                ? aligned.enumerated().map { i, e in i == 0 ? e : (options.commaFirst ? "\n" + String(indent.dropLast(min(2, indent.count))) + ", " + e : ",\n" + indent + e) }.joined()
                : names.map { $0 + " => " }.joined(separator: ", ")
            items.insert(CompletionItem(label: L10n.tr("(all)"), insertText: text, kind: .keyword, detail: L10n.tr("Parametrów: \(params.count)")), at: 0)
        }
        return CompletionResult(replaceRange: o..<o, prefix: "", items: items)
    }

    static let utAnnotations: [(String, String)] = [
        ("suite", "suite(opis)"), ("suitepath", "suitepath(a.b.c)"), ("displayname", "displayname(opis)"), ("test", "test(opis)"),
        ("context", "context(opis)"), ("endcontext", "endcontext"), ("name", "name(nazwa)"), ("beforeall", "beforeall"), ("afterall", "afterall"),
        ("beforeeach", "beforeeach"), ("aftereach", "aftereach"), ("beforetest", "beforetest(procedura)"), ("aftertest", "aftertest(procedura)"),
        ("throws", "throws(wyjątek|-kod)"), ("disabled", "disabled(powód)"), ("rollback", "rollback(auto|manual)"), ("tags", "tags(t1,t2)"),
    ]

    static let utMatchers = [
        "to_equal(", "not_to_equal(", "to_be_null", "to_be_not_null", "to_be_true", "to_be_false", "to_be_between(", "to_be_greater_than(",
        "to_be_greater_or_equal(", "to_be_less_than(", "to_be_less_or_equal(", "to_be_like(", "to_match(", "to_be_empty", "not_to_be_empty",
        "to_have_count(", "to_contain(", "to_be_within(", "to_be_within_pct(", "join_by(", "include(", "exclude(", "unordered", "unordered_columns",
    ]

    /// utPLSQL (UT-CA-001): adnotacje po `--%`, matchery po `ut.expect(…).`, `ut.` → expect / fail.
    static func utplsql(text: String, offset: Int) -> CompletionResult? {
        let ns = text as NSString
        let o = min(offset, ns.length)
        let lineStart = ns.lineRange(for: NSRange(location: o, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: o - lineStart))
        if let r = before.range(of: #"--%([A-Za-z_]*)$"#, options: .regularExpression) {
            let prefix = String(before[r].dropFirst(3))
            let start = o - (prefix as NSString).length
            let items = utAnnotations.filter { $0.0.hasPrefix(prefix.lowercased()) }.map {
                CompletionItem(label: $0.0, insertText: $0.1.contains("(") ? String($0.1.prefix { $0 != "(" }) + "(" : $0.1, kind: .keyword, detail: "--%" + $0.1)
            }
            return items.isEmpty ? nil : CompletionResult(replaceRange: start..<o, prefix: prefix, items: items)
        }
        let window = ns.substring(with: NSRange(location: max(0, o - 400), length: min(400, o)))
        if let r = window.range(of: #"ut\.expect\s*\((?:[^;])*\)\s*\.\s*([A-Za-z_]*)$"#, options: [.regularExpression, .caseInsensitive]) {
            let prefix = String(window[r].reversed().prefix { $0.isLetter || $0 == "_" }.reversed())
            let start = o - (prefix as NSString).length
            let items = utMatchers.filter { $0.hasPrefix(prefix.lowercased()) }.map {
                CompletionItem(label: $0.trimmingCharacters(in: CharacterSet(charactersIn: "(")), insertText: $0, kind: .function, detail: "ut.expect")
            }
            return items.isEmpty ? nil : CompletionResult(replaceRange: start..<o, prefix: prefix, items: items)
        }
        if let r = window.range(of: #"\but\.([A-Za-z_]*)$"#, options: [.regularExpression, .caseInsensitive]) {
            let prefix = String(window[r].dropFirst(3))
            let start = o - (prefix as NSString).length
            let items = [("expect(", "ut.expect(wartość)"), ("fail(", "ut.fail(komunikat)")].filter { $0.0.hasPrefix(prefix.lowercased()) }.map {
                CompletionItem(label: String($0.0.dropLast()), insertText: $0.0, kind: .function, detail: $0.1)
            }
            return items.isEmpty ? nil : CompletionResult(replaceRange: start..<o, prefix: prefix, items: items)
        }
        return nil
    }

    /// Filtr „zaczyna się od” bez rozróżniania wielkości liter, bez duplikatów, kolejność źródeł zachowana.
    static func filter(_ items: [CompletionItem], prefix: String, match: CompletionMatch = .startsWith) -> [CompletionItem] {
        let p = prefix.uppercased()
        var seen = Set<String>()
        let kept = items.filter { i in
            let l = i.label.uppercased()
            guard p.isEmpty || (match == .startsWith ? l.hasPrefix(p) : l.contains(p)) else { return false }
            return seen.insert(l + "|" + i.kind.rawValue).inserted
        }
        // „Zawiera” (PD-CA-007): najpierw nazwy zaczynające się od wpisanego tekstu.
        guard match == .contains, !p.isEmpty else { return kept }
        return kept.filter { $0.label.uppercased().hasPrefix(p) } + kept.filter { !$0.label.uppercased().hasPrefix(p) }
    }

    /// Wielkość liter wstawianego tekstu jak we wpisanym prefiksie (małe → małe, wielkie → wielkie); bez prefiksu —
    /// nazwy słownikowe małymi, deklaracje lokalne w oryginalnej postaci (D23).
    static func applyCase(_ item: CompletionItem, prefix: String, letterCase: CompletionCase = .auto) -> CompletionItem {
        var i = item
        // Preferencja wielkości liter (PD-CA-007); nazwy w cudzysłowie (mieszana wielkość ze słownika) bez zmian.
        let mixed = i.insertText != i.insertText.uppercased() && i.insertText != i.insertText.lowercased()
            && ![.variable, .constant, .parameter, .cursor, .localType, .exception, .alias].contains(i.kind)
        switch letterCase {
        case .upper: if !mixed { i.insertText = i.insertText.uppercased() }; return i
        case .lower: if !mixed { i.insertText = i.insertText.lowercased() }; return i
        case .initCap:
            if !mixed {
                i.insertText = i.insertText.lowercased().split(separator: "_", omittingEmptySubsequences: false)
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "_")
            }
            return i
        case .original: return i
        case .auto: break
        }
        let local: Set<CompletionItem.Kind> = [.variable, .constant, .parameter, .cursor, .localType, .exception, .alias]
        if local.contains(i.kind), prefix.isEmpty { return i }
        let hasLetters = prefix.contains { $0.isLetter }
        if hasLetters, prefix == prefix.uppercased() {
            i.insertText = i.insertText.uppercased()
        } else if i.insertText == i.insertText.uppercased() {
            // Nazwy wymagające cudzysłowu (małe litery w słowniku) pozostają bez zmian.
            i.insertText = i.insertText.lowercased()
        }
        return i
    }

    // MARK: Po kropce

    static func members(of c: CompletionContext, metadata m: MetadataProvider?, text: String = "", offset: Int = 0) async -> [CompletionItem] {
        let q = c.qualifier
        // SELF w ciele typu obiektowego — atrybuty i metody typu (specyfikacja z okna albo z bazy).
        if q == ["SELF"], !c.bindQualifier, let type = enclosingTypeBody(text, offset: offset) {
            if let spec = localTypeSpecification(type.name, in: text) { return typeSpecificationMembers(spec) }
            return await columnItems(owner: type.owner, name: type.name, metadata: m)
        }
        // :new / :old w wyzwalaczu — kolumny tabeli wyzwalacza.
        if c.bindQualifier, ["NEW", "OLD"].contains(q.last ?? ""), let t = c.triggerTable {
            return await columnItems(owner: t.owner, name: t.name, metadata: m)
        }
        if q.count == 1 {
            let name = q[0]
            // 1. Alias albo nazwa tabeli w instrukcji.
            if let t = c.tables.first(where: { $0.matches(name) }) {
                if let sub = t.subquery { return selectItems(sub) }
                return await columnItems(owner: t.owner, name: t.name, metadata: m)
            }
            // 2. Rekord pętli FOR.
            if let src = c.loopRecords[name] {
                return await recordSource(src, context: c, metadata: m)
            }
            // 3. Deklaracja lokalna (zmienna rekordowa, %ROWTYPE, kursor, obiekt).
            if let d = c.declarations.first(where: { $0.name.uppercased() == name }) {
                let r = await declarationMembers(d, context: c, metadata: m)
                if !r.isEmpty { return r }
            }
        }
        // 4. Obiekt bazy: [schemat.]obiekt albo schemat.
        guard let m else { return [] }
        let owner = q.count >= 2 ? q[q.count - 2] : nil
        if let o = try? await m.resolve(owner: owner, name: q.last ?? "") {
            return await objectMembers(o, metadata: m)
        }
        if q.count == 1, let names = try? await m.objectNames(owner: q[0]), !names.isEmpty {
            return names.map { CompletionItem(label: $0.name, kind: kind(ofObjectType: $0.type), detail: $0.type.lowercased()) }
        }
        return []
    }

    static func objectMembers(_ o: DBObject, metadata m: MetadataProvider) async -> [CompletionItem] {
        switch o.type {
        case .table, .view, .materializedView:
            return ((try? await m.columns(of: o)) ?? []).map { CompletionItem(label: $0.name, kind: .column, detail: $0.detail) }
        case .sequence:
            return [CompletionItem(label: "NEXTVAL", kind: .pseudoColumn), CompletionItem(label: "CURRVAL", kind: .pseudoColumn)]
        case .package, .type:
            let children = (try? await m.children(of: o)) ?? []
            return children.filter { $0.kind == .subprogram || $0.kind == .attribute }.map {
                CompletionItem(label: $0.name, kind: $0.kind == .attribute ? .field : .procedure, detail: $0.detail)
            }
        default:
            return []
        }
    }

    static func columnItems(owner: String?, name: String, metadata m: MetadataProvider?) async -> [CompletionItem] {
        guard let m, let o = try? await m.resolve(owner: owner, name: name) else { return [] }
        return await objectMembers(o, metadata: m)
    }

    /// Kolumny z listy SELECT podzapytania (alias albo nazwa kolumny).
    static func selectItems(_ query: String) -> [CompletionItem] {
        SelectListParser.items(query).compactMap { ($0.alias ?? $0.column).map { CompletionItem(label: $0, kind: .field) } }
    }

    /// Pola rekordu z kursora (nazwa) albo zapytania.
    static func recordSource(_ src: String, context c: CompletionContext, metadata m: MetadataProvider?) async -> [CompletionItem] {
        // Najpierw nazwa kursora (np. C_SELECTED — zawiera „SELECT”, a nie jest zapytaniem).
        if let cur = c.declarations.first(where: { $0.kind == .cursor && $0.name.uppercased() == src }) {
            return await cursorFields(cur, context: c, metadata: m)
        }
        if src.uppercased().contains("SELECT") { return await queryFields(src, metadata: m) }
        return []
    }

    static func cursorFields(_ cur: OutlineNode, context c: CompletionContext, metadata m: MetadataProvider?) async -> [CompletionItem] {
        guard let q = c.cursorQueries[cur.name.uppercased()] else { return [] }
        return await queryFields(q, metadata: m)
    }

    /// Pola wyniku zapytania: nazwy z listy SELECT, a dla `*` / `t.*` — kolumny tabel z FROM.
    static func queryFields(_ query: String, metadata m: MetadataProvider?) async -> [CompletionItem] {
        var out: [CompletionItem] = []
        let ctx = CompletionContext.analyze(query, offset: (query as NSString).length)
        for item in SelectListParser.items(query) {
            if item.isStar {
                for t in ctx.tables where item.qualifier == nil || t.matches(item.qualifier!) {
                    out += await columnItems(owner: t.owner, name: t.name, metadata: m).map { var x = $0; x.kind = .field; return x }
                }
            } else if let n = item.alias ?? item.column {
                out.append(CompletionItem(label: n, kind: .field))
            }
        }
        return out
    }

    /// Elementy zmiennej: `tabela%ROWTYPE`, `kursor%ROWTYPE`, typ rekordowy lokalny, typ obiektowy bazy.
    static func declarationMembers(_ d: OutlineNode, context c: CompletionContext, metadata m: MetadataProvider?) async -> [CompletionItem] {
        if d.kind == .cursor { return await cursorFields(d, context: c, metadata: m) }
        let type = d.detail.trimmingCharacters(in: .whitespaces)
        let upper = type.uppercased()
        if upper.hasSuffix("%ROWTYPE") {
            let base = String(upper.dropLast("%ROWTYPE".count))
            if let cur = c.declarations.first(where: { $0.kind == .cursor && $0.name.uppercased() == base }) {
                return await cursorFields(cur, context: c, metadata: m)
            }
            let parts = base.split(separator: ".").map(String.init)
            return await columnItems(owner: parts.count > 1 ? parts[0] : nil, name: parts.last ?? base, metadata: m)
        }
        if let decl = c.typeDeclarations[upper] {
            let fields = recordFields(decl)
            if !fields.isEmpty { return fields.map { CompletionItem(label: $0.name, kind: .field, detail: $0.type) } }
            return collectionMethods(decl)
        }
        // Typ obiektowy bazy.
        guard let m, !upper.isEmpty, !upper.contains("%"), let o = try? await m.resolve(owner: nil, name: upper), o.type == .type else { return [] }
        return await objectMembers(o, metadata: m)
    }

    /// Metody kolekcji (PD-CA-002) dla `TYPE t IS TABLE OF …` / `VARRAY(n) OF …`; tablica asocjacyjna (INDEX BY)
    /// bez EXTEND, TRIM i LIMIT.
    static func collectionMethods(_ declaration: String) -> [CompletionItem] {
        let up = declaration.uppercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let varray = up.range(of: #"\b(VARRAY|VARYING ARRAY)\b"#, options: .regularExpression) != nil
        guard varray || up.range(of: #"\bTABLE OF\b"#, options: .regularExpression) != nil else { return [] }
        let associative = up.contains(" INDEX BY ")
        var methods: [(String, String)] = [("COUNT", "integer"), ("FIRST", L10n.tr("pierwszy indeks")), ("LAST", L10n.tr("ostatni indeks")),
                                           ("NEXT(", L10n.tr("następny indeks")), ("PRIOR(", L10n.tr("poprzedni indeks")),
                                           ("EXISTS(", "boolean"), ("DELETE", L10n.tr("usuwa elementy"))]
        if !associative { methods += [("EXTEND", L10n.tr("dodaje elementy")), ("TRIM", L10n.tr("usuwa elementy z końca"))] }
        if varray { methods.append(("LIMIT", L10n.tr("maksymalna liczba elementów"))) }
        return methods.map { CompletionItem(label: $0.0.trimmingCharacters(in: CharacterSet(charactersIn: "(")), insertText: $0.0, kind: .function, detail: $0.1) }
    }

    /// Typ obiektowy, którego ciało (`CREATE TYPE BODY`) obejmuje pozycję.
    static func enclosingTypeBody(_ text: String, offset: Int) -> (owner: String?, name: String)? {
        let ns = text as NSString
        let head = ns.substring(to: min(offset, ns.length))
        let pattern = #"(?i)\bcreate\s+(?:or\s+replace\s+)?(?:(?:editionable|noneditionable)\s+)?type\s+body\s+(?:("?[\w$#]+"?)\s*\.\s*)?("?[\w$#]+"?)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.matches(in: head, range: NSRange(location: 0, length: (head as NSString).length)).last else { return nil }
        // Ciało typu kończy się „/” w osobnej linii — za nim pozycja nie należy już do typu.
        let after = (head as NSString).substring(from: m.range.upperBound)
        if after.range(of: #"(?m)^\s*/\s*$"#, options: .regularExpression) != nil { return nil }
        func clean(_ r: NSRange) -> String? {
            guard r.location != NSNotFound else { return nil }
            let s = (head as NSString).substring(with: r)
            return s.hasPrefix("\"") ? String(s.dropFirst().dropLast()) : s.uppercased()
        }
        guard let name = clean(m.range(at: 2)) else { return nil }
        return (clean(m.range(at: 1)), name)
    }

    /// Treść specyfikacji typu obiektowego z tego samego tekstu: lista w nawiasie po `AS|IS OBJECT`.
    static func localTypeSpecification(_ name: String, in text: String) -> String? {
        let pattern = #"(?is)\bcreate\s+(?:or\s+replace\s+)?(?:(?:editionable|noneditionable)\s+)?type\s+(?:"?[\w$#]+"?\s*\.\s*)?"?"# + NSRegularExpression.escapedPattern(for: name) + #""?\s+(?:force\s+)?(?:authid\s+\w+\s+)?(?:as|is|under\s+[\w$#."]+)\s*(?:object\s*)?\("#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        let ns = text as NSString
        var depth = 0
        var k = m.range.upperBound
        let start = k
        while k < ns.length {
            let ch = ns.character(at: k)
            if ch == 0x28 { depth += 1 }
            if ch == 0x29 { if depth == 0 { return ns.substring(with: NSRange(location: start, length: k - start)) }; depth -= 1 }
            k += 1
        }
        return nil
    }

    /// Atrybuty i metody ze specyfikacji typu (elementy rozdzielone przecinkami na najwyższym poziomie).
    static func typeSpecificationMembers(_ spec: String) -> [CompletionItem] {
        var parts: [String] = [""]
        var depth = 0
        for ch in spec {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1 }
            if ch == ",", depth == 0 { parts.append("") } else { parts[parts.count - 1].append(ch) }
        }
        let modifiers: Set<String> = ["MEMBER", "STATIC", "MAP", "ORDER", "CONSTRUCTOR", "OVERRIDING", "FINAL", "NOT", "INSTANTIABLE"]
        var out: [CompletionItem] = []
        for p in parts {
            // Komentarze w specyfikacji pomijane.
            let clean = p.replacingOccurrences(of: #"--[^\n]*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
            let words = clean.split(whereSeparator: { $0.isWhitespace || $0 == "(" }).map(String.init)
            guard let first = words.first else { continue }
            if modifiers.contains(first.uppercased()) {
                guard let k = words.firstIndex(where: { ["PROCEDURE", "FUNCTION"].contains($0.uppercased()) }), k + 1 < words.count else { continue }
                let isFunction = words[k].uppercased() == "FUNCTION"
                out.append(CompletionItem(label: words[k + 1], kind: isFunction ? .function : .procedure, detail: words[k].lowercased()))
            } else {
                out.append(CompletionItem(label: first, kind: .field, detail: words.dropFirst().joined(separator: " ")))
            }
        }
        return out
    }

    /// Pola typu `TYPE t IS RECORD (pole typ, …)`.
    static func recordFields(_ declaration: String) -> [(name: String, type: String)] {
        guard let open = declaration.range(of: "("), declaration.uppercased().contains("RECORD") else { return [] }
        var depth = 0
        var parts: [String] = [""]
        for ch in declaration[open.upperBound...] {
            if ch == "(" { depth += 1 }
            if ch == ")" { if depth == 0 { break }; depth -= 1 }
            if ch == ",", depth == 0 { parts.append("") } else { parts[parts.count - 1].append(ch) }
        }
        return parts.compactMap { p in
            let words = p.split(whereSeparator: { $0.isWhitespace })
            guard let n = words.first else { return nil }
            return (String(n), words.dropFirst().joined(separator: " "))
        }
    }

    // MARK: Bez kwalifikatora

    static func unqualified(_ c: CompletionContext, metadata m: MetadataProvider?, options: CompletionOptions = CompletionOptions()) async -> [CompletionItem] {
        var out: [CompletionItem] = []
        for d in c.declarations {
            out.append(CompletionItem(label: d.name, kind: declarationKind(d.kind), detail: d.detail))
        }
        for (name, _) in c.loopRecords.sorted(by: { $0.key < $1.key }) { out.append(CompletionItem(label: name.lowercased(), kind: .variable, detail: "record")) }
        if c.inSQLStatement {
            for t in c.tables {
                if let a = t.alias { out.append(CompletionItem(label: a.lowercased(), kind: .alias, detail: t.name.isEmpty ? "(select …)" : t.name)) }
            }
            // Kolumny tabel instrukcji bez aliasu (UG 25.4: kolumny tabel DML).
            for t in c.tables where t.subquery == nil {
                out += await columnItems(owner: t.owner, name: t.name, metadata: m)
            }
        }
        guard c.prefix.count >= max(minimumPrefix, options.minimumCharacters) else { return out }
        let p = c.prefix.uppercased()
        // Dopasowanie z preferencji (PD-CA-007): „zawiera” obejmuje też obiekty, synonimy i słowa kluczowe; nazwy
        // zaczynające się od prefiksu pierwsze (limit nie wycina ich na rzecz dopasowań w środku).
        func matching<T>(_ list: [T], limit: Int, name: @escaping (T) -> String) -> [T] {
            let starts = Array(list.lazy.filter { name($0).hasPrefix(p) }.prefix(limit))
            guard options.match == .contains, starts.count < limit else { return starts }
            return starts + list.lazy.filter { !name($0).hasPrefix(p) && name($0).contains(p) }.prefix(limit - starts.count)
        }
        if let m, let schema = try? await m.currentSchema(), let names = try? await m.objectNames(owner: schema) {
            out += matching(names, limit: 300) { $0.name }.map {
                CompletionItem(label: $0.name, kind: kind(ofObjectType: $0.type), detail: $0.type.lowercased())
            }
            // Obiekty dostępne przez synonimy publiczne (PD-CA-003) — po obiektach własnego schematu.
            if schema != "PUBLIC", let pub = try? await m.objectNames(owner: "PUBLIC") {
                out += matching(pub, limit: 200) { $0.name }.map {
                    CompletionItem(label: $0.name, kind: .synonym, detail: L10n.tr("synonim publiczny"))
                }
            }
        }
        out += matching(Keywords.reserved.union(Keywords.plsql).union(Keywords.sql).sorted(), limit: .max) { $0 }.map { CompletionItem(label: $0, kind: .keyword) }
        // Funkcje standardowe SQL (PD-CA-007).
        if options.standardFunctions {
            out += OracleDocs.sqlFunctions.filter { options.match == .contains ? $0.contains(p) : $0.hasPrefix(p) }.sorted()
                .map { CompletionItem(label: $0, kind: .function, detail: L10n.tr("funkcja SQL")) }
        }
        return out
    }

    static func declarationKind(_ k: OutlineNode.Kind) -> CompletionItem.Kind {
        switch k {
        case .constant: .constant
        case .parameter: .parameter
        case .cursor: .cursor
        case .typeDeclaration: .localType
        case .exception: .exception
        case .procedure: .procedure
        case .function: .function
        default: .variable
        }
    }

    static func kind(ofObjectType t: String) -> CompletionItem.Kind {
        switch t {
        case "TABLE": .table
        case "VIEW", "MATERIALIZED VIEW": .view
        case "SYNONYM": .synonym
        case "PACKAGE": .package
        case "PROCEDURE": .procedure
        case "FUNCTION": .function
        case "SEQUENCE": .sequence
        case "TYPE": .type
        case "TRIGGER": .trigger
        default: .object
        }
    }
}
