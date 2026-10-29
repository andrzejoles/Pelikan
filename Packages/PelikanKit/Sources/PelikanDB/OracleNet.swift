import Foundation

/// Stan katalogu portfela Oracle (wallet).
public enum WalletStatus: Sendable, Equatable {
    /// `cwallet.sso` — portfel z automatycznym logowaniem (wymagany przez klienta bez podawania hasła portfela).
    case autoLogin
    /// Tylko `ewallet.p12` — klient nie otworzy go bez hasła portfela; trzeba utworzyć auto-login (`orapki`/`mkstore`).
    case passwordOnly
    case missing
}

/// Konfiguracja Oracle Net zarządzana przez Pelikana (UG 19.2, D53): katalog przekazywany klientowi jako TNS_ADMIN
/// przy inicjalizacji, z `sqlnet.ora` wskazującym portfel magazynu haseł (Secure External Password Store) i z
/// dołączeniem (`IFILE`) plików `sqlnet.ora`/`tnsnames.ora` z katalogu użytkownika.
public enum OracleNet {
    public static func walletStatus(_ directory: String?) -> WalletStatus {
        guard let d = directory.map({ ($0 as NSString).expandingTildeInPath }), !d.isEmpty else { return .missing }
        if FileManager.default.fileExists(atPath: d + "/cwallet.sso") { return .autoLogin }
        if FileManager.default.fileExists(atPath: d + "/ewallet.p12") { return .passwordOnly }
        return .missing
    }

    /// Ścieżka w cudzysłowie dla plików Oracle Net (spacje w ścieżkach).
    static func quoted(_ path: String) -> String { "\"" + path.replacingOccurrences(of: "\"", with: "") + "\"" }

    /// Zapisuje katalog zarządzany; zwraca jego ścieżkę albo nil, gdy nic nie skonfigurowano (klient korzysta wtedy
    /// z TNS_ADMIN/domyślnych miejsc). Pliki bez sekretów — tylko ścieżki.
    @discardableResult
    public static func prepareManagedDirectory(_ dir: URL, userDirectory: String?, walletDirectory: String?) throws -> String? {
        let user = userDirectory.map { ($0 as NSString).expandingTildeInPath }.flatMap { $0.isEmpty ? nil : $0 }
        let wallet = walletDirectory.map { ($0 as NSString).expandingTildeInPath }.flatMap { $0.isEmpty ? nil : $0 }
        guard user != nil || wallet != nil else { return nil }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var sqlnet = "# " + "Pelikan — plik generowany; zmiany w Ustawieniach › Oracle Net" + "\n"
        if let u = user, FileManager.default.fileExists(atPath: u + "/sqlnet.ora") { sqlnet += "IFILE=\(quoted(u + "/sqlnet.ora"))\n" }
        if let w = wallet {
            sqlnet += "WALLET_LOCATION=(SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY=\(quoted(w)))))\n"
            sqlnet += "SQLNET.WALLET_OVERRIDE=TRUE\n"
        }
        try sqlnet.write(to: dir.appendingPathComponent("sqlnet.ora"), atomically: true, encoding: .utf8)
        var tns = "# Pelikan\n"
        if let u = user, FileManager.default.fileExists(atPath: u + "/tnsnames.ora") { tns += "IFILE=\(quoted(u + "/tnsnames.ora"))\n" }
        try tns.write(to: dir.appendingPathComponent("tnsnames.ora"), atomically: true, encoding: .utf8)
        // Nazewnictwo katalogowe (LDAP, PD-CONN-013): klient czyta ldap.ora tylko z TNS_ADMIN i bez IFILE — dowiązanie
        // do pliku użytkownika (NAMES.DIRECTORY_PATH przychodzi z jego sqlnet.ora przez IFILE).
        let ldap = dir.appendingPathComponent("ldap.ora")
        try? FileManager.default.removeItem(at: ldap)
        if let u = user, FileManager.default.fileExists(atPath: u + "/ldap.ora") {
            try FileManager.default.createSymbolicLink(atPath: ldap.path, withDestinationPath: u + "/ldap.ora")
        }
        return dir.path
    }
}
