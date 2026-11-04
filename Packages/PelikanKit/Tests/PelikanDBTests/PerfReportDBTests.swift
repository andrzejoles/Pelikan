import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Raporty wydajności na bazie testowej (D217)", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(8)))
struct PerfReportDBTests {
    @Test("Zapytanie z bindem: dostępność w pamięci, AWR i SQL Monitor; wszystkie raporty SQL i bazy")
    func reports() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .tool("perf")))
        ui.askAnswer = 0
        let lic = try await ManagementPacks.license(connection: def.id, session: s, in: ws, invoker: .user, ask: true)
        #expect(lic.diagnostics && lic.tuning && ws.connections.connection(def.id)?.managementPacks == .diagnosticsAndTuning)

        // Zapytanie z bindem i hintem MONITOR; SQL_ID liczony z tekstu jak w V$SQL.
        let tag = "pelikan_perf_" + UUID().uuidString.prefix(8).lowercased()
        let sql = "select /*+ MONITOR \(tag) */ count(*) from all_objects where object_id > :b1"
        let sqlID = SQLIdentity.sqlID(text: sql)
        _ = try await s.execute("begin dbms_workload_repository.create_snapshot; end;")
        for _ in 0..<3 {
            let r = try await s.execute(sql, binds: [BindVariable(name: "b1", type: .number, value: .text("10"))])
            if let rs = r.resultSet { _ = try await s.fetch(rs.id, maxRows: 10); await s.closeResultSet(rs.id) }
        }
        #expect(try await s.scalar("select count(*) from v$sql where sql_id = :i", binds: [BindVariable(name: "i", value: .text(sqlID))]) != "0")
        _ = try await s.execute("begin dbms_workload_repository.add_colored_sql(:i); end;", binds: [BindVariable(name: "i", value: .text(sqlID))])
        _ = try await s.execute("begin dbms_workload_repository.create_snapshot; end;")
        defer { Task { _ = try? await s.execute("begin dbms_workload_repository.remove_colored_sql(:i); end;", binds: [BindVariable(name: "i", value: .text(sqlID))]) } }

        let a = await SQLProbe.probe(sqlID: sqlID, in: s, license: lic)
        #expect(!a.cursors.isEmpty && a.text?.contains(tag) == true && a.schema?.isEmpty == false)
        #expect(!a.snapshots.isEmpty, "AWR: \(a.notes)")
        #expect(!a.executions.isEmpty, "SQL Monitor: \(a.notes)")
        #expect(a.bindSets.contains { if case .cursor = $0.origin { return $0.binds.first?.value == "10" }; return false }, "bindy: \(a.bindSets)")
        let hash = try #require(a.hashValue)
        #expect(try await SQLProbe.resolve(hash: hash, in: s, license: lic, major: s.info.server.major) == sqlID)

        let range = try #require(a.snapshotRange)
        let hourAgo = try await s.scalar("select to_char(sysdate - 1/24, 'YYYY-MM-DD HH24:MI:SS') from dual") ?? ""
        var failures: [String] = []
        func run(_ id: String, _ f: ReportFormat, _ edit: (inout PerfReportRequest) -> Void = { _ in }) async {
            var q = PerfReportRequest(reportID: id, sqlID: PerfReportCatalog.report(id)?.scope == .sql ? sqlID : nil, format: f)
            q.beginSnap = range.begin; q.endSnap = range.end
            q.begin = hourAgo; q.end = a.now
            q.timeLimit = 15
            edit(&q)
            do {
                let out = try await PerfReportRunner.run(q, availability: a, in: s)
                if out.content.count < 20 { failures.append("\(id): krótki wynik") }
            } catch { failures.append("\(id) [\(f.rawValue)]: \(error.localizedDescription)") }
        }
        await run("sql.planCursor", .text)
        await run("sql.planAWR", .text)
        await run("sql.monitor", .active) { $0.source = .sqlMonitor; $0.execution = a.executions.first }
        await run("sql.monitor", .text) { $0.source = .sqlMonitor; $0.execution = a.executions.first }
        await run("sql.monitorList", .html)
        await run("sql.detail", .active) { $0.source = .awr }
        await run("sql.perfHub", .active) { $0.source = .awr }
        await run("sql.awr", .html)
        await run("sql.awr", .text)
        await run("sql.ash", .html) { $0.source = .ashBoth }
        await run("sql.history", .html)
        await run("sql.binds", .text)
        await run("sql.tuning", .text) { $0.source = .cursorCache; $0.bindSet = a.bindSets.first { $0.usableByAdvisor } }
        await run("sql.repair", .text) { $0.source = .cursorCache }
        await run("perf.awr", .html)
        await run("perf.awrDiff", .html) { $0.beginSnap2 = range.begin; $0.endSnap2 = range.end }
        await run("perf.addm", .text)
        await run("perf.ash", .html) { $0.source = .ashBoth }
        await run("perf.perfHub", .active) { $0.realtime = true }   // historyczny na krótkim AWR testowym: ORA-01476 w PRVT_AWR_VIEWER
        await run("perf.realtimeADDM", .active)
        await run("perf.monitorList", .html)
        await run("perf.statsOps", .html)
        await run("perf.session", .active) { $0.realtime = true }
        print("PERF-FAILURES", failures)
        #expect(failures.isEmpty, "\(failures)")
    }
}
