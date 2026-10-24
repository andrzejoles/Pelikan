import Foundation
import PelikanDB

/// Komendy operacji na obiektach i okna programu z audytu Etapu 8.
@MainActor
enum ObjectAdminCommands {
    static func command(_ id: CommandID, _ title: String, _ category: CommandCategory = .tools, submenu: String? = L10n.tr("Obiekt"),
                        params: [CommandParameter] = [], agent: AgentAccess = .none, effect: CommandEffect, summary: String, feature: String,
                        validate: (@MainActor (Workspace) -> Bool)? = nil,
                        _ run: @escaping CommandHandler) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: category, submenu: submenu, parameters: params, agent: agent, effect: effect,
                                  summary: summary, feature: feature), validate: validate, run: run)
    }

    static func mainSession(_ ctx: CommandContext) async throws -> any DatabaseSession {
        guard let conn = ctx.workspace.sessions.mainConnectionID else { throw CommandError.notConnected }
        return try await ctx.workspace.sessions.session(SessionKey(connectionID: conn, purpose: .main))
    }

    static func programDocument(_ ws: Workspace) -> Document? { ws.activeDocument.flatMap { $0.kind == .program ? $0 : nil } }

    static var all: [Command] {
        let objectParams = ObjectCommands.objectParams
        func toggle(_ enabled: Bool) -> Command {
            command(enabled ? "ob.enable" : "ob.disable", enabled ? L10n.tr("Włącz") : L10n.tr("Wyłącz"),
                    params: objectParams + [CommandParameter("constraint", .string, L10n.tr("Więz tabeli (puste — wszystkie wyzwalacze tabeli)"))],
                    effect: .modifiesDatabase,
                    summary: enabled ? L10n.tr("Włącza wyzwalacz albo więz lub wszystkie wyzwalacze tabeli.") : L10n.tr("Wyłącza wyzwalacz albo więz lub wszystkie wyzwalacze tabeli."),
                    feature: "PD-OB-019",
                    validate: { ws in ws.selectedObject.map { [.trigger, .table].contains($0.type) } ?? false }) { ctx in
                let (o, _) = try await ObjectCommands.target(ctx)
                let sql = try ObjectAdmin.setEnabled(o, enabled: enabled, constraint: ctx.arguments.string("constraint"))
                try await ctx.workspace.guardModification([sql], connectionID: ctx.workspace.sessions.mainConnectionID ?? UUID())
                _ = try await mainSession(ctx).execute(sql)
                ctx.workspace.metadata()?.refresh()
                return CommandResult(message: sql)
            }
        }
        return [
            toggle(true), toggle(false),
            command("ob.refreshMV", L10n.tr("Odśwież widok zmaterializowany"), params: objectParams, effect: .modifiesDatabase,
                    summary: L10n.tr("Odświeża widok zmaterializowany (DBMS_MVIEW.REFRESH, metoda z definicji)."), feature: "PD-OB-019",
                    validate: { $0.selectedObject?.type == .materializedView }) { ctx in
                let (o, _) = try await ObjectCommands.target(ctx)
                _ = try await mainSession(ctx).execute("begin dbms_mview.refresh(:n); end;",
                                                       binds: [BindVariable(name: "n", value: .text("\(o.owner).\(o.name)"))])
                return CommandResult(message: L10n.tr("Odświeżono \(o.name)"))
            },
            command("ob.testLink", L10n.tr("Testuj łącze"), params: objectParams, agent: .read, effect: .none,
                    summary: L10n.tr("Sprawdza łącze bazy danych zapytaniem do DUAL po drugiej stronie i podaje czas odpowiedzi."), feature: "PD-OB-019",
                    validate: { $0.selectedObject?.type == .databaseLink }) { ctx in
                let (o, _) = try await ObjectCommands.target(ctx)
                guard o.name.range(of: #"^[A-Za-z0-9_$#.@]+$"#, options: .regularExpression) != nil else { throw CommandError.invalidArgument("object", o.name) }
                let start = ContinuousClock.now
                let v = try await mainSession(ctx).scalar("select dummy from dual@\(o.name)")
                let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
                guard v == "X" else { throw CommandError.notAvailable(L10n.tr("Łącze \(o.name) nie odpowiada poprawnie")) }
                return CommandResult(message: L10n.tr("Łącze \(o.name) działa (\(ms) ms)"), value: .int(Int64(ms)))
            },
            command("ob.runJob", L10n.tr("Uruchom zadanie"), params: objectParams, effect: .modifiesDatabase,
                    summary: L10n.tr("Uruchamia zadanie DBMS_JOB teraz (zadania Scheduler — w oknie DBMS Scheduler)."), feature: "PD-OB-019",
                    validate: { $0.selectedObject?.type == .job }) { ctx in
                let (o, _) = try await ObjectCommands.target(ctx)
                guard o.name.allSatisfy(\.isNumber) else { throw CommandError.notAvailable(L10n.tr("To nie jest zadanie DBMS_JOB (numer zadania)")) }
                _ = try await mainSession(ctx).execute("begin dbms_job.run(:j); end;", binds: [BindVariable(name: "j", type: .number, value: .text(o.name))])
                return CommandResult(message: L10n.tr("Zadanie \(o.name) wykonane"))
            },
            command("ob.startQueue", L10n.tr("Uruchom kolejkę"), params: objectParams + [
                        CommandParameter("enqueue", .boolean, L10n.tr("Kolejkowanie (domyślnie tak)")),
                        CommandParameter("dequeue", .boolean, L10n.tr("Odbieranie (domyślnie tak)"))],
                    effect: .modifiesDatabase,
                    summary: L10n.tr("DBMS_AQADM.START_QUEUE: włącza kolejkowanie i odbieranie wiadomości kolejki AQ."), feature: "PD-OB-019",
                    validate: { $0.selectedObject?.type == .queue }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                let sql = "begin dbms_aqadm.start_queue(queue_name => :q, enqueue => \(ctx.arguments.bool("enqueue") ?? true ? "true" : "false"), dequeue => \(ctx.arguments.bool("dequeue") ?? true ? "true" : "false")); end;"
                try await ctx.workspace.guardModification([sql], connectionID: m.connectionID)
                _ = try await mainSession(ctx).execute(sql, binds: [BindVariable(name: "q", value: .text("\(o.owner).\(o.name)"))])
                return CommandResult(message: L10n.tr("Kolejka \(o.name) uruchomiona"))
            },
            command("ob.stopQueue", L10n.tr("Zatrzymaj kolejkę"), params: objectParams + [
                        CommandParameter("enqueue", .boolean, L10n.tr("Zatrzymaj kolejkowanie (domyślnie tak)")),
                        CommandParameter("dequeue", .boolean, L10n.tr("Zatrzymaj odbieranie (domyślnie tak)"))],
                    effect: .modifiesDatabase,
                    summary: L10n.tr("DBMS_AQADM.STOP_QUEUE: wyłącza kolejkowanie i odbieranie wiadomości kolejki AQ (czeka na bieżące transakcje)."),
                    feature: "PD-OB-019",
                    validate: { $0.selectedObject?.type == .queue }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                let sql = "begin dbms_aqadm.stop_queue(queue_name => :q, enqueue => \(ctx.arguments.bool("enqueue") ?? true ? "true" : "false"), dequeue => \(ctx.arguments.bool("dequeue") ?? true ? "true" : "false"), wait => true); end;"
                try await ctx.workspace.guardModification([sql], connectionID: m.connectionID)
                _ = try await mainSession(ctx).execute(sql, binds: [BindVariable(name: "q", value: .text("\(o.owner).\(o.name)"))])
                return CommandResult(message: L10n.tr("Kolejka \(o.name) zatrzymana"))
            },
            command("prog.reloadFromDatabase", L10n.tr("Wczytaj ponownie z bazy"), .session, submenu: nil, agent: .none, effect: .modifiesEditor,
                    summary: L10n.tr("Zastępuje tekst okna programu źródłem obiektów z bazy (po potwierdzeniu, gdy są niezapisane zmiany)."), feature: "PD-PROG-011",
                    validate: { programDocument($0).map { !$0.objectTimestamps.isEmpty } ?? false }) { ctx in
                guard let doc = programDocument(ctx.workspace), let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
                if doc.isModified, let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Wczytać ponownie z bazy?"), message: L10n.tr("Niezapisane zmiany w oknie zostaną utracone."),
                                       buttons: [L10n.tr("Wczytaj"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                let order: [DBObjectType] = [.package, .type, .procedure, .function, .trigger, .packageBody, .typeBody]
                let objects = doc.objectTimestamps.keys.compactMap { k -> DBObject? in
                    let p = k.split(separator: ".", maxSplits: 2).map(String.init)
                    guard p.count == 3, let t = DBObjectType(rawValue: p[2]) else { return nil }
                    return DBObject(owner: p[0], name: p[1], type: t)
                }.sorted { (order.firstIndex(of: $0.type) ?? 9) < (order.firstIndex(of: $1.type) ?? 9) }
                var text = ""
                for o in objects { if let src = try? await m.source(of: o) { text += (text.isEmpty ? "" : "\n") + src + "\n/\n" } }
                guard !text.isEmpty else { throw CommandError.notAvailable(L10n.tr("Nie znaleziono źródła w bazie")) }
                doc.text = text
                doc.isModified = false
                if let s = try? await m.session() { doc.objectTimestamps = (try? await ObjectAdmin.lastDDLTimes(objects, in: s)) ?? doc.objectTimestamps }
                doc.statusText = L10n.tr("Wczytano ponownie z bazy")
                return .ok
            },
            command("ob.recycleBin", L10n.tr("Kosz"), submenu: nil, agent: .read, effect: .none,
                    summary: L10n.tr("Obiekty usunięte do kosza (USER_RECYCLEBIN): nazwa pierwotna, typ, czas usunięcia."), feature: "PD-OB-021",
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                let items = try await ObjectAdmin.recycleBin(try await mainSession(ctx))
                if ctx.invoker == .user {
                    let text = items.isEmpty ? L10n.tr("Kosz jest pusty.") : items.map { "\($0.originalName)  \($0.type)  \($0.dropTime)  \($0.binName)" }.joined(separator: "\n")
                    ctx.ui?.showHTMLReport(title: L10n.tr("Kosz"), html: PackCommands.html(L10n.tr("Kosz"), text))
                }
                return CommandResult(value: .array(items.map { .object(["binName": .string($0.binName), "originalName": .string($0.originalName),
                                                                       "type": .string($0.type), "dropTime": .string($0.dropTime)]) }))
            },
            command("ob.restoreFromRecycleBin", L10n.tr("Przywróć z kosza…"), submenu: L10n.tr("Kosz"),
                    params: [CommandParameter("name", .string, required: true, L10n.tr("Nazwa pierwotna albo BIN$…")),
                             CommandParameter("renameTo", .string, L10n.tr("Nowa nazwa (puste — pierwotna)"))],
                    effect: .modifiesDatabase, summary: L10n.tr("Przywraca tabelę z kosza (FLASHBACK TABLE … TO BEFORE DROP), opcjonalnie pod nową nazwą."),
                    feature: "PD-OB-021", validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                let s = try await mainSession(ctx)
                let name = ctx.arguments.string("name") ?? ""
                guard let item = try await ObjectAdmin.recycleBin(s).first(where: { $0.binName == name || $0.originalName.caseInsensitiveCompare(name) == .orderedSame }),
                      item.canRestore else { throw CommandError.notAvailable(L10n.tr("Nie ma w koszu obiektu „\(name)” do przywrócenia")) }
                let sql = ObjectAdmin.restoreStatement(binName: item.binName, renameTo: ctx.arguments.string("renameTo"))
                _ = try await s.execute(sql)
                ctx.workspace.metadata()?.refresh()
                return CommandResult(message: sql)
            },
            command("ob.purgeRecycleBin", L10n.tr("Opróżnij kosz…"), submenu: L10n.tr("Kosz"),
                    params: [CommandParameter("name", .string, L10n.tr("Obiekt (puste — cały kosz)"))],
                    effect: .modifiesDatabase, summary: L10n.tr("Trwale usuwa obiekt z kosza albo cały kosz użytkownika (PURGE) — po potwierdzeniu."),
                    feature: "PD-OB-021", validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                let s = try await mainSession(ctx)
                var item: ObjectAdmin.RecycledObject?
                if let name = ctx.arguments.string("name"), !name.isEmpty {
                    item = try await ObjectAdmin.recycleBin(s).first { $0.binName == name || $0.originalName.caseInsensitiveCompare(name) == .orderedSame }
                    guard item != nil else { throw CommandError.notAvailable(L10n.tr("Nie ma w koszu obiektu „\(name)”")) }
                }
                if let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Usunąć trwale?"), message: item.map { L10n.tr("Obiekt „\($0.originalName)” zostanie usunięty z kosza bez możliwości przywrócenia.") }
                                        ?? L10n.tr("Wszystkie obiekty z kosza zostaną usunięte bez możliwości przywrócenia."),
                                       buttons: [L10n.tr("Usuń"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                let sql = ObjectAdmin.purgeStatement(item)
                _ = try await s.execute(sql)
                return CommandResult(message: sql)
            },
            command("ob.ccflags", L10n.tr("Flagi kompilacji warunkowej…"),
                    params: objectParams + [CommandParameter("flags", .string, L10n.tr("PLSQL_CCFLAGS, np. debug:TRUE, level:2 (bez argumentu — odczyt)"))],
                    agent: .read, effect: .modifiesDatabase,
                    summary: L10n.tr("Pokazuje PLSQL_CCFLAGS jednostki albo ustawia nowe i rekompiluje ją (REUSE SETTINGS)."), feature: "PD-OB-020",
                    validate: { ws in ws.selectedObject.map(\.type.isProgram) ?? false }) { ctx in
                let (o, _) = try await ObjectCommands.target(ctx)
                let s = try await mainSession(ctx)
                let current = try await ObjectAdmin.ccflags(o, in: s)
                var flags = ctx.arguments.string("flags")
                if flags == nil, ctx.invoker == .user { flags = await ctx.ui?.askText(L10n.tr("Flagi kompilacji warunkowej"), message: "PLSQL_CCFLAGS", defaultValue: current) }
                guard let flags, flags != current else { return CommandResult(value: .string(current)) }
                guard ctx.invoker == .user else { throw AgentDenial.permissionDenied("zmiana flag kompilacji tylko przez użytkownika") }
                _ = try await s.execute(try ObjectAdmin.ccflagsStatement(o, flags: flags))
                ctx.workspace.metadata()?.refresh()
                return CommandResult(value: .string(try await ObjectAdmin.ccflags(o, in: s)))
            },
            command("ob.addSourceToEditor", L10n.tr("Dodaj źródło do edytora"), params: objectParams, agent: .none, effect: .modifiesEditor,
                    summary: L10n.tr("Wstawia źródło zaznaczonego obiektu w miejscu kursora w aktywnym oknie programu albo testu."), feature: "PD-OB-023",
                    validate: { ws in ws.selectedObject != nil && [.program, .test, .sql].contains(ws.activeDocument?.kind) }) { ctx in
                guard let doc = ctx.workspace.activeDocument, [.program, .test, .sql].contains(doc.kind) else { throw CommandError.notAvailable(L10n.tr("Brak okna edytora")) }
                let (o, m) = try await ObjectCommands.target(ctx)
                let source = o.type.isProgram ? try await m.source(of: o) + "\n/\n" : try await m.ddl(of: o)
                let ns = doc.text as NSString
                let at = min(doc.selectedRange.lowerBound, ns.length), end = min(doc.selectedRange.upperBound, ns.length)
                doc.text = ns.replacingCharacters(in: NSRange(location: at, length: end - at), with: source)
                doc.selectedRange = at..<(at + (source as NSString).length)
                doc.isModified = true
                return .ok
            },
            command("prog.safeCompile", L10n.tr("Kompilacja próbna"), .session, submenu: nil, effect: .modifiesDatabase,
                    summary: L10n.tr("Kompiluje jednostki okna pod tymczasową nazwą i pokazuje błędy bez zastępowania obiektów w bazie."), feature: "PD-PROG-010",
                    validate: { programDocument($0) != nil }) { ctx in
                guard let doc = programDocument(ctx.workspace), let conn = ctx.workspace.effectiveConnection(of: doc) else { throw CommandError.notConnected }
                let units = ProgramCompiler.units(in: doc.text)
                guard !units.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak jednostek do kompilacji (CREATE … zakończone /)")) }
                let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: conn))
                let messages = try await ObjectAdmin.safeCompile(units, in: s)
                doc.compileMessages = messages
                let errors = messages.filter { $0.severity == .error }.count
                return CommandResult(message: errors == 0 ? L10n.tr("Kompilacja próbna bez błędów") : L10n.tr("Kompilacja próbna: błędów \(errors)"),
                                     value: .int(Int64(errors)))
            },
            command("prog.checkChanges", L10n.tr("Sprawdź zmiany obiektów w bazie"), .session, submenu: nil, agent: .read, effect: .none,
                    summary: L10n.tr("Porównuje czas ostatniej zmiany obiektów okna programu w bazie z chwilą wczytania albo kompilacji."), feature: "PD-PROG-011",
                    validate: { programDocument($0) != nil }) { ctx in
                guard let doc = programDocument(ctx.workspace), let conn = ctx.workspace.effectiveConnection(of: doc) else { throw CommandError.notConnected }
                let s = try await ctx.workspace.sessions.session(SessionKey(connectionID: conn, purpose: .main))
                let changed = try await ObjectAdmin.changedObjects(of: doc, in: s)
                if !changed.isEmpty {
                    doc.statusText = L10n.tr("⚠️ Obiekt zmieniony w bazie po wczytaniu: \(changed.joined(separator: ", ")) — porównaj ze źródłem w bazie przed kompilacją")
                }
                return CommandResult(value: .array(changed.map { .string($0) }))
            },
            command("prog.runBlock", L10n.tr("Uruchom blok w oknie testu"), .session, submenu: nil, effect: .modifiesDatabase,
                    summary: L10n.tr("Otwiera zaznaczony blok PL/SQL (albo całe okno) w oknie testu i wykonuje go z DBMS_OUTPUT."), feature: "PD-PROG-016",
                    validate: { programDocument($0) != nil }) { ctx in
                guard let doc = programDocument(ctx.workspace) else { return .ok }
                let ns = doc.text as NSString
                let sel = doc.selectedRange
                var block = sel.isEmpty ? doc.text : ns.substring(with: NSRange(location: min(sel.lowerBound, ns.length), length: min(sel.count, ns.length - min(sel.lowerBound, ns.length))))
                block = block.trimmingCharacters(in: .whitespacesAndNewlines)
                while block.hasSuffix("/") { block.removeLast(); block = block.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard block.range(of: #"(?is)^(declare|begin)\b"#, options: .regularExpression) != nil else {
                    throw CommandError.notAvailable(L10n.tr("Zaznacz blok anonimowy (DECLARE … BEGIN … END;)"))
                }
                let t = ctx.workspace.newDocument(.test, text: block)
                t.connectionID = doc.connectionID
                t.connectionPinned = doc.connectionPinned
                t.outputEnabled = true
                TestRunner.synchronize(t)
                _ = try await TestRunner.execute(t, in: ctx.workspace)
                return CommandResult(value: .array(t.output.map { .string($0) }))
            },
        ]
    }
}
