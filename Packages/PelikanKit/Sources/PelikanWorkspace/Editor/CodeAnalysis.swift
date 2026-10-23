import Foundation
import PelikanDB
import PelikanSQL

/// Problem w tekście okna (podkreślenie w edytorze, lista problemów): nieznana nazwa albo wynik inspekcji kodu.
public struct EditorDiagnostic: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Hashable { case error, warning, info }
    public enum Source: String, Sendable, Hashable { case names, inspection }
    /// Zakres w tekście (UTF-16).
    public var range: Range<Int>
    public var severity: Severity
    public var source: Source
    /// Kod problemu (np. `unknown-table`, `unused-variable`).
    public var code: String
    public var message: String
    public var id: String { "\(source.rawValue):\(code):\(range.lowerBound)" }

    public init(range: Range<Int>, severity: Severity, source: Source, code: String, message: String) {
        self.range = range; self.severity = severity; self.source = source; self.code = code; self.message = message
    }

    /// Linia (od 1) początku problemu w tekście.
    public func line(in text: String) -> Int {
        let ns = text as NSString
        let end = min(range.lowerBound, ns.length)
        return ns.substring(to: end).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}

/// Znaczące tokeny tekstu (bez odstępów i komentarzy) z tekstem i wielkimi literami.
struct SQLToken: Sendable, Hashable {
    let kind: TokenKind
    let start: Int
    let end: Int
    let text: String
    let upper: String

    var isWord: Bool { kind == .identifier || kind == .keyword || kind == .quotedIdentifier }
    /// Nazwa identyfikatora (cudzysłowy zdjęte, bez nich — wielkie litery).
    var name: String { kind == .quotedIdentifier ? String(text.dropFirst().dropLast()) : upper }

    static func significant(_ text: String) -> [SQLToken] {
        let ns = text as NSString
        return Lexer(text).tokenize().filter { !$0.isTrivia }.map {
            let s = ns.substring(with: NSRange(location: $0.start, length: $0.length))
            return SQLToken(kind: $0.kind, start: $0.start, end: $0.start + $0.length, text: s, upper: s.uppercased())
        }
    }
}

// MARK: - Rozwiązywanie nazw (DG-RES-001)

/// Źródło metadanych dla rozwiązywania nazw (aplikacja: słownik bazy przez MetadataProvider; testy: atrapa).
public protocol NameResolutionSource: Sendable {
    /// Tabela, widok, widok zmaterializowany albo synonim o tej nazwie (z właścicielem albo w bieżącym schemacie / publiczny).
    func relationExists(owner: String?, name: String) async -> Bool
    /// Kolumny relacji (wielkie litery) albo nil, gdy nieznane.
    func columns(owner: String?, relation: String) async -> [String]?
    /// Jakikolwiek obiekt (pakiet, sekwencja, funkcja…) albo schemat o tej nazwie — kwalifikator, który nie jest aliasem.
    func objectOrSchemaExists(_ name: String) async -> Bool
}

public enum NameResolver {
    /// Odwołanie do relacji w poleceniu: nazwa, właściciel, alias i zakres nazwy w tekście.
    struct Relation {
        var owner: String?
        var name: String
        var alias: String?
        var range: Range<Int>
        var isCTE = false
    }

