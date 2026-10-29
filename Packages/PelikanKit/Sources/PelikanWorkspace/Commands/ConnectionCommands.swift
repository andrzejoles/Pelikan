import Foundation
import PelikanDB
import PelikanLog

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

    /// Folder listy połączeń z argumentu: identyfikator albo nazwa (bez wielkości liter).
    @MainActor
    static func folderID(_ ctx: CommandContext, _ spec: String) throws -> UUID {
        let folders = ctx.workspace.connections.folders
        if let match = UUID(uuidString: spec).flatMap({ u in folders.first { $0.id == u } })
            ?? folders.first(where: { $0.name.caseInsensitiveCompare(spec) == .orderedSame }) { return match.id }
        throw CommandError.invalidArgument("folder", L10n.tr("nieznany folder"))
    }

    /// Ścieżka folderu w liście wyboru („Produkcja / Klienci”).
    @MainActor
    static func folderPath(_ store: ConnectionStore, _ folder: ConnectionFolder) -> String {
        var names = [folder.name]
        var parent = folder.parentID
        var seen: Set<UUID> = [folder.id]
        while let p = parent, seen.insert(p).inserted, let f = store.folders.first(where: { $0.id == p }) {
            names.insert(f.name, at: 0)
            parent = f.parentID
        }
        return names.joined(separator: " / ")
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
                                      summary: L10n.tr("Dopisuje definicje połączeń z pliku JSON. Plik eksportu z hasłami: hasła trafiają do Pęku kluczy, a plik jest usuwany po imporcie; bez haseł — trzeba je podać przy pierwszym połączeniu."),
                                      feature: "PD-CONN-010")) { ctx in
                var url = ctx.arguments.string("file").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                if url == nil { url = await ctx.ui?.chooseFilesToOpen().first }
                guard let url else { throw CommandError.cancelledByUser }
                let data = try Data(contentsOf: url)
                // Plik z hasłami (D186): zaszyfrowane — fraza; po imporcie plik jest usuwany.
                let envelope = try ConnectionTransfer.envelope(in: data)
                var secrets: [String: ConnectionSecrets] = [:]
                if let envelope {
                    var passphrase: String?
                    if envelope.mode == .encrypted {
                        passphrase = await ctx.ui?.askSecret(L10n.tr("Fraza pliku połączeń"),
                                                             message: L10n.tr("Hasła w pliku są zaszyfrowane. Podaj frazę użytą przy eksporcie."), confirm: false)
                        guard passphrase != nil else { throw CommandError.cancelledByUser }
                    }
                    // PBKDF2 (setki tysięcy iteracji) poza wątkiem głównym — interfejs nie zamiera.
                    let phrase = passphrase
                    secrets = try await Task.detached(priority: .userInitiated) {
                        try ConnectionTransfer.open(envelope, passphrase: phrase, definitions: data)
                    }.value
                }
                // Tunel SSH i skrypt inicjalizacji działają przy każdym połączeniu — import tylko ze świadomą zgodą.
                let running = try ConnectionStore.definitionsRunningCode(in: data)
                if !running.isEmpty, let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Importować definicje z tunelem SSH albo skryptem inicjalizacji?"),
                                       message: L10n.tr("Połączenia \(running.joined(separator: ", ")) uruchamiają przy łączeniu ssh albo polecenia w bazie. Importuj tylko plik z zaufanego źródła."),
                                       buttons: [L10n.tr("Importuj"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                let n = try ctx.workspace.connections.importDefinitions(data, secrets: secrets)
                guard envelope != nil else { return CommandResult(message: L10n.tr("Zaimportowano połączeń: \(n)"), value: .int(Int64(n))) }
                Log.connection.info("Import połączeń z hasłami: \(n, privacy: .public) definicji, \(secrets.count, privacy: .public) z hasłami")
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    throw CommandError.notAvailable(L10n.tr("Zaimportowano połączeń: \(n), hasła zapisano w Pęku kluczy, ale pliku z hasłami nie udało się usunąć — usuń go ręcznie: \(error.localizedDescription)"))
                }
                return CommandResult(message: L10n.tr("Zaimportowano połączeń: \(n); hasła zapisano w Pęku kluczy, plik z hasłami usunięto"), value: .int(Int64(n)))
            },
            Command(CommandDescriptor(id: "connection.exportWithPasswords", title: L10n.tr("Eksportuj połączenia z hasłami…"), category: .session,
                                      submenu: L10n.tr("Połączenia"),
                                      parameters: [CommandParameter("file", .string, L10n.tr("Plik JSON")),
                                                   CommandParameter("mode", .string, L10n.tr("Hasła: encrypted — zaszyfrowane frazą, plain — jawnym tekstem"),
                                                                    allowed: ["encrypted", "plain"])],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje definicje połączeń z hasłami (bazy i tunelu SSH) — zaszyfrowanymi frazą albo jawnym tekstem — po uwierzytelnieniu właściciela Maca."),
                                      feature: "PD-CONN-010")) { ctx in
                try await exportWithPasswords(ctx)
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
            Command(CommandDescriptor(id: "connection.duplicate", title: L10n.tr("Duplikuj połączenie…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam, CommandParameter("name", .string, L10n.tr("Nazwa kopii (bez argumentu — pytanie)"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Tworzy kopię definicji połączenia pod inną nazwą, w tym samym folderze, z zapisanymi hasłami."),
                                      feature: "PD-CONN-004"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                let id = try connectionID(ctx)
                guard let def = ctx.workspace.connections.connection(id) else { return .ok }
                var name = ctx.arguments.string("name")
                if name == nil {
                    let taken = Set(ctx.workspace.connections.connections.map { $0.displayName.lowercased() })
                    let candidates = [L10n.tr("\(def.displayName) (kopia)")] + (2...99).map { L10n.tr("\(def.displayName) (kopia \($0))") }
                    name = await ctx.ui?.askText(L10n.tr("Duplikuj połączenie"), message: L10n.tr("Nazwa kopii połączenia „\(def.displayName)”:"),
                                                 defaultValue: candidates.first { !taken.contains($0.lowercased()) } ?? "")
                    guard name != nil else { throw CommandError.cancelledByUser }
                }
                let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw CommandError.invalidArgument("name", L10n.tr("pusta nazwa")) }
                let copy = try ctx.workspace.connections.duplicate(id, name: trimmed)
                Log.connection.info("Skopiowano połączenie \(def.displayName, privacy: .hash) jako \(copy.displayName, privacy: .hash)")
                return CommandResult(value: .string(copy.id.uuidString))
            },
            Command(CommandDescriptor(id: "connection.moveToFolder", title: L10n.tr("Przenieś połączenie do folderu"), category: .session,
                                      submenu: L10n.tr("Połączenia"),
                                      parameters: [CommandParameter("connection", .string, required: true, L10n.tr("Identyfikator albo nazwa połączenia")),
                                                   CommandParameter("folder", .string, L10n.tr("Identyfikator albo nazwa folderu (bez argumentu — poziom główny listy)"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Przenosi definicję połączenia do folderu listy połączeń (także przeciągnięciem myszą)."),
                                      inMenu: false, feature: "PD-CONN-003")) { ctx in
                let id = try connectionID(ctx)
                var folder: UUID?
                if let f = ctx.arguments.string("folder"), !f.isEmpty { folder = try folderID(ctx, f) }
                try ctx.workspace.connections.move(id, to: folder)
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
                // Pomijane sesje zajęte: wykonanie w toku albo otwarty kursor wyniku (dociąganie wierszy).
                let busy = ws.busySessionKeys
                for d in ws.documents where ws.effectiveConnection(of: d) == id && !d.transactionOpen && !d.isExecuting {
                    let key = ws.sessions.key(forDocument: d.id, connection: id)
                    guard case .document = key.purpose, !busy.contains(key), ws.sessions.existingSession(key) != nil else { continue }
                    await ws.sessions.close(key)
                    n += 1
                }
                return CommandResult(message: L10n.tr("Sesje do ponownego połączenia: \(n)"), value: .int(Int64(n)))
            },
            Command(CommandDescriptor(id: "connection.setCurrentSchema", title: L10n.tr("Ustaw bieżący schemat…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam, CommandParameter("schema", .string, required: true, L10n.tr("Schemat"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("ALTER SESSION SET CURRENT_SCHEMA w sesji głównej połączenia (Przeglądarka obiektów i nazwy bez schematu)."),
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
                // Zmiana połączenia zamyka sesję okna — trwające wykonanie trzeba najpierw przerwać (jak przy zamknięciu okna).
                if doc.isExecuting { throw CommandError.notAvailable(L10n.tr("Okno „\(doc.title)” wykonuje polecenie — najpierw przerwij wykonanie.")) }
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
                                      parameters: [CommandParameter("name", .string, L10n.tr("Nazwa folderu (bez argumentu — pytanie o nazwę)")),
                                                   CommandParameter("parent", .string, L10n.tr("Folder nadrzędny"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Tworzy folder na liście połączeń."), inMenu: false, feature: "PD-CONN-003")) { ctx in
                var name = ctx.arguments.string("name")
                if name == nil, let ui = ctx.askingUI {
                    // Pusta nazwa w oknie — rezygnacja (jak Anuluj).
                    guard let n = await ui.askText(L10n.tr("Nowy folder"), message: L10n.tr("Nazwa folderu na liście połączeń"), defaultValue: "")?
                        .trimmingCharacters(in: .whitespaces), !n.isEmpty else {
                        throw CommandError.cancelledByUser
                    }
                    name = n
                }
                guard let name, !name.isEmpty else { throw CommandError.missingArgument("name") }
                let parent = ctx.arguments.string("parent").flatMap(UUID.init(uuidString:))
                try ctx.workspace.connections.upsert(folder: ConnectionFolder(name: name, parentID: parent))
                return .ok
            },
            // Tylko pusty folder (D204): bez połączeń i podfolderów nic nie znika, więc bez pytania potwierdzającego.
            Command(CommandDescriptor(id: "connection.deleteFolder", title: L10n.tr("Usuń folder"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [CommandParameter("folder", .string, L10n.tr("Identyfikator albo nazwa folderu (bez argumentu — wybór z listy folderów)"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Usuwa pusty folder z listy połączeń; folder z połączeniami albo podfolderami zostaje — najpierw je przenieś albo usuń."),
                                      inMenu: false, feature: "PD-CONN-003")) { ctx in
                let store = ctx.workspace.connections
                var spec = ctx.arguments.string("folder")
                if spec == nil, ctx.askingUI != nil {
                    guard !store.folders.isEmpty else { throw CommandError.notAvailable(L10n.tr("Lista połączeń nie ma folderów")) }
                    let options = store.folders.map { (label: folderPath(store, $0), value: $0.id.uuidString) }
                        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                    spec = try await ctx.choose(L10n.tr("Usuń folder"), options)
                }
                guard let spec, !spec.isEmpty else { throw CommandError.missingArgument("folder") }
                // „Ostatnie” to folder tworzony automatycznie, nie folder użytkownika (chyba że użytkownik ma folder o tej nazwie).
                let isRecent = [L10n.tr("Ostatnie"), "recent"].contains { $0.caseInsensitiveCompare(spec) == .orderedSame }
                if isRecent, !store.folders.contains(where: { $0.name.caseInsensitiveCompare(spec) == .orderedSame }) {
                    throw CommandError.notAvailable(L10n.tr("Folder „Ostatnie” jest tworzony automatycznie z ostatnio używanych połączeń — nie można go usunąć."))
                }
                let id = try folderID(ctx, spec)
                let name = store.folders.first { $0.id == id }?.name ?? spec
                try store.removeEmpty(folder: id)
                Log.connection.info("Usunięto pusty folder połączeń \(name, privacy: .hash)")
                return CommandResult(message: L10n.tr("Usunięto folder „\(name)”"), resolvedArguments: CommandArguments(["folder": .string(id.uuidString)]))
            },
        ]
    }

    /// Eksport z hasłami (D186): tylko użytkownik, uwierzytelnienie właściciela Maca (Touch ID albo hasło) zawsze,
    /// tryb jawny po dodatkowym ostrzeżeniu; fraza tylko z okna (nigdy z argumentów); plik z prawami 0600.
    @MainActor
    static func exportWithPasswords(_ ctx: CommandContext) async throws -> CommandResult {
        guard ctx.invoker == .user, let ui = ctx.ui else { throw CommandError.notAvailable(L10n.tr("Eksport haseł tylko przez użytkownika")) }
        var mode = ctx.arguments.string("mode").flatMap(ConnectionTransfer.Mode.init(rawValue:))
        if mode == nil {
            let a = await ui.ask(L10n.tr("Eksport połączeń z hasłami"),
                                 message: L10n.tr("Jak zapisać hasła w pliku? Zaszyfrowane wymagają frazy przy imporcie; jawne może odczytać każdy, kto ma plik."),
                                 buttons: [L10n.tr("Zaszyfrowane frazą"), L10n.tr("Jawnym tekstem"), L10n.tr("Anuluj")])
            guard let a, a < 2 else { throw CommandError.cancelledByUser }
            mode = a == 0 ? .encrypted : .plain
        }
        guard let mode else { throw CommandError.cancelledByUser }
        if mode == .plain {
            guard await ui.ask(L10n.tr("Hasła jawnym tekstem?"),
                               message: L10n.tr("Plik będzie zawierał hasła baz i tuneli SSH bez szyfrowania. Przechowuj go w bezpiecznym miejscu i usuń, gdy nie będzie potrzebny."),
                               buttons: [L10n.tr("Eksportuj jawnie"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
        }
        guard await ctx.workspace.sessions.prompter?.authenticateOwner(reason: L10n.tr("wyeksportować hasła połączeń")) == true else {
            throw CommandError.cancelledByUser
        }
        var passphrase: String?
        if mode == .encrypted {
            // Za krótka (także pusta) fraza — ponowne pytanie od razu, bez ponownego uwierzytelnienia i wyboru pliku.
            var note = L10n.tr("Co najmniej \(ConnectionTransfer.minimumPassphraseLength) znaków. Bez frazy haseł z pliku nie da się odzyskać.")
            while passphrase == nil {
                guard let p = await ui.askSecret(L10n.tr("Fraza szyfrująca"), message: note, confirm: true) else { throw CommandError.cancelledByUser }
                if p.count >= ConnectionTransfer.minimumPassphraseLength { passphrase = p } else { note = ConnectionTransfer.TransferError.weakPassphrase.errorDescription ?? note }
            }
        }
        var url = ctx.arguments.string("file").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        if url == nil { url = await ui.chooseSaveURL(suggestedName: L10n.tr("Pelikan-połączenia-z-hasłami"), fileExtension: "json") }
        guard let url else { throw CommandError.cancelledByUser }
        // Hasło bazy także z bieżących sesji (podane przy logowaniu bez zapamiętania, zmienione w sesji).
        let sessions = ctx.workspace.sessions
        let secrets = ctx.workspace.connections.secretsForExport(password: { sessions.enteredPassword(for: $0) })
        // Definicje z jednej chwili: te same są w pliku i w danych uwierzytelnionych szyfrowaniem (PBKDF2 poza wątkiem
        // głównym, a w tym czasie np. połączenie może zmienić „ostatnio używane”).
        let definitions = try ctx.workspace.connections.exportDefinitions()
        let phrase = passphrase
        let envelope = try await Task.detached(priority: .userInitiated) {
            try ConnectionTransfer.envelope(secrets, mode: mode, passphrase: phrase, definitions: definitions)
        }.value
        let data = try ConnectionStore.addingSecrets(envelope, to: definitions)
        // Plik 0600 od chwili utworzenia; dysk bez praw POSIX (exFAT, udział sieciowy) — hasła jawne nie zostają w pliku
        // czytelnym dla wszystkich, zaszyfrowane — z ostrzeżeniem.
        let restricted = try PrivateFile.write(data, to: url)
        Log.connection.info("Eksport połączeń z hasłami (\(mode.rawValue, privacy: .public)): \(secrets.count, privacy: .public) z hasłami, prawa 0600: \(restricted, privacy: .public)")
        let count = ctx.workspace.connections.connections.count
        if !restricted {
            if mode == .plain {
                try? FileManager.default.removeItem(at: url)
                throw CommandError.notAvailable(L10n.tr("Na tym dysku nie można ograniczyć dostępu do pliku (prawa 0600) — plik z jawnymi hasłami usunięto. Zapisz go na dysku Maca."))
            }
            return CommandResult(message: L10n.tr("Zapisano \(count) połączeń, z hasłami: \(secrets.count). Uwaga: ten dysk nie przechowuje praw pliku — plik może odczytać każdy (hasła są zaszyfrowane frazą)."),
                                 value: .string(url.path))
        }
        return CommandResult(message: L10n.tr("Zapisano \(count) połączeń, z hasłami: \(secrets.count)"), value: .string(url.path))
    }

    /// Rozłączenie z pytaniem o otwarte transakcje okien tego połączenia (D10).
    @MainActor
    static func disconnect(_ ctx: CommandContext, _ id: UUID) async throws {
        // Wykonanie w toku trzeba najpierw przerwać; debugowanie jest kończone przed zamknięciem sesji (DEBUG_OFF z sesji
        // nadzorującej, ADR 0006) — jak przy zamknięciu okna.
        let ws = ctx.workspace
        let windows = ws.documents.filter { ws.effectiveConnection(of: $0) == id }
        let debugging: (Document) -> DebuggerEngine? = { d in ws.debuggers[d.id].flatMap { [.running, .paused].contains($0.state) ? $0 : nil } }
        if let busy = windows.first(where: { $0.isExecuting && debugging($0) == nil }) {
            throw CommandError.notAvailable(L10n.tr("Okno „\(busy.title)” wykonuje polecenie — najpierw przerwij wykonanie."))
        }
        for d in windows { await debugging(d)?.stop() }
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
