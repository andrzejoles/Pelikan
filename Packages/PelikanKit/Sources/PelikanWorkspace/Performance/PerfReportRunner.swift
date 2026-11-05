import Foundation
import PelikanDB

/// Wybory użytkownika dla raportu (D217). Czasy w zapisie bazy `YYYY-MM-DD HH24:MI:SS` (strefa serwera).
public struct PerfReportRequest: Sendable, Hashable {
    public var reportID: String
    public var sqlID: String?
    public var source: ReportSource?
    public var format: ReportFormat
    public var beginSnap: Int?, endSnap: Int?
    public var beginSnap2: Int?, endSnap2: Int?
    public var begin: String?, end: String?
    public var instance: Int?
    public var allInstances = false
    public var planHash: String?
    public var child: Int?
    public var planFormat = "ALLSTATS LAST +PEEKED_BINDS"
    /// Wykonanie SQL Monitor (instancja, SQL_EXEC_ID, start) albo zapisany raport (REPORT_ID).
    public var execution: SQLAvailability.Execution?
    public var storedReportID: String?
    /// Zestaw bindów dla doradcy (nil — bez bindów: doradca bierze zapytanie z pamięci kursorów albo AWR).
    public var bindSet: SQLAvailability.BindSet?
    public var timeLimit = 60
    public var sid: Int?, serial: Int?
    public var days = 7
    public var realtime = false

    public init(reportID: String, sqlID: String? = nil, format: ReportFormat) {
        self.reportID = reportID; self.sqlID = sqlID; self.format = format
    }
}

/// Wynik raportu: treść i rzeczywisty format (wykryty z treści — np. raport „tekstowy” bywa HTML).
public struct PerfReportOutput: Sendable {
    public var title: String
    public var format: ReportFormat
    public var content: String
    public var suggestedName: String
}

/// Wykonanie raportów z katalogu (D217): wartości tylko jako bindy, sprawdzenie uprawnień do pakietu przed
/// wywołaniem (bez niego Oracle zgłasza mylący ORA-00904), zadania doradców usuwane po raporcie.
public enum PerfReportRunner {
    static let ts = "'YYYY-MM-DD HH24:MI:SS'"

    static func text(_ n: String, _ v: String?) -> BindVariable { BindVariable(name: n, value: v.map { .text($0) } ?? .null) }
    static func num(_ n: String, _ v: Int?) -> BindVariable { BindVariable(name: n, type: .number, value: v.map { .text(String($0)) } ?? .null) }
    static func numText(_ n: String, _ v: String?) -> BindVariable {
        BindVariable(name: n, type: .number, value: (v?.isEmpty == false ? v : nil).map { .text($0) } ?? .null)
    }

    /// Pakiet, do którego raport potrzebuje EXECUTE.
    static func package(_ id: String) -> String? {
        switch id {
        case "sql.planCursor", "sql.planAWR": "DBMS_XPLAN"
        case "sql.awr", "sql.ash", "perf.awr", "perf.awrDiff", "perf.ash", "perf.ashAnalytics": "DBMS_WORKLOAD_REPOSITORY"
        case "sql.monitor", "sql.monitorList", "sql.detail", "sql.tuning", "perf.monitorList": "DBMS_SQLTUNE"
        case "sql.perfHub", "perf.perfHub", "perf.session": "DBMS_PERF"
        case "sql.repair": "DBMS_SQLDIAG"
        case "perf.addm", "perf.addmCompare", "perf.realtimeADDM": "DBMS_ADDM"
        case "perf.statsOps": "DBMS_STATS"
        case "perf.spmEvolve": "DBMS_SPM"
        default: nil
        }
    }

    /// Pakiety potrzebne raportowi (EXECUTE): ADDM korzysta też z repozytorium AWR.
    static func packages(_ id: String) -> [String] {
        switch id {
        case "perf.addm": ["DBMS_WORKLOAD_REPOSITORY", "DBMS_ADDM"]
        case "perf.autoTuning": ["DBMS_SQLTUNE"]
        default: package(id).map { [$0] } ?? []
        }
    }

    static let allPackages = ["DBMS_XPLAN", "DBMS_WORKLOAD_REPOSITORY", "DBMS_SQLTUNE", "DBMS_PERF", "DBMS_SQLDIAG", "DBMS_ADDM",
                              "DBMS_STATS", "DBMS_SPM", "DBMS_AUTO_SQLTUNE", "DBMS_AUTO_REPORT"]

