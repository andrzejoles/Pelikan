import Foundation

/// Rola przy logowaniu (CONNECT … AS SYSDBA itd.).
public enum ConnectRole: String, Sendable, Codable, Hashable, CaseIterable {
    case normal = "Normal", sysdba = "SYSDBA", sysoper = "SYSOPER", sysbackup = "SYSBACKUP"
    case sysdg = "SYSDG", syskm = "SYSKM", sysasm = "SYSASM"
}

/// Dokąd i jak się połączyć — bez hasła (to jest zapisywane w ustawieniach połączenia).
public struct ConnectionTarget: Sendable, Codable, Hashable {
    /// Użytkownik bazy. Przy proxy: konto pośrednika (proxy), a schemat docelowy w `proxyClient`.
    public var user: String
    /// EZConnect (`host:port/usługa`, `tcps://…`) albo alias z `tnsnames.ora`.
    public var connectString: String
    public var role: ConnectRole
    /// Proxy user: logujemy się jako `user` z prawami do schematu `proxyClient` (`user[proxyClient]`).
    public var proxyClient: String?
    /// Uwierzytelnianie zewnętrzne (wallet z hasłami, Kerberos, uwierzytelnianie systemu).
    public var externalAuth: Bool
    /// Katalog z `tnsnames.ora`, `sqlnet.ora` i wallet (jak TNS_ADMIN); nil = domyślny.
    public var configDirectory: String?
    public var edition: String?
    /// Portfel TLS (mTLS, np. Autonomous Database) tego połączenia; nil — katalog konfiguracji.
    public var walletDirectory: String?
    /// Uwierzytelnianie portfelem z magazynem haseł (SEPS, `/@alias`) — dla sterownika to uwierzytelnianie zewnętrzne.
    public var walletAuth: Bool?
    /// Uwierzytelnianie tokenem (Microsoft Entra ID, plik tokenu OAuth2) obsługiwane przez Instant Client 23 (SD-AUTH-001).
    public var tokenAuth: TokenAuth?

    public init(user: String, connectString: String, role: ConnectRole = .normal, proxyClient: String? = nil,
                externalAuth: Bool = false, configDirectory: String? = nil, edition: String? = nil) {
        self.user = user; self.connectString = connectString; self.role = role; self.proxyClient = proxyClient
        self.externalAuth = externalAuth; self.configDirectory = configDirectory; self.edition = edition
    }

    /// Logowanie bez hasła Pelikana: uwierzytelnianie zewnętrzne albo portfel z magazynem haseł.
    public var usesExternalCredentials: Bool { externalAuth || walletAuth == true || tokenAuth != nil }

    /// Nazwa użytkownika przekazywana do sterownika (z proxy: `pośrednik[schemat]`).
    public var driverUserName: String {
        if let p = proxyClient, !p.isEmpty { return "\(user)[\(p)]" }
        return user
    }
}

/// Hasła — tylko w pamięci, nigdy Codable, nigdy w logach (`description` ukrywa treść).
public struct Credentials: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var password: String?
    /// Nowe hasło przy zmianie wygasłego (ORA-28001).
    public var newPassword: String?

    public init(password: String?, newPassword: String? = nil) {
        self.password = password; self.newPassword = newPassword
    }

    public var description: String { "Credentials(«redacted»)" }
    public var debugDescription: String { description }
}

/// Jak sesja przedstawia się w V$SESSION (Session Browser, rozpoznawanie sesji agenta).
public struct SessionTags: Sendable, Hashable {
    public var module: String
    public var action: String?
    public var clientInfo: String?
    public var clientIdentifier: String?

    public init(module: String = "Pelikan", action: String? = nil, clientInfo: String? = nil, clientIdentifier: String? = nil) {
        self.module = module; self.action = action; self.clientInfo = clientInfo; self.clientIdentifier = clientIdentifier
    }
}

