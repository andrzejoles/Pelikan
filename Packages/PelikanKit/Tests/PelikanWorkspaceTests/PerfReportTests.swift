import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Sesja zapisująca polecenia; wersja bazy do wyboru.
final class PerfCaptureSession: DatabaseSession, @unchecked Sendable {
    let info: SessionInfo
    let queries = Mutex<[(sql: String, binds: [BindVariable])]>([])
    init(major: Int = 19) {
        info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: major, minor: 0),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    }
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        queries.withLock { $0.append((sql, binds)) }
        return ExecutionResult(kind: .query, resultSet: ResultSetDescriptor(id: ResultSetID(1), columns: []))
    }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch { RowBatch(rows: [], hasMore: false) }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
    var all: [(sql: String, binds: [BindVariable])] { queries.withLock { $0 } }
    func last(containing s: String) -> (sql: String, binds: [BindVariable])? { all.last { $0.sql.lowercased().contains(s.lowercased()) } }
}

@Suite("Raporty wydajności: katalog, dostępność, wywołania (D217)")
struct PerfReportTests {
    @Test("Katalog: unikalne identyfikatory, formaty, ACTIVE pierwszy, każdy raport bazy ma komendę")
    @MainActor func catalog() {
        let all = PerfReportCatalog.all
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.allSatisfy { !$0.formats.isEmpty })
        #expect(all.filter { $0.formats.contains(.active) }.allSatisfy { $0.formats.first == .active })
        // Aktywny raport planu (xplan) — przeglądarka Oracle odpowiada 404 (D221).
        #expect(PerfReportCatalog.report("sql.planCursor")?.formats == [.html, .text, .xml])
        let ws = Workspace()
        for r in PerfReportCatalog.globalReports { #expect(ws.registry.command(CommandID(rawValue: r.id)) != nil, "\(r.id)") }
        #expect(ws.registry.command("perf.sqlReports")?.descriptor.agentAccess == AgentAccess.none)
        #expect(ws.registry.command("perf.sqlReports")?.descriptor.category == .performance)
    }

    func availability(_ lic: PerfLicense = .all, major: Int = 19) -> SQLAvailability {
        var a = SQLAvailability(sqlID: "ghkw1782vah43")
        a.license = lic
        a.major = major
        a.cursors = [.init(instance: 1, child: 0, planHash: "123", executions: "5", elapsedSeconds: "1.5", lastActive: "2026-11-03 10:00:00")]
        a.snapshots = [.init(snapID: 100, instance: 1, begin: "2026-11-03 08:00:00", end: "2026-11-03 09:00:00", planHash: "123", executions: "3",
                             elapsedSeconds: "1", bufferGets: "10", diskReads: "0", rows: "3"),
                       .init(snapID: 102, instance: 1, begin: "2026-11-03 10:00:00", end: "2026-11-03 11:00:00", planHash: "456", executions: "2",
                             elapsedSeconds: "9", bufferGets: "99", diskReads: "5", rows: "2")]
        a.bindSets = [.init(origin: .awr(snapID: 102, instance: 1), captured: "2026-11-03 10:30:00",
                            binds: [.init(position: 1, name: ":B1", type: "NUMBER", value: "42", captured: true)])]
        return a
    }

    @Test("Dostępność: źródła, zakres migawek, plany; raporty blokowane licencją, wersją i brakiem danych")
    func gating() {
        let a = availability()
        #expect(a.sources == [.cursorCache, .awr])
        #expect(a.snapshotRange! == (99, 102))
        #expect(a.planHashes == ["123", "456"])
        let r = Dictionary(uniqueKeysWithValues: a.reports().map { ($0.report.id, $0) })
        #expect(r["sql.awr"]!.available && r["sql.planCursor"]!.available && r["sql.binds"]!.available)
        #expect(!r["sql.monitor"]!.available && r["sql.monitor"]!.reason!.contains("SQL Monitor"))
        #expect(r["sql.ash"]!.available && a.sources(for: PerfReportCatalog.report("sql.ash")!) == [.awr])   // bez próbek w pamięci — ASH z AWR
        let noPack = availability(PerfLicense(diagnostics: false, tuning: false))
        let r2 = Dictionary(uniqueKeysWithValues: noPack.reports().map { ($0.report.id, $0) })
        #expect(r2["sql.planCursor"]!.available && !r2["sql.awr"]!.available && r2["sql.awr"]!.reason!.contains("Diagnostics"))
        #expect(!r2["sql.tuning"]!.available)
        #expect(noPack.sources(for: PerfReportCatalog.report("sql.planAWR")!) == [])
        let old = availability(major: 11)
        #expect(old.reports().first { $0.report.id == "sql.repair" }!.available == false)
    }

