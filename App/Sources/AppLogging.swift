import AppKit
import PelikanLog
import PelikanWorkspace
import Sparkle

/// Dziennik aplikacji (PL-INFRA-011, D170): plik `~/Library/Logs/<nazwa>/<nazwa>.log` z rotacją i dziennik systemowy
/// macOS (podsystem = bundle id, widoczny w Konsoli). Przy `PELIKAN_DATA_DIR` (testy interfejsu, zrzuty) plik trafia
/// do `Logs` w tym katalogu.
@MainActor
enum AppLogging {
    static func start(appName: String, dataDirectoryOverride: URL?) {
        let directory = dataDirectoryOverride?.appendingPathComponent("Logs", isDirectory: true)
            ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Logs", isDirectory: true).appendingPathComponent(appName, isDirectory: true)
        Log.setHashKey(hashKey())
        Log.setSinks([FileLogSink(directory: directory, baseName: appName),
                      UnifiedLogSink(subsystem: Bundle.main.bundleIdentifier ?? appName)])
    }

    /// Poziom i nazwy z Preferencji (Ogólne › Dziennik aplikacji).
    static func apply(_ settings: Settings) {
        Log.configure(level: settings.logLevel, revealPrivate: settings.logIncludeNames)
    }

    /// Pierwszy wpis uruchomienia: wersja, system, architektura, język — bez ścieżek i nazw.
    static func logStartup() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        Log.app.notice("Start \(version, privacy: .public) (\(build, privacy: .public), \(configuration, privacy: .public)), macOS \(os, privacy: .public), język \(Locale.preferredLanguages.first ?? "?", privacy: .public)")
    }

    /// Klucz skrótów nazw w dzienniku — losowy, raz na instalację (bez niego skrót dałoby się odwrócić słownikiem nazw).
    static func hashKey() -> [UInt8] {
        let defaults = UserDefaults.standard
        let name = "PelikanLogKey"
        if let data = defaults.data(forKey: name), data.count == 32 { return Array(data) }
        var generator = SystemRandomNumberGenerator()
        let key = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        defaults.set(Data(key), forKey: name)
        return key
    }
}

/// Zdarzenia aktualizacji Sparkle w dzienniku (PL-INFRA-007).
final class UpdaterLogDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.update.info("Dostępna aktualizacja \(item.displayVersionString, privacy: .public)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.update.info("Brak nowszej wersji")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Log.update.notice("Instalacja aktualizacji \(item.displayVersionString, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        // „Brak aktualizacji” Sparkle też zgłasza jako przerwanie — ten przypadek ma własny wpis.
        let ns = error as NSError
        guard !(ns.domain == SUSparkleErrorDomain && ns.code == Int(SUError.noUpdateError.rawValue)) else { return }
        Log.update.notice("Aktualizacja przerwana: \(error)")
    }
}
