import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Atrapa sesji: rejestruje wykonane polecenia.
final class FakeSession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    let executed = Mutex<[String]>([])
    let closedFlag = Mutex(false)
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        executed.withLock { $0.append(sql) }
        return ExecutionResult(kind: .other)
    }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch { RowBatch(rows: [], hasMore: false) }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async { closedFlag.withLock { $0 = true } }
}

/// Atrapa sterownika: akceptuje hasło `good`, `expired` wymaga zmiany (ORA-28001), resztę odrzuca (ORA-01017).
final class FakeDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    let attempts = Mutex<[Credentials]>([])
    let sessions = Mutex<[FakeSession]>([])
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession {
        attempts.withLock { $0.append(credentials) }
        if credentials.password == "expired" && credentials.newPassword == nil {
            throw OracleError(code: 28001, message: "ORA-28001: the password has expired")
        }
        guard credentials.password == "good" || credentials.newPassword != nil else {
            throw OracleError(code: 1017, message: "ORA-01017: invalid username/password; logon denied")
        }
        let s = FakeSession()
        sessions.withLock { $0.append(s) }
        return s
    }
}

@MainActor
final class FakePrompter: ConnectionPrompter {
    var answers: [(String, Bool)?]
    var newPassword: String?
    var asked = 0
    init(answers: [(String, Bool)?], newPassword: String? = nil) {
        self.answers = answers
        self.newPassword = newPassword
    }
    func askPassword(for connection: ConnectionDefinition, reason: String?) async -> (password: String, remember: Bool)? {
        asked += 1
        guard !answers.isEmpty, let a = answers.removeFirst() else { return nil }
        return (a.0, a.1)
    }
    func askNewPassword(for connection: ConnectionDefinition, message: String) async -> String? { newPassword }
}

@MainActor
@Suite("Menedżer sesji")
struct SessionManagerTests {
    func make(_ secrets: MemorySecretStore = MemorySecretStore()) -> (Workspace, FakeDriver) {
        let driver = FakeDriver()
        return (Workspace(secrets: secrets, drivers: [.instantClient: driver]), driver)
    }

    @Test("Tryb multi: sesja na okno; dual: wspólna sesja; kompilacja osobno")
    func sessionModes() throws {
        let (ws, _) = make()
        let c = UUID()
        let d1 = DocumentID(), d2 = DocumentID()
        #expect(ws.sessions.key(forDocument: d1, connection: c) != ws.sessions.key(forDocument: d2, connection: c))
        ws.settings.sessionMode = .dual
        #expect(ws.sessions.key(forDocument: d1, connection: c) == ws.sessions.key(forDocument: d2, connection: c))
        #expect(ws.sessions.compileKey(connection: c).purpose == .compile)
        ws.settings.sessionMode = .single
        #expect(ws.sessions.compileKey(connection: c).purpose == .main)
    }

