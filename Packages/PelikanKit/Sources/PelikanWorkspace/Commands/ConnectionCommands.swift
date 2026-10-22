import Foundation
import PelikanDB

/// Komendy połączeń (UG 3, 19, 20). Argument `connection` = UUID definicji; bez argumentu — połączenie główne.
public enum ConnectionCommands {
    static let connectionParam = CommandParameter("connection", .string, "Identyfikator połączenia (domyślnie połączenie główne)")

    @MainActor
    static func connectionID(_ ctx: CommandContext) throws -> UUID {
        if let s = ctx.arguments.string("connection") {
            guard let id = UUID(uuidString: s), ctx.workspace.connections.connection(id) != nil else {
                throw CommandError.invalidArgument("connection", L10n.tr("nieznane połączenie"))
            }
            return id
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
            Command(CommandDescriptor(id: "connection.disconnect", title: L10n.tr("Rozłącz"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [connectionParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Rozłącza wszystkie sesje połączenia."), inMenu: false, feature: "PD-CONN-022")) { ctx in
                try await disconnect(ctx, try connectionID(ctx))
                return .ok
            },
            Command(CommandDescriptor(id: "connection.newFolder", title: L10n.tr("Nowy folder…"), category: .session, submenu: L10n.tr("Połączenia"),
                                      parameters: [CommandParameter("name", .string, required: true, "Nazwa folderu"),
                                                   CommandParameter("parent", .string, "Folder nadrzędny")],
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
