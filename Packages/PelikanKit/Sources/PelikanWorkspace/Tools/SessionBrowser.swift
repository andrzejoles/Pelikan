import Foundation
import PelikanDB
import PelikanSQL

/// Definicje zapytań przeglądarki sesji (UG 16.2 „Define Session Queries”, PD-TOOL-016): filtry listy, karty
/// szczegółów (zapytania ze zmienną `:sid`, `:serial#`; komentarz `/* concatenate */` skleja wiersze jednej kolumny
/// w tekst) i akcje.
public struct SessionQueries: Sendable, Codable, Hashable {
    public struct Item: Sendable, Codable, Hashable, Identifiable {
        public var name: String
        public var sql: String
        public var id: String { name }
        public init(name: String, sql: String) { self.name = name; self.sql = sql }
    }

    /// Warunek WHERE dla V$SESSION (pusty — wszystkie).
    public var filters: [Item]
    public var details: [Item]
    /// Polecenia dla zaznaczonej sesji (zmienne `:sid`, `:serial#`).
    public var actions: [Item]

    public init(filters: [Item], details: [Item], actions: [Item]) {
        self.filters = filters; self.details = details; self.actions = actions
    }

    public static var standard: SessionQueries {
        SessionQueries(
            filters: [
                Item(name: L10n.tr("Wszystkie"), sql: ""),
                Item(name: L10n.tr("Sesje użytkowników"), sql: "type = 'USER'"),
                Item(name: L10n.tr("Aktywne"), sql: "type = 'USER' and status = 'ACTIVE'"),
                Item(name: L10n.tr("Moje sesje"), sql: "username = user"),
            ],
            details: [
                Item(name: L10n.tr("Bieżące SQL"), sql: "/* concatenate */ select t.sql_text from v$sqltext_with_newlines t join v$session s on s.sql_address = t.address and s.sql_hash_value = t.hash_value where s.sid = :sid order by t.piece"),
                Item(name: L10n.tr("Otwarte kursory"), sql: "select sql_id, sql_text, cursor_type from v$open_cursor where sid = :sid"),
                Item(name: L10n.tr("Blokady"), sql: "select type, id1, id2, lmode, request, ctime, block from v$lock where sid = :sid"),
                Item(name: L10n.tr("Statystyki"), sql: "select n.name, s.value from v$sesstat s join v$statname n on n.statistic# = s.statistic# where s.sid = :sid and s.value <> 0 order by n.name"),
                Item(name: L10n.tr("Oczekiwanie"), sql: "select event, wait_class, state, seconds_in_wait, p1text, p1, p2text, p2 from v$session_wait where sid = :sid"),
            ],
            actions: [
                Item(name: L10n.tr("Włącz SQL Trace"), sql: "begin dbms_monitor.session_trace_enable(session_id => :sid, serial_num => :serial#, waits => true, binds => false); end;"),
                Item(name: L10n.tr("Wyłącz SQL Trace"), sql: "begin dbms_monitor.session_trace_disable(session_id => :sid, serial_num => :serial#); end;"),
            ])
    }
}

/// Wiersz listy sesji.
public struct SessionRow: Sendable, Hashable, Identifiable {
    public var sid: Int
    public var serial: Int
    public var values: [String: String]
    public var id: String { "\(sid),\(serial)" }
}

/// Przeglądarka sesji (UG 16, PD-TOOL-015) w sesji narzędzi połączenia.
public enum SessionBrowser {
    /// Kolumny listy (V$SESSION) — bez danych logowania aplikacji; `osuser`/`machine` są dla administratora bazy.
    public static let columns = ["SID", "SERIAL#", "USERNAME", "STATUS", "OSUSER", "MACHINE", "PROGRAM", "MODULE", "ACTION", "CLIENT_INFO",
                                 "SQL_ID", "EVENT", "SECONDS_IN_WAIT", "LOGON_TIME", "TYPE"]

