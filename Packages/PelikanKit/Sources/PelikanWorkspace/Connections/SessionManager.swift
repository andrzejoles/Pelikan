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
    /// Sesje narzędzi bez transakcji użytkownika (np. `plan` — Explain Plan wstawia wiersze do PLAN_TABLE).
    case tool(String)
}

public struct SessionKey: Hashable, Sendable {
    public var connectionID: UUID
    public var purpose: SessionPurpose

    public init(connectionID: UUID, purpose: SessionPurpose) {
        self.connectionID = connectionID
        self.purpose = purpose
    }
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
    func authenticateOwner(reason: String) async -> Bool
    /// Nowe hasło przy zmianie z menu (PD-CONN-017; nil = anulowano).
    func askPasswordChange(for connection: ConnectionDefinition) async -> String?
}

extension ConnectionPrompter {
    public func askPasswordChange(for connection: ConnectionDefinition) async -> String? {
        await askNewPassword(for: connection, message: L10n.tr("Zmiana hasła użytkownika \(connection.target.user)."))
    }

    /// Potwierdzenie właściciela Maca (Touch ID albo hasło) przed użyciem zapisanego hasła (D56). Domyślnie odmowa —
    /// prompter bez tej funkcji nie odblokuje zapisanych haseł, gdy ochrona jest włączona.
    public func authenticateOwner(reason: String) async -> Bool { false }
}

/// Sesje bazy wszystkich połączeń (UG 20). Jedno miejsce, które łączy się z bazą: okna, Object Browser, kompilacja i
/// agent proszą o sesję dla celu, a menedżer zwraca istniejącą albo zestawia nową wg trybu sesji.
@MainActor
@Observable
public final class SessionManager {
    public private(set) var mainConnectionID: UUID?
    private var sessions: [SessionKey: any DatabaseSession] = [:]
    /// SID i numer instancji sesji (SYS_CONTEXT przy otwarciu) — do zakończenia sesji okna z innej sesji (PD-CONN-027).
    public private(set) var serverSessionIDs: [SessionKey: (sid: String, instance: String)] = [:]
    /// Sesje okien z włączonym SQL Trace (PD-OPT-008).
    public var sqlTraceEnabled: Set<SessionKey> = []
    /// Ostatnie użycie sesji (zamykanie bezczynnych, PD-CONN-026).
    public private(set) var lastActivity: [SessionKey: Date] = [:]

    /// Parametry NLS sesji, które Pelikan pozwala ustawić (wartość w cudzysłowie, bez apostrofów).
    public static let nlsParameters = ["NLS_LANGUAGE", "NLS_TERRITORY", "NLS_DATE_FORMAT", "NLS_DATE_LANGUAGE", "NLS_TIMESTAMP_FORMAT",
                                       "NLS_TIMESTAMP_TZ_FORMAT", "NLS_NUMERIC_CHARACTERS", "NLS_CURRENCY", "NLS_ISO_CURRENCY",
                                       "NLS_SORT", "NLS_COMP", "NLS_LENGTH_SEMANTICS", "TIME_ZONE"]

    /// Polecenie ALTER SESSION dla parametrów NLS z ustawień (nieznane nazwy i wartości z apostrofem — pomijane).
    public static func nlsStatement(_ values: [String: String]) -> String? {
        let parts = values.sorted { $0.key < $1.key }.compactMap { k, v -> String? in
            // Wartość bez przycinania: spacja bywa znacząca (NLS_NUMERIC_CHARACTERS = ', ').
            let name = k.uppercased(), value = v
            guard nlsParameters.contains(name), !value.trimmingCharacters(in: .whitespaces).isEmpty, !value.contains("'") else { return nil }
            return "\(name) = '\(value)'"
        }
        return parts.isEmpty ? nil : "ALTER SESSION SET " + parts.joined(separator: " ")
    }

    /// Notuje użycie sesji (wykonanie polecenia w oknie).
    public func touch(_ key: SessionKey, at date: Date = Date()) { lastActivity[key] = date }

    /// Zamyka sesje okien bezczynne dłużej niż `minutes` minut, bez otwartej transakcji; zwraca liczbę zamkniętych.
    @discardableResult
    public func closeIdleSessions(olderThan minutes: Int, now: Date = Date()) async -> Int {
        guard minutes > 0 else { return 0 }
        var closed = 0
        for (key, s) in sessions {
            guard case .document = key.purpose, now.timeIntervalSince(lastActivity[key] ?? .distantPast) > Double(minutes * 60) else { continue }
            // Zamykamy tylko sesję, która odpowiada i nie ma otwartej transakcji (decyzję o transakcji podejmuje użytkownik).
            let tx: String?? = try? await s.scalar("select dbms_transaction.local_transaction_id from dual")
            if case .some(.none) = tx {
                await close(key)
                closed += 1
            }
        }
        return closed
    }
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

    /// Wywoływane po zmianie połączenia głównego (zestawy preferencji połączeń, PD-PREF-002).
    @ObservationIgnored public var onMainConnectionChange: (@MainActor () -> Void)?

