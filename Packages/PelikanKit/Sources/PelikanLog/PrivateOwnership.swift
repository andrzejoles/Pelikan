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

    /// Katalog prywatny gotowy do użycia: tworzony z 0700, gdy go brak; własny z innymi prawami — poprawiony na 0700;
    /// cudzy albo dowiązanie — false (wywołujący wybiera inne miejsce albo zgłasza błąd).
    public static func ensurePrivateDirectory(_ path: String) -> Bool {
        var st = stat()
        if lstat(path, &st) != 0 {
            guard mkdir(path, 0o700) == 0 || errno == EEXIST, lstat(path, &st) == 0 else { return false }
        }
        guard ownedByUser(st, type: mode_t(S_IFDIR)) else { return false }
        if st.st_mode & 0o777 != 0o700 { chmod(path, 0o700) }
        return isPrivateDirectory(path)
    }

    /// Katalog użytkownika (nie dowiązanie) bez praw dla innych.
    public static func isPrivateDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && isPrivate(st, type: mode_t(S_IFDIR))
    }
}
