import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Monitor zdarzeń i test obciążenia na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(2)))
struct MonitorTests {
    func workspace() throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    func waitFor(_ cond: () -> Bool) async {
        for _ in 0..<80 where !cond() { try? await Task.sleep(for: .milliseconds(100)) }
    }

    @Test("Alert DBMS_ALERT i wiadomość DBMS_PIPE odebrane przez monitor")
    func events() async throws {
        let (ws, id) = try workspace()
        let alerts = EventMonitor(kind: .alert, names: ["PELIKAN_ALERT"], connectionID: id, in: ws)
        let pipes = EventMonitor(kind: .pipe, names: ["PELIKAN_PIPE"], connectionID: id, in: ws)
        try await alerts.start()
        try await pipes.start()
        let sender = try await TestDatabase.connect()
        _ = try await sender.execute("begin dbms_alert.signal('PELIKAN_ALERT', 'cześć'); commit; end;")
        _ = try await sender.execute("declare st integer; begin dbms_pipe.pack_message('tekst'); dbms_pipe.pack_message(42); st := dbms_pipe.send_message('PELIKAN_PIPE'); end;")
        await waitFor { !alerts.events.isEmpty && !pipes.events.isEmpty }
        #expect(alerts.events.first?.name == "PELIKAN_ALERT" && alerts.events.first?.message == "cześć")
        #expect(pipes.events.first?.message == "tekst | 42")
        await alerts.stop()
        await pipes.stop()
        await sender.close()
        await ws.sessions.disconnectAll()
    }

    @Test("Test obciążenia: 3 wątki × 4 iteracje, zmienne :thread i :iteration, błąd liczony, CSV")
    func load() async throws {
        let (ws, id) = try workspace()
        var t = LoadTest()
        t.threads = 3
        t.iterations = 4
        t.steps = [LoadStep(name: "zapytanie", sql: "select :thread * 100 + :iteration from dual"),
                   LoadStep(name: "blok", sql: "begin update emp set sal = sal where empno = 7369; end;"),
                   LoadStep(name: "błąd", sql: "select * from nie_ma_takiej_tabeli")]
        let tester = LoadTester(t, connectionID: id, in: ws)
        tester.start()
        await tester.wait()
        #expect(!tester.running && tester.completedIterations == 12)
        #expect(tester.stats[0].count == 12 && tester.stats[0].errors == 0 && tester.stats[1].count == 12)
        #expect(tester.stats[2].errors == 12)
        #expect(tester.csv().contains("zapytanie;12;0;") && !tester.throughput.isEmpty)
        await ws.sessions.disconnectAll()
    }
}
