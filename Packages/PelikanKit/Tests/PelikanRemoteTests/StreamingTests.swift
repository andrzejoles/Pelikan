#if canImport(Darwin)
import Darwin
import Foundation
import Synchronization
import Testing
@testable import PelikanRemote

/// Oczekiwanie z limitem: przekroczenie kończy test błędem z nazwą etapu zamiast zawieszenia.
struct StageTimeout: Error, CustomStringConvertible { let stage: String; var description: String { "przekroczony limit etapu: \(stage)" } }
func withLimit<T: Sendable>(_ seconds: Double, _ stage: String, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    // Wyścig dwóch niezależnych zadań (grupa zadań czekałaby na zawieszone zadanie potomne).
    let resumed = Mutex(false)
    return try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, any Error>) in
        let finish: @Sendable (Result<T, any Error>) -> Void = { r in
            if resumed.withLock({ was in defer { was = true }; return !was }) { c.resume(with: r) }
        }
        Task.detached { do { finish(.success(try await body())) } catch { finish(.failure(error)) } }
        Task.detached { try? await Task.sleep(for: .seconds(seconds)); finish(.failure(StageTimeout(stage: stage))) }
    }
}

/// Zbiera zdarzenia strumienia (porcje tego samego rodzaju następujące po sobie są sklejane).
func collect(_ events: AsyncThrowingStream<SpawnEvent, any Error>) async throws -> [SpawnEvent] {
    var out: [SpawnEvent] = []
    for try await e in events {
        switch (out.last, e) {
        case let (.stdout(a)?, .stdout(b)): out[out.count - 1] = .stdout(a + b)
        case let (.stderr(a)?, .stderr(b)): out[out.count - 1] = .stderr(a + b)
        default: out.append(e)
        }
    }
    return out
}

func collect(_ events: AsyncThrowingStream<RemoteEvent, any Error>) async throws -> [RemoteEvent] {
    var out: [RemoteEvent] = []
    for try await e in events {
        switch (out.last, e) {
        case let (.stdout(a)?, .stdout(b)): out[out.count - 1] = .stdout(a + b)
        case let (.stderr(a)?, .stderr(b)): out[out.count - 1] = .stderr(a + b)
        default: out.append(e)
        }
    }
    return out
}

// Szeregowo: testy blokują wątki w Spawn.run i limitach czasu — równolegle na runnerze CI z 3 rdzeniami zagłodziły
// pulę współbieżności (zestaw wisiał do limitu skryptu, D168).
@Suite("Rozbudowa: strumień, stdin, limity, dekoder, prolog", .timeLimit(.minutes(1)), .serialized)
struct SpawnStreamTests {
    @Test("Kolejność porcji stdout/stderr i kod wyjścia")
    func order() async throws {
        let p = try Spawn.stream("/bin/sh", [Array("-c".utf8), Array("printf a; sleep 0.3; printf b >&2; sleep 0.3; printf c; exit 3".utf8)],
                                 environment: [:])
        let events = try await collect(p.events)
        #expect(events == [.stdout(Data("a".utf8)), .stderr(Data("b".utf8)), .stdout(Data("c".utf8)), .exit(3)])
    }

    @Test("stdin: dane i plik")
    func stdin() async throws {
        let r = try Spawn.run("/bin/cat", [], environment: [:], stdin: .data(Data("dane wejściowe\n".utf8)))
        #expect(String(decoding: r.output, as: UTF8.self) == "dane wejściowe\n")
        let dir = try TempDir()
        try dir.file("in.txt", "12345")
        let p = try Spawn.stream("/usr/bin/wc", [Array("-c".utf8)], environment: [:], stdin: .file(dir.path + "/in.txt"))
        let events = try await collect(p.events)
        #expect(String(decoding: { if case .stdout(let d) = events.first { d } else { Data() } }(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "5")
        // Duże wejście niewczytane przez proces nie zabija aplikacji (SIGPIPE).
        let big = try Spawn.run("/usr/bin/true", [], environment: [:], stdin: .data(Data(repeating: 65, count: 4 << 20)))
        #expect(big.status == 0)
    }

