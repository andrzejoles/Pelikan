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

    /// Wykonuje git z katalogu `directory`; wyjście standardowe albo błąd z treścią stderr. `config` — ustawienia
    /// na czas wywołania (zakres „command”, pierwszeństwo przed plikami konfiguracji).
    @discardableResult
    static func run(_ args: [String], in directory: URL, input: String? = nil, config: [(String, String)] = []) throws -> String {
        String(decoding: try runData(args, in: directory, input: input, config: config), as: UTF8.self)
    }

    /// Odczyty uruchamiane samoczynnie (stan przy otwarciu pliku i w przeglądarce plików, projekt, treść z HEAD,
    /// historia) nie wykonują poleceń z konfiguracji repozytorium: pobrane albo rozpakowane repozytorium może mieć
    /// w `.git/config` `core.fsmonitor` (git status uruchamia je zawsze), `log.showSignature` z `gpg.program` albo
    /// hooki. Filtry — osobno (`untrustedFilterConfig`). Dodawanie i zatwierdzanie (czynności jawne użytkownika)
    /// działają jak git w terminalu.
    static let backgroundConfig: [(String, String)] = [
        ("core.fsmonitor", "false"), ("core.hooksPath", "/dev/null"), ("log.showSignature", "false"),
    ]

    /// Filtry `clean`/`smudge`/`process` z konfiguracji repozytorium (zakres local/worktree, także z jej `include`) wyłączone:
    /// git status liczy nimi treść plików o zmienionym czasie modyfikacji, a `.gitattributes` przychodzi z repozytorium.
    /// Filtry z konfiguracji globalnej i systemowej (np. git-lfs) to ustawienia właściciela Maca — zostają.
    static func untrustedFilterConfig(in directory: URL) -> [(String, String)] {
        guard let out = try? run(["config", "-z", "--show-scope", "--get-regexp", #"^filter\."#], in: directory, config: backgroundConfig) else { return [] }
        // Rekordy: zakres NUL klucz LF wartość NUL.
        let fields = out.split(separator: "\0", omittingEmptySubsequences: false)
        var names: Set<String> = []
        var i = 0
        while i + 1 < fields.count {
            let scope = fields[i], key = fields[i + 1].prefix { $0 != "\n" }
            i += 2
            guard scope == "local" || scope == "worktree", key.hasPrefix("filter."), let dot = key.lastIndex(of: "."),
                  dot > key.index(key.startIndex, offsetBy: 7) else { continue }
            names.insert(String(key[key.index(key.startIndex, offsetBy: 7)..<dot]))
        }
        return names.sorted().flatMap { n in
            [("filter.\(n).clean", ""), ("filter.\(n).smudge", ""), ("filter.\(n).process", ""), ("filter.\(n).required", "false")]
        }
    }

    /// Jak `run`, ale wyjście w bajtach (treść plików w ich kodowaniu, np. ISO-8859-2).
    static func runData(_ args: [String], in directory: URL, input: String? = nil, config: [(String, String)] = []) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.notInstalled }
        let p = Process()
        p.executableURL = executable
        p.arguments = ["-C", directory.path] + args
        var env = ProcessInfo.processInfo.environment
        // Nigdy nie pytaj o dane logowania; status bez blokad indeksu (odświeżanie w tle).
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        // Ustawienia przez GIT_CONFIG_KEY_n/VALUE_n — dowolne nazwy podsekcji (np. z „=”) bez rozbioru jak przy `-c`.
        var n = Int(env["GIT_CONFIG_COUNT"] ?? "") ?? 0
        for (key, value) in config {
            env["GIT_CONFIG_KEY_\(n)"] = key
            env["GIT_CONFIG_VALUE_\(n)"] = value
            n += 1
        }
        if !config.isEmpty { env["GIT_CONFIG_COUNT"] = String(n) }
        p.environment = env
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        try p.run()
        if let input { try? inp.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
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
        p.waitForExit()
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
        guard let top = try? run(["rev-parse", "--show-toplevel"], in: dir, config: backgroundConfig).trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty else { return nil }
        return GitRepository(root: URL(fileURLWithPath: top, isDirectory: true))
    }

    /// Repozytorium katalogu dla grup kart (D200): katalog roboczy, nazwa (katalog głównego repozytorium — także dla
    /// worktree), gałąź z pliku HEAD i czy repozytorium ma zdalne (`git remote`). nil — poza repozytorium albo brak gita.
    public static func groupInfo(for directory: URL) -> RepositoryGroupInfo? {
        guard var info = location(for: directory) else { return nil }
        info.hasRemote = hasRemote(root: URL(fileURLWithPath: info.root, isDirectory: true))
        if let g = info.gitDirectory { info.branch = currentBranch(gitDirectory: g, root: info.root) }
        return info
    }

    /// Położenie repozytorium katalogu (bez sprawdzania zdalnego): katalog roboczy, nazwa, katalog gita i gałąź z pliku
    /// HEAD (bez procesu gita — HEAD reftable odczytuje wywołujący raz na repozytorium).
    public static func location(for directory: URL) -> RepositoryGroupInfo? {
        guard let out = try? run(["rev-parse", "--show-toplevel", "--git-common-dir", "--git-dir"], in: directory, config: backgroundConfig) else { return nil }
        // Ścieżki bez przycinania białych znaków (katalog może się nimi zaczynać albo kończyć) — tylko podział na linie.
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3, !lines[0].isEmpty, !lines[1].isEmpty, !lines[2].isEmpty else { return nil }
        let top = URL(fileURLWithPath: lines[0], isDirectory: true)
        func absolute(_ p: String) -> URL {
            p.hasPrefix("/") ? URL(fileURLWithPath: p, isDirectory: true) : directory.appendingPathComponent(p, isDirectory: true).standardizedFileURL
        }
        let common = absolute(lines[1]), gitDir = absolute(lines[2])
        var name = common.lastPathComponent == ".git" ? common.deletingLastPathComponent().lastPathComponent : common.lastPathComponent
        if name.hasSuffix(".git"), name.count > 4 { name = String(name.dropLast(4)) }
        let root = top.standardizedFileURL.path
        let branch: String? = if case .branch(let b) = readBranch(gitDirectory: gitDir.path, root: root, allowProcess: false) { b } else { nil }
        return RepositoryGroupInfo(root: root, name: name, branch: branch,
                                   hasRemote: false, gitDirectory: gitDir.path)
    }

    /// Repozytorium ma zdalne (`git remote` niepuste).
    public static func hasRemote(root: URL) -> Bool {
        !((try? run(["remote"], in: root, config: backgroundConfig)) ?? "").split(separator: "\n").isEmpty
    }

    /// Gałąź: z pliku HEAD (bez procesu); w trakcie rebase — gałąź z `rebase-merge/head-name` albo
    /// `rebase-apply/head-name`; HEAD w formacie reftable (`refs/heads/.invalid`) — `git symbolic-ref` (wywołanie w tle).
    /// nil — odłączony HEAD.
    public static func currentBranch(gitDirectory: String, root: String) -> String? {
        if case .branch(let b) = readBranch(gitDirectory: gitDirectory, root: root, allowProcess: true) { return b }
        return nil
    }

    /// Odczyt gałęzi: gałąź, odłączony HEAD albo nieznana (reftable bez zgody na proces gita — wtedy gałąź zapamiętana).
    public enum BranchRead: Sendable, Equatable { case branch(String), detached, unknown }

    public static func readBranch(gitDirectory: String, root: String, allowProcess: Bool) -> BranchRead {
        switch headReference(gitDirectory: gitDirectory) {
        case .branch(let b): return .branch(b)
        case .unknown:
            guard allowProcess else { return .unknown }
            let out = try? run(["symbolic-ref", "-q", "--short", "HEAD"], in: URL(fileURLWithPath: root, isDirectory: true), config: backgroundConfig)
            let b = out.map { $0.hasSuffix("\n") ? String($0.dropLast()) : $0 } ?? ""
            return b.isEmpty ? .detached : .branch(b)
        case .detached:
            for f in ["rebase-merge/head-name", "rebase-apply/head-name"] {
                if let h = try? String(contentsOfFile: gitDirectory + "/" + f, encoding: .utf8) {
                    let line = h.hasSuffix("\n") ? String(h.dropLast()) : h
                    if line.hasPrefix("refs/heads/") { return .branch(String(line.dropFirst("refs/heads/".count))) }
                }
            }
            return .detached
        }
    }

    enum HeadReference: Equatable { case branch(String), detached, unknown }

    /// Odczyt pliku HEAD: „ref: refs/heads/…” — gałąź; reftable (`.invalid`) albo brak pliku — nieznane; inaczej odłączony.
    static func headReference(gitDirectory: String) -> HeadReference {
        guard let head = try? String(contentsOfFile: gitDirectory + "/HEAD", encoding: .utf8) else { return .unknown }
        let line = head.hasSuffix("\n") ? String(head.dropLast()) : head
        let prefix = "ref: refs/heads/"
        guard line.hasPrefix(prefix) else { return line.hasPrefix("ref: ") ? .unknown : .detached }
        let b = String(line.dropFirst(prefix.count))
        return b == ".invalid" ? .unknown : .branch(b)
    }

    /// Gałąź z pliku `HEAD` katalogu gita (bez procesu gita); nil — odłączony HEAD, reftable albo brak pliku.
    public static func headBranch(gitDirectory: String) -> String? {
        if case .branch(let b) = headReference(gitDirectory: gitDirectory) { return b }
        return nil
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
        // Podmoduły pomijane: ich konfiguracja jest tak samo obca, a git status uruchamia w nich osobne procesy gita.
        GitStatus.parse(try Self.run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=normal", "--ignore-submodules=all"], in: root,
                                     config: Self.backgroundConfig + Self.untrustedFilterConfig(in: root)), root: root)
    }

    /// Treść pliku w HEAD w bajtach — dekodowanie jak pliku na dysku (`TextFileCodec`); nil — plik nowy, nieobecny w HEAD.
    public func headContent(of url: URL) throws -> Data? {
        guard let rel = Self.relativePath(of: url, root: root) else { throw Failure.failed(L10n.tr("Plik spoza repozytorium")) }
        do {
            return try Self.runData(["show", "--no-textconv", "HEAD:\(rel)"], in: root, config: Self.backgroundConfig)
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

    /// Punkt odniesienia zmian gałęzi (D201): punkt rozgałęzienia z gałęzią domyślną zdalnego repozytorium
    /// (`<zdalne>/HEAD`, inaczej `<zdalne>/main` albo `master`; zdalne `origin` albo pierwsze), bez niej — z gałęzią
    /// śledzoną (upstream); nil — tylko zmiany niezatwierdzone.
    public func branchBase() -> String? {
        let cfg = Self.backgroundConfig
        func verify(_ ref: String) -> Bool { (try? Self.run(["rev-parse", "--verify", "-q", ref + "^{commit}"], in: root, config: cfg)) != nil }
        func mergeBase(_ ref: String) -> String? {
            guard let b = (try? Self.run(["merge-base", "HEAD", ref], in: root, config: cfg))?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !b.isEmpty else { return nil }
            return b
        }
        let remotes = ((try? Self.run(["remote"], in: root, config: cfg)) ?? "").split(separator: "\n").map(String.init)
        if let remote = remotes.contains("origin") ? "origin" : remotes.first {
            var candidates: [String] = []
            if let head = (try? Self.run(["symbolic-ref", "-q", "--short", "refs/remotes/\(remote)/HEAD"], in: root, config: cfg))?
                .trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty { candidates.append(head) }
            candidates += ["\(remote)/main", "\(remote)/master"]
            for ref in candidates where verify(ref) {
                if let base = mergeBase(ref) { return base }
            }
        }
        if let up = (try? Self.run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: root, config: cfg))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !up.isEmpty {
            return mergeBase(up)
        }
        return nil
    }

    /// Pliki zmienione w gałęzi (D201): zatwierdzone od punktu rozgałęzienia (`branchBase`), niezatwierdzone (indeks
    /// i katalog roboczy względem HEAD) i nieśledzone (bez ignorowanych); bez usuniętych i binarnych, tylko istniejące.
    /// Kolejność: według ścieżki.
    public func branchChangedFiles(extensions: Set<String>? = nil) throws -> [URL] {
        // Filtr rozszerzeń przed sprawdzaniem plików binarnych (bez czytania plików, których i tak nie otworzymy).
        func wanted(_ p: String) -> Bool { extensions.map { $0.contains((p as NSString).pathExtension.lowercased()) } ?? true }
        let cfg = Self.backgroundConfig + Self.untrustedFilterConfig(in: root)
        var paths = Set<String>()
        var binary = Set<String>()
        func numstat(_ args: [String]) {
            guard let out = try? Self.run(["diff", "--numstat", "-z", "--no-renames", "--no-textconv", "--no-ext-diff", "--diff-filter=d"] + args,
                                          in: root, config: cfg) else { return }
            // Rekord: dodane TAB usunięte TAB ścieżka NUL; plik binarny — „-” zamiast liczb.
            for rec in out.split(separator: "\0") {
                let parts = rec.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3 else { continue }
                let path = String(parts[2])
                guard wanted(path) else { continue }
                if parts[0] == "-" { binary.insert(path) } else { paths.insert(path) }
            }
        }
        let hasHead = (try? Self.run(["rev-parse", "--verify", "-q", "HEAD"], in: root, config: Self.backgroundConfig)) != nil
        if hasHead {
            if let base = branchBase() { numstat([base, "HEAD", "--"]) }
            numstat(["HEAD", "--"])
        } else {
            numstat(["--cached", "--"])
        }
        let others = (try? Self.run(["ls-files", "--others", "--exclude-standard", "-z"], in: root, config: Self.backgroundConfig)) ?? ""
        for p in others.split(separator: "\0").map(String.init) where !p.isEmpty && !p.hasSuffix("/") && wanted(p) {
            if Self.looksBinary(root.appendingPathComponent(p)) { binary.insert(p) } else { paths.insert(p) }
        }
        return paths.subtracting(binary).sorted().compactMap { p in
            let u = root.appendingPathComponent(p).standardizedFileURL
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) && !isDir.boolValue ? u : nil
        }
    }

    /// Plik binarny: bajt NUL w pierwszych 8000 bajtach (jak git).
    static func looksBinary(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: 8000)) ?? Data()
        return data.contains(0)
    }

    /// Historia (dla pliku albo całego repozytorium), najnowsze pierwsze.
    public func log(limit: Int = 100, file: URL? = nil) throws -> [GitCommit] {
        var args = ["log", "-n", String(max(1, limit)), "--pretty=format:%H%x1f%an%x1f%aI%x1f%s%x1e"]
        if let file, let rel = Self.relativePath(of: file, root: root) { args += ["--", rel] }
        let out: String
        do { out = try Self.run(args, in: root, config: Self.backgroundConfig) } catch Failure.failed { return [] }   // repozytorium bez zatwierdzeń
        let iso = ISO8601DateFormatter()
        return out.split(separator: "\u{1e}").compactMap { rec in
            let f = rec.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4 else { return nil }
            return GitCommit(hash: f[0], author: f[1], date: iso.date(from: f[2]), subject: f[3])
        }
    }
}