public struct ConnectOptions: Sendable {
    public var tags: SessionTags
    /// Rozmiar porcji pobieranej z serwera w jednym przejściu (nie mylić z liczbą wierszy pokazywanych w siatce).
    public var fetchArraySize: UInt32
    public var statementCacheSize: UInt32
    /// Maksymalna długość LOB pobierana do wartości (reszta na żądanie).
    public var lobPrefetchLimit: Int

    public init(tags: SessionTags = SessionTags(), fetchArraySize: UInt32 = 500, statementCacheSize: UInt32 = 40,
                lobPrefetchLimit: Int = 1 << 20) {
        self.tags = tags; self.fetchArraySize = fetchArraySize
        self.statementCacheSize = statementCacheSize; self.lobPrefetchLimit = lobPrefetchLimit
    }
}

/// Sterownik, który obsługuje połączenie.
public enum DriverKind: String, Sendable, Codable, Hashable, CaseIterable {
    /// ODPI-C + Oracle Instant Client (domyślny, pełne OCI).
    case instantClient
    /// OracleNIO — czysty Swift, bez Instant Client (alternatywny).
    case thin
}

/// Funkcje, które sterownik może (nie) obsługiwać — interfejs wyszarza niedostępne z podpowiedzią.
public struct DriverCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let breakExecution = DriverCapabilities(rawValue: 1 << 0)
    public static let dbmsDebug = DriverCapabilities(rawValue: 1 << 1)
    public static let dbmsDebugJDWP = DriverCapabilities(rawValue: 1 << 2)
    public static let lobs = DriverCapabilities(rawValue: 1 << 3)
    public static let objectTypes = DriverCapabilities(rawValue: 1 << 4)
    public static let refCursors = DriverCapabilities(rawValue: 1 << 5)
    public static let implicitResults = DriverCapabilities(rawValue: 1 << 6)
    public static let wallet = DriverCapabilities(rawValue: 1 << 7)
    public static let kerberos = DriverCapabilities(rawValue: 1 << 8)
    public static let proxyUser = DriverCapabilities(rawValue: 1 << 9)
    public static let changePassword = DriverCapabilities(rawValue: 1 << 10)
    public static let tnsNames = DriverCapabilities(rawValue: 1 << 11)
    public static let ldap = DriverCapabilities(rawValue: 1 << 12)
    public static let sysdba = DriverCapabilities(rawValue: 1 << 13)
    public static let json = DriverCapabilities(rawValue: 1 << 14)
    public static let vector = DriverCapabilities(rawValue: 1 << 15)
    public static let oldServers = DriverCapabilities(rawValue: 1 << 16)   // 11.2 i starsze
}

public struct ServerVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var major: Int, minor: Int, update: Int, portRelease: Int, portUpdate: Int
    public var banner: String

    public init(major: Int, minor: Int = 0, update: Int = 0, portRelease: Int = 0, portUpdate: Int = 0, banner: String = "") {
        self.major = major; self.minor = minor; self.update = update
        self.portRelease = portRelease; self.portUpdate = portUpdate; self.banner = banner
    }

    public var description: String { "\(major).\(minor).\(update).\(portRelease).\(portUpdate)" }

    public static func < (a: ServerVersion, b: ServerVersion) -> Bool {
        (a.major, a.minor, a.update, a.portRelease, a.portUpdate) < (b.major, b.minor, b.update, b.portRelease, b.portUpdate)
    }
}

public struct SessionInfo: Sendable {
    public var driver: DriverKind
    public var driverVersion: String
    public var clientVersion: String
    public var server: ServerVersion
    public var capabilities: DriverCapabilities
    /// Aktualny schemat i użytkownik sesji (SYS_CONTEXT) — do Object Browsera i Code Assistant.
    public var currentSchema: String
    public var sessionUser: String

    public init(driver: DriverKind, driverVersion: String, clientVersion: String, server: ServerVersion,
                capabilities: DriverCapabilities, currentSchema: String, sessionUser: String) {
        self.driver = driver; self.driverVersion = driverVersion; self.clientVersion = clientVersion
        self.server = server; self.capabilities = capabilities
        self.currentSchema = currentSchema; self.sessionUser = sessionUser
    }
}