    @Test("Limit ciszy i limit całkowity; bez limitu (nil)")
    func timeouts() async throws {
        let start = Date()
        let p = try Spawn.stream("/bin/sleep", [Array("5".utf8)], environment: [:], silenceTimeout: 0.4)
        await #expect(throws: SSHError.timeout) { _ = try await collect(p.events) }
        #expect(Date().timeIntervalSince(start) < 3)
        // Wyjście co 0,2 s podtrzymuje proces mimo limitu ciszy 1,5 s (zapas na obciążony komputer/CI).
        let chatty = try Spawn.stream("/bin/sh", [Array("-c".utf8), Array("for i in 1 2 3 4 5; do echo $i; sleep 0.2; done".utf8)],
                                      environment: [:], silenceTimeout: 1.5)
        let ev = try await collect(chatty.events)
        #expect(ev.last == .exit(0))
        #expect(throws: SSHError.timeout) { try Spawn.run("/bin/sleep", [Array("5".utf8)], environment: [:], timeout: 0.3) }
        #expect(try Spawn.run("/bin/sleep", [Array("0.2".utf8)], environment: [:], timeout: nil).status == 0)
        // Anulowanie strumienia.
        let s = try Spawn.stream("/bin/sleep", [Array("5".utf8)], environment: [:])
        s.cancel()
        await #expect(throws: SSHError.cancelled) { _ = try await collect(s.events) }
    }

    @Test("Dekoder: znak UTF-8 rozcięty między porcjami, ISO-8859-2, \\r\\n z pty")
    func decoder() {
        var d = StreamTextDecoder(encoding: .utf8)
        let bytes = Array("zażółć".utf8)
        var text = ""
        for b in bytes { text += d.decode(Data([b])) }
        text += d.finish()
        #expect(text == "zażółć")
        var l = StreamTextDecoder(encoding: .latin2)
        #expect(l.decode(Data([0xB1, 0xB6])) == "ąś")
        var t = StreamTextDecoder(encoding: .utf8, normalizeNewlines: true)
        #expect(t.decode(Data("a\r".utf8)) == "a")
        #expect(t.decode(Data("\nb\r\nc".utf8)) == "\nb\nc")
        #expect(t.finish() == "")
    }

    /// Próbki z Linuksa (GNU coreutils, LC_ALL=C) i BSD/macOS (z flagą rozszerzonych atrybutów `@`, ACL `+`).
    /// Próbki AIX (wyżej, z Bifolda) do potwierdzenia na serwerze właściciela.
    @Test("ls -la: Linux i BSD")
    func listings() {
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
        let linux = """
        total 20
        drwxr-xr-x  3 build build 4096 Oct 17 09:15 .
        drwxr-xr-x 10 root  root  4096 Jan  2  2026 ..
        -rwxr-xr-x  1 build build 8760 Oct 16 18:30 rmsbatch
        -rw-r--r--  1 build build  312 Oct 16 18:29 Makefile
        lrwxrwxrwx  1 build build    8 Oct 17 09:15 latest -> rmsbatch
        brw-rw----  1 root  disk 8, 0 Oct 17 08:00 sda
        """
        let l = RemoteListing.parse(linux, now: now)
        #expect(l.map(\.name) == ["rmsbatch", "Makefile", "latest", "sda"])
        #expect(l[0].permissions == 0o755 && l[0].size == 8760 && l[2].linkTarget == "rmsbatch" && l[3].kind == .other && l[3].size == 0)
        let bsd = """
        total 16
        drwxr-xr-x@  4 aoles  staff   128 Oct 17 09:15 .
        -rw-r--r--@  1 aoles  staff  1234 Oct 15 10:00 notatki ąę.txt
        -rw-r--r--+  1 aoles  staff     7 Feb 29  2024 przestępny.txt
        drwxrwxrwt  12 root   wheel   384 Oct 17 11:59 tmp
        """
        let b = RemoteListing.parse(bsd, now: now)
        #expect(b.map(\.name) == ["notatki ąę.txt", "przestępny.txt", "tmp"])
        #expect(b[0].size == 1234 && b[2].kind == .directory && b[2].permissions == 0o1777)
        #expect(Calendar(identifier: .gregorian).component(.day, from: b[1].modified!) == 29)
    }

