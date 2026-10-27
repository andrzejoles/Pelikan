#if canImport(Darwin)
import Foundation
import PelikanRemote
import PelikanWorkspace

/// Stan lokalnego repo projektu względem remote celu (zadanie Pro*C, „Integracja z gitem (lokalnie)”).
public struct LocalGitStatus: Sendable, Hashable {
    public var branch: String
    /// Linie `git status --porcelain` (niezatwierdzone i nieśledzone pliki).
    public var uncommitted: [String]
    /// Commity lokalne niewypchnięte / brakujące lokalnie względem `<remote>/<gałąź>` (nil — brak gałęzi remote).
    public var ahead: Int?
    public var behind: Int?
    public var remoteHead: String?

    /// Ostrzeżenia przed wdrożeniem (wdrożenie bierze stan z GitLaba, nie z Maca).
    public var warnings: [String] {
        var w: [String] = []
        if !uncommitted.isEmpty { w.append(L10n.tr("Niezatwierdzone zmiany lokalnie: \(uncommitted.count) plików — nie trafią na serwer")) }
        if let a = ahead, a > 0 { w.append(L10n.tr("Commity niewypchnięte na remote: \(a) — nie trafią na serwer")) }
        if ahead == nil { w.append(L10n.tr("Brak gałęzi remote w lokalnym repo — wykonaj git fetch")) }
        return w
    }
}

/// Lokalny `git` w katalogu projektu — przez `Spawn` (posix_spawn), nigdy `Foundation.Process`. Pelikan nie robi
/// `push` ani zmian w repo: tylko odczyt i `fetch`.
public enum LocalGit {
    public static let executable = "/usr/bin/git"

    /// Środowisko procesu: bez pytań o hasło w terminalu, komunikaty po angielsku (parsowanie), agent SSH użytkownika.
    static var environment: [String: String] {
        let env = ProcessInfo.processInfo.environment
        var out = ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C", "PATH": env["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"]
        for k in ["HOME", "USER", "SSH_AUTH_SOCK", "TMPDIR"] { if let v = env[k] { out[k] = v } }
        return out
    }

    public static func run(_ repo: URL, _ args: [String], timeout: TimeInterval = 60) throws -> Spawn.Result {
        try Spawn.run(executable, (["-C", repo.path] + args).map { Array($0.utf8) }, environment: environment, timeout: timeout)
    }

    static func text(_ r: Spawn.Result) -> String {
        String(decoding: r.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stan repo względem `<remote>/<gałąź>` (bez `fetch`).
    public static func status(repo: URL, remote: String, branch: String) throws -> LocalGitStatus {
        try checkNames(remote, branch)
        let b = try run(repo, ["rev-parse", "--abbrev-ref", "HEAD"])
        guard b.status == 0 else { throw CommandError.notAvailable(L10n.tr("To nie jest repozytorium git: \(b.errorText)")) }
        let porcelain = text(try run(repo, ["status", "--porcelain"]))
        var s = LocalGitStatus(branch: text(b), uncommitted: porcelain.isEmpty ? [] : porcelain.components(separatedBy: "\n"))
        let ref = "\(remote)/\(branch)"
        let head = try run(repo, ["rev-parse", "--verify", "--quiet", "--end-of-options", ref])
        if head.status == 0 {
            s.remoteHead = text(head)
            let counts = text(try run(repo, ["rev-list", "--left-right", "--count", "HEAD...\(ref)"])).split(whereSeparator: \.isWhitespace)
            if counts.count == 2 { s.ahead = Int(counts[0]); s.behind = Int(counts[1]) }
        }
        return s
    }

    /// `git fetch <remote>` (dane logowania z konfiguracji gita użytkownika; bez pytań w terminalu).
    public static func fetch(repo: URL, remote: String) throws {
        try checkNames(remote)
        let r = try run(repo, ["fetch", "--quiet", "--", remote], timeout: 180)
        guard r.status == 0 else { throw CommandError.notAvailable(L10n.tr("git fetch: \(r.errorText)")) }
    }

    /// Nazwy remote i gałęzi z celu (także zaimportowanego) — nigdy jako opcje gita (R8-09).
    static func checkNames(_ names: String...) throws {
        for n in names where !PelikanSSHTarget.isSafeGitName(n) { throw DeployScriptError.invalidGitName(n) }
    }

    /// Czy commit jest w lokalnym repo.
    public static func hasCommit(repo: URL, _ commit: String) -> Bool {
        (try? run(repo, ["cat-file", "-e", "--end-of-options", commit + "^{commit}"]).status) == 0
    }

    /// Commity `from..to` (`krótki-hash temat`). Hasze pochodzą z serwera — `--end-of-options` przed rewizjami.
    public static func commits(repo: URL, from: String, to: String) throws -> [String] {
        let out = text(try run(repo, ["log", "--oneline", "--no-decorate", "--end-of-options", "\(from)..\(to)"]))
        return out.isEmpty ? [] : out.components(separatedBy: "\n")
    }

    /// `git diff --stat from to`.
    public static func diffStat(repo: URL, from: String, to: String) throws -> String {
        text(try run(repo, ["diff", "--stat", "--end-of-options", from, to]))
    }
}
#endif