/// Kierunek zmiennej wiązanej.
public enum BindDirection: String, Sendable, Codable, Hashable { case input, output, inputOutput }

/// Zmienna wiązana (`:nazwa`). Typ decyduje o buforze dla OUT; dla IN wystarczy wartość.
public struct BindVariable: Sendable, Hashable {
    public var name: String
    public var type: OracleType
    public var direction: BindDirection
    public var value: OracleValue
    /// Maksymalny rozmiar bufora dla tekstu/RAW (OUT, IN OUT).
    public var maxSize: UInt32

    public init(name: String, type: OracleType = .varchar2, direction: BindDirection = .input,
                value: OracleValue = .null, maxSize: UInt32 = 32767) {
        self.name = name; self.type = type; self.direction = direction; self.value = value; self.maxSize = maxSize
    }
}

/// Rodzaj polecenia wg sterownika (po sparsowaniu przez serwer).
public enum StatementKind: String, Sendable, Hashable {
    case query, dml, ddl, plsql, transaction, alterSession, other
}

/// Wynik wykonania pojedynczego polecenia.
public struct ExecutionResult: Sendable {
    public var kind: StatementKind
    /// Kursor wyniku zapytania (SELECT, WITH) — dociąganie przez `fetch`.
    public var resultSet: ResultSetDescriptor?
    /// Liczba wierszy zmienionych przez DML (także MERGE), 0 dla pozostałych.
    public var rowsAffected: UInt64
    /// Wartości zmiennych OUT / IN OUT po wykonaniu.
    public var outBinds: [String: OracleValue]
    /// Niejawne wyniki (DBMS_SQL.RETURN_RESULT, 12c+).
    public var implicitResults: [ResultSetDescriptor]
    /// Ostrzeżenie serwera, np. „success with compilation error” (ORA-24344) po CREATE PROCEDURE.
    public var warning: OracleError?
    public var elapsed: Duration

    public init(kind: StatementKind, resultSet: ResultSetDescriptor? = nil, rowsAffected: UInt64 = 0,
                outBinds: [String: OracleValue] = [:], implicitResults: [ResultSetDescriptor] = [],
                warning: OracleError? = nil, elapsed: Duration = .zero) {
        self.kind = kind; self.resultSet = resultSet; self.rowsAffected = rowsAffected; self.outBinds = outBinds
        self.implicitResults = implicitResults; self.warning = warning; self.elapsed = elapsed
    }
}

public struct ResultSetDescriptor: Sendable, Hashable {
    public var id: ResultSetID
    public var columns: [ColumnInfo]

    public init(id: ResultSetID, columns: [ColumnInfo]) {
        self.id = id; self.columns = columns
    }
}

/// Porcja wierszy z kursora.
public struct RowBatch: Sendable {
    public var rows: [[OracleValue]]
    /// false — kursor wyczerpany (i zamknięty po stronie sterownika).
    public var hasMore: Bool

    public init(rows: [[OracleValue]], hasMore: Bool) {
        self.rows = rows; self.hasMore = hasMore
    }
}

public struct ExecuteOptions: Sendable {
    /// Wykonanie w trybie „describe only” (tylko kolumny, bez danych) — Query Builder, Code Assistant.
    public var describeOnly: Bool
    /// Wykonanie z natychmiastowym COMMIT (sterownik), domyślnie false — PL/SQL Developer nie ma auto-commita.
    public var autoCommit: Bool
    /// Limit czasu wywołania (ms), 0 = bez limitu (przerwanie ręczne przez `breakExecution`).
    public var callTimeoutMs: UInt32
    /// Limit pobierania treści LOB (bajty) dla wyników tego polecenia; nil — z opcji połączenia (Large Data Editor
    /// pobiera całość).
    public var lobLimit: Int?
    /// Liczba wierszy pobieranych naraz dla wyników tego polecenia (także kursorów OUT); nil — z opcji połączenia.
    /// 1 — wiersze potokowe dostępne od razu (zdarzenia reportera utPLSQL czasu rzeczywistego).
    public var fetchArraySize: UInt32?

