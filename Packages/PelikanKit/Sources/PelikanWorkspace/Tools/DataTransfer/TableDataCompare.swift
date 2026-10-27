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
    /// Kolumny identity GENERATED ALWAYS w tabeli celu — na czas wyrównania BY DEFAULT (inaczej ORA-32795/32796).
    public var identityAlways: [String] = []
    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// Wartości poleceń wykonywanych na bazie (wyrównanie danych, przenoszenie): literał SQL, a LOB-y i RAW jako zmienne
/// wiązane — literał ma limit 4000 bajtów i `ResultExporter.literal` zastępuje większe wartości przez NULL.
struct TransferValues {
    var binds: [BindVariable] = []

    /// Wyrażenie SQL wartości kolumny; dla LOB-a i RAW dopisuje zmienną wiązaną.
    mutating func sql(_ v: OracleValue, column: String) throws -> String {
        try Self.check(v, column: column)
        let name = "v\(binds.count)"
        switch v {
        case .lob(let l):
            binds.append(BindVariable(name: name, type: l.kind == .blob ? .blob : l.kind == .nclob ? .nclob : .clob, value: v))
        case .raw(let d):
            binds.append(BindVariable(name: name, type: .raw, value: v, maxSize: UInt32(max(1, d.count))))
        default:
            return ResultExporter.literal(v)
        }
        return ":" + name
    }

    /// Wartości, których nie da się porównać ani przenieść: LOB obcięty przy odczycie, BFILE, obiekt, kursor —
    /// błąd zamiast cichego NULL.
    static func check(_ v: OracleValue, column: String) throws {
        switch v {
        case .lob(let l) where l.truncated:
            throw CommandError.notAvailable(L10n.tr("Kolumna \(column): wartość \(l.kind.rawValue) jest dłuższa niż limit odczytu — nie da się jej porównać ani przenieść"))
        case .lob(let l) where l.kind == .bfile:
            throw CommandError.notAvailable(L10n.tr("Kolumna \(column): wartości typu \(l.kind.rawValue) nie da się porównać ani przenieść"))
        case .object(let t, _):
            throw CommandError.notAvailable(L10n.tr("Kolumna \(column): wartości typu \(t) nie da się porównać ani przenieść"))
        case .cursor:
            throw CommandError.notAvailable(L10n.tr("Kolumna \(column): wartości typu \("CURSOR") nie da się porównać ani przenieść"))
        default: break
        }
    }

    /// Równość wartości kolumny: LOB-y po pełnej treści, pozostałe po literale (bez zależności od sesji i NLS).
    static func same(_ a: OracleValue, _ b: OracleValue, column: String) throws -> Bool {
        try check(a, column: column)
        try check(b, column: column)
        if case .lob(let x) = a, case .lob(let y) = b { return x.kind == y.kind && x.text == y.text && x.bytes == y.bytes }
        return ResultExporter.literal(a) == ResultExporter.literal(b)
    }

    /// Wartość bez literału SQL (w skrypcie zostaje `NULL /* … */`).
    static func hasNoLiteral(_ v: OracleValue) -> Bool { ResultExporter.literal(v).hasPrefix("NULL /*") }
}

/// Porównanie danych tabel dwóch schematów (także różnych połączeń) i wyrównanie skryptem albo bezpośrednio.
public enum TableDataCompare {
    static func q(_ s: String) -> String { ResultExporter.identifier(s) }

    /// Klucz wiersza (tekst literałów kolumn klucza) — porównywanie bez względu na sesję i NLS.
    static func key(_ row: [OracleValue], _ idx: [Int]) -> String { idx.map { ResultExporter.literal(row[$0]) }.joined(separator: "\u{1F}") }

