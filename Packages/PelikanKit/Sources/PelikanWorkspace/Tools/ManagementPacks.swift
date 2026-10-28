import Foundation
import PelikanDB

/// Licencja pakietów zarządzania Oracle zadeklarowana przez użytkownika dla połączenia (SD-LIC-001).
public enum ManagementPackLicense: String, Sendable, Codable, CaseIterable {
    case none, diagnostics, diagnosticsAndTuning

    public var displayName: String {
        switch self {
        case .none: L10n.tr("Brak licencji pakietów")
        case .diagnostics: L10n.tr("Diagnostics Pack")
        case .diagnosticsAndTuning: L10n.tr("Diagnostics i Tuning Pack")
        }
    }

    func covers(_ need: ManagementPacks.Need) -> Bool {
        switch (self, need) {
        case (.diagnosticsAndTuning, _): true
        case (.diagnostics, .diagnostics): true
        default: false
        }
    }
}

/// Funkcje wymagające Diagnostics Pack (AWR, ASH, ADDM) albo Tuning Pack (SQL Monitor, SQL Tuning Advisor):
/// deklaracja licencji na połączeniu (pytanie przy pierwszym użyciu, zapamiętane) i parametr bazy
/// CONTROL_MANAGEMENT_PACK_ACCESS (D63). Agent nie ma do nich dostępu (PROMPT §7.3).
public enum ManagementPacks {
    public enum Need: Sendable { case diagnostics, tuning }

    /// Ocena bez pytania: wartość parametru bazy (NONE / DIAGNOSTIC / DIAGNOSTIC+TUNING) i deklaracja.
    public static func evaluate(parameter: String?, declared: ManagementPackLicense?, need: Need) -> Result<Void, CommandError>? {
        let p = (parameter ?? "").uppercased()
        if p == "NONE" { return .failure(.notAvailable(L10n.tr("Pakiety zarządzania są wyłączone w bazie (CONTROL_MANAGEMENT_PACK_ACCESS = NONE)"))) }
        if need == .tuning, p == "DIAGNOSTIC" {
            return .failure(.notAvailable(L10n.tr("Tuning Pack jest wyłączony w bazie (CONTROL_MANAGEMENT_PACK_ACCESS = DIAGNOSTIC)")))
        }
        guard let declared else { return nil }      // trzeba zapytać użytkownika
        return declared.covers(need) ? .success(())
            : .failure(.notAvailable(L10n.tr("Połączenie ma zadeklarowane: \(declared.displayName) — ta funkcja wymaga \(need == .tuning ? "Tuning Pack" : "Diagnostics Pack")")))
    }

    /// Sprawdzenie przed funkcją pakietu; przy braku deklaracji pyta użytkownika i zapamiętuje odpowiedź w połączeniu.
    @MainActor
    public static func require(_ need: Need, connection id: UUID, session s: any DatabaseSession, in ws: Workspace, invoker: Invoker) async throws {
        guard !invoker.isAgent else { throw AgentDenial.permissionDenied(L10n.tr("funkcje Diagnostics/Tuning Pack są niedostępne dla agenta")) }
        guard var def = ws.connections.connection(id) else { throw CommandError.notConnected }
        let parameter = try? await s.scalar("select value from v$parameter where name = 'control_management_pack_access'")
        if let r = evaluate(parameter: parameter, declared: def.managementPacks, need: need) { return try r.get() }
        let choice = await ws.ui?.ask(L10n.tr("Licencja Oracle \(need == .tuning ? "Tuning Pack" : "Diagnostics Pack")"),
                                      message: L10n.tr("Ta funkcja korzysta z płatnego pakietu Oracle (\(need == .tuning ? "Tuning Pack, wymaga też Diagnostics Pack" : "Diagnostics Pack")). Używaj jej tylko, jeśli baza „\(def.displayName)” ma taką licencję. Odpowiedź zostanie zapamiętana dla połączenia."),
                                      buttons: [L10n.tr("Diagnostics i Tuning Pack"), L10n.tr("Tylko Diagnostics Pack"), L10n.tr("Brak licencji"), L10n.tr("Anuluj")])
        let declared: ManagementPackLicense
        switch choice {
        case 0: declared = .diagnosticsAndTuning
        case 1: declared = .diagnostics
        case 2: declared = .none
        default: throw CommandError.cancelledByUser
        }
        def.managementPacks = declared
        try ws.connections.upsert(def)
        if let r = evaluate(parameter: parameter, declared: declared, need: need) { try r.get() }
    }

