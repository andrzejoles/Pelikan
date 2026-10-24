import Foundation
import PelikanDB
import PelikanSQL

/// Kod obiektu przed i po zmianie wykonanej przez agenta (cofanie sesji agenta, PROMPT §7.3 p.6).
public struct AgentCodeChange: Sendable, Hashable {
    public var session: String
    public var connectionID: UUID
    public var object: DBObject
    /// Kod przed zmianą (nil — obiekt nie istniał).
    public var before: String?
    /// Kod po zmianie (nil — obiekt usunięty); inny kod przy cofaniu = konflikt.
    public var after: String?
}

/// Wynik cofnięcia sesji agenta.
public struct AgentUndoReport: Sendable, Equatable {
    public var editsUndone = 0
    public var objectsRestored = 0
    public var conflicts: [String] = []
    public var errors: [String] = []
    public var rolledBack = false
}

/// Zmiany w bazie wykonywane przez agenta (PROMPT §7.3 p.5–6): podgląd przed zgodą, DML niezatwierdzone do osobnej
/// zgody na COMMIT, DDL odmawiane przy otwartej transakcji (DDL zatwierdza ją niejawnie), historia kodu obiektów.
public enum AgentChanges {
    /// Obiekt kodu tworzony, zmieniany albo usuwany poleceniem DDL (nil — polecenie nie dotyczy kodu).
    static func codeTarget(_ sql: String, defaultOwner: String) -> (object: DBObject, drop: Bool)? {
        let pattern = #"^\s*(CREATE\s+(?:OR\s+REPLACE\s+)?(?:(?:NON)?EDITIONABLE\s+)?(?:(?:NO\s+)?FORCE\s+)?|DROP\s+)(PACKAGE\s+BODY|TYPE\s+BODY|PACKAGE|PROCEDURE|FUNCTION|TRIGGER|TYPE|VIEW)\s+(?:IF\s+(?:NOT\s+)?EXISTS\s+)?((?:"[^"]+"|[A-Za-z][\w$#]*)(?:\s*\.\s*(?:"[^"]+"|[A-Za-z][\w$#]*))?)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: sql, range: NSRange(location: 0, length: (sql as NSString).length)) else { return nil }
        let ns = sql as NSString
        let verb = ns.substring(with: m.range(at: 1)).uppercased()
        let typeText = ns.substring(with: m.range(at: 2)).uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let type = DBObjectType(rawValue: typeText) else { return nil }
        let parts = ns.substring(with: m.range(at: 3)).split(separator: ".").map { p -> String in
            let t = p.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("\"") ? String(t.dropFirst().dropLast()) : t.uppercased()
        }
        let owner = parts.count == 2 ? parts[0] : defaultOwner
        return (DBObject(owner: owner, name: parts.last ?? "", type: type), verb.hasPrefix("DROP"))
    }

    /// Aktualny kod obiektu (program — ALL_SOURCE, widok — DDL) albo nil, gdy obiekt nie istnieje.
    static func currentCode(_ o: DBObject, in s: any DatabaseSession) async -> String? {
        if o.type == .view {
            guard let ddl = try? await MetadataProvider.ddl(of: o, in: s), !ddl.isEmpty else { return nil }
            var t = ddl
            while t.hasSuffix(";") { t.removeLast() }
            return t
        }
        return try? await MetadataProvider.source(of: o, in: s)
    }

    /// Obiekty, których kod zmienia albo usuwa polecenie (DROP PACKAGE usuwa też ciało).
    static func affectedCode(_ sql: String, schema: String) -> [DBObject] {
        guard let t = codeTarget(sql, defaultOwner: schema) else { return [] }
        if t.drop, t.object.type == .package || t.object.type == .type {
            return [t.object, DBObject(owner: t.object.owner, name: t.object.name, type: t.object.type == .package ? .packageBody : .typeBody)]
        }
        return [t.object]
    }

    static func hasPendingTransaction(_ s: any DatabaseSession) async throws -> Bool {
        try await s.scalar("select dbms_transaction.local_transaction_id from dual") != nil
    }