    public init(describeOnly: Bool = false, autoCommit: Bool = false, callTimeoutMs: UInt32 = 0, lobLimit: Int? = nil, fetchArraySize: UInt32? = nil) {
        self.describeOnly = describeOnly; self.autoCommit = autoCommit; self.callTimeoutMs = callTimeoutMs; self.lobLimit = lobLimit
        self.fetchArraySize = fetchArraySize
    }
}

/// Sesja bazy danych. Implementacje: `ODPISession` (Instant Client), sterownik thin (później).
/// Wszystkie metody async wykonują się poza wątkiem głównym; `breakExecution` może być wołane w trakcie.
public protocol DatabaseSession: AnyObject, Sendable {
    var info: SessionInfo { get }

    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch
    func closeResultSet(_ resultSet: ResultSetID) async
    /// Opis kolumn otwartego kursora (np. REF CURSOR z OUT); pusta lista, gdy sterownik go nie zna.
    func columns(of resultSet: ResultSetID) async -> [ColumnInfo]

    func commit() async throws
    func rollback() async throws
    /// Przerywa bieżące wywołanie (OCIBreak) — bezpieczne z dowolnego wątku.
    func breakExecution()
    func ping() async throws
    func setTags(_ tags: SessionTags) async throws
    func close() async
}

public extension DatabaseSession {
    func columns(of resultSet: ResultSetID) async -> [ColumnInfo] { [] }

    func execute(_ sql: String, binds: [BindVariable] = []) async throws -> ExecutionResult {
        try await execute(sql, binds: binds, options: ExecuteOptions())
    }

    /// Wykonuje zapytanie i pobiera wszystkie wiersze (do `limit`) — dla metadanych i testów.
    func queryAll(_ sql: String, binds: [BindVariable] = [], limit: Int = 100_000) async throws -> (columns: [ColumnInfo], rows: [[OracleValue]]) {
        let r = try await execute(sql, binds: binds)
        guard let rs = r.resultSet else { return ([], []) }
        var rows: [[OracleValue]] = []
        while rows.count < limit {
            let batch = try await fetch(rs.id, maxRows: min(1000, limit - rows.count))
            rows += batch.rows
            if !batch.hasMore { return (rs.columns, rows) }
        }
        await closeResultSet(rs.id)
        return (rs.columns, rows)
    }

    /// Pierwsza kolumna pierwszego wiersza jako tekst.
    func scalar(_ sql: String, binds: [BindVariable] = []) async throws -> String? {
        let (_, rows) = try await queryAll(sql, binds: binds, limit: 1)
        return rows.first?.first.flatMap { $0.displayText }
    }
}

/// Błąd Oracle albo sterownika.
public struct OracleError: Error, Sendable, Hashable, CustomStringConvertible, LocalizedError {
    /// Kod ORA- (np. 942); 0 — błąd sterownika bez kodu ORA (wtedy `driverCode`, np. DPI-1047).
    public var code: Int32
    public var message: String
    /// Pozycja błędu w tekście polecenia (0-based, w znakach UTF-16 wg Oracle — tu w bajtach UTF-8 od sterownika).
    public var offset: UInt32
    public var isRecoverable: Bool
    public var isWarning: Bool
    public var sqlState: String
    public var driverCode: String?

    public init(code: Int32, message: String, offset: UInt32 = 0, isRecoverable: Bool = false,
                isWarning: Bool = false, sqlState: String = "", driverCode: String? = nil) {
        self.code = code; self.message = message; self.offset = offset; self.isRecoverable = isRecoverable
        self.isWarning = isWarning; self.sqlState = sqlState; self.driverCode = driverCode
    }

    public var description: String { message }
    /// Treść komunikatu Oracle także w `localizedDescription` (okna błędów, wyniki komend).
    public var errorDescription: String? { message }

