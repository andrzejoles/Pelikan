import Foundation
import PelikanDB
import PelikanSQL

/// Rodzaj obiektu DBMS_SCHEDULER w drzewie (UG 10, PD-SCHED-001).
public enum SchedulerObjectKind: String, Sendable, CaseIterable, Codable {
    case windows, windowGroups, jobClasses, schedules, programs, chains, jobs, fileWatchers, credentials

    public var displayName: String {
        switch self {
        case .windows: L10n.tr("Okna")
        case .windowGroups: L10n.tr("Grupy okien")
        case .jobClasses: L10n.tr("Klasy zadań")
        case .schedules: L10n.tr("Harmonogramy")
        case .programs: L10n.tr("Programy")
        case .chains: L10n.tr("Łańcuchy")
        case .jobs: L10n.tr("Zadania")
        case .fileWatchers: L10n.tr("Obserwatory plików")
        case .credentials: L10n.tr("Poświadczenia")
        }
    }

    /// Zapytanie listy: właściciel (pusty dla obiektów systemowych), nazwa, stan, opis.
    var query: String {
        switch self {
        case .windows: "select 'SYS', window_name, enabled, nvl(repeat_interval, schedule_name), comments from all_scheduler_windows"
        // Opis liczby w języku interfejsu jako literał SQL (forma „Okna: n” bez odmiany liczebnika).
        case .windowGroups: "select 'SYS', window_group_name, enabled, \(ResultExporter.quote(L10n.tr("Okna") + ": ")) || number_of_windows, comments from all_scheduler_window_groups"
        case .jobClasses: "select 'SYS', job_class_name, resource_consumer_group, logging_level, comments from all_scheduler_job_classes"
        case .schedules: "select owner, schedule_name, schedule_type, nvl(repeat_interval, to_char(start_date)), comments from all_scheduler_schedules"
        case .programs: "select owner, program_name, enabled, program_type || ': ' || substr(program_action, 1, 200), comments from all_scheduler_programs"
        case .chains: "select owner, chain_name, enabled, \(ResultExporter.quote(L10n.tr("Kroki") + ": ")) || number_of_steps, comments from all_scheduler_chains"
        case .jobs: "select owner, job_name, state, nvl(repeat_interval, schedule_name), comments from all_scheduler_jobs"
        case .fileWatchers: "select owner, file_watcher_name, enabled, directory_path || '/' || file_name, comments from all_scheduler_file_watchers"
        // Poświadczenia: tylko nazwa i użytkownik (bez hasła — słownik go i tak nie pokazuje).
        case .credentials: "select owner, credential_name, enabled, username, comments from all_credentials"
        }
    }
}

/// Wiersz drzewa schedulera.
public struct SchedulerObject: Sendable, Hashable, Identifiable {
    public var kind: SchedulerObjectKind
    public var owner: String
    public var name: String
    public var state: String
    public var detail: String
    public var comments: String
    public var id: String { "\(kind.rawValue):\(owner).\(name)" }
}

/// Definicja zadania (UG 10.1): harmonogram wbudowany albo nazwany, powiadomienia e-mail.
public struct SchedulerJob: Sendable, Hashable, Codable {
    public enum JobType: String, Sendable, Codable, CaseIterable { case plsqlBlock = "PLSQL_BLOCK", storedProcedure = "STORED_PROCEDURE", program = "PROGRAM" }
    public var owner: String?
    public var name: String
    public var type: JobType = .plsqlBlock
    /// Blok PL/SQL, nazwa procedury albo nazwa programu.
    public var action: String
    public var scheduleName: String?
    public var startDate: Date?
    public var repeatInterval: String?
    public var endDate: Date?
    public var jobClass: String?
    public var enabled = true
    public var autoDrop = false
    public var comments = ""
    public var emailRecipients: [String] = []
    public var emailEvents: [String] = ["JOB_FAILED"]

    public init(name: String, action: String) { self.name = name; self.action = action }

    public var qualifiedName: String { (owner.map { "\($0)." } ?? "") + name }
}

/// DBMS_SCHEDULER (UG 10, PD-SCHED-001..003).
public enum Scheduler {
    nonisolated static func literal(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    nonisolated static func timestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "to_timestamp_tz('\(f.string(from: d)) UTC', 'YYYY-MM-DD HH24:MI:SS TZR')"
    }

