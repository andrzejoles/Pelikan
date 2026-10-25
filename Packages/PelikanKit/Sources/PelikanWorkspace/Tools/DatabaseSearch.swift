import Foundation
import PelikanDB

/// Kryteria Find Database Objects (UG 24.2).
public struct DatabaseSearchCriteria: Sendable, Hashable, Codable {
    public var text = ""
    public var caseSensitive = false
    public var wholeWords = false
    public var regularExpression = false
    /// Właściciele (puste — bieżący schemat) i filtr nazw obiektów (`%`).
    public var owners: [String] = []
    public var nameFilter = ""
    /// Typy źródeł (ALL_SOURCE.TYPE) i widoki (tekst zapytania); puste — wszystkie.
    public var types: [DBObjectType] = []
    /// Szukaj także w nazwach obiektów.
    public var searchNames = true
    /// Szukaj w definicjach tabel: nazwy i komentarze kolumn, komentarze tabel, warunki CHECK (PD-TOOL-001).
    public var searchTableDefinitions = false

    public init(text: String = "") { self.text = text }

    // Dekodowanie odporne na nowe pola (zapisane kryteria ze starszej wersji).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ cur: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? cur }
        text = v(.text, text)
        caseSensitive = v(.caseSensitive, caseSensitive)
        wholeWords = v(.wholeWords, wholeWords)
        regularExpression = v(.regularExpression, regularExpression)
        owners = v(.owners, owners)
        nameFilter = v(.nameFilter, nameFilter)
        types = v(.types, types)
        searchNames = v(.searchNames, searchNames)
        searchTableDefinitions = v(.searchTableDefinitions, searchTableDefinitions)
    }
}

/// Zapisane kryteria wyszukiwania (PD-TOOL-001).
public struct SavedDatabaseSearch: Sendable, Hashable, Codable, Identifiable {
    public var name: String
    public var criteria: DatabaseSearchCriteria
    public var id: String { name }

    public init(name: String, criteria: DatabaseSearchCriteria) { self.name = name; self.criteria = criteria }
}

/// Wynik wyszukiwania: obiekt i linia (0 — trafienie w nazwie albo w tekście widoku).
public struct DatabaseSearchHit: Sendable, Hashable, Identifiable {
    public var object: DBObject
    public var line: Int
    public var text: String
    public var id: String { "\(object.id):\(line)" }
}

@MainActor
public enum DatabaseSearch {
    static let sourceTypes: [DBObjectType] = [.package, .packageBody, .procedure, .function, .trigger, .type, .typeBody, .javaSource, .mleModule]

    /// Typy do wyboru w kryteriach (źródła, widoki, tabele — definicje).
    public static let selectableTypes: [DBObjectType] = sourceTypes + [.view, .table]