    /// Utrata połączenia (ORA-03113, 03114, 03135, 12537, 28 itd.) — przyczynek do ponownego łączenia.
    public var isConnectionLost: Bool {
        [28, 1012, 2396, 3113, 3114, 3135, 12153, 12537, 12541, 12547, 12570, 12571].contains(code)
            || driverCode == "DPI-1010" || driverCode == "DPI-1080"
    }
    /// Przerwane przez użytkownika (ORA-01013).
    public var isCancelled: Bool { code == 1013 }
    /// Wygasłe hasło (ORA-28001) — okno zmiany hasła.
    public var isPasswordExpired: Bool { code == 28001 }
}

public enum DatabaseError: Error, LocalizedError, Sendable, Equatable {
    /// Sterownik niedostępny (np. brak Instant Client) — komunikat z instrukcją.
    case driverUnavailable(String)
    /// Brak biblioteki klienta (Instant Client) — interfejs pokazuje ekran pomocy (PD-CONN-029).
    case clientMissing(String)
    case unknownResultSet
    case unsupported(String)
    case closed

    public var errorDescription: String? {
        switch self {
        case .driverUnavailable(let m), .unsupported(let m), .clientMissing(let m): m
        case .unknownResultSet: "Wynik zapytania jest już zamknięty"
        case .closed: "Sesja jest zamknięta"
        }
    }
}

/// Fabryka sesji danego sterownika (aplikacja wstrzykuje implementacje do modelu — Workspace nie zna sterowników).
public protocol DatabaseDriver: Sendable {
    var kind: DriverKind { get }
    /// Możliwości sterownika (bez łączenia) — do wyszarzania funkcji w interfejsie.
    var capabilities: DriverCapabilities { get }
    /// Czy sterownik jest gotowy (np. znaleziono Instant Client); komunikat z instrukcją, gdy nie.
    func availability() -> Result<Void, DatabaseError>
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession
}

/// Token dostępu pobierany przez klienta Oracle (Instant Client 23+), bez hasła i bez sekretów w Pelikanie:
/// Entra ID interaktywnie (przeglądarka) albo token OAuth2 z pliku (np. zapisany przez `az account get-access-token`).
public struct TokenAuth: Sendable, Codable, Hashable {
    public enum Flow: String, Sendable, Codable, CaseIterable { case azureInteractive, oauthFile }
    public var flow: Flow
    /// Entra ID: identyfikator dzierżawy, identyfikator aplikacji klienta i URI aplikacji bazy.
    public var tenantID: String?
    public var clientID: String?
    public var appIDURI: String?
    /// Plik albo katalog z tokenem (TOKEN_LOCATION) dla `oauthFile`.
    public var tokenLocation: String?

    public init(flow: Flow, tenantID: String? = nil, clientID: String? = nil, appIDURI: String? = nil, tokenLocation: String? = nil) {
        self.flow = flow; self.tenantID = tenantID; self.clientID = clientID; self.appIDURI = appIDURI; self.tokenLocation = tokenLocation
    }

    /// Parametry sekcji SECURITY deskryptora / EZConnect Plus.
    public var parameters: [(String, String)] {
        func clean(_ s: String?) -> String? { s.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } }
        switch flow {
        case .azureInteractive:
            return [("TOKEN_AUTH", "AZURE_INTERACTIVE")] + [("TENANT_ID", clean(tenantID)), ("AZURE_CLIENT_ID", clean(clientID)), ("AZURE_DB_APP_ID_URI", clean(appIDURI))]
                .compactMap { k, v in v.map { (k, $0) } }
        case .oauthFile:
            return [("TOKEN_AUTH", "OAUTH")] + (clean(tokenLocation).map { [("TOKEN_LOCATION", ($0 as NSString).expandingTildeInPath)] } ?? [])
        }
    }

    /// Brakujące pola wymagane dla przepływu (puste — gotowe).
    public var missingFields: [String] {
        switch flow {
        case .azureInteractive:
            return [("TENANT_ID", tenantID), ("AZURE_CLIENT_ID", clientID), ("AZURE_DB_APP_ID_URI", appIDURI)]
                .filter { ($0.1 ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.map(\.0)
        case .oauthFile:
            return (tokenLocation ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? ["TOKEN_LOCATION"] : []
        }
    }
}
