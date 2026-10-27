import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Plik tylko dla właściciela (0600) od chwili utworzenia (D186): zapis do pliku tymczasowego utworzonego z prawami 0600
/// w katalogu docelowym, potem zamiana nazwy — treść nigdy nie leży w pliku czytelnym dla innych użytkowników Maca.
public enum PrivateFile {
    /// Zapisuje dane atomowo. Zwraca false, gdy system plików nie przechowuje praw POSIX (exFAT, FAT, część udziałów
    /// sieciowych) i plik po zapisie nie ma praw 0600 — decyzję, czy go zostawić, podejmuje wywołujący.
    @discardableResult
    public static func write(_ data: Data, to url: URL) throws -> Bool {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8)).tmp")
        let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Prawa dokładnie 0600 także przy nietypowej masce procesu.
        _ = fchmod(fd, 0o600)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            unlink(temporary.path)
            throw error
        }
        let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
        return permissions.map { $0 & 0o777 == 0o600 } ?? false
    }
}
