import Foundation
import PelikanDB

/// Komendy połączeń (UG 3, 19, 20). Argument `connection` = UUID definicji; bez argumentu — połączenie główne.
public enum ConnectionCommands {
    static let connectionParam = CommandParameter("connection", .string, L10n.tr("Identyfikator albo nazwa połączenia (domyślnie połączenie główne)"))

    @MainActor
    static func connectionID(_ ctx: CommandContext) throws -> UUID {
        if let s = ctx.arguments.string("connection") {
            if let id = UUID(uuidString: s), ctx.workspace.connections.connection(id) != nil { return id }
            // Także nazwa definicji (parametry startowe, skrypty) — bez rozróżniania wielkości liter.
            if let def = ctx.workspace.connections.connections.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return def.id }
            throw CommandError.invalidArgument("connection", L10n.tr("nieznane połączenie"))
        }
        guard let main = ctx.workspace.sessions.mainConnectionID else { throw CommandError.notConnected }
        return main
    }

    @MainActor
    public static var all: [Command] {
        [
            Command(CommandDescriptor(id: "session.logon", title: L10n.tr("Zaloguj…"), category: .session, mac: ["cmd+shift+l"],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Wybór połączenia i logowanie; połączenie staje się główne."), feature: "PD-CONN-002")) { ctx in
                ctx.ui?.showLogon()
                return .ok
            },
            Command(CommandDescriptor(id: "session.logoff", title: L10n.tr("Wyloguj połączenie główne"), category: .session,
                                      agent: .none, effect: .settings, summary: L10n.tr("Rozłącza wszystkie sesje połączenia głównego."),
                                      feature: "PD-CONN-018"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                guard let id = ctx.workspace.sessions.mainConnectionID else { return .ok }
                try await disconnect(ctx, id)
                ctx.workspace.sessions.setMainConnection(nil)
                return .ok
            },
            Command(CommandDescriptor(id: "connection.export", title: L10n.tr("Eksportuj definicje połączeń…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [CommandParameter("file", .string, L10n.tr("Plik JSON"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje definicje połączeń i foldery do pliku JSON — bez haseł (zostają w Pęku kluczy)."),
                                      feature: "PD-CONN-010")) { ctx in
                var url = ctx.arguments.string("file").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                if url == nil { url = await ctx.ui?.chooseSaveURL(suggestedName: "Pelikan-connections", fileExtension: "json") }
                guard let url else { throw CommandError.cancelledByUser }
                try ctx.workspace.connections.exportDefinitions().write(to: url, options: .atomic)
                return CommandResult(message: L10n.tr("Zapisano \(ctx.workspace.connections.connections.count) połączeń"), value: .string(url.path))
            },
            Command(CommandDescriptor(id: "connection.import", title: L10n.tr("Importuj definicje połączeń…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [CommandParameter("file", .string, L10n.tr("Plik JSON"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Dopisuje definicje połączeń z pliku JSON (hasła trzeba podać przy pierwszym połączeniu)."),
                                      feature: "PD-CONN-010")) { ctx in
                var url = ctx.arguments.string("file").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                if url == nil { url = await ctx.ui?.chooseFilesToOpen().first }
                guard let url else { throw CommandError.cancelledByUser }
                let data = try Data(contentsOf: url)
                // Tunel SSH i skrypt inicjalizacji działają przy każdym połączeniu — import tylko ze świadomą zgodą.
                let running = try ConnectionStore.definitionsRunningCode(in: data)
                if !running.isEmpty, let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Importować definicje z tunelem SSH albo skryptem inicjalizacji?"),
                                       message: L10n.tr("Połączenia \(running.joined(separator: ", ")) uruchamiają przy łączeniu ssh albo polecenia w bazie. Importuj tylko plik z zaufanego źródła."),
                                       buttons: [L10n.tr("Importuj"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                let n = try ctx.workspace.connections.importDefinitions(data)
                return CommandResult(message: L10n.tr("Zaimportowano połączeń: \(n)"), value: .int(Int64(n)))
            },
            Command(CommandDescriptor(id: "connection.new", title: L10n.tr("Nowe połączenie…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      agent: .none, effect: .settings, summary: L10n.tr("Definiuje nowe połączenie."), feature: "PD-CONN-004")) { ctx in
                ctx.ui?.showConnectionEditor(connectionID: nil)
                return .ok
            },
            Command(CommandDescriptor(id: "connection.edit", title: L10n.tr("Edytuj połączenie…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Zmienia definicję połączenia."), feature: "PD-CONN-004"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                ctx.ui?.showConnectionEditor(connectionID: try connectionID(ctx))
                return .ok
            },
            Command(CommandDescriptor(id: "connection.delete", title: L10n.tr("Usuń połączenie"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Usuwa definicję połączenia i jego hasło z Pęku kluczy."), inMenu: false, feature: "PD-CONN-004")) { ctx in
                let id = try connectionID(ctx)
                guard let def = ctx.workspace.connections.connection(id) else { return .ok }
                let answer = await ctx.ui?.ask(L10n.tr("Usunąć połączenie „\(def.displayName)”?"),
                                               message: L10n.tr("Definicja i zapisane hasło zostaną usunięte."), buttons: [L10n.tr("Usuń")])
                guard answer == 0 else { throw CommandError.cancelledByUser }
                try await disconnect(ctx, id)
                if ctx.workspace.sessions.mainConnectionID == id { ctx.workspace.sessions.setMainConnection(nil) }
                try ctx.workspace.connections.remove(id)
                return .ok
            },
            Command(CommandDescriptor(id: "connection.connectAsMain", title: L10n.tr("Połącz jako główne"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Łączy się i ustawia połączenie jako główne."), inMenu: false, feature: "PD-CONN-018")) { ctx in
                let id = try connectionID(ctx)
                let s = try await ctx.workspace.sessions.session(SessionKey(connectionID: id, purpose: .main))
                ctx.workspace.sessions.setMainConnection(id)
                if let msg = ctx.workspace.connections.connection(id)?.logonMessage, !msg.isEmpty {
                    _ = await ctx.ui?.ask(L10n.tr("Komunikat połączenia"), message: msg, buttons: [L10n.tr("OK")])
                }
                return CommandResult(message: L10n.tr("Połączono: \(s.info.server.banner.split(separator: "\n").first.map(String.init) ?? "")"))
            },
            Command(CommandDescriptor(id: "connection.connect", title: L10n.tr("Połącz"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Łączy się bez zmiany połączenia głównego."), inMenu: false, feature: "PD-CONN-022")) { ctx in
                let id = try connectionID(ctx)
                _ = try await ctx.workspace.sessions.session(SessionKey(connectionID: id, purpose: .main))
                return .ok
            },
            Command(CommandDescriptor(id: "connection.openWindow", title: L10n.tr("Nowe okno na połączeniu"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam, CommandParameter("kind", .string, L10n.tr("Typ okna: sql, program, test, command"),
                                                                                      allowed: ["sql", "program", "test", "command"])],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno wskazanego typu przypięte do połączenia (bez zmiany połączenia głównego)."),
                                      inMenu: false, feature: "PD-CONN-022")) { ctx in
                let id = try connectionID(ctx)
                let kind: DocumentKind = switch ctx.arguments.string("kind") { case "program": .program; case "test": .test; case "command": .command; default: .sql }
                let doc = ctx.workspace.newDocument(kind)
                doc.connectionID = id
                doc.connectionPinned = true
                return CommandResult(value: .string(doc.id.description))
            },
            Command(CommandDescriptor(id: "connection.showWindows", title: L10n.tr("Pokaż okna połączenia"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Aktywuje kolejne okno używające połączenia."), inMenu: false, feature: "PD-CONN-022")) { ctx in
                let id = try connectionID(ctx)
                let ws = ctx.workspace
                let docs = ws.documents.filter { ws.effectiveConnection(of: $0) == id }
                guard !docs.isEmpty else { return CommandResult(message: L10n.tr("Brak okien na tym połączeniu")) }
                let next = docs.firstIndex { $0.id == ws.activeDocumentID }.map { docs[($0 + 1) % docs.count] } ?? docs[0]
                ws.activate(next.id)
                return CommandResult(value: .int(Int64(docs.count)))
            },
            Command(CommandDescriptor(id: "connection.closeWindows", title: L10n.tr("Zamknij okna połączenia"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zamyka okna przypięte do połączenia (z pytaniem o niezapisane zmiany i otwarte transakcje)."),
                                      inMenu: false, feature: "PD-CONN-022")) { ctx in
                let id = try connectionID(ctx)
                let ws = ctx.workspace
                var closed = 0
                for d in ws.documents where ws.effectiveConnection(of: d) == id && d.connectionPinned && !d.isExecuting {
                    if d.isModified || d.transactionOpen, let ui = ctx.ui {
                        guard await ui.ask(L10n.tr("Zamknąć okno „\(d.fullTitle)”?"), message: L10n.tr("Okno ma niezapisane zmiany albo otwartą transakcję."),
                                           buttons: [L10n.tr("Zamknij"), L10n.tr("Pomiń")]) == 0 else { continue }
                    }
                    // Transakcja okna wycofywana zawsze (także bez interfejsu); nieudany ROLLBACK — okno zostaje.
                    if d.transactionOpen {
                        do { try await ws.endTransactions(of: [d], commit: false) } catch { continue }
                    }
                    // Sesje okna (tryb Multi) i debugera kończą się razem z oknem.
                    if ws.settings.sessionMode == .multi { await ws.sessions.close(ws.sessions.key(forDocument: d.id, connection: id)) }
                    await ws.sessions.close(ws.sessions.debuggerKey(document: d.id, connection: id))
                    ws.close(d.id)
                    closed += 1
                }
                return CommandResult(value: .int(Int64(closed)))
            },
            Command(CommandDescriptor(id: "connection.reconnectWindows", title: L10n.tr("Połącz ponownie okna połączenia"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Zamyka sesje okien bez otwartej transakcji; okna łączą się ponownie przy następnym wykonaniu."),
                                      inMenu: false, feature: "PD-CONN-022")) { ctx in
                let id = try connectionID(ctx)
                let ws = ctx.workspace
                var n = 0
                for d in ws.documents where ws.effectiveConnection(of: d) == id && !d.transactionOpen && !d.isExecuting {
                    let key = ws.sessions.key(forDocument: d.id, connection: id)
                    guard case .document = key.purpose, ws.sessions.existingSession(key) != nil else { continue }
                    await ws.sessions.close(key)
                    n += 1
                }
                return CommandResult(message: L10n.tr("Sesje do ponownego połączenia: \(n)"), value: .int(Int64(n)))
            },
            Command(CommandDescriptor(id: "connection.setCurrentSchema", title: L10n.tr("Ustaw bieżący schemat…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam, CommandParameter("schema", .string, required: true, L10n.tr("Schemat"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("ALTER SESSION SET CURRENT_SCHEMA w sesji głównej połączenia (Object Browser i nazwy bez schematu)."),
                                      inMenu: false, feature: "PD-CONN-022")) { ctx in
                let id = try connectionID(ctx)
                var schema = ctx.arguments.string("schema")
                if schema == nil { schema = await ctx.ui?.askText(L10n.tr("Bieżący schemat"), message: L10n.tr("Schemat"), defaultValue: "") }
                guard let schema, SessionManager.isSafeIdentifier(schema) else { throw CommandError.invalidArgument("schema", schema ?? "") }
                let s = try await ctx.workspace.sessions.session(SessionKey(connectionID: id, purpose: .main))
                _ = try await s.execute("ALTER SESSION SET CURRENT_SCHEMA = \(schema)")
                return CommandResult(value: .string(try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? schema))
            },
            Command(CommandDescriptor(id: "connection.disconnect", title: L10n.tr("Rozłącz"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Rozłącza wszystkie sesje połączenia."), inMenu: false, feature: "PD-CONN-022")) { ctx in
                try await disconnect(ctx, try connectionID(ctx))
                return .ok
            },
            Command(CommandDescriptor(id: "session.pinWindowConnection", title: L10n.tr("Przypnij połączenie okna"), category: .session,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Przypina połączenie bieżącego okna albo odpina je (UG 20.2); przypięte okno bez własnego połączenia dostaje połączenie główne."),
                                      inMenu: false, feature: "PD-CONN-019"),
                    validate: { $0.activeDocument != nil }) { ctx in
                guard let doc = ctx.workspace.activeDocument else { return .ok }
                doc.connectionPinned.toggle()
                if doc.connectionPinned, doc.connectionID == nil { doc.connectionID = ctx.workspace.sessions.mainConnectionID }
                return CommandResult(value: .bool(doc.connectionPinned))
            },
            Command(CommandDescriptor(id: "session.windowConnection", title: L10n.tr("Połączenie okna…"), category: .session,
                                      parameters: [CommandParameter("connection", .string, required: true,
                                                                    L10n.tr("Nazwa połączenia albo pusty tekst — połączenie główne"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zmienia połączenie bieżącego okna (UG 20.2); otwarta transakcja — pytanie o COMMIT/ROLLBACK."),
                                      inMenu: false, feature: "PD-CONN-019"),
                    validate: { $0.activeDocument != nil }) { ctx in
                guard let doc = ctx.workspace.activeDocument else { return .ok }
                let spec = ctx.arguments.string("connection") ?? ""
                var target: UUID?
                if !spec.isEmpty {
                    guard let def = ctx.workspace.connections.connections.first(where: {
                        $0.id.uuidString == spec || $0.name.caseInsensitiveCompare(spec) == .orderedSame
                            || $0.displayName.caseInsensitiveCompare(spec) == .orderedSame
                    }) else { throw CommandError.invalidArgument("connection", spec) }
                    target = def.id
                }
                guard target != doc.connectionID else { return .ok }
                if doc.transactionOpen {
                    let a = await ctx.ui?.ask(L10n.tr("Transakcja okna „\(doc.title)” jest otwarta"),
                                              message: L10n.tr("Zatwierdzić czy wycofać zmiany przed zmianą połączenia okna?"),
                                              buttons: [L10n.tr("Zatwierdź"), L10n.tr("Wycofaj"), L10n.tr("Anuluj")])
                    guard let a, a < 2 else { throw CommandError.cancelledByUser }
                    try await ctx.workspace.endTransactions(of: [doc], commit: a == 0)
                }
                if let old = ctx.workspace.effectiveConnection(of: doc), ctx.workspace.settings.sessionMode == .multi {
                    await ctx.workspace.sessions.close(ctx.workspace.sessions.key(forDocument: doc.id, connection: old))
                }
                doc.connectionID = target
                doc.isDisconnected = false
                doc.results.removeAll()
                return CommandResult(message: target.flatMap { ctx.workspace.connections.connection($0)?.displayName } ?? L10n.tr("Połączenie główne"))
            },
            Command(CommandDescriptor(id: "connection.newFolder", title: L10n.tr("Nowy folder…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [CommandParameter("name", .string, required: true, L10n.tr("Nazwa folderu")),
                                                   CommandParameter("parent", .string, L10n.tr("Folder nadrzędny"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Tworzy folder na liście połączeń."), inMenu: false, feature: "PD-CONN-003")) { ctx in
                guard let name = ctx.arguments.string("name"), !name.isEmpty else { throw CommandError.missingArgument("name") }
                let parent = ctx.arguments.string("parent").flatMap(UUID.init(uuidString:))
                try ctx.workspace.connections.upsert(folder: ConnectionFolder(name: name, parentID: parent))
                return .ok
            },
        ]
    }

    /// Rozłączenie z pytaniem o otwarte transakcje okien tego połączenia (D10).
    @MainActor
    static func disconnect(_ ctx: CommandContext, _ id: UUID) async throws {
        let open = ctx.workspace.documents.filter { $0.transactionOpen && ctx.workspace.effectiveConnection(of: $0) == id }
        if !open.isEmpty {
            switch ctx.workspace.settings.logoffWithOpenTransaction {
            case .ask:
                let a = await ctx.ui?.ask(L10n.tr("Niezatwierdzone zmiany"),
                                          message: L10n.tr("Okna z otwartą transakcją: \(open.map(\.fullTitle).joined(separator: ", ")). Co zrobić?"),
                                          buttons: [L10n.tr("Zatwierdź (COMMIT)"), L10n.tr("Wycofaj (ROLLBACK)")])
                guard let a else { throw CommandError.cancelledByUser }
                try await ctx.workspace.endTransactions(of: open, commit: a == 0)
            case .commit: try await ctx.workspace.endTransactions(of: open, commit: true)
            case .rollback: try await ctx.workspace.endTransactions(of: open, commit: false)
            }
        }
        await ctx.workspace.sessions.disconnect(id)
    }
}
