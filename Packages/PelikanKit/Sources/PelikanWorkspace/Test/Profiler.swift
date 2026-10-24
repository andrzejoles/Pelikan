import Foundation
import PelikanDB

/// Profiler okna testu (UG 6.3): liniowy DBMS_PROFILER albo hierarchiczny DBMS_HPROF.
public enum ProfilerKind: String, Sendable, Codable, Hashable, CaseIterable {
    case lines, hierarchical
}

/// Linia raportu profilera liniowego: jednostka, linia, liczba wykonań, czas (ns), tekst źródła.
public struct ProfilerLine: Sendable, Hashable, Identifiable {
    public var unitNumber: Int
    public var unitOwner: String
    public var unitName: String
    public var unitType: String
    public var line: Int
    public var occurrences: Int
    public var totalTime: Double
    public var minTime: Double
    public var maxTime: Double
    public var text: String
    public var id: String { "\(unitNumber):\(line)" }
    public var isAnonymous: Bool { unitType == "ANONYMOUS BLOCK" || unitName == "<anonymous>" }
}

/// Funkcja raportu profilera hierarchicznego: liczba wywołań, czas własny i z wywołaniami (µs), wywoływane.
public struct ProfilerFunction: Sendable, Hashable, Identifiable {
    public var symbol: Int
    public var owner: String
    public var module: String
    public var type: String
    public var function: String
    public var line: Int
    public var calls: Int
    public var functionTime: Double
    public var subtreeTime: Double
    public var children: [Int]
    public var id: Int { symbol }
    public var displayName: String {
        [owner, module, function].filter { !$0.isEmpty }.joined(separator: ".")
    }
}

/// Raport przebiegu profilera.
public struct ProfilerReport: Sendable, Hashable {
    public var kind: ProfilerKind
    public var run: Int
    public var totalTime: Double
    public var lines: [ProfilerLine]
    public var functions: [ProfilerFunction]
}

@MainActor
public enum Profiler {
    /// Tabele profilera liniowego w schemacie użytkownika (jak w PROFTAB.SQL), tworzone, gdy ich brak.
    static func ensureLineTables(_ s: any DatabaseSession) async throws {
        let n = try await s.scalar("select count(*) from user_tables where table_name = 'PLSQL_PROFILER_RUNS'")
        guard n == "0" else { return }
        // 23ai+: DBMS_PROFILER.CREATE_TABLES; starsze wersje — DDL jak w PROFTAB.SQL.
        if (try? await s.execute("begin dbms_profiler.create_tables; end;")) != nil { return }
        for ddl in [
            "create table plsql_profiler_runs (runid number primary key, related_run number, run_owner varchar2(128), run_date date, run_comment varchar2(2047), run_total_time number, run_system_info varchar2(2047), run_comment1 varchar2(2047), spare1 varchar2(256))",
            "create table plsql_profiler_units (runid number references plsql_profiler_runs, unit_number number, unit_type varchar2(128), unit_owner varchar2(128), unit_name varchar2(128), unit_timestamp date, total_time number default 0 not null, spare1 number, spare2 number, primary key (runid, unit_number))",
            "create table plsql_profiler_data (runid number, unit_number number, line# number not null, total_occur number, total_time number, min_time number, max_time number, spare1 number, spare2 number, spare3 number, spare4 number, primary key (runid, unit_number, line#), foreign key (runid, unit_number) references plsql_profiler_units)",
            "create sequence plsql_profiler_runnumber start with 1 nocache",
        ] { _ = try await s.execute(ddl) }
    }

    /// Tabele profilera hierarchicznego (DBMS_HPROF.CREATE_TABLES), gdy ich brak.
    static func ensureHierarchicalTables(_ s: any DatabaseSession) async throws {
        let n = try await s.scalar("select count(*) from user_tables where table_name = 'DBMSHP_RUNS'")
        guard n == "0" else { return }
        _ = try await s.execute("begin dbms_hprof.create_tables; end;")
    }

    /// Czy brakuje tabel profilera (ich utworzenie to DDL — przez strażnika modyfikacji).
    static func needsTables(_ kind: ProfilerKind, session s: any DatabaseSession) async -> Bool {
        let table = kind == .lines ? "PLSQL_PROFILER_RUNS" : "DBMSHP_RUNS"
        return (try? await s.scalar("select count(*) from user_tables where table_name = :t", binds: [BindVariable(name: "t", value: .text(table))])) == "0"
    }

