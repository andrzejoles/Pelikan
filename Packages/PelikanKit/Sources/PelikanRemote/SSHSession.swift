// Pochodzi z BiFold (Remote/SSH.swift @ a1ee643), dalej rozwijany w Pelikanie.
#if canImport(Darwin)
import CryptoKit
import Darwin
import Foundation
import Synchronization

/// Połączenie SSH przez systemowe `ssh`/`scp` z jednym połączeniem głównym (ControlMaster) na serwer.
/// Hasło (lub hasło klucza) trafia do `ssh` jednorazowo przez kolejkę FIFO w prywatnym katalogu —
/// nigdy przez argumenty, zmienne środowiskowe ani pliki.
public final class SSHSession: Sendable {
    public struct Config: Sendable, Hashable {
        public var host: String
        public var port: Int?
        public var user: String
        public var keyFile: String
        /// Stare algorytmy (diffie-hellman-group1/14-sha1, ssh-rsa, CBC) — AIX 6.1 i podobne.
        public var legacyAlgorithms: Bool
        public var encoding: NameEncoding
        /// `nil` = konfiguracja użytkownika (~/.ssh/config, ~/.ssh/known_hosts).
        public var configFile: String?
        public var knownHostsFile: String?

        public init(host: String, port: Int? = nil, user: String = "", keyFile: String = "", legacyAlgorithms: Bool = false,
                    encoding: NameEncoding = .utf8, configFile: String? = nil, knownHostsFile: String? = nil) {
            self.host = host
            self.port = port
            self.user = user
            self.keyFile = keyFile
            self.legacyAlgorithms = legacyAlgorithms
            self.encoding = encoding
            self.configFile = configFile
            self.knownHostsFile = knownHostsFile
        }
    }

    public let config: Config
    let runDirectory: URL
    let controlPath: String
    let secret: @Sendable () -> String?
    static let ssh = "/usr/bin/ssh", scp = "/usr/bin/scp"
    private let startLock = Mutex(())

    public init(config: Config, runDirectory: URL, secret: @escaping @Sendable () -> String?) throws {
        // Bez znaków, które `ssh` mógłby wziąć za opcję albo rozdzielić (wstrzyknięcie opcji).
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_:[]"))
        guard !config.host.isEmpty, !config.host.hasPrefix("-"), config.host.unicodeScalars.allSatisfy(allowed.contains) else {
            throw SSHError.invalidName(config.host)
        }
        guard !config.user.hasPrefix("-"), config.user.unicodeScalars.allSatisfy({ allowed.contains($0) || $0 == "$" }) else {
            throw SSHError.invalidName(config.user)
        }
        self.config = config
        self.runDirectory = runDirectory
        self.secret = secret
        let key = "\(config.user)@\(config.host):\(config.port ?? 22)"
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(5).map { String(format: "%02x", $0) }.joined()
        controlPath = runDirectory.appendingPathComponent("ssh-\(hash)").path
    }

    var destination: String { config.user.isEmpty ? config.host : "\(config.user)@\(config.host)" }

    /// Algorytmy obsługiwane przez lokalne `ssh` (`ssh -Q`), żeby nie podać nieznanej nazwy.
    static let supported: [String: Set<String>] = {
        var out: [String: Set<String>] = [:]
        for q in ["kex", "cipher", "key", "mac"] {
            let r = try? Spawn.run(ssh, [Array("-Q".utf8), Array(q.utf8)], environment: [:], timeout: 10)
            out[q] = Set(String(decoding: r?.output ?? Data(), as: UTF8.self).split(separator: "\n").map(String.init))
        }
        return out
    }()

    static func legacyOptions() -> [String] {
        func plus(_ option: String, _ query: String, _ names: [String]) -> [String] {
            let ok = names.filter { supported[query]?.contains($0) ?? false }
            return ok.isEmpty ? [] : ["-o", "\(option)=+\(ok.joined(separator: ","))"]
        }
        return plus("KexAlgorithms", "kex", ["diffie-hellman-group14-sha1", "diffie-hellman-group-exchange-sha1", "diffie-hellman-group1-sha1"])
            + plus("HostKeyAlgorithms", "key", ["ssh-rsa"])
            + plus("PubkeyAcceptedAlgorithms", "key", ["ssh-rsa"])
            + plus("Ciphers", "cipher", ["aes128-cbc", "aes192-cbc", "aes256-cbc", "3des-cbc"])
            + plus("MACs", "mac", ["hmac-sha1", "hmac-md5"])
    }

