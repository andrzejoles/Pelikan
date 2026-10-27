import Foundation
import Observation
import PelikanDB
import PelikanLog
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

extension SessionPurpose {
    /// Rodzaj sesji w dzienniku (bez identyfikatorów okien i agentów).
    var logLabel: String {
        switch self {
        case .main: "główna"
        case .document: "okna"
        case .compile: "kompilacji"
        case .agent: "agenta"
        case .debugger: "debugera"
        case .utplsql(let s): "utPLSQL \(s)"
        case .tool(let s): "narzędzia \(s.prefix { $0 != "-" })"
        }
    }
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
    /// Otwarte połączenia w kolejności połączenia (drzewo Object Browsera, PD-OB-001): od pierwszej sesji poza agentem
    /// AI do rozłączenia. Zamknięcie bezczynnych sesji i utrata sesji nie usuwają połączenia — wraca przy następnym użyciu.
    public private(set) var openConnections: [UUID] = []
    private var sessions: [SessionKey: any DatabaseSession] = [:]
    /// SID, numer seryjny i numer instancji sesji (przy otwarciu) — do zakończenia sesji okna z innej sesji (PD-CONN-027).
    /// Numer seryjny z chwili otwarcia: SID utraconej sesji serwer mógł już przydzielić innej (nil — brak DBMS_DEBUG_JDWP).
    public private(set) var serverSessionIDs: [SessionKey: (sid: String, serial: String?, instance: String)] = [:]
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
    /// `busy` — sesje okien, które wykonują polecenie albo mają otwarty kursor wyniku: nie są bezczynne (ich czas
    /// ostatniego użycia przesuwa się na `now`, więc odliczanie zaczyna się dopiero po zakończeniu).
    @discardableResult
    public func closeIdleSessions(olderThan minutes: Int, busy: Set<SessionKey> = [], now: Date = Date()) async -> Int {
        guard minutes > 0 else { return 0 }
        var closed = 0
        for key in busy where sessions[key] != nil { lastActivity[key] = now }
        let isIdle = { (key: SessionKey) in now.timeIntervalSince(self.lastActivity[key] ?? .distantPast) > Double(minutes * 60) }
        for (key, s) in sessions {
            guard case .document = key.purpose, isIdle(key) else { continue }
            // Zamykamy tylko sesję, która odpowiada i nie ma otwartej transakcji (decyzję o transakcji podejmuje użytkownik).
            let tx: String?? = try? await s.scalar("select dbms_transaction.local_transaction_id from dual")
            // W czasie zapytania okno mogło zacząć wykonanie (użycie sesji) albo sesja mogła zostać zastąpiona.
            guard sessions[key] === s, isIdle(key) else { continue }
            if case .some(.none) = tx {
                await close(key)
                closed += 1
            }
        }
        if closed > 0 { Log.connection.info("Zamknięto \(closed) bezczynnych sesji okien (po \(minutes) min)") }
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
    /// Tunel, przez który połączyła się sesja — zwalniany dokładnie ten (nie wg bieżącej definicji ani nowszego tunelu).
    @ObservationIgnored private var sessionTunnels: [SessionKey: SSHTunnelManager.Tunnel] = [:]
    /// Połączenia, dla których właściciel Maca potwierdził w tym uruchomieniu użycie zapisanych haseł (bazy i SSH, D56).
    @ObservationIgnored private var ownerConfirmed: Set<UUID> = []
    /// Sprawdzanie połączeń w toku (kolejny przebieg czeka na koniec poprzedniego) i czas ostatniego przebiegu.
    @ObservationIgnored var connectionCheckRunning = false
    @ObservationIgnored var lastConnectionCheck = Date()

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
        if let id {
            store.markUsed(id)
            noteOpen(id)
        }
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

    /// Hasło bazy podane w tym uruchomieniu (logowanie bez zapamiętania, zmiana albo wygaśnięcie hasła) — eksport
    /// z hasłami (D186); nil — brak.
    public func enteredPassword(for id: UUID) -> String? { sessionPasswords[id] }

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
        if case .agent = key.purpose {} else { noteOpen(key.connectionID) }
        // SID sesji okien i głównej (wykonują polecenia użytkownika) — do zakończenia sesji, gdy Przerwij nie działa.
        switch key.purpose {
        case .main, .document: await recordServerSessionID(s, key: key)
        default: break
        }
        return s
    }

