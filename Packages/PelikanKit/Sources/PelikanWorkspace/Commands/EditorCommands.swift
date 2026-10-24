import Foundation
import PelikanDB

/// Edytory obiektów (UG 9): definicja tabeli — nowa i istniejąca; dla agenta DDL zmian bez wykonania.
enum EditorCommands {
    /// „Nowy …” dla prostego edytora; obiekty schematu w schemacie bieżącym.
    @MainActor
    static func newSimple(_ kind: SimpleObjectEditor.Kind, id: String, title: String, feature: String) -> Command {
        Command(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .file, submenu: L10n.tr("Nowy"),
                                  agent: .none, effect: .uiState, summary: L10n.tr("Otwiera edytor nowego obiektu: \(title.replacingOccurrences(of: "…", with: ""))."),
                                  feature: feature),
                validate: { $0.metadata() != nil }) { ctx in
            guard let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
            var e = SimpleObjectEditor(kind: kind, owner: try await m.currentSchema())
            switch kind {
            case .sequence: e.values = ["name": "NOWA_SEKWENCJA", "start": "1", "increment": "1", "cache": "20"]
            case .user: e.values = ["name": "NOWY_UZYTKOWNIK", "roles": "CONNECT", "defaultTablespace": "USERS"]
            case .index: e.values = ["type": "NORMAL"]
            case .job: e.values = ["name": "NOWE_ZADANIE", "jobType": "PLSQL_BLOCK", "action": "begin\n  null;\nend;", "repeat": "FREQ=DAILY", "enabled": "N"]
            case .queue: e.values = ["name": "NOWA_KOLEJKA", "queueTable": "NOWA_KOLEJKA_TAB", "createTable": "Y", "payload": "RAW",
                                     "enqueue": "Y", "dequeue": "Y"]
            case .profile: e.values = ["name": "NOWY_PROFIL", "limits": "FAILED_LOGIN_ATTEMPTS:5"]
            case .view: e.values = ["name": "NOWY_WIDOK", "query": "select *\n  from dual"]
            default: break
            }
            ctx.ui?.showObjectEditor(e, connectionID: m.connectionID)
            return .ok
        }
    }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "file.newTable", title: L10n.tr("Tabela…"), category: .file, submenu: L10n.tr("Nowy"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera edytor definicji nowej tabeli w schemacie bieżącym."), feature: "PD-OED-001"),
                    validate: { $0.metadata() != nil }) { ctx in
                guard let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
                var d = TableDefinition(owner: try await m.currentSchema(), name: "NOWA_TABELA")
                d.columns = [TableDefinition.Column(name: "ID", type: "NUMBER", nullable: false)]
                d.keys = [TableDefinition.Key(name: "NOWA_TABELA_PK", kind: .primary, columns: ["ID"])]
                ctx.ui?.showTableEditor(d, original: nil, connectionID: m.connectionID)
                return .ok
            },
            newSimple(.sequence, id: "file.newSequence", title: L10n.tr("Sekwencja…"), feature: "PD-OED-008"),
            newSimple(.synonym, id: "file.newSynonym", title: L10n.tr("Synonim…"), feature: "PD-OED-008"),
            newSimple(.index, id: "file.newIndex", title: L10n.tr("Indeks…"), feature: "PD-OED-010"),
            newSimple(.user, id: "file.newUser", title: L10n.tr("Użytkownik…"), feature: "PD-OED-009"),
            newSimple(.role, id: "file.newRole", title: L10n.tr("Rola…"), feature: "PD-OED-009"),
            newSimple(.library, id: "file.newLibrary", title: L10n.tr("Biblioteka…"), feature: "PD-OED-008"),
            newSimple(.directory, id: "file.newDirectory", title: L10n.tr("Katalog…"), feature: "PD-OED-008"),
            newSimple(.job, id: "file.newJob", title: L10n.tr("Zadanie…"), feature: "PD-OED-008"),
            newSimple(.queue, id: "file.newQueue", title: L10n.tr("Kolejka…"), feature: "PD-OED-008"),
            newSimple(.profile, id: "file.newProfile", title: L10n.tr("Profil…"), feature: "PD-OED-009"),
            newSimple(.databaseLink, id: "file.newDatabaseLink", title: L10n.tr("Łącze bazy danych…"), feature: "PD-OED-009"),
            newSimple(.view, id: "file.newViewEditor", title: L10n.tr("Widok (edytor)…"), feature: "PD-OED-010"),
            Command(CommandDescriptor(id: "ob.viewEditor", title: L10n.tr("Edytor widoku"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams, agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera widok w edytorze formularza (zapytanie, FORCE, READ ONLY, CHECK OPTION, komentarz) z podglądem DDL."),
                                      feature: "PD-OED-010"),
                    validate: { $0.selectedObject?.type == .view }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                guard o.type == .view else { throw CommandError.notAvailable(L10n.tr("Edytor widoku dotyczy widoków")) }
                let e = try await SimpleObjectEditor.load(.view, owner: o.owner, name: o.name, metadata: m)
                ctx.ui?.showObjectEditor(e, connectionID: m.connectionID)
                return CommandResult(message: e.value("query"))
            },
            Command(CommandDescriptor(id: "file.newDomain", title: L10n.tr("Domena…"), category: .file, submenu: L10n.tr("Nowy"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno SQL z szablonem CREATE DOMAIN (23ai): typ, ograniczenie, wyświetlanie, adnotacje."),
                                      feature: "PD-OED-011")) { ctx in
                try await ctx.workspace.invoke("file.newFromTemplate", CommandArguments(["template": .string(TemplateLibrary.objectsFolder + "/" + L10n.tr("Domena"))]),
                                               invoker: ctx.invoker)
            },
            Command(CommandDescriptor(id: "file.newView", title: L10n.tr("Widok…"), category: .file, submenu: L10n.tr("Nowy"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno SQL z szablonem CREATE OR REPLACE VIEW."), feature: "PD-OED-010")) { ctx in
                try await ctx.workspace.invoke("file.newFromTemplate", CommandArguments(["template": .string(TemplateLibrary.objectsFolder + "/" + L10n.tr("Widok"))]),
                                               invoker: ctx.invoker)
            },
            Command(CommandDescriptor(id: "ob.test", title: L10n.tr("Testuj"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams + [
                                          CommandParameter("member", .string, L10n.tr("Podprogram pakietu")),
                                          CommandParameter("overload", .integer, L10n.tr("Numer przeciążenia")),
                                      ],
                                      agent: .full, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno testu z wywołaniem procedury lub funkcji (notacja nazwana) i zmiennymi parametrów."),
                                      feature: "PD-TEST-004"),
                    validate: { ws in ws.selectedObject.map { [.procedure, .function].contains($0.type) } ?? false }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                let member = ctx.arguments.string("member")
                let (text, vars) = try await TestRunner.script(for: o, member: member, overload: ctx.arguments.int("overload").map(Int.init), metadata: m)
                let doc = ctx.workspace.newDocument(.test, text: text)
                doc.testVariables = vars
                doc.customTitle = L10n.tr("Test \(member ?? o.name)").lowercased()
                return CommandResult(message: doc.fullTitle, value: .object(["document": .string(doc.id.description)]))
            },
            Command(CommandDescriptor(id: "ob.standardTest", title: L10n.tr("Test standardowy…"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams + [
                                          CommandParameter("name", .string, L10n.tr("Nazwa testu standardowego")),
                                          CommandParameter("member", .string, L10n.tr("Podprogram pakietu")),
                                      ],
                                      agent: .read, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno testu z testu standardowego (szablon z %CALL%) dla procedury lub funkcji."),
                                      feature: "PD-TEST-009"),
                    validate: { ws in ws.selectedObject.map { [.procedure, .function, .package].contains($0.type) } ?? false }) { ctx in
                let store = StandardTestStore(dataDirectory: ctx.workspace.dataDirectory)
                let names = store.names
                guard !names.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak testów standardowych — zapisz okno testu jako test standardowy")) }
                var name = ctx.arguments.string("name")
                if name == nil {
                    if names.count == 1 { name = names[0] }
                    else if let ui = ctx.ui, let i = await ui.ask(L10n.tr("Test standardowy"), message: L10n.tr("Wybierz test standardowy."), buttons: Array(names.prefix(8))) { name = names[i] }
                }
                guard let name else { throw CommandError.cancelledByUser }
                let (o, m) = try await ObjectCommands.target(ctx)
                let member = ctx.arguments.string("member")
                let (call, vars) = try await TestRunner.script(for: o, member: member, metadata: m)
                let (block, all) = StandardTestStore.apply(try store.load(name), call: call, variables: vars)
                let doc = ctx.workspace.newDocument(.test, text: block)
                doc.testVariables = all
                doc.customTitle = name + " — " + (member ?? o.name).lowercased()
                return CommandResult(message: doc.fullTitle, value: .object(["document": .string(doc.id.description)]))
            },
            Command(CommandDescriptor(id: "test.saveAsStandard", title: L10n.tr("Zapisz jako test standardowy…"), category: .debug,
                                      parameters: [CommandParameter("name", .string, L10n.tr("Nazwa testu standardowego"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Zapisuje okno testu jako szablon testu standardowego; %CALL% w bloku oznacza miejsce wywołania programu."),
                                      feature: "PD-TEST-009"),
                    validate: { $0.activeDocument?.kind == .test }) { ctx in
                guard let d = ctx.workspace.activeDocument, d.kind == .test else { return .ok }
                var name = ctx.arguments.string("name")
                if name == nil { name = await ctx.ui?.askText(L10n.tr("Test standardowy"), message: L10n.tr("Nazwa testu standardowego"), defaultValue: "") }
                guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError.cancelledByUser }
                try StandardTestStore(dataDirectory: ctx.workspace.dataDirectory).save(name, TestScriptFile(block: d.text, variables: d.testVariables))
                return CommandResult(message: name)
            },
            Command(CommandDescriptor(id: "test.trace", title: L10n.tr("Ślad DBMS_TRACE przy wykonaniu"), category: .debug,
                                      parameters: [CommandParameter("levels", .string, L10n.tr("Po przecinku: calls, exceptions, sql, lines (wszystkie) albo enabled-calls…; off — wyłączony"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zbiera ślad DBMS_TRACE (wywołania, wyjątki, SQL, linie) przy kolejnych wykonaniach okna testu — karta Ślad."),
                                      feature: "PD-OPT-007"),
                    validate: { $0.activeDocument?.kind == .test }) { ctx in
                guard let d = ctx.workspace.activeDocument, d.kind == .test else { return .ok }
                let raw = (ctx.arguments.string("levels") ?? (d.traceLevel == nil ? "calls,exceptions" : "off")).lowercased()
                guard raw != "off" else { d.traceLevel = nil; return CommandResult(message: L10n.tr("Ślad wyłączony")) }
                var level: PLSQLTrace.Level = []
                for p in raw.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                    switch p {
                    case "calls": level.insert(.allCalls)
                    case "enabled-calls": level.insert(.enabledCalls)
                    case "exceptions": level.insert(.allExceptions)
                    case "enabled-exceptions": level.insert(.enabledExceptions)
                    case "sql": level.insert(.allSQL)
                    case "lines": level.insert(.allLines)
                    case "enabled-lines": level.insert(.enabledLines)
                    default: throw CommandError.invalidArgument("levels", p)
                    }
                }
                d.traceLevel = level
                return CommandResult(message: L10n.tr("Ślad włączony"), value: .int(Int64(level.rawValue)))
            },
            Command(CommandDescriptor(id: "test.traceRuns", title: L10n.tr("Historia przebiegów DBMS_TRACE"), category: .debug,
                                      parameters: [CommandParameter("run", .integer, L10n.tr("Numer przebiegu do wczytania"))],
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Lista przebiegów DBMS_TRACE; z numerem — wczytuje zdarzenia przebiegu do karty Ślad okna testu."),
                                      feature: "PD-OPT-007"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                let ws = ctx.workspace
                guard let conn = ws.activeDocument.flatMap({ ws.effectiveConnection(of: $0) }) ?? ws.sessions.mainConnectionID else { throw CommandError.notConnected }
                let s = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("trace")))
                if let run = ctx.arguments.int("run"), let d = ws.activeDocument, d.kind == .test {
                    d.traceRun = Int(run)
                    d.traceEvents = try await PLSQLTrace.events(run: Int(run), in: s)
                    return CommandResult(value: .int(Int64(d.traceEvents.count)))
                }
                let runs = try await PLSQLTrace.runs(in: s)
                if ctx.invoker == .user {
                    let text = runs.isEmpty ? L10n.tr("Brak przebiegów.") : runs.map { "\($0.id)  \($0.date)  \($0.comment)" }.joined(separator: "\n")
                    ctx.ui?.showHTMLReport(title: L10n.tr("Historia przebiegów DBMS_TRACE"), html: PackCommands.html("DBMS_TRACE", text))
                }
                return CommandResult(value: .array(runs.map { .object(["run": .int(Int64($0.id)), "date": .string($0.date)]) }))
            },
            Command(CommandDescriptor(id: "debug.grantPrivileges", title: L10n.tr("Uprawnienia debugera…"), category: .debug,
                                      parameters: [CommandParameter("user", .string, L10n.tr("Użytkownik (domyślnie bieżący)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno SQL z poleceniami GRANT DEBUG CONNECT SESSION i DEBUG ANY PROCEDURE dla użytkownika (do wykonania przez administratora)."),
                                      feature: "PD-DBG-013")) { ctx in
                let ws = ctx.workspace
                var user = ctx.arguments.string("user")
                if user == nil, let m = ws.metadata() { user = try? await m.currentSchema() }
                guard let user, SessionManager.isSafeIdentifier(user) else { throw CommandError.invalidArgument("user", user ?? "") }
                let script = """
                    -- Uprawnienia debugera PL/SQL dla \(user.uppercased()) — wykonuje administrator (DBA).
                    grant debug connect session to \(user.uppercased());
                    grant debug any procedure to \(user.uppercased());
                    -- Węższa alternatywa dla DEBUG ANY PROCEDURE: grant debug on <schemat>.<obiekt> to \(user.uppercased());
                    """
                let doc = ws.newDocument(.sql, text: script)
                doc.customTitle = L10n.tr("uprawnienia debugera")
                return CommandResult(value: .string(script))
            },
            Command(CommandDescriptor(id: "test.profiler", title: L10n.tr("Profiler przy wykonaniu"), category: .debug,
                                      parameters: [CommandParameter("kind", .string, L10n.tr("lines (DBMS_PROFILER), hierarchical (DBMS_HPROF) albo off"),
                                                                    allowed: ["lines", "hierarchical", "off"])],
                                      agent: .full, effect: .uiState,
                                      summary: L10n.tr("Włącza profiler liniowy albo hierarchiczny dla kolejnych wykonań okna testu (raport w karcie Profiler)."),
                                      feature: "PD-OPT-005"),
                    validate: { $0.activeDocument?.kind == .test }) { ctx in
                guard let d = ctx.workspace.activeDocument, d.kind == .test else { return .ok }
                switch ctx.arguments.string("kind") {
                case "lines": d.profiler = .lines
                case "hierarchical": d.profiler = .hierarchical
                case "off": d.profiler = nil
                default: d.profiler = d.profiler == nil ? .lines : nil
                }
                return CommandResult(message: d.profiler.map { $0 == .lines ? L10n.tr("Profiler liniowy włączony") : L10n.tr("Profiler hierarchiczny włączony") }
                                     ?? L10n.tr("Profiler wyłączony"))
            },
            Command(CommandDescriptor(id: "test.saveAsSQLPlus", title: L10n.tr("Zapisz test jako skrypt SQL*Plus"), category: .file,
                                      agent: .full, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno poleceń ze skryptem SQL*Plus odpowiadającym oknu testu (VARIABLE, wartości, blok, PRINT)."),
                                      feature: "PD-TEST-005"),
                    validate: { $0.activeDocument?.kind == .test }) { ctx in
                guard let d = ctx.workspace.activeDocument, d.kind == .test else { return .ok }
                TestRunner.synchronize(d)
                let script = TestScriptFile(block: d.text, variables: d.testVariables).sqlPlusScript()
                let doc = ctx.workspace.newDocument(.command, text: script)
                return CommandResult(message: doc.fullTitle, value: .string(script))
            },
            Command(CommandDescriptor(id: "ob.editTable", title: L10n.tr("Edytuj definicję tabeli"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams, agent: .read, effect: .none,
                                      summary: L10n.tr("Otwiera edytor definicji tabeli (kolumny, klucze, warunki, indeksy); agent dostaje definicję jako DDL."),
                                      feature: "PD-OED-002"),
                    validate: { ws in ws.selectedObject?.type == .table }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                guard o.type == .table else { throw CommandError.notAvailable(L10n.tr("To nie jest tabela")) }
                let d = try await TableDDL.load(owner: o.owner, name: o.name, metadata: m)
                if ctx.invoker == .user { ctx.ui?.showTableEditor(d, original: d, connectionID: m.connectionID) }
                return CommandResult(value: .string(TableDDL.statements(from: nil, to: d).joined(separator: ";\n") + ";"))
            },
        ]
    }
}