    /// Uprawnienia systemowe potrzebne raportowi (SESSION_PRIVS) — bez nich Oracle zwraca zamiast raportu
    /// `<report>ORA-20000: Insufficient privileges</report>`.
    static func systemPrivileges(_ id: String) -> [String] {
        id == "perf.statsOps" ? ["ANALYZE ANY", "ANALYZE ANY DICTIONARY"] : []
    }

    static let allSystemPrivileges = ["ANALYZE ANY", "ANALYZE ANY DICTIONARY"]
    /// Znacznik w zbiorze dostępnych uprawnień: SESSION_PRIVS sprawdzone (bez niego uprawnień systemowych nie blokujemy).
    static let privilegesChecked = "PRIV:"

    /// Powód blokady raportu z braku EXECUTE albo uprawnienia systemowego (z poleceniem GRANT); nil — uprawnienia
    /// są albo nie sprawdzono.
    public static func missingPrivilege(_ id: String, accessible: Set<String>?, user: String) -> String? {
        guard let accessible else { return nil }
        let grantee = ManagementPacks.grantee(user)
        var reasons: [String] = []
        let missing = packages(id).filter { !accessible.contains($0) }
        if !missing.isEmpty {
            let grants = missing.map { "GRANT EXECUTE ON SYS.\($0) TO \(grantee);" }.joined(separator: " ")
            reasons.append(L10n.tr("Brak uprawnienia EXECUTE do \(missing.joined(separator: ", ")) — administrator bazy może je nadać: \(grants)"))
        }
        if accessible.contains(privilegesChecked) {
            let privs = systemPrivileges(id).filter { !accessible.contains(privilegesChecked + $0) }
            if !privs.isEmpty {
                let grants = privs.map { "GRANT \($0) TO \(grantee);" }.joined(separator: " ")
                reasons.append(L10n.tr("Brak uprawnienia \(privs.joined(separator: ", ")) — administrator bazy może je nadać: \(grants)"))
            }
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: " ")
    }