    static func rows(_ table: String, owner: String, columns: [TableTransfer.TableColumn], in s: any DatabaseSession) async throws -> [[OracleValue]] {
        // TIMESTAMP WITH LOCAL TIME ZONE w UTC — sesje źródła i celu mogą mieć różne strefy.
        let r = try await s.execute("select \(columns.map(\.selectExpression).joined(separator: ", ")) from \(q(owner)).\(q(table))", binds: [],
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
        // Kolumny wspólne obu tabel z wartościami (bez wirtualnych — UPDATE/INSERT daje ORA-54013; bez typów LONG).
        func stored(_ owner: String, _ s: any DatabaseSession) async throws -> [TableTransfer.TableColumn] {
            try await TableTransfer.columns(table, owner: owner, in: s).filter { !$0.virtual && !["LONG", "LONG RAW"].contains($0.type) }
        }
        let targetStored = try await stored(targetOwner, target)
        let targetCols = Set(targetStored.map(\.name))
        guard !targetCols.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak tabeli \(targetOwner).\(table) w celu")) }
        let common = try await stored(sourceOwner, source).filter { targetCols.contains($0.name) }
        let columns = common.map(\.name)
        let idx = keys.compactMap { columns.firstIndex(of: $0) }
        guard idx.count == keys.count else { throw CommandError.notAvailable(L10n.tr("Kolumny klucza \(table) różnią się w celu")) }
        let src = try await rows(table, owner: sourceOwner, columns: common, in: source)
        let dst = try await rows(table, owner: targetOwner, columns: common, in: target)
        var d = try diff(table: table, columns: columns, keyColumns: keys, source: src, target: dst)
        d.identityAlways = targetStored.filter { $0.identityAlways && columns.contains($0.name) }.map(\.name)
        return d
    }

    /// Różnice wierszy po kluczu; wartości nieporównywalne (LOB obcięty, obiekt) — błąd, nigdy „równe”.
    static func diff(table: String, columns: [String], keyColumns keys: [String], source src: [[OracleValue]], target dst: [[OracleValue]]) throws -> TableDataDiff {
        let idx = keys.compactMap { columns.firstIndex(of: $0) }
        let dstByKey = Dictionary(dst.map { (key($0, idx), $0) }, uniquingKeysWith: { a, _ in a })
        let srcKeys = Set(src.map { key($0, idx) })
        var inserts: [[OracleValue]] = [], updates: [[OracleValue]] = []
        for r in src {
            if let d = dstByKey[key(r, idx)] {
                for i in columns.indices where try !TransferValues.same(r[i], d[i], column: columns[i]) {
                    updates.append(r)
                    break
                }
            } else {
                inserts.append(r)
            }
        }
        let deletes = dst.filter { !srcKeys.contains(key($0, idx)) }
        return TableDataDiff(table: table, columns: columns, keyColumns: keys, inserts: inserts, updates: updates, deletes: deletes)
    }

    /// Polecenie wyrównujące: SQL z literałami (skrypt) albo z LOB-ami/RAW jako zmiennymi wiązanymi (wykonanie na bazie).
    struct Statement {
        enum Kind { case delete, update, insert }
        var kind: Kind
        var sql: String
        var binds: [BindVariable]
    }

    static func planned(_ d: TableDataDiff, table: String, options o: DataCompareOptions, bind: Bool) throws -> [Statement] {
        let idx = d.keyColumns.compactMap { d.columns.firstIndex(of: $0) }
        var out: [Statement] = []
        let groups: [(Statement.Kind, [[OracleValue]])] = [(.delete, o.delete ? d.deletes : []), (.update, o.update ? d.updates : []),
                                                           (.insert, o.insert ? d.inserts : [])]
        for (kind, rows) in groups {
            for r in rows {
                var values = TransferValues()
                func value(_ c: Int) throws -> String { bind ? try values.sql(r[c], column: d.columns[c]) : ResultExporter.literal(r[c]) }
                func whereKey() throws -> String { try idx.map { "\(q(d.columns[$0])) = \(try value($0))" }.joined(separator: " and ") }
                let sql: String
                switch kind {
                case .delete:
                    sql = "delete from \(table) where \(try whereKey())"
                case .update:
                    let sets = try d.columns.indices.filter { !idx.contains($0) }.map { "\(q(d.columns[$0])) = \(try value($0))" }
                    sql = "update \(table) set \(sets.joined(separator: ", ")) where \(try whereKey())"
                case .insert:
                    sql = "insert into \(table) (\(d.columns.map(q).joined(separator: ", "))) values (\(try r.indices.map(value).joined(separator: ", ")))"
                }
                out.append(Statement(kind: kind, sql: sql, binds: values.binds))
            }
        }
        return out
    }

    /// Identity ALWAYS celu: przed wstawieniami/zmianami BY DEFAULT, po nich ALWAYS z licznikiem od największej wartości.
    static func identitySwitch(_ d: TableDataDiff, table: String, options o: DataCompareOptions) -> (before: [String], after: [String]) {
        guard (o.insert && !d.inserts.isEmpty) || (o.update && !d.updates.isEmpty) else { return ([], []) }
        return (d.identityAlways.map { "alter table \(table) modify (\(q($0)) generated by default as identity)" },
                d.identityAlways.map { "alter table \(table) modify (\(q($0)) generated always as identity (start with limit value))" })
    }

    /// Polecenia wyrównujące (DELETE, UPDATE, INSERT) z literałami.
    public static func statements(_ d: TableDataDiff, targetOwner: String, options o: DataCompareOptions) -> [String] {
        // Bez wiązania nic nie rzuca błędu — literały jak w eksporcie.
        let table = (o.ownerInScript ? "\(q(targetOwner))." : "") + q(d.table)
        let identity = identitySwitch(d, table: table, options: o)
        return identity.before + ((try? planned(d, table: table, options: o, bind: false)) ?? []).map(\.sql) + identity.after
    }

    public static func script(_ diffs: [TableDataDiff], targetOwner: String, options o: DataCompareOptions) -> String {
        var out = "-- " + L10n.tr("Wyrównanie danych — wygenerowane przez Pelikana") + "\nset define off\n"
        if diffs.contains(where: { d in (d.inserts + d.updates).contains { $0.contains(where: TransferValues.hasNoLiteral) } }) {
            out += "-- " + L10n.tr("UWAGA: części wartości (duże LOB-y, obiekty) nie da się zapisać literałem — w skrypcie są jako NULL; wyrównaj je bezpośrednio na bazie") + "\n"
        }
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

    /// Bezpośrednia aktualizacja celu (Update database): zawsze w schemacie celu (opcja „schemat w SQL” dotyczy tylko
    /// skryptu), LOB-y i RAW jako zmienne wiązane; wartość nieprzenoszalna przerywa przed pierwszą zmianą.
    /// COMMIT co n poleceń; błędy poleceń w raporcie.
    public static func apply(_ diffs: [TableDataDiff], targetOwner: String, options o: DataCompareOptions, in s: any DatabaseSession) async throws -> ImportResult {
        let plan = try diffs.map { d in (d, try planned(d, table: "\(q(targetOwner)).\(q(d.table))", options: o, bind: true)) }
        var result = ImportResult()
        var n = 0
        for (d, statements) in plan {
            let identity = identitySwitch(d, table: "\(q(targetOwner)).\(q(d.table))", options: o)
            for sql in identity.before { _ = try await s.execute(sql) }
            do {
                for st in statements {
                    do {
                        let r = try await s.execute(st.sql, binds: st.binds)
                        switch st.kind {
                        case .insert: result.inserted += Int(r.rowsAffected)
                        case .update: result.updated += Int(r.rowsAffected)
                        case .delete: result.deleted += Int(r.rowsAffected)
                        }
                    } catch {
                        result.errors.append("\(d.table): \(error.localizedDescription)")
                    }
                    n += 1
                    if o.commitEvery > 0, n % o.commitEvery == 0 { try await s.commit() }
                }
            } catch {
                for sql in identity.after { _ = try? await s.execute(sql) }
                throw error
            }
            // ALTER zatwierdza transakcję — jak COMMIT co n poleceń.
            for sql in identity.after {
                do { _ = try await s.execute(sql) } catch { result.errors.append("\(d.table): \(error.localizedDescription)") }
            }
        }
        try await s.commit()
        return result
    }
}
