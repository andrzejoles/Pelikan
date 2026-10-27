import Foundation
import PelikanLog

/// Plik danych, którego nie da się odczytać (uszkodzony, poprawiony ręcznie albo z nowszej wersji aplikacji): przeniesiony
/// obok jako `<nazwa>.bad-<data>`, żeby pierwszy zapis pustej listy go nie nadpisał (R6-11, R8-08).
public enum DamagedFile {
    /// Przenosi plik do kopii i zwraca komunikat dla użytkownika. `preserved == false` — nie udało się przenieść pliku;
    /// magazyn nie może wtedy zapisywać w jego miejsce.
    public static func preserve(_ url: URL, now: Date = Date()) -> (message: String, preserved: Bool) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let bad = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".bad-" + f.string(from: now))
        do {
            try FileManager.default.moveItem(at: url, to: bad)
            Log.app.error("Nieczytelny plik danych \(url.lastPathComponent, privacy: .hash) przeniesiony do kopii")
            return (L10n.tr("Plik „\(url.lastPathComponent)” jest uszkodzony albo pochodzi z nowszej wersji aplikacji — zachowano go jako „\(bad.lastPathComponent)”."), true)
        } catch {
            Log.app.error("Nieczytelny plik danych \(url.lastPathComponent, privacy: .hash), kopia nieudana: \(error)")
            return (L10n.tr("Plik „\(url.lastPathComponent)” jest uszkodzony albo pochodzi z nowszej wersji aplikacji — zmiany nie będą w nim zapisywane."), false)
        }
    }
}
