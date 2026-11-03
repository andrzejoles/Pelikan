#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Obiekt systemu plików tylko dla użytkownika: jego własność, właściwy rodzaj (nie dowiązanie) i bez praw dla innych
/// (katalog gniazd SSH, plik śladu MCP, katalog gniazda agentów; w PelikanLog — moduł, od którego zależą obie warstwy).
public enum PrivateOwnership {
    /// Należy do bieżącego użytkownika i ma rodzaj `type` (`S_IFDIR`, `S_IFREG`).
    public static func ownedByUser(_ st: stat, type: mode_t) -> Bool {
        st.st_mode & mode_t(S_IFMT) == type && st.st_uid == getuid()
    }

    /// Jak `ownedByUser`, bez żadnych praw dla grupy i innych.
    public static func isPrivate(_ st: stat, type: mode_t) -> Bool {
        ownedByUser(st, type: type) && st.st_mode & 0o077 == 0
    }

    /// Katalog użytkownika (nie dowiązanie) bez praw dla innych.
    public static func isPrivateDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && isPrivate(st, type: mode_t(S_IFDIR))
    }
}
