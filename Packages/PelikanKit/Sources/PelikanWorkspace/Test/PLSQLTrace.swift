import Foundation
import PelikanDB

/// Ślad wykonania PL/SQL (DBMS_TRACE, PD-OPT-007): poziomy, zdarzenia przebiegu, historia przebiegów. Wymaga tabel
/// SYS.PLSQL_TRACE_RUNS/EVENTS (tracetab.sql) — bez nich Pelikan podaje, co zainstalować.
public enum PLSQLTrace {
    /// Poziomy (stałe DBMS_TRACE), łączone sumą.
    public struct Level: OptionSet, Sendable, Hashable, Codable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let allCalls = Level(rawValue: 1)
        public static let enabledCalls = Level(rawValue: 2)
        public static let allExceptions = Level(rawValue: 4)
        public static let enabledExceptions = Level(rawValue: 8)
        public static let allSQL = Level(rawValue: 32)
        public static let allLines = Level(rawValue: 128)
        public static let enabledLines = Level(rawValue: 256)
    }

    public struct Event: Sendable, Hashable, Identifiable {
        public var seq: Int
        public var kind: String
        public var unit: String
        public var line: Int
        public var comment: String
        public var id: Int { seq }
    }

    public struct Run: Sendable, Hashable, Identifiable {
        public var id: Int
        public var date: String
        public var comment: String
    }

    public static func isInstalled(_ s: any DatabaseSession) async -> Bool {
        (try? await s.scalar("select count(*) from plsql_trace_runs where 1 = 0")) != nil
    }

    public static func start(_ level: Level, in s: any DatabaseSession) async throws {
        guard await isInstalled(s) else {
            throw CommandError.notAvailable(L10n.tr("Brak tabel DBMS_TRACE — administrator instaluje je skryptem ?/rdbms/admin/tracetab.sql"))
        }
        _ = try await s.execute("begin dbms_trace.set_plsql_trace(:l); end;", binds: [BindVariable(name: "l", type: .number, value: .text(String(level.rawValue)))])
    }

    /// Kończy ślad i zwraca numer przebiegu i jego zdarzenia (bez zdarzeń samego włączania/wyłączania).
    public static func stop(in s: any DatabaseSession) async throws -> (run: Int, events: [Event]) {
        let run = Int(try await s.scalar("select dbms_trace.get_plsql_trace_runnumber from dual") ?? "0") ?? 0
        _ = try await s.execute("begin dbms_trace.clear_plsql_trace; end;")
        return (run, try await events(run: run, in: s))
    }

    public static func events(run: Int, in s: any DatabaseSession) async throws -> [Event] {
        let (_, rows) = try await s.queryAll("""
            select event_seq, event_kind, nvl(event_unit_owner || nvl2(event_unit_owner, '.', '') || event_unit, ' '), nvl(event_line, 0), nvl(event_comment, ' ')
              from plsql_trace_events where runid = :r and nvl(event_unit, ' ') <> 'DBMS_TRACE' order by event_seq
            """, binds: [BindVariable(name: "r", type: .number, value: .text(String(run)))], limit: 100_000)
        return rows.map { Event(seq: Int($0[0].format(.default)) ?? 0, kind: $0[1].displayText ?? "", unit: ($0[2].displayText ?? "").trimmingCharacters(in: .whitespaces),
                                line: Int($0[3].format(.default)) ?? 0, comment: ($0[4].displayText ?? "").trimmingCharacters(in: .whitespaces)) }
    }

    public static func runs(in s: any DatabaseSession, limit: Int = 50) async throws -> [Run] {
        let (_, rows) = try await s.queryAll("""
            select runid, to_char(run_date, 'YYYY-MM-DD HH24:MI:SS'), nvl(run_comment, ' ') from plsql_trace_runs order by runid desc fetch first :n rows only
            """, binds: [BindVariable(name: "n", type: .number, value: .text(String(limit)))], limit: limit)
        return rows.map { Run(id: Int($0[0].format(.default)) ?? 0, date: $0[1].displayText ?? "", comment: ($0[2].displayText ?? "").trimmingCharacters(in: .whitespaces)) }
    }
}