    // MARK: Raporty

    /// Dwa ostatnie migawki AWR bieżącej instancji (początek, koniec) albo nil, gdy jest ich mniej niż dwie.
    public static func lastSnapshots(in s: any DatabaseSession) async throws -> (dbid: String, instance: String, begin: String, end: String)? {
        // W PDB migawki mają DBID kontenera (CON_DBID), nie CDB z V$DATABASE.
        let rows: [[OracleValue]]
        do {
            rows = try await s.queryAll("""
                select dbid, instance_number, snap_id from (
                  select dbid, instance_number, snap_id from dba_hist_snapshot
                   where dbid = to_number(sys_context('userenv', 'con_dbid')) and instance_number = (select instance_number from v$instance)
                   order by snap_id desc fetch first 2 rows only) order by snap_id
                """, limit: 2).1
        } catch let e as OracleError where [942, 1031].contains(e.code) {
            // Uprawnienie do pakietu bez dostępu do słownika (np. tylko rola OEM_MONITOR) — komunikat zamiast ORA-00942.
            throw CommandError.notAvailable(L10n.tr("Odczyt migawek AWR wymaga uprawnienia do widoków DBA_HIST_SNAPSHOT i V$INSTANCE (zwykle przez rolę DBA albo SELECT_CATALOG_ROLE). Administrator bazy może je nadać: GRANT SELECT_CATALOG_ROLE TO \(grantee(s.info.sessionUser));"))
        }
        guard rows.count == 2 else { return nil }
        return (rows[0][0].displayText ?? "", rows[0][1].displayText ?? "", rows[0][2].displayText ?? "", rows[1][2].displayText ?? "")
    }

    static func joined(_ s: any DatabaseSession, _ sql: String, _ binds: [BindVariable]) async throws -> String {
        let (_, rows) = try await s.queryAll(sql, binds: binds, limit: 1_000_000)
        return rows.map { $0.first?.displayText ?? "" }.joined(separator: "\n")
    }

    /// Uprawnienie EXECUTE do pakietu SYS (zgłoszenia #113, #114): bez niego Oracle odpowiada w SQL mylącym
    /// ORA-00904 „invalid identifier”. Pakiet SYS jest w ALL_OBJECTS tylko z uprawnieniem (wprost, przez rolę, PUBLIC).
    static func requireExecute(_ package: String, in s: any DatabaseSession, report: String) async throws {
        let n = try await s.scalar("select count(*) from all_objects where owner = 'SYS' and object_name = :p and object_type = 'PACKAGE'",
                                   binds: [BindVariable(name: "p", value: .text(package))])
        guard n == "0" else { return }
        let user = grantee(s.info.sessionUser)
        throw CommandError.notAvailable(L10n.tr("\(report) wymaga uprawnienia EXECUTE do pakietu \(package) (zwykle przez rolę DBA) i licencji Oracle Diagnostics Pack. Administrator bazy może je nadać: GRANT EXECUTE ON SYS.\(package) TO \(user);"))
    }