    static let clauseEnd: Set<String> = ["WHERE", "GROUP", "ORDER", "HAVING", "CONNECT", "START", "UNION", "INTERSECT", "MINUS", "EXCEPT",
                                         "ON", "USING", "SET", "VALUES", "FETCH", "OFFSET", "FOR", "MODEL", "WINDOW", "RETURNING", "RETURN",
                                         "LOG", "WHEN", "INTO", "SELECT", "PIVOT", "UNPIVOT", "SAMPLE", "PARTITION", "AS", "LIMIT"]
    static let joinWords: Set<String> = ["JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "NATURAL", "LATERAL", "APPLY"]
    static let pseudoColumns: Set<String> = ["ROWID", "ROWNUM", "ORA_ROWSCN", "LEVEL", "NEXTVAL", "CURRVAL", "COLUMN_VALUE", "OBJECT_VALUE",
                                             "OBJECT_ID", "XMLDATA", "SYS_NC_ROWINFO$"]

    /// Polecenia SQL w tekście (także osadzone w PL/SQL): zakresy tokenów od słowa SELECT/INSERT/UPDATE/DELETE/MERGE/WITH
    /// rozpoczynającego polecenie do średnika na poziomie nawiasów polecenia.
    static func statements(_ t: [SQLToken]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        let starters: Set<String> = ["SELECT", "INSERT", "UPDATE", "DELETE", "MERGE", "WITH"]
        while i < t.count {
            let prev = i > 0 ? t[i - 1] : nil
            let startsStatement = starters.contains(t[i].upper) && t[i].isWord
                && (prev == nil || prev!.kind == .semicolon || prev!.kind == .slash
                    || ["BEGIN", "THEN", "ELSE", "LOOP", "DECLARE", "IS", "AS", "EXCEPTION"].contains(prev!.upper) && prev!.isWord
                    || (prev!.kind == .rightParen && false))
                && !(t[i].upper == "UPDATE" && prev?.upper == "FOR") && !(t[i].upper == "DELETE" && prev?.upper == "ON")
            guard startsStatement else { i += 1; continue }
            var depth = 0, j = i
            while j < t.count {
                if t[j].kind == .leftParen { depth += 1 } else if t[j].kind == .rightParen { depth -= 1; if depth < 0 { break } }
                if t[j].kind == .semicolon && depth <= 0 { break }
                j += 1
            }
            out.append(i..<j)
            i = j + 1
        }
        return out
    }

    /// Relacje polecenia (FROM, JOIN, UPDATE, INSERT INTO, MERGE INTO, DELETE FROM, USING) i nazwy CTE.
    static func relations(_ t: [SQLToken], _ range: Range<Int>) -> [Relation] {
        var out: [Relation] = []
        var ctes = Set<String>()
        // WITH nazwa AS ( … ), nazwa2 AS ( … )
        var i = range.lowerBound
        if t[i].upper == "WITH" {
            var j = i + 1
            if j < range.upperBound, ["FUNCTION", "PROCEDURE"].contains(t[j].upper) { return [] }
            while j + 1 < range.upperBound, t[j].isWord {
                ctes.insert(t[j].name)
                var k = j + 1
                if k < range.upperBound, t[k].kind == .leftParen { var d = 0; repeat { if t[k].kind == .leftParen { d += 1 } else if t[k].kind == .rightParen { d -= 1 }; k += 1 } while k < range.upperBound && d > 0 }
                guard k < range.upperBound, t[k].upper == "AS" else { break }
                k += 1
                guard k < range.upperBound, t[k].kind == .leftParen else { break }
                var d = 0
                repeat { if t[k].kind == .leftParen { d += 1 } else if t[k].kind == .rightParen { d -= 1 }; k += 1 } while k < range.upperBound && d > 0
                if k < range.upperBound, t[k].kind == .comma { j = k + 1 } else { break }
            }
        }
        let starter = t[range.lowerBound].upper
        func readRelation(at k: Int) -> (Relation, Int)? {
            guard k < range.upperBound, t[k].kind == .identifier || t[k].kind == .quotedIdentifier else { return nil }
            var owner: String?
            var name = t[k].name
            var start = t[k].start, end = t[k].end
            var n = k + 1
            if n + 1 < range.upperBound, t[n].kind == .dot, t[n + 1].kind == .identifier || t[n + 1].kind == .quotedIdentifier {
                owner = name; name = t[n + 1].name; end = t[n + 1].end; n += 2
            }
            // Funkcja tabelaryczna albo link bazy — poza zakresem sprawdzania.
            if n < range.upperBound, t[n].kind == .leftParen { return nil }
            if n < range.upperBound, t[n].text == "@" { return nil }
            if n < range.upperBound, t[n].kind == .operator, t[n].text.hasPrefix("@") { return nil }
            _ = start
            var alias: String?
            if n < range.upperBound, t[n].upper == "AS", n + 1 < range.upperBound, t[n + 1].isWord { alias = t[n + 1].name; n += 2 }
            else if n < range.upperBound, t[n].kind == .identifier || t[n].kind == .quotedIdentifier, !clauseEnd.contains(t[n].upper), !joinWords.contains(t[n].upper) {
                alias = t[n].name; n += 1
            }
            start = t[k].start
            return (Relation(owner: owner, name: name, alias: alias, range: start..<end, isCTE: owner == nil && ctes.contains(name)), n)
        }
        i = range.lowerBound
        // Poziomy nawiasów z aktywną listą FROM (przecinek dodaje relację tylko na tym poziomie; ON/USING jej nie kończą).
        var fromDepths = Set<Int>()
        var depth = 0
        while i < range.upperBound {
            let tk = t[i]
            if tk.kind == .leftParen { depth += 1; i += 1; continue }
            if tk.kind == .rightParen { fromDepths = fromDepths.filter { $0 < depth }; depth -= 1; i += 1; continue }
            let inFrom = fromDepths.contains(depth)
            let prev = i > range.lowerBound ? t[i - 1] : nil
            var next: Int?
            switch tk.isWord ? tk.upper : "" {
            case "FROM":
                fromDepths.insert(depth); next = i + 1
            case "JOIN":
                next = i + 1
            case "USING" where starter == "MERGE":
                next = i + 1
            case "INTO" where prev?.upper == "INSERT" || prev?.upper == "MERGE" || (prev?.upper == "ALL" && false):
                next = i + 1
            case "UPDATE" where i == range.lowerBound:
                next = i + 1
            case "TABLE" where prev?.upper == "LOCK":
                next = i + 1
            case "":
                break
            default:
                if clauseEnd.contains(tk.upper), !["ON", "USING", "AS", "PARTITION"].contains(tk.upper) { fromDepths.remove(depth) }
            }
            if tk.kind == .comma && inFrom { next = i + 1 }
            if let k = next, let (rel, n) = readRelation(at: k) {
                out.append(rel)
                i = n
                continue
            }
            i += 1
        }
        return out
    }

    /// Relacja (właściciel, nazwa) o aliasie albo nazwie `qualifier` w poleceniu obejmującym pozycję.
    public static func relation(qualifier: String, at offset: Int, in text: String) -> (owner: String?, name: String)? {
        let t = SQLToken.significant(text), q = qualifier.uppercased()
        for st in statements(t) where st.lowerBound < t.count && t[st.lowerBound].start <= offset
            && offset <= (st.upperBound < t.count ? t[st.upperBound].end : Int.max) {
            if let r = relations(t, st).first(where: { !$0.isCTE && ($0.alias == q || $0.name == q) }) { return (r.owner, r.name) }
        }
        return nil
    }

    /// Nieznane relacje, kolumny po aliasie i kwalifikatory, które nie są aliasem ani obiektem.
    public static func unresolved(in text: String, source: any NameResolutionSource) async -> [EditorDiagnostic] {
        let t = SQLToken.significant(text)
        var out: [EditorDiagnostic] = []
        var relationCache: [String: Bool] = [:]
        var columnCache: [String: [String]?] = [:]
        var objectCache: [String: Bool] = [:]
        for st in statements(t) {
            let rels = relations(t, st)
            var aliases: [String: Relation] = [:]
            for r in rels {
                if r.isCTE { if let a = r.alias { aliases[a] = r }; aliases[r.name] = r; continue }
                let key = "\(r.owner ?? "").\(r.name)"
                let exists: Bool
                if let c = relationCache[key] { exists = c } else {
                    exists = await source.relationExists(owner: r.owner, name: r.name)
                    relationCache[key] = exists
                }
                if !exists {
                    out.append(EditorDiagnostic(range: r.range, severity: .error, source: .names, code: "unknown-table",
                                                message: L10n.tr("Nieznana tabela albo widok: \(r.owner.map { "\($0)." } ?? "")\(r.name)")))
                    continue
                }
                aliases[r.alias ?? r.name] = r
                if r.alias != nil { aliases[r.name] = aliases[r.name] ?? r }
            }
            // q.kolumna: kolumna znanej relacji
            var i = st.lowerBound
            while i + 2 < st.upperBound {
                defer { i += 1 }
                guard t[i].kind == .identifier || t[i].kind == .quotedIdentifier, t[i + 1].kind == .dot,
                      t[i + 2].kind == .identifier || t[i + 2].kind == .quotedIdentifier || t[i + 2].kind == .keyword else { continue }
                // Część dłuższej ścieżki (schemat.tabela.kolumna) albo wywołanie (pakiet.funkcja(…)) — pomijane.
                if i > st.lowerBound, t[i - 1].kind == .dot { continue }
                if i + 3 < st.upperBound, t[i + 3].kind == .dot || t[i + 3].kind == .leftParen { continue }
                if t[i + 2].upper == "*" { continue }
                let q = t[i].name, col = t[i + 2].name
                if let r = aliases[q] {
                    guard !r.isCTE, !pseudoColumns.contains(col) else { continue }
                    let key = "\(r.owner ?? "").\(r.name)"
                    let cols: [String]?
                    if let c = columnCache[key] { cols = c } else {
                        cols = await source.columns(owner: r.owner, relation: r.name)
                        columnCache[key] = cols
                    }
                    if let cols, !cols.contains(col) {
                        out.append(EditorDiagnostic(range: t[i + 2].start..<t[i + 2].end, severity: .error, source: .names, code: "unknown-column",
                                                    message: L10n.tr("Kolumna \(col) nie istnieje w \(r.name)")))
                    }
                } else if !rels.isEmpty, rels.allSatisfy({ !$0.isCTE || true }) {
                    // Kwalifikator spoza aliasów: obiekt (pakiet, sekwencja), schemat albo zmienna PL/SQL — błąd tylko,
                    // gdy żadnym z nich nie jest (zmienne rekordowe w PL/SQL pomijane: polecenie w bloku).
                    let insidePLSQL = st.lowerBound > 0 && t[..<st.lowerBound].contains { ["BEGIN", "DECLARE"].contains($0.upper) }
                    if insidePLSQL { continue }
                    let known: Bool
                    if let c = objectCache[q] { known = c } else { known = await source.objectOrSchemaExists(q); objectCache[q] = known }
                    if !known {
                        out.append(EditorDiagnostic(range: t[i].start..<t[i].end, severity: .error, source: .names, code: "unknown-alias",
                                                    message: L10n.tr("Nieznany alias albo obiekt: \(q)")))
                    }
                }
            }
        }
        return out
    }
}

/// Metadane do rozwiązywania nazw ze słownika bazy (sesja metadanych połączenia; wyniki w pamięci podręcznej dostawcy).
public struct MetadataNameSource: NameResolutionSource {
    let session: any DatabaseSession

