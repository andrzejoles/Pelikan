import Foundation
import Observation
import PelikanDB
import PelikanSQL

/// Do czego służy sesja (UG 20: osobne sesje okien, kompilacji; agent — własna sesja, PROMPT §7.3 p.2).
public enum SessionPurpose: Hashable, Sendable {
    /// Sesja połączenia głównego (Object Browser, metadane, okna w trybie dual/single).
    case main
    /// Sesja okna (tryb multi).
    case document(DocumentID)
    /// Sesja kompilacji (DDL robi COMMIT — nie może dzielić transakcji z oknami).
    case compile
    /// Sesja agenta AI.
    case agent(String)
    /// Sesja nadzorująca debugera okna (DBMS_DEBUG wymaga drugiej sesji — ADR 0006).
    case debugger(DocumentID)
    /// Sesje utPLSQL: produkująca (`run`) i konsumująca zdarzenia reportera (`events`).
    case utplsql(String)
}

public struct SessionKey: Hashable, Sendable {
    public var connectionID: UUID
    public var purpose: SessionPurpose
}

/// Stan połączenia na liście (ikona klucza wzorca, UG 19.1).
public enum ConnectionStatus: Sendable, Equatable {
    case passwordUnknown
    case passwordKnown
    case connected(sessions: Int)
}

/// Pytania, które menedżer sesji zadaje użytkownikowi (implementuje interfejs; w testach — atrapa).
@MainActor
public protocol ConnectionPrompter: AnyObject {
    /// Hasło dla połączenia (nil = anulowano). `remember` — czy zapisać w Pęku kluczy.
    func askPassword(for connection: ConnectionDefinition, reason: String?) async -> (password: String, remember: Bool)?
    /// Nowe hasło po ORA-28001 (nil = anulowano).
    func askNewPassword(for connection: ConnectionDefinition, message: String) async -> String?
}

/// Sesje bazy wszystkich połączeń (UG 20). Jedno miejsce, które łączy się z bazą: okna, Object Browser, kompilacja i
/// agent proszą o sesję dla celu, a menedżer zwraca istniejącą albo zestawia nową wg trybu sesji.
@MainActor
@Observable
public final class SessionManager {
    public private(set) var mainConnectionID: UUID?
    private var sessions: [SessionKey: any DatabaseSession] = [:]
    @ObservationIgnored private var connecting: [SessionKey: Task<any DatabaseSession, any Error>] = [:]
    @ObservationIgnored private let store: ConnectionStore
    @ObservationIgnored private var drivers: [DriverKind: any DatabaseDriver]
    @ObservationIgnored public weak var prompter: (any ConnectionPrompter)?
    @ObservationIgnored public var settings: () -> Settings
    /// Hasła podane w tym uruchomieniu (tylko w pamięci): kolejne sesje tego połączenia (okna w trybie Multi, sesja
    /// kompilacji) nie pytają ponownie. Zapominane przy rozłączeniu połączenia i po ORA-01017.
    @ObservationIgnored private var sessionPasswords: [UUID: String] = [:]
    /// Tunele SSH połączeń (współdzielone przez sesje połączenia).
    @ObservationIgnored public let tunnels = SSHTunnelManager()

    public init(store: ConnectionStore, drivers: [DriverKind: any DatabaseDriver], settings: @escaping () -> Settings) {
        self.store = store
        self.drivers = drivers
        self.settings = settings
    }

    public func setDriver(_ driver: any DatabaseDriver) { drivers[driver.kind] = driver }

    public func driver(for kind: DriverKind) -> (any DatabaseDriver)? { drivers[kind] }

    // MARK: Połączenie główne

    public func setMainConnection(_ id: UUID?) {
        mainConnectionID = id
        if let id { store.markUsed(id) }
    }

    // MARK: Klucze sesji wg trybu

    /// Klucz sesji dla okna wg trybu sesji: multi → sesja okna, dual/single → sesja główna połączenia.
    public func key(forDocument doc: DocumentID, connection: UUID) -> SessionKey {
        switch settings().sessionMode {
        case .multi: SessionKey(connectionID: connection, purpose: .document(doc))
        case .dual, .single: SessionKey(connectionID: connection, purpose: .main)
        }
    }

    /// Klucz sesji kompilacji: w trybie single — sesja główna.
    /// Sesja nadzorująca debugera — zawsze osobna, także w trybie jednej sesji.
    public func debuggerKey(document: DocumentID, connection: UUID) -> SessionKey {
        SessionKey(connectionID: connection, purpose: .debugger(document))
    }