    @Test("Baza 19c właściciela (D223): zakres migawek w retencji, plan bez wierszy w AWR, brak EXECUTE z poleceniem GRANT")
    func productionFindings() {
        var a = availability()
        a.oldestSnapshot = 100
        #expect(a.snapshotRange! == (100, 102))   // migawka przed pierwszą (99) jest poza retencją — ORA-13768
        a.awrPlanRows = 0
        a.user = "PERF_USER"
        a.accessiblePackages = Set(PerfReportRunner.allPackages).subtracting(["DBMS_WORKLOAD_REPOSITORY"])
        let r = Dictionary(uniqueKeysWithValues: a.reports().map { ($0.report.id, $0) })
        #expect(!r["sql.planAWR"]!.available && r["sql.planAWR"]!.reason!.contains("DBA_HIST_SQL_PLAN"))
        #expect(!r["sql.awr"]!.available && r["sql.awr"]!.reason!.contains("GRANT EXECUTE ON SYS.DBMS_WORKLOAD_REPOSITORY TO PERF_USER;"))
        #expect(r["sql.planCursor"]!.available && r["sql.tuning"]!.available)
        #expect(PerfReportRunner.missingPrivilege("perf.addm", accessible: ["DBMS_ADDM"], user: "PERF_USER")!.contains("DBMS_WORKLOAD_REPOSITORY"))
        #expect(PerfReportRunner.missingPrivilege("perf.awr", accessible: nil, user: "PERF_USER") == nil)   // nie sprawdzono — bez blokady
        #expect(PerfReportCatalog.report("perf.session")?.formats == [.xml])
        #expect(PerfReportCatalog.report("perf.realtimeADDM")?.formats == [.xml])
    }