    public init(session: any DatabaseSession) { self.session = session }

    func bind(_ name: String, _ v: String?) -> BindVariable { BindVariable(name: name, value: v.map { .text($0) } ?? .null) }

    public func relationExists(owner: String?, name: String) async -> Bool {
        let n = try? await session.scalar("""
            select count(*) from all_objects
             where object_name = :n and object_type in ('TABLE', 'VIEW', 'MATERIALIZED VIEW', 'SYNONYM')
               and (owner = nvl(:o, sys_context('userenv', 'current_schema')) or (:o is null and owner = 'PUBLIC'))
            """, binds: [bind("n", name), bind("o", owner)])
        return (Int(n ?? "") ?? 1) > 0
    }

    public func columns(owner: String?, relation: String) async -> [String]? {
        guard let (_, rows) = try? await session.queryAll("""
            select c.column_name from all_tab_columns c
             where c.table_name = (select nvl(max(s.table_name), :n) from all_synonyms s
                                    where s.synonym_name = :n and s.owner in (nvl(:o, sys_context('userenv', 'current_schema')), 'PUBLIC'))
               and c.owner = (select nvl(max(s.table_owner), nvl(:o, sys_context('userenv', 'current_schema'))) from all_synonyms s
                               where s.synonym_name = :n and s.owner in (nvl(:o, sys_context('userenv', 'current_schema')), 'PUBLIC'))
            """, binds: [bind("n", relation), bind("o", owner)], limit: 5000), !rows.isEmpty else { return nil }
        return rows.compactMap { $0.first?.displayText }
    }

