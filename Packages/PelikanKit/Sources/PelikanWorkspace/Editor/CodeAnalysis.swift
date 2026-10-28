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
    /// Wersje hurtowe (jedno zapytanie na wiele nazw — przy zdalnej bazie każda podróż to dziesiątki ms).
    func existingRelations(_ keys: [RelationKey]) async -> Set<RelationKey>
    func columns(of keys: [RelationKey]) async -> [RelationKey: [String]]
    func existingObjectsOrSchemas(_ names: [String]) async -> Set<String>
}

/// Relacja w tekście: właściciel (nil — schemat domyślny albo synonim publiczny) i nazwa.
public struct RelationKey: Hashable, Sendable {
    public var owner: String?
    public var name: String
    public init(owner: String?, name: String) { self.owner = owner; self.name = name }
}

extension NameResolutionSource {
    public func existingRelations(_ keys: [RelationKey]) async -> Set<RelationKey> {
        var out = Set<RelationKey>()
        for k in keys where await relationExists(owner: k.owner, name: k.name) { out.insert(k) }
        return out
    }
    public func columns(of keys: [RelationKey]) async -> [RelationKey: [String]] {
        var out: [RelationKey: [String]] = [:]
        for k in keys { if let c = await columns(owner: k.owner, relation: k.name) { out[k] = c } }
        return out
    }
    public func existingObjectsOrSchemas(_ names: [String]) async -> Set<String> {
        var out = Set<String>()
        for n in names where await objectOrSchemaExists(n) { out.insert(n) }
        return out
    }
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
                    || ["BEGIN", "THEN", "ELSE", "LOOP", "DECLARE", "IS", "AS", "EXCEPTION"].contains(prev!.upper) && prev!.isWord)
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
        // WITH nazwa AS ( … ), nazwa2 AS ( … ) — na początku polecenia i dalej (INSERT … WITH … SELECT, podzapytania).
        var i = range.lowerBound
        if t[i].upper == "WITH", i + 1 < range.upperBound, ["FUNCTION", "PROCEDURE"].contains(t[i + 1].upper) { return [] }
        for w in range where t[w].upper == "WITH" && (w == range.lowerBound || t[w - 1].upper != "START") {
            var j = w + 1
            while j + 1 < range.upperBound, t[j].isWord {
                let name = t[j].name
                var k = j + 1
                if k < range.upperBound, t[k].kind == .leftParen { var d = 0; repeat { if t[k].kind == .leftParen { d += 1 } else if t[k].kind == .rightParen { d -= 1 }; k += 1 } while k < range.upperBound && d > 0 }
                guard k < range.upperBound, t[k].upper == "AS" else { break }
                k += 1
                guard k < range.upperBound, t[k].kind == .leftParen else { break }
                ctes.insert(name)
                var d = 0
                repeat { if t[k].kind == .leftParen { d += 1 } else if t[k].kind == .rightParen { d -= 1 }; k += 1 } while k < range.upperBound && d > 0
                if k < range.upperBound, t[k].kind == .comma { j = k + 1 } else { break }
            }
        }
        let starter = t[range.lowerBound].upper
        func readRelation(at k: Int) -> (Relation, Int)? {
            // Nazwa tabeli bywa słowem kluczowym (GROUPS, LEVELS); TABLE(…), LATERAL (…), ONLY (…) — nie relacja.
            guard k < range.upperBound, t[k].kind == .identifier || t[k].kind == .quotedIdentifier
                    || (t[k].kind == .keyword && !clauseEnd.contains(t[k].upper) && !joinWords.contains(t[k].upper)
                        && !["TABLE", "ONLY", "XMLTABLE", "JSON_TABLE", "THE"].contains(t[k].upper)) else { return nil }
            var owner: String?
            var name = t[k].name
            var end = t[k].end
            var n = k + 1
            if n + 1 < range.upperBound, t[n].kind == .dot, t[n + 1].isWord {
                owner = name; name = t[n + 1].name; end = t[n + 1].end; n += 2
            }
            // Funkcja tabelaryczna albo link bazy — poza zakresem sprawdzania.
            if n < range.upperBound, t[n].kind == .leftParen { return nil }
            if n < range.upperBound, t[n].text == "@" { return nil }
            if n < range.upperBound, t[n].kind == .operator, t[n].text.hasPrefix("@") { return nil }
            var alias: String?
            if n < range.upperBound, t[n].upper == "AS", n + 1 < range.upperBound, t[n + 1].isWord { alias = t[n + 1].name; n += 2 }
            else if n < range.upperBound, t[n].kind == .identifier || t[n].kind == .quotedIdentifier, !clauseEnd.contains(t[n].upper), !joinWords.contains(t[n].upper) {
                alias = t[n].name; n += 1
            }
            return (Relation(owner: owner, name: name, alias: alias, range: t[k].start..<end, isCTE: owner == nil && ctes.contains(name)), n)
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
            case "INTO" where prev?.upper == "INSERT" || prev?.upper == "MERGE":
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
            // Widok wbudowany `( … ) alias`: alias zapisany jako nie do sprawdzania (jak CTE); treść czytana dalej normalnie.
            if let k = next, k < range.upperBound, t[k].kind == .leftParen {
                var m = k, d = 0
                repeat { if t[m].kind == .leftParen { d += 1 } else if t[m].kind == .rightParen { d -= 1 }; m += 1 } while m < range.upperBound && d > 0
                if m < range.upperBound, t[m].upper == "AS" { m += 1 }
                if m < range.upperBound, t[m].kind == .identifier || t[m].kind == .quotedIdentifier, !clauseEnd.contains(t[m].upper), !joinWords.contains(t[m].upper) {
                    out.append(Relation(owner: nil, name: t[m].name, alias: t[m].name, range: t[m].start..<t[m].end, isCTE: true))
                }
            }
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

    /// Nieznane relacje, kolumny po aliasie i kwalifikatory, które nie są aliasem ani obiektem. Najpierw zbiera wszystkie
    /// nazwy tekstu, potem sprawdza je hurtowo (pakiet z 13 tys. linii na zdalnej bazie: 34 s pojedynczo → kilka zapytań).
    public static func unresolved(in text: String, source: any NameResolutionSource) async -> [EditorDiagnostic] {
        let t = SQLToken.significant(text)
        let sts = statements(t).map { ($0, relations(t, $0)) }
        func key(_ r: Relation) -> RelationKey { RelationKey(owner: r.owner, name: r.name) }
        let existing = await source.existingRelations(Array(Set(sts.flatMap { $0.1 }.filter { !$0.isCTE }.map(key))))

        /// Odwołanie `q.kolumna` w poleceniu: indeks tokenu kwalifikatora i relacje aliasu (ten sam alias bywa użyty
        /// w kilku podzapytaniach jednego polecenia — kolumna jest poprawna, gdy ma ją którakolwiek).
        struct Qualified { var index: Int; var relations: [Relation]? }
        var plan: [(rels: [Relation], unknown: [Relation], refs: [Qualified])] = []
        var columnKeys = Set<RelationKey>(), qualifiers = Set<String>()
        for (st, rels) in sts {
            var aliases: [String: [Relation]] = [:]
            var unknown: [Relation] = []
            // Alias relacji nieznanej (już zgłoszonej) albo CTE — kolumn nie da się sprawdzić.
            var unchecked = Set<String>()
            for r in rels {
                if r.isCTE { unchecked.insert(r.alias ?? r.name); unchecked.insert(r.name); continue }
                guard existing.contains(key(r)) else { unknown.append(r); unchecked.insert(r.alias ?? r.name); continue }
                aliases[r.alias ?? r.name, default: []].append(r)
                if r.alias != nil, aliases[r.name] == nil { aliases[r.name] = [r] }
            }
            var refs: [Qualified] = []
            // `schemat.tabela` w FROM/JOIN to relacja, nie kolumna aliasu (alias bywa równy nazwie schematu).
            let relationStarts = Set(rels.filter { $0.owner != nil }.map(\.range.lowerBound))
            var i = st.lowerBound
            while i + 2 < st.upperBound {
                defer { i += 1 }
                guard t[i].kind == .identifier || t[i].kind == .quotedIdentifier, t[i + 1].kind == .dot,
                      t[i + 2].kind == .identifier || t[i + 2].kind == .quotedIdentifier || t[i + 2].kind == .keyword else { continue }
                // Część dłuższej ścieżki (schemat.tabela.kolumna) albo wywołanie (pakiet.funkcja(…)) — pomijane.
                if i > st.lowerBound, t[i - 1].kind == .dot { continue }
                if i + 3 < st.upperBound, t[i + 3].kind == .dot || t[i + 3].kind == .leftParen { continue }
                if t[i + 2].upper == "*" || relationStarts.contains(t[i].start) { continue }
                let q = t[i].name, col = t[i + 2].name
                if unchecked.contains(q) { continue }
                if let rs = aliases[q] {
                    guard !pseudoColumns.contains(col) else { continue }
                    rs.forEach { columnKeys.insert(key($0)) }
                    refs.append(Qualified(index: i, relations: rs))
                } else if !rels.isEmpty {
                    // Kwalifikator spoza aliasów: obiekt (pakiet, sekwencja), schemat albo zmienna PL/SQL — błąd tylko,
                    // gdy żadnym z nich nie jest (zmienne rekordowe w PL/SQL pomijane: polecenie w bloku).
                    let insidePLSQL = st.lowerBound > 0 && t[..<st.lowerBound].contains { ["BEGIN", "DECLARE"].contains($0.upper) }
                    if insidePLSQL { continue }
                    qualifiers.insert(q)
                    refs.append(Qualified(index: i, relations: nil))
                }
            }
            plan.append((rels, unknown, refs))
        }
        let columns = columnKeys.isEmpty ? [:] : await source.columns(of: Array(columnKeys))
        let known = qualifiers.isEmpty ? [] : await source.existingObjectsOrSchemas(Array(qualifiers))

        var out: [EditorDiagnostic] = []
        for p in plan {
            for r in p.unknown {
                out.append(EditorDiagnostic(range: r.range, severity: .error, source: .names, code: "unknown-table",
                                            message: L10n.tr("Nieznana tabela albo widok: \(r.owner.map { "\($0)." } ?? "")\(r.name)")))
            }
            for ref in p.refs {
                let i = ref.index
                if let rs = ref.relations {
                    let col = t[i + 2].name
                    let known = rs.compactMap { columns[key($0)] }
                    if known.count == rs.count, !known.contains(where: { $0.contains(col) }), let r = rs.first {
                        out.append(EditorDiagnostic(range: t[i + 2].start..<t[i + 2].end, severity: .error, source: .names, code: "unknown-column",
                                                    message: L10n.tr("Kolumna \(col) nie istnieje w \(r.name)")))
                    }
                } else if !known.contains(t[i].name) {
                    out.append(EditorDiagnostic(range: t[i].start..<t[i].end, severity: .error, source: .names, code: "unknown-alias",
                                                message: L10n.tr("Nieznany alias albo obiekt: \(t[i].name)")))
                }
            }
        }
        return out
    }
}

