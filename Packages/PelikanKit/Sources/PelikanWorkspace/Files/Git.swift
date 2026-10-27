import Foundation
import Synchronization

/// Stan pliku w repozytorium Git (PD-VCS-001).
public enum GitFileState: String, Sendable, Codable, Hashable, CaseIterable {
    case unmodified, modified, added, deleted, renamed, untracked, ignored, conflicted

    public var displayName: String {
        switch self {
        case .unmodified: L10n.tr("bez zmian")
        case .modified: L10n.tr("zmieniony")
        case .added: L10n.tr("dodany")
        case .deleted: L10n.tr("usunięty")
        case .renamed: L10n.tr("przemianowany")
        case .untracked: L10n.tr("nieśledzony")
        case .ignored: L10n.tr("ignorowany")
        case .conflicted: L10n.tr("konflikt")
        }
    }

    /// Jednoliterowy znacznik (lista plików, pasek stanu).
    public var badge: String {
        switch self {
        case .unmodified: ""
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .untracked: "?"
        case .ignored: "!"
        case .conflicted: "U"
        }
    }
}

/// Wynik `git status`: gałąź i stany plików (ścieżki względem katalogu głównego repozytorium).
public struct GitStatus: Sendable, Hashable {
    public var root: URL
    public var branch: String?
    public var ahead = 0
    public var behind = 0
    public var files: [String: GitFileState] = [:]

    /// Stan pliku (bez zmian, gdy git go nie wymienia, a plik leży w repozytorium).
    public func state(of url: URL) -> GitFileState? {
        guard let rel = GitRepository.relativePath(of: url, root: root) else { return nil }
        if let s = files[rel] { return s }
        // Katalog nieśledzony obejmuje pliki pod nim.
        if files.contains(where: { $0.value == .untracked && $0.key.hasSuffix("/") && rel.hasPrefix($0.key) }) { return .untracked }
        return .unmodified
    }

    /// Parser `git status --porcelain=v2 --branch -z` (wpisy rozdzielone NUL; przy zmianie nazwy dodatkowe pole
    /// ze ścieżką źródłową).
    public static func parse(_ output: String, root: URL) -> GitStatus {
        var s = GitStatus(root: root)
        let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < fields.count {
            let f = fields[i]
            i += 1
            guard let kind = f.first else { continue }
            switch kind {
            case "#":
                let parts = f.split(separator: " ")
                if parts.count >= 3, parts[1] == "branch.head" { s.branch = parts[2] == "(detached)" ? nil : String(parts[2]) }
                if parts.count >= 4, parts[1] == "branch.ab" {
                    s.ahead = Int(parts[2].dropFirst()) ?? 0
                    s.behind = Int(parts[3].dropFirst()) ?? 0
                }
            case "1", "2":
                // 1 XY sub mH mI mW hH hI ścieżka  |  2 XY sub mH mI mW hH hI Xscore ścieżka NUL źródło
                let count = kind == "1" ? 9 : 10
                let parts = f.split(separator: " ", maxSplits: count - 1, omittingEmptySubsequences: false)
                guard parts.count == count else { continue }
                let xy = Array(parts[1])
                let path = String(parts[count - 1])
                if kind == "2" {
                    s.files[path] = .renamed
                    i += 1    // ścieżka źródłowa
                } else {
                    s.files[path] = state(x: xy.first ?? ".", y: xy.last ?? ".")
                }
            case "u":
                let parts = f.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                if let p = parts.last { s.files[String(p)] = .conflicted }
            case "?":
                s.files[String(f.dropFirst(2))] = .untracked
            case "!":
                s.files[String(f.dropFirst(2))] = .ignored
            default:
                break
            }
        }
        return s
    }

    static func state(x: Character, y: Character) -> GitFileState {
        if x == "A" { return .added }
        if x == "D" || y == "D" { return .deleted }
        if x == "R" || x == "C" { return .renamed }
        return .modified
    }
}

/// Wpis historii (`git log`).
public struct GitCommit: Sendable, Hashable, Identifiable {
    public var hash: String
    public var author: String
    public var date: Date?
    public var subject: String
    public var id: String { hash }
}

/// Repozytorium Git obsługiwane przez `/usr/bin/git` (bez haseł w argumentach; operacje sieciowe poza zakresem).
public struct GitRepository: Sendable, Hashable {
    public var root: URL

    public enum Failure: Error, LocalizedError, Equatable {
        case notInstalled
        case failed(String)
        public var errorDescription: String? {
            switch self {
            case .notInstalled: L10n.tr("Nie znaleziono programu git (/usr/bin/git)")
            case .failed(let m): m
            }
        }
    }

    public static let executable = URL(fileURLWithPath: "/usr/bin/git")