    @Test("Zapisane hasło: łączy bez pytania; skrypt inicjalizacji i bieżący schemat wykonane")
    func savedPassword() async throws {
        let (ws, driver) = make()
        let def = ConnectionDefinition(target: ConnectionTarget(user: "u", connectString: "db"), initScript: "alter session set nls_language = 'POLISH';\nbegin null; end;\n/", currentSchema: "HR")
        try ws.connections.upsert(def, password: "good")
        let prompter = FakePrompter(answers: [])
        ws.sessions.prompter = prompter
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main)) as! FakeSession
        #expect(prompter.asked == 0)
        #expect(s.executed.withLock { $0 } == ["ALTER SESSION SET CURRENT_SCHEMA = HR", "alter session set nls_language = 'POLISH'", "begin null; end;"])
        #expect(driver.attempts.withLock { $0.count } == 1)
        #expect(ws.sessions.status(of: def.id) == .connected(sessions: 1))
    }

    @Test("Hasło zapamiętane dopiero po udanym połączeniu i tylko na życzenie; błędne hasło — ponowne pytanie")
    func passwordPrompt() async throws {
        let secrets = MemorySecretStore()
        let (ws, driver) = make(secrets)
        let def = ConnectionDefinition(target: ConnectionTarget(user: "u", connectString: "db"), savePassword: false)
        try ws.connections.upsert(def)
        let prompter = FakePrompter(answers: [("bad", true), ("good", false)])
        ws.sessions.prompter = prompter
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(prompter.asked == 2)
        #expect(driver.attempts.withLock { $0.map(\.password) } == ["bad", "good"])
        #expect(try secrets.password(for: def.id.uuidString) == nil)   // „good” bez „Zapamiętaj”
    }

    @Test("Hasło podane raz wystarcza dla kolejnych sesji połączenia (tylko w pamięci); po rozłączeniu — pytanie ponownie")
    func passwordReusedInRun() async throws {
        let secrets = MemorySecretStore()
        let (ws, _) = make(secrets)
        let def = ConnectionDefinition(target: ConnectionTarget(user: "u", connectString: "db"), savePassword: false)
        try ws.connections.upsert(def)
        let prompter = FakePrompter(answers: [("good", false), ("good", false)])
        ws.sessions.prompter = prompter
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .document(DocumentID())))
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .compile))
        #expect(prompter.asked == 1)
        #expect(ws.sessions.status(of: def.id) == .connected(sessions: 3))
        #expect(try secrets.password(for: def.id.uuidString) == nil)
        await ws.sessions.disconnect(def.id)
        #expect(ws.sessions.status(of: def.id) == .passwordUnknown)
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(prompter.asked == 2)
    }

    @Test("Anulowanie pytania o hasło przerywa łączenie")
    func cancel() async throws {
        let (ws, _) = make()
        let def = ConnectionDefinition(target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def)
        let prompter = FakePrompter(answers: [nil])
        ws.sessions.prompter = prompter
        defer { withExtendedLifetime(prompter) {} }
        await #expect(throws: CommandError.cancelledByUser) {
            _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        }
    }

    @Test("Wygasłe hasło (ORA-28001): pytanie o nowe, zapis nowego zamiast starego")
    func expiredPassword() async throws {
        let secrets = MemorySecretStore()
        let (ws, driver) = make(secrets)
        let def = ConnectionDefinition(target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "expired")
        let prompter = FakePrompter(answers: [], newPassword: "Nowe-Haslo-1")
        ws.sessions.prompter = prompter
        defer { withExtendedLifetime(prompter) {} }
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(driver.attempts.withLock { $0.last?.newPassword } == "Nowe-Haslo-1")
        #expect(try secrets.password(for: def.id.uuidString) == "Nowe-Haslo-1")
    }

    @Test("Rozłączenie zamyka wszystkie sesje połączenia")
    func disconnect() async throws {
        let (ws, driver) = make()
        let def = ConnectionDefinition(target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .compile))
        await ws.sessions.disconnect(def.id)
        #expect(driver.sessions.withLock { $0.allSatisfy { $0.closedFlag.withLock { $0 } } })
        #expect(ws.sessions.status(of: def.id) == .passwordKnown)
    }

    @Test("Bieżący schemat: tylko bezpieczny identyfikator (bez wstrzyknięcia SQL)")
    func safeIdentifier() {
        #expect(SessionManager.isSafeIdentifier("HR"))
        #expect(SessionManager.isSafeIdentifier("\"Mixed Case\""))
        #expect(!SessionManager.isSafeIdentifier("HR; DROP TABLE X"))
    }

    @Test("Ustawienia zapisywane i odczytywane z katalogu danych")
    func settingsPersistence() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        ws.settings.sessionMode = .dual
        ws.settings.shortcutProfile = .macOS
        let again = Workspace(dataDirectory: dir)
        #expect(again.settings.sessionMode == .dual)
        #expect(again.shortcutProfile == .macOS)
    }
}

