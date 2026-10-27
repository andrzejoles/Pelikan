import Foundation
import PelikanDB

/// Komendy Etapu 7 (plany, DBA, zadania w tle, dokumentacja).
@MainActor
enum Stage7PlanCommands {
    static func connection(_ ws: Workspace) -> UUID? { ws.toolConnection() }

    static func toolSession(_ ws: Workspace, _ name: String) async throws -> any DatabaseSession {
        try await ws.toolSession(name, connection: ws.toolConnection())
    }

    static var all: [Command] {
        let connected: @MainActor (Workspace) -> Bool = { connection($0) != nil }
        return [
            Command(CommandDescriptor(id: "tools.autotrace", title: L10n.tr("Autotrace"), category: .tools,
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Wykonuje zaznaczenie albo polecenie pod kursorem z pomiarem planu rzeczywistego (A-Rows, E-Rows, czasy, bufory) i statystykami sesji; DML jest wycofywane."),
                                      feature: "SD-PLAN-002"),
                    validate: { ws in ws.activeDocument.map { [.sql, .program, .test, .explainPlan].contains($0.kind) } ?? false }) { ctx in
                let ws = ctx.workspace
                guard let doc = ws.activeDocument, let conn = ws.effectiveConnection(of: doc) else { throw CommandError.notConnected }
                let sql = PlanCommands.statement(of: doc)
                guard !sql.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak polecenia")) }
                try await ws.guardModification([sql], connectionID: conn)
                let s = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("autotrace")))
                var result: AutotraceResult?
                let task = ws.tasks.run(L10n.tr("Autotrace"), kind: "autotrace") { _ in result = try await Autotrace.run(sql, in: s) }
                await ws.tasks.wait(task)
                if case .failed(let m) = task.status { throw CommandError.notAvailable(m) }
                guard let r = result else { throw CommandError.cancelledByUser }
                ctx.ui?.showAutotrace(r, sql: sql)
                return CommandResult(message: L10n.tr("Wierszy: \(r.rowsFetched), czas \(String(format: "%.3f", r.elapsedSeconds)) s"), value: .string(r.planText))
            },
            Command(CommandDescriptor(id: "plan.compare", title: L10n.tr("Porównaj z poprzednim planem"), category: .tools, submenu: L10n.tr("Plan"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Porównuje bieżący plan okna z poprzednim (albo z planem drugiego okna planu): operacje, koszty, kardynalność, kolejność."),
                                      feature: "SD-PLAN-003"),
                    validate: { ws in
                        guard let d = ws.activeDocument, d.plan != nil else { return false }
                        return d.previousPlan != nil || ws.documents.filter { $0.kind == .explainPlan && $0.plan != nil }.count >= 2
                    }) { ctx in
                let ws = ctx.workspace
                guard let doc = ws.activeDocument, let current = doc.plan else { return .ok }
                let other: ExplainPlanResult
                let leftTitle: String
                if let prev = doc.previousPlan {
                    other = prev
                    leftTitle = L10n.tr("Poprzedni plan")
                } else if let d = ws.documents.last(where: { $0.kind == .explainPlan && $0.id != doc.id && $0.plan != nil }), let p = d.plan {
                    other = p
                    leftTitle = d.title
                } else { return .ok }
                let c = PlanCompare.compare(other.lines, current.lines)
                ctx.ui?.showPlanComparison(c, leftTitle: leftTitle, rightTitle: doc.title)
                return CommandResult(message: L10n.tr("Różnice: \(c.rows.filter { $0.status != .same }.count)"))
            },
            Command(CommandDescriptor(id: "view.dba", title: L10n.tr("Panel DBA"), category: .view,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Przestrzenie tabel, pliki danych, parametry, użytkownicy, role, sesje i blokady; zmiany po potwierdzeniu."),
                                      feature: "SD-DBA-001"),
                    validate: connected) { ctx in
                ctx.ui?.showDBAPanel()
                return .ok
            },
            Command(CommandDescriptor(id: "dba.alterParameter", title: L10n.tr("Zmień parametr instancji"), category: .tools, submenu: L10n.tr("DBA"),
                                      parameters: [CommandParameter("name", .string, required: true, L10n.tr("Parametr")),
                                                   CommandParameter("value", .string, required: true, L10n.tr("Wartość")),
                                                   CommandParameter("scope", .string, L10n.tr("Zakres"), allowed: ["MEMORY", "SPFILE", "BOTH"]),
                                                   CommandContext.toolConnectionParam],
                                      agent: .none, effect: .modifiesDatabase, summary: L10n.tr("ALTER SYSTEM SET po potwierdzeniu i strażniku zmian."),
                                      inMenu: false, feature: "SD-DBA-001")) { ctx in
                let conn = try ctx.toolConnection()
                let sql = try DBAPanel.alterParameterSQL(name: ctx.arguments.string("name") ?? "", value: ctx.arguments.string("value") ?? "",
                                                         scope: ctx.arguments.string("scope") ?? "BOTH")
                if let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Zmienić parametr instancji?"), message: sql, buttons: [L10n.tr("Zmień"), L10n.tr("Anuluj")]) == 0 else {
                        throw CommandError.cancelledByUser
                    }
                }
                try await DBAPanel.execute(sql, connectionID: conn, in: ctx.workspace)
                return CommandResult(message: sql)
            },
            Command(CommandDescriptor(id: "dba.lockUser", title: L10n.tr("Zablokuj / odblokuj konto"), category: .tools, submenu: L10n.tr("DBA"),
                                      parameters: [CommandParameter("user", .string, required: true, L10n.tr("Użytkownik")),
                                                   CommandParameter("lock", .boolean, required: true, L10n.tr("Zablokuj (true) albo odblokuj (false)")),
                                                   CommandContext.toolConnectionParam],
                                      agent: .none, effect: .modifiesDatabase, summary: L10n.tr("ALTER USER … ACCOUNT LOCK/UNLOCK po potwierdzeniu i strażniku zmian."),
                                      inMenu: false, feature: "SD-DBA-001")) { ctx in
                let conn = try ctx.toolConnection()
                let sql = try DBAPanel.lockUserSQL(ctx.arguments.string("user") ?? "", lock: ctx.arguments.bool("lock") ?? true)
                if let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Zmienić stan konta?"), message: sql, buttons: [L10n.tr("Wykonaj"), L10n.tr("Anuluj")]) == 0 else {
                        throw CommandError.cancelledByUser
                    }
                }
                try await DBAPanel.execute(sql, connectionID: conn, in: ctx.workspace)
                return CommandResult(message: sql)
            },
            Command(CommandDescriptor(id: "tools.instanceViewer", title: L10n.tr("Instance Viewer"), category: .tools,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pulpit instancji: wersja, czas pracy, sesje, klasy oczekiwań, najdroższe SQL, SGA/PGA, z odświeżaniem."),
                                      feature: "SD-DBA-004"),
                    validate: connected) { ctx in
                ctx.ui?.showInstanceViewer()
                return .ok
            },
            Command(CommandDescriptor(id: "view.taskMonitor", title: L10n.tr("Zadania w tle"), category: .view,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Lista zadań w tle (Autotrace, dokumentacja, eksporty…) ze stanem, czasem i anulowaniem."),
                                      feature: "SD-MON-002")) { ctx in
                ctx.ui?.showTaskMonitor()
                return .ok
            },
            Command(CommandDescriptor(id: "tools.schemaDoc", title: L10n.tr("Dokumentacja schematu…"), category: .tools,
                                      parameters: [CommandParameter("directory", .string, L10n.tr("Katalog docelowy (bez — okno wyboru)")),
                                                   CommandParameter("owner", .string, L10n.tr("Schemat (domyślnie bieżący)")),
                                                   CommandParameter("source", .boolean, L10n.tr("Dołącz kod źródłowy programów"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Generuje dokumentację HTML schematu: tabele z kolumnami i komentarzami, klucze, indeksy, widoki, programy z parametrami."),
                                      feature: "SD-DOC-001"),
                    validate: connected) { ctx in
                let ws = ctx.workspace
                guard let dir = ctx.arguments.string("directory") else {
                    ctx.ui?.showSchemaDoc()
                    return .ok
                }
                let s = try await toolSession(ws, "doc")
                var owner = ctx.arguments.string("owner")?.uppercased() ?? ""
                if owner.isEmpty { owner = try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? "" }
                let includeSource = ctx.arguments.bool("source") ?? false
                var count = 0
                let task = ws.tasks.run(L10n.tr("Dokumentacja schematu \(owner)"), kind: "doc") { t in
                    count = try await SchemaDoc.generate(owner: owner, into: URL(fileURLWithPath: dir), includeSource: includeSource, in: s) { t.message = $0 }
                }
                await ws.tasks.wait(task)
                if case .failed(let m) = task.status { throw CommandError.notAvailable(m) }
                return CommandResult(message: L10n.tr("Zapisano stron: \(count)"), value: .int(Int64(count)))
            },
        ]
    }
}