    public func objectOrSchemaExists(_ name: String) async -> Bool {
        let n = try? await session.scalar("""
            select (select count(*) from all_objects where object_name = :n and rownum = 1) + (select count(*) from all_users where username = :n) from dual
            """, binds: [bind("n", name)])
        return (Int(n ?? "") ?? 1) > 0
    }
}

// MARK: - Inspekcje kodu (DG-INSP-001)

public enum CodeInspections {
    static let numericTypes = ["NUMBER", "INTEGER", "INT", "PLS_INTEGER", "BINARY_INTEGER", "SIMPLE_INTEGER", "NATURAL", "POSITIVE",
                               "FLOAT", "BINARY_DOUBLE", "BINARY_FLOAT", "DECIMAL", "SMALLINT"]
    static let charTypes = ["VARCHAR2", "VARCHAR", "CHAR", "NVARCHAR2", "NCHAR"]

    /// Wszystkie inspekcje tekstu (bez bazy).
    public static func inspect(_ text: String, identifierLimit: Int = 30) -> [EditorDiagnostic] {
        let t = SQLToken.significant(text)
        let outline = PLSQLOutline.parse(text)
        return (unusedDeclarations(text, t, outline) + unreachableCode(t, text) + missingWhere(t) + implicitConversions(t, outline)
                + longIdentifiers(t, limit: identifierLimit))
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Identyfikatory dłuższe niż limit (PD-EDIT-019; domyślnie 30 bajtów — limit Oracle przed 12.2, 0 — wyłączone).
    static func longIdentifiers(_ t: [SQLToken], limit: Int) -> [EditorDiagnostic] {
        guard limit > 0 else { return [] }
        return t.filter { ($0.kind == .identifier || $0.kind == .quotedIdentifier) && $0.name.utf8.count > limit }.map {
            EditorDiagnostic(range: $0.start..<$0.end, severity: .info, source: .inspection, code: "long-identifier",
                             message: L10n.tr("Identyfikator dłuższy niż \(limit) bajtów — w bazach przed 12.2 (albo z COMPATIBLE < 12.2) niedozwolony"))
        }
    }

    /// Zmienne, stałe i parametry bez użycia w swoim zakresie (podprogram albo blok).
    static func unusedDeclarations(_ text: String, _ t: [SQLToken], _ outline: [OutlineNode]) -> [EditorDiagnostic] {
        var out: [EditorDiagnostic] = []
        func visit(_ nodes: [OutlineNode], scope: Range<Int>?, inSpec: Bool) {
            for n in nodes {
                let spec = inSpec || n.kind == .package || n.kind == .type
                if n.isContainer {
                    visit(n.children, scope: n.range, inSpec: spec)
                    continue
                }
                guard !spec, let scope, [.variable, .constant, .parameter].contains(n.kind), !n.name.isEmpty else { continue }
                let up = n.name.uppercased()
                let uses = t.filter { tok in
                    scope.contains(tok.start) && tok.start != n.nameOffset && tok.isWord && tok.name == up
                }
                if uses.isEmpty {
                    let r = n.nameOffset..<(n.nameOffset + (n.name as NSString).length)
                    let what = n.kind == .parameter ? L10n.tr("Parametr") : n.kind == .constant ? L10n.tr("Stała") : L10n.tr("Zmienna")
                    out.append(EditorDiagnostic(range: r, severity: .warning, source: .inspection, code: n.kind == .parameter ? "unused-parameter" : "unused-variable",
                                                message: L10n.tr("\(what) \(n.name) nie jest używana")))
                }
            }
        }
        visit(outline, scope: nil, inSpec: false)
        return out
    }

    /// Instrukcje po RETURN, RAISE, GOTO, EXIT/CONTINUE bez WHEN w tym samym ciągu instrukcji.
    static func unreachableCode(_ t: [SQLToken], _ text: String) -> [EditorDiagnostic] {
        var out: [EditorDiagnostic] = []
        let enders: Set<String> = ["END", "EXCEPTION", "WHEN", "ELSIF", "ELSE"]
        var i = 0
        while i < t.count {
            let tk = t[i]
            let prev = i > 0 ? t[i - 1] : nil
            let statementStart = prev == nil || prev!.kind == .semicolon || ["BEGIN", "THEN", "ELSE", "LOOP"].contains(prev!.upper)
            guard tk.isWord, statementStart, ["RETURN", "RAISE", "GOTO", "EXIT", "CONTINUE"].contains(tk.upper) else { i += 1; continue }
            var j = i + 1, conditional = false, depth = 0
            while j < t.count, !(t[j].kind == .semicolon && depth == 0) {
                if t[j].kind == .leftParen { depth += 1 } else if t[j].kind == .rightParen { depth -= 1 }
                if t[j].upper == "WHEN", ["EXIT", "CONTINUE"].contains(tk.upper) { conditional = true }
                j += 1
            }
            let k = j + 1
            if !conditional, k < t.count, t[k].isWord, !enders.contains(t[k].upper), t[k].text != "<<", t[k].kind != .operator || t[k].text != "<<" {
                // Zakres do końca linii następnej instrukcji.
                let ns = text as NSString
                let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: t[k].start, length: 0)))
                let end = min(lineEnd, ns.length)
                let trimmedEnd = ns.substring(with: NSRange(location: t[k].start, length: end - t[k].start)).hasSuffix("\n") ? end - 1 : end
                out.append(EditorDiagnostic(range: t[k].start..<max(t[k].end, trimmedEnd), severity: .warning, source: .inspection, code: "unreachable-code",
                                            message: L10n.tr("Kod nieosiągalny — wcześniej \(tk.upper)")))
            }
            i = max(i + 1, j)
        }
        return out
    }

    /// UPDATE/DELETE bez WHERE (całej tabeli).
    static func missingWhere(_ t: [SQLToken]) -> [EditorDiagnostic] {
        var out: [EditorDiagnostic] = []
        for st in NameResolver.statements(t) where ["UPDATE", "DELETE"].contains(t[st.lowerBound].upper) {
            var depth = 0
            let hasWhere = t[st].contains { tk in
                if tk.kind == .leftParen { depth += 1 } else if tk.kind == .rightParen { depth -= 1 }
                return depth == 0 && tk.upper == "WHERE"
            }
            if !hasWhere {
                let k = t[st.lowerBound]
                out.append(EditorDiagnostic(range: k.start..<k.end, severity: .warning, source: .inspection, code: "missing-where",
                                            message: L10n.tr("\(k.upper) bez WHERE zmieni wszystkie wiersze tabeli")))
            }
        }
        return out
    }

    /// Porównanie albo przypisanie zmiennej liczbowej z literałem tekstowym (i odwrotnie) — niejawna konwersja.
    static func implicitConversions(_ t: [SQLToken], _ outline: [OutlineNode]) -> [EditorDiagnostic] {
        var types: [(scope: Range<Int>, name: String, type: String)] = []
        func visit(_ nodes: [OutlineNode], scope: Range<Int>?) {
            for n in nodes {
                if n.isContainer { visit(n.children, scope: n.range); continue }
                guard let scope, [.variable, .constant, .parameter].contains(n.kind) else { continue }
                let base = n.detail.uppercased().split(whereSeparator: { !$0.isLetter && $0 != "_" }).first.map(String.init) ?? ""
                types.append((scope, n.name.uppercased(), base))
            }
        }
        visit(outline, scope: nil)
        guard !types.isEmpty else { return [] }
        func typeOf(_ tk: SQLToken) -> String? {
            types.filter { $0.scope.contains(tk.start) && $0.name == tk.name }.min { $0.scope.count < $1.scope.count }?.type
        }
        var out: [EditorDiagnostic] = []
        let ops: Set<String> = ["=", "<>", "!=", "<", ">", "<=", ">=", ":="]
        for i in 1..<max(1, t.count - 1) where ops.contains(t[i].text) {
            for (v, lit) in [(t[i - 1], t[i + 1]), (t[i + 1], t[i - 1])] where v.kind == .identifier {
                if t[i].text == ":=", v.start > lit.start { continue }
                if i >= 2, t[i - 2].kind == .dot, v.start < t[i].start { continue }
                guard let type = typeOf(v) else { continue }
                let mismatch = (numericTypes.contains(type) && lit.kind == .string) || (charTypes.contains(type) && lit.kind == .number)
                if mismatch {
                    out.append(EditorDiagnostic(range: lit.start..<lit.end, severity: .warning, source: .inspection, code: "implicit-conversion",
                                                message: L10n.tr("Niejawna konwersja: \(v.text) jest typu \(type), a literał \(lit.text) innego typu")))
                }
            }
        }
        return out
    }
}

