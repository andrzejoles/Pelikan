import Foundation
import PelikanDB

/// Licencje pakietów dostępne dla połączenia w tej chwili (deklaracja i CONTROL_MANAGEMENT_PACK_ACCESS, D63).
public struct PerfLicense: Sendable, Hashable {
    public var diagnostics: Bool
    public var tuning: Bool
    /// Powód braku (np. parametr NONE, deklaracja tylko Diagnostics).
    public var note: String?

    public init(diagnostics: Bool, tuning: Bool, note: String? = nil) { self.diagnostics = diagnostics; self.tuning = tuning; self.note = note }

    public func allows(_ need: PerfReport.Need) -> Bool {
        switch need {
        case .none: true
        case .diagnostics: diagnostics
        case .tuning: tuning && diagnostics
        }
    }

    public static let all = PerfLicense(diagnostics: true, tuning: true)
}

/// Gdzie Oracle pamięta zapytanie (D217): pamięć kursorów, aktywne sesje, ASH, AWR, SQL Monitor, zapisane raporty
/// i zapamiętane bindy. Źródła płatne sprawdzane tylko z licencją; brak uprawnień — uwaga zamiast błędu.
public struct SQLAvailability: Sendable {
    public struct Cursor: Sendable, Hashable, Identifiable {
        public var id: String { "\(instance)/\(child)" }
        public var instance: Int, child: Int, planHash: String, executions: String, elapsedSeconds: String, lastActive: String
    }

    public struct Snapshot: Sendable, Hashable, Identifiable {
        public var id: String { "\(snapID)/\(instance)" }
        public var snapID: Int, instance: Int, begin: String, end: String, planHash: String
        public var executions: String, elapsedSeconds: String, bufferGets: String, diskReads: String, rows: String
    }

    public struct Execution: Sendable, Hashable, Identifiable {
        public var id: String { "\(instance)/\(execID)/\(start)" }
        public var instance: Int, execID: String, start: String, status: String, elapsedSeconds: String, sid: String
    }

    public struct StoredReport: Sendable, Hashable, Identifiable {
        public var id: String { reportID }
        public var reportID: String, execID: String, start: String
    }

    public struct Bind: Sendable, Hashable {
        public var position: Int, name: String, type: String, value: String?, captured: Bool
    }

    /// Zestaw zapamiętanych bindów jednego kursora, migawki AWR albo wykonania SQL Monitor.
    public struct BindSet: Sendable, Hashable, Identifiable {
        public enum Origin: Sendable, Hashable {
            case cursor(instance: Int, child: Int)
            case awr(snapID: Int, instance: Int)
            case monitor(instance: Int, execID: String, start: String)
        }
        public var id: String {
            switch origin {
            case .cursor(let i, let c): "c/\(i)/\(c)"
            case .awr(let s, let i): "a/\(s)/\(i)"
            case .monitor(let i, let e, let st): "m/\(i)/\(e)/\(st)"
            }
        }
        public var origin: Origin
        public var captured: String
        public var binds: [Bind]

        /// Czy zestaw można przekazać doradcy (ANYDATA jest tylko w V$SQL_BIND_CAPTURE i DBA_HIST_SQLBIND).
        public var usableByAdvisor: Bool {
            if case .monitor = origin { return false }
            return !binds.isEmpty && binds.allSatisfy(\.captured)
        }

        public var label: String {
            let values = binds.prefix(4).map { "\($0.name)=\($0.value ?? "NULL")" }.joined(separator: ", ") + (binds.count > 4 ? ", …" : "")
            switch origin {
            case .cursor(let i, let c): return L10n.tr("Kursor \(c) (instancja \(i)), \(captured): \(values)")
            case .awr(let s, _): return L10n.tr("AWR, migawka \(s), \(captured): \(values)")
            case .monitor(_, let e, let st): return L10n.tr("SQL Monitor, wykonanie \(e) z \(st): \(values)")
            }
        }
    }

    public var sqlID: String
    public var hashValue: UInt32?
    public var text: String?
    public var schema: String?
    public var cursors: [Cursor] = []
    public var activeSessions = 0
    /// ASH w pamięci: pierwsza i ostatnia próbka, liczba próbek.
    public var ash: (first: String, last: String, samples: Int)?
    public var snapshots: [Snapshot] = []
    public var executions: [Execution] = []
    public var storedReports: [StoredReport] = []
    public var bindSets: [BindSet] = []
    public var notes: [String] = []
    /// Czas bazy (SYSDATE) i bieżąca instancja — wartości domyślne okien czasu.
    public var now = ""
    public var instance = 1
    public var license = PerfLicense.all
    public var major = 19