/// Metadane do rozwiązywania nazw ze słownika bazy (sesja metadanych połączenia; wyniki w pamięci podręcznej dostawcy).
/// Nazwy bez schematu rozwiązywane w `defaultSchema` (program z innego schematu — schemat właściciela), inaczej
/// w bieżącym schemacie sesji; potem synonimy publiczne.
public struct MetadataNameSource: NameResolutionSource {
    let session: any DatabaseSession
    let defaultSchema: String?

    public init(session: any DatabaseSession, defaultSchema: String? = nil) { self.session = session; self.defaultSchema = defaultSchema }

    func bind(_ name: String, _ v: String?) -> BindVariable { BindVariable(name: name, value: v.map { .text($0) } ?? .null) }
    static let currentSchema = "nvl(:d, sys_context('userenv', 'current_schema'))"
    /// Lista IN do 900 nazw na zapytanie (limit Oracle: 1000 wyrażeń).
    static let chunk = 900

    public func relationExists(owner: String?, name: String) async -> Bool {
        await existingRelations([RelationKey(owner: owner, name: name)]).contains(RelationKey(owner: owner, name: name))
    }

    public func columns(owner: String?, relation: String) async -> [String]? {
        await columns(of: [RelationKey(owner: owner, name: relation)])[RelationKey(owner: owner, name: relation)]
    }

