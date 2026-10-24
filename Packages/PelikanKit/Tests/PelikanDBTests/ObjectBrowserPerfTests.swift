import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

/// PD-OB-024: folder ze 100 000 obiektów bez blokady głównego wątku. Uruchamiany na żądanie
/// (`PELIKAN_PERF_OBJECTS=1`) — tworzy i usuwa 100 000 synonimów w schemacie testowym (kilka minut).
@MainActor
@Suite("Object Browser: 100 000 obiektów", .enabled(if: TestDatabase.isAvailable && ProcessInfo.processInfo.environment["PELIKAN_PERF_OBJECTS"] == "1"),
       .serialized)
struct ObjectBrowserPerfTests {
    @Test("Wczytanie folderu synonimów: czas i najdłuższa przerwa głównego wątku")
    func hundredThousand() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        let create = "begin for i in 1 .. 100000 loop execute immediate 'create or replace synonym pelikan_perf_' || i || ' for dual'; end loop; end;"
        let drop = "begin for r in (select synonym_name from user_synonyms where synonym_name like 'PELIKAN\\_PERF\\_%' escape '\\') loop execute immediate 'drop synonym ' || r.synonym_name; end loop; end;"
        _ = try await s.execute(create)
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        // Zegar głównego wątku: najdłuższa przerwa między kolejnymi taktami co 5 ms.
        var maxGap: Duration = .zero
        let clock = ContinuousClock()
        var last = clock.now
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
                let now = clock.now
                maxGap = max(maxGap, now - last)
                last = now
            }
        }
        let start = clock.now
        let objects = try await m.objects(.synonym, owner: schema)
        let elapsed = clock.now - start
        ticker.cancel()
        print("PERF 100k: \(objects.count) objects in \(elapsed), max main-thread gap \(maxGap)")
        #expect(objects.count >= 100_000)
        #expect(elapsed < .seconds(30))
        #expect(maxGap < .milliseconds(500), "\(maxGap)")
        _ = try await s.execute(drop)
        await ws.sessions.disconnectAll()
    }
}
