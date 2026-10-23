import Foundation

/// Błąd warstwy SSH/SCP z przypadkami strukturalnymi — teksty dla użytkownika tworzy warstwa interfejsu Pelikana
/// (lokalizacja przez `L10n.tr`), tutaj tylko surowy komunikat narzędzia w `detail`.
public enum SSHError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Brak wspólnych algorytmów (stary serwer bez trybu zgodności).
    case negotiationFailed(String)
    /// Odmowa dostępu (użytkownik, hasło, klucz).
    case permissionDenied(String)
    /// Klucz serwera inny niż zapamiętany w known_hosts.
    case hostKeyChanged(String)
    /// Przekroczony limit czasu (całkowity albo ciszy).
    case timeout
    case cancelled
    /// Błąd systemowy (`errno`) albo inny komunikat `ssh`/`scp`.
    case io(code: Int32, detail: String)
    /// Nazwa, host albo użytkownik, których nie wolno przekazać (wstrzyknięcie opcji, znaki sterujące).
    case invalidName(String)
    /// Tekstu nie da się zapisać w kodowaniu serwera (np. „😀” w ISO-8859-2).
    case unencodable(String)

    public var description: String {
        switch self {
        case .negotiationFailed(let m): "negotiation failed: \(m)"
        case .permissionDenied(let m): "permission denied: \(m)"
        case .hostKeyChanged(let m): "host key changed: \(m)"
        case .timeout: "timeout"
        case .cancelled: "cancelled"
        case .io(let code, let detail): "io(\(code)): \(detail)"
        case .invalidName(let n): "invalid name: \(n)"
        case .unencodable(let s): "unencodable: \(s)"
        }
    }
}
