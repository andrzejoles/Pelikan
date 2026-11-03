import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Kanał hasła SSH bez sekretu w plikach, argumentach i środowisku: skrypt `SSH_ASKPASS` czyta hasło z kolejki FIFO
/// (ścieżka w zmiennej środowiska), wątek zapisuje je tam raz. Wspólne dla połączeń SSH celów (PelikanRemote, macOS)
/// i tuneli SSH połączeń z bazą (PelikanWorkspace, także Linux) — w PelikanLog, od którego zależą oba moduły.
public enum Askpass {
    static let script = Data("#!/bin/sh\nexec /bin/cat -- \"$PELIKAN_ASKPASS_FIFO\"\n".utf8)

    /// Skrypt zapisany tylko, gdy go brak albo ma inną treść, przez plik tymczasowy z prawami 0700 zamieniony nazwą —
    /// równoległe logowanie nigdy nie wykona skryptu w trakcie zapisu ani bez prawa wykonania.
    public static func installScript(at path: String) throws {
        if FileManager.default.contents(atPath: path) == script, FileManager.default.isExecutableFile(atPath: path) { return }
        let temp = path + ".\(UUID().uuidString.prefix(8)).tmp"
        guard FileManager.default.createFile(atPath: temp, contents: script, attributes: [.posixPermissions: 0o700]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        chmod(temp, 0o700)
        guard rename(temp, path) == 0 else {
            unlink(temp)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Wątek, który zapisze hasło do kolejki raz (gdy `ssh` otworzy ją do odczytu) albo zakończy się, gdy `done()`.
    /// Deskryptor z O_CLOEXEC (atomowo) — proces potomny uruchomiony w tej chwili nie odziedziczy kanału hasła.
    public static func startWriter(fifo: String, secret: String, done: @escaping @Sendable () -> Bool) {
        let bytes = Array((secret + "\n").utf8)
        Thread.detachNewThread {
            while !done() {
                let fd = open(fifo, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
                if fd >= 0 {
                    _ = fcntl(fd, F_SETFL, 0)
                    bytes.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
                    close(fd)
                    unlink(fifo)
                    return
                }
                usleep(20_000)
            }
        }
    }
}