    @Test("Prolog środowiska: wartości dosłowne, nazwy sprawdzane")
    func prolog() throws {
        let prolog = try SSHSession.environmentProlog([("ORACLE_HOME", "/u01/app/oracle"), ("X", "a'b $HOME `id`")])
        #expect(prolog == "ORACLE_HOME='/u01/app/oracle'; export ORACLE_HOME; X='a'\\''b $HOME `id`'; export X; ")
        #expect(throws: SSHError.self) { try SSHSession.environmentProlog([("A;rm", "x")]) }
        let r = try Spawn.run("/bin/sh", [Array("-c".utf8), Array((prolog + "echo \"$X\"; sh -c 'echo $ORACLE_HOME'").utf8)], environment: [:])
        #expect(String(decoding: r.output, as: UTF8.self) == "a'b $HOME `id`\n/u01/app/oracle\n")
    }

    @Test("Zaufanie kluczowi: do known_hosts trafiają dokładnie potwierdzone klucze (bez komentarzy i powtórzeń), bez łączenia")
    func trustScannedHostKeys() throws {
        let dir = URL(fileURLWithPath: "/private/tmp/plk-kh-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        // Klucz publiczny z losowych bajtów (format ssh-ed25519; nic z ~/.ssh) — tylko jako poprawny wpis known_hosts.
        func field(_ b: [UInt8]) -> [UInt8] { withUnsafeBytes(of: UInt32(b.count).bigEndian, Array.init) + b }
        let blob = field(Array("ssh-ed25519".utf8)) + field((0..<32).map { _ in UInt8.random(in: 0...255) })
        let pub = ["ssh-ed25519", Data(blob).base64EncodedString()]
        let name = "[127.0.0.1]:2222"
        let keyscan = "# 127.0.0.1:2222 SSH-2.0-OpenSSH_9.9\n\(name) \(pub[0]) \(pub[1])\nzły wiersz\n\(name) ssh-rsa AAAA;rm\n127.0.0.1 \(pub[0]) \(pub[1])\n"
        let entries = SSHSession.knownHostsEntries(keyscan, name: name)
        #expect(entries == ["\(name) \(pub[0]) \(pub[1])"])

        let file = dir.path + "/known_hosts"
        try "inny ssh-ed25519 AAAA".write(toFile: file, atomically: true, encoding: .utf8)
        let session = try SSHSession(config: SSHSession.Config(host: "127.0.0.1", port: 2222, knownHostsFile: file), runDirectory: dir, secret: { nil })
        try session.trustHostKeys(SSHSession.HostKeyScan(entries: entries, fingerprints: []))
        #expect(try String(contentsOfFile: file, encoding: .utf8) == "inny ssh-ed25519 AAAA\n\(entries[0])\n")
        #expect(try session.unknownHostKeys() == nil)
    }
}

@Suite("Potok trzymany przez potomka (jak master ssh z ControlMaster)", .timeLimit(.minutes(1)))
struct SpawnHeldPipeTests {
    @Test("Proces zakończony, potomek w tle trzyma stdout 30 s — run i stream kończą się po kilku sekundach z danymi")
    func heldPipe() async throws {
        let script = "echo przed; sleep 30 & exit 0"
        let start = Date()
        let r = try Spawn.run("/bin/sh", [Array("-c".utf8), Array(script.utf8)], environment: [:])
        #expect(String(decoding: r.output, as: UTF8.self) == "przed\n" && r.status == 0)
        #expect(Date().timeIntervalSince(start) < 10, "run czekał na potomka trzymającego potok")
        let s2 = Date()
        let p = try Spawn.stream("/bin/sh", [Array("-c".utf8), Array(script.utf8)], environment: [:])
        let events = try await collect(p.events)
        #expect(events == [.stdout(Data("przed\n".utf8)), .exit(0)], "\(events)")
        #expect(Date().timeIntervalSince(s2) < 10, "strumień czekał na potomka trzymającego potok")
    }
}

@Suite("Rozbudowa na lokalnym sshd: strumień, stdin, Stop, ISO-8859-2", .serialized, .enabled(if: sshdAvailable), .timeLimit(.minutes(2)))
struct RemoteStreamTests {
    func connected(encoding: NameEncoding = .utf8) throws -> (TestSSHD, SSHSession, URL) {
        let sshd = try TestSSHD()
        let (s, run) = try sshd.session(encoding: encoding)
        try s.recordHostKey()
        try s.connect()
        return (sshd, s, run)
    }

