// Pochodzi z BiFold (Remote/SSH.swift @ a1ee643), dalej rozwijany w Pelikanie.
#if canImport(Darwin)
import Darwin
import Foundation
import Synchronization

/// Wejście procesu.
public enum SpawnInput: Sendable {
    case null
    /// Dane zapisywane na stdin (np. `cat > plik`, `ksh -s`), potem stdin zamykane.
    case data(Data)
    /// Plik lokalny jako stdin.
    case file(String)
}

/// Zdarzenie procesu uruchomionego strumieniowo — porcje w kolejności odczytu, na końcu kod wyjścia.
public enum SpawnEvent: Sendable, Equatable {
    case stdout(Data)
    case stderr(Data)
    case exit(Int32)
}

/// Uruchamianie programu przez `posix_spawn` z argumentami jako dokładne bajty. `Foundation.Process`
/// zamienia argumenty na NFD, co psuje polskie nazwy na serwerach porównujących bajty (np. AIX).
public enum Spawn {
    public struct Result: Sendable {
        public var status: Int32
        public var output: Data
        public var error: Data

        public var errorText: String { String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public enum Output: Sendable {
        case capture
        /// Do pliku (procesy, które zostają w tle i trzymałyby otwarty potok, np. `ssh` z ControlPersist).
        case file(String)
    }

    /// Proces z potokami: pid i deskryptory (odczyt stdout/stderr, zapis stdin).
    struct Launched {
        var pid: pid_t
        var stdout: Int32
        var stderr: Int32
        var stdin: Int32
    }

    static func cString(_ bytes: [UInt8]) -> UnsafeMutablePointer<CChar>? {
        let p = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count + 1)
        for (i, b) in bytes.enumerated() { p[i] = CChar(bitPattern: b) }
        p[bytes.count] = 0
        return p
    }

