import Foundation
import PelikanDB
import PelikanLog

extension Workspace {
    /// Dziennik do zgłoszenia błędu (PL-INFRA-011): nagłówek ze środowiskiem (bez nazw połączeń i ścieżek) i pliki
    /// dziennika od najstarszego. Treść plików jest już po nałożeniu widoczności z chwili zapisu.
    public func logExport(now: Date = Date()) -> String {
        var out = "Pelikan — dziennik aplikacji (eksport \(now.formatted(.iso8601)))\n" + environmentSummary() + "\n\n"
        guard let sink = Log.fileSink else { return out + "(dziennik nie jest zapisywany do pliku)\n" }
        sink.flush()
        for f in sink.files {
            out += "\n===== \(f.lastPathComponent) =====\n"
            out += (try? String(contentsOf: f, encoding: .utf8)) ?? "(nie można odczytać)\n"
        }
        return out
    }
}
