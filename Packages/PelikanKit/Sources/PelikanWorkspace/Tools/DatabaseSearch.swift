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

    public init(text: String = "") { self.text = text }
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
    static let sourceTypes: [DBObjectType] = [.package, .packageBody, .procedure, .function, .trigger, .type, .typeBody, .javaSource]

    /// Wzorzec REGEXP_LIKE dla kryteriów (tekst dosłowny, całe słowa — granice identyfikatora PL/SQL).
    nonisolated static func pattern(_ c: DatabaseSearchCriteria) -> String {
        var p = c.regularExpression ? c.text : NSRegularExpression.escapedPattern(for: c.text)
        if c.wholeWords { p = "(^|[^A-Za-z0-9_$#])" + p + "($|[^A-Za-z0-9_$#])" }
        return p
    }

    public static func search(_ c: DatabaseSearchCriteria, metadata m: MetadataProvider, limit: Int = 10_000) async throws -> [DatabaseSearchHit] {
        let text = c.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        let s = try await m.session()
        let owners = c.owners.isEmpty ? [s.info.currentSchema] : c.owners
        let flags = c.caseSensitive ? "c" : "i"
        var binds = [BindVariable(name: "p", value: .text(pattern(c))), BindVariable(name: "f", value: .text(flags))]
        let ownerList = owners.enumerated().map { i, o -> String in
            binds.append(BindVariable(name: "o\(i)", value: .text(o)))
            return ":o\(i)"
        }.joined(separator: ", ")
        var nameCond = ""
        if !c.nameFilter.isEmpty {
            binds.append(BindVariable(name: "nf", value: .text(c.nameFilter.uppercased().contains("%") ? c.nameFilter.uppercased() : c.nameFilter.uppercased() + "%")))
            nameCond = " and name like :nf"
        }
        let wanted = c.types.isEmpty ? sourceTypes + [.view] : c.types
        var hits: [DatabaseSearchHit] = []
        let src = wanted.filter { sourceTypes.contains($0) }
        if !src.isEmpty {
            let typeList = src.map { "'\($0.rawValue)'" }.joined(separator: ", ")
            let (_, rows) = try await s.queryAll("""
                select owner, name, type, line, text from all_source
                where owner in (\(ownerList)) and type in (\(typeList))\(nameCond) and regexp_like(text, :p, :f)
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
                where owner in (\(ownerList))\(nameCond.replacingOccurrences(of: "name", with: "view_name")) and regexp_like(text_vc, :p, :f)
                order by owner, view_name
                """, binds: binds, limit: limit - hits.count)
            hits += rows.map { r in
                DatabaseSearchHit(object: DBObject(owner: r[0].displayText ?? "", name: r[1].displayText ?? "", type: .view, status: "VALID"),
                                  line: 0, text: String((r[2].displayText ?? "").prefix(200)).replacingOccurrences(of: "\n", with: " "))
            }
        }
        if c.searchNames, hits.count < limit {
            let (_, rows) = try await s.queryAll("""
                select owner, object_name, object_type, status from all_objects
                where owner in (\(ownerList))\(nameCond.replacingOccurrences(of: "name", with: "object_name")) and regexp_like(object_name, :p, :f)
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
}
