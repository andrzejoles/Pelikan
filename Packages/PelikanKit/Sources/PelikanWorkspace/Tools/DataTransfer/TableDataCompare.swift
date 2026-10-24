import Foundation
import PelikanDB
import PelikanSQL

/// Akcje porównania danych (UG 24.12, PD-TOOL-013).
public struct DataCompareOptions: Sendable, Codable, Hashable {
    public var insert = true
    public var update = true
    public var delete = true
    public var commitEvery = 100
    /// Nazwa schematu docelowego w skrypcie.
    public var ownerInScript = true
    public init() {}
}

/// Różnice danych jednej tabeli: wiersze tylko w źródle, różne (po kluczu głównym) i tylko w celu.
public struct TableDataDiff: Sendable, Identifiable {
    public var table: String
    public var id: String { table }
    public var columns: [String]
    public var keyColumns: [String]
    public var inserts: [[OracleValue]]
    public var updates: [[OracleValue]]
    public var deletes: [[OracleValue]]
    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// Porównanie danych tabel dwóch schematów (także różnych połączeń) i wyrównanie skryptem albo bezpośrednio.
public enum TableDataCompare {
    static func q(_ s: String) -> String { ResultExporter.identifier(s) }

    /// Klucz wiersza (tekst literałów kolumn klucza) — porównywanie bez względu na sesję i NLS.
    static func key(_ row: [OracleValue], _ idx: [Int]) -> String { idx.map { ResultExporter.literal(row[$0]) }.joined(separator: "\u{1F}") }

    static func rows(_ table: String, owner: String, columns: [String], in s: any DatabaseSession) async throws -> [[OracleValue]] {
        let r = try await s.execute("select \(columns.map(q).joined(separator: ", ")) from \(q(owner)).\(q(table))", binds: [],
                                    options: ExecuteOptions(lobLimit: 10_000_000, bulk: true))
        guard let rs = r.resultSet else { return [] }
        var out: [[OracleValue]] = []
        while true {
            let b = try await s.fetch(rs.id, maxRows: 5000)
            out += b.rows
            if !b.hasMore { break }
            if out.count > 5_000_000 { throw CommandError.notAvailable(L10n.tr("Tabela \(table) jest za duża do porównania (ponad 5 mln wierszy)")) }
        }
        return out
    }

    public static func compare(table: String, sourceOwner: String, source: any DatabaseSession, targetOwner: String, target: any DatabaseSession) async throws -> TableDataDiff {
        let keys = try await TextImport.primaryKey(owner: sourceOwner, table: table, in: source)
        guard !keys.isEmpty else { throw CommandError.notAvailable(L10n.tr("Tabela \(table) nie ma klucza głównego — porównanie wymaga klucza")) }
        // Kolumny wspólne obu tabel (bez LOB-ów długich typów LONG).
        let colSQL = "select column_name from all_tab_columns where owner = :o and table_name = :t and data_type not in ('LONG', 'LONG RAW') order by column_id"
        let (_, sc) = try await source.queryAll(colSQL, binds: [BindVariable(name: "o", value: .text(sourceOwner)), BindVariable(name: "t", value: .text(table))])
        let (_, tc) = try await target.queryAll(colSQL, binds: [BindVariable(name: "o", value: .text(targetOwner)), BindVariable(name: "t", value: .text(table))])
        let targetCols = Set(tc.compactMap { $0.first?.displayText })
        guard !targetCols.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak tabeli \(targetOwner).\(table) w celu")) }
        let columns = sc.compactMap { $0.first?.displayText }.filter { targetCols.contains($0) }
        let idx = keys.compactMap { columns.firstIndex(of: $0) }
        guard idx.count == keys.count else { throw CommandError.notAvailable(L10n.tr("Kolumny klucza \(table) różnią się w celu")) }
        let src = try await rows(table, owner: sourceOwner, columns: columns, in: source)
        let dst = try await rows(table, owner: targetOwner, columns: columns, in: target)
        let dstByKey = Dictionary(dst.map { (key($0, idx), $0) }, uniquingKeysWith: { a, _ in a })
        let srcKeys = Set(src.map { key($0, idx) })
        var inserts: [[OracleValue]] = [], updates: [[OracleValue]] = []
        for r in src {
            if let d = dstByKey[key(r, idx)] {
                if r.map(ResultExporter.literal) != d.map(ResultExporter.literal) { updates.append(r) }
            } else {
                inserts.append(r)
            }
        }
        let deletes = dst.filter { !srcKeys.contains(key($0, idx)) }
        return TableDataDiff(table: table, columns: columns, keyColumns: keys, inserts: inserts, updates: updates, deletes: deletes)
    }

    /// Polecenia wyrównujące (DELETE, UPDATE, INSERT) z literałami.
    public static func statements(_ d: TableDataDiff, targetOwner: String, options o: DataCompareOptions) -> [String] {
        let table = (o.ownerInScript ? "\(q(targetOwner))." : "") + q(d.table)
        let idx = d.keyColumns.compactMap { d.columns.firstIndex(of: $0) }
        func whereKey(_ r: [OracleValue]) -> String { idx.map { "\(q(d.columns[$0])) = \(ResultExporter.literal(r[$0]))" }.joined(separator: " and ") }
        var out: [String] = []
        if o.delete { out += d.deletes.map { "delete from \(table) where \(whereKey($0))" } }
        if o.update {
            out += d.updates.map { r in
                let sets = d.columns.indices.filter { !idx.contains($0) }.map { "\(q(d.columns[$0])) = \(ResultExporter.literal(r[$0]))" }
                return "update \(table) set \(sets.joined(separator: ", ")) where \(whereKey(r))"
            }
        }
        if o.insert {
            let cols = d.columns.map(q).joined(separator: ", ")
            out += d.inserts.map { "insert into \(table) (\(cols)) values (\($0.map(ResultExporter.literal).joined(separator: ", ")))" }
        }
        return out
    }

    public static func script(_ diffs: [TableDataDiff], targetOwner: String, options o: DataCompareOptions) -> String {
        var out = "-- " + L10n.tr("Wyrównanie danych — wygenerowane przez Pelikana") + "\nset define off\n"
        var n = 0
        for d in diffs {
            for st in statements(d, targetOwner: targetOwner, options: o) {
                out += st + ";\n"
                n += 1
                if o.commitEvery > 0, n % o.commitEvery == 0 { out += "commit;\n" }
            }
        }
        return out + "commit;\nset define on\n"
    }

    /// Bezpośrednia aktualizacja celu (Update database): COMMIT co n poleceń; błędy w raporcie.
    public static func apply(_ diffs: [TableDataDiff], targetOwner: String, options o: DataCompareOptions, in s: any DatabaseSession) async throws -> ImportResult {
        var result = ImportResult()
        var n = 0
        for d in diffs {
            for st in statements(d, targetOwner: targetOwner, options: o) {
                do {
                    let r = try await s.execute(st)
                    if st.hasPrefix("insert") { result.inserted += Int(r.rowsAffected) } else if st.hasPrefix("update") { result.updated += Int(r.rowsAffected) } else { result.deleted += Int(r.rowsAffected) }
                } catch {
                    result.errors.append("\(d.table): \(error.localizedDescription)")
                }
                n += 1
                if o.commitEvery > 0, n % o.commitEvery == 0 { try await s.commit() }
            }
        }
        try await s.commit()
        return result
    }
}