    @Test("Strumień zdalny: prolog, kolejność, kod wyjścia, znacznik @@PID odcięty")
    func remoteStream() async throws {
        let (sshd, s, run) = try connected()
        defer { s.disconnect(); try? FileManager.default.removeItem(at: run); _ = sshd }
        let p = try s.stream("echo \"$FOO\"; sleep 0.3; printf 'x\\n' >&2; sleep 0.3; echo koniec; exit 4", environment: [("FOO", "a'b $X")])
        let events = try await collect(p.events)
        #expect(events == [.stdout("a'b $X\n"), .stderr("x\n"), .stdout("koniec\n"), .exit(4)], "\(events)")
        #expect(p.remoteProcessID != nil)
    }

    @Test("stdin do zdalnego polecenia")
    func remoteStdin() async throws {
        let (sshd, s, run) = try connected()
        defer { s.disconnect(); try? FileManager.default.removeItem(at: run); _ = sshd }
        let r = try s.run("cat", stdin: .data(Data("wiersz 1\nwiersz 2\n".utf8)))
        #expect(String(decoding: r.output, as: UTF8.self) == "wiersz 1\nwiersz 2\n")
        let dir = try TempDir()
        try dir.file("skrypt.sh", "echo z pliku\nexit 7\n")
        let p = try s.stream("sh -s", stdin: .file(dir.path + "/skrypt.sh"))
        #expect(try await collect(p.events) == [.stdout("z pliku\n"), .exit(7)])
    }

    @Test("ISO-8859-2 w poleceniu i wyjściu")
    func latin2() async throws {
        let (sshd, s, run) = try connected(encoding: .latin2)
        defer { s.disconnect(); try? FileManager.default.removeItem(at: run); _ = sshd }
        let r = try s.run("echo 'zażółć'")
        #expect(Array(r.output) == (try NameEncoding.latin2.encode("zażółć")) + [0x0A])
        let p = try s.stream("echo 'gęślą jaźń'")
        #expect(try await collect(p.events) == [.stdout("gęślą jaźń\n"), .exit(0)])
        #expect(throws: SSHError.unencodable("echo 😀")) { try s.run("echo 😀") }
    }

    /// Stop z pty: zakończenie `ssh -tt` kończy grupę procesów na serwerze (tu serwer = ten komputer, więc grupę
    /// sprawdzamy lokalnie `kill(-pid, 0)`).
    @Test("Stop z pty i bez pty: proces zdalny znika")
    func stop() async throws {
        let (sshd, s, run) = try connected()
        defer { s.disconnect(); try? FileManager.default.removeItem(at: run); _ = sshd }
        // Znaczniki etapów i limit każdego oczekiwania: sporadyczne zawieszenie na CI (macOS 26) ma wskazać etap,
        // zamiast zużyć limit całego testu.
        func stage(_ s: String) { print("[stop-test] \(s)"); fflush(stdout) }
        for tty in [true, false] {
            stage("tty \(tty): stream")
            let p = try s.stream("sleep 300; echo nie", tty: tty)
            for _ in 0..<100 where p.remoteProcessID == nil {
                // Zdarzenia czyta zadanie RemoteProcess; czekamy na znacznik @@PID.
                try await Task.sleep(for: .milliseconds(50))
            }
            let pid = try #require(p.remoteProcessID)
            #expect(kill(-pid, 0) == 0, "grupa procesów działa (tty: \(tty))")
            stage("tty \(tty): stop (pid \(pid))")
            try await withLimit(40, "stop") { await Task.detached { p.stop() }.value }
            var gone = false
            for _ in 0..<60 {
                if kill(-pid, 0) != 0 && errno == ESRCH { gone = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(gone, "proces zdalny zakończony (tty: \(tty))")
            stage("tty \(tty): zdarzenia")
            let outcome = try await withLimit(20, "zdarzenia") { () -> Result<[RemoteEvent], any Error> in
                do { return .success(try await collect(p.events)) } catch { return .failure(error) }
            }
            #expect(throws: SSHError.cancelled) { _ = try outcome.get() }
            stage("tty \(tty): koniec")
        }
    }
}
#endif