    /// Błąd Oracle zwrócony jako treść raportu (`<report>ORA-20000: Insufficient privileges</report>` z DBMS_STATS) —
    /// komunikat zamiast pozornie poprawnego raportu.
    static func embeddedError(_ content: String) -> String? {
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count < 2000, t.hasPrefix("<report>"), t.hasSuffix("</report>") else { return nil }
        let inner = t.dropFirst("<report>".count).dropLast("</report>".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.hasPrefix("ORA-") ? inner : nil
    }

    /// Dane raportu aktywnego (`<report … encode="base64" compress="zlib">`) po rozpakowaniu; nil — brak albo nie da się
    /// rozpakować (poza macOS — bez frameworku Compression).
    static func activePayload(_ content: String) -> String? {
        #if canImport(Darwin)
        guard let open = content.range(of: "compress=\"zlib\""), let tagEnd = content.range(of: ">", range: open.upperBound..<content.endIndex),
              let close = content.range(of: "</report>", range: tagEnd.upperBound..<content.endIndex) else { return nil }
        var body = content[tagEnd.upperBound..<close.lowerBound]
        if let id = body.range(of: "</report_id>") { body = body[id.upperBound...] }
        guard let data = Data(base64Encoded: body.filter { !$0.isWhitespace }), data.count > 6 else { return nil }
        // Strumień zlib (RFC 1950): 2 bajty nagłówka i 4 bajty sumy Adler-32 wokół surowego DEFLATE (algorytm .zlib).
        guard let raw = try? (data.subdata(in: 2..<(data.count - 4)) as NSData).decompressed(using: .zlib) as Data else { return nil }
        return String(decoding: raw, as: UTF8.self)
        #else
        return nil
        #endif
    }

    /// Wykrycie formatu treści: HTML (także ACTIVE), XML albo tekst.
    static func detect(_ content: String, requested: ReportFormat) -> ReportFormat {
        let head = content.prefix(800).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if head.contains("<html") || head.contains("<!doctype html") { return requested == .active ? .active : .html }
        if head.hasPrefix("<") { return .xml }
        return .text
    }

    /// Wykonanie raportu. Licencja i wersja bazy sprawdzane tutaj (nie tylko w oknie): raport albo źródło z pakietu
    /// spoza licencji nie wywołuje Oracle.
    public static func run(_ q: PerfReportRequest, availability: SQLAvailability?, license: PerfLicense,
                           in s: any DatabaseSession) async throws -> PerfReportOutput {
        guard let report = PerfReportCatalog.report(q.reportID) else { throw CommandError.invalidArgument("report", q.reportID) }
        let major = s.info.server.major > 0 ? s.info.server.major : 19
        if let reason = license.blockReason(report, major: major) { throw CommandError.notAvailable(reason) }
        // Źródło: podane albo pierwsze raportu (raport z samym źródłem AWR wymaga Diagnostics Pack także bez wyboru).
        if let src = q.source ?? report.sources.first, !license.allows(report.need(for: src)) {
            throw CommandError.notAvailable(L10n.tr("Źródło „\(src.displayName)” wymaga licencji \(report.need(for: src).displayName)"))
        }
        // Bindy z AWR (doradcy czytają DBA_HIST_SQLBIND i DBA_HIST_SQLTEXT) — Diagnostics Pack niezależnie od źródła.
        if let set = q.bindSet, case .awr = set.origin, !license.allows(.diagnostics) {
            throw CommandError.notAvailable(L10n.tr("Bindy z AWR wymagają licencji \(PerfReport.Need.diagnostics.displayName)"))
        }
        let dbid = SQLProbe.dbid(major)
        for p in packages(q.reportID) { try await ManagementPacks.requireExecute(p, in: s, report: report.title) }
        let id = q.sqlID ?? ""
        let inst = q.instance ?? availability?.instance
        var content: String
        let ty = q.format.oracleType

        func clob(_ body: String, _ binds: [BindVariable]) async throws -> String {
            let r = try await s.execute("begin :r := \(body); end;", binds: [BindVariable(name: "r", type: .clob, direction: .output)] + binds,
                                        options: ExecuteOptions(lobLimit: 200_000_000))
            if case .lob(let l)? = r.outBinds["r"] { return l.text ?? "" }
            if case .text(let t)? = r.outBinds["r"] { return t }
            return ""
        }
        func lines(_ sql: String, _ binds: [BindVariable]) async throws -> String { try await ManagementPacks.joined(s, sql, binds) }
        let html = q.format != .text
        let b = text("b", q.begin), e = text("e", q.end)
        if report.parameters.contains(.timeWindow), let bt = q.begin, let et = q.end, !bt.isEmpty, !et.isEmpty, bt >= et {
            throw CommandError.invalidArgument(L10n.tr("okno czasu"), L10n.tr("początek \(bt) musi być wcześniejszy niż koniec \(et)"))
        }
        if report.parameters.contains(.snapshots), let bs = q.beginSnap, let es = q.endSnap, bs >= es {
            throw CommandError.invalidArgument(L10n.tr("migawki"), L10n.tr("migawka początkowa \(bs) musi być wcześniejsza niż końcowa \(es)"))
        }

        switch q.reportID {
        case "sql.planCursor":
            if q.format == .text {
                content = try await lines("select plan_table_output from table(dbms_xplan.display_cursor(:id, :c, :f))",
                                          [text("id", id), num("c", q.child), text("f", q.planFormat)])
            } else {
                // HTML, ACTIVE i XML: DISPLAY_PLAN na planie z pamięci kursorów; filtr z SQL_ID sprawdzonego wzorcem
                // i numeru kursora (bez tekstu od użytkownika w filter_preds).
                guard SQLIdentity.isSQLID(id) else { throw CommandError.invalidArgument("sqlId", id) }
                // Bez numeru kursora — najniższy (plany kilku kursorów w jednym raporcie by się mieszały).
                let filter = "sql_id = '\(id)' and child_number = " + (q.child.map(String.init) ?? "(select min(child_number) from v$sql where sql_id = '\(id)')")
                content = try await clob("dbms_xplan.display_plan(table_name => 'V$SQL_PLAN_STATISTICS_ALL', format => :f, filter_preds => :p, type => :ty)",
                                         [text("f", q.planFormat), text("p", filter), text("ty", ty)])
            }
        case "sql.planAWR":
            let f = q.planFormat.replacingOccurrences(of: "ALLSTATS LAST", with: "TYPICAL")
            let binds = [text("id", id), numText("ph", q.planHash), text("f", f)]
            if major >= 19 {
                // W PDB z własnym AWR plany są w AWR_PDB; domyślne położenie to AWR kontenera głównego (pusty wynik).
                content = (try? await lines("""
                    select plan_table_output from table(dbms_xplan.display_workload_repository(sql_id => :id, plan_hash_value => :ph, format => :f,
                                                                                                awr_location => 'AWR_PDB'))
                    """, binds)) ?? ""
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    content = try await lines("select plan_table_output from table(dbms_xplan.display_workload_repository(sql_id => :id, plan_hash_value => :ph, format => :f))", binds)
                }
            } else {
                content = try await lines("select plan_table_output from table(dbms_xplan.display_awr(:id, :ph, null, :f))", binds)
            }
        case "sql.monitor":
            if q.source == .reportRepository, let rid = q.storedReportID {
                content = try await clob("dbms_auto_report.report_repository_detail(rid => :rid, type => :ty)", [numText("rid", rid), text("ty", ty)])
            } else {
                let x = q.execution
                content = try await clob("""
                    dbms_sqltune.report_sql_monitor(sql_id => :id, sql_exec_id => :ex, sql_exec_start => to_date(:st, \(ts)), inst_id => :inst,
                                                    type => :ty, report_level => 'ALL')
                    """, [text("id", id), numText("ex", x?.execID), text("st", x?.start), num("inst", x?.instance), text("ty", ty)])
            }
        case "sql.monitorList":
            content = try await clob("dbms_sqltune.report_sql_monitor_list(sql_id => :id, type => :ty, report_level => 'ALL')", [text("id", id), text("ty", ty)])
        case "sql.detail":
            if major >= 19 {
                let ds = q.source == .awr ? "DISK" : q.source == .ashMemory ? "MEMORY" : "AUTO"
                content = try await clob("""
                    dbms_sqltune.report_sql_detail(sql_id => :id, sql_plan_hash_value => :ph, start_time => to_date(:b, \(ts)),
                        end_time => to_date(:e, \(ts)), report_level => 'ALL', type => :ty, data_source => :ds)
                    """, [text("id", id), numText("ph", q.planHash), b, e, text("ty", ty), text("ds", ds)])
            } else {
                content = try await clob("""
                    dbms_sqltune.report_sql_detail(sql_id => :id, sql_plan_hash_value => :ph, start_time => to_date(:b, \(ts)),
                        duration => greatest(60, round((to_date(:e, \(ts)) - to_date(:b2, \(ts))) * 86400)), report_level => 'ALL', type => :ty)
                    """, [text("id", id), numText("ph", q.planHash), b, e, text("b2", q.begin), text("ty", ty)])
            }
        case "sql.perfHub":
            content = try await clob("""
                dbms_perf.report_sql(sql_id => :id, is_realtime => :rt, outer_start_time => to_date(:b, \(ts)), outer_end_time => to_date(:e, \(ts)),
                    selected_start_time => to_date(:b2, \(ts)), selected_end_time => to_date(:e2, \(ts)), type => :ty)
                """, [text("id", id), num("rt", q.source == .ashMemory ? 1 : 0), b, e, text("b2", q.begin), text("e2", q.end), text("ty", ty)])
        case "sql.awr":
            content = try await lines("select output from table(dbms_workload_repository.awr_sql_report_\(html ? "html" : "text")(\(dbid), :inst, :bs, :es, :id))",
                                      [num("inst", inst), num("bs", q.beginSnap), num("es", q.endSnap), text("id", id)])
        case "sql.ash", "perf.ash":
            let src = q.source == .ashMemory ? 1 : q.source == .awr ? 2 : 0
            content = try await lines("""
                select output from table(dbms_workload_repository.ash_report_\(html ? "html" : "text")(l_dbid => \(dbid), l_inst_num => :inst,
                    l_btime => to_date(:b, \(ts)), l_etime => to_date(:e, \(ts)), l_sql_id => :id, l_data_src => :src))
                """, [num("inst", inst), b, e, text("id", q.reportID == "perf.ash" ? nil : id), num("src", src)])
        case "sql.history":
            content = history(availability, format: q.format)
        case "sql.binds":
            content = binds(availability, source: q.source, format: q.format)
        case "sql.tuning":
            content = try await tuning(q, availability: availability, dbid: dbid, in: s)
        case "sql.repair":
            content = try await repair(q, availability: availability, in: s)
        case "perf.awr":
            if q.allInstances {
                content = try await lines("select output from table(dbms_workload_repository.awr_global_report_\(html ? "html" : "text")(\(dbid), :il, :bs, :es))",
                                          [text("il", nil), num("bs", q.beginSnap), num("es", q.endSnap)])
            } else {
                content = try await lines("select output from table(dbms_workload_repository.awr_report_\(html ? "html" : "text")(\(dbid), :inst, :bs, :es))",
                                          [num("inst", inst), num("bs", q.beginSnap), num("es", q.endSnap)])
            }
        case "perf.awrDiff":
            if q.allInstances {
                content = try await lines("""
                    select output from table(dbms_workload_repository.awr_global_diff_report_\(html ? "html" : "text")(\(dbid), :il, :bs, :es, \(dbid), :il2, :bs2, :es2))
                    """, [text("il", nil), num("bs", q.beginSnap), num("es", q.endSnap), text("il2", nil), num("bs2", q.beginSnap2), num("es2", q.endSnap2)])
            } else {
                content = try await lines("""
                    select output from table(dbms_workload_repository.awr_diff_report_\(html ? "html" : "text")(\(dbid), :inst, :bs, :es, \(dbid), :inst2, :bs2, :es2))
                    """, [num("inst", inst), num("bs", q.beginSnap), num("es", q.endSnap), num("inst2", inst), num("bs2", q.beginSnap2), num("es2", q.endSnap2)])
            }
        case "perf.addm":
            content = try await ManagementPacks.addmReport(s, begin: String(q.beginSnap ?? 0), end: String(q.endSnap ?? 0))
        case "perf.addmCompare":
            content = try await clob("""
                dbms_addm.compare_databases(base_dbid => \(dbid), base_begin_snap_id => :bs, base_end_snap_id => :es,
                    comp_dbid => \(dbid), comp_begin_snap_id => :bs2, comp_end_snap_id => :es2, report_type => :ty)
                """, [num("bs", q.beginSnap), num("es", q.endSnap), num("bs2", q.beginSnap2), num("es2", q.endSnap2), text("ty", q.format == .xml ? "XML" : "HTML")])
        case "perf.ashAnalytics":
            content = try await clob("dbms_workload_repository.ash_report_analytics(begin_time => to_date(:b, \(ts)), end_time => to_date(:e, \(ts)))", [b, e])
        case "perf.perfHub":
            content = try await clob("""
                dbms_perf.report_perfhub(is_realtime => :rt, outer_start_time => to_date(:b, \(ts)), outer_end_time => to_date(:e, \(ts)),
                    selected_start_time => to_date(:b2, \(ts)), selected_end_time => to_date(:e2, \(ts)), type => :ty)
                """, [num("rt", q.realtime ? 1 : 0), b, e, text("b2", q.begin), text("e2", q.end), text("ty", ty)])
        case "perf.session":
            content = try await clob("""
                dbms_perf.report_session(inst_id => :inst, sid => :sid, serial => :ser, is_realtime => :rt,
                    outer_start_time => to_date(:b, \(ts)), outer_end_time => to_date(:e, \(ts)), type => :ty)
                """, [num("inst", inst), num("sid", q.sid), num("ser", q.serial), num("rt", q.realtime ? 1 : 0), b, e, text("ty", ty)])
        case "perf.realtimeADDM":
            content = try await clob("dbms_addm.real_time_addm_report()", [])
        case "perf.monitorList":
            content = try await clob("dbms_sqltune.report_sql_monitor_list(active_since_date => to_date(:b, \(ts)), type => :ty, report_level => 'ALL')", [b, text("ty", ty)])
        case "perf.statsOps":
            content = try await clob("""
                dbms_stats.report_stats_operations(detail_level => 'TYPICAL', format => :ty, since => systimestamp - numtodsinterval(:d, 'DAY'), until => systimestamp)
                """, [text("ty", ty), num("d", q.days)])
        case "perf.autoTuning":
            // DBMS_AUTO_SQLTUNE (12c+) bywa bez EXECUTE dla użytkownika — wtedy przestarzały, ale dostępny DBMS_SQLTUNE.
            let autoCount = major >= 12 ? ((try? await s.scalar("select count(*) from all_objects where owner = 'SYS' and object_name = 'DBMS_AUTO_SQLTUNE' and object_type = 'PACKAGE'")) ?? nil) : "0"
            let auto = autoCount != "0"
            do {
                content = try await clob(auto ? "dbms_auto_sqltune.report_auto_tuning_task(type => 'TEXT')" : "dbms_sqltune.report_auto_tuning_task(type => 'TEXT')", [])
            } catch let e as OracleError where [13605, 13631, 13780].contains(e.code) {
                throw CommandError.notAvailable(await autoTaskReason("SYS_AUTO_SQL_TUNING_TASK", in: s))
            }
        case "perf.spmEvolve":
            do {
                content = try await clob("dbms_spm.report_auto_evolve_task(type => :ty)", [text("ty", ty)])
            } catch let e as OracleError where [13605, 13631].contains(e.code) {
                throw CommandError.notAvailable(await autoTaskReason("SYS_AUTO_SPM_EVOLVE_TASK", in: s))
            }
        default:
            throw CommandError.invalidArgument("report", q.reportID)
        }
        if let error = embeddedError(content) {
            let privs = systemPrivileges(q.reportID)
            if error.contains("ORA-20000"), !privs.isEmpty {
                let grants = privs.map { "GRANT \($0) TO \(ManagementPacks.grantee(s.info.sessionUser));" }.joined(separator: " ")
                throw CommandError.notAvailable(L10n.tr("Oracle odmówił raportu (\(error)) — raport wymaga uprawnień \(privs.joined(separator: ", ")); administrator bazy może je nadać: \(grants)"))
            }
            throw CommandError.notAvailable(L10n.tr("Oracle zwrócił zamiast raportu błąd: \(error)"))
        }
        // ASH Analytics (19c) bywa samym szkieletem: parametry i opis procesora, puste `<body/>` (dane wczytuje dopiero
        // Enterprise Manager) — zamiast pustej strony wskazanie Performance Hub, który ma kartę ASH Analytics z danymi.
        if q.reportID == "perf.ashAnalytics", let payload = activePayload(content),
           payload.contains("<body/>") || payload.contains("<body></body>") {
            throw CommandError.notAvailable(L10n.tr("Oracle zwrócił raport ASH Analytics bez danych (sam szkielet raportu) — te same wykresy aktywności z danymi pokazuje Performance Hub (karta ASH Analytics)"))
        }
        content = secureViewerScripts(content)
        let format = detect(content, requested: q.format)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommandError.notAvailable(L10n.tr("Oracle zwrócił pusty raport (brak danych w wybranym źródle albo okresie)"))
        }
        let name = (q.sqlID.map { report.title + " " + $0 } ?? report.title)
        return PerfReportOutput(title: name, format: format, content: content,
                                suggestedName: name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_") + "." + format.fileExtension)
    }