    public func compileKey(connection: UUID) -> SessionKey {
        settings().sessionMode == .single ? SessionKey(connectionID: connection, purpose: .main)
            : SessionKey(connectionID: connection, purpose: .compile)
    }

    // MARK: Sesje

    public func existingSession(_ key: SessionKey) -> (any DatabaseSession)? { sessions[key] }

    /// Klucze otwartych sesji o danym przeznaczeniu (np. wszystkie sesje jednej sesji agenta).
    public func keys(purpose: SessionPurpose) -> [SessionKey] { sessions.keys.filter { $0.purpose == purpose } }

    /// Bieżący schemat dowolnej otwartej sesji połączenia (bez łączenia) — nil, gdy brak sesji.
    public func connectedSchema(_ connection: UUID?) -> String? {
        guard let connection else { return nil }
        return sessions.first { $0.key.connectionID == connection }?.value.info.currentSchema
    }

    /// Sesja dla klucza: istniejąca albo nowa (pyta o hasło, obsługuje wygasłe hasło, wykonuje skrypt inicjalizacji).
    public func session(_ key: SessionKey) async throws -> any DatabaseSession {
        if let s = sessions[key] { return s }
        if let pending = connecting[key] { return try await pending.value }
        let task = Task { @MainActor in try await self.open(key) }
        connecting[key] = task
        defer { connecting[key] = nil }
        let s = try await task.value
        sessions[key] = s
        store.markUsed(key.connectionID)
        return s
    }

    private func open(_ key: SessionKey) async throws -> any DatabaseSession {
        guard let def = store.connection(key.connectionID) else { throw CommandError.notConnected }
        guard let driver = drivers[def.driver] else {
            throw DatabaseError.driverUnavailable(L10n.tr("Sterownik \(def.driver.rawValue) jest niedostępny"))
        }
        if case .failure(let e) = driver.availability() { throw e }
        var password = store.password(for: def.id) ?? sessionPasswords[def.id]
        // Hasło zapisujemy dopiero po udanym połączeniu i tylko gdy użytkownik zaznaczył „Zapamiętaj”.
        var rememberOnSuccess = false
        if password == nil, !def.target.externalAuth {
            guard let answer = await prompter?.askPassword(for: def, reason: nil) else { throw CommandError.cancelledByUser }
            password = answer.password
            rememberOnSuccess = answer.remember
        }
        var tags = SessionTags(module: key.moduleName, action: key.actionName)
        var credentials = Credentials(password: password)
        // Tunel SSH: łączymy się przez 127.0.0.1:port lokalny (alias TNS rozwijany do deskryptora).
        var target = def.target
        // Sesja agenta: CLIENT_INFO z identyfikatorem sesji agenta, a gdy wskazano użytkownika bazy agenta — połączenie
        // proxy `główny[agent]` (agent działa z uprawnieniami tylko tego użytkownika, bez osobnego hasła; PROMPT §7.3 p.4).
        if case .agent(let id) = key.purpose {
            tags.clientInfo = "Pelikan agent \(id)"
            if let u = def.agent.agentUser?.trimmingCharacters(in: .whitespaces), !u.isEmpty { target.proxyClient = u }
        }
        var tunnelOpened = false
        if def.sshTunnel != nil {
            let tns = TNSNames.load(directories: TNSNames.searchDirectories(configured: def.target.configDirectory))
            let tunnel = try await tunnels.open(for: def, tns: tns)
            tunnelOpened = true
            guard let rewritten = ConnectStringRewriter.rewrite(def.target.connectString, localPort: tunnel.localPort, tns: tns) else {
                tunnels.release(def.id)
                throw DatabaseError.driverUnavailable(L10n.tr("Nie można przepisać connect stringu dla tunelu SSH"))
            }
            target.connectString = rewritten
        }
        var connected = false
        defer { if tunnelOpened, !connected { tunnels.release(def.id) } }
        for attempt in 0..<3 {
            do {
                let s = try await driver.connect(target: target, credentials: credentials, options: ConnectOptions(tags: tags))
                connected = true
                if let np = credentials.newPassword {
                    // Wygasłe hasło zmienione — nowe zastępuje stare, jeśli stare było zapisane albo użytkownik chciał.
                    if def.savePassword || rememberOnSuccess { try? store.rememberPassword(np, for: def.id) }
                } else if rememberOnSuccess, let p = password {
                    try? store.rememberPassword(p, for: def.id)
                }
                if let p = credentials.newPassword ?? password { sessionPasswords[def.id] = p }
                try await initialize(s, def)
                return s
            } catch let e as OracleError where e.isPasswordExpired && attempt < 2 {
                guard let np = await prompter?.askNewPassword(for: def, message: e.message) else { throw CommandError.cancelledByUser }
                credentials = Credentials(password: password, newPassword: np)
            } catch let e as OracleError where e.code == 1017 && attempt < 2 && !def.target.externalAuth {
                // ORA-01017: błędne hasło — pytamy ponownie (zapisane hasło jest nieaktualne).
                sessionPasswords[def.id] = nil
                guard let answer = await prompter?.askPassword(for: def, reason: e.message) else { throw CommandError.cancelledByUser }
                password = answer.password
                rememberOnSuccess = answer.remember
                credentials = Credentials(password: password)
            }
        }
        throw CommandError.notConnected
    }

