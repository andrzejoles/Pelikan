import Foundation
import PelikanDB

/// Wskazane zapytanie (D217): SQL_ID albo hash, skąd pochodzi (opis dla okna) i tekst polecenia, gdy SQL_ID policzono
/// z tekstu edytora.
public struct SQLReportTarget: Sendable, Hashable {
    public var target: SQLIdentity.Target
    public var origin: String
    public var statement: String?
    public var connection: UUID?
    /// Raport zaznaczony po otwarciu okna i czy uruchomić go od razu (makra, skrypty zrzutów).
    public var report: String?
    public var runReport = false

    public init(target: SQLIdentity.Target, origin: String, statement: String? = nil, connection: UUID? = nil) {
        self.target = target; self.origin = origin; self.statement = statement; self.connection = connection
    }

    public var label: String {
        switch target {
        case .sqlID(let s): "SQL_ID \(s)"
        case .hash(let h): "HASH_VALUE \(h)"
        }
    }
}

/// Zapytanie z bieżącego zaznaczenia (D217): wiersz albo komórka siatki, zaznaczony tekst, słowo pod kursorem, polecenie
/// pod kursorem (SQL_ID liczony z tekstu).
@MainActor
public enum SQLTargetFinder {
    /// Siatka wyniku: komórka bieżąca, gdy zawiera SQL_ID/hash (w kolumnie SQL_ID/hash albo wygląda jak SQL_ID), inaczej
    /// kolumna SQL_ID (potem hash) zaznaczonego wiersza.
    public static func fromGrid(_ tab: ResultTab) -> SQLReportTarget? {
        fromGrid(tab, row: tab.selectedRows?.first, column: tab.currentColumn)
    }

    /// Cel z podanego wiersza i kolumny siatki (menu kontekstowe: wiersz spod kursora, nie pierwszy zaznaczony).
    public static func fromGrid(_ tab: ResultTab, row: Int?, column: Int?) -> SQLReportTarget? {
        guard let grid = tab.grid, let row, row >= 0, row < grid.rowCount else { return nil }
        let names = grid.columns.map(\.name)
        let values = grid.columns.indices.map { grid.value(row: row, column: $0).format(grid.format) }
        if let c = column, c >= 0, c < values.count, let t = SQLIdentity.parse(values[c]) {
            let kind = SQLIdentity.columnKind(names[c])
            if case .sqlID = t { return SQLReportTarget(target: t, origin: L10n.tr("komórka \(names[c]) wiersza \(row + 1)")) }
            if kind == .hash { return SQLReportTarget(target: t, origin: L10n.tr("komórka \(names[c]) wiersza \(row + 1)")) }
        }
        guard let t = SQLIdentity.target(columns: names, values: values) else { return nil }
        return SQLReportTarget(target: t, origin: L10n.tr("wiersz \(row + 1) siatki wyniku"))
    }

    /// Edytor: zaznaczony SQL_ID albo hash, słowo pod kursorem (SQL_ID), inaczej SQL_ID polecenia pod kursorem.
    public static func fromEditor(_ doc: Document, statement: Bool = true) -> SQLReportTarget? {
        let ns = doc.text as NSString
        let sel = doc.selectedRange
        if !sel.isEmpty, sel.upperBound <= ns.length, sel.count <= 40,
           let t = SQLIdentity.parse(ns.substring(with: NSRange(location: sel.lowerBound, length: sel.count))) {
            return SQLReportTarget(target: t, origin: L10n.tr("zaznaczenie w edytorze"))
        }
        if let w = OracleDocs.word(at: sel.lowerBound, in: doc.text), let t = SQLIdentity.parse(w.word), case .sqlID = t {
            return SQLReportTarget(target: t, origin: L10n.tr("słowo pod kursorem"))
        }
        guard statement, [.sql, .program, .test, .explainPlan].contains(doc.kind) else { return nil }
        let text = PlanCommands.statement(of: doc).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SQLReportTarget(target: .sqlID(SQLIdentity.sqlID(text: text)), origin: L10n.tr("polecenie pod kursorem (SQL_ID policzony z tekstu)"), statement: text)
    }

    /// Aktywne okno: zaznaczony wiersz siatki, potem edytor.
    public static func fromWorkspace(_ ws: Workspace) -> SQLReportTarget? {
        guard let doc = ws.activeDocument else { return nil }
        if doc.kind == .sql, let tab = doc.results.first(where: { $0.id == doc.activeResultID }) ?? doc.results.first, let t = fromGrid(tab) {
            return t
        }
        return fromEditor(doc)
    }
}