    /// Użytkownik w poleceniu GRANT: nazwa zwykła bez cudzysłowów, inna (małe litery, spacje, znaki spoza
    /// `A–Z 0–9 _ $ #`) w cudzysłowach; nieznana — zamiennik do uzupełnienia.
    static func grantee(_ user: String) -> String {
        guard !user.isEmpty else { return L10n.tr("<użytkownik>") }
        if user.range(of: "^[A-Z][A-Z0-9_$#]*$", options: .regularExpression) != nil { return user }
        return "\"" + user.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// ADDM analizuje migawki repozytorium AWR: potrzebny DBMS_WORKLOAD_REPOSITORY (DBMS_ADDM bywa nadany PUBLIC,
    /// więc sam nie wystarcza do oceny) i DBMS_ADDM.
    static func requireADDM(_ s: any DatabaseSession) async throws {
        try await requireExecute("DBMS_WORKLOAD_REPOSITORY", in: s, report: L10n.tr("Raport ADDM"))
        try await requireExecute("DBMS_ADDM", in: s, report: L10n.tr("Raport ADDM"))
    }

    /// Raport AWR (HTML) między migawkami.
    public static func awrReport(_ s: any DatabaseSession, dbid: String, instance: String, begin: String, end: String) async throws -> String {
        try await requireExecute("DBMS_WORKLOAD_REPOSITORY", in: s, report: L10n.tr("Raport AWR"))
        return try await joined(s, "select output from table(dbms_workload_repository.awr_report_html(:d, :i, :b, :e))",
                         [num("d", dbid), num("i", instance), num("b", begin), num("e", end)])
    }

    /// Raport ASH (HTML) z ostatnich `minutes` minut.
    public static func ashReport(_ s: any DatabaseSession, minutes: Int) async throws -> String {
        try await requireExecute("DBMS_WORKLOAD_REPOSITORY", in: s, report: L10n.tr("Raport ASH"))
        return try await joined(s, """
            select output from table(dbms_workload_repository.ash_report_html(
              to_number(sys_context('userenv', 'con_dbid')), (select instance_number from v$instance), sysdate - :m / 1440, sysdate))
            """, [num("m", String(minutes))])
    }

    /// Raport ADDM dla przedziału migawek (zadanie doradcy tworzone i usuwane).
    public static func addmReport(_ s: any DatabaseSession, begin: String, end: String) async throws -> String {
        try await requireADDM(s)
        let task = "PELIKAN_ADDM_\(UUID().uuidString.prefix(8))"
        // Sprzątanie także po błędzie analizy (zadanie mogło już powstać).
        defer { Task { _ = try? await s.execute("begin dbms_addm.delete(:t); end;", binds: [BindVariable(name: "t", value: .text(task))]) } }
        _ = try await s.execute("begin dbms_addm.analyze_db(:t, :b, :e); end;", binds: [BindVariable(name: "t", value: .text(task)), num("b", begin), num("e", end)])
        let r = try await s.execute("begin :r := dbms_addm.get_report(:t); end;", binds: [BindVariable(name: "r", type: .clob, direction: .output), BindVariable(name: "t", value: .text(task))],
                                    options: ExecuteOptions(lobLimit: 50_000_000))
        if case .lob(let l)? = r.outBinds["r"] { return l.text ?? "" }
        return ""
    }

    /// Monitorowane zapytania (V$SQL_MONITOR) i raport SQL Monitor (HTML) dla SQL_ID.
    public static func monitoredSQL(_ s: any DatabaseSession) async throws -> (columns: [String], rows: [[String]]) {
        let (cols, rows) = try await s.queryAll("""
            select sql_id, status, username, to_char(sql_exec_start, 'YYYY-MM-DD HH24:MI:SS') sql_exec_start,
                   round(elapsed_time / 1e6, 2) elapsed_s, round(cpu_time / 1e6, 2) cpu_s, buffer_gets, substr(sql_text, 1, 200) sql_text
              from v$sql_monitor order by sql_exec_start desc fetch first 200 rows only
            """, limit: 200)
        return (cols.map(\.name), rows.map { $0.map { $0.displayText ?? "" } })
    }

    public static func sqlMonitorReport(_ s: any DatabaseSession, sqlID: String) async throws -> String {
        let r = try await s.execute("begin :r := dbms_sql_monitor.report_sql_monitor(sql_id => :id, type => 'HTML', report_level => 'ALL'); end;",
                                    binds: [BindVariable(name: "r", type: .clob, direction: .output), BindVariable(name: "id", value: .text(sqlID))],
                                    options: ExecuteOptions(lobLimit: 50_000_000))
        if case .lob(let l)? = r.outBinds["r"] { return l.text ?? "" }
        return ""
    }

    /// SQL Tuning Advisor dla tekstu polecenia: zadanie, wykonanie (limit czasu), raport tekstowy; zadanie usuwane.
    public static func tuningReport(_ s: any DatabaseSession, sql: String, timeLimitSeconds: Int = 60) async throws -> String {
        let task = "PELIKAN_TUNE_\(UUID().uuidString.prefix(8))"
        // Sprzątanie także po błędzie wykonania (zadanie utworzone przez create_tuning_task).
        defer { Task { _ = try? await s.execute("begin dbms_sqltune.drop_tuning_task(:t); end;", binds: [BindVariable(name: "t", value: .text(task))]) } }
        _ = try await s.execute("""
            declare t varchar2(128); begin
              t := dbms_sqltune.create_tuning_task(sql_text => :s, time_limit => :l, task_name => :t, description => 'Pelikan');
              dbms_sqltune.execute_tuning_task(task_name => :t);
            end;
            """, binds: [BindVariable(name: "s", type: .clob, value: .text(sql)), num("l", String(timeLimitSeconds)), BindVariable(name: "t", value: .text(task))])
        let r = try await s.execute("begin :r := dbms_sqltune.report_tuning_task(:t); end;",
                                    binds: [BindVariable(name: "r", type: .clob, direction: .output), BindVariable(name: "t", value: .text(task))],
                                    options: ExecuteOptions(lobLimit: 50_000_000))
        if case .lob(let l)? = r.outBinds["r"] { return l.text ?? "" }
        return ""
    }

    static func num(_ name: String, _ v: String) -> BindVariable { BindVariable(name: name, type: .number, value: .text(v)) }
}

/// Komendy pakietów zarządzania (agent: Brak — PROMPT §7.3).
@MainActor
enum PackCommands {
    static func session(_ ctx: CommandContext) async throws -> (UUID, any DatabaseSession) {
        let conn = try ctx.toolConnection()
        return (conn, try await ctx.workspace.toolSession("packs", connection: conn))
    }

