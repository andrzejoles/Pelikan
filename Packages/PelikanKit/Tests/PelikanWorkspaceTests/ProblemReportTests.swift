import Foundation
import PelikanDB
import PelikanLog
@testable import PelikanWorkspace
import Testing

/// Zgłaszanie problemów na GitHubie (PL-INFRA-013, D173).
@MainActor
@Suite("Zgłoszenie problemu")
struct ProblemReportTests {
    func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test("treść: sekcje, filtr haseł i ścieżki domowej, blok kodu odporny na ```")
    func body() {
        var r = ProblemReport(origin: .error("ORA-01017 przy CONNECT scott/tiger@db\n" + NSHomeDirectory() + "/plik.sql"),
                              environment: "Wersja: 1.0 (1)", logTail: ["2026-10-26 10:00:00.000+0100 INFO  app  Start", "```"])
        r.details = "Kliknąłem Wykonaj, password=abc"
        let text = r.body()
        #expect(r.title.hasPrefix("Błąd: ORA-01017"))
        #expect(text.contains("### Co się stało"))
        #expect(text.contains("### Komunikat błędu"))
        #expect(text.contains("### Środowisko"))
        #expect(text.contains("### Ostatnie wpisy dziennika"))
        #expect(!text.contains("tiger") && !text.contains("abc"))
        #expect(!text.contains(NSHomeDirectory()))
        #expect(text.contains("~/plik.sql"))
        #expect(text.contains("````\n"))
        r.includeEnvironment = false
        r.includeLog = false
        #expect(!r.body().contains("### Środowisko") && !r.body().contains("### Ostatnie wpisy"))
        #expect(ProblemReport(origin: .manual, title: "Coś", environment: "", logTail: []).title == "Coś")
        #expect(ProblemReport(origin: .crash(nil), environment: "", logTail: []).title == "Awaria: nieoczekiwane zamknięcie")
    }

    @Test("R3-05: tytuł z samego kodu błędu, komunikat do edycji albo pominięcia")
    func errorMessageOptional() {
        var r = ProblemReport(origin: .error("ORA-20001: Klient Jan Kowalski nie ma limitu\nORA-06512: at \"HR.LIMITY\", line 7"),
                              environment: "", logTail: [])
        #expect(r.title == "Błąd: ORA-20001")
        #expect(r.body().contains("Jan Kowalski"))
        r.errorMessage = "ORA-20001: (dane usunięte)"
        #expect(!r.body().contains("Kowalski") && r.body().contains("(dane usunięte)"))
        r.includeErrorMessage = false
        #expect(!r.body().contains("### Komunikat błędu") && !r.body().contains("ORA-20001"))
        #expect(ProblemReport(origin: .error("Nie można otworzyć pliku /Volumes/Klient/umowa.sql"), environment: "", logTail: []).title == "Błąd w aplikacji")
    }

    @Test("adres nowego zgłoszenia: repozytorium, tytuł, treść, znak +")
    func url() throws {
        var r = ProblemReport(origin: .manual, title: "Okno + wynik", environment: "Wersja: 1.0", logTail: ["a + b"])
        r.details = "1 + 1"
        let (u, truncated) = try #require(r.issueURL(repository: "andrzejoles/Pelikan"))
        #expect(!truncated)
        #expect(u.host == "github.com" && u.path == "/andrzejoles/Pelikan/issues/new")
        let q = query(u)
        #expect(q["title"] == "Okno + wynik")
        #expect(q["body"] == r.body())
        #expect(q["labels"] == "bug")
        #expect(!u.absoluteString.contains("+"))
    }

    @Test("za długa treść: dziennik skracany od najstarszych wpisów, adres w limicie")
    func truncation() throws {
        let log = (0..<400).map { "2026-10-26 10:00:00.000+0100 INFO  sql  Okno SQL: poleceń \($0), czas 12 ms — wpis numer \($0)" }
        let r = ProblemReport(origin: .manual, title: "Długi", environment: "Wersja: 1.0", logTail: log)
        let (u, truncated) = try #require(r.issueURL(repository: "andrzejoles/Pelikan", maxLength: 6000))
        #expect(truncated)
        #expect(u.absoluteString.count <= 6000)
        let body = query(u)["body"] ?? ""
        #expect(body.contains("wpis numer 399"))
        #expect(!body.contains("wpis numer 0\n"))
        #expect(body.contains("pełna treść w schowku"))
    }

