import Foundation
import PelikanDB
import PelikanLog

extension Workspace {
    /// Dziennik do zgłoszenia błędu (PL-INFRA-011): nagłówek ze środowiskiem (bez nazw połączeń i ścieżek) i pliki
    /// dziennika od najstarszego. Treść plików jest już po nałożeniu widoczności z chwili zapisu.
    public func logExport(now: Date = Date()) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let drivers = DriverKind.allCases.map { kind -> String in
            guard let d = sessions.driver(for: kind) else { return "\(kind.rawValue): brak" }
            if case .failure = d.availability() { return "\(kind.rawValue): niedostępny" }
            return "\(kind.rawValue): dostępny"
        }
        var out = """
        Pelikan — dziennik aplikacji (eksport \(now.formatted(.iso8601)))
        Wersja: \(version) (\(build))
        System: \(osVersion), \(arch)
        Dziennik: poziom \(settings.logLevel.rawValue), nazwy \(settings.logIncludeNames ? "jawne" : "ukryte")
        Sterowniki: \(drivers.joined(separator: ", "))
        Połączenia: \(connections.connections.count), tryb sesji: \(settings.sessionMode.rawValue)

        """
        guard let sink = Log.fileSink else { return out + "(dziennik nie jest zapisywany do pliku)\n" }
        sink.flush()
        for f in sink.files {
            out += "\n===== \(f.lastPathComponent) =====\n"
            out += (try? String(contentsOf: f, encoding: .utf8)) ?? "(nie można odczytać)\n"
        }
        return out
    }
}
