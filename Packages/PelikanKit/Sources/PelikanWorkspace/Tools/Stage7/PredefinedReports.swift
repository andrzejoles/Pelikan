import Foundation
import PelikanDB
import PelikanSQL

/// Raport predefiniowany (SD-REP-001): kategoria, styl wyniku (siatka, wykres, DBMS_OUTPUT), zmienne, raport
/// szczegółów dla wiersza. Zapytania w słowniku ALL_/USER_ (bez uprawnień DBA); schemat domyślnie bieżący.
public struct PredefinedReport: Sendable, Hashable, Identifiable {
    public enum Style: String, Sendable, Hashable, CaseIterable { case grid, chart, dbmsOutput }
    public struct Variable: Sendable, Hashable {
        public var name: String
        public var label: String
        public var defaultValue: String
    }
    public var id: String
    public var category: String
    public var title: String
    public var sql: String
    public var style: Style = .grid
    public var variables: [Variable] = []
    /// Wykres (styl `.chart`): kolumna kategorii i serie.
    public var chart: ChartDefinition?
    /// Raport szczegółów: zapytanie z binds `:PARENT_<KOLUMNA>` z zaznaczonego wiersza.
    public var detailTitle: String?
    public var detailSQL: String?
}

/// Wynik raportu: siatka (kolumny + wiersze) albo linie DBMS_OUTPUT.
public struct PredefinedReportResult: Sendable {
    public var columns: [ColumnInfo] = []
    public var rows: [[OracleValue]] = []
    public var output: [String] = []
    public var truncated = false
}

public enum PredefinedReports {
    static let owner = "nvl(upper(:owner), sys_context('userenv', 'current_schema'))"
    static let ownerVar = PredefinedReport.Variable(name: "OWNER", label: L10n.tr("Schemat (puste — bieżący)"), defaultValue: "")

