import Foundation
import PelikanDB

/// Połączenie narzędzi — jedna reguła dla okien i komend narzędzi (wcześniej kopia w każdym narzędziu).
/// Okno narzędzia ustala połączenie raz, przy otwarciu (`toolConnection()`), pokazuje je i używa go do wszystkich
/// operacji; komendy wołane z okna dostają je w argumencie `connection` (UUID definicji). Bez tego okno niemodalne
/// po przełączeniu aktywnego okna działałoby po cichu na innej bazie niż przy otwarciu.
extension Workspace {
    /// Połączenie dla narzędzia otwieranego teraz: aktywnego okna (przypięte albo główne), bez okna — główne.
    public func toolConnection() -> UUID? {
        activeDocument.flatMap { effectiveConnection(of: $0) } ?? sessions.mainConnectionID
    }

    /// Sesja narzędzia o danym przeznaczeniu na wskazanym połączeniu (osobna od sesji okien użytkownika).
    public func toolSession(_ purpose: String, connection: UUID?) async throws -> any DatabaseSession {
        guard let connection else { throw CommandError.notConnected }
        return try await sessions.session(SessionKey(connectionID: connection, purpose: .tool(purpose)))
    }
}

extension CommandContext {
    /// Parametr komend wołanych z okna narzędzia: połączenie ustalone przy otwarciu okna.
    static let toolConnectionParam = CommandParameter("connection", .string, L10n.tr("Identyfikator połączenia (domyślnie połączenie aktywnego okna albo główne)"))

    /// Połączenie komendy narzędzia: argument `connection` (UUID znanej definicji), bez niego — `toolConnection()`.
    @MainActor
    public func toolConnection() throws -> UUID {
        if let s = arguments.string("connection") {
            guard let id = UUID(uuidString: s), workspace.connections.connection(id) != nil else {
                throw CommandError.invalidArgument("connection", L10n.tr("nieznane połączenie"))
            }
            return id
        }
        guard let c = workspace.toolConnection() else { throw CommandError.notConnected }
        return c
    }
}
