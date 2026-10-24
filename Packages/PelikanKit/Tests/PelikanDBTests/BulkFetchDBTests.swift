import Foundation
@testable import PelikanDB
@testable import PelikanODPI
import Testing

@Suite("Pobieranie hurtowe: paczka dopasowana do konsumenta", .serialized)
struct BulkFetchDBTests {
    @Test("Rozmiar paczki hurtowej: limit 10 000 i budżet pamięci, nie mniej niż bieżąca")
    func arraySize() {
        #expect(ODPISession.bulkFetchArraySize(rowBytes: 100, current: 500) == 10_000)
        // Szeroki wiersz (np. 4 kolumny VARCHAR2(4000) w UTF-8): budżet ~16 MB ogranicza paczkę, nie mniej niż bieżąca.
        #expect(ODPISession.bulkFetchArraySize(rowBytes: 4000, current: 500) == 4194)
        #expect(ODPISession.bulkFetchArraySize(rowBytes: 64_000, current: 500) == 500)
    }

    @Test("queryAll i pobieranie paczkami po 5000: komplet wierszy w kolejności, także po pierwszej małej paczce")
    func completeness() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let all = try await s.queryAll("select level n, rpad('x', mod(level, 200), 'y') t from dual connect by level <= 23456", limit: 1_000_000)
        #expect(all.rows.count == 23456)
        #expect(all.rows.enumerated().allSatisfy { i, r in if case .number(let v) = r[0] { v == String(i + 1) } else { false } })
        // Szeroki wiersz i pobieranie w kawałkach po 1 i 5000 wierszy przy paczce hurtowej.
        let r = try await s.execute("select level n, rpad('x', 3000, 'y') a, rpad('x', 3000, 'z') b from dual connect by level <= 3000",
                                    binds: [], options: ExecuteOptions(bulk: true))
        let rs = try #require(r.resultSet)
        var n = try await s.fetch(rs.id, maxRows: 1).rows.count
        while true { let b = try await s.fetch(rs.id, maxRows: 5000); n += b.rows.count; if !b.hasMore { break } }
        #expect(n == 3000)
    }
}