    public static func objects(_ kind: SchedulerObjectKind, in s: any DatabaseSession) async throws -> [SchedulerObject] {
        let (_, rows) = try await s.queryAll(kind.query + " order by 1, 2", limit: 20_000)
        return rows.map {
            SchedulerObject(kind: kind, owner: $0[0].displayText ?? "", name: $0[1].displayText ?? "", state: $0[2].displayText ?? "",
                            detail: $0[3].displayText ?? "", comments: $0[4].displayText ?? "")
        }
    }

    /// SQL tworzący zadanie (View SQL): create_job + powiadomienie e-mail.
    public nonisolated static func createSQL(_ j: SchedulerJob) -> String {
        var args = ["job_name => \(literal(j.qualifiedName))"]
        if j.type == .program {
            args.append("program_name => \(literal(j.action))")
        } else {
            args.append("job_type => \(literal(j.type.rawValue))")
            args.append("job_action => \(literal(j.action))")
        }
        if let n = j.scheduleName, !n.isEmpty {
            args.append("schedule_name => \(literal(n))")
        } else {
            if let d = j.startDate { args.append("start_date => \(timestamp(d))") }
            if let r = j.repeatInterval, !r.isEmpty { args.append("repeat_interval => \(literal(r))") }
            if let d = j.endDate { args.append("end_date => \(timestamp(d))") }
        }
        if let c = j.jobClass, !c.isEmpty { args.append("job_class => \(literal(c))") }
        args.append("enabled => \(j.enabled ? "true" : "false")")
        args.append("auto_drop => \(j.autoDrop ? "true" : "false")")
        if !j.comments.isEmpty { args.append("comments => \(literal(j.comments))") }
        var sql = "begin\n  dbms_scheduler.create_job(\n    " + args.joined(separator: ",\n    ") + ");\n"
        sql += emailSQL(j)
        return sql + "end;"
    }

    nonisolated static func emailSQL(_ j: SchedulerJob) -> String {
        guard !j.emailRecipients.isEmpty else { return "" }
        return "  dbms_scheduler.add_job_email_notification(job_name => \(literal(j.qualifiedName)), recipients => \(literal(j.emailRecipients.joined(separator: ","))), events => \(literal(j.emailEvents.joined(separator: ","))));\n"
    }

    /// SQL zmiany zadania: `set_attribute` dla zmienionych atrybutów (edycja w miejscu, UG 10.2).
    public nonisolated static func alterSQL(from old: SchedulerJob, to new: SchedulerJob) -> String {
        var calls: [String] = []
        let n = literal(new.qualifiedName)
        func set(_ attr: String, _ value: String) { calls.append("  dbms_scheduler.set_attribute(\(n), \(literal(attr)), \(value));") }
        if old.action != new.action { set(new.type == .program ? "program_name" : "job_action", literal(new.action)) }
        if old.type != new.type, new.type != .program { set("job_type", literal(new.type.rawValue)) }
        if old.scheduleName != new.scheduleName, let s = new.scheduleName, !s.isEmpty { set("schedule_name", literal(s)) }
        if old.repeatInterval != new.repeatInterval, let r = new.repeatInterval { set("repeat_interval", literal(r)) }
        if old.startDate != new.startDate, let d = new.startDate { set("start_date", timestamp(d)) }
        if old.endDate != new.endDate, let d = new.endDate { set("end_date", timestamp(d)) }
        if old.jobClass != new.jobClass, let c = new.jobClass { set("job_class", literal(c)) }
        if old.autoDrop != new.autoDrop { set("auto_drop", new.autoDrop ? "true" : "false") }
        if old.comments != new.comments { set("comments", literal(new.comments)) }
        if old.enabled != new.enabled { calls.append("  dbms_scheduler.\(new.enabled ? "enable" : "disable")(\(n));") }
        if old.emailRecipients != new.emailRecipients || old.emailEvents != new.emailEvents {
            if !old.emailRecipients.isEmpty {
                calls.append("  dbms_scheduler.remove_job_email_notification(job_name => \(n), recipients => \(literal(old.emailRecipients.joined(separator: ","))));")
            }
            let e = emailSQL(new)
            if !e.isEmpty { calls.append(String(e.dropLast())) }
        }
        return calls.isEmpty ? "" : "begin\n" + calls.joined(separator: "\n") + "\nend;"
    }