    /// Dlaczego raport zadania automatycznego jest pusty (D223): liczba wykonań zadania, stan klienta „sql tuning
    /// advisor” w oknie konserwacji (uruchamia SQL Tuning i ewolucję SPM) i parametr AUTO_SPM_EVOLVE_TASK.
    static func autoTaskReason(_ task: String, in s: any DatabaseSession) async -> String {
        let t = BindVariable(name: "t", value: .text(task))
        let runs = (try? await s.scalar("select count(*) from dba_advisor_executions where task_name = :t", binds: [t])) ?? nil
        let client = (try? await s.scalar("select status from dba_autotask_client where client_name = 'sql tuning advisor'")) ?? nil
        let spm = task.contains("SPM") ? ((try? await s.scalar("select parameter_value from dba_sql_management_config where parameter_name = 'AUTO_SPM_EVOLVE_TASK'")) ?? nil) : nil
        var parts: [String] = []
        if let runs { parts.append(runs == "0" ? L10n.tr("zadanie \(task) nie było uruchamiane") : L10n.tr("ostatnie wykonanie zadania \(task) nie ma wyników")) }
        if let client { parts.append(L10n.tr("klient zadań automatycznych „sql tuning advisor”: \(client)")) }
        if let spm { parts.append("AUTO_SPM_EVOLVE_TASK = \(spm)") }
        if parts.isEmpty { parts.append(L10n.tr("ostatnie wykonanie zadania \(task) nie ma wyników")) }
        return L10n.tr("Brak wyników do raportu: \(parts.joined(separator: "; ")).")
    }

