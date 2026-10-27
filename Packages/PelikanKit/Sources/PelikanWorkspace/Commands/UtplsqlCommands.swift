import Foundation
import PelikanDB
import PelikanSQL

/// utPLSQL (PROMPT §6): uruchamianie testów, pokrycie, wyniki. Agent uruchamia testy za zgodą (testy zmieniają dane
/// w transakcji wycofywanej przez utPLSQL) i dostaje podsumowanie z nieudanymi testami.
enum UtplsqlCommands {
    static let runParams = [
        CommandParameter("path", .string, L10n.tr("Ścieżka: schemat, schemat.pakiet[.procedura] albo schemat:suitepath (domyślnie bieżący użytkownik)")),
        CommandParameter("coverage", .boolean, L10n.tr("Zbieraj pokrycie kodu bieżącego schematu")),
    ]

    /// Instalacja/aktualizacja utPLSQL (UT-INS-002); agent — po zgodzie w oknie zgody, bez drugiego pytania.
    @MainActor
    static func install(_ ctx: CommandContext, connection conn: UUID) async throws -> CommandResult {
        let ws = ctx.workspace
        guard let def = ws.connections.connection(conn) else { throw CommandError.notConnected }
        guard [.development, .test].contains(def.environment) else {
            throw CommandError.notAvailable(L10n.tr("Instalacja utPLSQL jest dostępna tylko dla połączeń deweloperskich i testowych"))
        }
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: conn))
        let installed = await UtplsqlRunner.version(s)
        let owner = await UtplsqlInstaller.installedOwner(s) ?? (ctx.arguments.string("owner") ?? "UT3").uppercased()
        let release = try await UtplsqlInstaller.release(version: ctx.arguments.string("version"))
        let message = installed.map {
            L10n.tr("Zaktualizować utPLSQL \($0) do \(release.version) w schemacie \(owner) (połączenie \(def.name))? Obiekty utPLSQL zostaną usunięte i zainstalowane ponownie; potrzebne są uprawnienia SYSDBA albo DBA.")
        } ?? L10n.tr("Zainstalować utPLSQL \(release.version) w nowym schemacie \(owner) (połączenie \(def.name)) z publicznymi synonimami? Konto schematu dostanie losowe hasło i zostanie zablokowane; potrzebne są uprawnienia SYSDBA albo DBA.")
        if ctx.invoker == .user, let ui = ctx.ui {
            guard await ui.ask(L10n.tr("Instalacja utPLSQL"), message: message, buttons: [L10n.tr("Instaluj"), L10n.tr("Anuluj")]) == 0 else {
                throw CommandError.cancelledByUser
            }
        }
        let cache = (ws.dataDirectory ?? FileManager.default.temporaryDirectory).appendingPathComponent("utPLSQL", isDirectory: true)
        let source = try await UtplsqlInstaller.prepare(release, cache: cache)
        let doc = ws.newDocument(.command, text: "")
        doc.connectionID = conn
        doc.customTitle = L10n.tr("Instalacja utPLSQL \(release.version)")
        let steps = UtplsqlInstaller.script(owner: owner, upgrade: installed != nil,
                                            tablespace: ctx.arguments.string("tablespace") ?? "USERS")
        guard await UtplsqlInstaller.run(steps, source: source, engine: ws.sqlplusEngine(for: doc)) else {
            throw CommandError.notAvailable(L10n.tr("Instalacja utPLSQL nie powiodła się — szczegóły w oknie poleceń"))
        }
        let now = await UtplsqlRunner.version(s)
        return CommandResult(message: L10n.tr("Zainstalowano utPLSQL \(now ?? release.version)"), value: now.map { .string($0) } ?? .null)
    }

    /// Połączenie dla utPLSQL: aktywnego okna albo główne.
    @MainActor
    static func connection(_ ws: Workspace) -> UUID? {
        ws.activeDocument.flatMap { ws.effectiveConnection(of: $0) } ?? ws.sessions.mainConnectionID
    }

    /// Jednorazowe (na sesję aplikacji) ostrzeżenie przed pierwszym pokryciem (UT-COV-003): utPLSQL zbiera je przez
    /// DBMS_PROFILER/DBMS_PLSQL_CODE_COVERAGE, co wymaga uprawnień i zapisuje dane profilera w bazie.
    @MainActor
    static func confirmCoverage(_ ctx: CommandContext) async throws {
        guard ctx.invoker == .user, !ctx.workspace.coverageWarningShown, let ui = ctx.ui else { return }
        let choice = await ui.ask(L10n.tr("Pokrycie kodu"),
                                  message: L10n.tr("utPLSQL zbiera pokrycie przez profiler PL/SQL: wymaga uprawnień do DBMS_PROFILER i obiektów schematu UT3, zapisuje dane profilera w bazie i spowalnia testy. Kontynuować?"),
                                  buttons: [L10n.tr("Kontynuuj"), L10n.tr("Anuluj")])
        guard choice == 0 else { throw CommandError.cancelledByUser }
        ctx.workspace.coverageWarningShown = true
    }

    @MainActor
    static func run(_ ctx: CommandContext, paths: [String]?, coverage: Bool, schemes: [String] = [],
                    include: [String] = [], exclude: [String] = []) async throws -> CommandResult {
        let ws = ctx.workspace
        if coverage { try await confirmCoverage(ctx) }
        guard let conn = connection(ws), let m = ws.metadata(for: conn) else { throw CommandError.notConnected }
        let schema = try await m.currentSchema()
        let p = paths ?? [schema]
        let run = try await UtplsqlRunner.start(paths: p, coverageSchemes: coverage ? (schemes.isEmpty ? [schema] : schemes) : [],
                                                include: coverage ? include : [], exclude: coverage ? exclude : [],
                                                in: ws, connectionID: conn)
        if ctx.invoker == .user {
            ctx.ui?.showUtplsqlResults(run)
            return CommandResult(message: L10n.tr("Uruchomiono testy: \(p.joined(separator: ", "))"))
        }
        // Agent: czeka na koniec przebiegu (do 10 min) i dostaje podsumowanie.
        for _ in 0..<6000 where !run.finished { try await Task.sleep(for: .milliseconds(100)) }
        let failed = run.tests.filter { $0.status == .failure || $0.status == .error }
        return CommandResult(message: L10n.tr("utPLSQL: sukces \(run.counter.success), niepowodzenia \(run.counter.failure), błędy \(run.counter.error), wyłączone \(run.counter.disabled)"),
                             value: .object([
                                "success": .int(Int64(run.counter.success)), "failure": .int(Int64(run.counter.failure)),
                                "error": .int(Int64(run.counter.error)), "disabled": .int(Int64(run.counter.disabled)),
                                "failed": .array(failed.map { t in
                                    .object(["path": .string(t.id), "messages": .array((t.expectations.map(\.message) + (t.errorStack.isEmpty ? [] : [t.errorStack])).map { .string($0) })])
                                }),
                                "runError": run.failure.map { .string($0) } ?? .null,
                             ]))
    }

    /// Formularz opcji przebiegu (UT-RUN-003, UT-COV-001) — pola jak parametry `utplsql.runWithOptions`.
    @MainActor
    static func optionsForm(_ ui: any UIServices, document: Document, path: String) async throws -> [String: String] {
        func field(_ name: String, _ label: String, hint: String, value: String = "", checkbox: Bool = false) -> VariableRequest {
            var o = VariableOptions(name: label)
            o.hint = hint
            if checkbox { o.checkbox = ("true", "false") }
            return VariableRequest(name: name, kind: .substitution, options: o, value: .text(value))
        }
        let requests = [
            field("path", L10n.tr("Ścieżki testów"), hint: L10n.tr("schemat, schemat.pakiet[.procedura] albo schemat:suitepath; kilka po przecinku"), value: path),
            field("coverage", L10n.tr("Pokrycie kodu"), hint: L10n.tr("Zbieraj pokrycie przez profiler PL/SQL"), value: "false", checkbox: true),
            field("schemes", L10n.tr("Schematy pokrycia"), hint: L10n.tr("Puste — bieżący schemat")),
            field("include", L10n.tr("Uwzględnij obiekty"), hint: L10n.tr("np. emp_api, dept_api")),
            field("exclude", L10n.tr("Pomiń obiekty"), hint: L10n.tr("np. emp_api_test")),
        ]
        guard let answers = await ui.askVariables(requests, document: document) else { throw CommandError.cancelledByUser }
        var out: [String: String] = [:]
        for (k, v) in answers { if case .text(let s) = v { out[k] = s } }
        return out
    }

    /// Ścieżka utPLSQL dla pozycji kursora w oknie programu: procedura testowa pod kursorem albo cały pakiet.
    @MainActor
    static func editorPath(_ ws: Workspace) async -> String? {
        guard let doc = ws.activeDocument, doc.kind == .program else { return nil }
        let outline = PLSQLOutline.parse(doc.text)
        let path = PLSQLOutline.path(at: doc.selectedRange.lowerBound, in: outline)
        guard let unit = path.first, unit.kind == .packageBody || unit.kind == .package else { return nil }
        let owner = ProgramCompiler.units(in: doc.text).first { $0.name.uppercased() == unit.name.uppercased() }?.owner
        let schema = await (try? ws.metadata(for: ws.effectiveConnection(of: doc))?.currentSchema()) ?? ""
        let base = "\(owner ?? schema).\(unit.name)".lowercased()
        if path.count >= 2, [.procedure, .function].contains(path[1].kind) { return base + "." + path[1].name.lowercased() }
        // Kursor na deklaracji procedury w specyfikacji (bez ciała).
        if let decl = unit.children.first(where: { [.procedure, .function].contains($0.kind) && $0.range.contains(doc.selectedRange.lowerBound) }) {
            return base + "." + decl.name.lowercased()
        }
        return base
    }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "utplsql.runAll", title: L10n.tr("utPLSQL: uruchom wszystkie testy"), category: .tools, submenu: "utPLSQL",
                                      pd: ["ctrl+shift+u"], mac: ["cmd+shift+u"], agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia wszystkie testy utPLSQL bieżącego użytkownika; wyniki na żywo w oknie wyników."),
                                      feature: "UT-RUN-001"),
                    validate: { connection($0) != nil }) { ctx in
                try await run(ctx, paths: nil, coverage: false)
            },
            Command(CommandDescriptor(id: "utplsql.runPath", title: L10n.tr("utPLSQL: uruchom testy ze ścieżki…"), category: .tools, submenu: "utPLSQL",
                                      parameters: runParams, agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia testy ze ścieżki: schemat.pakiet.procedura albo schemat:suitepath (kilka po przecinku)."),
                                      feature: "UT-RUN-002")) { ctx in
                var path = ctx.arguments.string("path") ?? ""
                if path.isEmpty {
                    guard let p = await ctx.ui?.askText(L10n.tr("Ścieżka testów utPLSQL"), message: L10n.tr("schemat.pakiet[.procedura] albo schemat:suitepath; kilka po przecinku"),
                                                        defaultValue: await editorPath(ctx.workspace) ?? ""), !p.isEmpty else { throw CommandError.cancelledByUser }
                    path = p
                }
                let paths = path.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                return try await run(ctx, paths: paths, coverage: ctx.arguments.bool("coverage") ?? false)
            },
            Command(CommandDescriptor(id: "utplsql.runWithOptions", title: L10n.tr("utPLSQL: uruchom z opcjami…"), category: .tools, submenu: "utPLSQL",
                                      parameters: runParams + [
                                        CommandParameter("schemes", .string, L10n.tr("Schematy pokrycia po przecinku (domyślnie bieżący)")),
                                        CommandParameter("include", .string, L10n.tr("Obiekty uwzględniane w pokryciu po przecinku")),
                                        CommandParameter("exclude", .string, L10n.tr("Obiekty pomijane w pokryciu po przecinku")),
                                      ],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Okno opcji przebiegu: ścieżki testów, pokrycie, schematy pokrycia oraz obiekty uwzględniane i pomijane."),
                                      feature: "UT-RUN-003"),
                    validate: { connection($0) != nil }) { ctx in
                var a = ctx.arguments
                if ctx.invoker == .user, a.string("path") == nil, let ui = ctx.ui, let doc = ctx.workspace.activeDocument ?? ctx.workspace.documents.first {
                    let defaultPath = await editorPath(ctx.workspace) ?? ctx.workspace.selectedObject.map { o in
                        (o.type == .user ? o.name : "\(o.owner).\(o.name)").lowercased()
                    } ?? ""
                    let answers = try await optionsForm(ui, document: doc, path: defaultPath)
                    a = CommandArguments(answers.mapValues { $0 == "true" || $0 == "false" ? .bool($0 == "true") : .string($0) })
                }
                func list(_ k: String) -> [String] {
                    (a.string(k) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                let paths = list("path")
                return try await run(ctx, paths: paths.isEmpty ? nil : paths, coverage: a.bool("coverage") ?? false,
                                     schemes: list("schemes"), include: list("include"), exclude: list("exclude"))
            },
            Command(CommandDescriptor(id: "utplsql.coverage", title: L10n.tr("utPLSQL: testy z pokryciem kodu"), category: .tools, submenu: "utPLSQL",
                                      parameters: runParams, agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia testy z pokryciem kodu bieżącego schematu: raport HTML i linie pokryte na marginesie edytora. Pokrycie zbiera dane profilera."),
                                      feature: "UT-COV-001")) { ctx in
                let p = ctx.arguments.string("path").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                return try await run(ctx, paths: p, coverage: true)
            },
            Command(CommandDescriptor(id: "utplsql.runEditor", title: L10n.tr("utPLSQL: uruchom test pod kursorem"), category: .tools, submenu: "utPLSQL",
                                      pd: ["ctrl+alt+u"], mac: ["cmd+ctrl+u"], agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia test (procedurę pod kursorem) albo cały pakiet testowy z okna programu."),
                                      feature: "UT-RUN-004"),
                    validate: { $0.activeDocument?.kind == .program }) { ctx in
                guard let path = await editorPath(ctx.workspace) else {
                    throw CommandError.notAvailable(L10n.tr("Kursor nie jest w pakiecie testowym"))
                }
                return try await run(ctx, paths: [path], coverage: false)
            },
            Command(CommandDescriptor(id: "utplsql.rerunFailed", title: L10n.tr("utPLSQL: uruchom ponownie nieudane"), category: .tools, submenu: "utPLSQL",
                                      agent: .approval, effect: .modifiesDatabase, summary: L10n.tr("Uruchamia ponownie testy nieudane w ostatnim przebiegu."),
                                      feature: "UT-RUN-006"),
                    validate: { ws in ws.lastUtplsqlRun.map { $0.finished && !$0.failedPaths.isEmpty } ?? false }) { ctx in
                guard let failed = ctx.workspace.lastUtplsqlRun?.failedPaths, !failed.isEmpty else { return .ok }
                return try await run(ctx, paths: failed, coverage: false)
            },
            Command(CommandDescriptor(id: "utplsql.cancel", title: L10n.tr("utPLSQL: przerwij"), category: .tools, submenu: "utPLSQL",
                                      agent: .full, effect: .uiState, summary: L10n.tr("Przerywa trwający przebieg testów."), feature: "UT-RUN-006"),
                    validate: { ws in ws.lastUtplsqlRun.map { !$0.finished } ?? false }) { ctx in
                if let r = ctx.workspace.lastUtplsqlRun { UtplsqlRunner.cancel(r) }
                return .ok
            },
            Command(CommandDescriptor(id: "utplsql.version", title: L10n.tr("utPLSQL: wersja w bazie"), category: .tools, submenu: "utPLSQL",
                                      agent: .read, effect: .none, summary: L10n.tr("Wersja utPLSQL zainstalowanego w bazie połączenia (ut_runner.version)."),
                                      feature: "UT-INS-001"),
                    validate: { connection($0) != nil }) { ctx in
                guard let conn = connection(ctx.workspace) else { throw CommandError.notConnected }
                let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: conn))
                let v = await UtplsqlRunner.version(s)
                return CommandResult(message: v.map { L10n.tr("utPLSQL \($0)") } ?? L10n.tr("utPLSQL nie jest zainstalowany w tej bazie"), value: v.map { .string($0) } ?? .null)
            },
            Command(CommandDescriptor(id: "utplsql.install", title: L10n.tr("utPLSQL: instaluj lub aktualizuj…"), category: .tools, submenu: "utPLSQL",
                                      parameters: [CommandParameter("version", .string, L10n.tr("Znacznik wydania (domyślnie najnowsze)")),
                                                   CommandParameter("owner", .string, L10n.tr("Schemat utPLSQL przy nowej instalacji (domyślnie UT3)")),
                                                   CommandParameter("tablespace", .string, L10n.tr("Przestrzeń tabel schematu (domyślnie USERS)"))],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Pobiera oficjalne wydanie utPLSQL (z sumą kontrolną) i instaluje je albo aktualizuje w oknie poleceń — tylko dla połączeń deweloperskich i testowych, po potwierdzeniu."),
                                      feature: "UT-INS-002"),
                    validate: { connection($0) != nil }) { ctx in
                guard let conn = connection(ctx.workspace) else { throw CommandError.notConnected }
                return try await install(ctx, connection: conn)
            },
            Command(CommandDescriptor(id: "utplsql.explorer", title: L10n.tr("Eksplorator testów utPLSQL"), category: .view,
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Drzewo suit, kontekstów i testów bieżącego użytkownika (ut_runner.get_suites_info) z ostatnim wynikiem."),
                                      feature: "UT-EXP-001"),
                    validate: { connection($0) != nil }) { ctx in
                guard let m = ctx.workspace.metadata(for: connection(ctx.workspace)) else { throw CommandError.notConnected }
                if ctx.invoker == .user { ctx.ui?.showTestExplorer(); return .ok }
                let items = try await UtplsqlExplorer.load(owner: try await m.currentSchema(), metadata: m)
                func flat(_ n: [UtSuiteItem]) -> [UtSuiteItem] { n.flatMap { [$0] + flat($0.children ?? []) } }
                return CommandResult(value: .array(flat(items).filter { $0.kind == .test }.map { .string($0.runPath) }))
            },
            Command(CommandDescriptor(id: "utplsql.generateTest", title: L10n.tr("utPLSQL: generuj pakiet testowy"), category: .tools, submenu: "utPLSQL",
                                      parameters: ObjectCommands.objectParams, agent: .full, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno programu ze szkieletem pakietu testowego (suita, test na każdą procedurę i funkcję) dla pakietu."),
                                      feature: "UT-GEN-001"),
                    validate: { ws in ws.selectedObject?.type == .package || ws.activeDocument?.kind == .program }) { ctx in
                let ws = ctx.workspace
                var name: String?, owner: String?, spec: String?
                if ctx.arguments.string("object") == nil, let doc = ws.activeDocument, doc.kind == .program,
                   let u = ProgramCompiler.units(in: doc.text).first(where: { $0.type == .package }) {
                    name = u.name; owner = u.owner; spec = u.text
                } else {
                    let (o, m) = try await ObjectCommands.target(ctx)
                    guard o.type == .package || o.type == .packageBody else { throw CommandError.notAvailable(L10n.tr("Wybierz pakiet")) }
                    name = o.name; owner = o.owner
                    spec = try await m.source(of: DBObject(owner: o.owner, name: o.name, type: .package))
                }
                guard let name, let spec else { throw CommandError.notAvailable(L10n.tr("Brak specyfikacji pakietu")) }
                let text = UtplsqlExplorer.skeleton(for: name, owner: owner, specification: spec)
                let doc = ws.newDocument(.program, text: text)
                return CommandResult(message: doc.fullTitle, value: .string(text))
            },
            Command(CommandDescriptor(id: "utplsql.toggleTest", title: L10n.tr("utPLSQL: przejdź do testu / testowanego pakietu"), category: .tools, submenu: "utPLSQL",
                                      pd: ["ctrl+shift+t"], mac: ["cmd+ctrl+t"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Z pakietu otwiera jego pakiet testowy (test_nazwa albo zależność), z pakietu testowego — testowany pakiet."),
                                      feature: "UT-NAV-001"),
                    validate: { $0.activeDocument?.kind == .program }) { ctx in
                let ws = ctx.workspace
                guard let doc = ws.activeDocument, let u = ProgramCompiler.units(in: doc.text).first,
                      let m = ws.metadata(for: ws.effectiveConnection(of: doc)) else { throw CommandError.notConnected }
                var owner = u.owner ?? ""
                if owner.isEmpty { owner = try await m.currentSchema() }
                guard let o = try await UtplsqlExplorer.counterpart(of: u.name, owner: owner, metadata: m) else {
                    throw CommandError.notAvailable(L10n.tr("Nie znaleziono pakietu testowego ani testowanego dla \(u.name)"))
                }
                try await ws.openObject(o)
                return CommandResult(message: "\(o.owner).\(o.name)")
            },
            Command(CommandDescriptor(id: "utplsql.export", title: L10n.tr("utPLSQL: eksport wyników…"), category: .tools, submenu: "utPLSQL",
                                      parameters: runParams + [CommandParameter("format", .string, required: true, L10n.tr("Format wyniku albo pokrycia"),
                                                                                 allowed: UtplsqlReportFormat.allCases.map(\.rawValue))],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia testy z reporterem JUnit, Sonar, TeamCity, TAP albo pokryciem Cobertura/Sonar/HTML i zapisuje wynik do pliku (agent dostaje tekst)."),
                                      feature: "UT-CI-001")) { ctx in
                let ws = ctx.workspace
                guard let conn = connection(ws), let m = ws.metadata(for: conn) else { throw CommandError.notConnected }
                guard let format = UtplsqlReportFormat(rawValue: ctx.arguments.string("format") ?? "") else {
                    throw CommandError.invalidArgument("format", UtplsqlReportFormat.allCases.map(\.rawValue).joined(separator: ", "))
                }
                if format.isCoverage { try await confirmCoverage(ctx) }
                let schema = try await m.currentSchema()
                let paths = ctx.arguments.string("path").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? [schema]
                let text = try await UtplsqlRunner.report(paths: paths, format: format, coverageSchemes: [schema], in: ws, connectionID: conn)
                if ctx.invoker == .user, let ui = ctx.ui {
                    _ = await ui.saveFile(suggestedName: "utplsql-\(format.rawValue)", fileExtension: format.fileExtension, data: Data(text.utf8))
                    return CommandResult(message: L10n.tr("Wyeksportowano: \(format.rawValue)"))
                }
                return CommandResult(value: .string(text))
            },
            Command(CommandDescriptor(id: "utplsql.cliScript", title: L10n.tr("utPLSQL: skrypt dla wiersza poleceń"), category: .tools, submenu: "utPLSQL",
                                      parameters: [runParams[0]], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Otwiera skrypt SQL*Plus/SQLcl uruchamiający te same testy z wynikiem JUnit oraz skrypt powłoki (bez hasła)."),
                                      feature: "UT-CI-001")) { ctx in
                let ws = ctx.workspace
                guard let conn = connection(ws), let def = ws.connections.connection(conn), let m = ws.metadata(for: conn) else { throw CommandError.notConnected }
                let schema = try await m.currentSchema()
                let paths = ctx.arguments.string("path").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? [schema]
                // Łańcuch połączenia z definicji (alias albo EZConnect); hasła w skrypcie nie ma.
                let (sql, shell) = UtplsqlRunner.cliScript(paths: paths, user: def.target.user, connectString: def.target.connectString)
                let doc = ws.newDocument(.command, text: sql + "\n\n-- utplsql-run.sh:\n" + shell.split(separator: "\n", omittingEmptySubsequences: false).map { "-- " + $0 }.joined(separator: "\n"))
                doc.customTitle = "utplsql-run.sql"
                return CommandResult(message: doc.fullTitle, value: .object(["sql": .string(sql), "shell": .string(shell)]))
            },
            Command(CommandDescriptor(id: "utplsql.debugTest", title: L10n.tr("utPLSQL: debuguj test pod kursorem"), category: .debug,
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Okno testu z ut.run dla testu pod kursorem, punkt przerwania w procedurze testowej i start debugera."),
                                      feature: "UT-RUN-007"),
                    validate: { $0.activeDocument?.kind == .program }) { ctx in
                let ws = ctx.workspace
                guard let path = await editorPath(ws), let src = ws.activeDocument else {
                    throw CommandError.notAvailable(L10n.tr("Kursor nie jest w pakiecie testowym"))
                }
                let parts = path.split(separator: ".").map(String.init)
                // Punkt przerwania w pierwszej linii ciała procedury testowej (linia w źródle ciała pakietu).
                if parts.count == 3, let body = ProgramCompiler.units(in: src.text).first(where: { $0.type == .packageBody }) {
                    let lines = body.text.components(separatedBy: "\n")
                    if let i = lines.firstIndex(where: { $0.lowercased().contains("procedure \(parts[2])") }) {
                        let begin = lines[i...].firstIndex { $0.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix("begin") } ?? i
                        ws.breakpoints.append(Breakpoint(owner: parts[0].uppercased(), unit: parts[1].uppercased(), type: .packageBody, line: begin + 2))
                    }
                }
                let doc = ws.newDocument(.test, text: "begin\n  ut.run('\(path)');\nend;")
                let d = ws.debugger(for: doc)
                ctx.ui?.showDebugger(d, document: doc)
                try await d.start()
                try await d.step(.run)
                ws.showDebugLocation(d, testDocument: doc)
                return .ok
            },
            Command(CommandDescriptor(id: "ob.utplsqlRun", title: L10n.tr("Uruchom testy utPLSQL"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams + [CommandParameter("coverage", .boolean, L10n.tr("Z pokryciem kodu"))],
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Testy utPLSQL zaznaczonego pakietu, procedury albo użytkownika (opcjonalnie z pokryciem)."),
                                      feature: "UT-RUN-003"),
                    validate: { ws in ws.selectedObject.map { [.package, .packageBody, .procedure, .user].contains($0.type) } ?? false }) { ctx in
                let (o, _) = try await ObjectCommands.target(ctx)
                let path = o.type == .user ? o.name : "\(o.owner).\(o.name)"
                return try await run(ctx, paths: [path.lowercased()], coverage: ctx.arguments.bool("coverage") ?? false)
            },
        ]
    }
}