/// Pamięć podręczna odpowiedzi słownika dla analizy w czasie pisania (ważna kilka minut; odświeżenie metadanych ją czyści).
public actor CachedNameSource: NameResolutionSource {
    let base: any NameResolutionSource
    let ttl: TimeInterval
    private var relations: [String: (Bool, Date)] = [:]
    private var cols: [String: ([String]?, Date)] = [:]
    private var objects: [String: (Bool, Date)] = [:]

    public init(_ base: any NameResolutionSource, ttl: TimeInterval = 300) { self.base = base; self.ttl = ttl }

    func fresh(_ d: Date) -> Bool { Date().timeIntervalSince(d) < ttl }

    public func relationExists(owner: String?, name: String) async -> Bool {
        let k = "\(owner ?? "").\(name)"
        if let (v, d) = relations[k], fresh(d) { return v }
        let v = await base.relationExists(owner: owner, name: name)
        relations[k] = (v, Date())
        return v
    }

    public func columns(owner: String?, relation: String) async -> [String]? {
        let k = "\(owner ?? "").\(relation)"
        if let (v, d) = cols[k], fresh(d) { return v }
        let v = await base.columns(owner: owner, relation: relation)
        cols[k] = (v, Date())
        return v
    }

    public func objectOrSchemaExists(_ name: String) async -> Bool {
        if let (v, d) = objects[name], fresh(d) { return v }
        let v = await base.objectOrSchemaExists(name)
        objects[name] = (v, Date())
        return v
    }
}

