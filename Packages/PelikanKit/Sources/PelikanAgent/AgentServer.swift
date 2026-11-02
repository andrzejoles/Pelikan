#if canImport(Darwin)
import PelikanBridgeKit
import Darwin
import Foundation
import PelikanLog
import PelikanRemote
import Synchronization

/// Wynik próby połączenia (do dziennika i testów).
public enum ConnectionEvent: Sendable, Equatable {
    case accepted(sessionID: String, pid: pid_t)
    case rejected(reason: String, pid: pid_t?)
}

/// Serwer gniazda Unix dla mostów `pelikan-mcp`. Bez portów TCP. Każde połączenie przechodzi:
/// UID rozmówcy → ramka `hello` z tokenem (≤ 5 s) → token w stałym czasie → PID mostu musi
/// pochodzić od procesu CLI sesji. Dopiero potem połączenie trafia do `onAccept`.
public final class AgentServer: @unchecked Sendable {
    public let socketURL: URL
    let registry: SessionRegistry
    let onAccept: @Sendable (Int32, AgentSession) -> Void
    let onEvent: @Sendable (ConnectionEvent) -> Void
    private let state = Mutex<(fd: Int32, running: Bool)>((-1, false))
    /// Potok budzenia pętli `accept` przy `stop` (czekanie bez limitu czasu, bez budzenia co sekundę).
    private let wake = Mutex<(read: Int32, write: Int32)>((-1, -1))
    /// Limit czasu na ramkę hello (s).
    static let helloTimeout: Double = 5

    public init(
        socketURL: URL, registry: SessionRegistry,
        onAccept: @escaping @Sendable (Int32, AgentSession) -> Void,
        onEvent: @escaping @Sendable (ConnectionEvent) -> Void = { _ in }
    ) {
        self.socketURL = socketURL
        self.registry = registry
        self.onAccept = onAccept
        self.onEvent = onEvent
    }

    public enum StartError: Error, Equatable {
        case insecureDirectory(String)
        case socket(Int32)
        case pathTooLong
    }

    public func start() throws {
        let dir = socketURL.deletingLastPathComponent().path(percentEncoded: false)
        try Self.prepareDirectory(dir)
        let path = socketURL.path(percentEncoded: false)
        unlink(path)

        // Terminal agenta startuje przez forkpty+execve bez zamykania deskryptorów — gniazda nie mogą przejść do CLI
        // (utworzenie z FD_CLOEXEC pod `DescriptorLock`, jak start terminala).
        let fd = DescriptorLock.withLock {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            if fd >= 0 {
                _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
                // Nieblokujące: `accept` pod blokadą nigdy nie czeka (połączenie zerwane między `poll` a `accept`).
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            }
            return fd
        }
        guard fd >= 0 else { throw StartError.socket(errno) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw StartError.pathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let e = errno
            close(fd)
            throw StartError.socket(e)
        }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else {
            let e = errno
            close(fd)
            throw StartError.socket(e)
        }
        var pipeFDs: [Int32] = [-1, -1]
        DescriptorLock.withLock {
            if pipe(&pipeFDs) == 0 { for p in pipeFDs { _ = fcntl(p, F_SETFD, FD_CLOEXEC) } }
        }
        wake.withLock { $0 = (pipeFDs[0], pipeFDs[1]) }
        state.withLock { $0 = (fd, true) }
        let wakeRead = pipeFDs[0]
        let thread = Thread { [self] in acceptLoop(fd, wake: wakeRead) }
        thread.name = "pelikan.agent.accept"
        thread.start()
    }

    public func stop() {
        let fd = state.withLock { s -> Int32 in
            let fd = s.fd
            s = (-1, false)
            return fd
        }
        // Najpierw obudzenie pętli (kończy się i zamyka potok), potem zamknięcie gniazda.
        let w = wake.withLock { w -> Int32 in
            let fd = w.write
            w = (-1, -1)
            return fd
        }
        if w >= 0 {
            var b: UInt8 = 1
            _ = Darwin.write(w, &b, 1)
            close(w)
        }
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        unlink(socketURL.path(percentEncoded: false))
    }

    /// Katalog gniazda: tworzony z 0700, musi należeć do bieżącego użytkownika i nie być dowiązaniem.
    static func prepareDirectory(_ dir: String) throws {
        var st = stat()
        if lstat(dir, &st) != 0 {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard lstat(dir, &st) == 0 else { throw StartError.insecureDirectory(dir) }
        }
        guard st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { throw StartError.insecureDirectory(dir) }
        if st.st_mode & 0o777 != 0o700 { chmod(dir, 0o700) }
    }