/// Zapytanie z elementu z fokusem (UIServices.focusedSQLTarget).
public enum FocusedSQL: Sendable {
    case target(SQLReportTarget)
    /// Fokus w tabeli z kolumną SQL_ID/hash, bez zaznaczonego zapytania.
    case tableWithoutTarget
    case noTarget
}

extension ManagementPacks {
    /// Licencje połączenia dla okna raportów (D217): deklaracja (pytanie przy pierwszym użyciu, gdy `ask`) i parametr
    /// CONTROL_MANAGEMENT_PACK_ACCESS. Raporty bez licencji działają zawsze.
    @MainActor
    public static func license(connection id: UUID, session s: any DatabaseSession, in ws: Workspace, invoker: Invoker, ask: Bool) async throws -> PerfLicense {
        guard !invoker.isAgent else { throw AgentDenial.permissionDenied(L10n.tr("funkcje Diagnostics/Tuning Pack są niedostępne dla agenta")) }
        guard var def = ws.connections.connection(id) else { throw CommandError.notConnected }
        let parameter = try? await s.scalar("select value from v$parameter where name = 'control_management_pack_access'")
        if def.managementPacks == nil, ask {
            let choice = await ws.ui?.ask(L10n.tr("Licencje Oracle dla połączenia „\(def.displayName)”"),
                                          message: L10n.tr("Część raportów korzysta z płatnych pakietów Oracle: Diagnostics Pack (AWR, ASH, ADDM, Performance Hub) i Tuning Pack (SQL Monitor, SQL Detail, SQL Tuning Advisor). Pelikan pokaże tylko raporty objęte licencją bazy. Odpowiedź zostanie zapamiętana dla połączenia (zmiana w definicji połączenia)."),
                                          buttons: [L10n.tr("Diagnostics i Tuning Pack"), L10n.tr("Tylko Diagnostics Pack"), L10n.tr("Brak licencji"), L10n.tr("Anuluj")])
            switch choice {
            case 0: def.managementPacks = .diagnosticsAndTuning
            case 1: def.managementPacks = .diagnostics
            case 2: def.managementPacks = ManagementPackLicense.none
            default: throw CommandError.cancelledByUser
            }
            try ws.connections.upsert(def)
        }
        func ok(_ need: Need) -> (Bool, String?) {
            guard let r = evaluate(parameter: parameter, declared: def.managementPacks, need: need) else { return (false, nil) }
            switch r {
            case .success: return (true, nil)
            case .failure(let e): return (false, e.localizedDescription)
            }
        }
        let d = ok(.diagnostics), t = ok(.tuning)
        return PerfLicense(diagnostics: d.0, tuning: t.0 && d.0, note: d.1 ?? t.1)
    }

    /// Migawki AWR bieżącej bazy i instancji (DBA_HIST_SNAPSHOT jest poza Diagnostics Pack), najnowsze na końcu.
    public static func snapshots(in s: any DatabaseSession, limit: Int = 500) async throws -> [(id: Int, begin: String, end: String, instance: Int)] {
        let major = s.info.server.major > 0 ? s.info.server.major : 19
        let rows = try await s.queryAll("""
            select snap_id, to_char(begin_interval_time, 'YYYY-MM-DD HH24:MI:SS'), to_char(end_interval_time, 'YYYY-MM-DD HH24:MI:SS'), instance_number
              from (select * from dba_hist_snapshot where dbid = \(SQLProbe.dbid(major)) and instance_number = (select instance_number from v$instance)
                    order by snap_id desc) where rownum <= \(limit)
            """, limit: limit).1
        return rows.reversed().map { r in
            (Int(r[0].displayText ?? "") ?? 0, r[1].displayText ?? "", r[2].displayText ?? "", Int(r[3].displayText ?? "") ?? 1)
        }
    }
}