    static let ips = """
    {"app_name":"Pelikan","timestamp":"2026-10-26 10:15:00.00 +0100","bug_type":"309","name":"Pelikan"}
    {"procPath":"/Users/someone/Applications/Pelikan.app/Contents/MacOS/Pelikan","faultingThread":1,
     "exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
     "asi":{"libswiftCore.dylib":["Fatal error: Index out of range"]},
     "usedImages":[{"name":"Pelikan","path":"/Users/someone/Applications/Pelikan.app/Contents/MacOS/Pelikan"},{"name":"libswiftCore.dylib"}],
     "threads":[{"frames":[{"imageIndex":1,"imageOffset":10}]},
                {"triggered":true,"frames":[{"imageIndex":1,"symbol":"_assertionFailure","symbolLocation":44},
                                            {"imageIndex":0,"symbol":"SQLExecutor.execute()","symbolLocation":120},
                                            {"imageIndex":0,"imageOffset":4096}]}]}
    """

    @Test("raport awarii macOS: wyjątek, przyczyna, stos wątku z awarią — bez ścieżek")
    func crashSummary() throws {
        let c = try #require(CrashSummary.parse(Self.ips))
        #expect(c.exceptionType == "EXC_BREAKPOINT" && c.signal == "SIGTRAP")
        #expect(c.reason == "Fatal error: Index out of range")
        #expect(c.frames == ["libswiftCore.dylib  _assertionFailure + 44", "Pelikan  SQLExecutor.execute() + 120", "Pelikan  +4096"])
        #expect(!c.text.contains("/Users"))
        #expect(c.text.contains("Wyjątek: EXC_BREAKPOINT (SIGTRAP)"))
        #expect(CrashSummary.parse("nie json") == nil)
        let r = ProblemReport(origin: .crash(c), environment: "", logTail: [])
        #expect(r.title == "Awaria: EXC_BREAKPOINT")
        #expect(r.body().contains("Pelikan  SQLExecutor.execute() + 120"))
    }

    @Test("znacznik pracy: wykrycie niepoprawnego zamknięcia i najnowszy raport awarii")
    func monitor() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-crash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let m = CrashMonitor(dataDirectory: dir)
        #expect(m.begin() == nil)
        m.end()
        #expect(m.begin() == nil)
        let started = Date(timeIntervalSinceNow: -60)
        #expect(m.begin() != nil)

        let reports = dir.appendingPathComponent("DiagnosticReports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let old = reports.appendingPathComponent("Pelikan-2026-10-01-100000.ips")
        try Self.ips.replacingOccurrences(of: "EXC_BREAKPOINT", with: "EXC_OLD").write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -86_400)], ofItemAtPath: old.path)
        try "x".write(to: reports.appendingPathComponent("Inna-2026-10-26-101500.ips"), atomically: true, encoding: .utf8)
        #expect(CrashMonitor.latestReport(appName: "Pelikan", since: started, in: reports) == nil)
        try Self.ips.write(to: reports.appendingPathComponent("Pelikan-2026-10-26-101500.ips"), atomically: true, encoding: .utf8)
        #expect(CrashMonitor.latestReport(appName: "Pelikan", since: started, in: reports)?.exceptionType == "EXC_BREAKPOINT")
    }

    @Test("znacznik pracy: nieudany zapis zostawia ślad w dzienniku")
    func monitorMarkerNotWritten() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-crash-\(UUID().uuidString)")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let sink = MemoryLogSink(everything: true)
        let id = Log.addSink(sink)
        defer { Log.removeSink(id) }
        // Katalog danych jest zwykłym plikiem — znacznika nie da się utworzyć.
        #expect(CrashMonitor(dataDirectory: file).begin() == nil)
        #expect(sink.all.contains { $0.level == .error && $0.category == "app" && $0.text.hasPrefix("Znacznik pracy aplikacji nie zapisany") })
    }

    @Test("komenda Zgłoś problem: tylko dla użytkownika, z opisem środowiska bez nazw połączeń")
    func command() throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        try ws.connections.upsert(ConnectionDefinition(name: "dev_zgl_kadry", target: ConnectionTarget(user: "kadry", connectString: "kadry-db.example:1521/KADRY")))
        let d = try #require(ws.registry.command("help.reportProblem")?.descriptor)
        #expect(d.agentAccess == .none)
        let r = ws.problemReport(.manual)
        #expect(r.environment.contains("Połączenia: 1"))
        #expect(!r.body().contains("kadry"))
    }
}
