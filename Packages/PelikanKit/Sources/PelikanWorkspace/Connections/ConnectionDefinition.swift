import Foundation
import PelikanDB

/// Środowisko połączenia — steruje ostrzeżeniami i domyślnymi uprawnieniami agenta (PROMPT §4.2 p.6, §7.3 p.8).
public enum ConnectionEnvironment: String, Sendable, Codable, CaseIterable {
    case development, test, production, other

    public var displayName: String {
        switch self {
        case .development: L10n.tr("Deweloperskie")
        case .test: L10n.tr("Testowe")
        case .production: L10n.tr("Produkcyjne")
        case .other: L10n.tr("Inne")
        }
    }

    public var shortName: String {
        switch self {
        case .development: "dev"
        case .test: "test"
        case .production: "prod"
        case .other: "—"
        }
    }
}

/// Kolor RGB (wskaźnik połączenia, foldery) — bez AppKit.
public struct RGBColor: Sendable, Codable, Hashable {
    public var red: Double, green: Double, blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    /// `#RRGGBB` albo `RRGGBB`.
    public init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        red = Double((v >> 16) & 0xFF) / 255
        green = Double((v >> 8) & 0xFF) / 255
        blue = Double(v & 0xFF) / 255
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    public static let production = RGBColor(red: 0.85, green: 0.18, blue: 0.16)
    public static let test = RGBColor(red: 0.95, green: 0.65, blue: 0.10)
    public static let development = RGBColor(red: 0.20, green: 0.62, blue: 0.30)
}

/// Tunel SSH do bazy (DB-SSH-001): Pelikan uruchamia systemowy `ssh -L` i łączy się z portem lokalnym.
public struct SSHTunnel: Sendable, Codable, Hashable {
    public var host: String
    public var port: Int
    public var user: String
    /// Plik klucza prywatnego (nil = agent SSH / domyślne klucze).
    public var identityFile: String?
    /// Host pośredni (ProxyJump), opcjonalnie.
    public var jumpHost: String?
    /// Hasło SSH w Pęku kluczy (zamiast klucza).
    public var usesPassword: Bool

    public init(host: String, port: Int = 22, user: String, identityFile: String? = nil, jumpHost: String? = nil, usesPassword: Bool = false) {
        self.host = host; self.port = port; self.user = user
        self.identityFile = identityFile; self.jumpHost = jumpHost; self.usesPassword = usesPassword
    }
}

/// Ustawienia agenta AI dla połączenia (PROMPT §7.3).
public struct AgentConnectionPolicy: Sendable, Codable, Hashable {
    /// Czy agent w ogóle widzi to połączenie.
    public var visibleToAgent: Bool
    /// Czy agent może zmieniać dane i obiekty (na prod domyślnie nie).
    public var allowChanges: Bool
    /// Osobny użytkownik bazy dla sesji agenta (np. proxy user tylko z grantami SELECT).
    public var agentUser: String?
    /// Kolumny maskowane w wynikach dla agenta, np. `PESEL`, `EMAIL`, `HR.EMPLOYEES.SALARY`.
    public var maskedColumns: [String]

    public init(visibleToAgent: Bool = true, allowChanges: Bool = true, agentUser: String? = nil, maskedColumns: [String] = []) {
        self.visibleToAgent = visibleToAgent; self.allowChanges = allowChanges
        self.agentUser = agentUser; self.maskedColumns = maskedColumns
    }

    public static func `default`(for env: ConnectionEnvironment) -> AgentConnectionPolicy {
        AgentConnectionPolicy(allowChanges: env != .production)
    }
}