    public init(sqlID: String) { self.sqlID = sqlID; hashValue = SQLIdentity.hashValue(sqlID: sqlID) }

    /// Źródła, w których zapytanie jest.
    public var sources: [ReportSource] {
        var out: [ReportSource] = []
        if !cursors.isEmpty { out.append(.cursorCache) }
        if ash != nil { out.append(.ashMemory) }
        if !snapshots.isEmpty { out.append(.awr) }
        if ash != nil, !snapshots.isEmpty { out.append(.ashBoth) }
        if !executions.isEmpty { out.append(.sqlMonitor) }
        if !storedReports.isEmpty { out.append(.reportRepository) }
        return out
    }

    public var isEmpty: Bool { cursors.isEmpty && ash == nil && snapshots.isEmpty && executions.isEmpty && storedReports.isEmpty && activeSessions == 0 }

    /// Pierwsza i ostatnia migawka AWR z zapytaniem; początek raportu — migawka przed pierwszą (raport liczy różnice).
    public var snapshotRange: (begin: Int, end: Int)? {
        guard let lo = snapshots.map(\.snapID).min(), let hi = snapshots.map(\.snapID).max() else { return nil }
        return (lo == hi ? lo - 1 : lo - 1, hi)
    }

    /// Różne plany (z pamięci i AWR).
    public var planHashes: [String] {
        var seen: [String] = []
        for p in cursors.map(\.planHash) + snapshots.map(\.planHash) where p != "0" && !p.isEmpty && !seen.contains(p) { seen.append(p) }
        return seen
    }

    /// Okno czasu z dostępnych danych: ASH w pamięci, potem AWR; inaczej ostatnia godzina.
    public func window(for source: ReportSource?) -> (begin: String, end: String) {
        if source != .awr, let a = ash { return (a.first, a.last) }
        if let first = snapshots.first, let last = snapshots.last, source != .ashMemory { return (first.begin, last.end) }
        if let a = ash { return (a.first, a.last) }
        return ("", now)
    }
}

/// Sprawdzanie dostępności zapytania w bazie (D217).
public enum SQLProbe {
    static func dbid(_ major: Int) -> String { major >= 12 ? "to_number(sys_context('userenv', 'con_dbid'))" : "(select dbid from v$database)" }
    static let ts = "'YYYY-MM-DD HH24:MI:SS'"

    /// SQL_ID dla hasha: najpierw pamięć kursorów, potem (z licencją Diagnostics) AWR.
    public static func resolve(hash: UInt32, in s: any DatabaseSession, license: PerfLicense, major: Int) async throws -> String? {
        let h = BindVariable(name: "h", type: .number, value: .text(String(hash)))
        if let id = try? await s.scalar("select sql_id from gv$sql where hash_value = :h and rownum = 1", binds: [h]), !id.isEmpty { return id }
        if license.diagnostics,
           let id = try? await s.scalar("select sql_id from dba_hist_sqltext where dbid = \(dbid(major)) and dbms_utility.sqlid_to_sqlhash(sql_id) = :h and rownum = 1", binds: [h]),
           !id.isEmpty { return id }
        return nil
    }