    /// Polecenia skryptu (bez poleceń SQL*Plus) do wykonania przez agenta; odmowa dla kontroli transakcji i SQL*Plus.
    static func statements(_ script: String, single: Bool) throws -> [String] {
        let parts = ScriptSplitter.split(script)
        guard !parts.isEmpty else { throw CommandError.missingArgument("sql") }
        if single, parts.count != 1 { throw AgentDenial.permissionDenied(L10n.tr("execute_statement przyjmuje jedno polecenie — kilka: execute_script")) }
        return try parts.map { p in
            if p.sqlplusCommand != nil || p.category == .sqlplus { throw AgentDenial.permissionDenied(L10n.tr("polecenia SQL*Plus są niedostępne dla agenta")) }
            if p.category == .transactionControl { throw AgentDenial.permissionDenied(L10n.tr("COMMIT/ROLLBACK tylko narzędziami commit i rollback")) }
            var t = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Blok PL/SQL i CREATE kodu kończy „;” będące częścią składni; zwykłe SQL — bez końcowego średnika.
            if !p.isPLSQL { while t.hasSuffix(";") { t.removeLast() } }
            return t
        }
    }

    /// Nazwa tabeli zmienianej przez DML (INSERT INTO, UPDATE, DELETE FROM, MERGE INTO).
    static func dmlTable(_ sql: String, schema: String) -> (owner: String, name: String)? {
        let pattern = #"^\s*(?:INSERT\s+INTO|UPDATE|DELETE\s+(?:FROM\s+)?|MERGE\s+INTO)\s+((?:"[^"]+"|[A-Za-z][\w$#]*)(?:\s*\.\s*(?:"[^"]+"|[A-Za-z][\w$#]*))?)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: sql, range: NSRange(location: 0, length: (sql as NSString).length)) else { return nil }
        let parts = (sql as NSString).substring(with: m.range(at: 1)).split(separator: ".").map { p -> String in
            let t = p.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("\"") ? String(t.dropFirst().dropLast()) : t.uppercased()
        }
        return (parts.count == 2 ? parts[0] : schema, parts.last ?? "")
    }