extension Workspace {
    /// Pokrycie z ostatniego przebiegu utPLSQL dla jednostek okna programu: linie dokumentu (od 1) pokryte i niepokryte.
    public func coverageLines(in doc: Document) -> (covered: Set<Int>, uncovered: Set<Int>) {
        let d = coverageDetail(in: doc)
        return (d.covered, d.uncovered)
    }

    /// Tekst paska stanu: procent pokrycia jednostek okna i ich schematu z ostatniego przebiegu (UT-COV-002).
    public func coverageStatus(in doc: Document) -> String? {
        let d = coverageDetail(in: doc)
        guard let o = d.objectPercent else { return nil }
        let schema = d.schemaPercent.map { L10n.tr(" (schemat \(String(format: "%.0f", $0))%)") } ?? ""
        return L10n.tr("Pokrycie \(String(format: "%.0f", o))%") + schema
    }

    /// Pokrycie okna programu: linie (z częściowo pokrytymi) i procent jednostek okna oraz ich schematu (UT-COV-002).
    public func coverageDetail(in doc: Document) -> (covered: Set<Int>, uncovered: Set<Int>, partial: Set<Int>, objectPercent: Double?, schemaPercent: Double?) {
        guard doc.kind == .program, let cov = lastUtplsqlRun?.coverage, !cov.isEmpty else { return ([], [], [], nil, nil) }
        var covered = Set<Int>(), uncovered = Set<Int>(), partial = Set<Int>()
        var owners = Set<String>()
        let schema = sessions.connectedSchema(effectiveConnection(of: doc))
        for u in doc.programUnits {
            let key = "\(u.type.rawValue) \(u.owner ?? schema ?? "").\(u.name)".uppercased()
            // Klucz raportu: „TYP WŁAŚCICIEL.NAZWA” — typ porównywany dokładnie (PACKAGE ≠ PACKAGE BODY).
            let match = cov.first { k, _ in
                guard let space = k.lastIndex(of: " ") else { return false }
                return String(k[..<space]) == u.type.rawValue && k[k.index(after: space)...].hasSuffix(".\(u.name.uppercased())")
            }
            guard let lines = cov[key] ?? match?.value else { continue }
            covered.formUnion(lines.covered.map { u.line + $0 })
            uncovered.formUnion(lines.uncovered.map { u.line + $0 })
            partial.formUnion(lines.partial.map { u.line + $0 })
            if let k = cov[key] != nil ? key : match?.key, let space = k.lastIndex(of: " "), let dot = k[space...].firstIndex(of: ".") {
                owners.insert(String(k[k.index(after: space)..<dot]))
            }
        }
        func percent(_ c: Int, _ u: Int) -> Double? { c + u == 0 ? nil : Double(c) * 100 / Double(c + u) }
        let schemaLines = cov.filter { k, _ in owners.contains { k.contains(" \($0).") } }.values
        return (covered, uncovered, partial, percent(covered.count, uncovered.count),
                percent(schemaLines.map(\.covered.count).reduce(0, +), schemaLines.map(\.uncovered.count).reduce(0, +)))
    }
}