    /// Otwarcie sesji z wpisem w dzienniku (PL-INFRA-011): nazwa połączenia jako skrót, sterownik, rodzaj sesji, czas;
    /// przy błędzie kod ORA- jawny, komunikat prywatny.
    private func open(_ key: SessionKey) async throws -> any DatabaseSession {
        let started = ContinuousClock.now
        let def = store.connection(key.connectionID)
        let name = def?.displayName ?? "?"
        let driver = def?.driver.rawValue ?? "?"
        do {
            let s = try await openSession(key)
            Log.connection.info("Połączono \(name, privacy: .hash) w \(ms: started) (sterownik \(driver, privacy: .public), klient \(s.info.clientVersion, privacy: .public), serwer \(s.info.server.description, privacy: .public), sesja \(key.purpose.logLabel, privacy: .public))")
            return s
        } catch CommandError.cancelledByUser {
            Log.connection.info("Łączenie z \(name, privacy: .hash) przerwane przez użytkownika")
            throw CommandError.cancelledByUser
        } catch {
            Log.connection.notice("Nie połączono \(name, privacy: .hash) (sterownik \(driver, privacy: .public), sesja \(key.purpose.logLabel, privacy: .public)) po \(ms: started): \(error)")
            throw error
        }
    }

    private func openSession(_ key: SessionKey) async throws -> any DatabaseSession {
        guard let def = store.connection(key.connectionID) else { throw CommandError.notConnected }
        guard let driver = drivers[def.driver] else {
            throw DatabaseError.driverUnavailable(L10n.tr("Sterownik \(def.driver.rawValue) jest niedostępny"))
        }
        if case .failure(let e) = driver.availability() { throw e }
        var password = sessionPasswords[def.id] ?? store.sessionPassword(for: def.id)
        if password == nil, store.hasStoredPassword(for: def.id) {
            // Zapisane hasło: przy włączonej ochronie najpierw Touch ID / hasło Maca (raz na połączenie w sesji aplikacji).
            try await confirmOwner(def)
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
        var tunnel: SSHTunnelManager.Tunnel?
        if def.sshTunnel != nil {
            let tns = tnsEntries(for: def)
            let opened = try await tunnels.open(for: def, tns: tns, secret: try await tunnelSecret(for: def))
            tunnel = opened
            guard let rewritten = ConnectStringRewriter.rewrite(def.target.connectString, localPort: opened.localPort, tns: tns) else {
                tunnels.release(opened, of: def.id)
                throw DatabaseError.driverUnavailable(L10n.tr("Nie można przepisać connect stringu dla tunelu SSH"))
            }
            target.connectString = rewritten
        }
        var connected = false
        defer { if let tunnel, !connected { tunnels.release(tunnel, of: def.id) } }
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
                if let tunnel { sessionTunnels[key] = tunnel }
                if credentials.newPassword == nil, let p = password {
                    if rememberOnSuccess { try? store.rememberPassword(p, for: def.id) }
                    sessionPasswords[def.id] = p
                }
                return s
            } catch let e as OracleError where e.isPasswordExpired && attempt < 2 {
                Log.connection.notice("Hasło wygasło (\(e as any Error)) — prośba o nowe hasło")
                guard let np = await prompter?.askNewPassword(for: def, message: e.message) else { throw CommandError.cancelledByUser }
                credentials = Credentials(password: password, newPassword: np)
            } catch let e as OracleError where e.code == 1017 && attempt < 2 && !def.target.usesExternalCredentials {
                // ORA-01017: błędne hasło — pytamy ponownie (zapisane hasło jest nieaktualne).
                Log.connection.notice("Odmowa logowania (ORA-01017) — ponowne pytanie o hasło")
                sessionPasswords[def.id] = nil
                guard let answer = await prompter?.askPassword(for: def, reason: e.message) else { throw CommandError.cancelledByUser }
                password = answer.password
                rememberOnSuccess = answer.remember
                credentials = Credentials(password: password)
            }
        }
        throw CommandError.notConnected
    }

    /// Zapamiętuje SID, numer seryjny i instancję sesji (bez uprawnień do V$SESSION).
    func recordServerSessionID(_ s: any DatabaseSession, key: SessionKey) async {
        let (_, rows) = (try? await s.queryAll("select sys_context('userenv', 'sid'), sys_context('userenv', 'instance') from dual", limit: 1)) ?? ([], [])
        guard let r = rows.first, let sid = r[0].displayText else { return }
        let serial = (try? await s.scalar("select dbms_debug_jdwp.current_session_serial from dual")) ?? nil
        serverSessionIDs[key] = (sid, serial, r[1].displayText ?? "1")
    }

    /// Potwierdzenie właściciela Maca przed użyciem zapisanego hasła bazy albo tunelu SSH (D56) — gdy ochrona jest
    /// włączona, raz na połączenie w tym uruchomieniu (do rozłączenia).
    private func confirmOwner(_ def: ConnectionDefinition) async throws {
        guard settings().requireOwnerForSavedPasswords, !ownerConfirmed.contains(def.id) else { return }
        guard await prompter?.authenticateOwner(reason: L10n.tr("użyć zapisanego hasła połączenia „\(def.displayName)”")) == true else {
            throw CommandError.cancelledByUser
        }
        ownerConfirmed.insert(def.id)
    }

    /// Hasło tunelu SSH z Pęku kluczy (po potwierdzeniu właściciela, D56); nil — tunel na klucz albo agenta SSH.
    public func tunnelSecret(for def: ConnectionDefinition) async throws -> String? {
        guard def.sshTunnel?.usesPassword == true, let secret = store.sshPassword(for: def.id) else { return nil }
        try await confirmOwner(def)
        return secret
    }

    /// Wpisy tnsnames.ora dla połączenia — te same katalogi co lista aliasów w oknie definicji połączenia.
    public func tnsEntries(for def: ConnectionDefinition) -> [TNSEntry] {
        TNSNames.load(directories: TNSNames.searchDirectories(configured: def.target.configDirectory,
                                                              instantClientDirectory: settings().instantClientDirectory))
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
        Log.connection.debug("Zamknięto sesję \(key.purpose.logLabel, privacy: .public) połączenia \(store.connection(key.connectionID)?.displayName, privacy: .hash)")
        await s.close()
        if let t = sessionTunnels.removeValue(forKey: key) { tunnels.release(t, of: key.connectionID) }
    }

    /// Rozłącza wszystkie sesje połączenia (UG 19.1 Disconnect).
    public func disconnect(_ connectionID: UUID) async {
        Log.connection.info("Rozłączono \(store.connection(connectionID)?.displayName, privacy: .hash)")
        for key in sessions.keys where key.connectionID == connectionID {
            await close(key)
        }
        sessionPasswords[connectionID] = nil
        ownerConfirmed.remove(connectionID)
        openConnections.removeAll { $0 == connectionID }
    }

    private func noteOpen(_ connectionID: UUID) {
        if !openConnections.contains(connectionID) { openConnections.append(connectionID) }
    }

    public func disconnectAll() async {
        openConnections.removeAll()
        for key in Array(sessions.keys) { await close(key) }
        sessionPasswords.removeAll()
        ownerConfirmed.removeAll()
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
        Log.connection.notice("Utracono połączenie \(store.connection(key.connectionID)?.displayName, privacy: .hash) (sesja \(key.purpose.logLabel, privacy: .public))")
        // SID utraconej sesji może dostać inna sesja — „Zakończ sesję okna” nie może jej wskazać.
        serverSessionIDs[key] = nil
        sqlTraceEnabled.remove(key)
        lastActivity[key] = nil
        if let t = sessionTunnels.removeValue(forKey: key) { tunnels.release(t, of: key.connectionID) }
        return true
    }

    /// Sprawdzenie połączeń (UG 23.1 Check connection): ping sesji głównych i sesji z `also` (okna z otwartą
    /// transakcją); sesje zajęte (`busy` — ping czekałby w kolejce sesji na koniec polecenia) pomijane; utracone usuwane.
    public func checkConnections(also: Set<SessionKey> = [], busy: Set<SessionKey> = []) async -> [SessionKey] {
        var lost: [SessionKey] = []
        for (key, s) in sessions where (key.purpose == .main || also.contains(key)) && !busy.contains(key) {
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