    /// Ścieżka jako wartość opcji `-o`: `ssh` czyta ją jak wiersz konfiguracji, więc spacja (np.
    /// „Application Support”) ją rozcina — stąd cudzysłów; `%` to znacznik (`%h`), więc `%%`.
    static func pathValue(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "%", with: "%%") + "\""
    }

    /// Opcje wspólne `ssh` i `scp` (port podawany osobno: `-p` / `-P`).
    func commonOptions(master: Bool, batch: Bool = true) -> [String] {
        var o: [String] = []
        if let f = config.configFile { o += ["-F", f] }
        o += ["-o", "ControlPath=\(Self.pathValue(controlPath))", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30",
              "-o", "StrictHostKeyChecking=yes", "-o", "NumberOfPasswordPrompts=1"]
        // Połączenie główne pisze do pliku dziennika — tam potrzebne są komunikaty negocjacji (INFO).
        o += ["-o", master ? "LogLevel=INFO" : "LogLevel=ERROR"]
        if let k = config.knownHostsFile { o += ["-o", "UserKnownHostsFile=\(Self.pathValue(k))"] }
        if !config.keyFile.isEmpty { o += ["-i", (config.keyFile as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"] }
        if config.legacyAlgorithms { o += Self.legacyOptions() }
        // Polecenia korzystają z połączenia głównego; bez niego nie pytają o nic (BatchMode).
        o += master ? ["-o", "ControlMaster=yes", "-o", "ControlPersist=900"] : ["-o", "ControlMaster=no"] + (batch ? ["-o", "BatchMode=yes"] : [])
        return o
    }

    var environment: [String: String] {
        var env: [String: String] = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        if let home = ProcessInfo.processInfo.environment["HOME"] { env["HOME"] = home }
        if let sock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] { env["SSH_AUTH_SOCK"] = sock }
        return env
    }

    public var isConnected: Bool {
        let args = (commonOptions(master: false) + ["-O", "check", destination]).map { Array($0.utf8) }
        return (try? Spawn.run(Self.ssh, args, environment: environment, timeout: 10).status) == 0
    }

    /// Nawiązuje połączenie główne (pierwsze logowanie, także po wygaśnięciu ControlPersist).
    public func connect() throws {
        try startLock.withLock { _ in
            if isConnected { return }
            try startMaster()
        }
    }

    private func startMaster() throws {
        try? FileManager.default.removeItem(atPath: controlPath)
        var env = environment
        let fifo = runDirectory.appendingPathComponent("askpass-\(UUID().uuidString.prefix(8))").path
        let askpass = runDirectory.appendingPathComponent("askpass.sh").path
        let secret = secret()
        let writer = Mutex<Bool>(false)
        if let secret, !secret.isEmpty {
            try Data("#!/bin/sh\nexec /bin/cat -- \"$PELIKAN_ASKPASS_FIFO\"\n".utf8).write(to: URL(fileURLWithPath: askpass))
            chmod(askpass, 0o700)
            guard mkfifo(fifo, 0o600) == 0 else { throw SSHError.io(code: errno, detail: fifo) }
            env["SSH_ASKPASS"] = askpass
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = ":0"
            // W środowisku tylko ścieżka kolejki — sekret idzie przez kolejkę, jednorazowo.
            env["PELIKAN_ASKPASS_FIFO"] = fifo
            let bytes = Array((secret + "\n").utf8)
            Thread.detachNewThread {
                while !writer.withLock({ $0 }) {
                    let fd = open(fifo, O_WRONLY | O_NONBLOCK)
                    if fd >= 0 {
                        _ = fcntl(fd, F_SETFL, 0)
                        bytes.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
                        close(fd)
                        unlink(fifo)
                        return
                    }
                    usleep(20_000)
                }
            }
        }
        defer {
            writer.withLock { $0 = true }
            unlink(fifo)
        }
        let log = runDirectory.appendingPathComponent("ssh-\(UUID().uuidString.prefix(8)).log").path
        defer { unlink(log) }
        var args = commonOptions(master: true)
        if secret == nil || secret!.isEmpty { args += ["-o", "BatchMode=yes"] }
        if let port = config.port { args += ["-p", String(port)] }
        args += ["-N", "-f", destination]
        let r = try Spawn.run(Self.ssh, args.map { Array($0.utf8) }, environment: env, output: .file(log), timeout: 60)
        guard r.status == 0 else {
            let message = (try? String(contentsOfFile: log, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw Self.explain(message)
        }
    }

    /// Błąd strukturalny z komunikatu `ssh` (tekst dla użytkownika — warstwa interfejsu).
    public static func explain(_ message: String) -> SSHError {
        if message.contains("no matching") || message.contains("Unable to negotiate") { return .negotiationFailed(message) }
        if message.contains("Permission denied") { return .permissionDenied(message) }
        if message.contains("host key is known for") && !message.contains("IDENTIFICATION HAS CHANGED") { return .hostKeyUnknown(message) }
        if message.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") || message.contains("Host key verification failed") {
            return .hostKeyChanged(message)
        }
        return .io(code: 0, detail: message)
    }

    /// Plik znanych kluczy serwerów, którego używa ta sesja.
    public var knownHostsPath: String { config.knownHostsFile ?? NSHomeDirectory() + "/.ssh/known_hosts" }

    /// Nazwa serwera w known_hosts (`[host]:port` dla portu innego niż 22).
    var knownHostsName: String { config.port.map { $0 == 22 ? config.host : "[\(config.host)]:\($0)" } ?? config.host }

    /// Odciski kluczy serwera (SHA256, `ssh-keyscan` bez logowania), gdy serwera nie ma w known_hosts; `nil` — serwer
    /// znany. Pusta lista — kluczy nie udało się odczytać (np. host z aliasu ~/.ssh/config). Pokazywane do potwierdzenia
    /// przed `recordHostKey()` — zaufanie przy pierwszym kontakcie bez potwierdzenia oddałoby hasło podstawionemu serwerowi.
    public func unknownHostFingerprints() throws -> [String]? {
        let known = try Spawn.run("/usr/bin/ssh-keygen", ["-F", knownHostsName, "-f", knownHostsPath].map { Array($0.utf8) },
                                  environment: environment, timeout: 10)
        if known.status == 0, !known.output.isEmpty { return nil }
        var scan = ["-T", "10"]
        if let port = config.port { scan += ["-p", String(port)] }
        scan.append(config.host)
        let keys = try Spawn.run("/usr/bin/ssh-keyscan", scan.map { Array($0.utf8) }, environment: environment, timeout: 20)
        guard !keys.output.isEmpty else { return [] }
        let fp = try Spawn.run("/usr/bin/ssh-keygen", [Array("-lf".utf8), Array("-".utf8)], environment: environment, stdin: .data(keys.output), timeout: 10)
        return String(decoding: fp.output, as: UTF8.self).split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    /// Zaufanie nowemu serwerowi (po potwierdzeniu odcisku w interfejsie albo dla serwera już znanego): zapisuje klucz
    /// do known_hosts bez logowania. Znany serwer z innym kluczem — błąd.
    public func recordHostKey() throws {
        try? FileManager.default.createDirectory(atPath: (knownHostsPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        // Pierwsze wystąpienie opcji wygrywa — własne ustawienia przed wspólnymi (tu accept-new zamiast yes).
        var args = ["-o", "StrictHostKeyChecking=accept-new", "-o", "PreferredAuthentications=none",
                    "-o", "UserKnownHostsFile=\(Self.pathValue(knownHostsPath))"] + commonOptions(master: false)
        if let port = config.port { args += ["-p", String(port)] }
        args += [destination, "exit"]
        let r = try Spawn.run(Self.ssh, args.map { Array($0.utf8) }, environment: environment, timeout: 30)
        let text = r.errorText
        if text.contains("IDENTIFICATION HAS CHANGED") || text.contains("Host key verification failed") || text.contains("Unable to negotiate") {
            throw Self.explain(text)
        }
    }

    public func disconnect() {
        let args = (commonOptions(master: false) + ["-O", "exit", destination]).map { Array($0.utf8) }
        _ = try? Spawn.run(Self.ssh, args, environment: environment, timeout: 10)
    }

    /// Argumenty `ssh` dla polecenia (przez połączenie główne); `tty` — `-tt` (pty: zakończenie `ssh` wysyła SIGHUP
    /// do grupy procesów polecenia na serwerze).
    func commandArguments(_ command: String, tty: Bool) throws -> [[UInt8]] {
        var args = commonOptions(master: false).map { Array($0.utf8) }
        if tty { args.append(Array("-tt".utf8)) }
        if let port = config.port { args += [Array("-p".utf8), Array(String(port).utf8)] }
        args += [Array(destination.utf8), try config.encoding.encode(command)]
        return args
    }

    /// Polecenie powłoki na serwerze (tekst w kodowaniu serwera). Ponawia raz po zerwaniu połączenia.
    /// `timeout: nil` — bez limitu.
    public func run(_ command: String, stdin: SpawnInput = .null, timeout: TimeInterval? = 120) throws -> Spawn.Result {
        try connect()
        let args = try commandArguments(command, tty: false)
        let r = try Spawn.run(Self.ssh, args, environment: environment, stdin: stdin, timeout: timeout)
        if r.status == 255, !isConnected {
            try connect()
            return try Spawn.run(Self.ssh, args, environment: environment, stdin: stdin, timeout: timeout)
        }
        return r
    }

    /// Polecenie strumieniowo (build): prolog środowiska, znacznik `@@PID <pid>` (Stop), wyjście na bieżąco.
    public func stream(_ command: String, environment remoteEnvironment: [(name: String, value: String)] = [], tty: Bool = false,
                       stdin: SpawnInput = .null, timeout: TimeInterval? = nil, silenceTimeout: TimeInterval? = nil) throws -> RemoteProcess {
        try connect()
        let script = Self.pidMarkerCommand + (try Self.environmentProlog(remoteEnvironment)) + command
        let process = try Spawn.stream(Self.ssh, try commandArguments(script, tty: tty), environment: environment, stdin: stdin,
                                       timeout: timeout, silenceTimeout: silenceTimeout)
        return RemoteProcess(process: process, session: self, encoding: config.encoding, tty: tty)
    }

    /// Wypisuje identyfikator powłoki polecenia — lidera grupy procesów sesji na serwerze (`kill -TERM -<pid>`).
    static let pidMarkerCommand = "echo \"@@PID $$\"; "

    /// Prolog `NAZWA='wartość'; export NAZWA;` (dwa kroki — bezpieczne w ksh88). Wartości dosłowne (bez rozwijania
    /// zmiennych), nazwy tylko `[A-Za-z_][A-Za-z0-9_]*`.
    public static func environmentProlog(_ variables: [(name: String, value: String)]) throws -> String {
        var out = ""
        for v in variables {
            guard v.name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { throw SSHError.invalidName(v.name) }
            out += "\(v.name)=\(shellQuote(v.value)); export \(v.name); "
        }
        return out
    }

    /// `scp -O` (klasyczny protokół SCP, bez SFTP). `remote` to ścieżka absolutna na serwerze.
    public func scp(download remote: String, to local: String, isCancelled: @escaping @Sendable () -> Bool = { false },
                    isPaused: @escaping @Sendable () -> Bool = { false }) throws {
        try connect()
        let source = Array("\(destination):".utf8) + (try Self.scpEscape(remote, config.encoding))
        try runScp([source, Array(local.utf8)], isCancelled: isCancelled, isPaused: isPaused)
    }

    public func scp(upload local: String, to remote: String, isCancelled: @escaping @Sendable () -> Bool = { false },
                    isPaused: @escaping @Sendable () -> Bool = { false }) throws {
        try connect()
        let target = Array("\(destination):".utf8) + (try Self.scpEscape(remote, config.encoding))
        try runScp([Array(local.utf8), target], isCancelled: isCancelled, isPaused: isPaused)
    }

    private func runScp(_ paths: [[UInt8]], isCancelled: @escaping @Sendable () -> Bool, isPaused: @escaping @Sendable () -> Bool) throws {
        var args = (["-O", "-p", "-q"] + commonOptions(master: false)).map { Array($0.utf8) }
        if let port = config.port { args += [Array("-P".utf8), Array(String(port).utf8)] }
        args += paths
        let r = try Spawn.run(Self.scp, args, environment: environment, timeout: 24 * 3600, isCancelled: isCancelled, isPaused: isPaused)
        guard r.status == 0 else { throw Self.explain(r.errorText) }
    }

    /// Cudzysłów powłoki POSIX (ksh na AIX, sh, bash).
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Ścieżka zdalna dla `scp -O`: odwrotny ukośnik przed każdym znakiem ASCII spoza [A-Za-z0-9/._-].
    /// Działa jednocześnie dla powłoki serwera i dla kontroli nazw klienta (fnmatch); apostrofy
    /// tej kontroli nie przechodzą („filename does not match request”).
    public static func scpEscape(_ path: String, _ encoding: NameEncoding) throws -> [UInt8] {
        var out: [UInt8] = []
        for b in try encoding.encode(path) {
            let c = Character(Unicode.Scalar(b))
            if b < 0x80, !(c.isLetter || c.isNumber || "/._-".contains(c)) {
                guard b >= 0x20, b != 0x7f else { throw SSHError.invalidName(path) }
                out.append(0x5c)
            }
            out.append(b)
        }
        return out
    }
}

/// Zdarzenie zdalnego polecenia (tekst zdekodowany w kodowaniu serwera).
public enum RemoteEvent: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

final class PIDBox: Sendable { let value = Mutex<Int32?>(nil) }

/// Zdalne polecenie uruchomione strumieniowo: zdarzenia tekstowe bez znacznika `@@PID`, Stop.
public final class RemoteProcess: Sendable {
    let process: SpawnedProcess
    let session: SSHSession
    let tty: Bool
    private let remotePID = PIDBox()
    public let events: AsyncThrowingStream<RemoteEvent, any Error>

    init(process: SpawnedProcess, session: SSHSession, encoding: NameEncoding, tty: Bool) {
        self.process = process
        self.session = session
        self.tty = tty
        let (stream, continuation) = AsyncThrowingStream<RemoteEvent, any Error>.makeStream()
        events = stream
        let remotePID = remotePID
        Task.detached {
            var out = StreamTextDecoder(encoding: encoding, normalizeNewlines: tty)
            var err = StreamTextDecoder(encoding: encoding, normalizeNewlines: tty)
            var markerSeen = false
            var head = ""
            do {
                for try await e in process.events {
                    switch e {
                    case .stdout(let d):
                        var text = out.decode(d)
                        if !markerSeen {
                            // Pierwsza linia wyjścia to znacznik `@@PID n` — odcinany i zapamiętywany.
                            head += text
                            guard let nl = head.firstIndex(of: "\n") else { continue }
                            let line = head[..<nl].trimmingCharacters(in: .whitespaces)
                            if line.hasPrefix("@@PID "), let pid = Int32(line.dropFirst(6).trimmingCharacters(in: .whitespaces)) {
                                remotePID.value.withLock { $0 = pid }
                                text = String(head[head.index(after: nl)...])
                            } else {
                                text = head
                            }
                            markerSeen = true
                            head = ""
                        }
                        if !text.isEmpty { continuation.yield(.stdout(text)) }
                    case .stderr(let d):
                        let text = err.decode(d)
                        if !text.isEmpty { continuation.yield(.stderr(text)) }
                    case .exit(let code):
                        let rest = head + out.finish()
                        if !rest.isEmpty { continuation.yield(.stdout(rest)) }
                        let restErr = err.finish()
                        if !restErr.isEmpty { continuation.yield(.stderr(restErr)) }
                        continuation.yield(.exit(code))
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// PID powłoki polecenia na serwerze (ze znacznika `@@PID`), gdy już odczytany.
    public var remoteProcessID: Int32? { remotePID.value.withLock { $0 } }

    /// Stop: zakończenie lokalnego `ssh` (z pty — SIGHUP dla grupy procesów na serwerze), a zapasowo osobnym
    /// połączeniem `kill -TERM -<pid>` i po `grace` sekundach `kill -KILL -<pid>`, gdy grupa nadal żyje.
    public func stop(grace: TimeInterval = 5) {
        process.cancel()
        guard let pid = remoteProcessID else { return }
        let group = "-\(pid)"
        _ = try? session.run("kill -TERM \(group) 2>/dev/null; kill -TERM \(pid) 2>/dev/null; exit 0", timeout: 20)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            let r = try? session.run("kill -0 \(group) 2>/dev/null && echo alive", timeout: 20)
            if r.map({ !String(decoding: $0.output, as: UTF8.self).contains("alive") }) ?? true { return }
            usleep(200_000)
        }
        _ = try? session.run("kill -KILL \(group) 2>/dev/null; exit 0", timeout: 20)
    }
}
#endif