    /// Wyniki jako tekst do eksportu: CSV (z nagłówkiem, cudzysłowy wg RFC 4180) albo tekst z tabulatorami.
    public nonisolated static func exportText(_ hits: [DatabaseSearchHit], csv: Bool) -> String {
        func field(_ s: String) -> String {
            guard csv else { return s.replacingOccurrences(of: "\t", with: " ") }
            return s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        let sep = csv ? "," : "\t"
        let header = [L10n.tr("Właściciel"), L10n.tr("Obiekt"), L10n.tr("Typ"), L10n.tr("Linia"), L10n.tr("Tekst")]
        let rows = hits.map { h in [h.object.owner, h.object.name, h.object.type.rawValue, h.line > 0 ? String(h.line) : "", h.text] }
        return ([header] + rows).map { $0.map(field).joined(separator: sep) }.joined(separator: "\n") + "\n"
    }

    /// Wzorzec REGEXP_LIKE dla kryteriów (tekst dosłowny, całe słowa — granice identyfikatora PL/SQL).
    nonisolated static func pattern(_ c: DatabaseSearchCriteria) -> String {
        var p = c.regularExpression ? c.text : NSRegularExpression.escapedPattern(for: c.text)
        if c.wholeWords { p = "(^|[^A-Za-z0-9_$#])" + p + "($|[^A-Za-z0-9_$#])" }
        return p
    }

    /// Warunek dopasowania kolumny: dla tekstu dosłownego najpierw `INSTR` (na dużej bazie ~30× szybsze niż samo
    /// REGEXP_LIKE po ALL_SOURCE — D164), potem REGEXP_LIKE dla całych słów i dokładności; wyrażenie regularne — samo
    /// REGEXP_LIKE. Kolejność wymusza CASE (gałęzie WHEN są sprawdzane po kolei): przy zmiennych wiązanych optymalizator
    /// liczy `instr … and regexp_like …` od REGEXP_LIKE. Binds `:p`, `:f` i (dla tekstu dosłownego) `:t`.
    nonisolated static func match(_ column: String, _ c: DatabaseSearchCriteria) -> String {
        let regexp = "regexp_like(\(column), :p, :f)"
        guard !c.regularExpression else { return regexp }
        let instr = c.caseSensitive ? "instr(\(column), :t)" : "instr(upper(\(column)), upper(:t))"
        return "case when nvl(\(instr), 0) = 0 then 0 when \(regexp) then 1 else 0 end = 1"
    }

    public static func search(_ c: DatabaseSearchCriteria, metadata m: MetadataProvider, limit: Int = 10_000) async throws -> [DatabaseSearchHit] {
        let text = c.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        let s = try await m.session()
        let owners = c.owners.isEmpty ? [s.info.currentSchema] : c.owners
        let flags = c.caseSensitive ? "c" : "i"
        var binds = [BindVariable(name: "p", value: .text(pattern(c))), BindVariable(name: "f", value: .text(flags))]
        if !c.regularExpression { binds.append(BindVariable(name: "t", value: .text(text))) }
        let ownerList = owners.enumerated().map { i, o -> String in
            binds.append(BindVariable(name: "o\(i)", value: .text(o)))
            return ":o\(i)"
        }.joined(separator: ", ")
        var nameCond = ""
        if !c.nameFilter.isEmpty {
            binds.append(BindVariable(name: "nf", value: .text(c.nameFilter.uppercased().contains("%") ? c.nameFilter.uppercased() : c.nameFilter.uppercased() + "%")))
            nameCond = " and name like :nf"
        }
        let wanted = c.types.isEmpty ? sourceTypes + [.view] + (c.searchTableDefinitions ? [.table] : []) : c.types
        var hits: [DatabaseSearchHit] = []
        let src = wanted.filter { sourceTypes.contains($0) }
        if !src.isEmpty {
            let typeList = src.map { "'\($0.rawValue)'" }.joined(separator: ", ")
            let (_, rows) = try await s.queryAll("""
                select owner, name, type, line, text from all_source
                where owner in (\(ownerList)) and type in (\(typeList))\(nameCond) and \(match("text", c))
                order by owner, name, type, line
                """, binds: binds, limit: limit)
            hits += rows.compactMap { r in
                guard let t = DBObjectType(rawValue: r[2].displayText ?? "") else { return nil }
                return DatabaseSearchHit(object: DBObject(owner: r[0].displayText ?? "", name: r[1].displayText ?? "", type: t, status: "VALID"),
                                         line: Int(r[3].format(.default)) ?? 0,
                                         text: (r[4].displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if wanted.contains(.view), hits.count < limit {
            let (_, rows) = try await s.queryAll("""
                select owner, view_name, text_vc from all_views
                where owner in (\(ownerList))\(nameCond.replacingOccurrences(of: "name", with: "view_name")) and \(match("text_vc", c))
                order by owner, view_name
                """, binds: binds, limit: limit - hits.count)
            hits += rows.map { r in
                DatabaseSearchHit(object: DBObject(owner: r[0].displayText ?? "", name: r[1].displayText ?? "", type: .view, status: "VALID"),
                                  line: 0, text: String((r[2].displayText ?? "").prefix(200)).replacingOccurrences(of: "\n", with: " "))
            }
        }
        if wanted.contains(.table), c.searchTableDefinitions || c.types.contains(.table), hits.count < limit {
            hits += try await tableDefinitionHits(ownerList: ownerList, nameCond: nameCond, binds: binds, criteria: c, in: s, limit: limit - hits.count)
        }
        if c.searchNames, hits.count < limit {
            let (_, rows) = try await s.queryAll("""
                select owner, object_name, object_type, status from all_objects
                where owner in (\(ownerList))\(nameCond.replacingOccurrences(of: "name", with: "object_name")) and \(match("object_name", c))
                  and object_name not like 'BIN$%' and subobject_name is null
                order by owner, object_name
                """, binds: binds, limit: limit - hits.count)
            hits += rows.compactMap { r in
                guard let t = DBObjectType(rawValue: r[2].displayText ?? ""), c.types.isEmpty || c.types.contains(t) else { return nil }
                return DatabaseSearchHit(object: DBObject(owner: r[0].displayText ?? "", name: r[1].displayText ?? "", type: t, status: r[3].displayText ?? ""),
                                         line: 0, text: L10n.tr("nazwa obiektu"))
            }
        }
        return hits
    }

    /// Trafienia w definicjach tabel: nazwy i komentarze kolumn, komentarze tabel, warunki CHECK (SEARCH_CONDITION_VC
    /// od 12.2 — na starszych serwerach bez warunków).
    nonisolated static func tableDefinitionHits(ownerList: String, nameCond: String, binds: [BindVariable], criteria c: DatabaseSearchCriteria,
                                                in s: any DatabaseSession, limit: Int) async throws -> [DatabaseSearchHit] {
        let tableCond = nameCond.replacingOccurrences(of: "name", with: "table_name")
        var sql = """
            select owner, table_name, 'COLUMN ' || column_name, column_id from all_tab_columns
             where owner in (\(ownerList))\(tableCond) and \(match("column_name", c))
            union all
            select owner, table_name, 'COMMENT ' || column_name || ': ' || comments, 0 from all_col_comments
             where owner in (\(ownerList))\(tableCond) and comments is not null and \(match("comments", c))
            union all
            select owner, table_name, 'COMMENT: ' || comments, 0 from all_tab_comments
             where owner in (\(ownerList))\(tableCond) and table_type = 'TABLE' and comments is not null and \(match("comments", c))
            """
        let checks = """

            union all
            select owner, table_name, 'CHECK ' || constraint_name || ': ' || search_condition_vc, 0 from all_constraints
             where owner in (\(ownerList))\(tableCond) and constraint_type = 'C' and constraint_name not like 'SYS\\_C%' escape '\\'
               and \(match("search_condition_vc", c))
            """
        sql += "%CHECKS%\n order by 1, 2, 4"
        let (_, rows) = try await DictionaryQuery.queryAll([sql.replacingOccurrences(of: "%CHECKS%", with: checks),
                                                            sql.replacingOccurrences(of: "%CHECKS%", with: "")],
                                                           binds: binds, limit: limit, in: s)
        guard !rows.isEmpty else { return [] }
        // Kolumny i komentarze widoków odpadają tutaj, jednym zapytaniem o tabele schematów — półzłączenie z ALL_TABLES
        // w gałęziach kosztowało na dużej bazie ~5 s na gałąź przy 0,4 s bez niego (D165).
        let ownerBinds = binds.filter { $0.name.hasPrefix("o") && Int($0.name.dropFirst()) != nil }
        let (_, tables) = try await s.queryAll("select owner, table_name from all_tables where owner in (\(ownerList))\(tableCond)",
                                               binds: ownerBinds + binds.filter { $0.name == "nf" }, limit: 10_000_000)
        let isTable = Set(tables.map { "\($0[0].displayText ?? "").\($0[1].displayText ?? "")" })
        return rows.filter { isTable.contains("\($0[0].displayText ?? "").\($0[1].displayText ?? "")") }.map { r in
            DatabaseSearchHit(object: DBObject(owner: r[0].displayText ?? "", name: r[1].displayText ?? "", type: .table, status: "VALID"),
                              line: 0, text: (r[2].displayText ?? "").replacingOccurrences(of: "\n", with: " "))
        }
    }
}