    @Test("Baza 19c właściciela (D226): uprawnienia systemowe raportu statystyk, błąd Oracle w treści, pusty ASH Analytics")
    func emptyAndRefusedReports() async throws {
        // Bez znacznika SESSION_PRIVS — uprawnień systemowych nie sprawdzono, bez blokady.
        #expect(PerfReportRunner.missingPrivilege("perf.statsOps", accessible: ["DBMS_STATS"], user: "PERF_USER") == nil)
        let checked: Set<String> = ["DBMS_STATS", PerfReportRunner.privilegesChecked, PerfReportRunner.privilegesChecked + "ANALYZE ANY"]
        let reason = try #require(PerfReportRunner.missingPrivilege("perf.statsOps", accessible: checked, user: "PERF_USER"))
        #expect(reason.contains("GRANT ANALYZE ANY DICTIONARY TO PERF_USER;") && !reason.contains("GRANT ANALYZE ANY TO"))
        #expect(PerfReportRunner.missingPrivilege("perf.statsOps", accessible: checked.union([PerfReportRunner.privilegesChecked + "ANALYZE ANY DICTIONARY"]), user: "PERF_USER") == nil)
        #expect(PerfReportRunner.missingPrivilege("perf.awr", accessible: checked.union(["DBMS_WORKLOAD_REPOSITORY"]), user: "PERF_USER") == nil)

        // Wykonanie bez ANALYZE ANY DICTIONARY — zablokowane przed wywołaniem raportu (SESSION_PRIVS atrapy jest puste).
        let s = PerfCaptureSession()
        await #expect(throws: CommandError.self) { _ = try await PerfReportRunner.run(PerfReportRequest(reportID: "perf.statsOps", format: .html), availability: nil, license: .all, in: s) }
        #expect(s.last(containing: "report_stats_operations") == nil && s.last(containing: "session_privs") != nil)
        #expect(PerfReportRunner.embeddedError("<report>ORA-20000: Insufficient privileges</report>\n") == "ORA-20000: Insufficient privileges")
        #expect(PerfReportRunner.embeddedError("<report><body>x</body></report>") == nil)
        #expect(PerfReportRunner.embeddedError(String(repeating: "\n", count: 50) + "<report>ORA-20000: Brak uprawnień — zażółć</report>") != nil)
        #expect(PerfReportRunner.embeddedError("plain text") == nil)

        #if canImport(Darwin)
        func active(_ xml: String) throws -> String {
            let raw = try (Data(xml.utf8) as NSData).compressed(using: .zlib) as Data
            let zlib = Data([0x78, 0x01]) + raw + Data([0, 0, 0, 0])   // nagłówek i suma Adler-32 (niesprawdzana)
            return "<html><script id=\"fxtmodel\" type=\"text/xml\"><report db_version=\"19.0.0.0.0\" encode=\"base64\" compress=\"zlib\">"
                + "<report_id><![CDATA[/orarep/ash/viewer]]></report_id>\n" + zlib.base64EncodedString(options: .lineLength64Characters) + "\n</report></script></html>"
        }
        let empty = try active("<report_parameters><begin_time>t</begin_time></report_parameters><cpu_info/><body/>")
        #expect(PerfReportRunner.activePayload(empty)?.contains("<body/>") == true)
        let full = try active("<report_parameters/><body><activity>1</activity></body>")
        #expect(PerfReportRunner.activePayload(full)?.contains("<activity>1</activity>") == true)
        #expect(PerfReportRunner.activePayload("<html></html>") == nil)
        #endif
    }

    @Test("Wykonanie (D224): raport i źródło spoza licencji oraz raport z nowszej wersji nie wywołują Oracle")
    func runnerGating() async throws {
        let s = PerfCaptureSession(major: 11)
        var q = PerfReportRequest(reportID: "perf.ashAnalytics", format: .active)
        await #expect(throws: CommandError.self) { _ = try await PerfReportRunner.run(q, availability: nil, license: .all, in: s) }
        q = PerfReportRequest(reportID: "sql.monitor", sqlID: "ghkw1782vah43", format: .active)
        let s19 = PerfCaptureSession()
        await #expect(throws: CommandError.self) { _ = try await PerfReportRunner.run(q, availability: nil, license: .unlicensed, in: s19) }
        q = PerfReportRequest(reportID: "sql.planCursor", sqlID: "ghkw1782vah43", format: .text)
        q.source = .awr
        await #expect(throws: CommandError.self) { _ = try await PerfReportRunner.run(q, availability: nil, license: .unlicensed, in: s19) }
        // Bindy z AWR dla doradcy — Diagnostics Pack także przy źródle bez licencji.
        q = PerfReportRequest(reportID: "sql.repair", sqlID: "ghkw1782vah43", format: .text)
        q.bindSet = .init(origin: .awr(snapID: 1, instance: 1), captured: "", binds: [])
        await #expect(throws: CommandError.self) { _ = try await PerfReportRunner.run(q, availability: nil, license: .unlicensed, in: s19) }
        // Raport z jedynym źródłem AWR — bez licencji zablokowany także bez wybranego źródła.
        q = PerfReportRequest(reportID: "sql.planAWR", sqlID: "ghkw1782vah43", format: .text)
        await #expect(throws: CommandError.self) { _ = try await PerfReportRunner.run(q, availability: nil, license: .unlicensed, in: s19) }
        #expect(s.all.isEmpty && s19.all.isEmpty)
        #expect(PerfLicense.unlicensed.blockReason(PerfReportCatalog.report("perf.awr")!, major: 19) != nil)
        #expect(PerfLicense.all.blockReason(PerfReportCatalog.report("perf.ashAnalytics")!, major: 12)!.contains("19"))
    }

