import Foundation
import PelikanDB
import PelikanLog
@testable import PelikanWorkspace
import Testing

/// Losowe wartości atrapy (przyjmowana, odrzucana, w treści polecenia) — za każdym uruchomieniem inne.
private enum Fixture {
    static let values = (0..<3).map { _ in UUID().uuidString }
    static var accepted: String { values[0] }
    static var rejected: String { values[1] }
    static var inStatement: String { values[2] }
}

/// Atrapa sterownika: przyjmuje tylko `Fixture.accepted`, inne hasła odrzuca jak Oracle (ORA-01017).
private final class LogLeakDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession {
        guard credentials.password == Fixture.accepted else {
            throw OracleError(code: 1017, message: "ORA-01017: invalid username/password; logon denied")
        }
        return FakeSession()
    }
}

/// Dziennik aplikacji (PL-INFRA-011, D170): co trafia do wpisów, a czego nie ma w nich nigdy.
@MainActor
@Suite("Dziennik aplikacji")
struct AppLogTests {
    let secrets = [Fixture.accepted, Fixture.rejected, Fixture.inStatement, "tajna_wartosc", "identified by"]

    func connected(_ prompter: FakePrompter) async throws -> (Workspace, ConnectionDefinition) {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: LogLeakDriver()])
        let def = ConnectionDefinition(name: "dev_log_kadry", target: ConnectionTarget(user: "kadry", connectString: "kadry-db.example:1521/KADRY"),
                                       savePassword: false)
        try ws.connections.upsert(def)
        ws.sessions.prompter = prompter
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        return (ws, def)
    }

    @Test("łączenie z błędnym hasłem, SQL i rozłączenie: zdarzenia są, haseł, treści SQL i wartości nie ma — nawet z jawnymi nazwami")
    func noSecretsEvenWithNames() async throws {
        let sink = MemoryLogSink(everything: true)
        let id = Log.addSink(sink)
        defer { Log.removeSink(id) }
        let prompter = FakePrompter(answers: [(Fixture.rejected, false), (Fixture.accepted, true)])
        let (ws, def) = try await connected(prompter)
        ws.settings.autoSelectStatement = false
        let doc = ws.newDocument(.sql, text: "alter user kadry identified by \"\(Fixture.inStatement)\";\nselect 'tajna_wartosc' from dual;")
        doc.connectionID = def.id
        _ = try await SQLExecutor.execute(doc, scope: .standard, in: ws)
        await ws.sessions.disconnect(def.id)

        let text = sink.text
        for s in secrets { #expect(!text.localizedCaseInsensitiveContains(s), "w dzienniku: \(s)") }
        #expect(!text.contains("kadry-db.example"))
        #expect(text.contains("Odmowa logowania (ORA-01017) — ponowne pytanie o hasło"))
        #expect(text.contains("Połączono dev_log_kadry w "))
        #expect(text.contains(" (sterownik instantClient, klient 0, serwer 23.0.0.0.0, sesja główna)"))
        #expect(text.contains("Okno SQL: poleceń 2, czas "))
        #expect(text.contains("Rozłączono dev_log_kadry"))
    }

    @Test("domyślnie nazwa połączenia jako skrót, błąd Oracle jako sam kod")
    func defaultVisibility() async throws {
        let sink = MemoryLogSink()
        let id = Log.addSink(sink)
        defer { Log.removeSink(id) }
        #expect(Log.level == .info)
        let prompter = FakePrompter(answers: [(Fixture.rejected, false), (Fixture.accepted, true)])
        _ = try await connected(prompter)
        let mine = sink.all.filter { $0.category == "connection" }.map(\.text)
        #expect(mine.contains { $0.hasPrefix("Połączono <#") && $0.hasSuffix("(sterownik instantClient, klient 0, serwer 23.0.0.0.0, sesja główna)") })
        #expect(!sink.text.contains("dev_log_kadry"))
        for s in secrets { #expect(!sink.text.contains(s)) }
    }

    @Test("komenda zakończona błędem: identyfikator i rodzaj błędu w dzienniku")
    func commandFailure() async throws {
        let sink = MemoryLogSink(everything: true)
        let id = Log.addSink(sink)
        defer { Log.removeSink(id) }
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        await #expect(throws: (any Error).self) { try await ws.invoke("help.context") }
        #expect(sink.all.contains { $0.level == .notice && $0.text.hasPrefix("Komenda help.context nie powiodła się po ") && $0.text.contains("CommandError.notAvailable") })
    }

    @Test("eksport: opis środowiska bez nazw połączeń i adresów")
    func export() throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: LogLeakDriver()])
        try ws.connections.upsert(ConnectionDefinition(name: "dev_log_kadry", target: ConnectionTarget(user: "kadry", connectString: "kadry-db.example:1521/KADRY")))
        let text = ws.logExport()
        #expect(text.hasPrefix("Pelikan — dziennik aplikacji (eksport "))
        #expect(text.contains("Połączenia: 1, tryb sesji: multi"))
        #expect(text.contains("Sterowniki: instantClient: dostępny, thin: brak"))
        #expect(!text.contains("kadry"))
    }

    @Test("komendy dziennika: tylko dla użytkownika, nie dla agenta")
    func commands() throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        for id in ["help.log", "help.exportLog"] as [CommandID] {
            let d = try #require(ws.registry.command(id)?.descriptor)
            #expect(d.agentAccess == .none)
            #expect(d.feature == "PL-INFRA-011")
        }
    }
}
