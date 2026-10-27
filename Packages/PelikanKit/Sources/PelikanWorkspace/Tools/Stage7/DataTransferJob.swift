import Foundation
import PelikanDB
import PelikanSQL

/// Mapowanie kolumny celu: wyrażenie źródła (kolumna zapytania źródłowego albo stała SQL) lub pominięcie.
public struct TransferColumnMapping: Sendable, Codable, Hashable, Identifiable {
    public var target: String
    /// Kolumna źródła (nazwa z zapytania źródłowego); nil — `constant` albo pominięta.
    public var source: String?
    /// Wyrażenie SQL wstawiane zamiast wartości (np. `sysdate`, `'X'`), gdy nie ma kolumny źródła.
    public var constant = ""
    public var id: String { target }
    public init(target: String, source: String?, constant: String = "") { self.target = target; self.source = source; self.constant = constant }
    public var isUsed: Bool { source != nil || !constant.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Definicja przeniesienia danych (DB-XFER-001): źródło (tabela albo zapytanie) w jednym połączeniu, tabela docelowa
/// w tym samym albo innym połączeniu, mapowanie kolumn i tryb. Połączenia po nazwie — bez haseł.
public struct DataTransferJob: Sendable, Codable, Hashable {
    public enum Mode: String, Sendable, Codable, CaseIterable { case append, truncate, delete }
    public var sourceConnection = ""
    public var sourceOwner = ""
    public var sourceTable = ""
    /// Zapytanie źródłowe (zamiast tabeli).
    public var sourceQuery = ""
    public var whereClause = ""
    public var targetConnection = ""
    public var targetOwner = ""
    public var targetTable = ""
    public var mappings: [TransferColumnMapping] = []
    public var mode: Mode = .append
    public var commitEvery = 1000
    /// Błąd wiersza: kontynuacja (z listą błędów) albo przerwanie.
    public var continueOnError = true
    public init() {}

    public var sourceSQL: String {
        let q = sourceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            var t = q
            while t.hasSuffix(";") { t.removeLast() }
            return t
        }
        let w = whereClause.trimmingCharacters(in: .whitespaces)
        return "select * from \(ResultExporter.identifier(sourceOwner.uppercased())).\(ResultExporter.identifier(sourceTable.uppercased()))" + (w.isEmpty ? "" : " where \(w)")
    }

    var targetName: String { "\(ResultExporter.identifier(targetOwner.uppercased())).\(ResultExporter.identifier(targetTable.uppercased()))" }
}

public enum DataTransferRunner {
    /// Limit odczytu wartości LOB przy przenoszeniu (bajty).
    static let lobLimit = 10_000_000

    /// Mapowanie domyślne: kolumny celu do kolumn źródła o tej samej nazwie (bez rozróżniania wielkości liter).
    public static func defaultMappings(targetColumns: [String], sourceColumns: [String]) -> [TransferColumnMapping] {
        targetColumns.map { t in TransferColumnMapping(target: t, source: sourceColumns.first { $0.caseInsensitiveCompare(t) == .orderedSame }) }
    }

    /// Kolumny celu, które przyjmują wartości: bez wirtualnych (ORA-54013) i identity ALWAYS (ORA-32795).
    public static func targetColumns(_ job: DataTransferJob, in s: any DatabaseSession) async throws -> [String] {
        try await TableTransfer.columns(job.targetTable.uppercased(), owner: job.targetOwner.uppercased(), in: s)
            .filter { !$0.virtual && !$0.identityAlways }.map(\.name)
    }

    /// Kolumny zapytania źródłowego (bez pobierania wierszy).
    public static func sourceColumns(_ job: DataTransferJob, in s: any DatabaseSession) async throws -> [String] {
        let r = try await s.execute("select * from (\(job.sourceSQL)) where 1 = 0", binds: [], options: ExecuteOptions())
        guard let rs = r.resultSet else { return [] }
        await s.closeResultSet(rs.id)
        return rs.columns.map(\.name)
    }