extension Workspace {
    /// Analiza tekstu okna: inspekcje zawsze, nieznane nazwy — gdy połączenie okna ma otwartą sesję główną
    /// (analiza nie łączy z bazą). Wynik trafia do `diagnostics` (podkreślenia w edytorze, lista problemów).
    @discardableResult
    public func analyzeCode(_ doc: Document, names: Bool = true) async -> [EditorDiagnostic] {
        guard [.sql, .program, .test].contains(doc.kind) else { return [] }
        let text = doc.text
        var found = CodeInspections.inspect(text, identifierLimit: settings.identifierLengthWarning)
        if names, let c = effectiveConnection(of: doc), let s = sessions.existingSession(SessionKey(connectionID: c, purpose: .main)) {
            let source = nameSources[c] ?? CachedNameSource(MetadataNameSource(session: s))
            nameSources[c] = source
            found += await NameResolver.unresolved(in: text, source: source)
        }
        found.sort { $0.range.lowerBound < $1.range.lowerBound }
        // Tekst zmienił się w trakcie analizy — wynik nieaktualny.
        guard doc.text == text else { return found }
        diagnostics[doc.id] = found
        return found
    }

    /// Czyści pamięć słownika analizy (po DDL, odświeżeniu metadanych).
    public func resetNameResolutionCache(_ connection: UUID? = nil) {
        if let connection { nameSources[connection] = nil } else { nameSources.removeAll() }
    }
}