    /// Start przebiegu; zwraca identyfikator (numer przebiegu DBMS_PROFILER albo trace_id DBMS_HPROF).
    static func start(_ kind: ProfilerKind, session s: any DatabaseSession, comment: String) async throws -> Int {
        switch kind {
        case .lines:
            try await ensureLineTables(s)
            // Wariant z numerem przebiegu (OUT) zwraca w 26ai błąd — numer odczytywany po zatrzymaniu z komentarza.
            let r = try await s.execute("begin :st := dbms_profiler.start_profiler(:c); end;", binds: [
                BindVariable(name: "st", type: .number, direction: .output), BindVariable(name: "c", value: .text(comment)),
            ])
            let st = Int(r.outBinds["st"]?.displayText ?? r.outBinds["ST"]?.displayText ?? "") ?? -1
            guard st == 0 else { throw CommandError.notAvailable(L10n.tr("DBMS_PROFILER nie wystartował (status \(st))")) }
            return 0
        case .hierarchical:
            try await ensureHierarchicalTables(s)
            let r = try await s.execute("begin :t := dbms_hprof.start_profiling; end;", binds: [BindVariable(name: "t", type: .number, direction: .output)])
            return Int(r.outBinds["t"]?.displayText ?? r.outBinds["T"]?.displayText ?? "") ?? 0
        }
    }

    /// Koniec przebiegu i raport.
    static func stop(_ kind: ProfilerKind, id: Int, comment: String, session s: any DatabaseSession) async throws -> ProfilerReport {
        switch kind {
        case .lines:
            _ = try await s.execute("declare st binary_integer; begin st := dbms_profiler.stop_profiler; end;")
            let run = try await s.scalar("select max(runid) from plsql_profiler_runs where run_comment = :c", binds: [BindVariable(name: "c", value: .text(comment))])
            return try await lineReport(run: Int(run ?? "") ?? id, session: s)
        case .hierarchical:
            let r = try await s.execute("begin dbms_hprof.stop_profiling; :r := dbms_hprof.analyze(:t); end;", binds: [
                BindVariable(name: "r", type: .number, direction: .output), BindVariable(name: "t", type: .number, value: .number(String(id))),
            ])
            let run = Int(r.outBinds["r"]?.displayText ?? r.outBinds["R"]?.displayText ?? "") ?? 0
            return try await hierarchicalReport(run: run, session: s)
        }
    }

    /// Raport liniowy: jednostki i linie z czasem; tekst linii z ALL_SOURCE (blok anonimowy — bez tekstu).
    static func lineReport(run: Int, session s: any DatabaseSession) async throws -> ProfilerReport {
        let b = [BindVariable(name: "r", type: .number, value: .number(String(run)))]
        let total = try await s.scalar("select run_total_time from plsql_profiler_runs where runid = :r", binds: b)
        let (_, rows) = try await s.queryAll("""
            select u.unit_owner, u.unit_name, u.unit_type, d.line#, d.total_occur, d.total_time, d.min_time, d.max_time,
                   (select rtrim(s.text, chr(10)) from all_source s where s.owner = u.unit_owner and s.name = u.unit_name
                     and s.type = u.unit_type and s.line = d.line#), u.unit_number
            from plsql_profiler_data d join plsql_profiler_units u on u.runid = d.runid and u.unit_number = d.unit_number
            where d.runid = :r and d.total_occur > 0
            order by d.total_time desc
            """, binds: b, limit: 10_000)
        func num(_ v: OracleValue) -> Double { Double(v.format(.default)) ?? 0 }
        var lines = rows.map { r in
            ProfilerLine(unitNumber: Int(num(r[9])), unitOwner: r[0].displayText ?? "", unitName: r[1].displayText ?? "", unitType: r[2].displayText ?? "",
                         line: Int(num(r[3])), occurrences: Int(num(r[4])), totalTime: num(r[5]), minTime: num(r[6]), maxTime: num(r[7]),
                         text: (r[8].displayText ?? "").trimmingCharacters(in: .whitespaces))
        }
        // Bloki pomocnicze Pelikana (start/stop profilera, statystyki) — jednolinijkowe, wykonane 1–2 razy.
        let anonymousUnits = Dictionary(grouping: lines.filter(\.isAnonymous), by: \.unitNumber)
        let helpers = Set(anonymousUnits.filter { _, l in l.allSatisfy { $0.line == 1 } && l.reduce(0) { $0 + $1.occurrences } <= 2 }.keys)
        lines.removeAll { helpers.contains($0.unitNumber) }
        return ProfilerReport(kind: .lines, run: run, totalTime: Double(total ?? "") ?? lines.reduce(0) { $0 + $1.totalTime }, lines: lines, functions: [])
    }