    @Test("Raport AWR dla SQL i ASH: funkcje, źródło ASH, wartości tylko jako bindy")
    func awrAndASH() async throws {
        let s = PerfCaptureSession()
        var q = PerfReportRequest(reportID: "sql.awr", sqlID: "ghkw1782vah43", format: .html)
        q.beginSnap = 99; q.endSnap = 102
        _ = try? await PerfReportRunner.run(q, availability: availability(), license: .all, in: s)
        let awr = try #require(s.last(containing: "awr_sql_report_html"))
        #expect(awr.sql.contains("con_dbid") && !awr.sql.contains("ghkw1782vah43"))
        #expect(awr.binds.map(\.name) == ["inst", "bs", "es", "id"])
        var a = PerfReportRequest(reportID: "sql.ash", sqlID: "ghkw1782vah43", format: .text)
        a.source = .ashMemory; a.begin = "2026-11-03 08:00:00"; a.end = "2026-11-03 09:00:00"
        _ = try? await PerfReportRunner.run(a, availability: availability(), license: .all, in: s)
        let ash = try #require(s.last(containing: "ash_report_text"))
        #expect(ash.binds.first { $0.name == "src" }?.value == .text("1"))
    }

    @Test("Plany: DISPLAY_WORKLOAD_REPOSITORY w 19c, DISPLAY_AWR w 11g (DBID z V$DATABASE)")
    func plans() async throws {
        for (major, fn) in [(19, "awr_location => 'AWR_PDB'"), (11, "display_awr")] {
            let s = PerfCaptureSession(major: major)
            _ = try? await PerfReportRunner.run(PerfReportRequest(reportID: "sql.planAWR", sqlID: "ghkw1782vah43", format: .text), availability: nil, license: .all, in: s)
            #expect(s.last(containing: fn) != nil, "\(major)")
        }
        let s11 = PerfCaptureSession(major: 11)
        var q = PerfReportRequest(reportID: "sql.awr", sqlID: "ghkw1782vah43", format: .html)
        q.beginSnap = 1; q.endSnap = 2
        _ = try? await PerfReportRunner.run(q, availability: nil, license: .all, in: s11)
        #expect(s11.last(containing: "awr_sql_report")?.sql.contains("v$database") == true)
    }

    @Test("SQL Monitor: wykonanie z pamięci albo zapisany raport; typ ACTIVE")
    func monitor() async throws {
        let s = PerfCaptureSession()
        var q = PerfReportRequest(reportID: "sql.monitor", sqlID: "ghkw1782vah43", format: .active)
        q.source = .sqlMonitor
        q.execution = .init(instance: 2, execID: "16777216", start: "2026-11-03 10:15:02", status: "DONE", elapsedSeconds: "3", sid: "12")
        _ = try? await PerfReportRunner.run(q, availability: nil, license: .all, in: s)
        let m = try #require(s.last(containing: "report_sql_monitor("))
        #expect(m.binds.first { $0.name == "ty" }?.value == .text("ACTIVE") && m.binds.first { $0.name == "ex" }?.value == .text("16777216"))
        q.source = .reportRepository; q.storedReportID = "77"
        _ = try? await PerfReportRunner.run(q, availability: nil, license: .all, in: s)
        #expect(s.last(containing: "report_repository_detail")?.binds.first { $0.name == "rid" }?.value == .text("77"))
    }