    /// Raporty ACTIVE z Oracle 19c ładują przeglądarkę raportów z `http://download.oracle.com/…` (23ai — już https).
    /// macOS blokuje w aplikacjach niezaszyfrowane skrypty (pusty raport), a przeglądarka przechodzi na https i ramka
    /// z inną domeną nie dostaje danych („Błąd podczas pobierania danych”). Adres serwera Oracle zawsze przez https (D220).
    static func secureViewerScripts(_ content: String) -> String {
        guard content.contains("http://download.oracle.com/") else { return content }
        return content.replacingOccurrences(of: "http://download.oracle.com/", with: "https://download.oracle.com/")
    }

    // MARK: Raporty budowane w Pelikanie

    static func table(_ title: String, _ columns: [String], _ rows: [[String]], format: ReportFormat) -> String {
        let data = TableExport.data(title: title, columns: columns, rows: rows)
        return format == .text ? title + "\n\n" + ResultExporter.text(.text, data) : ResultExporter.text(.html, data)
    }

    static func history(_ a: SQLAvailability?, format: ReportFormat) -> String {
        let rows = (a?.snapshots ?? []).map { [String($0.snapID), String($0.instance), $0.begin, $0.end, $0.planHash, $0.executions, $0.elapsedSeconds,
                                               $0.bufferGets, $0.diskReads, $0.rows] }
        return table(L10n.tr("Historia wykonań w AWR — \(a?.sqlID ?? "")"),
                     ["SNAP_ID", L10n.tr("Instancja"), L10n.tr("Początek"), L10n.tr("Koniec"), "PLAN_HASH_VALUE", L10n.tr("Wykonania"), L10n.tr("Czas [s]"),
                      "BUFFER_GETS", "DISK_READS", L10n.tr("Wiersze")], rows, format: format)
    }

