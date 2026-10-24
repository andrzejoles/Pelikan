import Foundation
import PelikanDB
import PelikanODPI
import Testing

/// Dostęp do lokalnej bazy testowej (scripts/testdb.sh). Testy NIGDY nie łączą się z inną bazą:
/// host musi być lokalny (127.0.0.1/localhost) — wyjątek tylko w CI, gdzie baza jest kontenerem usługi.
enum TestDatabase {
    struct Config: Sendable {
        var connectString: String
        var user: String
        var password: String
        var agentUser: String
        var agentPassword: String
        var systemPassword: String
        /// Serwer SSH testów tunelu (scripts/testdb.sh ssh-up): port lokalny, nazwa kontenera bazy w sieci Docker,
        /// katalog z kluczem i known_hosts.
        var sshPort: Int?
        var sshDBHost: String?
        var sshDirectory: String?
        /// Hasło użytkownika `haslo` serwera SSH testów (tunel z hasłem, DB-SSH-001).
        var sshPassword: String?
        /// ORDS testów (scripts/testdb.sh ords-up): bazowy adres HTTP, np. http://127.0.0.1:8181/ords.
        var ordsURL: String?
    }

    static let config: Config? = {
        var env = ProcessInfo.processInfo.environment
        if env["PELIKAN_TESTDB_PASSWORD"] == nil, let file = envFile(),
           let text = try? String(contentsOfFile: file, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { env[parts[0]] = parts[1] }
            }
        }
        guard let host = env["PELIKAN_TESTDB_HOST"], let port = env["PELIKAN_TESTDB_PORT"],
              let service = env["PELIKAN_TESTDB_SERVICE"], let user = env["PELIKAN_TESTDB_USER"],
              let password = env["PELIKAN_TESTDB_PASSWORD"] else { return nil }
        let isLocal = ["127.0.0.1", "localhost", "::1"].contains(host)
        guard isLocal || env["CI"] != nil else {
            fatalError("Testy łączą się tylko z lokalną bazą testową, nie z \(host)")
        }
        // Portfel testowy (scripts/testdb.sh wallet) i LDAP (ldap-up): katalog Oracle Net jak w aplikacji, jako TNS_ADMIN
        // procesu testów — ustawiany przed pierwszym połączeniem (klient czyta konfigurację raz). Bez nich — bez zmian.
        if let file = envFile() {
            let state = (file as NSString).deletingLastPathComponent
            let fm = FileManager.default
            let wallet = fm.fileExists(atPath: state + "/wallet/cwallet.sso")
            let ldap = fm.fileExists(atPath: state + "/oracle-net-user/ldap.ora")
            if wallet || ldap,
               let dir = try? OracleNet.prepareManagedDirectory(URL(fileURLWithPath: state + "/oracle-net"), userDirectory: state + "/oracle-net-user",
                                                               walletDirectory: wallet ? state + "/wallet" : nil) {
                setenv("TNS_ADMIN", dir, 1)
                walletReady = wallet
                ldapReady = ldap
                oracleNetDirectory = dir
            }
        }
        return Config(connectString: "\(host):\(port)/\(service)", user: user, password: password,
                      agentUser: env["PELIKAN_TESTDB_AGENT_USER"] ?? "PELIKAN_AGENT",
                      agentPassword: env["PELIKAN_TESTDB_AGENT_PASSWORD"] ?? "",
                      systemPassword: env["PELIKAN_TESTDB_SYSTEM_PASSWORD"] ?? "",
                      sshPort: env["PELIKAN_TESTDB_SSH_PORT"].flatMap(Int.init), sshDBHost: env["PELIKAN_TESTDB_SSH_DBHOST"],
                      sshDirectory: envFile().map { ($0 as NSString).deletingLastPathComponent + "/ssh" },
                      sshPassword: env["PELIKAN_TESTDB_SSH_PASSWORD"],
                      ordsURL: env["PELIKAN_TESTDB_ORDS_URL"].flatMap { url in
                          // Tylko lokalny ORDS z kontenera testowego.
                          URL(string: url).flatMap(\.host).map { ["127.0.0.1", "localhost"].contains($0) } == true ? url : nil
                      })
    }()

    /// .testdb/env w katalogu głównym repozytorium (szukany w górę od tego pliku).
    private static func envFile() -> String? {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = url.appendingPathComponent(".testdb/env").path
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
            url.deleteLastPathComponent()
        }
        return nil
    }

    static var isAvailable: Bool { config != nil && InstantClientLocator.locate() != nil }

    /// Portfel SEPS bazy testowej przygotowany (scripts/testdb.sh wallet).
    nonisolated(unsafe) static var walletReady = false
    static var isWalletAvailable: Bool { isAvailable && walletReady }

    /// Nazewnictwo katalogowe przygotowane (scripts/testdb.sh ldap-up): ldap.ora i sqlnet.ora w katalogu użytkownika.
    nonisolated(unsafe) static var ldapReady = false
    nonisolated(unsafe) static var oracleNetDirectory: String?
    static var isLDAPAvailable: Bool { isAvailable && ldapReady }

    static func connect(agent: Bool = false, tags: SessionTags = SessionTags(module: "Pelikan tests")) async throws -> ODPISession {
        guard let c = config else { throw DatabaseError.driverUnavailable("Brak konfiguracji bazy testowej (scripts/testdb.sh up)") }
        let target = ConnectionTarget(user: agent ? c.agentUser : c.user, connectString: c.connectString)
        return try await ODPISession.connect(target: target, credentials: Credentials(password: agent ? c.agentPassword : c.password),
                                             options: ConnectOptions(tags: tags))
    }
}
