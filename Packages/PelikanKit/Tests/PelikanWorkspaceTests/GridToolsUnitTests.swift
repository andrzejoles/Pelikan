import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Narzędzia siatki na posortowanej i przefiltrowanej siatce: wiersz widoku mapowany raz (APP2-01).
@MainActor
@Suite("Narzędzia siatki: wiersze widoku przy sortowaniu i filtrze")
struct GridToolsUnitTests {
    let columns = [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER"),
                   ColumnInfo(name: "NAME", type: .varchar2, typeName: "VARCHAR2(20)")]

    func grid(_ rows: [[OracleValue]]) async -> ResultGridModel {
        let g = ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession(rows), sql: "select id, name from t", format: ValueFormat())
        await g.fetchAll()
        return g
    }

    /// Dane: 1 a, 2 b, 3 c; malejąco po ID widok = 3 c, 2 b, 1 a.
    var sample: [[OracleValue]] { [[.number("1"), .text("a")], [.number("2"), .text("b")], [.number("3"), .text("c")]] }

    @Test("Posortowana malejąco: rowValues, compareRecords, compareResults i columnToFiles dla wiersza widoku 0")
    func sorted() async throws {
        let g = await grid(sample)
        g.sort([.init(column: 0, ascending: false)])
        #expect(GridTools.rowValues(g, viewRow: 0)["NAME"] == .text("c"))
        #expect(GridTools.compareRecords(g, viewRows: [0, 2], ignoreCase: false).first { $0.column == "NAME" }?.values == ["c", "a"])

        // Ta sama kolejność widoku z obu stron — wyniki identyczne; inna — różnica w wierszu 0.
        let other = await grid(sample.reversed())
        #expect(GridTools.compareResults(g, other).identical)
        let plain = await grid(sample)
        #expect(GridTools.compareResults(g, plain).cells.contains(.init(row: 0, column: "NAME")))

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-c2f-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try GridTools.columnToFiles(g, column: 1, viewRows: [0], directory: dir, template: "[ID].txt")
        #expect(try String(contentsOf: dir.appendingPathComponent("3.txt"), encoding: .utf8) == "c")
    }

    @Test("Przefiltrowana: wiersz widoku 0 to pierwszy pasujący, nie pierwszy pobrany")
    func filtered() async throws {
        let g = await grid(sample)
        g.setFilter(GridFilter(groups: [[.init(column: "NAME", op: .ne, value: "a")]], text: "NAME <> 'a'"))
        #expect(g.rowCount == 2)
        #expect(GridTools.rowValues(g, viewRow: 0)["ID"] == .number("2"))
        #expect(GridTools.compareRecords(g, viewRows: [0, 1], ignoreCase: false).first { $0.column == "NAME" }?.values == ["b", "c"])
        let tail = await grid(Array(sample.dropFirst()))
        #expect(GridTools.compareResults(g, tail).identical)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-c2f-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try GridTools.columnToFiles(g, column: 1, viewRows: [0, 1], directory: dir, template: "[ID]_[NAME].txt")
        #expect(r.files == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["2_b.txt", "3_c.txt"])
    }
}