/// Komendy raportów wydajności (D217; agent: Brak — pakiety zarządzania, PROMPT §7.3).
@MainActor
enum PerfCommands {
    static let sqlParams: [CommandParameter] = [
        CommandParameter("sqlId", .string, L10n.tr("SQL_ID (domyślnie z zaznaczonego wiersza, komórki albo polecenia pod kursorem)")),
        CommandParameter("hash", .integer, L10n.tr("HASH_VALUE zapytania (zamiast SQL_ID)")),
        CommandParameter("report", .string, L10n.tr("Raport do zaznaczenia (np. sql.monitor)")),
        CommandParameter("run", .boolean, L10n.tr("Uruchom zaznaczony raport od razu (wartości domyślne)")),
        CommandContext.toolConnectionParam,
    ]

    /// Zapytanie z argumentów, zaznaczonego elementu z fokusem (interfejs) albo aktywnego okna; inaczej pytanie.
    static func target(_ ctx: CommandContext) async throws -> SQLReportTarget {
        if let s = ctx.arguments.string("sqlId"), !s.isEmpty {
            guard let t = SQLIdentity.parse(s), case .sqlID = t else { throw CommandError.invalidArgument("sqlId", s) }
            return SQLReportTarget(target: t, origin: L10n.tr("parametr komendy"))
        }
        if let h = ctx.arguments.int("hash") {
            guard h > 0, h <= Int64(UInt32.max) else { throw CommandError.invalidArgument("hash", String(h)) }
            return SQLReportTarget(target: .hash(UInt32(h)), origin: L10n.tr("parametr komendy"))
        }
        switch ctx.ui?.focusedSQLTarget() ?? .noTarget {
        case .target(let t): return t
        // Fokus w tabeli z kolumną SQL bez zaznaczonego zapytania — pytanie, nie polecenie z edytora w tle.
        case .tableWithoutTarget: break
        case .noTarget: if let t = SQLTargetFinder.fromWorkspace(ctx.workspace) { return t }
        }
        guard let ui = ctx.ui, let raw = await ui.askText(L10n.tr("Raporty dla SQL"), message: L10n.tr("SQL_ID albo HASH_VALUE zapytania"), defaultValue: "") else {
            throw CommandError.cancelledByUser
        }
        guard let t = SQLIdentity.parse(raw) else { throw CommandError.invalidArgument("sqlId", raw) }
        return SQLReportTarget(target: t, origin: L10n.tr("wpisany"))
    }

    static var all: [Command] {
        var out: [Command] = [
            Command(CommandDescriptor(id: "perf.sqlReports", title: L10n.tr("Raporty dla SQL_ID…"), category: .performance,
                                      mac: ["cmd+ctrl+r"], parameters: sqlParams, agent: .none, effect: .none,
                                      summary: L10n.tr("Wszystkie raporty dla zapytania z zaznaczonego wiersza, komórki albo polecenia pod kursorem: plany, SQL Monitor, SQL Detail, Performance Hub, AWR, ASH, bindy, doradcy — ze sprawdzeniem, gdzie zapytanie jest dostępne."),
                                      feature: "PD-PERF-001"),
                    validate: { $0.toolConnection() != nil }) { ctx in
                let t = try await target(ctx)
                var tt = t
                tt.connection = try t.connection ?? ctx.toolConnection()
                tt.report = ctx.arguments.string("report")
                tt.runReport = ctx.arguments.bool("run") ?? false
                ctx.ui?.showSQLReports(tt)
                return .ok
            },
        ]
        for r in PerfReportCatalog.globalReports {
            out.append(Command(CommandDescriptor(id: CommandID(rawValue: r.id), title: r.title + "…", category: .performance, submenu: r.group,
                                                 parameters: [CommandContext.toolConnectionParam], agent: .none, effect: .none,
                                                 summary: r.summary + " (" + r.need.displayName + ")", feature: "PD-PERF-002"),
                               validate: { $0.toolConnection() != nil }) { ctx in
                ctx.ui?.showPerfReport(r.id, connection: try ctx.toolConnection())
                return .ok
            })
        }
        out.append(Command(CommandDescriptor(id: "perf.reports", title: L10n.tr("Wszystkie raporty wydajności…"), category: .performance,
                                             parameters: [CommandContext.toolConnectionParam], agent: .none, effect: .none,
                                             summary: L10n.tr("Okno raportów wydajności bazy (AWR, ASH, ADDM, Performance Hub, SQL Monitor, statystyki) z wyborem parametrów i formatu."),
                                             feature: "PD-PERF-002"),
                           validate: { $0.toolConnection() != nil }) { ctx in
            ctx.ui?.showPerfReport(nil, connection: try ctx.toolConnection())
            return .ok
        })
        return out
    }
}