    /// Polecenie INSERT dla wiersza (literały wartości; stałe jako wyrażenia SQL).
    public static func insert(_ job: DataTransferJob, columns: [String], row: [OracleValue]) -> String {
        // Bez wiązania nic nie rzuca błędu — literały jak w eksporcie.
        (try? statement(job, columns: columns, row: row, bind: false).sql) ?? ""
    }

    /// INSERT wiersza do wykonania: LOB-y i RAW jako zmienne wiązane (bez limitu literału); wartość nieprzenoszalna
    /// (LOB obcięty przy odczycie, obiekt) — błąd zamiast NULL.
    static func statement(_ job: DataTransferJob, columns: [String], row: [OracleValue], bind: Bool) throws -> (sql: String, binds: [BindVariable]) {
        let used = job.mappings.filter(\.isUsed)
        var bound = TransferValues()
        var values: [String] = []
        for m in used {
            if let src = m.source, let i = columns.firstIndex(where: { $0.caseInsensitiveCompare(src) == .orderedSame }), i < row.count {
                values.append(bind ? try bound.sql(row[i], column: src) : ResultExporter.literal(row[i]))
            } else {
                values.append(m.constant.isEmpty ? "null" : m.constant)
            }
        }
        return ("insert into \(job.targetName) (\(used.map { ResultExporter.identifier($0.target) }.joined(separator: ", "))) values (\(values.joined(separator: ", ")))",
                bound.binds)
    }

    /// Kontrola definicji przed wykonaniem.
    public static func validate(_ job: DataTransferJob) throws {
        guard !job.targetTable.isEmpty, !job.targetOwner.isEmpty else { throw CommandError.notAvailable(L10n.tr("Wskaż tabelę docelową")) }
        guard job.sourceQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || !job.sourceTable.isEmpty else {
            throw CommandError.notAvailable(L10n.tr("Wskaż tabelę albo zapytanie źródłowe"))
        }
        guard job.mappings.contains(where: \.isUsed) else { throw CommandError.notAvailable(L10n.tr("Mapowanie nie zawiera żadnej kolumny")) }
    }

    /// Przeniesienie: odczyt partiami ze źródła, INSERT do celu, COMMIT co n wierszy (źródło i cel mogą być różnymi sesjami).
    public static func run(_ job: DataTransferJob, source: any DatabaseSession, target: any DatabaseSession,
                           progress: (@MainActor (Int) -> Void)? = nil) async throws -> ImportResult {
        try validate(job)
        var result = ImportResult()
        // Zapytanie źródła przed czyszczeniem celu: kolumny typów nieprzenoszalnych przerywają, zanim cokolwiek zmienimy.
        let r = try await source.execute(job.sourceSQL, binds: [], options: ExecuteOptions(lobLimit: Self.lobLimit, bulk: true))
        guard let rs = r.resultSet else { throw CommandError.notAvailable(L10n.tr("Źródło musi być zapytaniem SELECT")) }
        let columns = rs.columns.map(\.name)
        let mapped = Set(job.mappings.filter(\.isUsed).compactMap { $0.source?.uppercased() })
        if let bad = rs.columns.first(where: { [.object, .bfile, .refCursor].contains($0.type) && mapped.contains($0.name.uppercased()) }) {
            await source.closeResultSet(rs.id)
            throw CommandError.notAvailable(L10n.tr("Kolumna \(bad.name): wartości typu \(bad.typeName) nie da się porównać ani przenieść"))
        }
        // LOB ponad limit odczytu przerwałby przeniesienie w połowie — po TRUNCATE/DELETE i zatwierdzonych paczkach —
        // więc długości sprawdzamy przed jakąkolwiek zmianą w celu (CLOB: znaki, zapas na 4 bajty na znak).
        let lobs = rs.columns.filter { [.blob, .clob, .nclob].contains($0.type) && mapped.contains($0.name.uppercased()) }
        if !lobs.isEmpty {
            let exprs = lobs.map { "max(dbms_lob.getlength(\(ResultExporter.identifier($0.name))))" }.joined(separator: ", ")
            let (_, rows) = try await source.queryAll("select \(exprs) from (\(job.sourceSQL))", limit: 1)
            for (i, c) in lobs.enumerated() where (Int(rows.first?[i].displayText ?? "") ?? 0) > (c.type == .blob ? Self.lobLimit : Self.lobLimit / 4) {
                await source.closeResultSet(rs.id)
                throw CommandError.notAvailable(L10n.tr("Kolumna \(c.name): wartości LOB są większe niż limit przenoszenia (10 MB)"))
            }
        }
        switch job.mode {
        case .append: break
        case .truncate: _ = try await target.execute("truncate table \(job.targetName)")
        case .delete: result.deleted = Int(try await target.execute("delete from \(job.targetName)").rowsAffected)
        }
        var n = 0
        while true {
            try Task.checkCancellation()
            let batch = try await source.fetch(rs.id, maxRows: 5000)
            for row in batch.rows {
                // Wartość nieprzenoszalna (np. LOB ponad limit odczytu) przerywa całe przeniesienie — bez cichego NULL.
                let st: (sql: String, binds: [BindVariable])
                do { st = try statement(job, columns: columns, row: row, bind: true) } catch {
                    await source.closeResultSet(rs.id)
                    try await target.rollback()
                    throw error
                }
                do {
                    _ = try await target.execute(st.sql, binds: st.binds)
                    result.inserted += 1
                } catch {
                    result.errors.append(L10n.tr("Wiersz \(n + 1): \(error.localizedDescription)"))
                    if !job.continueOnError { await source.closeResultSet(rs.id); try await target.rollback(); throw error }
                }
                n += 1
                if job.commitEvery > 0, n % job.commitEvery == 0 { try await target.commit() }
            }
            await progress?(n)
            if !batch.hasMore { break }
        }
        try await target.commit()
        return result
    }
}

/// Zapisane definicje przeniesień (`Transfers/*.json` w katalogu danych) — także do zadań lokalnych.
public enum DataTransferStore {
    static func directory(_ base: URL?) -> URL? { base?.appendingPathComponent("Transfers", isDirectory: true) }