    public func objectOrSchemaExists(_ name: String) async -> Bool {
        await existingObjectsOrSchemas([name]).contains(name)
    }

    /// Słownik: DBA_*, gdy sesja może go czytać (uprawnienia sesji nie dają wtedy fałszywych „nieznanych” obiektów
    /// w kodzie innego schematu), inaczej ALL_*.
    func dictionary() async -> String {
        (try? await session.scalar("select 'DBA' from dba_objects where rownum = 1")) == "DBA" ? "dba" : "all"
    }

    /// Schemat domyślny po stronie bazy (jedna podróż na analizę).
    func schema() async -> String {
        if let defaultSchema { return defaultSchema }
        return (try? await session.scalar("select sys_context('userenv', 'current_schema') from dual")) ?? ""
    }

    func inList(_ prefix: String, _ values: [String]) -> (sql: String, binds: [BindVariable]) {
        let binds = values.enumerated().map { BindVariable(name: "\(prefix)\($0.offset)", value: .text($0.element)) }
        return (binds.map { ":\($0.name)" }.joined(separator: ", "), binds)
    }

    public func existingRelations(_ keys: [RelationKey]) async -> Set<RelationKey> {
        guard !keys.isEmpty else { return [] }
        let schema = await schema(), dict = await dictionary()
        var found = Set<String>()   // "WŁAŚCICIEL.NAZWA"
        let names = Array(Set(keys.map(\.name)))
        let owners = Array(Set(keys.compactMap(\.owner) + [schema, "PUBLIC"]))
        for part in stride(from: 0, to: names.count, by: Self.chunk) {
            let n = inList("n", Array(names[part..<min(part + Self.chunk, names.count)]))
            let o = inList("o", owners)
            guard let (_, rows) = try? await session.queryAll("""
                select owner || '.' || object_name from \(dict)_objects
                 where object_type in ('TABLE', 'VIEW', 'MATERIALIZED VIEW', 'SYNONYM')
                   and object_name in (\(n.sql)) and owner in (\(o.sql))
                """, binds: n.binds + o.binds, limit: 100_000) else { return Set(keys) }   // błąd słownika — bez fałszywych alarmów
            for r in rows { if let s = r.first?.displayText { found.insert(s) } }
        }
        return Set(keys.filter { k in
            if let owner = k.owner { return found.contains("\(owner).\(k.name)") }
            return found.contains("\(schema).\(k.name)") || found.contains("PUBLIC.\(k.name)")
        })
    }

