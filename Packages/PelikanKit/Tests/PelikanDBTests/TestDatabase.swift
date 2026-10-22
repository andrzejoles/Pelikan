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
        return Config(connectString: "\(host):\(port)/\(service)", user: user, password: password,
                      agentUser: env["PELIKAN_TESTDB_AGENT_USER"] ?? "PELIKAN_AGENT",
                      agentPassword: env["PELIKAN_TESTDB_AGENT_PASSWORD"] ?? "",
                      systemPassword: env["PELIKAN_TESTDB_SYSTEM_PASSWORD"] ?? "",
                      sshPort: env["PELIKAN_TESTDB_SSH_PORT"].flatMap(Int.init), sshDBHost: env["PELIKAN_TESTDB_SSH_DBHOST"],
                      sshDirectory: envFile().map { ($0 as NSString).deletingLastPathComponent + "/ssh" })
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

    static func connect(agent: Bool = false, tags: SessionTags = SessionTags(module: "Pelikan tests")) async throws -> ODPISession {
        guard let c = config else { throw DatabaseError.driverUnavailable("Brak konfiguracji bazy testowej (scripts/testdb.sh up)") }
        let target = ConnectionTarget(user: agent ? c.agentUser : c.user, connectString: c.connectString)
        return try await ODPISession.connect(target: target, credentials: Credentials(password: agent ? c.agentPassword : c.password),
                                             options: ConnectOptions(tags: tags))
    }
}