    public static func names(in base: URL?) -> [String] {
        guard let d = directory(base), let files = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    public static func save(_ job: DataTransferJob, name: String, in base: URL?) throws {
        guard let d = directory(base) else { return }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(job).write(to: d.appendingPathComponent(ImportProfileStore.safe(name) + ".json"), options: .atomic)
    }

    public static func load(_ name: String, in base: URL?) throws -> DataTransferJob {
        guard let d = directory(base) else { throw CommandError.notAvailable(L10n.tr("Brak katalogu danych")) }
        return try JSONDecoder().decode(DataTransferJob.self, from: Data(contentsOf: d.appendingPathComponent(ImportProfileStore.safe(name) + ".json")))
    }
}

extension Workspace {
    /// Identyfikator połączenia po nazwie wyświetlanej (definicje narzędzi zapisują nazwy, nie hasła ani adresy).
    public func connectionID(named name: String) -> UUID? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return activeDocument.flatMap { effectiveConnection(of: $0) } ?? sessions.mainConnectionID }
        return connections.connections.first { $0.displayName.caseInsensitiveCompare(n) == .orderedSame }?.id
    }

    /// Przeniesienie danych w sesjach narzędzi połączeń źródła i celu; zmiana celu przez strażnika zmian.
    public func runDataTransfer(_ job: DataTransferJob, progress: (@MainActor (Int) -> Void)? = nil) async throws -> ImportResult {
        guard let src = connectionID(named: job.sourceConnection) else { throw CommandError.notAvailable(L10n.tr("Nieznane połączenie źródła „\(job.sourceConnection)”")) }
        guard let dst = connectionID(named: job.targetConnection) else { throw CommandError.notAvailable(L10n.tr("Nieznane połączenie celu „\(job.targetConnection)”")) }
        try await guardModification(["insert into \(job.targetName) values (null)"], connectionID: dst)
        let source = try await sessions.session(SessionKey(connectionID: src, purpose: .tool("transfer-source")))
        let target = try await sessions.session(SessionKey(connectionID: dst, purpose: .tool("transfer-target")))
        return try await DataTransferRunner.run(job, source: source, target: target, progress: progress)
    }
}
