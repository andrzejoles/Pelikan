#if canImport(Darwin)
import Darwin
import Foundation

/// Wykluczenie tworzenia deskryptorów i uruchamiania procesów przez fork bez zamykania deskryptorów.
///
/// macOS nie ma `pipe2` ani `accept4`: FD_CLOEXEC ustawia się osobnym `fcntl` tuż po utworzeniu deskryptora. Terminal
/// agenta startuje przez `forkpty`+`execve` (SwiftTerm) bez zamykania deskryptorów. Start terminala:
/// `markAllCloseOnExec` (wszystkie otwarte deskryptory aplikacji — także tworzone przez Foundation, OCI, pliki — dostają
/// FD_CLOEXEC, więc CLI agenta nie dziedziczy żadnego) i `forkpty` pod tą blokadą; miejsca tworzące deskryptory dla
/// procesów potomnych (potoki `ssh`, gniazdo agentów) — utworzenie z FD_CLOEXEC też pod nią, bez okna między nimi.
public enum DescriptorLock {
    private static let lock = NSLock()

    public static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// FD_CLOEXEC na wszystkich otwartych deskryptorach powyżej 2 (przed `forkpty`+`execve` bez zamykania deskryptorów).
    /// Deskryptory przekazywane procesom przez `posix_spawn`/`Process` trafiają do nich przez dup2 na 0/1/2 — bez zmian.
    public static func markAllCloseOnExec() {
        let limit = min(Int32(getdtablesize()), 65_536)
        guard limit > 3 else { return }
        for fd in 3..<limit {
            let flags = fcntl(fd, F_GETFD)
            if flags >= 0, flags & FD_CLOEXEC == 0 { _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC) }
        }
    }
}
#endif
