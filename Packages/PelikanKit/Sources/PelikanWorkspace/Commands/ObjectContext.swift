import Foundation

/// Połączenie obiektu (PD-OB-001, D185): Object Browser pokazuje wszystkie otwarte połączenia, więc komenda obiektu
/// działa na połączeniu wynikającym z kontekstu — argument `connection`, gałąź drzewa zaznaczonego obiektu, okno, z którego
/// wskazano obiekt po nazwie — a połączenie główne jest tylko zapasem.
extension Workspace {
    /// Połączenie obiektów zaznaczonych w Object Browserze (bez gałęzi — główne).
    public var objectBrowserConnection: UUID? { selectedObjectConnection ?? sessions.mainConnectionID }

    /// Odświeżenie drzewa wszystkich otwartych połączeń (filtr, foldery użytkownika, Odśwież).
    public func refreshOpenMetadata() {
        for c in sessions.openConnections { metadata(for: c)?.refresh() }
    }

    /// Okno otwarte dla obiektu innego połączenia niż główne jest do niego przypięte (zostaje przy nim po zmianie
    /// połączenia głównego i w worksecie); okno połączenia głównego — jak dotąd, za połączeniem głównym.
    public func bind(_ doc: Document, to connection: UUID?) {
        guard let connection, connection != sessions.mainConnectionID else { return }
        doc.connectionID = connection
        doc.connectionPinned = true
    }
}

extension CommandContext {
    /// Połączenie komendy obiektu: argument `connection`; obiekt wskazany nazwą (`object`, `objects`) — połączenie aktywnego okna
    /// albo główne; bez argumentów — połączenie gałęzi zaznaczonego obiektu, a bez niej — główne.
    /// `connectionArgument: false` — komenda ma własny argument `connection` o innym znaczeniu (np. druga baza porównania).
    @MainActor
    public func objectConnection(connectionArgument: Bool = true) throws -> UUID {
        if connectionArgument, arguments.string("connection") != nil { return try toolConnection() }
        if arguments.string("object") != nil || arguments.string("objects") != nil {
            guard let c = workspace.toolConnection() else { throw CommandError.notConnected }
            return c
        }
        guard let c = workspace.objectBrowserConnection else { throw CommandError.notConnected }
        return c
    }
}