    /// Dostępność zapytania; każde źródło osobno (brak uprawnień do jednego widoku nie przerywa sprawdzania).
    public static func probe(sqlID: String, in s: any DatabaseSession, license: PerfLicense) async -> SQLAvailability {
        var a = SQLAvailability(sqlID: sqlID)
        a.license = license
        a.major = s.info.server.major > 0 ? s.info.server.major : 19
        let idBind = BindVariable(name: "id", value: .text(sqlID))
        func rows(_ sql: String, _ what: String, limit: Int = 2000) async -> [[String]] {
            do {
                return try await s.queryAll(sql, binds: [idBind], limit: limit).1.map { $0.map { $0.displayText ?? "" } }
            } catch let e as OracleError {
                a.notes.append(L10n.tr("\(what): \(e.code == 942 || e.code == 1031 ? L10n.tr("brak uprawnień do widoku (zwykle rola SELECT_CATALOG_ROLE)") : "ORA-\(String(format: "%05d", e.code))")"))
                return []
            } catch {
                a.notes.append("\(what): \(error.localizedDescription)")
                return []
            }
        }
        a.now = (try? await s.scalar("select to_char(sysdate, \(ts)) from dual")) ?? ""
        a.instance = Int((try? await s.scalar("select instance_number from v$instance")) ?? "1") ?? 1

        // Pamięć kursorów i sesje — bez licencji.
        for r in await rows("""
            select inst_id, child_number, plan_hash_value, executions, round(elapsed_time / 1e6, 3), to_char(last_active_time, \(ts)), parsing_schema_name
              from gv$sql where sql_id = :id order by inst_id, child_number
            """, L10n.tr("Pamięć kursorów"), limit: 200) {
            a.cursors.append(.init(instance: Int(r[0]) ?? 1, child: Int(r[1]) ?? 0, planHash: r[2], executions: r[3], elapsedSeconds: r[4], lastActive: r[5]))
            if a.schema == nil, !r[6].isEmpty { a.schema = r[6] }
        }
        if !a.cursors.isEmpty {
            a.text = try? await s.queryAll("select sql_fulltext from gv$sql where sql_id = :id and rownum = 1", binds: [idBind], limit: 1).1.first?.first?.displayText
        }
        a.activeSessions = Int(await rows("select count(*) from gv$session where sql_id = :id and status = 'ACTIVE'", L10n.tr("Aktywne sesje")).first?.first ?? "0") ?? 0
        for r in await rows("""
            select inst_id, child_number, position, name, datatype_string, was_captured, value_string, to_char(last_captured, \(ts))
              from gv$sql_bind_capture where sql_id = :id order by inst_id, child_number, position
            """, L10n.tr("Bindy w pamięci kursorów")) {
            let origin = SQLAvailability.BindSet.Origin.cursor(instance: Int(r[0]) ?? 1, child: Int(r[1]) ?? 0)
            a.add(origin, captured: r[7], bind: .init(position: Int(r[2]) ?? 0, name: r[3], type: r[4], value: r[5] == "YES" ? r[6] : nil, captured: r[5] == "YES"))
        }

        if license.diagnostics {
            if let r = await rows("select to_char(min(sample_time), \(ts)), to_char(max(sample_time), \(ts)), count(*) from gv$active_session_history where sql_id = :id",
                                  L10n.tr("ASH w pamięci")).first, let n = Int(r[2]), n > 0 {
                a.ash = (r[0], r[1], n)
            }
            for r in await rows("""
                select s.snap_id, s.instance_number, to_char(sn.begin_interval_time, \(ts)), to_char(sn.end_interval_time, \(ts)), s.plan_hash_value,
                       s.executions_delta, round(s.elapsed_time_delta / 1e6, 3), s.buffer_gets_delta, s.disk_reads_delta, s.rows_processed_delta,
                       s.parsing_schema_name
                  from dba_hist_sqlstat s
                  join dba_hist_snapshot sn on sn.snap_id = s.snap_id and sn.dbid = s.dbid and sn.instance_number = s.instance_number
                 where s.sql_id = :id and s.dbid = \(dbid(a.major))
                 order by s.snap_id, s.instance_number
                """, "AWR", limit: 5000) {
                a.snapshots.append(.init(snapID: Int(r[0]) ?? 0, instance: Int(r[1]) ?? 1, begin: r[2], end: r[3], planHash: r[4], executions: r[5],
                                         elapsedSeconds: r[6], bufferGets: r[7], diskReads: r[8], rows: r[9]))
                if a.schema == nil, !r[10].isEmpty { a.schema = r[10] }
            }
            if a.text == nil, !a.snapshots.isEmpty {
                a.text = try? await s.queryAll("select sql_text from dba_hist_sqltext where sql_id = :id and dbid = \(dbid(a.major)) and rownum = 1",
                                               binds: [idBind], limit: 1).1.first?.first?.displayText
            }
            // Najnowsze zestawy bindów z AWR (najwyżej 20 migawek).
            var awrSets = 0
            var lastSnap = ""
            for r in await rows("""
                select snap_id, instance_number, position, name, datatype_string, was_captured, value_string, to_char(last_captured, \(ts))
                  from dba_hist_sqlbind where sql_id = :id and dbid = \(dbid(a.major)) order by snap_id desc, instance_number, position
                """, L10n.tr("Bindy w AWR")) {
                if r[0] + "/" + r[1] != lastSnap { lastSnap = r[0] + "/" + r[1]; awrSets += 1 }
                guard awrSets <= 20 else { break }
                a.add(.awr(snapID: Int(r[0]) ?? 0, instance: Int(r[1]) ?? 1), captured: r[7],
                      bind: .init(position: Int(r[2]) ?? 0, name: r[3], type: r[4], value: r[5] == "YES" ? r[6] : nil, captured: r[5] == "YES"))
            }
        }

        if license.allows(.tuning) {
            for r in await rows("""
                select inst_id, sql_exec_id, to_char(sql_exec_start, \(ts)), status, round(elapsed_time / 1e6, 3), sid
                  from gv$sql_monitor where sql_id = :id order by sql_exec_start desc
                """, "SQL Monitor", limit: 200) {
                a.executions.append(.init(instance: Int(r[0]) ?? 1, execID: r[1], start: r[2], status: r[3], elapsedSeconds: r[4], sid: r[5]))
            }
            if a.major >= 12 {
                for r in await rows("""
                    select report_id, key2, to_char(period_start_time, \(ts)) from dba_hist_reports
                     where component_name = 'sqlmonitor' and key1 = :id order by period_start_time desc
                    """, L10n.tr("Zapisane raporty SQL Monitor"), limit: 200) {
                    a.storedReports.append(.init(reportID: r[0], execID: r[1], start: r[2]))
                }
            }
            if !a.executions.isEmpty {
                // Struktura BINDS_XML nie jest opisana w dokumentacji — błąd odczytu nie jest zgłaszany.
                if let (_, rs) = try? await s.queryAll("""
                    select m.inst_id, m.sql_exec_id, to_char(m.sql_exec_start, \(ts)), x.pos, x.name, x.dty, x.val
                      from gv$sql_monitor m,
                           xmltable('/binds/bind' passing xmltype(m.binds_xml)
                                    columns name varchar2(128) path '@name', pos number path '@pos',
                                            dty varchar2(30) path '@dtystr', val varchar2(4000) path '.') x
                     where m.sql_id = :id and m.binds_xml is not null
                     order by m.sql_exec_start desc, x.pos
                    """, binds: [idBind], limit: 2000) {
                    for r in rs.map({ $0.map { $0.displayText ?? "" } }) {
                        a.add(.monitor(instance: Int(r[0]) ?? 1, execID: r[1], start: r[2]), captured: r[2],
                              bind: .init(position: Int(r[3]) ?? 0, name: r[4], type: r[5], value: r[6], captured: true))
                    }
                }
            }
        }
        if !license.diagnostics { a.notes.append(L10n.tr("ASH i AWR pominięte — brak Diagnostics Pack dla połączenia")) }
        else if !license.tuning { a.notes.append(L10n.tr("SQL Monitor pominięty — brak Tuning Pack dla połączenia")) }
        if let n = license.note { a.notes.append(n) }
        return a
    }
}

