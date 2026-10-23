import Foundation
import Observation
import PelikanDB
import PelikanSQL

/// Wynik sekcji panelu DBA: wiersze albo komunikat o braku uprawnień (zamiast błędu).
public enum DBASectionResult: Sendable {
    case rows(columns: [String], rows: [[String]])
    case noPrivilege(String)
    case failed(String)

    public var rows: [[String]] { if case .rows(_, let r) = self { r } else { [] } }
    public var columns: [String] { if case .rows(let c, _) = self { c } else { [] } }
}

/// Panel DBA (SD-DBA-001): przestrzenie tabel, pliki danych, parametry, użytkownicy, role, sesje i blokady — przeglądanie;
/// zmiany (parametr, blokada konta) tylko przez strażnika zmian po potwierdzeniu.
public enum DBAPanel {
    public enum Section: String, Sendable, CaseIterable, Identifiable {
        case tablespaces, dataFiles, parameters, users, roles, sessions, blocking
        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .tablespaces: L10n.tr("Przestrzenie tabel")
            case .dataFiles: L10n.tr("Pliki danych")
            case .parameters: L10n.tr("Parametry")
            case .users: L10n.tr("Użytkownicy")
            case .roles: L10n.tr("Role")
            case .sessions: L10n.tr("Sesje")
            case .blocking: L10n.tr("Blokady")
            }
        }

        var query: String {
            switch self {
            case .tablespaces: """
                select t.tablespace_name, t.status, t.contents, t.extent_management,
                       round(nvl(f.bytes, 0) / 1048576, 1) size_mb,
                       round((nvl(f.bytes, 0) - nvl(s.bytes, 0)) / 1048576, 1) used_mb,
                       round(nvl(s.bytes, 0) / 1048576, 1) free_mb,
                       case when nvl(f.bytes, 0) > 0 then round((f.bytes - nvl(s.bytes, 0)) * 100 / f.bytes, 1) end used_pct
                  from dba_tablespaces t
                  left join (select tablespace_name, sum(bytes) bytes from dba_data_files group by tablespace_name
                             union all select tablespace_name, sum(bytes) from dba_temp_files group by tablespace_name) f on f.tablespace_name = t.tablespace_name
                  left join (select tablespace_name, sum(bytes) bytes from dba_free_space group by tablespace_name) s on s.tablespace_name = t.tablespace_name
                 order by t.tablespace_name
                """
            case .dataFiles: """
                select file_name, tablespace_name, round(bytes / 1048576, 1) size_mb, autoextensible, round(maxbytes / 1048576, 1) max_mb, status
                  from dba_data_files
                union all
                select file_name, tablespace_name, round(bytes / 1048576, 1), autoextensible, round(maxbytes / 1048576, 1), status from dba_temp_files
                 order by 2, 1
                """
            case .parameters: "select name, value, isdefault, ismodified, issys_modifiable, description from v$parameter order by name"
            case .users: """
                select username, account_status, default_tablespace, temporary_tablespace, profile,
                       to_char(created, 'YYYY-MM-DD') created, to_char(last_login, 'YYYY-MM-DD HH24:MI') last_login, oracle_maintained
                  from dba_users order by username
                """
            case .roles: """
                select r.role, r.authentication_type, r.oracle_maintained, (select count(*) from dba_role_privs p where p.granted_role = r.role) grantees
                  from dba_roles r order by r.role
                """
            case .sessions: """
                select sid, serial#, username, status, osuser, machine, program, module, sql_id, event, blocking_session, to_char(logon_time, 'YYYY-MM-DD HH24:MI') logon_time
                  from v$session where type = 'USER' order by sid
                """
            case .blocking: """
                select w.sid waiting_sid, w.username waiting_user, w.event, w.seconds_in_wait, b.sid blocking_sid, b.username blocking_user, b.status blocking_status
                  from v$session w join v$session b on b.sid = w.blocking_session order by w.seconds_in_wait desc
                """
            }
        }
    }

    /// ORA-00942 (brak widoku) i ORA-01031 (brak uprawnień) — sekcja niedostępna dla użytkownika.
    nonisolated static func isPrivilegeError(_ e: any Error) -> Bool {
        if let o = e as? OracleError { return [942, 1031, 1039].contains(o.code) }
        return false
    }

    public static func load(_ section: Section, in s: any DatabaseSession) async -> DBASectionResult {
        do {
            let (cols, rows) = try await s.queryAll(section.query, limit: 50_000)
            return .rows(columns: cols.map(\.name), rows: rows.map { $0.map { $0.displayText ?? "" } })
        } catch {
            if isPrivilegeError(error) {
                return .noPrivilege(L10n.tr("Brak uprawnień do widoków słownika tej sekcji (potrzebne np. SELECT_CATALOG_ROLE)."))
            }
            return .failed(error.localizedDescription)
        }
    }

    nonisolated static func identifier(_ s: String) -> String? {
        s.range(of: #"^[A-Za-z][A-Za-z0-9_$#]{0,127}$"#, options: .regularExpression) != nil ? s.uppercased() : nil
    }

    /// `ALTER SYSTEM SET` (zakres MEMORY/SPFILE/BOTH) — wartość jako literał, gdy nie jest liczbą ani TRUE/FALSE.
    public static func alterParameterSQL(name: String, value: String, scope: String = "BOTH") throws -> String {
        guard let n = identifier(name) else { throw CommandError.invalidArgument("name", name) }
        guard ["MEMORY", "SPFILE", "BOTH"].contains(scope.uppercased()) else { throw CommandError.invalidArgument("scope", scope) }
        let v = value.trimmingCharacters(in: .whitespaces)
        let literal = Double(v) != nil || ["TRUE", "FALSE"].contains(v.uppercased()) || v.range(of: #"^[0-9]+[KMGT]$"#, options: .regularExpression) != nil
            ? v : "'" + v.replacingOccurrences(of: "'", with: "''") + "'"
        return "alter system set \(n.lowercased()) = \(literal) scope = \(scope.lowercased())"
    }

    public static func lockUserSQL(_ user: String, lock: Bool) throws -> String {
        guard let u = identifier(user) else { throw CommandError.invalidArgument("user", user) }
        return "alter user \(u) account \(lock ? "lock" : "unlock")"
    }

    /// Wykonanie zmiany przez strażnika zmian (tylko do odczytu — blokada, prod — potwierdzenie).
    @MainActor
    public static func execute(_ sql: String, connectionID: UUID, in ws: Workspace) async throws {
        try await ws.guardModification([sql], connectionID: connectionID)
        let s = try await ws.sessions.session(SessionKey(connectionID: connectionID, purpose: .tool("dba")))
        _ = try await s.execute(sql)
    }
}

// MARK: Instance Viewer (SD-DBA-004)

public struct InstanceSnapshot: Sendable {
    public struct WaitClass: Sendable, Hashable, Identifiable {
        public var name: String
        /// Czas oczekiwania w sekundach (od startu instancji) i przyrost od poprzedniej migawki na sekundę.
        public var seconds: Double
        public var rate: Double?
        public var id: String { name }
    }
    public struct TopSQL: Sendable, Hashable, Identifiable {
        public var sqlID: String
        public var executions: Int64
        public var elapsedSeconds: Double
        public var cpuSeconds: Double
        public var bufferGets: Int64
        public var text: String
        public var id: String { sqlID }
    }
    public var taken = Date()
    public var version: String?
    public var instanceName: String?
    public var status: String?
    public var startup: Date?
    public var databaseRole: String?
    public var logMode: String?
    public var sessionsTotal: Int?
    public var sessionsActive: Int?
    public var waitClasses: [WaitClass] = []
    public var topSQL: [TopSQL] = []
    /// SGA wg puli i PGA (MB).
    public var sga: [(String, Double)] = []
    public var pgaAllocatedMB: Double?
    public var pgaTargetMB: Double?
    /// Części niedostępne (brak uprawnień) — pokazywane jako komunikaty.
    public var unavailable: [String] = []

    public var uptime: TimeInterval? { startup.map { taken.timeIntervalSince($0) } }
}

public enum InstanceViewer {
    public static func snapshot(in s: any DatabaseSession, previous: InstanceSnapshot? = nil) async -> InstanceSnapshot {
        var snap = InstanceSnapshot()
        func part(_ name: String, _ body: () async throws -> Void) async {
            do { try await body() } catch { snap.unavailable.append("\(name): \(DBAPanel.isPrivilegeError(error) ? L10n.tr("brak uprawnień") : error.localizedDescription)") }
        }
        await part(L10n.tr("Instancja")) {
            let (_, r) = try await s.queryAll("""
                select i.instance_name, i.status, to_char(i.startup_time, 'YYYY-MM-DD"T"HH24:MI:SS'), d.database_role, d.log_mode,
                       (select banner_full from v$version where rownum = 1)
                  from v$instance i cross join v$database d
                """, limit: 1)
            if let x = r.first {
                snap.instanceName = x[0].displayText; snap.status = x[1].displayText
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                snap.startup = x[2].displayText.flatMap(f.date(from:))
                snap.databaseRole = x[3].displayText; snap.logMode = x[4].displayText; snap.version = x[5].displayText
            }
        }
        await part(L10n.tr("Sesje")) {
            let (_, r) = try await s.queryAll("select count(*), sum(case when status = 'ACTIVE' then 1 else 0 end) from v$session where type = 'USER'", limit: 1)
            snap.sessionsTotal = r.first.flatMap { Int($0[0].displayText ?? "") }
            snap.sessionsActive = r.first.flatMap { Int($0[1].displayText ?? "") }
        }
        await part(L10n.tr("Oczekiwania")) {
            let (_, r) = try await s.queryAll("select wait_class, time_waited / 100 from v$system_wait_class where wait_class <> 'Idle' order by 2 desc", limit: 50)
            let dt = previous.map { snap.taken.timeIntervalSince($0.taken) }
            snap.waitClasses = r.map { x in
                let name = x[0].displayText ?? ""
                let secs = Double(x[1].displayText ?? "") ?? 0
                let prev = previous?.waitClasses.first { $0.name == name }?.seconds
                return .init(name: name, seconds: secs, rate: (prev != nil && (dt ?? 0) > 0) ? (secs - prev!) / dt! : nil)
            }
        }
        await part("Top SQL") {
            let (_, r) = try await s.queryAll("""
                select sql_id, executions, elapsed_time / 1e6, cpu_time / 1e6, buffer_gets, substr(sql_text, 1, 200)
                  from v$sql where executions > 0 order by elapsed_time desc fetch first 10 rows only
                """, limit: 10)
            snap.topSQL = r.map { x in
                .init(sqlID: x[0].displayText ?? "", executions: Int64(x[1].displayText ?? "") ?? 0, elapsedSeconds: Double(x[2].displayText ?? "") ?? 0,
                      cpuSeconds: Double(x[3].displayText ?? "") ?? 0, bufferGets: Int64(x[4].displayText ?? "") ?? 0, text: x[5].displayText ?? "")
            }
        }
        await part("SGA/PGA") {
            let (_, r) = try await s.queryAll("select nvl(pool, name), round(sum(bytes) / 1048576, 1) from v$sgastat group by nvl(pool, name) order by 2 desc", limit: 50)
            snap.sga = r.map { ($0[0].displayText ?? "", Double($0[1].displayText ?? "") ?? 0) }
            let (_, p) = try await s.queryAll("""
                select name, round(value / 1048576, 1) from v$pgastat where name in ('total PGA allocated', 'aggregate PGA target parameter')
                """, limit: 5)
            for x in p {
                let v = Double(x[1].displayText ?? "")
                if x[0].displayText == "total PGA allocated" { snap.pgaAllocatedMB = v } else { snap.pgaTargetMB = v }
            }
        }
        return snap
    }
}

// MARK: Task Monitor (SD-MON-002)

/// Zadanie w tle aplikacji: tytuł, rodzaj, stan, czasy, anulowanie.
@MainActor
@Observable
public final class WorkspaceTask: Identifiable {
    public enum Status: Sendable, Equatable { case running, succeeded, failed(String), cancelled }
    public let id = UUID()
    public let title: String
    public let kind: String
    public let started = Date()
    public internal(set) var finished: Date?
    public internal(set) var status: Status = .running
    /// Postęp 0…1 (nil — nieokreślony) i komunikat bieżący.
    public var progress: Double?
    public var message: String?
    @ObservationIgnored var task: Task<Void, Never>?

    init(title: String, kind: String) { self.title = title; self.kind = kind }

    public var duration: TimeInterval { (finished ?? Date()).timeIntervalSince(started) }
    public var isRunning: Bool { status == .running }

    public func cancel() {
        guard isRunning else { return }
        task?.cancel()
        status = .cancelled
        finished = Date()
    }
}

/// Lista zadań w tle (wspólna dla długich operacji: eksporty, testy, importy, dokumentacja).
@MainActor
@Observable
public final class WorkspaceTaskCenter {
    public private(set) var tasks: [WorkspaceTask] = []

    public init() {}

    /// Uruchamia operację jako zadanie w tle; operacja dostaje zadanie (postęp, komunikat) i powinna sprawdzać
    /// `Task.isCancelled`. Zwraca zadanie od razu.
    @discardableResult
    public func run(_ title: String, kind: String, _ operation: @escaping @MainActor (WorkspaceTask) async throws -> Void) -> WorkspaceTask {
        let t = WorkspaceTask(title: title, kind: kind)
        tasks.insert(t, at: 0)
        if tasks.count > 200 { tasks.removeLast(tasks.count - 200) }
        t.task = Task { @MainActor in
            do {
                try await operation(t)
                if t.status == .running { t.status = Task.isCancelled ? .cancelled : .succeeded }
            } catch is CancellationError {
                t.status = .cancelled
            } catch {
                if t.status == .running { t.status = .failed(error.localizedDescription) }
            }
            if t.finished == nil { t.finished = Date() }
        }
        return t
    }

    /// Czeka na zakończenie zadania (testy, tryb wsadowy).
    public func wait(_ t: WorkspaceTask) async { await t.task?.value }

    public func clearFinished() { tasks.removeAll { !$0.isRunning } }
}

// MARK: Dokumentacja schematu (SD-DOC-001)

public enum SchemaDoc {
    nonisolated static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    nonisolated static func fileName(_ type: String, _ name: String) -> String {
        let safe = name.lowercased().map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" }
        return type.lowercased().replacingOccurrences(of: " ", with: "_") + "-" + String(safe) + ".html"
    }

    static let css = """
        body{font:14px -apple-system,Helvetica,Arial,sans-serif;margin:24px;color:#222}h1{font-size:22px}h2{font-size:17px;margin-top:24px}
        table{border-collapse:collapse;margin:8px 0}th,td{border:1px solid #ccc;padding:3px 8px;text-align:left;vertical-align:top}
        th{background:#f2f2f2}code,pre{font:12px Menlo,monospace}pre{background:#f7f7f7;padding:8px;overflow:auto}a{color:#0a58ca}
        .meta{color:#666}@media (prefers-color-scheme:dark){body{background:#1e1e1e;color:#ddd}th{background:#333}td,th{border-color:#555}pre{background:#2a2a2a}a{color:#7ab0ff}}
        """

    nonisolated static func page(_ title: String, _ body: String) -> String {
        "<!doctype html><html lang=\"pl\"><head><meta charset=\"utf-8\"><title>\(esc(title))</title><link rel=\"stylesheet\" href=\"styl.css\"></head><body>\(body)</body></html>\n"
    }

    nonisolated static func table(_ header: [String], _ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "<p class=\"meta\">—</p>" }
        return "<table><tr>" + header.map { "<th>\(esc($0))</th>" }.joined() + "</tr>"
            + rows.map { "<tr>" + $0.map { "<td>\(esc($0))</td>" }.joined() + "</tr>" }.joined() + "</table>"
    }

    /// Generuje strony HTML schematu do katalogu: index, tabele (kolumny, komentarze, klucze, indeksy), widoki (kolumny,
    /// tekst), programy (parametry; opcjonalnie źródło), sekwencje. Zwraca liczbę zapisanych plików.
    public static func generate(owner: String, into dir: URL, includeSource: Bool, in s: any DatabaseSession,
                                progress: (@MainActor (String) -> Void)? = nil) async throws -> Int {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try css.write(to: dir.appendingPathComponent("styl.css"), atomically: true, encoding: .utf8)
        let o = BindVariable(name: "o", value: .text(owner))
        let (_, objs) = try await s.queryAll("""
            select object_name, object_type from all_objects
             where owner = :o and object_type in ('TABLE','VIEW','PACKAGE','PROCEDURE','FUNCTION','TYPE','SEQUENCE','TRIGGER','MATERIALIZED VIEW')
               and object_name not like 'BIN$%' order by object_type, object_name
            """, binds: [o], limit: 100_000)
        var written = 1
        var index = "<h1>" + esc(L10n.tr("Schemat \(owner)")) + "</h1><p class=\"meta\">" + esc(L10n.tr("Wygenerowane przez Pelikana")) + " — "
            + esc(ISO8601DateFormatter().string(from: Date())) + "</p>"
        var byType: [String: [String]] = [:]
        for r in objs { byType[r[1].displayText ?? "", default: []].append(r[0].displayText ?? "") }
        for type in byType.keys.sorted() {
            index += "<h2>\(esc(type)) (\(byType[type]!.count))</h2><ul>"
            for name in byType[type]! {
                if Task.isCancelled { throw CancellationError() }
                await progress?("\(type) \(name)")
                let b = [o, BindVariable(name: "n", value: .text(name))]
                var body = "<p><a href=\"index.html\">" + esc(L10n.tr("Spis")) + "</a></p><h1>\(esc(type)) \(esc(owner)).\(esc(name))</h1>"
                switch type {
                case "TABLE", "VIEW", "MATERIALIZED VIEW":
                    let comment = try await s.scalar("select comments from all_tab_comments where owner = :o and table_name = :n", binds: b)
                    if let c = comment, !c.isEmpty { body += "<p>\(esc(c))</p>" }
                    let (_, cols) = try await s.queryAll("""
                        select c.column_name, c.data_type || case when c.data_type in ('VARCHAR2','NVARCHAR2','CHAR','NCHAR','RAW') then '(' || c.data_length || ')'
                                when c.data_type = 'NUMBER' and c.data_precision is not null then '(' || c.data_precision || nvl2(c.data_scale, ',' || c.data_scale, '') || ')' end,
                               c.nullable, m.comments
                          from all_tab_columns c left join all_col_comments m on m.owner = c.owner and m.table_name = c.table_name and m.column_name = c.column_name
                         where c.owner = :o and c.table_name = :n order by c.column_id
                        """, binds: b, limit: 2000)
                    body += "<h2>" + esc(L10n.tr("Kolumny")) + "</h2>" + table([L10n.tr("Kolumna"), L10n.tr("Typ"), "Null", L10n.tr("Komentarz")],
                                                                           cols.map { $0.map { $0.displayText ?? "" } })
                    if type != "VIEW" {
                        let (_, cons) = try await s.queryAll("""
                            select c.constraint_name, decode(c.constraint_type, 'P', 'PRIMARY KEY', 'U', 'UNIQUE', 'R', 'FOREIGN KEY', 'C', 'CHECK', c.constraint_type),
                                   (select listagg(column_name, ', ') within group (order by position) from all_cons_columns k where k.owner = c.owner and k.constraint_name = c.constraint_name),
                                   nvl2(c.r_constraint_name, (select r.table_name from all_constraints r where r.owner = c.r_owner and r.constraint_name = c.r_constraint_name), '')
                              from all_constraints c where c.owner = :o and c.table_name = :n and c.constraint_type in ('P','U','R','C') and c.constraint_name not like 'SYS_C%' order by 2, 1
                            """, binds: b, limit: 500)
                        body += "<h2>" + esc(L10n.tr("Ograniczenia")) + "</h2>" + table([L10n.tr("Nazwa"), L10n.tr("Typ"), L10n.tr("Kolumny"), L10n.tr("Tabela nadrzędna")],
                                                                                   cons.map { $0.map { $0.displayText ?? "" } })
                        let (_, idx) = try await s.queryAll("""
                            select i.index_name, i.uniqueness, (select listagg(column_name, ', ') within group (order by column_position) from all_ind_columns k where k.index_owner = i.owner and k.index_name = i.index_name)
                              from all_indexes i where i.table_owner = :o and i.table_name = :n order by 1
                            """, binds: b, limit: 500)
                        body += "<h2>" + esc(L10n.tr("Indeksy")) + "</h2>" + table([L10n.tr("Nazwa"), L10n.tr("Unikalność"), L10n.tr("Kolumny")], idx.map { $0.map { $0.displayText ?? "" } })
                    } else if let text = try? await MetadataProvider.ddl(of: DBObject(owner: owner, name: name, type: .view), in: s) {
                        body += "<h2>" + esc(L10n.tr("Definicja")) + "</h2><pre>\(esc(text))</pre>"
                    }
                case "PACKAGE", "PROCEDURE", "FUNCTION", "TYPE":
                    let (_, args) = try await s.queryAll("""
                        select nvl2(package_name, object_name, ''), overload, nvl(argument_name, '(wynik)'), in_out, nvl(type_name, data_type)
                          from all_arguments where owner = :o and data_level = 0 and (package_name = :n or package_name is null and object_name = :n)
                         order by object_name, overload, position
                        """, binds: b, limit: 5000)
                    body += "<h2>" + esc(L10n.tr("Parametry")) + "</h2>" + table([L10n.tr("Podprogram"), L10n.tr("Przeciążenie"), L10n.tr("Parametr"), L10n.tr("Kierunek"), L10n.tr("Typ")],
                                                                             args.map { $0.map { $0.displayText ?? "" } })
                    if includeSource, let src = try? await MetadataProvider.source(of: DBObject(owner: owner, name: name, type: DBObjectType(rawValue: type) ?? .package), in: s) {
                        var all = src
                        if type == "PACKAGE" || type == "TYPE",
                           let b = try? await MetadataProvider.source(of: DBObject(owner: owner, name: name, type: type == "PACKAGE" ? .packageBody : .typeBody), in: s) {
                            all += "\n/\n\n" + b
                        }
                        body += "<h2>" + esc(L10n.tr("Źródło")) + "</h2><pre>\(esc(all))</pre>"
                    }
                case "SEQUENCE":
                    let (_, sq) = try await s.queryAll("select min_value, max_value, increment_by, cycle_flag, cache_size from all_sequences where sequence_owner = :o and sequence_name = :n", binds: b, limit: 1)
                    body += table(["MIN", "MAX", L10n.tr("Krok"), L10n.tr("Cykl"), "Cache"], sq.map { $0.map { $0.displayText ?? "" } })
                default:
                    if includeSource, let src = try? await MetadataProvider.source(of: DBObject(owner: owner, name: name, type: DBObjectType(rawValue: type) ?? .trigger), in: s) {
                        body += "<pre>\(esc(src))</pre>"
                    }
                }
                let file = fileName(type, name)
                try page("\(owner).\(name)", body).write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
                written += 1
                index += "<li><a href=\"\(file)\">\(esc(name))</a></li>"
            }
            index += "</ul>"
        }
        try page(L10n.tr("Schemat \(owner)"), index).write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        return written
    }
}
