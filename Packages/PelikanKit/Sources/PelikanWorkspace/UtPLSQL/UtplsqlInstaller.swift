import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PelikanDB
import PelikanLog

/// Instalacja i aktualizacja utPLSQL z oficjalnego wydania (UT-INS-002): archiwum i suma SHA-256 z wydań projektu
/// na GitHubie, skrypty instalatora wykonywane silnikiem Command Window. Tylko połączenia deweloperskie i testowe,
/// zawsze po potwierdzeniu.
public enum UtplsqlInstaller {
    public struct Release: Sendable, Equatable {
        public var version: String
        public var archive: URL
    }

    static let releases = "https://github.com/utPLSQL/utPLSQL/releases"

    /// Wydanie: wskazana wersja (np. `v3.2.01`) albo najnowsze (przekierowanie `releases/latest` → znacznik).
    public static func release(version: String? = nil) async throws -> Release {
        var tag = version
        if tag == nil {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/utPLSQL/utPLSQL/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            tag = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["tag_name"] as? String
        }
        guard let tag, !tag.isEmpty, tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) else {
            throw CommandError.notAvailable(L10n.tr("Nie udało się ustalić wersji utPLSQL do pobrania"))
        }
        return Release(version: tag, archive: URL(string: "\(releases)/download/\(tag)/utPLSQL.tar.gz")!)
    }

    /// Pobiera i rozpakowuje wydanie do `cache/<wersja>` (gdy go tam nie ma); zwraca katalog `source` instalatora.
    /// Archiwum bez zgodnej sumy kontrolnej wydania jest odrzucane (SHA-256; starsze wydania mają tylko MD5).
    public static func prepare(_ r: Release, cache: URL) async throws -> URL {
        let dir = cache.appendingPathComponent(r.version, isDirectory: true)
        let source = dir.appendingPathComponent("utPLSQL/source", isDirectory: true)
        if FileManager.default.fileExists(atPath: source.appendingPathComponent("install.sql").path) { return source }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (archive, _) = try await URLSession.shared.data(from: r.archive)
        guard try await checksumMatches(archive, release: r) else { throw CommandError.notAvailable(L10n.tr("Błędna suma kontrolna archiwum utPLSQL \(r.version)")) }
        let file = dir.appendingPathComponent("utPLSQL.tar.gz")
        try archive.write(to: file)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", file.path, "-C", dir.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0, FileManager.default.fileExists(atPath: source.appendingPathComponent("install.sql").path) else {
            throw CommandError.notAvailable(L10n.tr("Nie udało się rozpakować archiwum utPLSQL"))
        }
        return source
    }

    static func checksumMatches(_ archive: Data, release r: Release) async throws -> Bool {
        for (ext, digest) in [("sha256", sha256(archive)), ("md5", md5(archive))] {
            let (sum, response) = try await URLSession.shared.data(from: r.archive.appendingPathExtension(ext))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            // Format GNU („suma  plik”) albo BSD („SHA256 (plik) = suma”): szukany token szesnastkowy długości skrótu.
            let tokens = String(decoding: sum, as: UTF8.self).lowercased().split { !$0.isHexDigit }
            return tokens.contains { $0.count == digest.count && $0 == digest }
        }
        return false
    }

    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Wykonuje kroki instalatora w oknie poleceń (wyjście w konsoli dokumentu); `true` — bez błędów. Skrypty
    /// instalatora kończą się EXIT, więc każdy krok to osobne uruchomienie (EXIT kończy krok, nie instalację).
    @MainActor
    public static func run(_ steps: [String], source: URL, engine: SQLPlusEngine) async -> Bool {
        engine.state.installerDirectory = source
        engine.state.directory = source
        defer {
            engine.state.installerDirectory = nil
            for log in ["install.log", "uninstall.log", "params.sql.tmp"] { try? FileManager.default.removeItem(at: source.appendingPathComponent(log)) }
        }
        let before = engine.document.console.count
        for (i, step) in steps.enumerated() {
            let outcome = await engine.run(step, baseDirectory: source)
            if outcome == .stopped || engine.document.console.dropFirst(before).contains(where: { $0.kind == .error }) {
                Log.tests.notice("utPLSQL: instalator przerwany na kroku \(i + 1) z \(steps.count)")
                return false
            }
        }
        Log.tests.info("utPLSQL: instalator zakończony (\(steps.count) kroków)")
        return true
    }

    /// Właściciel zainstalowanego utPLSQL (schemat pakietu UT_RUNNER) albo nil.
    public static func installedOwner(_ s: any DatabaseSession) async -> String? {
        try? await s.scalar("select owner from all_objects where object_name = 'UT_RUNNER' and object_type = 'PACKAGE' and rownum = 1")
    }

    /// Skrypt instalatora: nowa instalacja — `install_headless.sql` (schemat, publiczne synonimy i granty) z losowym
    /// hasłem właściciela, po czym konto jest blokowane (utPLSQL nie loguje się jako właściciel; hasło nigdzie nie
    /// trafia); aktualizacja — `uninstall.sql` i `install.sql` w istniejącym schemacie oraz synonimy i granty publiczne.
    /// `publicSynonyms: false` — instalacja bez publicznych synonimów (np. druga wersja obok).
    nonisolated public static func script(owner: String, upgrade: Bool, tablespace: String = "USERS", publicSynonyms: Bool = true) -> [String] {
        let o = owner.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
        if upgrade {
            return ["@@uninstall.sql \(o)", "@@install.sql \(o)"] + (publicSynonyms ? ["@@create_synonyms_and_grants_for_public.sql \(o)"] : [])
        }
        let password = "U" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24)
        let ts = tablespace.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
        if publicSynonyms {
            return ["@@install_headless.sql \(o) \(password) \(ts)", "alter user \(o) account lock;"]
        }
        return ["@@create_utplsql_owner.sql \(o) \(password) \(ts)", "alter user \(o) account lock;", "@@install.sql \(o)"]
    }
}
