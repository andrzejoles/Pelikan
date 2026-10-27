import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Sterownik, którego łączenie czeka na otwarcie bramki (okno pytania, długie łączenie).
final class ConnectGateDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    let waiting = Mutex(false)
    let open = Mutex(false)
    let sessions = Mutex<[FakeSession]>([])
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession {
        waiting.withLock { $0 = true }
        while !open.withLock({ $0 }) { await Task.yield() }
        let s = FakeSession()
        sessions.withLock { $0.append(s) }
        return s
    }
}

@MainActor
@Suite("Wykonanie w oknie i wartości okna testu (przegląd 3)")
struct ExecutionStateTests {
    func workspace(_ driver: any DatabaseDriver) throws -> (Workspace, ConnectionDefinition) {
        let ws = Workspace(drivers: [.instantClient: driver])
        let def = ConnectionDefinition(name: "dev_x", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        ws.sessions.setMainConnection(def.id)
        return (ws, def)
    }

    @Test("Wykonanie oznaczone od początku: drugie F8 w trakcie łączenia odrzucone; okno zamknięte w tym czasie — sesja zamknięta, polecenie pominięte")
    func executingBeforeConnect() async throws {
        let driver = ConnectGateDriver()
        let (ws, _) = try workspace(driver)
        let doc = ws.newDocument(.sql, text: "update emp set sal = 1")
        let run = Task { try await ws.invoke("sql.execute") }
        for _ in 0..<1000 where !driver.waiting.withLock({ $0 }) { await Task.yield() }
        #expect(doc.isExecuting && !ws.isEnabled("sql.execute"))
        await #expect(throws: CommandError.self) { _ = try await BuiltinCommands.closeDocument(doc, in: ws) }
        ws.close(doc.id)                                                       // zamknięcie z pominięciem pytań
        driver.open.withLock { $0 = true }
        await #expect(throws: CommandError.cancelledByUser) { _ = try await run.value }
        let session = try #require(driver.sessions.withLock { $0.first })
        #expect(session.closedFlag.withLock { $0 } && session.executed.withLock { !$0.contains { $0.hasPrefix("update") } })
        #expect(!doc.isExecuting && ws.sessions.openSessionCount == 0)
    }

    @Test("Wartości okna testu wracają na wejście: znacznik czasu z ułamkiem, data w formacie z Preferencji, BLOB szesnastkowo")
    func testVariableRoundTrip() throws {
        let ts = OracleTimestamp(year: 2026, month: 10, day: 26, hour: 12, minute: 30, second: 5, fsecond: 120_000_000)
        let f = ValueFormat(dateFormat: "DD.MM.YYYY HH24:MI", timestampFormat: "DD.MM.YYYY HH24:MI:SS.FF6")
        let tsText = OracleValue.timestamp(ts, .timestamp).format(f)
        let v1 = try TestRunner.value(TestVariable(name: "t", type: .timestamp, value: tsText, isNull: false), format: f)
        #expect(v1 == .timestamp(ts, .timestamp))
        let dateText = OracleValue.timestamp(ts, .date).format(f)
        guard case .timestamp(let d, .date) = try TestRunner.value(TestVariable(name: "d", type: .date, value: dateText, isNull: false), format: f) else {
            Issue.record("data"); return
        }
        #expect(d.day == 26 && d.hour == 12 && d.minute == 30)
        // Domyślny format znacznika czasu (z .FF) — drugie wykonanie przyjmuje wynik pierwszego.
        let def = OracleValue.timestamp(ts, .timestamp).format(.default)
        #expect(throws: Never.self) { try TestRunner.value(TestVariable(name: "t", type: .timestamp, value: def, isNull: false)) }
        // BLOB: wynik w całości szesnastkowo, tekst niebędący hex odrzucony.
        let blob = OracleValue.lob(LOBValue(kind: .blob, bytes: Data([0xAB, 0x01]), length: 2, truncated: false))
        let hex = TestRunner.outputText(blob, format: .default)
        #expect(hex == "AB01")
        #expect(try TestRunner.value(TestVariable(name: "b", type: .blob, value: hex, isNull: false)) == .raw(Data([0xAB, 0x01])))
        #expect(throws: CommandError.self) { try TestRunner.value(TestVariable(name: "b", type: .blob, value: "<BLOB 2 B> AB01", isNull: false)) }
    }
}
