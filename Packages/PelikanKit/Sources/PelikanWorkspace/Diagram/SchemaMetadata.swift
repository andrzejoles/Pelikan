import Foundation
import PelikanDB

/// Kolumna tabeli lub widoku na diagramie i w Query Builderze.
public struct SchemaColumn: Sendable, Codable, Hashable {
    public var name: String
    public var type: String
    public var nullable: Bool
    public var primaryKey: Bool

    public init(name: String, type: String, nullable: Bool = true, primaryKey: Bool = false) {
        self.name = name; self.type = type; self.nullable = nullable; self.primaryKey = primaryKey
    }
}

/// Klucz obcy: tabela podrzędna (child) wskazuje nadrzędną (parent).
public struct ForeignKey: Sendable, Codable, Hashable {
    public var name: String
    public var childOwner: String
    public var childTable: String
    public var childColumns: [String]
    public var parentOwner: String
    public var parentTable: String
    public var parentColumns: [String]

    public init(name: String, childOwner: String, childTable: String, childColumns: [String], parentOwner: String, parentTable: String, parentColumns: [String]) {
        self.name = name; self.childOwner = childOwner; self.childTable = childTable; self.childColumns = childColumns
        self.parentOwner = parentOwner; self.parentTable = parentTable; self.parentColumns = parentColumns
    }
}

/// Źródło metadanych diagramu i Query Buildera — w aplikacji słownik bazy, w testach atrapa.
public protocol SchemaMetadataSource: Sendable {
    /// Obiekt o nazwie (`NAZWA` w bieżącym schemacie albo `SCHEMAT.NAZWA`); nil — nie ma.
    func resolve(_ name: String) async throws -> DBObject?
    func columns(owner: String, name: String) async throws -> [SchemaColumn]
    /// Klucze obce, w których tabela jest podrzędna albo nadrzędna.
    func foreignKeys(owner: String, table: String) async throws -> [ForeignKey]
    /// Obiekty, od których obiekt zależy (ALL_DEPENDENCIES), bez obiektów SYS.
    func references(owner: String, name: String) async throws -> [DBObject]
}

/// Metadane ze słownika bazy (ALL_TAB_COLUMNS, ALL_CONSTRAINTS, ALL_CONS_COLUMNS, ALL_DEPENDENCIES).
public struct SessionSchemaMetadata: SchemaMetadataSource {
    let session: any DatabaseSession

    public init(session: any DatabaseSession) { self.session = session }

    func bind(_ n: String, _ v: String?) -> BindVariable { BindVariable(name: n, value: v.map { .text($0) } ?? .null) }

    public func resolve(_ raw: String) async throws -> DBObject? {
        let parts = raw.split(separator: ".", maxSplits: 1).map { String($0).replacingOccurrences(of: "\"", with: "") }
        let owner = parts.count == 2 ? parts[0].uppercased() : nil
        let name = (parts.last ?? raw).uppercased()
        let (_, rows) = try await session.queryAll("""
            select owner, object_name, object_type from all_objects
             where object_name = :n and owner = nvl(:o, sys_context('userenv', 'current_schema'))
               and object_type in ('TABLE', 'VIEW', 'MATERIALIZED VIEW', 'PACKAGE', 'PROCEDURE', 'FUNCTION', 'TYPE', 'SEQUENCE', 'SYNONYM', 'TRIGGER')
             order by decode(object_type, 'TABLE', 1, 'VIEW', 2, 3)
            """, binds: [bind("n", name), bind("o", owner)], limit: 1)
        guard let r = rows.first, let o = r[0].displayText, let n = r[1].displayText, let t = r[2].displayText.flatMap(DBObjectType.init(rawValue:)) else { return nil }
        return DBObject(owner: o, name: n, type: t)
    }

    public func columns(owner: String, name: String) async throws -> [SchemaColumn] {
        let (_, rows) = try await session.queryAll("""
            select c.column_name,
                   c.data_type || case when c.data_type in ('VARCHAR2', 'CHAR', 'NVARCHAR2', 'RAW') then '(' || c.char_length || ')'
                                       when c.data_type = 'NUMBER' and c.data_precision is not null then '(' || c.data_precision || nvl2(nullif(c.data_scale, 0), ',' || c.data_scale, '') || ')' end,
                   c.nullable,
                   (select count(*) from all_cons_columns cc join all_constraints k on k.owner = cc.owner and k.constraint_name = cc.constraint_name
                     where k.constraint_type = 'P' and k.owner = c.owner and k.table_name = c.table_name and cc.column_name = c.column_name)
              from all_tab_columns c where c.owner = :o and c.table_name = :n order by c.column_id
            """, binds: [bind("o", owner), bind("n", name)], limit: 5000)
        return rows.map { SchemaColumn(name: $0[0].displayText ?? "", type: $0[1].displayText ?? "", nullable: $0[2].displayText == "Y", primaryKey: ($0[3].displayText ?? "0") != "0") }
    }

    public func foreignKeys(owner: String, table: String) async throws -> [ForeignKey] {
        let (_, rows) = try await session.queryAll("""
            select c.constraint_name, c.owner, c.table_name, p.owner, p.table_name,
                   (select listagg(column_name, ',') within group (order by position) from all_cons_columns where owner = c.owner and constraint_name = c.constraint_name),
                   (select listagg(column_name, ',') within group (order by position) from all_cons_columns where owner = p.owner and constraint_name = p.constraint_name)
              from all_constraints c join all_constraints p on p.owner = c.r_owner and p.constraint_name = c.r_constraint_name
             where c.constraint_type = 'R' and ((c.owner = :o and c.table_name = :n) or (p.owner = :o and p.table_name = :n))
             order by c.constraint_name
            """, binds: [bind("o", owner), bind("n", table)], limit: 2000)
        return rows.map { r in
            ForeignKey(name: r[0].displayText ?? "", childOwner: r[1].displayText ?? "", childTable: r[2].displayText ?? "",
                       childColumns: (r[5].displayText ?? "").split(separator: ",").map(String.init),
                       parentOwner: r[3].displayText ?? "", parentTable: r[4].displayText ?? "",
                       parentColumns: (r[6].displayText ?? "").split(separator: ",").map(String.init))
        }
    }

    public func references(owner: String, name: String) async throws -> [DBObject] {
        let (_, rows) = try await session.queryAll("""
            select distinct referenced_owner, referenced_name, referenced_type from all_dependencies
             where owner = :o and name = :n and referenced_owner not in ('SYS', 'PUBLIC') and referenced_type <> 'NON-EXISTENT'
            """, binds: [bind("o", owner), bind("n", name)], limit: 2000)
        return rows.compactMap { r in
            guard let o = r[0].displayText, let n = r[1].displayText, let t = r[2].displayText.flatMap(DBObjectType.init(rawValue:)) else { return nil }
            return DBObject(owner: o, name: n, type: t)
        }
    }
}

extension MetadataProvider {
    /// Metadane diagramu i Query Buildera w sesji metadanych połączenia.
    public func schemaSource() async throws -> SessionSchemaMetadata {
        SessionSchemaMetadata(session: try await session())
    }
}