    /// Katalog raportów w kategoriach.
    public static var catalog: [PredefinedReport] {
        let about = L10n.tr("O bazie danych"), objects = L10n.tr("Obiekty"), tables = L10n.tr("Tabele"), plsql = L10n.tr("PL/SQL"),
            security = L10n.tr("Bezpieczeństwo"), storage = L10n.tr("Przechowywanie"), jobs = L10n.tr("Harmonogram")
        func chart(_ category: String, _ series: [String]) -> ChartDefinition {
            var c = ChartDefinition(name: L10n.tr("Wykres"))
            c.categoryColumn = category
            c.seriesColumns = series
            return c
        }
        return [
            PredefinedReport(id: "version", category: about, title: L10n.tr("Wersja bazy i komponenty"), sql: """
                select product, version, status from product_component_version order by product
                """),
            PredefinedReport(id: "nls", category: about, title: L10n.tr("Parametry NLS (sesja i baza)"), sql: """
                select s.parameter, s.value wartosc_sesji, d.value wartosc_bazy
                  from nls_session_parameters s left join nls_database_parameters d on d.parameter = s.parameter
                 order by s.parameter
                """),
            PredefinedReport(id: "sessionContext", category: about, title: L10n.tr("Kontekst sesji"), sql: """
                select 'SESSION_USER' atrybut, sys_context('userenv', 'session_user') wartosc from dual union all
                select 'CURRENT_SCHEMA', sys_context('userenv', 'current_schema') from dual union all
                select 'DB_NAME', sys_context('userenv', 'db_name') from dual union all
                select 'CON_NAME', sys_context('userenv', 'con_name') from dual union all
                select 'SERVICE_NAME', sys_context('userenv', 'service_name') from dual union all
                select 'SID', sys_context('userenv', 'sid') from dual
                """),
            PredefinedReport(id: "objectsByType", category: objects, title: L10n.tr("Obiekty według typu"), sql: """
                select object_type, count(*) liczba from all_objects where owner = \(owner) group by object_type order by 2 desc
                """, style: .chart, variables: [ownerVar], chart: chart("OBJECT_TYPE", ["LICZBA"]),
                detailTitle: L10n.tr("Obiekty typu"), detailSQL: """
                select object_name, status, last_ddl_time from all_objects
                 where owner = \(owner) and object_type = :parent_object_type order by object_name
                """),
            PredefinedReport(id: "invalidObjects", category: objects, title: L10n.tr("Nieprawidłowe obiekty"), sql: """
                select object_type, object_name, last_ddl_time from all_objects
                 where owner = \(owner) and status <> 'VALID' order by object_type, object_name
                """, variables: [ownerVar], detailTitle: L10n.tr("Błędy kompilacji"), detailSQL: """
                select line, position, text from all_errors
                 where owner = \(owner) and name = :parent_object_name and type = :parent_object_type order by sequence
                """),
            PredefinedReport(id: "recentObjects", category: objects, title: L10n.tr("Ostatnio zmienione obiekty"), sql: """
                select object_type, object_name, last_ddl_time, status from all_objects
                 where owner = \(owner) and last_ddl_time > sysdate - to_number(nvl(:days, '7')) order by last_ddl_time desc
                """, variables: [ownerVar, .init(name: "DAYS", label: L10n.tr("Dni wstecz"), defaultValue: "7")]),
            PredefinedReport(id: "tableRows", category: tables, title: L10n.tr("Tabele — liczba wierszy (statystyki)"), sql: """
                select table_name, num_rows, blocks, to_char(last_analyzed, 'YYYY-MM-DD HH24:MI') last_analyzed from all_tables
                 where owner = \(owner) order by num_rows desc nulls last, table_name
                """, variables: [ownerVar], detailTitle: L10n.tr("Kolumny"), detailSQL: """
                select column_name, data_type, data_length, data_precision, data_scale, nullable from all_tab_columns
                 where owner = \(owner) and table_name = :parent_table_name order by column_id
                """),
            PredefinedReport(id: "tablesWithoutPK", category: tables, title: L10n.tr("Tabele bez klucza głównego"), sql: """
                select t.table_name from all_tables t
                 where t.owner = \(owner)
                   and not exists (select 1 from all_constraints c where c.owner = t.owner and c.table_name = t.table_name and c.constraint_type = 'P')
                 order by t.table_name
                """, variables: [ownerVar]),
            PredefinedReport(id: "unindexedFK", category: tables, title: L10n.tr("Klucze obce bez indeksu"), sql: """
                select c.table_name, c.constraint_name, cc.column_name from all_constraints c
                  join all_cons_columns cc on cc.owner = c.owner and cc.constraint_name = c.constraint_name and cc.position = 1
                 where c.owner = \(owner) and c.constraint_type = 'R'
                   and not exists (select 1 from all_ind_columns ic where ic.table_owner = c.owner and ic.table_name = c.table_name
                                      and ic.column_name = cc.column_name and ic.column_position = 1)
                 order by c.table_name, c.constraint_name
                """, variables: [ownerVar]),
            PredefinedReport(id: "constraints", category: tables, title: L10n.tr("Więzy"), sql: """
                select table_name, constraint_name, constraint_type, status, r_constraint_name from all_constraints
                 where owner = \(owner) and constraint_name not like 'BIN$%' order by table_name, constraint_type, constraint_name
                """, variables: [ownerVar]),
            PredefinedReport(id: "sourceSizes", category: plsql, title: L10n.tr("Rozmiar kodu PL/SQL"), sql: """
                select name, type, count(*) linie from all_source where owner = \(owner) group by name, type order by 3 desc
                """, style: .chart, variables: [ownerVar], chart: chart("NAME", ["LINIE"]), detailTitle: L10n.tr("Źródło"), detailSQL: """
                select line, text from all_source where owner = \(owner) and name = :parent_name and type = :parent_type order by line
                """),
            PredefinedReport(id: "searchSource", category: plsql, title: L10n.tr("Szukaj w kodzie"), sql: """
                select name, type, line, text from all_source
                 where owner = \(owner) and upper(text) like '%' || upper(:text) || '%' order by name, type, line
                """, variables: [ownerVar, .init(name: "TEXT", label: L10n.tr("Szukany tekst"), defaultValue: "")]),
            PredefinedReport(id: "dependencies", category: plsql, title: L10n.tr("Zależności obiektu"), sql: """
                select referenced_owner, referenced_name, referenced_type, dependency_type from all_dependencies
                 where owner = \(owner) and name = upper(:name) order by referenced_owner, referenced_name
                """, variables: [ownerVar, .init(name: "NAME", label: L10n.tr("Obiekt"), defaultValue: "")]),
            PredefinedReport(id: "schemaSummary", category: plsql, title: L10n.tr("Podsumowanie schematu (DBMS_OUTPUT)"), sql: """
                begin
                  for r in (select object_type, count(*) n from all_objects where owner = \(owner) group by object_type order by object_type) loop
                    dbms_output.put_line(rpad(r.object_type, 24) || lpad(r.n, 8));
                  end loop;
                end;
                """, style: .dbmsOutput, variables: [ownerVar]),
            PredefinedReport(id: "roles", category: security, title: L10n.tr("Role użytkownika"), sql: """
                select granted_role, admin_option, default_role from user_role_privs order by granted_role
                """),
            PredefinedReport(id: "sysPrivs", category: security, title: L10n.tr("Uprawnienia systemowe"), sql: """
                select privilege, admin_option from user_sys_privs union select privilege, admin_option from role_sys_privs order by 1
                """),
            PredefinedReport(id: "objectGrants", category: security, title: L10n.tr("Nadane uprawnienia do obiektów"), sql: """
                select grantee, table_name, privilege, grantable from all_tab_privs where grantor = \(owner) order by grantee, table_name
                """, variables: [ownerVar]),
            PredefinedReport(id: "segments", category: storage, title: L10n.tr("Segmenty według typu (MB)"), sql: """
                select segment_type, round(sum(bytes) / 1048576, 2) mb from user_segments group by segment_type order by 2 desc
                """, style: .chart, chart: chart("SEGMENT_TYPE", ["MB"]), detailTitle: L10n.tr("Segmenty"), detailSQL: """
                select segment_name, round(bytes / 1048576, 2) mb, tablespace_name from user_segments
                 where segment_type = :parent_segment_type order by bytes desc
                """),
            PredefinedReport(id: "quotas", category: storage, title: L10n.tr("Limity przestrzeni tabel"), sql: """
                select tablespace_name, round(bytes / 1048576, 2) mb_uzyte,
                       case max_bytes when -1 then null else round(max_bytes / 1048576, 2) end mb_limit from user_ts_quotas order by 1
                """),
            PredefinedReport(id: "schedulerJobs", category: jobs, title: L10n.tr("Zadania harmonogramu"), sql: """
                select job_name, enabled, state, to_char(next_run_date, 'YYYY-MM-DD HH24:MI') next_run, repeat_interval
                  from all_scheduler_jobs where owner = \(owner) order by job_name
                """, variables: [ownerVar], detailTitle: L10n.tr("Ostatnie uruchomienia"), detailSQL: """
                select to_char(actual_start_date, 'YYYY-MM-DD HH24:MI:SS') start_time, status, run_duration, additional_info
                  from all_scheduler_job_run_details where owner = \(owner) and job_name = :parent_job_name
                 order by actual_start_date desc fetch first 50 rows only
                """),
        ]
    }

