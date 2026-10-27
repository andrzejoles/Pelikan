import Foundation
import Testing
@testable import PelikanLog

/// Dziennik aplikacji (PL-INFRA-011, D170).
@Suite struct LogMessageTests {
    func render(_ m: LogMessage, reveal: Bool = false) -> String {
        m.render(revealPrivate: reveal) { Log.hash($0, key: [1, 2, 3]) }
    }

    @Test("tekst domyślnie prywatny, liczby i wartości logiczne jawne")
    func defaultPrivacy() {
        let alias = "PROD_DB"
        let m: LogMessage = "Połączono z \(alias) w \(42) ms, ponowienie: \(false)"
        #expect(render(m) == "Połączono z <private> w 42 ms, ponowienie: nie")
        #expect(render(m, reveal: true) == "Połączono z PROD_DB w 42 ms, ponowienie: nie")
    }

    @Test("jawna, skrót i brak wartości")
    func explicitPrivacy() {
        let driver = "odpi", alias = "PROD_DB"
        let none: String? = nil
        let m: LogMessage = "sterownik \(driver, privacy: .public), połączenie \(alias, privacy: .hash), schemat \(none)"
        let text = render(m)
        #expect(text.hasPrefix("sterownik odpi, połączenie <#"))
        #expect(!text.contains("PROD_DB"))
        #expect(text.hasSuffix(">, schemat –"))
        // Ten sam tekst — ten sam skrót; inny klucz — inny skrót.
        #expect(Log.hash("PROD_DB", key: [1]) == Log.hash("PROD_DB", key: [1]))
        #expect(Log.hash("PROD_DB", key: [1]) != Log.hash("PROD_DB", key: [2]))
        #expect(Log.hash("PROD_DB", key: [1]).count == 6)
    }

    @Test("błąd: kod jawny, komunikat prywatny")
    func errors() {
        struct Failure: LogDescribableError {
            var logPublicDescription: String { "ORA-00942" }
            var logPrivateDescription: String? { "table or view \"HR\".\"SECRET\" does not exist" }
        }
        let m: LogMessage = "Błąd: \(Failure() as any Error)"
        #expect(render(m) == "Błąd: ORA-00942: <private>")
        #expect(render(m, reveal: true).contains("SECRET"))
        let ns = NSError(domain: "NSPOSIXErrorDomain", code: 13, userInfo: [NSLocalizedDescriptionKey: "Permission denied /x"])
        let n: LogMessage = "\(ns as any Error)"
        #expect(render(n) == "NSError (NSPOSIXErrorDomain 13): <private>")
        enum Sample: Error { case notConnected, failed(String) }
        let e: LogMessage = "\(Sample.failed("HR.TAJNE") as any Error)"
        #expect(render(e).hasPrefix("Sample.failed: <private>"))
        let c: LogMessage = "\(Sample.notConnected as any Error)"
        #expect(render(c).hasPrefix("Sample.notConnected"))
    }

    @Test("filtr haseł i katalogu domowego działa także na wartościach jawnych", arguments: [
        ("CONNECT scott/tiger@orcl", "CONNECT scott/***@orcl"),
        ("conn scott/tiger", "conn scott/***"),
        ("sqlplus \"sys\"/\"t i g\"@db as sysdba", "sqlplus \"sys\"/***@db as sysdba"),
        ("ALTER USER x IDENTIFIED BY \"Sekret1\" ACCOUNT UNLOCK", "ALTER USER x IDENTIFIED BY *** ACCOUNT UNLOCK"),
        ("create user x identified by values 'S:ABC;T:DEF'", "create user x identified by *** "),
        ("password=abc123;user=x", "password=***;user=x"),
        ("pwd: 'q w'", "pwd: ***"),
        ("https://user:pa55@example.com/x", "https://user:***@example.com/x"),
        ("ORA-01017: invalid username/password; logon denied", "ORA-01017: invalid username/password; logon denied"),
    ])
    func redaction(input: String, expected: String) {
        let m: LogMessage = "\(input, privacy: .public)"
        #expect(render(m) == expected.trimmingCharacters(in: .whitespaces))
    }

    @Test("ścieżka domowa zamieniona na ~")
    func homePath() {
        let path = NSHomeDirectory() + "/Library/Application Support/Pelikan/settings.json"
        let m: LogMessage = "\(path, privacy: .public)"
        #expect(render(m) == "~/Library/Application Support/Pelikan/settings.json")
    }
}