    static func binds(_ a: SQLAvailability?, source: ReportSource?, format: ReportFormat) -> String {
        let sets = (a?.bindSets ?? []).filter { b in
            switch (b.origin, source) {
            case (.cursor, .cursorCache?), (.awr, .awr?), (.monitor, .sqlMonitor?), (_, nil): true
            default: false
            }
        }
        var rows: [[String]] = []
        for set in sets {
            let origin: String = switch set.origin {
            case .cursor(let i, let c): L10n.tr("kursor \(c), instancja \(i)")
            case .awr(let snap, let i): L10n.tr("AWR, migawka \(snap), instancja \(i)")
            case .monitor(let i, let e, let st): L10n.tr("SQL Monitor, wykonanie \(e) (\(st)), instancja \(i)")
            }
            for b in set.binds { rows.append([origin, set.captured, String(b.position), b.name, b.type, b.captured ? (b.value ?? "NULL") : L10n.tr("(nie przechwycono)")]) }
        }
        return table(L10n.tr("Zapamiętane wartości bindów — \(a?.sqlID ?? "")"),
                     [L10n.tr("Źródło"), L10n.tr("Przechwycono"), L10n.tr("Pozycja"), L10n.tr("Nazwa"), L10n.tr("Typ"), L10n.tr("Wartość")], rows, format: format)
    }

