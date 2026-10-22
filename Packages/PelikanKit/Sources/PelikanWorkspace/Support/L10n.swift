import Foundation
import Synchronization

/// Teksty interfejsu. Kluczem jest polskie zdanie (język źródłowy); tłumaczenia leżą w `Localizable.xcstrings`
/// celu aplikacji. Brak tłumaczenia = polski tekst. Na Linuksie (CI warstwy bazy) — zawsze polski tekst.
public enum L10n {
    private static let selected = Mutex<Bundle?>(nil)

#if canImport(Darwin)
    public static func tr(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: selected.withLock { $0 } ?? .main)
    }
#else
    public static func tr(_ key: String) -> String { key }
#endif

    /// Katalog `.lproj` języka wybranego w ustawieniach (`nil` = język systemu przez `Bundle.main`).
    public static func use(_ bundle: Bundle?) {
        selected.withLock { $0 = bundle }
    }
}
