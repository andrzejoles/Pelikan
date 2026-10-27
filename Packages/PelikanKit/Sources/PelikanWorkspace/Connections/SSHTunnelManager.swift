import Foundation
import PelikanDB
import PelikanLog
import Synchronization
#if canImport(Darwin)
import Darwin
private let sockStream = SOCK_STREAM
#else
import Glibc
private let sockStream = Int32(SOCK_STREAM.rawValue)
#endif

/// Adres bazy w connect stringu i jego wersja przez tunel (127.0.0.1:port lokalny).
public enum ConnectStringRewriter {
    public struct Endpoint: Sendable, Hashable {
        public var host: String
        public var port: Int
    }

    /// Host i port bazy z EZConnect (`host[:port]/usługa`, `//host…`, `tcps://…`, `[IPv6]`) albo deskryptora.
    public static func endpoint(of connect: String) -> Endpoint? {
        let s = connect.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("(") {
            guard let h = TNSNames.value("HOST", in: s) else { return nil }
            return Endpoint(host: h, port: TNSNames.value("PORT", in: s).flatMap(Int.init) ?? 1521)
        }
        var rest = s
        if let r = rest.range(of: "://") { rest = String(rest[r.upperBound...]) }
        if rest.hasPrefix("//") { rest.removeFirst(2) }
        let hostPort = rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? rest
        if hostPort.hasPrefix("["), let close = hostPort.firstIndex(of: "]") {
            let host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
            let after = hostPort[hostPort.index(after: close)...]
            return Endpoint(host: host, port: after.hasPrefix(":") ? Int(after.dropFirst()) ?? 1521 : 1521)
        }
        let parts = hostPort.split(separator: ":", maxSplits: 1)
        guard let host = parts.first, !host.isEmpty, s.contains("/") || s.contains(":") else { return nil }
        return Endpoint(host: String(host), port: parts.count > 1 ? Int(parts[1]) ?? 1521 : 1521)
    }