    /// Podgląd skutków (okno zgody): polecenia, obiekty, na które wpływa (zależne z ALL_DEPENDENCIES, wyzwalacze tabeli),
    /// plan i szacunek wierszy dla DML, nieodwracalność (DDL na tabelach, polecenia nierozpoznane).
    static func preview(_ statements: [String], connection def: ConnectionDefinition, in s: any DatabaseSession) async throws -> EffectPreview {
        let schema = try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? ""
        var affected: [String] = [], plans: [String] = [], rows: Int64?, irreversible = false
        var kinds: [String] = []
        let pending = try await hasPendingTransaction(s)
        for sql in statements {
            let c = StatementClassifier.classify(sql)
            kinds.append(c.category.rawValue)
            switch c.category {
            case .dml:
                if let (o, n) = dmlTable(sql, schema: schema) {
                    affected.append("TABLE \(o).\(n)")
                    let (_, trg) = try await s.queryAll("select owner || '.' || trigger_name from all_triggers where table_owner = :o and table_name = :n and status = 'ENABLED'",
                                                       binds: [BindVariable(name: "o", value: .text(o)), BindVariable(name: "n", value: .text(n))], limit: 100)
                    affected += trg.compactMap { $0.first?.displayText.map { "TRIGGER " + $0 } }
                }
                if let p = try? await explain(sql, in: s) {
                    plans.append(p.text)
                    if let r = p.rows { rows = (rows ?? 0) + r }
                }
            case .ddl:
                let code = affectedCode(sql, schema: schema)
                if code.isEmpty { irreversible = true }
                for o in code {
                    affected.append("\(o.type.rawValue) \(o.qualifiedName)")
                    let (_, dep) = try await s.queryAll("select distinct type || ' ' || owner || '.' || name from all_dependencies where referenced_owner = :o and referenced_name = :n",
                                                       binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name))], limit: 200)
                    affected += dep.compactMap { $0.first?.displayText }
                }
            case .plsql, .query, .sessionControl:
                break
            default:
                irreversible = true
            }
        }
        var summary = L10n.tr("Agent chce wykonać polecenia na połączeniu „\(def.agentAlias)” (\(def.environment.rawValue)) — liczba poleceń: \(statements.count) (\(kinds.joined(separator: ", "))).")
        if statements.contains(where: { StatementClassifier.classify($0).category == .dml }) {
            summary += " " + L10n.tr("DML pozostanie niezatwierdzone do osobnej zgody na COMMIT.")
        }
        if pending, statements.contains(where: { StatementClassifier.classify($0).category == .ddl }) {
            summary += " " + L10n.tr("Agent ma niezatwierdzone zmiany — DDL zostanie odrzucone.")
        }
        if irreversible { summary += " " + L10n.tr("Tej zmiany nie da się cofnąć (DDL na tabelach albo polecenie nierozpoznane).") }
        return EffectPreview(summary: summary, statements: statements, affectedObjects: Array(NSOrderedSet(array: affected)) as? [String] ?? affected,
                             estimatedRows: rows, plan: plans.isEmpty ? nil : plans.joined(separator: "\n\n"), irreversible: irreversible)
    }

    /// EXPLAIN PLAN dla jednego zapytania albo DML (polecenie nie jest wykonywane); wynik DBMS_XPLAN i szacowana
    /// liczba wierszy z korzenia planu. Wiersze PLAN_TABLE są usuwane bez naruszania otwartej transakcji agenta.
    static func explain(_ sql: String, in s: any DatabaseSession) async throws -> (text: String, rows: Int64?) {
        let parts = ScriptSplitter.split(sql)
        guard parts.count == 1, let only = parts.first, [.query, .dml].contains(only.category) else {
            throw CommandError.invalidArgument("sql", L10n.tr("plan wykonania dla jednego zapytania albo polecenia DML"))
        }
        var text = only.text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast() }
        let id = "PLK" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)
        let pending = try await hasPendingTransaction(s)
        _ = try await s.execute("explain plan set statement_id = '\(id)' for \(text)")
        let b = [BindVariable(name: "id", value: .text(id))]
        let (_, rows) = try await s.queryAll("select plan_table_output from table(dbms_xplan.display('PLAN_TABLE', :id, 'TYPICAL'))", binds: b, limit: 2000)
        let card = try await s.scalar("select cardinality from plan_table where statement_id = :id and id = 0", binds: b).flatMap { Int64($0) }
        if pending { _ = try? await s.execute("delete from plan_table where statement_id = :id", binds: b) } else { try? await s.rollback() }
        return (rows.map { $0.first?.displayText ?? "" }.joined(separator: "\n"), card)
    }
}

extension Workspace {
    func agentPendingKey(_ session: String, _ connection: UUID) -> String { "\(session)|\(connection.uuidString)" }

