import Foundation
import PelikanDB

/// Generowanie SQL z zaznaczonych wierszy siatki (DB-GRID-002): INSERT, UPDATE, DELETE, MERGE.
/// Klucz: kolumny klucza głównego tabeli (gdy są w wyniku) albo ROWID; literały przez `ResultExporter.literal`.
public enum RowSQLGenerator {
    public enum Kind: String, Sendable, CaseIterable { case insert, update, delete, merge }

    public enum GenerationError: Error, LocalizedError, Equatable {
        case noKey
        public var errorDescription: String? {
            L10n.tr("Brak klucza: wynik nie zawiera kolumn klucza głównego ani ROWID — UPDATE, DELETE i MERGE nie mają warunku")
        }
    }

    static func isRowid(_ c: ColumnInfo) -> Bool { c.type == .rowid || c.name.uppercased() == "ROWID" }

    /// - Parameters:
    ///   - table: nazwa tabeli (z właścicielem albo bez)
    ///   - keyColumns: nazwy kolumn klucza głównego; puste — ROWID z wyniku
    public static func statements(_ kind: Kind, table: String, columns: [ColumnInfo], rows: [[OracleValue]], keyColumns: [String]) throws -> String {
        let id = { (n: String) in ResultExporter.identifier(n) }
        let dataCols = columns.indices.filter { !isRowid(columns[$0]) }
        let keyIdx: [Int] = {
            let pk = keyColumns.compactMap { k in columns.firstIndex { $0.name.caseInsensitiveCompare(k) == .orderedSame } }
            if !keyColumns.isEmpty, pk.count == keyColumns.count { return pk }
            return columns.indices.filter { isRowid(columns[$0]) }
        }()
        let usesRowid = keyIdx.contains { isRowid(columns[$0]) }
        if kind != .insert, keyIdx.isEmpty { throw GenerationError.noKey }
        func cond(_ row: [OracleValue]) -> String {
            keyIdx.map { i in
                let name = usesRowid ? "ROWID" : id(columns[i].name)
                if case .null = row[i] { return "\(name) IS NULL" }
                return "\(name) = \(ResultExporter.literal(row[i]))"
            }.joined(separator: " AND ")
        }
        let nonKey = dataCols.filter { !keyIdx.contains($0) }
        var out: [String] = []
        for row in rows {
            switch kind {
            case .insert:
                out.append("INSERT INTO \(table) (\(dataCols.map { id(columns[$0].name) }.joined(separator: ", ")))\n  VALUES (\(dataCols.map { ResultExporter.literal(row[$0]) }.joined(separator: ", ")));")
            case .update:
                guard !nonKey.isEmpty else { continue }
                out.append("UPDATE \(table)\n   SET \(nonKey.map { "\(id(columns[$0].name)) = \(ResultExporter.literal(row[$0]))" }.joined(separator: ",\n       "))\n WHERE \(cond(row));")
            case .delete:
                out.append("DELETE FROM \(table) WHERE \(cond(row));")
            case .merge:
                // MERGE po ROWID nie ma sensu dla nowych wierszy — warunek łączenia na kolumnach klucza głównego.
                if usesRowid { throw GenerationError.noKey }
                let src = dataCols.map { "\(ResultExporter.literal(row[$0])) AS \(id(columns[$0].name))" }.joined(separator: ", ")
                let on = keyIdx.map { "t.\(id(columns[$0].name)) = s.\(id(columns[$0].name))" }.joined(separator: " AND ")
                var m = "MERGE INTO \(table) t\nUSING (SELECT \(src) FROM dual) s\n   ON (\(on))"
                if !nonKey.isEmpty {
                    m += "\n WHEN MATCHED THEN UPDATE SET \(nonKey.map { "t.\(id(columns[$0].name)) = s.\(id(columns[$0].name))" }.joined(separator: ", "))"
                }
                m += "\n WHEN NOT MATCHED THEN INSERT (\(dataCols.map { id(columns[$0].name) }.joined(separator: ", ")))"
                m += " VALUES (\(dataCols.map { "s.\(id(columns[$0].name))" }.joined(separator: ", ")));"
                out.append(m)
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Kolumny klucza głównego tabeli (ALL_CONSTRAINTS/ALL_CONS_COLUMNS) w kolejności pozycji.
    public static func primaryKey(owner: String, table: String, in s: any DatabaseSession) async throws -> [String] {
        let (_, rows) = try await s.queryAll("""
            select cc.column_name from all_constraints c
              join all_cons_columns cc on cc.owner = c.owner and cc.constraint_name = c.constraint_name
             where c.constraint_type = 'P' and c.owner = :o and c.table_name = :t order by cc.position
            """, binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "t", value: .text(table))], limit: 100)
        return rows.compactMap { $0.first?.displayText }
    }
}