    public static func list(filter: String, in s: any DatabaseSession) async throws -> [SessionRow] {
        let condition = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        // Warunek pochodzi z definicji użytkownika — tylko wyrażenie WHERE, bez średników i kilku poleceń.
        guard !condition.contains(";") else { throw CommandError.invalidArgument("filter", L10n.tr("warunek filtra bez średnika")) }
        let (cols, rows) = try await s.queryAll("""
            select sid, serial#, username, status, osuser, machine, program, module, action, client_info, sql_id, event, seconds_in_wait,
                   to_char(logon_time, 'YYYY-MM-DD HH24:MI:SS') logon_time, type
              from v$session \(condition.isEmpty ? "" : "where " + condition) order by sid
            """, limit: 10_000)
        return rows.map { r in
            var v: [String: String] = [:]
            for (i, c) in cols.enumerated() { v[c.name.uppercased()] = r[i].displayText ?? "" }
            return SessionRow(sid: Int(v["SID"] ?? "") ?? 0, serial: Int(v["SERIAL#"] ?? "") ?? 0, values: v)
        }
    }

    /// Wynik karty szczegółów: kolumny i wiersze albo — dla `/* concatenate */` — jeden tekst.
    public struct Detail: Sendable {
        public var columns: [String]
        public var rows: [[String]]
        public var text: String?
    }

    public static func detail(_ item: SessionQueries.Item, sid: Int, serial: Int, in s: any DatabaseSession) async throws -> Detail {
        let (sql, binds) = bindSession(item.sql, sid: sid, serial: serial)
        let (cols, rows) = try await s.queryAll(sql, binds: binds, limit: 5000)
        let strings = rows.map { $0.map { $0.displayText ?? "" } }
        if item.sql.lowercased().contains("/* concatenate */") {
            return Detail(columns: cols.map(\.name), rows: [], text: strings.map { $0.first ?? "" }.joined())
        }
        return Detail(columns: cols.map(\.name), rows: strings, text: nil)
    }

    public static func perform(_ item: SessionQueries.Item, sid: Int, serial: Int, in s: any DatabaseSession) async throws {
        let (sql, binds) = bindSession(item.sql, sid: sid, serial: serial)
        _ = try await s.execute(sql, binds: binds)
    }

    /// `ALTER SYSTEM KILL SESSION 'sid,serial#' [IMMEDIATE]` (UG 16.1 Kill).
    public static func kill(sid: Int, serial: Int, immediate: Bool, in s: any DatabaseSession) async throws {
        _ = try await s.execute("alter system kill session '\(sid),\(serial)'\(immediate ? " immediate" : "")")
    }

    /// `:sid` i `:serial#` jako zmienne wiązane (nazwa `serial#` jest niedozwolona — zamiana na `:serial_`).
    nonisolated static func bindSession(_ sql: String, sid: Int, serial: Int) -> (String, [BindVariable]) {
        var text = sql.replacingOccurrences(of: ":serial#", with: ":serial_", options: .caseInsensitive)
        var binds: [BindVariable] = []
        let names = Set(Lexer(text).tokenize().filter { $0.kind == .bindVariable }.map { (text as NSString).substring(with: NSRange(location: $0.start + 1, length: $0.length - 1)).lowercased() })
        if names.contains("sid") { binds.append(BindVariable(name: "sid", type: .number, value: .text(String(sid)))) }
        if names.contains("serial_") { binds.append(BindVariable(name: "serial_", type: .number, value: .text(String(serial)))) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasSuffix("end;") { while text.hasSuffix(";") { text.removeLast() } }
        return (text, binds)
    }
}

/// Komendy przeglądarki sesji.
@MainActor
public enum SessionCommands {
    /// Połączenie przeglądarki sesji: aktywnego okna albo główne.
    static func toolConnection(_ ws: Workspace) throws -> UUID {
        guard let conn = ws.activeDocument.flatMap({ ws.effectiveConnection(of: $0) }) ?? ws.sessions.mainConnectionID else { throw CommandError.notConnected }
        return conn
    }

    public static func toolSession(_ ws: Workspace) async throws -> any DatabaseSession {
        try await ws.sessions.session(SessionKey(connectionID: try toolConnection(ws), purpose: .tool("sessions")))
    }

