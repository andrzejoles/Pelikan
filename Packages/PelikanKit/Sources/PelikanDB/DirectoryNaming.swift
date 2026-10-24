import Foundation

/// Nazewnictwo katalogowe Oracle Net (LDAP, PD-CONN-013): konfiguracja z `ldap.ora` i `sqlnet.ora` katalogu TNS_ADMIN
/// oraz kolejność metod rozwiązywania nazw. Samo zapytanie do serwera wykonuje sterownik (D-ENV-3).
public enum DirectoryNaming {
    public struct Server: Sendable, Equatable {
        public var host: String
        public var port: Int
        public init(host: String, port: Int) { self.host = host; self.port = port }
    }

    public struct Config: Sendable, Equatable {
        /// Katalog, z którego pochodzi konfiguracja (TNS_ADMIN).
        public var directory: String
        /// Serwery z DIRECTORY_SERVERS — port bez SSL (pierwszy z `host:port[:portSSL]`).
        public var servers: [Server]
        public var adminContext: String?
        /// NAMES.DIRECTORY_PATH małymi literami (`hostname` jako `ezconnect`).
        public var path: [String]
    }

    /// Domyślna kolejność metod, gdy sqlnet.ora jej nie podaje (Net Services Reference, NAMES.DIRECTORY_PATH).
    public static let defaultPath = ["tnsnames", "ezconnect", "ldap"]

    /// Pierwszy z katalogów z `ldap.ora`, w którym kolejność metod obejmuje LDAP; nil — nazewnictwo katalogowe wyłączone.
    public static func config(directories: [String]) -> Config? {
        for raw in directories where !raw.isEmpty {
            let dir = (raw as NSString).expandingTildeInPath
            let ldap = dir + "/ldap.ora"
            guard FileManager.default.fileExists(atPath: ldap) else { continue }
            let path = directoryPath(sqlnetFile: dir + "/sqlnet.ora")
            guard path.contains("ldap") else { return nil }
            let entries = TNSNames.load(file: ldap)
            func value(_ key: String) -> String? {
                entries.first { $0.aliases.count == 1 && $0.aliases[0].caseInsensitiveCompare(key) == .orderedSame }?.descriptor
            }
            let servers = value("DIRECTORY_SERVERS").map(Self.servers) ?? []
            guard !servers.isEmpty else { return nil }
            let context = value("DEFAULT_ADMIN_CONTEXT").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            return Config(directory: dir, servers: servers, adminContext: context?.isEmpty == false ? context : nil, path: path)
        }
        return nil
    }

    /// NAMES.DIRECTORY_PATH z sqlnet.ora (z plikami IFILE); bez parametru — kolejność domyślna.
    public static func directoryPath(sqlnetFile: String) -> [String] {
        let entries = FileManager.default.fileExists(atPath: sqlnetFile) ? TNSNames.load(file: sqlnetFile) : []
        guard let raw = entries.last(where: { $0.aliases.count == 1 && $0.aliases[0].uppercased() == "NAMES.DIRECTORY_PATH" })?.descriptor else {
            return defaultPath
        }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "() \t"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { $0 == "hostname" ? "ezconnect" : $0 }
            .filter { !$0.isEmpty }
    }

    /// `(host:port[:portSSL], host2:port)` → serwery.
    static func servers(_ value: String) -> [Server] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "() \t\"")).split(separator: ",").compactMap { item in
            let parts = item.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
            guard let host = parts.first, !host.isEmpty else { return nil }
            return Server(host: host, port: parts.count > 1 ? Int(parts[1]) ?? 389 : 389)
        }
    }

    /// Nazwa w postaci aliasu (bez deskryptora, EZConnect, ścieżki i spacji) — kandydat do rozwiązania przez katalog.
    public static func isBareAlias(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.rangeOfCharacter(from: CharacterSet(charactersIn: "()/:@= \t\n")) == nil
    }

    /// DN wpisu usługi: `alias` → `cn=alias,cn=OracleContext,<kontekst>`; nazwa z kropkami (`alias.dc1.dc2`) —
    /// `cn=alias,cn=OracleContext,dc=dc1,dc=dc2` (pełna nazwa w drzewie domen).
    public static func distinguishedName(alias: String, context: String?) -> String? {
        let parts = alias.split(separator: ".").map { escapeRDN(String($0)) }
        guard let cn = parts.first else { return nil }
        if parts.count > 1 { return "cn=\(cn),cn=OracleContext," + parts.dropFirst().map { "dc=\($0)" }.joined(separator: ",") }
        guard let context else { return nil }
        return "cn=\(cn),cn=OracleContext,\(context)"
    }

    /// Znaki specjalne wartości RDN (RFC 4514).
    static func escapeRDN(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.enumerated() {
            if ",+\"\\<>;=".contains(ch) || (i == 0 && (ch == "#" || ch == " ")) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