    public func columns(of keys: [RelationKey]) async -> [RelationKey: [String]] {
        guard !keys.isEmpty else { return [:] }
        let schema = await schema(), dict = await dictionary()
        // Kolejność jak w Oracle: obiekt w schemacie, synonim prywatny w schemacie, synonim publiczny (tylko bez schematu).
        func direct(_ k: RelationKey) -> String { "\(k.owner ?? schema).\(k.name)" }
        var cols = await tableColumns(Set(keys.map(direct)), dict: dict)
        let viaSynonym = keys.filter { cols[direct($0)] == nil }
        var target: [RelationKey: String] = [:]
        if !viaSynonym.isEmpty {
            var synonyms: [String: String] = [:]   // "WŁAŚCICIEL_SYNONIMU.NAZWA" → "WŁAŚCICIEL.TABELA"
            let names = Array(Set(viaSynonym.map(\.name)))
            for part in stride(from: 0, to: names.count, by: Self.chunk) {
                let n = inList("n", Array(names[part..<min(part + Self.chunk, names.count)]))
                let rows = (try? await session.queryAll("select owner, synonym_name, table_owner, table_name from \(dict)_synonyms where synonym_name in (\(n.sql)) and db_link is null",
                                                        binds: n.binds, limit: 100_000).rows) ?? []
                for r in rows where r.count == 4 {
                    synonyms["\(r[0].displayText ?? "").\(r[1].displayText ?? "")"] = "\(r[2].displayText ?? "").\(r[3].displayText ?? "")"
                }
            }
            for k in viaSynonym {
                if let s = synonyms[direct(k)] ?? (k.owner == nil ? synonyms["PUBLIC.\(k.name)"] : nil) { target[k] = s }
            }
            let more = await tableColumns(Set(target.values), dict: dict)
            cols.merge(more) { a, _ in a }
        }
        var out: [RelationKey: [String]] = [:]
        for k in keys { if let c = cols[direct(k)] ?? target[k].flatMap({ cols[$0] }) { out[k] = c } }
        return out
    }

