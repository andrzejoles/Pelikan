// Pochodzi z BiFold (Tests/BifoldWorkspaceTests/ScpTests.swift @ a1ee643), dalej rozwijany w Pelikanie.
#if canImport(Darwin)
import Foundation
@testable import PelikanRemote

/// Katalog tymczasowy usuwany przy zwolnieniu.
final class TempDir: @unchecked Sendable {
    let url: URL
    init(prefix: String = "pelikan-remote") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    var path: String { url.path }
    func file(_ rel: String, _ text: String) throws {
        let u = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: u)
    }
    func read(_ rel: String) throws -> String { try String(contentsOf: url.appendingPathComponent(rel), encoding: .utf8) }
    func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent(rel).path) }
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Testowy serwer SSH bez roota (tylko bieżący użytkownik, logowanie kluczem, 127.0.0.1, losowy port). Domyślnie jak
/// stary AIX: wyłącznie stare algorytmy i bez podsystemu SFTP — działa tylko klasyczne SCP. Nie dotyka `~/.ssh`:
/// klucze, `ssh_config` i `known_hosts` w katalogu tymczasowym.
final class TestSSHD: @unchecked Sendable {
    let dir: TempDir
    let root: TempDir
    let port: Int
    let process: Process
    let clientKey: String
    let clientConfig: String
    let knownHosts: String
    /// Hasło klucza testowego — losowe na każde uruchomienie (klucz tymczasowy, tylko na czas testu).
    /// (ASCII: `ssh-keygen` w teście idzie przez Foundation.Process, który zapisałby polskie znaki w NFD.)
    static let passphrase = "k " + UUID().uuidString

    init(sftp: Bool = false) throws {
        dir = try TempDir(prefix: "pelikan-sshd")
        root = try TempDir(prefix: "pelikan-sshd-root")
        let d = dir.url.path
        func keygen(_ args: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            p.arguments = ["-q"] + args
            p.detachStandardIO()
            try p.run()
            p.waitForExit(timeout: 30)
        }
        try keygen(["-t", "rsa", "-b", "2048", "-N", "", "-f", d + "/host_rsa"])
        try keygen(["-t", "ed25519", "-N", Self.passphrase, "-f", d + "/client_key"])
        try FileManager.default.copyItem(atPath: d + "/client_key.pub", toPath: d + "/authorized_keys")
        clientKey = d + "/client_key"
        clientConfig = d + "/ssh_config"
        knownHosts = d + "/known_hosts"
        try Data().write(to: URL(fileURLWithPath: clientConfig))
        var lastError = ""
        for _ in 0..<5 {
            let port = Int.random(in: 20000...45000)
            let config = """
            Port \(port)
            ListenAddress 127.0.0.1
            HostKey \(d)/host_rsa
            PidFile \(d)/sshd.pid
            AuthorizedKeysFile \(d)/authorized_keys
            UsePAM no
            StrictModes no
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            HostKeyAlgorithms ssh-rsa
            PubkeyAcceptedAlgorithms +ssh-rsa
            KexAlgorithms diffie-hellman-group14-sha1
            Ciphers aes128-cbc
            \(sftp ? "Subsystem sftp internal-sftp" : "")
            """
            try Data(config.utf8).write(to: URL(fileURLWithPath: d + "/sshd_config"))
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
            p.arguments = ["-D", "-f", d + "/sshd_config", "-E", d + "/sshd.log"]
            // Bez dziedziczenia stdout/stderr testów: procesy potomne sshd (sesje trzymane przez ControlPersist) żyją
            // po teście i trzymałyby otwarty potok wyjścia — `swift test | tee` czekałby w nieskończoność (CI).
            p.detachStandardIO()
            try p.run()
            for _ in 0..<50 where p.isRunning {
                if (try? String(contentsOfFile: d + "/sshd.log", encoding: .utf8))?.contains("Server listening") == true {
                    self.port = port
                    process = p
                    return
                }
                usleep(50_000)
            }
            p.terminateAndWait()
            lastError = (try? String(contentsOfFile: d + "/sshd.log", encoding: .utf8)) ?? ""
        }
        throw SSHError.io(code: 0, detail: "sshd: \(lastError)")
    }

    /// Sesja do tego serwera (katalog run krótki — limit sun_path).
    func session(legacy: Bool = true, encoding: NameEncoding = .utf8, secret: String? = TestSSHD.passphrase,
                 runDirectory: URL? = nil) throws -> (SSHSession, URL) {
        let run = try runDirectory ?? SocketDirectory.make(preferred: URL(fileURLWithPath: "/tmp/plk-\(UUID().uuidString.prefix(6))"))
        let config = SSHSession.Config(host: "127.0.0.1", port: port, user: NSUserName(), keyFile: clientKey, legacyAlgorithms: legacy,
                                       encoding: encoding, configFile: clientConfig, knownHostsFile: knownHosts)
        let s = try SSHSession(config: config, runDirectory: run, secret: { secret })
        return (s, run)
    }

    deinit {
        process.terminateAndWait()
    }
}

extension Process {
    /// stdin, stdout i stderr procesu na /dev/null.
    func detachStandardIO() {
        standardInput = FileHandle.nullDevice
        standardOutput = FileHandle.nullDevice
        standardError = FileHandle.nullDevice
    }

    /// Czeka na zakończenie najwyżej `timeout` sekund; `true` — proces się zakończył. Bez `waitUntilExit()`: ten kręci
    /// pętlą zdarzeń bieżącego wątku i potrafił nie wrócić wcale (wątek puli zadań w `deinit` po teście — zawieszenie
    /// całego przebiegu, którego `.timeLimit` nie przerywa). `isRunning` odświeża Foundation bez pętli zdarzeń.
    @discardableResult
    func waitForExit(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while isRunning {
            if Date() > deadline { return false }
            usleep(20_000)
        }
        return true
    }

    /// SIGTERM, po 5 s SIGKILL — w ograniczonym czasie, nawet gdy proces nie reaguje.
    func terminateAndWait() {
        guard isRunning else { return }
        terminate()
        if !waitForExit(timeout: 5) {
            kill(processIdentifier, SIGKILL)
            waitForExit(timeout: 5)
        }
    }
}

let sshdAvailable = FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd") && FileManager.default.isExecutableFile(atPath: "/usr/bin/scp")
#endif
