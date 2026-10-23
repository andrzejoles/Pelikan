// Pochodzi z BiFold (Tests/BifoldWorkspaceTests/ScpTests.swift @ a1ee643), dalej rozwijany w Pelikanie.
// Przeniesione testy warstwy SSH (bez modelu zdalnych systemów plików Bifolda) — punkt odniesienia przed rozbudową.
#if canImport(Darwin)
import Foundation
import Testing
@testable import PelikanRemote

@Suite("Przeniesione z Bifolda: parser, kodowanie, Spawn")
struct PortedParserTests {
    /// Wyjście `ls -la` z AIX 6.1 (grupy „system”/„staff”, pliki urządzeń, dowiązania, daty bez roku) — format z Bifolda,
    /// sprawdzony tam na AIX 6.1; w Pelikanie do potwierdzenia na serwerze właściciela.
    @Test("ls -la z AIX 6.1")
    func aixListing() throws {
        let text = """
        total 48
        drwxr-xr-x    5 oracle   dba             256 Oct 17 09:15 .
        drwxr-xr-x   22 root     system         4096 Jan 12  2024 ..
        -rw-r--r--    1 oracle   dba         1048576 Mar  3  2025 alert_PROD.log
        -rwsr-x---    1 root     system        12345 Oct 16 23:59 suid prog
        drwxr-x---    2 oracle   dba             256 Sep  1 08:00 trace (stare)
        lrwxrwxrwx    1 oracle   dba              17 Oct 17 09:15 current -> trace (stare)
        crw-rw-rw-    1 root     system      2,  2 Oct 17 08:00 null
        -rw-------    1 oracle   dba               0 Dec 31 23:00 przyszły.txt
        """
        let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
        let items = RemoteListing.parse(text, now: now)
        #expect(items.map(\.name) == ["alert_PROD.log", "suid prog", "trace (stare)", "current", "null", "przyszły.txt"])
        #expect(items[0].size == 1_048_576 && items[0].kind == .file && items[0].permissions == 0o644)
        #expect(items[1].permissions == 0o4750)
        #expect(items[2].kind == .directory && items[3].kind == .symlink && items[3].linkTarget == "trace (stare)")
        #expect(items[4].kind == .other && items[4].size == 0)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.year, from: items[0].modified!) == 2025)
        #expect(cal.component(.year, from: items[1].modified!) == 2026 && cal.component(.hour, from: items[1].modified!) == 23)
        // „Dec 31” bez roku przy dacie bieżącej w październiku to zeszły rok.
        #expect(cal.component(.year, from: items[5].modified!) == 2025)
    }

    @Test("Escapowanie scp, shellQuote, kodowanie nazw")
    func escapingAndEncoding() throws {
        #expect(String(decoding: try SSHSession.scpEscape("/a b/(1)&'x'.txt", .utf8), as: UTF8.self) == "/a\\ b/\\(1\\)\\&\\'x\\'.txt")
        #expect(String(decoding: try SSHSession.scpEscape("/zażółć", .utf8), as: UTF8.self) == "/zażółć")
        #expect(throws: SSHError.self) { try SSHSession.scpEscape("/a\nb", .utf8) }
        #expect(SSHSession.shellQuote("it's") == "'it'\\''s'")
        // ISO-8859-2: „ą” = 0xB1, „ś” = 0xB6; nazwy z NFD zamieniane na NFC.
        #expect(try NameEncoding.latin2.encode("ąś") == [0xB1, 0xB6])
        #expect(try NameEncoding.utf8.encode("a\u{0328}") == [0xC4, 0x85])
        #expect(NameEncoding.latin2.decode(Data([0xB1, 0xB6])) == "ąś")
        #expect(throws: SSHError.unencodable("😀")) { try NameEncoding.latin2.encode("😀") }
    }

    /// Argumenty idą do procesu bajt w bajt (Foundation.Process zamieniłby je na NFD).
    @Test("Spawn przekazuje dokładne bajty")
    func spawnPassesExactBytes() throws {
        let r = try Spawn.run("/bin/echo", [Array("zażółć".utf8)], environment: [:])
        #expect(Array(r.output) == Array("zażółć\n".utf8))
        let latin = try Spawn.run("/bin/echo", [try NameEncoding.latin2.encode("ą")], environment: [:])
        #expect(Array(latin.output) == [0xB1, 0x0A])
    }