    static func launch(_ executable: String, _ args: [[UInt8]], environment: [String: String], stdin: SpawnInput,
                       output: Output) throws -> Launched {
        var outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1], inPipe: [Int32] = [-1, -1]
        func closeAll() { for fd in outPipe + errPipe + inPipe where fd >= 0 { close(fd) } }
        if case .capture = output {
            guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else { closeAll(); throw SSHError.io(code: errno, detail: executable) }
        }
        if case .data = stdin {
            guard pipe(&inPipe) == 0 else { closeAll(); throw SSHError.io(code: errno, detail: executable) }
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        switch stdin {
        case .null: posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        case .file(let path): posix_spawn_file_actions_addopen(&actions, 0, path, O_RDONLY, 0)
        case .data: posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0)
        }
        switch output {
        case .capture:
            posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
            posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        case .file(let path):
            posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
            posix_spawn_file_actions_addopen(&actions, 2, path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Tylko 0–2 przechodzą do procesu potomnego (bez gniazd agenta i innych deskryptorów aplikacji).
        // Domyślne obsługi i pusta maska sygnałów (proces potomny dziedziczyłby blokady wątku).
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for sig in [SIGPIPE, SIGTERM, SIGINT, SIGHUP] { sigaddset(&defaults, sig) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attr, &mask)

        let argv: [UnsafeMutablePointer<CChar>?] = ([Array(executable.utf8)] + args).map(cString) + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { cString(Array("\($0.key)=\($0.value)".utf8)) } + [nil]
        defer { (argv + envp).forEach { $0?.deallocate() } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &actions, &attr, argv, envp)
        for fd in [outPipe[1], errPipe[1], inPipe[0]] where fd >= 0 { close(fd) }
        guard rc == 0 else {
            for fd in [outPipe[0], errPipe[0], inPipe[1]] where fd >= 0 { close(fd) }
            throw SSHError.io(code: rc, detail: executable)
        }
        if inPipe[1] >= 0 {
            // Zapis wejścia w tle; zamknięcie potoku = koniec danych dla procesu.
            let fd = inPipe[1]
            if case .data(let d) = stdin {
                Thread.detachNewThread {
                    // Proces, który nie czyta całego wejścia, nie może zabić aplikacji sygnałem SIGPIPE.
                    _ = fcntl(fd, F_SETNOSIGPIPE, 1)
                    d.withUnsafeBytes { buf in
                        var off = 0
                        while off < buf.count {
                            let n = write(fd, buf.baseAddress! + off, buf.count - off)
                            if n < 0 { if errno == EINTR { continue }; break }
                            off += n
                        }
                    }
                    close(fd)
                }
            }
        }
        return Launched(pid: pid, stdout: outPipe[0], stderr: errPipe[0], stdin: -1)
    }

    static func exitCode(_ status: Int32) -> Int32 {
        (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    }

    /// Uruchamia i czeka. `isPaused` wstrzymuje proces sygnałem SIGSTOP, `isCancelled` kończy go.
    /// `timeout: nil` — bez limitu.
    public static func run(
        _ executable: String, _ args: [[UInt8]], environment: [String: String], stdin: SpawnInput = .null, output: Output = .capture,
        timeout: TimeInterval? = 120, isCancelled: @Sendable () -> Bool = { false }, isPaused: @Sendable () -> Bool = { false }
    ) throws -> Result {
        let p = try launch(executable, args, environment: environment, stdin: stdin, output: output)
        let collected = Mutex<(out: Data, err: Data)>((Data(), Data()))
        let group = DispatchGroup()
        let readStop = ReadStop()
        if case .capture = output {
            for (fd, isError) in [(p.stdout, false), (p.stderr, true)] {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    var data = Data()
                    readUntilEOF(fd, stop: readStop) { buffer, n in data.append(buffer, count: n) }
                    collected.withLock { if isError { $0.err = data } else { $0.out = data } }
                    group.leave()
                }
            }
        }
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        var stopped = false
        var status: Int32 = 0
        var cancelled = false, timedOut = false
        while true {
            let r = waitpid(p.pid, &status, WNOHANG)
            if r == p.pid { break }
            if r < 0, errno != EINTR { break }
            let expired = deadline.map { Date() > $0 } ?? false
            if isCancelled() || expired {
                cancelled = isCancelled()
                timedOut = !cancelled
                if stopped { kill(p.pid, SIGCONT) }
                kill(p.pid, SIGTERM)
                var waited = 0
                while waitpid(p.pid, &status, WNOHANG) == 0 {
                    if waited == 100 { kill(p.pid, SIGKILL) }
                    usleep(20_000)
                    waited += 1
                }
                break
            }
            let pause = isPaused()
            if pause != stopped {
                kill(p.pid, pause ? SIGSTOP : SIGCONT)
                stopped = pause
            }
            usleep(20_000)
        }
        if group.wait(timeout: .now() + readGraceAfterExit) == .timedOut {
            readStop.set()
            group.wait()
        }
        if cancelled { throw SSHError.cancelled }
        if timedOut { throw SSHError.timeout }
        let (out, err) = collected.withLock { $0 }
        return Result(status: exitCode(status), output: out, error: err)
    }

    /// Uruchamia strumieniowo: porcje stdout/stderr na bieżąco, na końcu `.exit`. `timeout` — limit całkowity,
    /// `silenceTimeout` — limit czasu bez żadnego wyjścia (nil — bez limitu); przekroczenie kończy proces
    /// (SIGTERM, po 5 s SIGKILL) i strumień błędem `SSHError.timeout`.
    public static func stream(_ executable: String, _ args: [[UInt8]], environment: [String: String], stdin: SpawnInput = .null,
                              timeout: TimeInterval? = nil, silenceTimeout: TimeInterval? = nil) throws -> SpawnedProcess {
        let p = try launch(executable, args, environment: environment, stdin: stdin, output: .capture)
        return SpawnedProcess(p, timeout: timeout, silenceTimeout: silenceTimeout)
    }
}

/// Odczyt deskryptora do końca danych albo do sygnału `stop`. Klient `ssh` z ControlMaster przekazuje swoje stdio
/// procesowi głównemu, więc po zabiciu klienta koniec zapisu potoku może trzymać master aż do zamknięcia zdalnej sesji —
/// `read` bez limitu potrafił wtedy wisieć bez końca (zawieszenia testów Stop na CI). `poll` co 200 ms i flaga `stop`
/// ograniczają czas odczytu po zakończeniu procesu lokalnego.
final class ReadStop: Sendable {
    private let flag = Mutex(false)
    var isSet: Bool { flag.withLock { $0 } }
    func set() { flag.withLock { $0 = true } }
}

func readUntilEOF(_ fd: Int32, stop: ReadStop, _ chunk: ([UInt8], Int) -> Void) {
    var buffer = [UInt8](repeating: 0, count: 65536)
    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    while true {
        pfd.revents = 0
        let pr = poll(&pfd, 1, 200)
        if pr < 0 { if errno == EINTR { continue }; break }
        if pr == 0 { if stop.isSet { break }; continue }
        let n = read(fd, &buffer, buffer.count)
        if n < 0, errno == EINTR || errno == EAGAIN { continue }
        if n <= 0 { break }
        chunk(buffer, n)
    }
    close(fd)
}

/// Po zakończeniu procesu: czas na dociągnięcie danych, potem przerwanie odczytu (master `ssh` może trzymać potok).
let readGraceAfterExit: TimeInterval = 3

/// Stan procesu dzielony przez wątki odczytu, nadzoru i Stop.
final class SpawnState: Sendable {
    /// `reaped` — proces odebrany przez `waitpid` (jego pid może już należeć do innego procesu).
    let value = Mutex<(lastActivity: Date, finished: Bool, reaped: Bool, reason: SSHError?)>((Date(), false, false, nil))
    /// Wysyłanie zdarzeń pod jedną blokadą (kolejność porcji w każdym potoku).
    let emit = Mutex(())
}

/// Proces uruchomiony strumieniowo (`Spawn.stream`).
public final class SpawnedProcess: Sendable {
    public let pid: pid_t
    public let events: AsyncThrowingStream<SpawnEvent, any Error>
    private let shared = SpawnState()

