import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Sterownik, którego sesja główna (tag akcji „główna”) traci połączenie, a pozostałe działają.
final class LostMainDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession {
        options.tags.action == "główna" ? LostSession() : FakeSession()
    }
}

@MainActor
@Suite("Sesje: sprawdzanie połączeń, bezczynne sesje, hasło tunelu (przegląd 3)")
struct SessionCheckTests {
    func workspace(_ driver: any DatabaseDriver) throws -> (Workspace, ConnectionDefinition) {
        let ws = Workspace(drivers: [.instantClient: driver])
        let def = ConnectionDefinition(name: "dev_x", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        ws.sessions.setMainConnection(def.id)
        return (ws, def)
    }

    @Test("Tryb Multi: utrata sesji głównej nie zeruje transakcji okna z własną, żywą sesją; komunikat bez tego okna")
    func lostMainKeepsWindowTransaction() async throws {
        let (ws, def) = try workspace(LostMainDriver())
        let doc = ws.newDocument(.sql)
        _ = try await ws.session(for: doc)
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        doc.transactionOpen = true
        ws.sessions.lastConnectionCheck = .distantPast
        let message = try #require(await ws.connectionCheckTick())
        #expect(doc.transactionOpen)
        #expect(message.contains("dev_x") && !message.contains(doc.title))
        #expect(ws.sessions.existingSession(try #require(ws.sessionKey(for: doc))) != nil)
    }

    @Test("Tryb Dual: utrata sesji głównej zeruje transakcję okien tej sesji i wymienia je w komunikacie")
    func lostSharedSessionClearsWindows() async throws {
        let (ws, def) = try workspace(LostDriver())
        ws.settings.sessionMode = .dual
        let doc = ws.newDocument(.sql)
        doc.connectionID = def.id
        _ = try await ws.session(for: doc)
        doc.transactionOpen = true
        ws.sessions.lastConnectionCheck = .distantPast
        let message = try #require(await ws.connectionCheckTick())
        #expect(!doc.transactionOpen && message.contains(doc.title))
    }

    @Test("Sprawdzanie połączeń: 0 wyłącza tylko ping; przebieg wg interwału; bez nakładania przebiegów")
    func checkIntervalAndOverlap() async throws {
        let (ws, def) = try workspace(LostDriver())
        let key = SessionKey(connectionID: def.id, purpose: .main)
        _ = try await ws.sessions.session(key)
        ws.settings.checkConnectionIntervalSeconds = 0
        ws.sessions.lastConnectionCheck = .distantPast
        #expect(await ws.connectionCheckTick() == nil)
        #expect(ws.sessions.existingSession(key) != nil)                      // bez pingu
        ws.settings.checkConnectionIntervalSeconds = 120                       // zmiana działa bez restartu timera
        #expect(await ws.connectionCheckTick(now: Date()) == nil)              // przed upływem interwału
        ws.sessions.connectionCheckRunning = true                              // poprzedni przebieg trwa
        #expect(await ws.connectionCheckTick(now: Date().addingTimeInterval(600)) == nil)
        ws.sessions.connectionCheckRunning = false
        #expect(await ws.connectionCheckTick(now: Date().addingTimeInterval(600)) != nil)
        #expect(ws.sessions.existingSession(key) == nil)
    }

    @Test("Bezczynne sesje: sesja okna wykonującego polecenie albo z otwartym kursorem nie jest zamykana")
    func idleSkipsBusy() async throws {
        let (ws, def) = try workspace(FakeDriver())
        let busy = SessionKey(connectionID: def.id, purpose: .document(DocumentID()))
        let idle = SessionKey(connectionID: def.id, purpose: .document(DocumentID()))
        _ = try await ws.sessions.session(busy)
        _ = try await ws.sessions.session(idle)
        let later = Date().addingTimeInterval(3600)
        #expect(await ws.sessions.closeIdleSessions(olderThan: 15, busy: [busy], now: later) == 1)
        #expect(ws.sessions.existingSession(busy) != nil && ws.sessions.existingSession(idle) == nil)
        #expect(ws.sessions.lastActivity[busy] == later)                       // odliczanie od końca wykonania
        // Okno w trakcie wykonania — zbiór zajętych sesji z dokumentów.
        let doc = ws.newDocument(.sql)
        doc.isExecuting = true
        #expect(ws.busySessionKeys == [try #require(ws.sessionKey(for: doc))])
    }

    @Test("Utracona sesja: SID, ślad i czas użycia zapomniane (zakończenie sesji nie wskaże cudzej sesji)")
    func dropLostForgetsSession() async throws {
        let (ws, def) = try workspace(FakeDriver())
        let key = SessionKey(connectionID: def.id, purpose: .document(DocumentID()))
        _ = try await ws.sessions.session(key)
        ws.sessions.sqlTraceEnabled.insert(key)
        #expect(ws.sessions.dropLost(key))
        #expect(ws.sessions.lastActivity[key] == nil && !ws.sessions.sqlTraceEnabled.contains(key) && ws.sessions.serverSessionIDs[key] == nil)
    }

    @Test("Hasło tunelu SSH z Pęku kluczy dopiero po potwierdzeniu właściciela — jedno pytanie na połączenie także z hasłem bazy")
    func tunnelSecretNeedsOwner() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: FakeDriver()])
        var def = ConnectionDefinition(name: "dev_ssh", target: ConnectionTarget(user: "u", connectString: "db:1521/s"))
        def.sshTunnel = SSHTunnel(host: "bastion", user: "ops", usesPassword: true)
        try ws.connections.upsert(def, password: "good")
        try ws.connections.setSSHPassword("tajne-ssh", for: def.id)
        let prompter = FakePrompter(answers: [])
        ws.sessions.prompter = prompter
        ws.settings.requireOwnerForSavedPasswords = true
        await #expect(throws: CommandError.cancelledByUser) { _ = try await ws.sessions.tunnelSecret(for: def) }
        #expect(prompter.ownerAsked == 1)
        prompter.ownerAnswers = [true]
        #expect(try await ws.sessions.tunnelSecret(for: def) == "tajne-ssh")
        #expect(try await ws.sessions.tunnelSecret(for: def) == "tajne-ssh")
        #expect(prompter.ownerAsked == 2)
        ws.settings.requireOwnerForSavedPasswords = false
        var keyBased = def
        keyBased.sshTunnel?.usesPassword = false
        #expect(try await ws.sessions.tunnelSecret(for: keyBased) == nil)            // tunel na klucz — bez hasła
    }

}