/// Definicja połączenia (UG 19.2) — zapisywana bez hasła; hasło w Pęku kluczy pod `id`.
public struct ConnectionDefinition: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    /// Nazwa wyświetlana; pusta = `user@baza`.
    public var name: String
    public var folderID: UUID?
    public var target: ConnectionTarget
    public var driver: DriverKind
    public var environment: ConnectionEnvironment
    /// Kolor wskaźnika (nil = wg środowiska / reguł Connection Indicators).
    public var color: RGBColor?
    /// Hasło zapisane w Pęku kluczy (false = pytaj przy pierwszym użyciu w sesji aplikacji).
    public var savePassword: Bool
    public var readOnly: Bool
    public var connectOnStartup: Bool
    /// Skrypt wykonywany w każdej nowej sesji tego połączenia (polecenia rozdzielone `;`, bloki `/`).
    public var initScript: String
    /// Komunikat pokazywany przy logowaniu.
    public var logonMessage: String
    /// Workspace Manager (DBMS_WM.GotoWorkspace).
    public var workspaceManager: String?
    public var sshTunnel: SSHTunnel?
    public var agent: AgentConnectionPolicy
    /// Bieżący schemat ustawiany w każdej sesji (Set current schema, UG 19.1).
    public var currentSchema: String?
    public var lastUsed: Date?

    public init(id: UUID = UUID(), name: String = "", folderID: UUID? = nil, target: ConnectionTarget,
                driver: DriverKind = .instantClient, environment: ConnectionEnvironment = .development, color: RGBColor? = nil,
                savePassword: Bool = true, readOnly: Bool = false, connectOnStartup: Bool = false, initScript: String = "",
                logonMessage: String = "", workspaceManager: String? = nil, sshTunnel: SSHTunnel? = nil,
                agent: AgentConnectionPolicy? = nil, currentSchema: String? = nil) {
        self.id = id; self.name = name; self.folderID = folderID; self.target = target; self.driver = driver
        self.environment = environment; self.color = color; self.savePassword = savePassword; self.readOnly = readOnly
        self.connectOnStartup = connectOnStartup; self.initScript = initScript; self.logonMessage = logonMessage
        self.workspaceManager = workspaceManager; self.sshTunnel = sshTunnel
        self.agent = agent ?? .default(for: environment); self.currentSchema = currentSchema
    }

    /// `user@baza` jak we wzorcu (z rolą, proxy i edycją: `sys@chicago as sysdba`, `{R2}`).
    public var connectionString: String {
        var s = "\(target.driverUserName.lowercased())@\(target.connectString)"
        if target.role != .normal { s += " as \(target.role.rawValue.lowercased())" }
        if let e = target.edition, !e.isEmpty { s += " {\(e)}" }
        return s
    }

    public var displayName: String { name.isEmpty ? connectionString : name }

    /// Kolor efektywny: własny albo wg środowiska.
    public var effectiveColor: RGBColor? {
        if let color { return color }
        switch environment {
        case .production: return .production
        case .test: return .test
        case .development, .other: return nil
        }
    }

    /// Nazwa dla agenta (alias bez hosta, portu, usługi i użytkownika — PROMPT §7.3 p.1).
    public var agentAlias: String { name.isEmpty ? "połączenie-\(id.uuidString.prefix(8).lowercased())" : name }
}

/// Folder listy połączeń (UG 19.2): połączenia jawne + dopasowane regułą (wzorce * ?).
public struct ConnectionFolder: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var color: RGBColor?
    /// Reguły dopasowania (puste = tylko połączenia jawnie w folderze).
    public var userPattern: String
    public var databasePattern: String
    public var role: ConnectRole?

    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil, color: RGBColor? = nil,
                userPattern: String = "", databasePattern: String = "", role: ConnectRole? = nil) {
        self.id = id; self.name = name; self.parentID = parentID; self.color = color
        self.userPattern = userPattern; self.databasePattern = databasePattern; self.role = role
    }

    public var hasRule: Bool { !userPattern.isEmpty || !databasePattern.isEmpty || role != nil }

    /// Czy połączenie pasuje do reguły folderu.
    public func matches(_ c: ConnectionDefinition) -> Bool {
        guard hasRule else { return false }
        if !userPattern.isEmpty, !Wildcard.matches(c.target.driverUserName, pattern: userPattern) { return false }
        if !databasePattern.isEmpty, !Wildcard.matches(c.target.connectString, pattern: databasePattern) { return false }
        if let role, c.target.role != role { return false }
        return true
    }
}

/// Dopasowanie wzorców `*` i `?` bez rozróżniania wielkości liter (reguły folderów, wskaźniki, preferencje `user@db`).
public enum Wildcard {
    public static func matches(_ text: String, pattern: String) -> Bool {
        let t = Array(text.lowercased())
        let p = Array(pattern.lowercased())
        var ti = 0, pi = 0
        var star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "?" || p[pi] == t[ti] {
                ti += 1; pi += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = ti; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ti = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// Dopasowanie `user@database` (np. `sys@*`, `*@prd*`).
    public static func matches(user: String, database: String, pattern: String) -> Bool {
        let parts = pattern.split(separator: "@", maxSplits: 1).map(String.init)
        let up = parts.first ?? "*"
        let dp = parts.count > 1 ? parts[1] : "*"
        return matches(user, pattern: up.isEmpty ? "*" : up) && matches(database, pattern: dp.isEmpty ? "*" : dp)
    }
}