    /// Kolumny tabel i widoków "WŁAŚCICIEL.NAZWA" (pary w liście IN).
    func tableColumns(_ names: Set<String>, dict: String) async -> [String: [String]] {
        var cols: [String: [String]] = [:]
        let list = Array(names)
        for part in stride(from: 0, to: list.count, by: Self.chunk / 2) {
            let slice = Array(list[part..<min(part + Self.chunk / 2, list.count)])
            let pairs = slice.indices.map { "(:o\($0), :t\($0))" }.joined(separator: ", ")
            let binds = slice.enumerated().flatMap { i, s -> [BindVariable] in
                let p = s.split(separator: ".", maxSplits: 1).map(String.init)
                return [BindVariable(name: "o\(i)", value: .text(p[0])), BindVariable(name: "t\(i)", value: .text(p.count > 1 ? p[1] : ""))]
            }
            let rows = (try? await session.queryAll("select owner, table_name, column_name from \(dict)_tab_columns where (owner, table_name) in (\(pairs))",
                                                    binds: binds, limit: 1_000_000).rows) ?? []
            for r in rows where r.count == 3 { cols["\(r[0].displayText ?? "").\(r[1].displayText ?? "")", default: []].append(r[2].displayText ?? "") }
        }
        return cols
    }

    public func existingObjectsOrSchemas(_ names: [String]) async -> Set<String> {
        guard !names.isEmpty else { return [] }
        let dict = await dictionary()
        var found = Set<String>()
        let unique = Array(Set(names))
        for part in stride(from: 0, to: unique.count, by: Self.chunk) {
            let n = inList("n", Array(unique[part..<min(part + Self.chunk, unique.count)]))
            guard let (_, rows) = try? await session.queryAll("""
                select object_name from \(dict)_objects where object_name in (\(n.sql))
                union select username from \(dict)_users where username in (\(n.sql))
                """, binds: n.binds, limit: 100_000) else { return Set(names) }
            for r in rows { if let s = r.first?.displayText { found.insert(s) } }
        }
        return found
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
        // Pozycje słów według nazwy (rosnąco) — wyszukiwanie użycia w zakresie bez przeglądania wszystkich tokenów dla
        // każdej deklaracji (pakiet 60 000 linii z tysiącami podprogramów blokował główny wątek na minuty, D192).
        var positions: [String: [Int]] = [:]
        for tok in t where tok.isWord { positions[tok.name, default: []].append(tok.start) }
        func used(_ name: String, in scope: Range<Int>, except: Int) -> Bool {
            guard let list = positions[name] else { return false }
            var lo = 0, hi = list.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if list[mid] < scope.lowerBound { lo = mid + 1 } else { hi = mid }
            }
            while lo < list.count, list[lo] < scope.upperBound {
                if list[lo] != except { return true }
                lo += 1
            }
            return false
        }
        func visit(_ nodes: [OutlineNode], scope: Range<Int>?, inSpec: Bool) {
            for n in nodes {
                let spec = inSpec || n.kind == .package || n.kind == .type
                if n.isContainer {
                    visit(n.children, scope: n.range, inSpec: spec)
                    continue
                }
                guard !spec, let scope, [.variable, .constant, .parameter].contains(n.kind), !n.name.isEmpty else { continue }
                if !used(n.name.uppercased(), in: scope, except: n.nameOffset) {
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

    func k(_ r: RelationKey) -> String { "\(r.owner ?? "").\(r.name)" }

    public func existingRelations(_ keys: [RelationKey]) async -> Set<RelationKey> {
        let missing = keys.filter { relations[k($0)].map { !fresh($0.1) } ?? true }
        if !missing.isEmpty {
            let found = await base.existingRelations(missing)
            for m in missing { relations[k(m)] = (found.contains(m), Date()) }
        }
        return Set(keys.filter { relations[k($0)]?.0 == true })
    }

    public func columns(of keys: [RelationKey]) async -> [RelationKey: [String]] {
        let missing = keys.filter { cols[k($0)].map { !fresh($0.1) } ?? true }
        if !missing.isEmpty {
            let found = await base.columns(of: missing)
            for m in missing { cols[k(m)] = (found[m], Date()) }
        }
        var out: [RelationKey: [String]] = [:]
        for key in keys { if let c = cols[k(key)]?.0 { out[key] = c } }
        return out
    }

    public func existingObjectsOrSchemas(_ names: [String]) async -> Set<String> {
        let missing = names.filter { objects[$0].map { !fresh($0.1) } ?? true }
        if !missing.isEmpty {
            let found = await base.existingObjectsOrSchemas(missing)
            for m in missing { objects[m] = (found.contains(m), Date()) }
        }
        return Set(names.filter { objects[$0]?.0 == true })
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
            // Program z innego schematu (nagłówek z właścicielem): nazwy bez schematu — w schemacie właściciela.
            let schema = doc.kind == .program ? ProgramCompiler.units(in: text).first?.owner : nil
            // Klucz z tożsamością sesji: po ponownym połączeniu źródło ze starą (zamkniętą) sesją jest odrzucane.
            let key = NameSourceKey(connection: c, schema: schema, session: ObjectIdentifier(s))
            if nameSources[key] == nil { nameSources = nameSources.filter { $0.key.connection != c || $0.key.session == key.session } }
            let source = nameSources[key] ?? CachedNameSource(MetadataNameSource(session: s, defaultSchema: schema))
            nameSources[key] = source
            found += await NameResolver.unresolved(in: text, source: source)
        }
        found.sort { $0.range.lowerBound < $1.range.lowerBound }
        // Tekst zmienił się w trakcie analizy — wynik nieaktualny.
        guard doc.text == text else { return found }
        diagnostics[doc.id] = found
        return found
    }

    /// Czyści pamięć słownika analizy (wołane przy odświeżeniu metadanych połączenia — także po DDL edytorów obiektów).
    public func resetNameResolutionCache(_ connection: UUID? = nil) {
        if let connection { nameSources = nameSources.filter { $0.key.connection != connection } } else { nameSources.removeAll() }
    }
}

/// Pamięć słownika analizy: połączenie, schemat domyślny (nil — bieżący schemat sesji) i sesja główna.
struct NameSourceKey: Hashable {
    var connection: UUID
    var schema: String?
    var session: ObjectIdentifier
}