    init(_ p: Spawn.Launched, timeout: TimeInterval?, silenceTimeout: TimeInterval?) {
        pid = p.pid
        let (stream, continuation) = AsyncThrowingStream<SpawnEvent, any Error>.makeStream()
        events = stream
        let shared = shared
        let pid = p.pid
        let group = DispatchGroup()
        let readStop = ReadStop()
        // Jeden wątek na deskryptor; zdarzenia wysyłane pod blokadą, więc kolejność w każdym potoku zachowana.
        for (fd, isError) in [(p.stdout, false), (p.stderr, true)] {
            group.enter()
            Thread.detachNewThread {
                readUntilEOF(fd, stop: readStop) { buffer, n in
                    let d = Data(buffer[0..<n])
                    shared.emit.withLock { _ in
                        shared.value.withLock { $0.lastActivity = Date() }
                        continuation.yield(isError ? .stderr(d) : .stdout(d))
                    }
                }
                group.leave()
            }
        }
        let started = Date()
        Thread.detachNewThread {
            var status: Int32 = 0
            var exited = false
            while !exited {
                let r = waitpid(pid, &status, WNOHANG)
                if r == pid { shared.value.withLock { $0.reaped = true }; exited = true; break }
                if r < 0, errno != EINTR { break }
                let now = Date()
                let (last, reason) = shared.value.withLock { ($0.lastActivity, $0.reason) }
                let total = timeout.map { now.timeIntervalSince(started) > $0 } ?? false
                let silent = silenceTimeout.map { now.timeIntervalSince(last) > $0 } ?? false
                if reason == nil, total || silent {
                    shared.value.withLock { $0.reason = .timeout }
                    SpawnedProcess.terminate(pid, shared)
                }
                usleep(20_000)
            }
            if group.wait(timeout: .now() + readGraceAfterExit) == .timedOut {
                readStop.set()
                group.wait()
            }
            let reason = shared.value.withLock { s -> SSHError? in
                s.finished = true
                return s.reason
            }
            if let reason {
                continuation.finish(throwing: reason)
            } else {
                continuation.yield(.exit(Spawn.exitCode(status)))
                continuation.finish()
            }
        }
    }

    /// SIGTERM, po 5 s SIGKILL (proces, który nie reaguje) — tylko dopóki proces nie został odebrany przez `waitpid`
    /// (potem jego pid może należeć do innego procesu).
    static func terminate(_ pid: pid_t, _ shared: SpawnState) {
        shared.value.withLock { if !$0.reaped { kill(pid, SIGTERM) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            shared.value.withLock { if !$0.reaped { kill(pid, SIGKILL) } }
        }
    }

    /// Zatrzymanie przez użytkownika — strumień kończy się błędem `SSHError.cancelled`.
    public func cancel() {
        let shouldKill = shared.value.withLock { s -> Bool in
            guard !s.finished, s.reason == nil else { return false }
            s.reason = .cancelled
            return true
        }
        if shouldKill { Self.terminate(pid, shared) }
    }
}
#endif