    static let sessionParams = [CommandParameter("sid", .integer, required: true, "SID"), CommandParameter("serial", .integer, required: true, "SERIAL#")]

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "tools.sessions", title: L10n.tr("Sesje"), category: .tools,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Przeglądarka sesji bazy: lista z filtrami, karty szczegółów, zabijanie sesji, SQL Trace, automatyczne odświeżanie."),
                                      feature: "PD-TOOL-015"),
                    validate: { $0.sessions.mainConnectionID != nil || $0.activeDocument?.connectionID != nil }) { ctx in
                ctx.ui?.showSessionBrowser()
                return .ok
            },
            Command(CommandDescriptor(id: "tools.exportUserObjects", title: L10n.tr("Eksport obiektów użytkownika…"), category: .tools,
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("DDL wybranych obiektów schematu do jednego pliku albo pliku na obiekt (sekwencje pierwsze, uprawnienia, składowanie, schemat)."),
                                      feature: "PD-TOOL-007"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                ctx.ui?.showExportObjects()
                return .ok
            },
            Command(CommandDescriptor(id: "tools.compareUserObjects", title: L10n.tr("Porównaj obiekty użytkowników…"), category: .tools,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Porównuje DDL obiektów schematu ze schematem docelowym (także na innym połączeniu); lista różnic, podgląd i SQL wyrównujący."),
                                      feature: "PD-TOOL-012"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                ctx.ui?.showCompareObjects()
                return .ok
            },
            Command(CommandDescriptor(id: "sessions.kill", title: L10n.tr("Zabij sesję"), category: .tools, submenu: L10n.tr("Sesje"),
                                      parameters: sessionParams + [CommandParameter("immediate", .boolean, L10n.tr("Natychmiast (IMMEDIATE)"))],
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("ALTER SYSTEM KILL SESSION dla zaznaczonej sesji (po potwierdzeniu)."), inMenu: false,
                                      feature: "PD-TOOL-015")) { ctx in
                guard let sid = ctx.arguments.int("sid"), let serial = ctx.arguments.int("serial") else { throw CommandError.missingArgument("sid, serial") }
                // Strażnik zmian jak w panelu DBA: tylko do odczytu blokuje, produkcja wymaga potwierdzenia.
                try await ctx.workspace.guardModification(["alter system kill session '\(sid),\(serial)'"], connectionID: try toolConnection(ctx.workspace))
                if let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Zabić sesję \(sid),\(serial)?"), message: L10n.tr("Niezatwierdzona transakcja tej sesji zostanie wycofana."),
                                       buttons: [L10n.tr("Zabij"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                try await SessionBrowser.kill(sid: Int(sid), serial: Int(serial), immediate: ctx.arguments.bool("immediate") ?? true, in: try await toolSession(ctx.workspace))
                return CommandResult(message: L10n.tr("Sesja \(sid),\(serial) zabita"))
            },
            Command(CommandDescriptor(id: "sessions.action", title: L10n.tr("Akcja sesji"), category: .tools, submenu: L10n.tr("Sesje"),
                                      parameters: sessionParams + [CommandParameter("action", .string, required: true, L10n.tr("Nazwa akcji z Preferencji › Sesje"))],
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Wykonuje akcję przeglądarki sesji (polecenie z Preferencji) dla zaznaczonej sesji przez strażnika zmian."),
                                      inMenu: false, feature: "PD-TOOL-015")) { ctx in
                guard let sid = ctx.arguments.int("sid"), let serial = ctx.arguments.int("serial") else { throw CommandError.missingArgument("sid, serial") }
                let name = ctx.arguments.string("action") ?? ""
                guard let item = ctx.workspace.settings.sessionQueries.actions.first(where: { $0.name == name }) else {
                    throw CommandError.invalidArgument("action", name)
                }
                try await ctx.workspace.guardModification([item.sql], connectionID: try toolConnection(ctx.workspace))
                try await SessionBrowser.perform(item, sid: Int(sid), serial: Int(serial), in: try await toolSession(ctx.workspace))
                return CommandResult(message: L10n.tr("Wykonano: \(item.name)"))
            },
        ]
    }
}
