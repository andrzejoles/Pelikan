import Foundation
import PelikanDB

/// Reguła wskaźnika połączenia (Connection Indicators, PD-CONN-005): wzorzec `user@baza` (`*`, `?`) i kolor.
/// `id` tylko do wierszy Preferencji (wiązanie po identyfikatorze, nie indeksie) — nie trafia do pliku ani do porównań.
public struct ConnectionIndicator: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var pattern: String
    public var color: RGBColor
    public init(pattern: String, color: RGBColor) { self.pattern = pattern; self.color = color }

    private enum CodingKeys: String, CodingKey { case pattern, color }
    public static func == (a: Self, b: Self) -> Bool { a.pattern == b.pattern && a.color == b.color }
    public func hash(into h: inout Hasher) { h.combine(pattern); h.combine(color) }
}

/// Kolejność listy okien (PD-UI-002).
public enum WindowListSort: String, Sendable, Codable, CaseIterable {
    case opening, name, type
}

extension Workspace {
    /// Kolor połączenia okna: pierwsza pasująca reguła wskaźników `user@baza`, inaczej kolor połączenia lub środowiska.
    public func indicatorColor(for doc: Document) -> RGBColor? {
        guard let id = effectiveConnection(of: doc), let c = connections.connection(id) else { return nil }
        let user = c.target.driverUserName
        for rule in settings.connectionIndicators {
            if Wildcard.matches(user: user, database: c.target.connectString, pattern: rule.pattern)
                || Wildcard.matches(user: user, database: c.name, pattern: rule.pattern) { return rule.color }
        }
        return c.effectiveColor
    }

    /// Okna w kolejności listy okien.
    public var windowListDocuments: [Document] {
        switch settings.windowListSort {
        case .opening: documents
        case .name: documents.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .type: documents.enumerated().sorted { ($0.element.kind.rawValue, $0.offset) < ($1.element.kind.rawValue, $1.offset) }.map(\.element)
        }
    }

    /// Tytuł na liście okien: pełny albo krótki (Short Text — bez połączenia i ścieżki).
    public func windowListTitle(_ doc: Document) -> String {
        settings.windowListShortTitles ? doc.title : doc.fullTitle
    }
}

/// Komendy menu listy okien (PD-UI-002): wykonanie, ponowne połączenie, zmiana nazwy, krótkie tytuły, sortowanie.
enum WindowListCommands {
    static let documentParam = CommandParameter("document", .string, L10n.tr("Identyfikator okna (domyślnie aktywne)"))

    @MainActor
    static func document(_ ctx: CommandContext) throws -> Document {
        if let s = ctx.arguments.string("document") {
            guard let d = ctx.workspace.documents.first(where: { $0.id.description == s }) else {
                throw CommandError.invalidArgument("document", L10n.tr("Nie ma takiego okna"))
            }
            return d
        }
        guard let d = ctx.workspace.activeDocument else { throw CommandError.notAvailable(L10n.tr("Brak aktywnego okna")) }
        return d
    }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "window.execute", title: L10n.tr("Wykonaj okno"), category: .window,
                                      parameters: [documentParam], agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Aktywuje okno z listy i wykonuje je (SQL, test, program albo skrypt poleceń)."),
                                      inMenu: false, feature: "PD-UI-002")) { ctx in
                let d = try document(ctx)
                ctx.workspace.activate(d.id)
                // Wykonaj działa według typu okna (SQL, test, kompilacja programu, skrypt poleceń, raport).
                return try await ctx.workspace.invoke("sql.execute", CommandArguments())
            },
            Command(CommandDescriptor(id: "window.reconnect", title: L10n.tr("Połącz ponownie okno"), category: .window,
                                      parameters: [documentParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Zamyka sesję okna (bez otwartej transakcji); okno łączy się ponownie przy następnym wykonaniu."),
                                      inMenu: false, feature: "PD-UI-002")) { ctx in
                let d = try document(ctx)
                let ws = ctx.workspace
                guard let c = ws.effectiveConnection(of: d) else { throw CommandError.notConnected }
                guard !d.transactionOpen else {
                    throw CommandError.notAvailable(L10n.tr("Okno ma otwartą transakcję — zatwierdź albo wycofaj ją przed ponownym połączeniem"))
                }
                guard !d.isExecuting else { throw CommandError.notAvailable(L10n.tr("Okno wykonuje polecenie")) }
                await ws.sessions.close(ws.sessions.key(forDocument: d.id, connection: c))
                return CommandResult(message: L10n.tr("Okno połączy się ponownie przy następnym wykonaniu"))
            },
            Command(CommandDescriptor(id: "window.rename", title: L10n.tr("Zmień nazwę okna…"), category: .window,
                                      parameters: [documentParam, CommandParameter("title", .string, L10n.tr("Nowa nazwa; pusta przywraca domyślną"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Nadaje oknu własną nazwę na karcie i liście okien."),
                                      inMenu: false, feature: "PD-UI-002")) { ctx in
                let d = try document(ctx)
                var title = ctx.arguments.string("title")
                if title == nil {
                    guard let t = await ctx.ui?.askText(L10n.tr("Zmień nazwę okna"), message: L10n.tr("Nowa nazwa okna"), defaultValue: d.title) else {
                        throw CommandError.cancelledByUser
                    }
                    title = t
                }
                let t = title!.trimmingCharacters(in: .whitespaces)
                d.customTitle = t.isEmpty ? nil : t
                return .ok
            },
            Command(CommandDescriptor(id: "window.listShortTitles", title: L10n.tr("Krótkie nazwy na liście okien"), category: .window,
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Przełącza listę okien między pełnymi tytułami (z połączeniem) a krótkimi."),
                                      inMenu: false, feature: "PD-UI-002")) { ctx in
                ctx.workspace.settings.windowListShortTitles.toggle()
                return .ok
            },
            Command(CommandDescriptor(id: "window.listSort", title: L10n.tr("Sortuj listę okien…"), category: .window,
                                      parameters: [CommandParameter("order", .string, L10n.tr("opening, name albo type"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Kolejność listy okien: otwarcia, nazwa albo typ okna."),
                                      inMenu: false, feature: "PD-UI-002")) { ctx in
                guard let o = ctx.arguments.string("order").flatMap(WindowListSort.init(rawValue:)) else {
                    throw CommandError.invalidArgument("order", L10n.tr("Dozwolone: opening, name, type"))
                }
                ctx.workspace.settings.windowListSort = o
                return .ok
            },
        ]
    }
}
