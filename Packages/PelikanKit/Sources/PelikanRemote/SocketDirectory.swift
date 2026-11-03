// Pochodzi z BiFold (BifoldWorkspace/Remote/RemoteManager.swift @ a1ee643), dalej rozwijany w Pelikanie.
#if canImport(Darwin)
import Darwin
import Foundation

/// Katalog gniazd ControlMaster: ścieżka gniazda (`ssh-<skrót>` w katalogu + dopiski `ssh`) nie może przekroczyć
/// limitu `sun_path` (104 bajty). Gdy katalog preferowany (np. `~/Library/Application Support/…/run`) jest za długi —
/// prywatny katalog w `/tmp` (0700).
public enum SocketDirectory {
    /// Zapas na nazwę gniazda i przyrostek tymczasowy, który `ssh` dokleja przy tworzeniu.
    static let reserve = 40

    public static func make(preferred: URL) throws -> URL {
        if preferred.path.utf8.count + reserve <= 100 {
            try FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            chmod(preferred.path, 0o700)
            return preferred
        }
        let dir = URL(fileURLWithPath: "/tmp/pelikan-\(getuid())-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return dir
    }
}
#endif