    /// Connect string z adresem zastąpionym przez `127.0.0.1:localPort` (alias TNS — rozwinięty do deskryptora).
    public static func rewrite(_ connect: String, localPort: Int, tns: [TNSEntry] = []) -> String? {
        var s = connect.trimmingCharacters(in: .whitespaces)
        if !s.hasPrefix("("), !s.contains("/"), !s.contains(":"),
           let entry = tns.first(where: { $0.aliases.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }) {
            s = entry.descriptor
        }
        if s.hasPrefix("(") {
            var out = s.replacingOccurrences(of: #"\(\s*HOST\s*=\s*[^)]+\)"#, with: "(HOST=127.0.0.1)", options: [.regularExpression, .caseInsensitive])
            out = out.replacingOccurrences(of: #"\(\s*PORT\s*=\s*[^)]+\)"#, with: "(PORT=\(localPort))", options: [.regularExpression, .caseInsensitive])
            return out.contains("(HOST=127.0.0.1)") ? out : nil
        }
        guard let ep = endpoint(of: s) else { return nil }
        var prefix = ""
        var rest = s
        if let r = rest.range(of: "://") { prefix = String(rest[..<r.upperBound]); rest = String(rest[r.upperBound...]) }
        if rest.hasPrefix("//") { prefix += "//"; rest.removeFirst(2) }
        let hostPortEnd = rest.firstIndex(of: "/") ?? rest.endIndex
        let tail = rest[hostPortEnd...]
        _ = ep
        return prefix + "127.0.0.1:\(localPort)" + tail
    }
}

/// Tunele SSH dla połączeń (UG nie ma tej funkcji — jak SQL Developer/DBeaver): systemowy `ssh -N -L`, więc działają
/// `~/.ssh/config`, agent SSH (klucze w Pęku kluczy przez `ssh-add --apple-use-keychain`), ProxyJump i known_hosts.
/// Hasło SSH (DB-SSH-001, D134) nie trafia do argumentów, środowiska ani plików: `SSH_ASKPASS` to skrypt `cat` z kolejki
/// FIFO (w środowisku tylko jej ścieżka), a sekret z Pęku kluczy jest do niej zapisywany jednorazowo.
@MainActor
public final class SSHTunnelManager {
    public struct Tunnel: Sendable {
        public let localPort: Int
        public let remote: ConnectStringRewriter.Endpoint
        /// Przebieg procesu ssh: po jego śmierci i ponownym otwarciu stare sesje zwalniają swój tunel, nie nowy.
        let run = UUID()
    }

    final class Running {
        let process: Process
        let tunnel: Tunnel
        var users = 1
        init(process: Process, tunnel: Tunnel) { self.process = process; self.tunnel = tunnel }
    }

    /// Katalog prywatny (0700) na skrypt askpass i kolejki FIFO.
    nonisolated static let runDirectory: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-tunnel-\(getuid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(d.path, 0o700)
        return d
    }()

    /// Przygotowuje askpass: skrypt bez sekretu, kolejka FIFO 0600 i wątek, który zapisze hasło raz (albo zakończy się,
    /// gdy `done` zostanie ustawione). Zwraca zmienne środowiska dla `ssh` i funkcję sprzątającą.
    nonisolated static func askpass(secret: String) throws -> (environment: [String: String], cleanup: @Sendable () -> Void) {
        let askpass = runDirectory.appendingPathComponent("askpass.sh").path
        try Data("#!/bin/sh\nexec /bin/cat -- \"$PELIKAN_ASKPASS_FIFO\"\n".utf8).write(to: URL(fileURLWithPath: askpass))
        chmod(askpass, 0o700)
        let fifo = runDirectory.appendingPathComponent("askpass-\(UUID().uuidString.prefix(8))").path
        guard mkfifo(fifo, 0o600) == 0 else { throw DatabaseError.driverUnavailable(L10n.tr("Nie można utworzyć kolejki dla hasła SSH")) }
        let done = Flag()
        let bytes = Array((secret + "\n").utf8)
        Thread.detachNewThread {
            while !done.isSet {
                #if canImport(Darwin)
                let fd = Darwin.open(fifo, O_WRONLY | O_NONBLOCK)
                #else
                let fd = Glibc.open(fifo, O_WRONLY | O_NONBLOCK)
                #endif
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
        let env = ["SSH_ASKPASS": askpass, "SSH_ASKPASS_REQUIRE": "force", "DISPLAY": ":0", "PELIKAN_ASKPASS_FIFO": fifo]
        return (env, { done.set(); unlink(fifo) })
    }

    /// Znacznik zakończenia współdzielony z wątkiem zapisu kolejki.
    final class Flag: Sendable {
        private let value = Mutex<Bool>(false)
        var isSet: Bool { value.withLock { $0 } }
        func set() { value.withLock { $0 = true } }
    }

    var running: [UUID: Running] = [:]
    /// Otwierane tunele: równoległe otwarcia tego samego połączenia czekają na jeden proces ssh.
    private var opening: [UUID: Task<Tunnel, any Error>] = [:]
    /// Dodatkowe opcje ssh (testy: własny plik known_hosts).
    public var extraOptions: [String] = []
    public var sshPath = "/usr/bin/ssh"

    public init() {}

    /// Wolny port lokalny (bind na 0 i odczyt przydzielonego).
    nonisolated static func freePort() -> Int? {
        let fd = socket(AF_INET, sockStream, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        return ok ? Int(UInt16(bigEndian: addr.sin_port)) : nil
    }

    nonisolated static func canConnect(port: Int) -> Bool {
        let fd = socket(AF_INET, sockStream, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }

    /// Argumenty ssh dla tunelu (bez haseł; z hasłem — askpass i jedna próba hasła zamiast BatchMode).
    nonisolated static func arguments(_ t: SSHTunnel, localPort: Int, remote: ConnectStringRewriter.Endpoint, extra: [String]) -> [String] {
        let auth = t.usesPassword
            ? ["-o", "BatchMode=no", "-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "NumberOfPasswordPrompts=1",
               "-o", "PubkeyAuthentication=no"]
            : ["-o", "BatchMode=yes"]
        var a = ["-N", "-T", "-o", "ExitOnForwardFailure=yes"] + auth + ["-o", "ServerAliveInterval=30",
                 "-o", "ConnectTimeout=15", "-L", "127.0.0.1:\(localPort):\(remote.host):\(remote.port)", "-p", String(t.port)]
        if let id = t.identityFile, !id.isEmpty { a += ["-i", (id as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"] }
        if let j = t.jumpHost, !j.isEmpty { a += ["-J", j] }
        a += extra
        // „--”: cel nie może być wzięty za opcję (host/użytkownik sprawdzane też w `SSHTunnel.validate`).
        a += ["--", t.user.isEmpty ? t.host : "\(t.user)@\(t.host)"]
        return a
    }

    /// Otwiera (albo współdzieli) tunel połączenia; zwraca lokalny port.
    public func open(for def: ConnectionDefinition, tns: [TNSEntry] = [], secret: String? = nil) async throws -> Tunnel {
        if let r = running[def.id], r.process.isRunning {
            r.users += 1
            return r.tunnel
        }
        // Druga sesja tego połączenia otwierana w trakcie czekania na port nie uruchamia drugiego ssh (osierocony
        // proces, rozjechany licznik użytkowników) — czeka na pierwszy.
        if let pending = opening[def.id] {
            let tunnel = try await pending.value
            running[def.id]?.users += 1
            return tunnel
        }
        let task = Task { try await start(for: def, tns: tns, secret: secret) }
        opening[def.id] = task
        defer { opening[def.id] = nil }
        let clock = ContinuousClock.now
        do {
            let tunnel = try await task.value
            Log.ssh.info("Tunel SSH połączenia \(def.displayName, privacy: .hash) otwarty w \(ms: clock) (\(def.sshTunnel?.usesPassword == true ? "hasło" : "klucz/agent", privacy: .public))")
            return tunnel
        } catch {
            Log.ssh.notice("Tunel SSH połączenia \(def.displayName, privacy: .hash) nie powstał po \(ms: clock): \(error)")
            throw error
        }
    }

    private func start(for def: ConnectionDefinition, tns: [TNSEntry], secret: String?) async throws -> Tunnel {
        guard let t = def.sshTunnel else { throw DatabaseError.driverUnavailable(L10n.tr("Połączenie nie ma tunelu SSH")) }
        try t.validate()
        if t.usesPassword, (secret ?? "").isEmpty {
            throw DatabaseError.driverUnavailable(L10n.tr("Brak hasła SSH tunelu w Pęku kluczy — wpisz je w definicji połączenia."))
        }
        var connect = def.target.connectString
        if !connect.hasPrefix("("), !connect.contains("/"), !connect.contains(":"),
           let e = tns.first(where: { $0.aliases.contains { $0.caseInsensitiveCompare(connect) == .orderedSame } }) {
            connect = e.descriptor
        }
        guard let remote = ConnectStringRewriter.endpoint(of: connect) else {
            throw DatabaseError.driverUnavailable(L10n.tr("Nie można ustalić hosta bazy z „\(def.target.connectString)” dla tunelu SSH"))
        }
        guard let port = Self.freePort() else { throw DatabaseError.driverUnavailable(L10n.tr("Brak wolnego portu lokalnego dla tunelu")) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: sshPath)
        p.arguments = Self.arguments(t, localPort: port, remote: remote, extra: extraOptions)
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        var cleanup: (@Sendable () -> Void)?
        if t.usesPassword, let secret {
            let a = try Self.askpass(secret: secret)
            p.environment = ProcessInfo.processInfo.environment.merging(a.environment) { _, new in new }
            cleanup = a.cleanup
        }
        defer { cleanup?() }
        try p.run()
        // Czekamy, aż port przyjmuje połączenia albo ssh się zakończy (błąd uwierzytelnienia, host key, sieć).
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            if !p.isRunning {
                let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw DatabaseError.driverUnavailable(L10n.tr("Tunel SSH nie powstał: \(msg.isEmpty ? "ssh zakończył się kodem \(p.terminationStatus)" : msg)"))
            }
            if Self.canConnect(port: port) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard p.isRunning, Self.canConnect(port: port) else {
            p.terminate()
            throw DatabaseError.driverUnavailable(L10n.tr("Tunel SSH: przekroczony czas oczekiwania"))
        }
        let tunnel = Tunnel(localPort: port, remote: remote)
        running[def.id] = Running(process: p, tunnel: tunnel)
        return tunnel
    }

    /// Zwalnia tunel (zamyka, gdy nikt go nie używa). Tunel z wcześniejszego przebiegu ssh (proces padł, otwarto nowy)
    /// jest pomijany — licznik nowego tunelu należy do sesji, które go otworzyły.
    public func release(_ tunnel: Tunnel, of id: UUID) {
        guard let r = running[id], r.tunnel.run == tunnel.run else { return }
        r.users -= 1
        if r.users <= 0 {
            r.process.terminate()
            running[id] = nil
            Log.ssh.debug("Tunel SSH zamknięty")
        }
    }

    public func closeAll() {
        for r in running.values { r.process.terminate() }
        running.removeAll()
    }

    public func isOpen(_ id: UUID) -> Bool { running[id]?.process.isRunning ?? false }
}
