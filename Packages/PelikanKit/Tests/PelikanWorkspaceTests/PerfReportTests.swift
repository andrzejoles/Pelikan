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

    @Test("Raport AWR dla SQL i ASH: funkcje, źródło ASH, wartości tylko jako bindy")
    func awrAndASH() async throws {
        let s = PerfCaptureSession()
        var q = PerfReportRequest(reportID: "sql.awr", sqlID: "ghkw1782vah43", format: .html)
        q.beginSnap = 99; q.endSnap = 102
        _ = try? await PerfReportRunner.run(q, availability: availability(), in: s)
        let awr = try #require(s.last(containing: "awr_sql_report_html"))
        #expect(awr.sql.contains("con_dbid") && !awr.sql.contains("ghkw1782vah43"))
        #expect(awr.binds.map(\.name) == ["inst", "bs", "es", "id"])
        var a = PerfReportRequest(reportID: "sql.ash", sqlID: "ghkw1782vah43", format: .text)
        a.source = .ashMemory; a.begin = "2026-11-03 08:00:00"; a.end = "2026-11-03 09:00:00"
        _ = try? await PerfReportRunner.run(a, availability: availability(), in: s)
        let ash = try #require(s.last(containing: "ash_report_text"))
        #expect(ash.binds.first { $0.name == "src" }?.value == .text("1"))
    }

    @Test("Plany: DISPLAY_WORKLOAD_REPOSITORY w 19c, DISPLAY_AWR w 11g (DBID z V$DATABASE)")
    func plans() async throws {
        for (major, fn) in [(19, "awr_location => 'AWR_PDB'"), (11, "display_awr")] {
            let s = PerfCaptureSession(major: major)
            _ = try? await PerfReportRunner.run(PerfReportRequest(reportID: "sql.planAWR", sqlID: "ghkw1782vah43", format: .text), availability: nil, in: s)
            #expect(s.last(containing: fn) != nil, "\(major)")
        }
        let s11 = PerfCaptureSession(major: 11)
        var q = PerfReportRequest(reportID: "sql.awr", sqlID: "ghkw1782vah43", format: .html)
        q.beginSnap = 1; q.endSnap = 2
        _ = try? await PerfReportRunner.run(q, availability: nil, in: s11)
        #expect(s11.last(containing: "awr_sql_report")?.sql.contains("v$database") == true)
    }

    @Test("SQL Monitor: wykonanie z pamięci albo zapisany raport; typ ACTIVE")
    func monitor() async throws {
        let s = PerfCaptureSession()
        var q = PerfReportRequest(reportID: "sql.monitor", sqlID: "ghkw1782vah43", format: .active)
        q.source = .sqlMonitor
        q.execution = .init(instance: 2, execID: "16777216", start: "2026-11-03 10:15:02", status: "DONE", elapsedSeconds: "3", sid: "12")
        _ = try? await PerfReportRunner.run(q, availability: nil, in: s)
        let m = try #require(s.last(containing: "report_sql_monitor("))
        #expect(m.binds.first { $0.name == "ty" }?.value == .text("ACTIVE") && m.binds.first { $0.name == "ex" }?.value == .text("16777216"))
        q.source = .reportRepository; q.storedReportID = "77"
        _ = try? await PerfReportRunner.run(q, availability: nil, in: s)
        #expect(s.last(containing: "report_repository_detail")?.binds.first { $0.name == "rid" }?.value == .text("77"))
    }

    @Test("SQL Tuning Advisor: zestaw bindów z AWR jako bind_list, zadanie ≤ 30 znaków i usuwane")
    func tuning() async throws {
        let s = PerfCaptureSession()
        var q = PerfReportRequest(reportID: "sql.tuning", sqlID: "ghkw1782vah43", format: .text)
        q.source = .awr
        q.bindSet = availability().bindSets[0]
        _ = try? await PerfReportRunner.run(q, availability: availability(), in: s)
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
        _ = try? await PerfReportRunner.run(q2, availability: nil, in: s2)
        #expect(s2.last(containing: "create_tuning_task")?.sql.contains("sql_id => :id, plan_hash_value") == true)
    }

    @Test("Raporty budowane w Pelikanie: historia AWR i bindy; wykrycie formatu")
    func local() async throws {
        let s = PerfCaptureSession()
        let h = try await PerfReportRunner.run(PerfReportRequest(reportID: "sql.history", sqlID: "ghkw1782vah43", format: .html), availability: availability(), in: s)
        #expect(h.format == .html && h.content.contains("<td class=\"n\">102</td>") && h.content.contains("456"))
        let b = try await PerfReportRunner.run(PerfReportRequest(reportID: "sql.binds", sqlID: "ghkw1782vah43", format: .text), availability: availability(), in: s)
        #expect(b.format == .text && b.content.contains(":B1") && b.content.contains("42"))
        #expect(PerfReportRunner.detect("<html><body>x", requested: .active) == .active)
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
}
