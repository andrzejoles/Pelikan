import Foundation

/// Wykluczenie tworzenia deskryptorów i uruchamiania procesów przez fork bez zamykania deskryptorów.
///
/// macOS nie ma `pipe2` ani `accept4`: FD_CLOEXEC ustawia się osobnym `fcntl` tuż po utworzeniu deskryptora. Terminal
/// agenta startuje przez `forkpty`+`execve` (SwiftTerm) bez zamykania deskryptorów — proces potomny utworzony między
/// `pipe`/`accept` a `fcntl` odziedziczyłby deskryptor (brak EOF potoku `ssh`, dostęp do gniazda agentów). Utworzenie
/// deskryptora z ustawieniem FD_CLOEXEC i start takiego procesu wykonują się pod tą blokadą.
public enum DescriptorLock {
    private static let lock = NSLock()

    public static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
