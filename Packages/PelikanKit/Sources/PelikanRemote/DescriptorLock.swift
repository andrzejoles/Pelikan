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
    /// Tylko otwarte deskryptory (`proc_pidinfo` PROC_PIDLISTFDS), nie każdy numer do limitu procesu.
    public static func markAllCloseOnExec() {
        for fd in openDescriptors() where fd > 2 {
            let flags = fcntl(fd, F_GETFD)
            if flags >= 0, flags & FD_CLOEXEC == 0 { _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC) }
        }
    }

    /// Numery otwartych deskryptorów procesu.
    public static func openDescriptors() -> [Int32] {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let needed = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        // Zapas na deskryptory otwarte między pytaniem o rozmiar a odczytem.
        var infos = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 32)
        let got = infos.withUnsafeMutableBytes { proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard got > 0 else { return [] }
        return infos.prefix(Int(got) / stride).map(\.proc_fd)
    }
}

/// Obiekt systemu plików tylko dla użytkownika: jego własność, właściwy rodzaj (nie dowiązanie) i bez praw dla innych
/// (katalog gniazd, plik śladu MCP, katalog gniazda agentów).
public enum PrivateOwnership {
    /// Należy do bieżącego użytkownika i ma rodzaj `type` (`S_IFDIR`, `S_IFREG`).
    public static func ownedByUser(_ st: stat, type: mode_t) -> Bool {
        st.st_mode & S_IFMT == type && st.st_uid == getuid()
    }

    /// Jak `ownedByUser`, bez żadnych praw dla grupy i innych.
    public static func isPrivate(_ st: stat, type: mode_t) -> Bool {
        ownedByUser(st, type: type) && st.st_mode & 0o077 == 0
    }
}
#endif