    public static var categories: [String] {
        var seen: [String] = []
        for r in catalog where !seen.contains(r.category) { seen.append(r.category) }
        return seen
    }

    public static func report(_ id: String) -> PredefinedReport? { catalog.first { $0.id == id } }

    /// Nazwy zmiennych wiązanych zapytania (wielkimi literami, bez powtórzeń).
    public static func bindNames(_ sql: String) -> [String] {
        var out: [String] = []
        for v in Variables.find(in: sql, syntax: .sqlplus) where v.kind == .bind {
            let n = v.name.uppercased()
            if !out.contains(n) { out.append(n) }
        }
        return out
    }

    static func binds(_ sql: String, values: [String: String]) -> [BindVariable] {
        bindNames(sql).map { n in
            let v = values[n] ?? ""
            return BindVariable(name: n, type: .varchar2, value: v.isEmpty ? .null : .text(v), maxSize: 4000)
        }
    }

    /// Wartości dla raportu szczegółów: `PARENT_<KOLUMNA>` z wiersza nadrzędnego plus zmienne raportu.
    public static func detailValues(_ r: PredefinedReport, result: PredefinedReportResult, row: Int, values: [String: String]) -> [String: String] {
        var out = values
        guard result.rows.indices.contains(row) else { return out }
        for (i, c) in result.columns.enumerated() where i < result.rows[row].count {
            out["PARENT_" + c.name.uppercased()] = result.rows[row][i].displayText ?? ""
        }
        return out
    }

