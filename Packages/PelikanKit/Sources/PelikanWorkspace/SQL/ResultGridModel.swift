import Foundation
import Observation
import PelikanDB

/// Model siatki wyników (ADR 0004): kolumny, pobrane wiersze, dociąganie porcjami z kursora sesji.
/// Bez AppKit — interfejs czyta `rowCount`, `columns`, `text(row:column:)`, a przy zbliżeniu do końca woła `fetchMore`.
@MainActor
@Observable
public final class ResultGridModel {
    public let columns: [ColumnInfo]
    public private(set) var rows: [[OracleValue]] = []
    public private(set) var hasMore: Bool
    public private(set) var isFetching = false
    public private(set) var lastError: String?
    /// Polecenie, z którego pochodzi wynik (odświeżanie, eksport SQL).
    public let sql: String
    @ObservationIgnored private let resultSet: ResultSetID
    @ObservationIgnored private var sessionRef: (any DatabaseSession)?
    @ObservationIgnored public var format: ValueFormat

    public init(columns: [ColumnInfo], resultSet: ResultSetID, session: any DatabaseSession, sql: String, format: ValueFormat) {
        self.columns = columns
        self.resultSet = resultSet
        sessionRef = session
        self.sql = sql
        self.format = format
        hasMore = true
    }

    public var rowCount: Int { rows.count }

    public func value(row: Int, column: Int) -> OracleValue {
        guard row < rows.count, column < rows[row].count else { return .null }
        return rows[row][column]
    }

    /// Tekst komórki (siatka pokazuje LOB/LONG jako `<CLOB>` itd. jak wzorzec — UG 7.2).
    public func text(row: Int, column: Int) -> String {
        let v = value(row: row, column: column)
        switch v {
        case .lob(let l): return "<\(l.kind.rawValue)>"
        case .cursor: return "<Cursor>"
        case .object(let t, _): return "<\(t)>"
        case .text(let s) where columns[column].type == .long: return s.isEmpty ? "" : "<Long>"
        case .raw where columns[column].type == .longRaw: return "<Long Raw>"
        default: return v.format(format)
        }
    }

    /// Dociąga kolejne `count` wierszy (nic nie robi, gdy kursor wyczerpany albo trwa pobieranie).
    public func fetchMore(_ count: Int) async {
        guard hasMore, !isFetching, let s = sessionRef else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let batch = try await s.fetch(resultSet, maxRows: count)
            rows.append(contentsOf: batch.rows)
            hasMore = batch.hasMore
            if !batch.hasMore { sessionRef = nil }
        } catch let e as OracleError {
            lastError = e.message
            hasMore = false
        } catch {
            lastError = error.localizedDescription
            hasMore = false
        }
    }

    /// Pobiera wszystkie wiersze („Last Page”), z limitem bezpieczeństwa.
    public func fetchAll(limit: Int = 5_000_000) async {
        while hasMore, rows.count < limit {
            let before = rows.count
            await fetchMore(10_000)
            if rows.count == before { break }
        }
    }

    /// Zamyka kursor (zamknięcie karty, ponowne wykonanie).
    public func close() async {
        guard hasMore, let s = sessionRef else { return }
        hasMore = false
        sessionRef = nil
        await s.closeResultSet(resultSet)
    }
}

/// Karta wyniku w SQL Window (UG 7.1): wynik zapytania albo komunikat polecenia.
@MainActor
@Observable
public final class ResultTab: Identifiable {
    public let id = UUID()
    public var title: String
    /// Zakres polecenia w tekście okna (UTF-16) — podświetlenie po wybraniu karty.
    public var statementRange: Range<Int>
    public var grid: ResultGridModel?
    public var message: String?
    public var pinned = false
    public var elapsed: Duration = .zero

    public init(title: String, statementRange: Range<Int>, grid: ResultGridModel? = nil, message: String? = nil) {
        self.title = title
        self.statementRange = statementRange
        self.grid = grid
        self.message = message
    }
}