@MainActor
@Suite("Strażnik zmian i połączenie okna")
struct ModificationGuardTests {
    func make() throws -> (Workspace, ConnectionDefinition, ConnectionDefinition, FakeUI) {
        let ws = Workspace(drivers: [.instantClient: FakeDriver()])
        let ui = FakeUI()
        ws.ui = ui
        let ro = ConnectionDefinition(name: "raport", target: ConnectionTarget(user: "u", connectString: "db"), readOnly: true)
        let prod = ConnectionDefinition(name: "prod", target: ConnectionTarget(user: "u", connectString: "db"), environment: .production)
        try ws.connections.upsert(ro, password: "good")
        try ws.connections.upsert(prod, password: "good")
        return (ws, ro, prod, ui)
    }

    @Test("Tylko do odczytu: zapytania tak; DML, DDL, PL/SQL i FOR UPDATE — zablokowane")
    func readOnly() throws {
        let (ws, ro, _, _) = try make()
        #expect(ws.modificationCheck(["select * from emp", "alter session set nls_language = 'POLISH'"], connectionID: ro.id) == .allowed)
        for s in ["update emp set sal = 1", "drop table t", "begin p; end;", "select * from emp for update"] {
            if case .blocked = ws.modificationCheck([s], connectionID: ro.id) {} else { Issue.record("niezablokowane: \(s)") }
        }
    }

    @Test("Produkcja: polecenia zmieniające wymagają potwierdzenia; anulowanie przerywa; preferencja wyłącza")
    func production() async throws {
        let (ws, _, prod, ui) = try make()
        #expect(ws.modificationCheck(["select 1 from dual"], connectionID: prod.id) == .allowed)
        #expect(ws.modificationCheck(["delete from emp"], connectionID: prod.id) == .needsConfirmation)
        ui.answers = [1]
        await #expect(throws: CommandError.cancelledByUser) { try await ws.guardModification(["delete from emp"], connectionID: prod.id) }
        ui.answers = [0]
        try await ws.guardModification(["delete from emp"], connectionID: prod.id)
        ws.settings.confirmProductionChanges = false
        #expect(ws.modificationCheck(["delete from emp"], connectionID: prod.id) == .allowed)
    }

    @Test("SQL Window na połączeniu tylko do odczytu odrzuca UPDATE przed wysłaniem do bazy")
    func sqlWindowBlocked() async throws {
        let (ws, ro, _, _) = try make()
        let doc = ws.newDocument(.sql)
        doc.connectionID = ro.id
        doc.text = "update emp set sal = 1"
        await #expect(throws: CommandError.self) { try await ws.invoke("sql.execute") }
    }

    @Test("Zmiana połączenia okna po nazwie; puste — połączenie główne; nieznane — błąd")
    func windowConnection() async throws {
        let (ws, ro, prod, _) = try make()
        ws.sessions.setMainConnection(prod.id)
        let doc = ws.newDocument(.sql)
        try await ws.invoke("session.windowConnection", CommandArguments(["connection": .string("raport")]))
        #expect(doc.connectionID == ro.id && ws.effectiveConnection(of: doc) == ro.id)
        try await ws.invoke("session.windowConnection", CommandArguments(["connection": .string("")]))
        #expect(doc.connectionID == nil && ws.effectiveConnection(of: doc) == prod.id)
        await #expect(throws: CommandError.self) {
            try await ws.invoke("session.windowConnection", CommandArguments(["connection": .string("brak")]))
        }
    }
}

/// Sterownik bez biblioteki klienta.
final class MissingClientDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .failure(.clientMissing("Brak Instant Client")) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession {
        throw DatabaseError.clientMissing("Brak Instant Client")
    }
}

@MainActor
@Suite("Brak Instant Client")
struct ClientMissingTests {
    @Test("Połączenie bez biblioteki klienta otwiera ekran pomocy zamiast zwykłego błędu")
    func help() async throws {
        let ws = Workspace(drivers: [.instantClient: MissingClientDriver()])
        let ui = FakeUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "x", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "p")
        ws.perform("connection.connectAsMain", CommandArguments(["connection": .string(def.id.uuidString)]))
        for _ in 0..<200 where ui.clientHelp == nil { await Task.yield() }
        #expect(ui.clientHelp == "Brak Instant Client")
    }
}
