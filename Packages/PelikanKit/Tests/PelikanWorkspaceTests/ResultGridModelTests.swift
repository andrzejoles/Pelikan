import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Sesja z gotowym wynikiem, oddawanym porcjami.
final class RowsSession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    let remaining: Mutex<[[OracleValue]]>
    init(_ rows: [[OracleValue]]) { remaining = Mutex(rows) }
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult { ExecutionResult(kind: .other) }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch {
        remaining.withLock { r in
            let batch = Array(r.prefix(maxRows))
            r.removeFirst(batch.count)
            return RowBatch(rows: batch, hasMore: !r.isEmpty)
        }
    }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
}

@MainActor
@Suite("Model siatki: sortowanie, dociąganie, dane do eksportu")
struct ResultGridModelTests {
    let columns = [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER"),
                   ColumnInfo(name: "NAME", type: .varchar2, typeName: "VARCHAR2(20)"),
                   ColumnInfo(name: "D", type: .date, typeName: "DATE")]

    func grid(_ rows: [[OracleValue]]) -> ResultGridModel {
        ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession(rows), sql: "select id, name, d from t", format: ValueFormat())
    }

    var sample: [[OracleValue]] {
        [[.number("10"), .text("beta"), .timestamp(OracleTimestamp(year: 2024, month: 5, day: 1), .date)],
         [.number("9.5"), .text("Alfa"), .null],
         [.null, .text("gamma"), .timestamp(OracleTimestamp(year: 2023, month: 1, day: 1), .date)],
         [.number("100"), .text("alfa"), .timestamp(OracleTimestamp(year: 2025, month: 1, day: 1), .date)]]
    }

    @Test("Liczby numerycznie (nie tekstowo), NULL na końcu; malejąco; trzeci klik wyłącza")
    func numeric() async {
        let g = grid(sample)
        await g.fetchAll()
        g.toggleSort(column: 0)
        #expect((0..<4).map { g.text(row: $0, column: 0) } == ["9.5", "10", "100", ""])
        g.toggleSort(column: 0)
        #expect((0..<4).map { g.text(row: $0, column: 0) } == ["", "100", "10", "9.5"])
        g.toggleSort(column: 0)
        #expect(g.sortKeys.isEmpty)
        #expect(g.text(row: 0, column: 0) == "10")
    }

    @Test("Tekst bez rozróżniania wielkości liter (stabilnie); klucz dodatkowy z Shift; daty chronologicznie")
    func textAndSecondary() async {
        let g = grid(sample)
        await g.fetchAll()
        g.toggleSort(column: 1)
        #expect((0..<4).map { g.text(row: $0, column: 1) } == ["Alfa", "alfa", "beta", "gamma"])
        g.toggleSort(column: 1)          // malejąco
        g.toggleSort(column: 0, add: true)
        #expect(g.sortKeys == [.init(column: 1, ascending: false), .init(column: 0, ascending: true)])
        g.sort([.init(column: 2, ascending: true)])
        #expect((0..<4).map { g.text(row: $0, column: 1) } == ["gamma", "beta", "alfa", "Alfa"])
    }

    @Test("Po dociągnięciu sortowanie obejmuje nowe wiersze")
    func resortAfterFetch() async {
        let g = grid((1...30).map { [.number(String(31 - $0)), .text("r\($0)"), .null] })
        await g.fetchMore(10)
        g.toggleSort(column: 0)
        #expect(g.text(row: 0, column: 0) == "21")
        await g.fetchMore(20)
        #expect(g.text(row: 0, column: 0) == "1")
        #expect(g.rowCount == 30)
    }

    @Test("Dane do eksportu w kolejności widoku, wybrane wiersze i kolumny, tabela z zapytania")
    func exportData() async {
        let g = grid(sample)
        await g.fetchAll()
        g.toggleSort(column: 1)
        let d = g.exportData(rows: [0, 1], columns: [1, 0], title: "T")
        #expect(d.columns.map(\.name) == ["NAME", "ID"])
        #expect(d.rows.map { $0[0].format(.default) } == ["Alfa", "alfa"])
        #expect(d.tableName == "T")
    }
}