    /// Wykonanie raportu (zapytanie albo blok z DBMS_OUTPUT); `values` — zmienne po nazwie (wielkie litery).
    public static func run(_ sql: String, style: PredefinedReport.Style, values: [String: String], maxRows: Int = 5000,
                           in s: any DatabaseSession) async throws -> PredefinedReportResult {
        var result = PredefinedReportResult()
        var text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if style == .dbmsOutput {
            try await SessionUtilities.enableOutput(s, bufferSize: 1_000_000)
            _ = try await s.execute(text, binds: binds(text, values: values), options: ExecuteOptions())
            result.output = try await SessionUtilities.readOutput(s)
            return result
        }
        while text.hasSuffix(";") { text.removeLast() }
        let r = try await s.execute(text, binds: binds(text, values: values), options: ExecuteOptions(lobLimit: 64_000))
        guard let rs = r.resultSet else { return result }
        result.columns = rs.columns
        while true {
            let batch = try await s.fetch(rs.id, maxRows: min(1000, maxRows + 1 - result.rows.count))
            for row in batch.rows {
                if result.rows.count >= maxRows { result.truncated = true; break }
                result.rows.append(row)
            }
            if result.truncated || !batch.hasMore { break }
        }
        if result.truncated { await s.closeResultSet(rs.id) }
        return result
    }

    public static func run(_ r: PredefinedReport, values: [String: String], in s: any DatabaseSession) async throws -> PredefinedReportResult {
        try await run(r.sql, style: r.style, values: values, in: s)
    }

    public static func detail(_ r: PredefinedReport, master: PredefinedReportResult, row: Int, values: [String: String],
                              in s: any DatabaseSession) async throws -> PredefinedReportResult? {
        guard let sql = r.detailSQL else { return nil }
        return try await run(sql, style: .grid, values: detailValues(r, result: master, row: row, values: values), in: s)
    }

    /// Dane do eksportu (formaty ResultExporter) albo dla wykresu.
    public static func exportData(_ r: PredefinedReport, _ result: PredefinedReportResult) -> ExportData {
        if r.style == .dbmsOutput {
            return ExportData(title: r.title, columns: [ColumnInfo(name: "OUTPUT", type: .varchar2, typeName: "VARCHAR2")],
                              rows: result.output.map { [.text($0)] }, sql: r.sql)
        }
        return ExportData(title: r.title, columns: result.columns, rows: result.rows, sql: r.sql)
    }

    public static func chartData(_ r: PredefinedReport, _ result: PredefinedReportResult) -> ChartData? {
        guard let c = r.chart ?? (r.style == .chart ? ChartBuilder.suggest(result.columns) : nil) else { return nil }
        return ChartBuilder.build(c, columns: result.columns, rows: result.rows)
    }
}

extension Workspace {
    /// „Open in Worksheet”: zapytanie raportu w nowym oknie SQL (zmienne wiązane zostają — okno zapyta o wartości).
    @discardableResult
    public func openReportInWorksheet(_ r: PredefinedReport) -> Document {
        let doc = newDocument(.sql, text: r.sql)
        doc.customTitle = r.title
        doc.isModified = false
        return doc
    }
}