    /// Po połączeniu: Workspace Manager, bieżący schemat, skrypt inicjalizacji połączenia (UG 19.2).
    private func initialize(_ s: any DatabaseSession, _ def: ConnectionDefinition) async throws {
        if let ws = def.workspaceManager, !ws.isEmpty {
            _ = try await s.execute("BEGIN DBMS_WM.GotoWorkspace(:ws); END;", binds: [BindVariable(name: "ws", value: .text(ws))])
        }
        if let schema = def.currentSchema, !schema.isEmpty, Self.isSafeIdentifier(schema) {
            _ = try await s.execute("ALTER SESSION SET CURRENT_SCHEMA = \(schema)")
        }
        if !def.initScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for stmt in ScriptSplitter.split(def.initScript) where stmt.sqlplusCommand == nil {
                _ = try await s.execute(stmt.text)
            }
        }
    }

    static func isSafeIdentifier(_ s: String) -> Bool {
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count > 2, !s.dropFirst().dropLast().contains("\"") { return true }
        return s.range(of: #"^[A-Za-z][A-Za-z0-9_$#]{0,127}$"#, options: .regularExpression) != nil
    }

    /// Zamyka sesję (bez pytania — decyzję o transakcji podejmuje wywołujący).
    public func close(_ key: SessionKey) async {
        guard let s = sessions.removeValue(forKey: key) else { return }
        await s.close()
        if store.connection(key.connectionID)?.sshTunnel != nil { tunnels.release(key.connectionID) }
    }

    /// Rozłącza wszystkie sesje połączenia (UG 19.1 Disconnect).
    public func disconnect(_ connectionID: UUID) async {
        for key in sessions.keys where key.connectionID == connectionID {
            await close(key)
        }
        sessionPasswords[connectionID] = nil
    }

    public func disconnectAll() async {
        for key in Array(sessions.keys) { await close(key) }
        sessionPasswords.removeAll()
    }

    /// Stan połączenia na liście.
    public func status(of connectionID: UUID) -> ConnectionStatus {
        let n = sessions.keys.filter { $0.connectionID == connectionID }.count
        if n > 0 { return .connected(sessions: n) }
        return store.password(for: connectionID) != nil || sessionPasswords[connectionID] != nil || store.connection(connectionID)?.target.externalAuth == true
            ? .passwordKnown : .passwordUnknown
    }

    public var openSessionCount: Int { sessions.count }

    /// Usuwa sesje z utraconym połączeniem (zwraca klucze, żeby interfejs mógł poinformować o utraconej transakcji).
    @discardableResult
    public func dropLost(_ key: SessionKey) -> Bool {
        guard sessions.removeValue(forKey: key) != nil else { return false }
        if store.connection(key.connectionID)?.sshTunnel != nil { tunnels.release(key.connectionID) }
        return true
    }

    /// Sprawdzenie połączeń (UG 23.1 Check connection): ping sesji głównych; utracone usuwane.
    public func checkConnections() async -> [SessionKey] {
        var lost: [SessionKey] = []
        for (key, s) in sessions where key.purpose == .main {
            do { try await s.ping() } catch let e as OracleError where e.isConnectionLost {
                lost.append(key)
            } catch {}
        }
        for k in lost { _ = dropLost(k) }
        return lost
    }
}

extension SessionKey {
    var moduleName: String {
        switch purpose {
        case .agent: "Pelikan agent"
        default: "Pelikan"
        }
    }

    var actionName: String {
        switch purpose {
        case .main: "główna"
        case .document: "okno"
        case .compile: "kompilacja"
        case .agent(let id): "agent \(id)"
        case .debugger: "debuger"
        case .utplsql(let r): "utPLSQL \(r)"
        }
    }
}