    /// Wykonuje polecenia agenta w jego sesji: historia kodu przed DDL, odmowa DDL przy niezatwierdzonym DML, DML bez
    /// zatwierdzenia. Zwraca wynik każdego polecenia i stan transakcji.
    func runAgentStatements(_ ctx: CommandContext, _ statements: [String], def: ConnectionDefinition, s: any DatabaseSession) async throws -> JSONValue {
        guard let sessionID = ctx.invoker.agentSessionID else { throw AgentDenial.sessionClosed }
        let schema = try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? ""
        let key = agentPendingKey(sessionID, def.id)
        var results: [JSONValue] = []
        for sql in statements {
            let c = StatementClassifier.classify(sql)
            if c.category == .ddl, try await AgentChanges.hasPendingTransaction(s) {
                throw AgentDenial.permissionDenied(L10n.tr("agent ma niezatwierdzone zmiany, a DDL zatwierdziłoby je niejawnie — najpierw commit albo rollback"))
            }
            let code = c.category == .ddl ? AgentChanges.affectedCode(sql, schema: schema) : []
            var before: [DBObject: String?] = [:]
            for o in code { before[o] = .some(await AgentChanges.currentCode(o, in: s)) }
            var entry: [String: JSONValue] = ["statement": .string(String(sql.prefix(200))), "category": .string(c.category.rawValue)]
            do {
                let r = try await s.execute(sql)
                if c.category == .dml {
                    agentPendingRows[key, default: 0] += r.rowsAffected
                    entry["rowsAffected"] = .int(Int64(r.rowsAffected))
                }
                if let w = r.warning { entry["warning"] = .string(w.message) }
            } catch {
                entry["error"] = .string(error.localizedDescription)
                results.append(.object(entry))
                // Kod mógł zostać utworzony z błędami kompilacji — historia i tak potrzebna.
                await recordCodeChanges(code, before: before, session: sessionID, connection: def.id, s: s)
                return .object(["results": .array(results), "stoppedOnError": .bool(true), "pendingRows": .int(Int64(agentPendingRows[key] ?? 0))])
            }
            await recordCodeChanges(code, before: before, session: sessionID, connection: def.id, s: s)
            if !code.isEmpty {
                var errs: [JSONValue] = []
                for o in code where o.type != .view {
                    let (_, rows) = try await s.queryAll("select line, position, text from all_errors where owner = :o and name = :n and type = :t and attribute = 'ERROR' order by sequence",
                                                         binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name)),
                                                                 BindVariable(name: "t", value: .text(o.type.rawValue))], limit: 200)
                    errs += rows.map { .string("\(o.type.rawValue) \(o.name) \($0[0].displayText ?? ""):\($0[1].displayText ?? "") \($0[2].displayText ?? "")") }
                }
                if !errs.isEmpty { entry["compileErrors"] = .array(errs) }
            }
            results.append(.object(entry))
        }
        let pending = try await AgentChanges.hasPendingTransaction(s)
        if !pending { agentPendingRows[key] = nil }
        return .object(["results": .array(results), "pendingTransaction": .bool(pending), "pendingRows": .int(Int64(agentPendingRows[key] ?? 0))])
    }

    private func recordCodeChanges(_ code: [DBObject], before: [DBObject: String?], session: String, connection: UUID, s: any DatabaseSession) async {
        for o in code {
            let after = await AgentChanges.currentCode(o, in: s)
            let b = before[o] ?? nil
            if b != after { agentCodeChanges.append(AgentCodeChange(session: session, connectionID: connection, object: o, before: b, after: after)) }
        }
    }

    /// Cofnięcie sesji agenta (PROMPT §7.6): zmiany edytorów, przywrócenie kodu obiektów z historii (w odwrotnej
    /// kolejności; obiekt zmieniony później przez kogoś innego to konflikt, pomijany bez `force`), ROLLBACK
    /// niezatwierdzonych zmian. Przywracanie wykonuje sesja kompilacji użytkownika (cofnięcie zleca użytkownik).
    public func undoAgentSession(_ session: String, force: Bool = false) async -> AgentUndoReport {
        var report = AgentUndoReport()
        let edits = undoAgentEdits(session: session, force: force)
        report.editsUndone = edits.undone
        report.conflicts = edits.conflicts
        for key in sessions.keys(purpose: .agent(session)) {
            if let s = sessions.existingSession(key), (try? await AgentChanges.hasPendingTransaction(s)) == true {
                try? await s.rollback()
                report.rolledBack = true
            }
            agentPendingRows[agentPendingKey(session, key.connectionID)] = nil
        }
        // Pierwszy stan obiektu sprzed sesji i ostatni stan po niej (kilka zmian tego samego obiektu).
        let changes = agentCodeChanges.filter { $0.session == session }
        var seen = Set<DBObject>()
        for change in changes.reversed() where !seen.contains(change.object) {
            seen.insert(change.object)
            let first = changes.first { $0.object == change.object }!
            do {
                let s = try await sessions.session(sessions.compileKey(connection: change.connectionID))
                let now = await AgentChanges.currentCode(change.object, in: s)
                if now != change.after, !force {
                    report.conflicts.append("\(change.object.type.rawValue) \(change.object.qualifiedName)")
                    continue
                }
                if let b = first.before {
                    _ = try await s.execute(b)
                } else if now != nil {
                    // Obiekt utworzony przez agenta — usuwany (ciało przed specyfikacją: kolejność odwrotna).
                    _ = try await s.execute("drop \(change.object.type.rawValue.lowercased()) \"\(change.object.owner)\".\"\(change.object.name)\"")
                }
                report.objectsRestored += 1
            } catch {
                report.errors.append("\(change.object.qualifiedName): \(error.localizedDescription)")
            }
        }
        agentCodeChanges.removeAll { $0.session == session && !report.conflicts.contains("\($0.object.type.rawValue) \($0.object.qualifiedName)") }
        return report
    }
}