@MainActor
@Suite("Tunel SSH — wstrzyknięcie opcji i licznik użytkowników")
struct SSHTunnelSafetyTests {
    @Test("Host, użytkownik i ProxyJump zaczynające się od „-” albo ze spacją odrzucone; cel ssh po „--”")
    func optionInjection() throws {
        for t in [SSHTunnel(host: "-oProxyCommand=sh -c x", user: ""), SSHTunnel(host: "bastion", user: "-oProxyCommand=x"),
                  SSHTunnel(host: "bastion", user: "ops", jumpHost: "j1,-oProxyCommand=x"), SSHTunnel(host: "bast ion", user: "ops")] {
            #expect(throws: CommandError.self) { try t.validate() }
        }
        try SSHTunnel(host: "bastion.example", port: 22, user: "ops", jumpHost: "jump@j1.example:2222,j2").validate()
        let a = SSHTunnelManager.arguments(SSHTunnel(host: "bastion", user: "ops"), localPort: 41000, remote: .init(host: "db", port: 1521), extra: [])
        #expect(Array(a.suffix(2)) == ["--", "ops@bastion"])
        let store = ConnectionStore(fileURL: nil, secrets: MemorySecretStore())
        var def = ConnectionDefinition(name: "x", target: ConnectionTarget(user: "u", connectString: "db:1521/s"))
        def.sshTunnel = SSHTunnel(host: "-oProxyCommand=x", user: "")
        #expect(throws: CommandError.self) { try store.upsert(def) }
    }

    @Test("Import: tunel z opcją ssh odrzuca plik; definicje z tunelem lub skryptem inicjalizacji wskazane do ostrzeżenia")
    func importChecks() throws {
        let source = ConnectionStore(fileURL: nil, secrets: MemorySecretStore())
        var tunnel = ConnectionDefinition(name: "z_tunelem", target: ConnectionTarget(user: "u", connectString: "db:1521/s"))
        tunnel.sshTunnel = SSHTunnel(host: "bastion", user: "ops")
        try source.upsert(tunnel)
        try source.upsert(ConnectionDefinition(name: "skrypt", target: ConnectionTarget(user: "u", connectString: "db"), initScript: "begin null; end;"))
        try source.upsert(ConnectionDefinition(name: "zwykle", target: ConnectionTarget(user: "u", connectString: "db")))
        let data = try source.exportDefinitions()
        #expect(Set(try ConnectionStore.definitionsRunningCode(in: data)) == ["z_tunelem", "skrypt"])
        let bad = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"bastion\"", with: "\"-oProxyCommand=x\"")
        let target = ConnectionStore(fileURL: nil, secrets: MemorySecretStore())
        #expect(throws: CommandError.self) { _ = try target.importDefinitions(Data(bad.utf8)) }
        #expect(target.connections.isEmpty)
    }

    @Test("Zwolnienie tunelu z poprzedniego przebiegu ssh nie zamyka nowego tunelu")
    func staleReleaseKeepsNewTunnel() throws {
        let manager = SSHTunnelManager()
        let id = UUID()
        func process() throws -> Process {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sleep")
            p.arguments = ["30"]
            try p.run()
            return p
        }
        let oldProcess = try process()
        let old = SSHTunnelManager.Tunnel(localPort: 40001, remote: .init(host: "db", port: 1521))
        manager.running[id] = .init(process: oldProcess, tunnel: old)
        oldProcess.terminate()                                                  // ssh padł (uśpienie, sieć)
        oldProcess.waitUntilExit()
        let newProcess = try process()
        defer { newProcess.terminate() }
        let new = SSHTunnelManager.Tunnel(localPort: 40002, remote: .init(host: "db", port: 1521))
        manager.running[id] = .init(process: newProcess, tunnel: new)          // nowy tunel dla nowych sesji
        manager.release(old, of: id)                                            // stara sesja zamknięta
        #expect(manager.isOpen(id))
        manager.release(new, of: id)
        #expect(!manager.isOpen(id))
    }
}