    // MARK: Doradcy

    /// Nazwa zadania doradcy: najwyżej 30 znaków (dłuższa kończy się ORA-13608 w starszych wersjach), unikalna.
    static func taskName(_ prefix: String, _ sqlID: String) -> String {
        String((prefix + "_" + sqlID + "_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).prefix(30)).uppercased()
    }

    /// Zapytanie o bindy zestawu jako ANYDATA (pozycje bez powtórzeń przy bindowaniu po nazwie).
    static func bindQuery(_ set: SQLAvailability.BindSet, dbid: String) -> (String, [BindVariable])? {
        switch set.origin {
        case .cursor(let i, let c):
            return ("select value_anydata from gv$sql_bind_capture where sql_id = :id and inst_id = :bi and child_number = :bc and dup_position is null order by position",
                    [num("bi", i), num("bc", c)])
        case .awr(let snap, let i):
            return ("select value_anydata from dba_hist_sqlbind where sql_id = :id and dbid = \(dbid) and snap_id = :bs and instance_number = :bi and dup_position is null order by position",
                    [num("bs", snap), num("bi", i)])
        case .monitor:
            return nil
        }
    }

    static func textAndUser(_ source: ReportSource?, dbid: String) -> String {
        source == .awr
            ? """
              select sql_text into l_txt from dba_hist_sqltext where sql_id = :id and dbid = \(dbid) and rownum = 1;
              select parsing_schema_name into l_user from (select parsing_schema_name from dba_hist_sqlstat where sql_id = :id and dbid = \(dbid) order by snap_id desc) where rownum = 1;
              """
            : "select sql_fulltext, parsing_schema_name into l_txt, l_user from gv$sql where sql_id = :id and rownum = 1;"
    }

    static func tuning(_ q: PerfReportRequest, availability a: SQLAvailability?, dbid: String, in s: any DatabaseSession) async throws -> String {
        let id = q.sqlID ?? ""
        let task = taskName("PLK_STA", id)
        let t = text("t", task)
        defer { Task { _ = try? await s.execute("begin dbms_sqltune.drop_tuning_task(:t); end;", binds: [t]) } }
        if let set = q.bindSet, set.usableByAdvisor, let (bq, bb) = bindQuery(set, dbid: dbid) {
            _ = try await s.execute("""
                declare l_txt clob; l_user varchar2(128); l_binds sql_binds := sql_binds(); l_t varchar2(128);
                begin
                  \(textAndUser(set.origin.isAWR ? .awr : .cursorCache, dbid: dbid))
                  for b in (\(bq)) loop l_binds.extend; l_binds(l_binds.count) := b.value_anydata; end loop;
                  l_t := dbms_sqltune.create_tuning_task(sql_text => l_txt, bind_list => l_binds, user_name => l_user, scope => 'COMPREHENSIVE',
                                                         time_limit => :tl, task_name => :t, description => 'Pelikan');
                  dbms_sqltune.execute_tuning_task(task_name => :t);
                end;
                """, binds: [text("id", id), num("tl", q.timeLimit), t] + bb)
        } else if q.source == .awr {
            _ = try await s.execute("""
                declare l_t varchar2(128); begin
                  l_t := dbms_sqltune.create_tuning_task(begin_snap => :bs, end_snap => :es, sql_id => :id, plan_hash_value => :ph, scope => 'COMPREHENSIVE',
                                                         time_limit => :tl, task_name => :t, description => 'Pelikan');
                  dbms_sqltune.execute_tuning_task(task_name => :t);
                end;
                """, binds: [num("bs", q.beginSnap), num("es", q.endSnap), text("id", id), numText("ph", q.planHash), num("tl", q.timeLimit), t])
        } else {
            _ = try await s.execute("""
                declare l_t varchar2(128); begin
                  l_t := dbms_sqltune.create_tuning_task(sql_id => :id, plan_hash_value => :ph, scope => 'COMPREHENSIVE', time_limit => :tl,
                                                         task_name => :t, description => 'Pelikan');
                  dbms_sqltune.execute_tuning_task(task_name => :t);
                end;
                """, binds: [text("id", id), numText("ph", q.planHash), num("tl", q.timeLimit), t])
        }
        let r = try await s.execute("begin :r := dbms_sqltune.report_tuning_task(:t, 'TEXT', 'TYPICAL', 'ALL'); :sc := dbms_sqltune.script_tuning_task(:t, 'ALL'); end;",
                                    binds: [BindVariable(name: "r", type: .clob, direction: .output), BindVariable(name: "sc", type: .clob, direction: .output), t],
                                    options: ExecuteOptions(lobLimit: 50_000_000))
        var out = ""
        if case .lob(let l)? = r.outBinds["r"] { out = l.text ?? "" }
        if case .lob(let l)? = r.outBinds["sc"], let sc = l.text, !sc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "\n\n-- " + L10n.tr("Skrypt zaleceń (DBMS_SQLTUNE.SCRIPT_TUNING_TASK) — przejrzyj przed wykonaniem") + "\n" + sc
        }
        return out
    }

    static func repair(_ q: PerfReportRequest, availability a: SQLAvailability?, in s: any DatabaseSession) async throws -> String {
        let id = q.sqlID ?? ""
        let task = taskName("PLK_DIAG", id)
        let t = text("t", task)
        defer { Task { _ = try? await s.execute("begin dbms_sqldiag.drop_diagnosis_task(:t); end;", binds: [t]) } }
        if let set = q.bindSet, set.usableByAdvisor, let (bq, bb) = bindQuery(set, dbid: SQLProbe.dbid(19)) {
            _ = try await s.execute("""
                declare l_txt clob; l_user varchar2(128); l_binds sql_binds := sql_binds(); l_t varchar2(128);
                begin
                  \(textAndUser(set.origin.isAWR ? .awr : .cursorCache, dbid: SQLProbe.dbid(19)))
                  for b in (\(bq)) loop l_binds.extend; l_binds(l_binds.count) := b.value_anydata; end loop;
                  l_t := dbms_sqldiag.create_diagnosis_task(sql_text => l_txt, bind_list => l_binds, user_name => l_user, time_limit => :tl,
                                                            task_name => :t, problem_type => dbms_sqldiag.problem_type_performance);
                  dbms_sqldiag.execute_diagnosis_task(:t);
                end;
                """, binds: [text("id", id), num("tl", q.timeLimit), t] + bb)
        } else {
            _ = try await s.execute("""
                declare l_t varchar2(128); begin
                  l_t := dbms_sqldiag.create_diagnosis_task(sql_id => :id, time_limit => :tl, task_name => :t, problem_type => dbms_sqldiag.problem_type_performance);
                  dbms_sqldiag.execute_diagnosis_task(:t);
                end;
                """, binds: [text("id", id), num("tl", q.timeLimit), t])
        }
        let r = try await s.execute("begin :r := dbms_sqldiag.report_diagnosis_task(:t, :ty); end;",
                                    binds: [BindVariable(name: "r", type: .clob, direction: .output), t, text("ty", q.format.oracleType)],
                                    options: ExecuteOptions(lobLimit: 50_000_000))
        if case .lob(let l)? = r.outBinds["r"] { return l.text ?? "" }
        return ""
    }
}

extension SQLAvailability.BindSet.Origin {
    var isAWR: Bool { if case .awr = self { return true }; return false }
}