/// Narzędzia agenta zmieniające bazę (PROMPT §7.5, „Za zgodą”): każde z podglądem dla okna zgody.
@MainActor
enum AgentChangeCommands {
    static let connectionParam = AgentDatabaseCommands.connectionParam

    static func changeCommand(_ id: CommandID, _ title: String, sqlParam: CommandParameter, single: Bool, summary: String, feature: String,
                              validate: @escaping @Sendable (String) throws -> Void = { _ in }) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: .help, parameters: [connectionParam, sqlParam],
                                  agent: .approval, effect: .modifiesDatabase, summary: summary, inMenu: false, feature: feature),
                preview: { ctx in
                    let (def, s) = try await ctx.workspace.agentDatabase(ctx, action: "preview")
                    let text = ctx.arguments.string(sqlParam.name) ?? ""
                    try validate(text)
                    return try await AgentChanges.preview(try AgentChanges.statements(text, single: single), connection: def, in: s)
                }) { ctx in
            let text = ctx.arguments.string(sqlParam.name) ?? ""
            try validate(text)
            let statements = try AgentChanges.statements(text, single: single)
            let (def, s) = try await ctx.workspace.agentDatabase(ctx, action: id.rawValue)
            return CommandResult(value: try await ctx.workspace.runAgentStatements(ctx, statements, def: def, s: s))
        }
    }

    static var all: [Command] {
        [
            changeCommand("agent.execute", L10n.tr("Wykonaj polecenie (agent)"),
                          sqlParam: CommandParameter("sql", .sql, required: true, L10n.tr("Jedno polecenie: DML, DDL albo blok PL/SQL")), single: true,
                          summary: L10n.tr("Wykonuje jedno polecenie w sesji agenta po zgodzie użytkownika; DML pozostaje niezatwierdzone do zgody na COMMIT, kod obiektów trafia do historii przed zmianą."),
                          feature: "AI-TOOL-003"),
            changeCommand("agent.executeScript", L10n.tr("Wykonaj skrypt (agent)"),
                          sqlParam: CommandParameter("script", .sql, required: true, L10n.tr("Polecenia rozdzielone ; (bloki i kod PL/SQL zakończone /)")), single: false,
                          summary: L10n.tr("Wykonuje kilka poleceń po kolei w sesji agenta po jednej zgodzie; zatrzymuje się na pierwszym błędzie."),
                          feature: "AI-TOOL-003"),
            changeCommand("agent.createTestPackage", L10n.tr("Utwórz pakiet testowy (agent)"),
                          sqlParam: CommandParameter("source", .sql, required: true, L10n.tr("Specyfikacja i ciało pakietu testowego utPLSQL (z --%suite)")), single: false,
                          summary: L10n.tr("Kompiluje w bazie pakiet testowy utPLSQL podany przez agenta (specyfikacja z --%suite i ciało)."),
                          feature: "AI-TOOL-003",
                          validate: { text in
                              guard text.lowercased().contains("--%suite") else { throw CommandError.invalidArgument("source", L10n.tr("brak adnotacji --%suite")) }
                          }),
            Command(CommandDescriptor(id: "agent.compile", title: L10n.tr("Kompiluj (agent)"), category: .help,
                                      parameters: [connectionParam, AgentCommands.windowParam,
                                                   CommandParameter("object", .string, L10n.tr("Zamiast okna: obiekt do rekompilacji (SCHEMAT.NAZWA)")),
                                                   AgentDatabaseCommands.typeParam],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Kompiluje jednostki z okna programu w sesji agenta (kod poprzedni trafia do historii) albo rekompiluje obiekt; zwraca błędy kompilacji."),
                                      inMenu: false, feature: "AI-TOOL-003"),
                    preview: { ctx in
                        let (def, s) = try await ctx.workspace.agentDatabase(ctx, action: "preview")
                        return try await AgentChanges.preview(try await compileStatements(ctx, s), connection: def, in: s)
                    }) { ctx in
                let (def, s) = try await ctx.workspace.agentDatabase(ctx, action: "compile")
                return CommandResult(value: try await ctx.workspace.runAgentStatements(ctx, try await compileStatements(ctx, s), def: def, s: s))
            },
            Command(CommandDescriptor(id: "agent.commit", title: L10n.tr("COMMIT zmian agenta"), category: .help,
                                      parameters: [connectionParam], agent: .approval, effect: .transaction,
                                      summary: L10n.tr("Zatwierdza niezatwierdzone zmiany agenta na połączeniu (po zgodzie z liczbą zmienionych wierszy) — nieodwracalne."),
                                      inMenu: false, feature: "AI-SEC-007"),
                    preview: { ctx in
                        let def = try ctx.workspace.agentConnection(alias: ctx.arguments.string("connection"))
                        let rows = ctx.invoker.agentSessionID.flatMap { ctx.workspace.agentPendingRows[ctx.workspace.agentPendingKey($0, def.id)] } ?? 0
                        return EffectPreview(summary: L10n.tr("COMMIT zmian agenta na połączeniu „\(def.agentAlias)”: zmienione wiersze — \(rows). Po zatwierdzeniu zmian danych nie da się cofnąć."),
                                             statements: ["COMMIT"], estimatedRows: Int64(rows), irreversible: true)
                    }) { ctx in
                let (def, s) = try await ctx.workspace.agentDatabase(ctx, action: "commit")
                try await s.commit()
                if let id = ctx.invoker.agentSessionID { ctx.workspace.agentPendingRows[ctx.workspace.agentPendingKey(id, def.id)] = nil }
                return CommandResult(message: "COMMIT")
            },
            Command(CommandDescriptor(id: "agent.rollback", title: L10n.tr("ROLLBACK zmian agenta"), category: .help,
                                      parameters: [connectionParam], agent: .approval, effect: .transaction,
                                      summary: L10n.tr("Wycofuje niezatwierdzone zmiany agenta na połączeniu."),
                                      inMenu: false, feature: "AI-SEC-007"),
                    preview: { ctx in
                        let def = try ctx.workspace.agentConnection(alias: ctx.arguments.string("connection"))
                        let rows = ctx.invoker.agentSessionID.flatMap { ctx.workspace.agentPendingRows[ctx.workspace.agentPendingKey($0, def.id)] } ?? 0
                        return EffectPreview(summary: L10n.tr("ROLLBACK zmian agenta na połączeniu „\(def.agentAlias)”: wycofane wiersze — \(rows)."),
                                             statements: ["ROLLBACK"], estimatedRows: Int64(rows))
                    }) { ctx in
                let (def, s) = try await ctx.workspace.agentDatabase(ctx, action: "rollback")
                try await s.rollback()
                if let id = ctx.invoker.agentSessionID { ctx.workspace.agentPendingRows[ctx.workspace.agentPendingKey(id, def.id)] = nil }
                return CommandResult(message: "ROLLBACK")
            },
            Command(CommandDescriptor(id: "agent.runTests", title: L10n.tr("Uruchom testy utPLSQL (agent)"), category: .help,
                                      parameters: [connectionParam, CommandParameter("paths", .string, L10n.tr("Ścieżki rozdzielone przecinkami (schemat, schemat.pakiet[.procedura], schemat:suitepath); domyślnie bieżący schemat")),
                                                   CommandParameter("coverage", .boolean, L10n.tr("Zbieraj pokrycie kodu"))],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia testy utPLSQL w sesjach agenta (zmiany testów są wycofywane przez utPLSQL) i zwraca wynik po zakończeniu; okno wyników pokazuje przebieg użytkownikowi."),
                                      inMenu: false, feature: "AI-TOOL-003")) { ctx in
                let ws = ctx.workspace
                guard let id = ctx.invoker.agentSessionID else { throw AgentDenial.sessionClosed }
                let (def, s) = try await ws.agentDatabase(ctx, action: "run_tests")
                let schema = try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? ""
                let paths = ctx.arguments.string("paths").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? [schema]
                let run = try await UtplsqlRunner.start(paths: paths, coverageSchemes: ctx.arguments.bool("coverage") == true ? [schema] : [], in: ws,
                                                        connectionID: def.id, purposes: (.agent("\(id)/run"), .agent("\(id)/events")))
                ctx.ui?.showUtplsqlResults(run)
                for _ in 0..<6000 where !run.finished { try? await Task.sleep(for: .milliseconds(100)) }
                return try await ws.invoke("agent.testResults", invoker: ctx.invoker)
            },
            Command(CommandDescriptor(id: "agent.generateTest", title: L10n.tr("Generuj i kompiluj szkielet testu (agent)"), category: .help,
                                      parameters: [connectionParam, CommandParameter("package", .string, required: true, L10n.tr("Testowany pakiet (SCHEMAT.NAZWA albo NAZWA)"))],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Tworzy w bazie szkielet pakietu testowego test_<pakiet> (suita, test na każdą procedurę i funkcję) i otwiera go w oknie programu."),
                                      inMenu: false, feature: "AI-TOOL-003"),
                    preview: { ctx in
                        let (def, s) = try await ctx.workspace.agentDatabase(ctx, action: "preview")
                        return try await AgentChanges.preview(try await skeletonStatements(ctx, s).statements, connection: def, in: s)
                    }) { ctx in
                let (def, s) = try await ctx.workspace.agentDatabase(ctx, action: "generate_test_skeleton")
                let (text, statements) = try await skeletonStatements(ctx, s)
                let result = try await ctx.workspace.runAgentStatements(ctx, statements, def: def, s: s)
                let doc = ctx.workspace.newDocument(.program, text: text)
                doc.connectionID = def.id
                doc.isModified = false
                ctx.workspace.recordAgentEdit(ctx, doc, before: "", created: true)
                return CommandResult(value: .object(["window": .string(Workspace.agentWindowID(doc)), "compile": result]))
            },
            Command(CommandDescriptor(id: "agent.installUtplsql", title: L10n.tr("Instaluj utPLSQL (agent)"), category: .help,
                                      parameters: [connectionParam, CommandParameter("version", .string, L10n.tr("Znacznik wydania (domyślnie najnowsze)"))],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Instaluje albo aktualizuje utPLSQL z oficjalnego wydania w oknie poleceń widocznym dla użytkownika — tylko połączenia deweloperskie i testowe."),
                                      inMenu: false, feature: "AI-TOOL-003"),
                    preview: { ctx in
                        let def = try ctx.workspace.agentConnection(alias: ctx.arguments.string("connection"))
                        return EffectPreview(summary: L10n.tr("Instalacja albo aktualizacja utPLSQL na połączeniu „\(def.agentAlias)” (\(def.environment.rawValue)) z oficjalnego wydania; potrzebne uprawnienia SYSDBA albo DBA."),
                                             statements: ["@install_headless.sql / @uninstall.sql + @install.sql"])
                    }) { ctx in
                let def = try ctx.workspace.agentConnection(alias: ctx.arguments.string("connection"))
                return try await UtplsqlCommands.install(ctx, connection: def.id)
            },
        ]
    }

    /// Polecenia kompilacji: jednostki okna programu albo ALTER … COMPILE wskazanego obiektu.
    static func compileStatements(_ ctx: CommandContext, _ s: any DatabaseSession) async throws -> [String] {
        if let object = ctx.arguments.string("object") {
            let o = try await AgentDatabaseCommands.resolve(object, type: ctx.arguments.string("type"), in: s)
            let q = "\"\(o.owner)\".\"\(o.name)\""
            switch o.type {
            case .packageBody: return ["alter package \(q) compile body"]
            case .typeBody: return ["alter type \(q) compile body"]
            default: return ["alter \(o.type.rawValue.lowercased()) \(q) compile"]
            }
        }
        let d = try ctx.workspace.agentDocument(ctx.arguments.string("window"))
        let units = ProgramCompiler.units(in: d.text)
        guard !units.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak jednostek do kompilacji (CREATE … zakończone /)")) }
        return units.map(\.text)
    }

    static func skeletonStatements(_ ctx: CommandContext, _ s: any DatabaseSession) async throws -> (text: String, statements: [String]) {
        let o = try await AgentDatabaseCommands.resolve(ctx.arguments.string("package") ?? "", type: "PACKAGE", in: s)
        let spec = try await MetadataProvider.source(of: o, in: s)
        let text = UtplsqlExplorer.skeleton(for: o.name, owner: o.owner, specification: spec)
        return (text, ProgramCompiler.units(in: text).map(\.text))
    }
}