extension SQLAvailability {
    mutating func add(_ origin: BindSet.Origin, captured: String, bind: Bind) {
        if let i = bindSets.firstIndex(where: { $0.origin == origin }) {
            bindSets[i].binds.append(bind)
        } else {
            bindSets.append(BindSet(origin: origin, captured: captured, binds: [bind]))
        }
    }

    /// Raporty dostępne dla zapytania: (raport, czy można uruchomić, powód blokady).
    public func reports() -> [(report: PerfReport, available: Bool, reason: String?)] {
        PerfReportCatalog.sqlReports.map { r in
            if major < r.minMajor { return (r, false, L10n.tr("Wymaga Oracle \(r.minMajor) lub nowszej")) }
            if !license.allows(r.need) { return (r, false, L10n.tr("Wymaga licencji \(r.need.displayName)")) }
            if r.id == "sql.binds" {
                return bindSets.isEmpty ? (r, false, L10n.tr("Oracle nie przechwycił bindów tego zapytania")) : (r, true, nil)
            }
            if r.sources.isEmpty { return (r, true, nil) }
            let usable = r.sources.filter { sources.contains($0) && license.allows(r.need(for: $0)) }
            if usable.isEmpty { return (r, false, L10n.tr("Zapytania nie ma w: \(r.sources.map(\.displayName).joined(separator: ", "))")) }
            return (r, true, nil)
        }
    }

    /// Źródła raportu, w których zapytanie jest i na które jest licencja.
    public func sources(for r: PerfReport) -> [ReportSource] {
        if r.id == "sql.binds" {
            var out: [ReportSource] = []
            for b in bindSets {
                let s: ReportSource = switch b.origin { case .cursor: .cursorCache; case .awr: .awr; case .monitor: .sqlMonitor }
                if !out.contains(s) { out.append(s) }
            }
            return out
        }
        return r.sources.filter { sources.contains($0) && license.allows(r.need(for: $0)) }
    }
}