    public nonisolated static func dropSQL(_ kind: SchedulerObjectKind, owner: String, name: String, force: Bool) -> String {
        let n = literal(owner.isEmpty || owner == "SYS" ? name : "\(owner).\(name)")
        let proc: String = switch kind {
        case .jobs: "drop_job(\(n), force => \(force ? "true" : "false"))"
        case .schedules: "drop_schedule(\(n), force => \(force ? "true" : "false"))"
        case .programs: "drop_program(\(n), force => \(force ? "true" : "false"))"
        case .chains: "drop_chain(\(n), force => \(force ? "true" : "false"))"
        case .windows: "drop_window(\(n), force => \(force ? "true" : "false"))"
        case .windowGroups: "drop_group(\(n), force => \(force ? "true" : "false"))"
        case .jobClasses: "drop_job_class(\(n), force => \(force ? "true" : "false"))"
        case .fileWatchers: "drop_file_watcher(\(n), force => \(force ? "true" : "false"))"
        case .credentials: "drop_credential(\(n), force => \(force ? "true" : "false"))"
        }
        return "begin dbms_scheduler.\(proc); end;"
    }

    /// Zadanie ze słownika (do edycji).
    public static func job(owner: String, name: String, in s: any DatabaseSession) async throws -> SchedulerJob {
        let (_, rows) = try await s.queryAll("""
            select job_type, nvl(job_action, program_name), schedule_name, repeat_interval, job_class, enabled, auto_drop, comments,
                   to_char(start_date at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS'), to_char(end_date at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS')
              from all_scheduler_jobs where owner = :o and job_name = :n
            """, binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(name))], limit: 1)
        guard let r = rows.first else { throw CommandError.notAvailable(L10n.tr("Nie znaleziono zadania \(owner).\(name)")) }
        var j = SchedulerJob(name: name, action: r[1].displayText ?? "")
        j.owner = owner
        j.type = r[0].displayText.flatMap(SchedulerJob.JobType.init(rawValue:)) ?? (r[2].displayText == nil ? .plsqlBlock : .program)
        j.scheduleName = r[2].displayText
        j.repeatInterval = r[3].displayText
        j.jobClass = r[4].displayText == "DEFAULT_JOB_CLASS" ? nil : r[4].displayText
        j.enabled = r[5].displayText == "TRUE"
        j.autoDrop = r[6].displayText == "TRUE"
        j.comments = r[7].displayText ?? ""
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        j.startDate = r[8].displayText.flatMap(f.date(from:))
        j.endDate = r[9].displayText.flatMap(f.date(from:))
        let (_, mails) = try await s.queryAll("select recipient, event from all_scheduler_notifications where owner = :o and job_name = :n",
                                              binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(name))], limit: 200)
        j.emailRecipients = Array(Set(mails.compactMap { $0[0].displayText })).sorted()
        if !mails.isEmpty { j.emailEvents = Array(Set(mails.compactMap { $0[1].displayText })).sorted() }
        return j
    }

    /// DDL obiektu schedulera (View SQL dla obiektów spoza zadań).
    public static func ddl(owner: String, name: String, in s: any DatabaseSession) async throws -> String {
        let r = try await s.execute("""
            declare begin
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
              :ddl := dbms_metadata.get_ddl('PROCOBJ', :n, :o);
            end;
            """, binds: [BindVariable(name: "ddl", type: .clob, direction: .output), BindVariable(name: "n", value: .text(name)), BindVariable(name: "o", value: .text(owner))])
        guard case .lob(let l)? = r.outBinds["ddl"], let text = l.text else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Przebiegi (UG 10.4–10.5)

    /// Raport przebiegów: nazwa i warunek WHERE dla ALL_SCHEDULER_JOB_RUN_DETAILS, reguły kolorów (kolumna = wartość → kolor).
    public struct RunReport: Sendable, Codable, Hashable, Identifiable {
        public struct ColorRule: Sendable, Codable, Hashable {
            public var column: String
            public var value: String
            public var color: RGBColor
            public init(column: String, value: String, color: RGBColor) { self.column = column; self.value = value; self.color = color }
        }
        public var name: String
        public var condition: String
        public var colors: [ColorRule]
        public var id: String { name }
        public init(name: String, condition: String, colors: [ColorRule] = []) { self.name = name; self.condition = condition; self.colors = colors }

        public static var standard: [RunReport] {
            let failed = ColorRule(column: "STATUS", value: "FAILED", color: RGBColor(red: 0.85, green: 0.2, blue: 0.2))
            return [
                RunReport(name: L10n.tr("Wszystkie"), condition: "", colors: [failed]),
                RunReport(name: L10n.tr("Nieudane"), condition: "status <> 'SUCCEEDED'", colors: [failed]),
                RunReport(name: L10n.tr("Ostatnie 24 godziny"), condition: "log_date > systimestamp - interval '1' day", colors: [failed]),
            ]
        }
    }

    public static func runs(_ report: RunReport, job: String? = nil, in s: any DatabaseSession) async throws -> (columns: [String], rows: [[String]]) {
        let condition = report.condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !condition.contains(";") else { throw CommandError.invalidArgument("condition", L10n.tr("warunek bez średnika")) }
        var parts: [String] = []
        if !condition.isEmpty { parts.append("(\(condition))") }
        if job != nil { parts.append("job_name = :j") }
        let (cols, rows) = try await s.queryAll("""
            select log_id, owner, job_name, status, to_char(actual_start_date, 'YYYY-MM-DD HH24:MI:SS') actual_start_date,
                   to_char(run_duration) run_duration, error#, substr(additional_info, 1, 400) additional_info
              from all_scheduler_job_run_details \(parts.isEmpty ? "" : "where " + parts.joined(separator: " and ")) order by log_id desc
            """, binds: job.map { [BindVariable(name: "j", value: .text($0))] } ?? [], limit: 5000)
        return (cols.map(\.name), rows.map { $0.map { $0.displayText ?? "" } })
    }

    public static func running(in s: any DatabaseSession) async throws -> (columns: [String], rows: [[String]]) {
        let (cols, rows) = try await s.queryAll("""
            select owner, job_name, session_id, running_instance, to_char(elapsed_time) elapsed_time, cpu_used from all_scheduler_running_jobs order by 1, 2
            """, limit: 1000)
        return (cols.map(\.name), rows.map { $0.map { $0.displayText ?? "" } })
    }

    public nonisolated static func stopSQL(owner: String, name: String, force: Bool) -> String {
        "begin dbms_scheduler.stop_job(\(literal("\(owner).\(name)")), force => \(force ? "true" : "false")); end;"
    }

    /// Uruchomienie zadania w osobnej sesji (nazwa jako literał z podwojonymi apostrofami).
    public nonisolated static func runSQL(owner: String, name: String) -> String {
        "begin dbms_scheduler.run_job(\(literal("\(owner).\(name)")), use_current_session => false); end;"
    }
}

/// Komendy schedulera.
@MainActor
public enum SchedulerCommands {
    public static func session(_ ws: Workspace) async throws -> (UUID, any DatabaseSession) {
        guard let conn = ws.activeDocument.flatMap({ ws.effectiveConnection(of: $0) }) ?? ws.sessions.mainConnectionID else { throw CommandError.notConnected }
        return (conn, try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("scheduler"))))
    }

    /// Wykonuje polecenie schedulera po strażniku zmian (prod — potwierdzenie, tylko do odczytu — blokada).
    public static func execute(_ sql: String, in ws: Workspace) async throws {
        let (conn, s) = try await session(ws)
        try await ws.guardModification([sql], connectionID: conn)
        _ = try await s.execute(sql)
    }

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "tools.scheduler", title: L10n.tr("DBMS Scheduler"), category: .tools,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Obiekty DBMS_SCHEDULER (okna, klasy, harmonogramy, programy, łańcuchy, zadania…), tworzenie i edycja zadań, View SQL, przebiegi i uruchomione zadania."),
                                      feature: "PD-SCHED-001"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                ctx.ui?.showScheduler()
                return .ok
            },
        ]
    }
}
