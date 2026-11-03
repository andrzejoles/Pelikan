#if canImport(Darwin)
import Darwin

/// Obiekt systemu plików tylko dla użytkownika: jego własność, właściwy rodzaj (nie dowiązanie) i bez praw dla innych
/// (katalog gniazd SSH, plik śladu MCP, katalog gniazda agentów).
public enum PrivateOwnership {
    /// Należy do bieżącego użytkownika i ma rodzaj `type` (`S_IFDIR`, `S_IFREG`).
    public static func ownedByUser(_ st: stat, type: mode_t) -> Bool {
        st.st_mode & S_IFMT == type && st.st_uid == getuid()
    }

    /// Jak `ownedByUser`, bez żadnych praw dla grupy i innych.
    public static func isPrivate(_ st: stat, type: mode_t) -> Bool {
        ownedByUser(st, type: type) && st.st_mode & 0o077 == 0
    }

    /// Katalog użytkownika (nie dowiązanie) bez praw dla innych.
    public static func isPrivateDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && isPrivate(st, type: S_IFDIR)
    }

    /// Stan katalogu (bez podążania za dowiązaniem), gdy to katalog użytkownika; nil — brak, dowiązanie albo cudzy.
    public static func ownedDirectory(_ path: String) -> stat? {
        var st = stat()
        guard lstat(path, &st) == 0, ownedByUser(st, type: S_IFDIR) else { return nil }
        return st
    }
}
#endif