    @Test("SQL Tuning Advisor: zestaw bindów z AWR jako bind_list, zadanie ≤ 30 znaków i usuwane")
    func tuning() async throws {
        let s = PerfCaptureSession()
        var q = PerfReportRequest(reportID: "sql.tuning", sqlID: "ghkw1782vah43", format: .text)
        q.source = .awr
        q.bindSet = availability().bindSets[0]
        _ = try? await PerfReportRunner.run(q, availability: availability(), license: .all, in: s)
        try await Task.sleep(for: .milliseconds(100))
        let create = try #require(s.last(containing: "create_tuning_task"))
        #expect(create.sql.contains("bind_list => l_binds") && create.sql.contains("dba_hist_sqlbind") && create.sql.contains("dba_hist_sqltext"))
        #expect(create.binds.first { $0.name == "bs" }?.value == .text("102"))
        let task = create.binds.first { $0.name == "t" }?.value.displayText ?? ""
        #expect(task.count <= 30 && task.hasPrefix("PLK_STA_GHKW1782VAH43"))
        #expect(s.last(containing: "drop_tuning_task") != nil)
        // Bez bindów, z pamięci kursorów — wariant sql_id.
        let s2 = PerfCaptureSession()
        var q2 = PerfReportRequest(reportID: "sql.tuning", sqlID: "ghkw1782vah43", format: .text)
        q2.source = .cursorCache
        _ = try? await PerfReportRunner.run(q2, availability: nil, license: .all, in: s2)
        #expect(s2.last(containing: "create_tuning_task")?.sql.contains("sql_id => :id, plan_hash_value") == true)
    }

    @Test("Raporty budowane w Pelikanie: historia AWR i bindy; wykrycie formatu")
    func local() async throws {
        let s = PerfCaptureSession()
        let h = try await PerfReportRunner.run(PerfReportRequest(reportID: "sql.history", sqlID: "ghkw1782vah43", format: .html), availability: availability(), license: .all, in: s)
        #expect(h.format == .html && h.content.contains("<td class=\"n\">102</td>") && h.content.contains("456"))
        let b = try await PerfReportRunner.run(PerfReportRequest(reportID: "sql.binds", sqlID: "ghkw1782vah43", format: .text), availability: availability(), license: .all, in: s)
        #expect(b.format == .text && b.content.contains(":B1") && b.content.contains("42"))
        #expect(PerfReportRunner.detect("<html><body>x", requested: .active) == .active)
        // 19c: przeglądarka raportów ACTIVE z http — zawsze https (D220).
        let r19 = #"var swf_base_path = "http://download.oracle.com/otn_software/omx/";"#
        #expect(PerfReportRunner.secureViewerScripts(r19) == #"var swf_base_path = "https://download.oracle.com/otn_software/omx/";"#)
        #expect(PerfReportRunner.secureViewerScripts("http://example.com/") == "http://example.com/")
        #expect(PerfReportRunner.detect("<?xml version='1.0'?><report/>", requested: .html) == .xml)
        #expect(PerfReportRunner.detect("SQL Tuning Advisor report", requested: .html) == .text)
    }

    @Test("Zapytanie z siatki i edytora: wiersz z SQL_ID, komórka hasha, słowo, polecenie pod kursorem")
    @MainActor func finder() throws {
        let doc = Document(kind: .sql, ordinal: 1, text: "select 'pelikan sqlid probe' from dual;\n-- ghkw1782vah43")
        doc.selectedRange = 5..<5
        let fromStatement = try #require(SQLTargetFinder.fromEditor(doc))
        #expect(fromStatement.target == SQLIdentity.Target.sqlID("ghkw1782vah43") && fromStatement.statement == "select 'pelikan sqlid probe' from dual")
        let off = (doc.text as NSString).range(of: "ghkw").location + 3
        doc.selectedRange = off..<off
        #expect(SQLTargetFinder.fromEditor(doc)?.origin.contains("słowo") == true)
    }

    @Test("Sesje: otwarte kursory z kolumną wykonywania; stare ustawienia przełączone, zmienione zostają; PREV_SQL_ID na liście (D220)")
    func sessionQueries() {
        #expect(SessionQueries.standard.details.first { $0.name == L10n.tr("Otwarte kursory") }?.sql == SessionQueries.openCursors)
        var old = SessionQueries.standard
        old.details[1].sql = "select sql_id, sql_text, cursor_type from v$open_cursor where sid = :sid"
        old.details.append(.init(name: "Moje", sql: "select 1 from dual"))
        let m = old.migrated()
        #expect(m.details[1].sql.contains("wykonywany") && m.details.last?.sql == "select 1 from dual")
        #expect(SessionBrowser.columns.contains("PREV_SQL_ID") && SQLIdentity.columnKind("PREV_SQL_ID") == .sqlID)
    }
}
