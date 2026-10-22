#if os(macOS)
import Darwin
import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// Siatka z milionem wierszy (cel Etapu 1). Tylko w Release (`make test-release`) i z bazą testową.
@MainActor
@Suite("PerformanceTests — siatka 1 mln wierszy", .serialized,
       .enabled(if: TestDatabase.isAvailable && ProcessInfo.processInfo.environment["PELIKAN_PERF_STRICT"] == "1"))
struct GridPerformanceTests {
    static func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    static func report(_ name: String, _ value: String, _ target: String, _ ok: Bool) {
        print("PERF\t\(name)\t\(value)\t\(target)\t\(ok ? "ok" : "fail")")
    }

    /// Pamięć rezydentna procesu (MB).
    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    @Test("Pierwsza strona, dociąganie porcjami, pobranie wszystkich, dostęp do komórek, pamięć")
    func millionRows() async throws {
        let session = try await TestDatabase.connect()
        let sql = "select level as id, 'Wiersz numer ' || level as txt, date '2026-01-01' + level / 86400 as d, mod(level, 97) * 1.5 as n from dual connect by level <= 1000000"
        let clock = ContinuousClock()
        let memBefore = Self.residentMB()

        // Pierwsza strona (100 wierszy) — od wykonania do pokazania.
        var grid: ResultGridModel!
        let first = try await clock.measure {
            let r = try await session.execute(sql)
            grid = ResultGridModel(columns: r.resultSet!.columns, resultSet: r.resultSet!.id, session: session, sql: sql, format: ValueFormat())
            await grid.fetchMore(100)
        }
        Self.report("Siatka: pierwsza strona (100 wierszy)", String(format: "%.0f ms", Self.ms(first)), "< 500 ms", first < .milliseconds(500))
        #expect(grid.rowCount == 100)

        // Porcja przy przewijaniu (1000 wierszy).
        var pages: [Duration] = []
        for _ in 0..<20 { pages.append(await clock.measure { await grid.fetchMore(1000) }) }
        let worstPage = pages.max()!
        Self.report("Siatka: porcja 1000 wierszy przy przewijaniu (najgorsza z 20)", String(format: "%.1f ms", Self.ms(worstPage)), "< 50 ms", worstPage < .milliseconds(50))
        #expect(worstPage < .milliseconds(50))

        // Wszystkie wiersze („Last Page”).
        let all = await clock.measure { await grid.fetchAll() }
        let rate = Double(grid.rowCount) / max(0.001, Self.ms(all) / 1000)
        Self.report("Siatka: pobranie 1 mln wierszy (4 kolumny)", String(format: "%.1f s (%.0f tys. wierszy/s)", Self.ms(all) / 1000, rate / 1000), "< 15 s", all < .seconds(15))
        #expect(grid.rowCount == 1_000_000)
        #expect(!grid.hasMore)
        #expect(all < .seconds(15))

        // Rysowanie widocznych komórek: losowy dostęp do tekstu komórek (ekran ≈ 50 wierszy × 4 kolumny).
        var rng = SystemRandomNumberGenerator()
        var chars = 0
        let cells = clock.measure {
            for _ in 0..<200 {
                let r = Int.random(in: 0..<1_000_000, using: &rng)
                for c in 0..<4 { chars += grid.text(row: r, column: c).utf8.count }
            }
        }
        Self.report("Siatka: tekst 200 komórek z dowolnego miejsca (jeden ekran)", String(format: "%.2f ms", Self.ms(cells)), "< 4 ms", cells < .milliseconds(4))
        #expect(chars > 0)
        #expect(cells < .milliseconds(4))

        let mem = Self.residentMB() - memBefore
        Self.report("Siatka: pamięć na 1 mln wierszy × 4 kolumny", String(format: "%.0f MB", mem), "< 800 MB", mem < 800)
        #expect(mem < 800)
        await session.close()
    }
}
#endif