@Suite struct LogRoutingTests {
    @Test("poziom: niższe wpisy pomijane, treść nie jest budowana")
    func levels() {
        let sink = MemoryLogSink()
        let c = Log.Configuration(level: .notice, revealPrivate: false, hashKey: [], sinks: [sink])
        var built = 0
        func message(_ t: String) -> LogMessage { built += 1; return "\(t, privacy: .public)" }
        Log.emit(.info, LogCategory("t"), { message("pominięty") }, c)
        Log.emit(.notice, LogCategory("t"), { message("ważny") }, c)
        Log.emit(.error, LogCategory("t"), { message("błąd") }, c)
        #expect(sink.all.map(\.text) == ["ważny", "błąd"])
        #expect(built == 2)
    }

    @Test("ujście diagnostyczne dostaje wszystko z jawnymi wartościami, zwykłe — według ustawień")
    func diagnosticSink() {
        let regular = MemoryLogSink(), everything = MemoryLogSink(everything: true)
        let c = Log.Configuration(level: .info, revealPrivate: false, hashKey: [], sinks: [regular, everything])
        let name = "HR"
        Log.emit(.debug, LogCategory("t"), { "schemat \(name)" }, c)
        Log.emit(.info, LogCategory("t"), { "schemat \(name)" }, c)
        #expect(regular.all.map(\.text) == ["schemat <private>"])
        #expect(everything.all.map(\.text) == ["schemat HR", "schemat HR"])
    }

    @Test("dodatkowe ujście globalne")
    func extraSink() {
        let sink = MemoryLogSink(everything: true)
        let id = Log.addSink(sink)
        let marker = UUID().uuidString
        Log.tools.debug("znacznik \(marker, privacy: .public)")
        Log.removeSink(id)
        Log.tools.debug("po usunięciu \(marker, privacy: .public)")
        #expect(sink.all.filter { $0.text.contains(marker) }.map(\.text) == ["znacznik \(marker)"])
        #expect(sink.all.first { $0.text.contains(marker) }?.category == "tools")
    }
}

@Suite struct FileLogSinkTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-log-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("format linii, uprawnienia pliku i katalogu")
    func format() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = FileLogSink(directory: dir, baseName: "Test")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        sink.write(LogEntry(date: date, level: .notice, category: "connection", text: "pierwsza\ndruga"))
        sink.flush()
        let text = try String(contentsOf: sink.currentFile, encoding: .utf8)
        #expect(text.hasPrefix(FileLogSink.timestamp(date) + " UWAGA  connection  pierwsza\n\tdruga\n"))
        #expect(text.range(of: #"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}[+-]\d{4} "#, options: .regularExpression) != nil)
        let fileMode = try FileManager.default.attributesOfItem(atPath: sink.currentFile.path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(dirMode == 0o700)
    }

    @Test("rotacja: najwyżej `keep` starszych plików, najnowsze wpisy w bieżącym")
    func rotation() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = FileLogSink(directory: dir, baseName: "Test", maxBytes: 400, keep: 2)
        for i in 0..<40 {
            sink.write(LogEntry(date: Date(), level: .info, category: "t", text: "wpis \(i) " + String(repeating: "x", count: 40)))
        }
        sink.flush()
        let names = sink.files.map(\.lastPathComponent)
        #expect(names == ["Test.2.log", "Test.1.log", "Test.log"])
        for f in sink.files {
            let size = try FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int ?? 0
            #expect(size <= 400)
        }
        let current = try String(contentsOf: sink.currentFile, encoding: .utf8)
        #expect(current.contains("wpis 39 "))
    }

    @Test("zapis z wielu wątków bez utraty i przeplotu linii")
    func concurrentWrites() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = FileLogSink(directory: dir, baseName: "Test")
        await withTaskGroup(of: Void.self) { g in
            for t in 0..<8 {
                g.addTask {
                    for i in 0..<100 { sink.write(LogEntry(date: Date(), level: .info, category: "t", text: "w\(t)-\(i)")) }
                }
            }
        }
        sink.flush()
        let lines = try String(contentsOf: sink.currentFile, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 800)
        #expect(lines.allSatisfy { $0.range(of: #" t {9}  w\d-\d+$"#, options: .regularExpression) != nil })
    }
}
