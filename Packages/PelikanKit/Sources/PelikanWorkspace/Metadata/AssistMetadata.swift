import Foundation
import PelikanDB

/// Zapytania słownika dla Code Assistant (UG 25.4) — wyniki w pamięci podręcznej odświeżanej komendą Refresh (PD-CA-009).
extension MetadataProvider {
    /// Nazwy i typy obiektów schematu (bez ciał i obiektów kosza).
    public func objectNames(owner: String) async throws -> [(name: String, type: String)] {
        if let c = nameCache[owner] { return c }
        let s = try await session()
        let (_, rows) = try await s.queryAll("""
            select object_name, object_type from all_objects
            where owner = :o and object_type not in ('PACKAGE BODY', 'TYPE BODY', 'INDEX PARTITION', 'TABLE PARTITION', 'LOB', 'INDEX')
              and object_name not like 'BIN$%' and subobject_name is null
            order by object_name
            """, binds: [BindVariable(name: "o", value: .text(owner))], limit: 200_000)
        let list = rows.map { (name: $0[0].displayText ?? "", type: $0[1].displayText ?? "") }
        nameCache[owner] = list
        return list
    }

    /// Obiekt o nazwie `[owner.]name` widoczny z bieżącego schematu — przez synonim prywatny albo publiczny.
    public func resolve(owner: String?, name: String) async throws -> DBObject? {
        let key = "\(owner ?? "").\(name)"
        if let c = resolveCache[key] { return c }
        var result = try await find(owner.map { "\"\($0)\".\"\(name)\"" } ?? "\"\(name)\"")
        if result == nil || result?.type == .synonym {
            let s = try await session()
            let own = owner ?? s.info.currentSchema
            let (_, rows) = try await s.queryAll("""
                select table_owner, table_name from all_synonyms
                where synonym_name = :n and (owner = :o or (owner = 'PUBLIC' and :q is null)) and db_link is null
                order by decode(owner, 'PUBLIC', 2, 1)
                """, binds: [BindVariable(name: "n", value: .text(name)), BindVariable(name: "o", value: .text(own)),
                             BindVariable(name: "q", value: owner.map { .text($0) } ?? .null)], limit: 1)
            if let r = rows.first, let to = r[0].displayText, let tn = r[1].displayText {
                result = try await find("\"\(to)\".\"\(tn)\"")
            }
        }
        resolveCache[key] = result
        return result
    }

    /// Kolumny tabeli, widoku albo perspektywy zmaterializowanej (nazwa, typ).
    public func columns(of o: DBObject) async throws -> [DBObjectChild] {
        try await children(of: o).filter { $0.kind == .column }
    }

    /// Linki bazy danych widoczne dla użytkownika.
    public func databaseLinks() async throws -> [String] {
        if let c = linkCache { return c }
        let (_, rows) = try await session().queryAll("select distinct db_link from all_db_links order by 1", limit: 10_000)
        let list = rows.compactMap { $0.first?.displayText }
        linkCache = list
        return list
    }
}