    private func acceptLoop(_ listenFD: Int32, wake wakeRead: Int32) {
        defer { if wakeRead >= 0 { close(wakeRead) } }
        while state.withLock({ $0.running }) {
            // Czekanie bez blokady i bez limitu czasu (budzi `stop` przez potok); samo `accept` (gniazdo gotowe,
            // nieblokujące) i FD_CLOEXEC pod `DescriptorLock`.
            var fds = [pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0), pollfd(fd: wakeRead, events: Int16(POLLIN), revents: 0)]
            let ready = poll(&fds, wakeRead >= 0 ? 2 : 1, wakeRead >= 0 ? -1 : 1000)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }
            if wakeRead >= 0, fds[1].revents != 0 { break }
            if fds[0].revents & Int16(POLLNVAL | POLLHUP | POLLERR) != 0 { break }
            let (client, error) = DescriptorLock.withLock { () -> (Int32, Int32) in
                let c = accept(listenFD, nil, nil)
                let e = errno   // przed zwolnieniem blokady
                if c >= 0 {
                    _ = fcntl(c, F_SETFD, FD_CLOEXEC)
                    // Połączenie dziedziczy O_NONBLOCK gniazda nasłuchu — uzgadnianie czyta z limitem czasu, blokująco.
                    _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK)
                }
                return (c, e)
            }
            if client < 0 {
                if error == EINTR || error == EAGAIN || error == ECONNABORTED { continue }
                // Brak deskryptorów (EMFILE/ENFILE) — przejściowe: chwila przerwy zamiast trwałego końca serwera.
                if error == EMFILE || error == ENFILE {
                    usleep(200_000)
                    continue
                }
                break
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let t = Thread { [self] in handshake(client) }
            t.name = "pelikan.agent.handshake"
            t.start()
        }
    }

    private func reject(_ fd: Int32, _ reason: String, pid: pid_t?) {
        if let data = try? JSONEncoder().encode(Wire.Reply.error(reason)) { try? Wire.writeFrame(data, to: fd) }
        close(fd)
        onEvent(.rejected(reason: reason, pid: pid))
    }

    func handshake(_ fd: Int32) {
        // 1. UID rozmówcy.
        guard let peer = PeerCredentials.of(fd) else {
            reject(fd, "peer_unknown", pid: nil)
            return
        }
        guard peer.uid == getuid() else {
            reject(fd, "peer_uid", pid: peer.pid)
            return
        }
        // 2. Ramka hello z tokenem w ograniczonym czasie.
        Wire.setReadTimeout(fd, seconds: Self.helloTimeout)
        // Rozmiar sprawdzany przed odczytem treści — proces bez tokenu nie zajmie 4 MB na połączenie.
        guard let data = try? Wire.readFrame(from: fd, limit: 4096),
              let hello = try? JSONDecoder().decode(Wire.Hello.self, from: data), hello.type == "hello"
        else {
            reject(fd, "no_hello", pid: peer.pid)
            return
        }
        // Most z innej wersji protokołu — jasny błąd od razu, nie później w trakcie pracy.
        guard hello.version == Wire.protocolVersion else {
            reject(fd, "protocol_version", pid: peer.pid)
            return
        }
        // 3. Token (stały czas).
        guard let session = registry.authenticate(token: hello.token) else {
            reject(fd, "bad_token", pid: peer.pid)
            return
        }
        // 4. Proces po drugiej stronie musi być potomkiem procesu CLI tej sesji.
        guard let cli = session.cliPID, ProcessTree.ancestry(of: peer.pid).contains(cli) else {
            reject(fd, "not_descendant", pid: peer.pid)
            return
        }
        Wire.setReadTimeout(fd, seconds: 0)
        guard let welcome = try? JSONEncoder().encode(Wire.Reply.welcome), (try? Wire.writeFrame(welcome, to: fd)) != nil else {
            close(fd)
            return
        }
        onEvent(.accepted(sessionID: session.id, pid: peer.pid))
        onAccept(fd, session)
    }
}

/// UID i PID procesu po drugiej stronie gniazda Unix.
public enum PeerCredentials {
    // <sys/un.h>: SOL_LOCAL 0, LOCAL_PEERPID 0x002
    static let solLocal: Int32 = 0
    static let localPeerPID: Int32 = 0x002

    public static func of(_ fd: Int32) -> (uid: uid_t, pid: pid_t)? {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return nil }
        var pid: pid_t = 0
        var len = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, solLocal, localPeerPID, &pid, &len) == 0, pid > 0 else { return nil }
        return (uid, pid)
    }
}
#endif