    static func html(_ title: String, _ text: String) -> String {
        "<html><head><meta charset=\"utf-8\"><title>\(title)</title></head><body><pre style=\"font: 12px Menlo, monospace\">"
            + text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") + "</pre></body></html>"
    }

    static func report(_ id: CommandID, _ title: String, _ summary: String, _ feature: String, need: ManagementPacks.Need,
                       params: [CommandParameter] = [], body: @escaping @MainActor @Sendable (CommandContext, any DatabaseSession) async throws -> String) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: .tools, submenu: L10n.tr("Wydajność (pakiety Oracle)"), parameters: params,
                                  agent: .none, effect: .none, summary: summary, feature: feature),
                validate: { $0.sessions.mainConnectionID != nil }) { ctx in
            let (conn, s) = try await session(ctx)
            try await ManagementPacks.require(need, connection: conn, session: s, in: ctx.workspace, invoker: ctx.invoker)
            let html = try await body(ctx, s)
            ctx.ui?.showHTMLReport(title: title, html: html)
            return CommandResult(value: .string(html))
        }
    }

    static var all: [Command] {
        [
            report("tools.awrReport", L10n.tr("Raport AWR"), L10n.tr("Raport AWR (HTML) między dwiema ostatnimi migawkami albo wskazanymi; wymaga Diagnostics Pack."), "SD-DBA-002",
                   need: .diagnostics, params: [CommandParameter("begin", .integer, L10n.tr("Migawka początkowa")), CommandParameter("end", .integer, L10n.tr("Migawka końcowa"))]) { ctx, s in
                // Uprawnienie przed migawkami: bez niego DBA_HIST_SNAPSHOT kończy się ORA-00942 zamiast komunikatu z GRANT.
                try await ManagementPacks.requireExecute("DBMS_WORKLOAD_REPOSITORY", in: s, report: L10n.tr("Raport AWR"))
                guard let snaps = try await ManagementPacks.lastSnapshots(in: s) else {
                    throw CommandError.notAvailable(L10n.tr("W repozytorium AWR są mniej niż dwie migawki tej bazy"))
                }
                let b = ctx.arguments.int("begin").map(String.init) ?? snaps.begin, e = ctx.arguments.int("end").map(String.init) ?? snaps.end
                return try await ManagementPacks.awrReport(s, dbid: snaps.dbid, instance: snaps.instance, begin: b, end: e)
            },
            report("tools.ashReport", L10n.tr("Raport ASH"), L10n.tr("Raport ASH (HTML) z ostatnich minut; wymaga Diagnostics Pack."), "SD-DBA-002",
                   need: .diagnostics, params: [CommandParameter("minutes", .integer, L10n.tr("Ostatnie minuty (domyślnie 30)"))]) { ctx, s in
                try await ManagementPacks.ashReport(s, minutes: Int(ctx.arguments.int("minutes") ?? 30))
            },
            report("tools.addmReport", L10n.tr("Raport ADDM"), L10n.tr("Analiza ADDM dwóch ostatnich migawek AWR; wymaga Diagnostics Pack."), "SD-DBA-002", need: .diagnostics) { _, s in
                try await ManagementPacks.requireADDM(s)
                guard let snaps = try await ManagementPacks.lastSnapshots(in: s) else {
                    throw CommandError.notAvailable(L10n.tr("W repozytorium AWR są mniej niż dwie migawki tej bazy"))
                }
                return html("ADDM", try await ManagementPacks.addmReport(s, begin: snaps.begin, end: snaps.end))
            },
            report("tools.sqlMonitorReport", L10n.tr("Raport SQL Monitor"), L10n.tr("Raport Real-Time SQL Monitoring (HTML) dla SQL_ID; wymaga Tuning Pack."), "SD-MON-001",
                   need: .tuning, params: [CommandParameter("sqlId", .string, required: true, "SQL_ID"), CommandContext.toolConnectionParam]) { ctx, s in
                try await ManagementPacks.sqlMonitorReport(s, sqlID: ctx.arguments.string("sqlId") ?? "")
            },
            Command(CommandDescriptor(id: "tools.sqlMonitor", title: L10n.tr("SQL Monitor"), category: .tools, submenu: L10n.tr("Wydajność (pakiety Oracle)"),
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Lista monitorowanych zapytań (V$SQL_MONITOR) z raportem dla wybranego; wymaga Tuning Pack."),
                                      feature: "SD-MON-001"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                let (conn, s) = try await session(ctx)
                try await ManagementPacks.require(.tuning, connection: conn, session: s, in: ctx.workspace, invoker: ctx.invoker)
                // Okno pracuje na połączeniu, dla którego sprawdzono licencję (lista i raporty).
                ctx.ui?.showSQLMonitor(connection: conn)
                return .ok
            },
            report("tools.sqlTuningAdvisor", L10n.tr("SQL Tuning Advisor"), L10n.tr("Zalecenia SQL Tuning Advisor dla polecenia pod kursorem albo zaznaczenia; wymaga Tuning Pack."), "SD-DBA-003",
                   need: .tuning) { ctx, s in
                guard let doc = ctx.workspace.activeDocument, [.sql, .program, .test, .explainPlan].contains(doc.kind) else {
                    throw CommandError.notAvailable(L10n.tr("Ustaw kursor na poleceniu w oknie SQL"))
                }
                let sql = PlanCommands.statement(of: doc)
                guard !sql.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak polecenia")) }
                return html("SQL Tuning Advisor", try await ManagementPacks.tuningReport(s, sql: sql))
            },
        ]
    }
}