    public func setMainConnection(_ id: UUID?) {
        let changed = mainConnectionID != id
        mainConnectionID = id
        if let id { store.markUsed(id) }
        if changed { onMainConnectionChange?() }
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

    /// Zmiana hasła użytkownika połączenia w otwartej sesji głównej (PD-CONN-017): OCIPasswordChange, nowe hasło
    /// w pamięci sesji i — gdy definicja zapisuje hasło — w Pęku kluczy. false — anulowano.
    public func changePassword(_ id: UUID) async throws -> Bool {
        guard let def = store.connection(id), let s = sessions[SessionKey(connectionID: id, purpose: .main)] else { throw CommandError.notConnected }
        guard !def.target.usesExternalCredentials else {
            throw CommandError.notAvailable(L10n.tr("Połączenie bez hasła (wallet, Kerberos, uwierzytelnianie zewnętrzne)"))
        }
        var old = sessionPasswords[id] ?? store.sessionPassword(for: id)
        if old == nil {
            guard let answer = await prompter?.askPassword(for: def, reason: L10n.tr("Podaj bieżące hasło")) else { return false }
            old = answer.password
        }
        guard let old, let new = await prompter?.askPasswordChange(for: def) else { return false }
        try await s.changePassword(user: def.target.user, oldPassword: old, newPassword: new)
        sessionPasswords[id] = new
        if def.savePassword { try store.rememberPassword(new, for: id) }
        return true
    }

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
        lastActivity[key] = Date()
        store.markUsed(key.connectionID)
        // SID sesji okien i głównej (wykonują polecenia użytkownika) — do zakończenia sesji, gdy Przerwij nie działa.
        switch key.purpose {
        case .main, .document: await recordServerSessionID(s, key: key)
        default: break
        }
        return s
    }

    private func open(_ key: SessionKey) async throws -> any DatabaseSession {
        guard let def = store.connection(key.connectionID) else { throw CommandError.notConnected }
        guard let driver = drivers[def.driver] else {
            throw DatabaseError.driverUnavailable(L10n.tr("Sterownik \(def.driver.rawValue) jest niedostępny"))
        }
        if case .failure(let e) = driver.availability() { throw e }
        var password = sessionPasswords[def.id] ?? store.sessionPassword(for: def.id)
        if password == nil, store.hasStoredPassword(for: def.id) {
            // Zapisane hasło: przy włączonej ochronie najpierw Touch ID / hasło Maca (raz na połączenie w sesji aplikacji).
            if settings().requireOwnerForSavedPasswords {
                guard await prompter?.authenticateOwner(reason: L10n.tr("użyć zapisanego hasła połączenia „\(def.displayName)”")) == true else {
                    throw CommandError.cancelledByUser
                }
            }
            password = store.password(for: def.id)
        }
        // Hasło zapisujemy dopiero po udanym połączeniu i tylko gdy użytkownik zaznaczył „Zapamiętaj”.
        var rememberOnSuccess = false
        if password == nil, !def.target.usesExternalCredentials {
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
            let tunnel = try await tunnels.open(for: def, tns: tns, secret: def.sshTunnel?.usesPassword == true ? store.sshPassword(for: def.id) : nil)
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
                // Wygasłe hasło jest już zmienione na serwerze — nowe zapamiętane przed inicjalizacją (inaczej po jej
                // błędzie następne logowanie kończyłoby się ORA-01017).
                if let np = credentials.newPassword {
                    // Nowe zastępuje stare, jeśli stare było zapisane albo użytkownik chciał.
                    if def.savePassword || rememberOnSuccess { try? store.rememberPassword(np, for: def.id) }
                    sessionPasswords[def.id] = np
                }
                // Nieudana inicjalizacja (skrypt startowy, NLS, Workspace Manager) — sesja zamknięta, tunel zwolniony.
                do { try await initialize(s, def) } catch { await s.close(); throw error }
                connected = true
                if credentials.newPassword == nil, let p = password {
                    if rememberOnSuccess { try? store.rememberPassword(p, for: def.id) }
                    sessionPasswords[def.id] = p
                }
                return s
            } catch let e as OracleError where e.isPasswordExpired && attempt < 2 {
                guard let np = await prompter?.askNewPassword(for: def, message: e.message) else { throw CommandError.cancelledByUser }
                credentials = Credentials(password: password, newPassword: np)
            } catch let e as OracleError where e.code == 1017 && attempt < 2 && !def.target.usesExternalCredentials {
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

    /// Zapamiętuje SID i instancję sesji (bez uprawnień do V$SESSION).
    func recordServerSessionID(_ s: any DatabaseSession, key: SessionKey) async {
        let (_, rows) = (try? await s.queryAll("select sys_context('userenv', 'sid'), sys_context('userenv', 'instance') from dual", limit: 1)) ?? ([], [])
        if let r = rows.first, let sid = r[0].displayText { serverSessionIDs[key] = (sid, r[1].displayText ?? "1") }
    }

    /// Po połączeniu: Workspace Manager, bieżący schemat, skrypt inicjalizacji połączenia (UG 19.2).
    private func initialize(_ s: any DatabaseSession, _ def: ConnectionDefinition) async throws {
        if let ws = def.workspaceManager, !ws.isEmpty {
            _ = try await s.execute("BEGIN DBMS_WM.GotoWorkspace(:ws); END;", binds: [BindVariable(name: "ws", value: .text(ws))])
        }
        if let nls = Self.nlsStatement(settings().sessionNLS) { _ = try await s.execute(nls) }
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
        serverSessionIDs[key] = nil
        sqlTraceEnabled.remove(key)
        lastActivity[key] = nil
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
        return store.hasStoredPassword(for: connectionID) || sessionPasswords[connectionID] != nil || store.connection(connectionID)?.target.usesExternalCredentials == true
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
        case .tool(let r): "narzędzie \(r)"
        }
    }
}