    @Test("Spawn: anulowanie")
    func spawnCancel() throws {
        let start = Date()
        #expect(throws: SSHError.cancelled) {
            try Spawn.run("/bin/sleep", [Array("5".utf8)], environment: [:], isCancelled: { Date().timeIntervalSince(start) > 0.3 })
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test("Host i użytkownik nie wstrzykną opcji ssh")
    func hostAndUserCannotInjectOptions() throws {
        let dir = try TempDir()
        for host in ["-oProxyCommand=x", "a b", "host;rm"] {
            #expect(throws: SSHError.self) { try SSHSession(config: .init(host: host), runDirectory: dir.url, secret: { nil }) }
        }
        #expect(throws: SSHError.self) { try SSHSession(config: .init(host: "h", user: "-oX"), runDirectory: dir.url, secret: { nil }) }
    }
}

@Suite("Przeniesione z Bifolda: lokalny sshd", .serialized, .enabled(if: sshdAvailable), .timeLimit(.minutes(2)))
struct PortedServerTests {
    /// Stary serwer tylko z SCP: hasło klucza przez askpass/FIFO, polecenia, scp w obie strony z polskimi
    /// i specjalnymi znakami, listing `ls -la`, bez śladów w katalogu run.
    @Test("Serwer tylko SCP ze starymi algorytmami")
    func scpOnlyServerWithLegacyAlgorithms() throws {
        let sshd = try TestSSHD()
        let (session, run) = try sshd.session()
        defer { session.disconnect(); try? FileManager.default.removeItem(at: run) }
        try sshd.root.file("plik z spacją.txt", "abc")
        try sshd.root.file("kat (1)/pod/a&b'c.txt", "x")
        try sshd.root.file("zażółć gęślą.txt", "polskie")
        try session.recordHostKey()
        try session.connect()
        #expect(session.isConnected)
        let runFiles = try FileManager.default.contentsOfDirectory(atPath: run.path)
        #expect(!runFiles.contains { $0.hasPrefix("askpass-") || $0.hasSuffix(".log") })

        let listing = try session.run("cd \(SSHSession.shellQuote(sshd.root.path)) && LC_ALL=C ls -la")
        let names = Set(RemoteListing.parse(String(decoding: listing.output, as: UTF8.self)).map(\.name))
        #expect(names.isSuperset(of: ["plik z spacją.txt", "kat (1)", "zażółć gęślą.txt"]), "\(names)")

        let local = try TempDir()
        try session.scp(download: sshd.root.path + "/kat (1)/pod/a&b'c.txt", to: local.path + "/pobrany.txt")
        #expect(try local.read("pobrany.txt") == "x")
        try session.scp(download: sshd.root.path + "/zażółć gęślą.txt", to: local.path + "/pl.txt")
        #expect(try local.read("pl.txt") == "polskie")
        try local.file("raport ąę.txt", "raport")
        try session.scp(upload: local.path + "/raport ąę.txt", to: sshd.root.path + "/wysłany ąę.txt")
        #expect(try sshd.root.read("wysłany ąę.txt") == "raport")
    }

    /// Katalog danych aplikacji to „~/Library/Application Support/…” — ze spacją w ścieżce gniazda.
    @Test("Katalog run ze spacjami")
    func runDirectoryWithSpaces() throws {
        let sshd = try TestSSHD()
        let dir = URL(fileURLWithPath: "/private/tmp/pelikan sp-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = SSHSession.Config(host: "127.0.0.1", port: sshd.port, user: NSUserName(), keyFile: sshd.clientKey, legacyAlgorithms: true,
                                       configFile: sshd.clientConfig, knownHostsFile: dir.appendingPathComponent("known hosts").path)
        let session = try SSHSession(config: config, runDirectory: dir, secret: { TestSSHD.passphrase })
        defer { session.disconnect() }
        try session.recordHostKey()
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("known hosts").path))
        try session.connect()
        let r = try session.run("echo ok")
        #expect(r.status == 0 && String(decoding: r.output, as: UTF8.self) == "ok\n", "\(r.errorText)")
        #expect(SSHSession.pathValue("/a b/%h") == "\"/a b/%%h\"")
    }

    @Test("Bez trybu zgodności stary serwer odrzuca negocjację")
    func modernClientWithoutLegacyModeFails() throws {
        let sshd = try TestSSHD()
        let (session, run) = try sshd.session(legacy: false)
        defer { try? FileManager.default.removeItem(at: run) }
        do {
            try session.connect()
            Issue.record("połączenie bez trybu zgodności nie powinno się udać")
        } catch let e as SSHError {
            if case .negotiationFailed = e {} else { Issue.record("oczekiwano negotiationFailed, jest \(e)") }
        }
    }

    @Test("Złe hasło klucza — odmowa")
    func wrongPassphraseIsRejected() throws {
        let sshd = try TestSSHD()
        let (session, run) = try sshd.session(secret: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: run) }
        #expect(throws: SSHError.self) { try session.connect() }
    }

    /// Podstawiony serwer (inny klucz pod tym samym adresem) jest odrzucany — hasło nie trafia do niego.
    @Test("Zmieniony klucz serwera — odrzucenie")
    func changedHostKeyIsRejected() throws {
        let sshd = try TestSSHD()
        let other = try TempDir()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        p.arguments = ["-q", "-t", "rsa", "-b", "2048", "-N", "", "-f", other.path + "/k"]
        try p.run()
        p.waitUntilExit()
        let fake = try String(contentsOfFile: other.path + "/k.pub", encoding: .utf8).split(separator: " ").prefix(2).joined(separator: " ")
        try Data("[127.0.0.1]:\(sshd.port) \(fake)\n".utf8).write(to: URL(fileURLWithPath: sshd.knownHosts))
        let (session, run) = try sshd.session()
        defer { try? FileManager.default.removeItem(at: run) }
        do {
            try session.connect()
            Issue.record("połączenie z serwerem o zmienionym kluczu nie powinno się udać")
        } catch let e as SSHError {
            if case .hostKeyChanged = e {} else { Issue.record("oczekiwano hostKeyChanged, jest \(e)") }
        }
    }
}
#endif