    /// Raport hierarchiczny: funkcje z czasami i wywoływanymi (DBMSHP_FUNCTION_INFO, DBMSHP_PARENT_CHILD_INFO).
    static func hierarchicalReport(run: Int, session s: any DatabaseSession) async throws -> ProfilerReport {
        let b = [BindVariable(name: "r", type: .number, value: .number(String(run)))]
        let (_, rows) = try await s.queryAll("""
            select symbolid, owner, module, type, function, line#, calls, function_elapsed_time, subtree_elapsed_time
            from dbmshp_function_info where runid = :r order by subtree_elapsed_time desc
            """, binds: b, limit: 10_000)
        let (_, links) = try await s.queryAll("select parentsymid, childsymid from dbmshp_parent_child_info where runid = :r", binds: b, limit: 100_000)
        func num(_ v: OracleValue) -> Double { Double(v.format(.default)) ?? 0 }
        var children: [Int: [Int]] = [:]
        for l in links { children[Int(num(l[0])), default: []].append(Int(num(l[1]))) }
        let functions = rows.map { r in
            ProfilerFunction(symbol: Int(num(r[0])), owner: r[1].displayText ?? "", module: r[2].displayText ?? "", type: r[3].displayText ?? "",
                             function: r[4].displayText ?? "", line: Int(num(r[5])), calls: Int(num(r[6])), functionTime: num(r[7]),
                             subtreeTime: num(r[8]), children: children[Int(num(r[0]))] ?? [])
        }
        let total = try await s.scalar("select total_elapsed_time from dbmshp_runs where runid = :r", binds: b)
        return ProfilerReport(kind: .hierarchical, run: run, totalTime: Double(total ?? "") ?? 0, lines: [], functions: functions)
    }
}

/// Statystyka sesji (V$STATNAME / V$MYSTAT).
public struct SessionStatistic: Sendable, Hashable, Identifiable {
    public var name: String
    public var value: Double
    public var id: String { name }
}

extension Profiler {
    /// Migawka statystyk sesji; nil — brak uprawnień do V$MYSTAT (statystyki pomijane).
    static func statistics(_ s: any DatabaseSession) async -> [String: Double]? {
        guard let (_, rows) = try? await s.queryAll("""
            select n.name, m.value from v$mystat m join v$statname n on n.statistic# = m.statistic#
            """, limit: 10_000) else { return nil }
        var out: [String: Double] = [:]
        for r in rows { out[r[0].displayText ?? ""] = Double(r[1].format(.default)) ?? 0 }
        return out
    }

    /// Wiersz widoku statystyk: ostatnie wykonanie i suma okna.
    public struct StatisticRow: Sendable, Hashable, Identifiable {
        public var name: String
        public var last: Double
        public var total: Double
        public var id: String { name }
    }

    /// Statystyki do pokazania (PD-OPT-004): wybrane w Preferencjach (puste — wszystkie niezerowe), z filtrem tekstu;
    /// wybrane statystyki są pokazywane także z zerem ostatniego wykonania, jeśli mają sumę.
    public nonisolated static func rows(last: [SessionStatistic], totals: [String: Double], selected: [String], filter: String = "") -> [StatisticRow] {
        let lastMap = Dictionary(last.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
        let chosen = Set(selected.map { $0.lowercased() })
        let names: [String] = chosen.isEmpty ? last.map(\.name) : Array(Set(lastMap.keys).union(totals.keys)).filter { chosen.contains($0.lowercased()) }
        return names
            .filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }
            .map { StatisticRow(name: $0, last: lastMap[$0] ?? 0, total: totals[$0] ?? lastMap[$0] ?? 0) }
            .sorted { $0.last != $1.last ? $0.last > $1.last : $0.name < $1.name }
    }

    /// Eksport statystyk do CSV (nazwa, ostatnie, suma).
    public nonisolated static func csv(_ rows: [StatisticRow]) -> String {
        func num(_ d: Double) -> String { d.rounded() == d ? String(format: "%.0f", d) : String(d) }
        return (["\"statystyka\",\"ostatnie\",\"suma\""] + rows.map { "\"\($0.name.replacingOccurrences(of: "\"", with: "\"\""))\",\(num($0.last)),\(num($0.total))" })
            .joined(separator: "\n") + "\n"
    }

    /// Różnica migawek — niezerowe statystyki, malejąco.
    static func difference(_ before: [String: Double], _ after: [String: Double]) -> [SessionStatistic] {
        after.compactMap { k, v in
            let d = v - (before[k] ?? 0)
            return d != 0 ? SessionStatistic(name: k, value: d) : nil
        }.sorted { $0.value > $1.value }
    }
}