    /// Wykonuje git z katalogu `directory`; wyjście standardowe albo błąd z treścią stderr.
    @discardableResult
    static func run(_ args: [String], in directory: URL, input: String? = nil) throws -> String {
        String(decoding: try runData(args, in: directory, input: input), as: UTF8.self)
    }

    /// Jak `run`, ale wyjście w bajtach (treść plików w ich kodowaniu, np. ISO-8859-2).
    static func runData(_ args: [String], in directory: URL, input: String? = nil) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.notInstalled }
        let p = Process()
        p.executableURL = executable
        p.arguments = ["-C", directory.path] + args
        var env = ProcessInfo.processInfo.environment
        // Nigdy nie pytaj o dane logowania; status bez blokad indeksu (odświeżanie w tle).
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        p.environment = env
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        try p.run()
        if let input { inp.fileHandleForWriting.write(Data(input.utf8)) }
        try? inp.fileHandleForWriting.close()
        // stderr czytany równolegle — pełny bufor potoku stderr zatrzymałby gita przed końcem stdout.
        let errHandle = err.fileHandleForReading, errData = Mutex(Data()), group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            // readToEnd: błąd odczytu jako błąd Swift (readDataToEndOfFile rzuca wyjątek ObjC — awaria).
            let d = (try? errHandle.readToEnd()) ?? Data()
            errData.withLock { $0 = d }
        }
        let data = Result { try out.fileHandleForReading.readToEnd() ?? Data() }
        group.wait()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw Failure.failed(String(decoding: errData.withLock { $0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try data.get()
    }

    /// Repozytorium zawierające plik albo katalog (nil — poza repozytorium albo brak gita).
    public static func discover(for url: URL) -> GitRepository? {
        var dir = url
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue { dir = dir.deletingLastPathComponent() }
        guard let top = try? run(["rev-parse", "--show-toplevel"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty else { return nil }
        return GitRepository(root: URL(fileURLWithPath: top, isDirectory: true))
    }

    /// Ścieżka względem katalogu głównego (dowiązania rozwiązane po obu stronach, np. /var → /private/var).
    static func relativePath(of url: URL, root: URL) -> String? {
        let r = root.resolvingSymlinksInPath().standardizedFileURL.path
        var p = url.resolvingSymlinksInPath().standardizedFileURL.path
        if !FileManager.default.fileExists(atPath: p) {
            // Plik usunięty: rozwiązujemy dowiązania katalogu nadrzędnego.
            p = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent(url.lastPathComponent).path
        }
        guard p.hasPrefix(r + "/") else { return nil }
        return String(p.dropFirst(r.count + 1))
    }

    public func status() throws -> GitStatus {
        GitStatus.parse(try Self.run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=normal"], in: root), root: root)
    }

    /// Treść pliku w HEAD w bajtach — dekodowanie jak pliku na dysku (`TextFileCodec`); nil — plik nowy, nieobecny w HEAD.
    public func headContent(of url: URL) throws -> Data? {
        guard let rel = Self.relativePath(of: url, root: root) else { throw Failure.failed(L10n.tr("Plik spoza repozytorium")) }
        do {
            return try Self.runData(["show", "HEAD:\(rel)"], in: root)
        } catch Failure.failed {
            return nil
        }
    }

    public func add(_ urls: [URL]) throws {
        let rel = urls.compactMap { Self.relativePath(of: $0, root: root) }
        guard !rel.isEmpty else { return }
        try Self.run(["add", "--"] + rel, in: root)
    }

    /// Zatwierdza zawartość indeksu; komunikat przez stdin (`-F -`), nie w argumentach.
    @discardableResult
    public func commit(message: String) throws -> String {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { throw Failure.failed(L10n.tr("Pusty komunikat zatwierdzenia")) }
        try Self.run(["commit", "-F", "-"], in: root, input: m + "\n")
        return try Self.run(["rev-parse", "--short", "HEAD"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Historia (dla pliku albo całego repozytorium), najnowsze pierwsze.
    public func log(limit: Int = 100, file: URL? = nil) throws -> [GitCommit] {
        var args = ["log", "-n", String(max(1, limit)), "--pretty=format:%H%x1f%an%x1f%aI%x1f%s%x1e"]
        if let file, let rel = Self.relativePath(of: file, root: root) { args += ["--", rel] }
        let out: String
        do { out = try Self.run(args, in: root) } catch Failure.failed { return [] }   // repozytorium bez zatwierdzeń
        let iso = ISO8601DateFormatter()
        return out.split(separator: "\u{1e}").compactMap { rec in
            let f = rec.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4 else { return nil }
            return GitCommit(hash: f[0], author: f[1], date: iso.date(from: f[2]), subject: f[3])
        }
    }
}
