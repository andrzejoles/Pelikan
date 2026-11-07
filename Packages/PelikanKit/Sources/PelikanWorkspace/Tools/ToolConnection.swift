import Foundation
import PelikanDB
import PelikanLog

/// Połączenie narzędzi — jedna reguła dla okien i komend narzędzi (wcześniej kopia w każdym narzędziu).
/// Okno narzędzia ustala połączenie raz, przy otwarciu (`toolConnection()`), pokazuje je i używa go do wszystkich
/// operacji; komendy wołane z okna dostają je w argumencie `connection` (UUID definicji). Bez tego okno niemodalne
/// po przełączeniu aktywnego okna działałoby po cichu na innej bazie niż przy otwarciu.
extension Workspace {
    /// Połączenie dla narzędzia otwieranego teraz: aktywnego okna (przypięte albo główne), bez okna — główne.
    public func toolConnection() -> UUID? {
        activeDocument.flatMap { effectiveConnection(of: $0) } ?? sessions.mainConnectionID
    }

    /// Sesja narzędzia o danym przeznaczeniu na wskazanym połączeniu (osobna od sesji okien użytkownika). Przy limicie
    /// sesji (ORA-02391, ORA-00018, ORA-00020, listener ORA-12516/12519/12520) — sesja główna, jak metadane (D235),
    /// ale tylko bez otwartej transakcji okien na niej: narzędzia danych zatwierdzają własne zmiany, więc w sesji
    /// z cudzą transakcją zatwierdziłyby i ją.
    public func toolSession(_ purpose: String, connection: UUID?) async throws -> any DatabaseSession {
        guard let connection else { throw CommandError.notConnected }
        let key = SessionKey(connectionID: connection, purpose: .tool(purpose))
        if sessions.existingSession(key) == nil, sessions.toolLimitActive(connection) {
            return try await mainSessionForTool(connection)
        }
        do {
            return try await sessions.session(key)
        } catch let e as OracleError where SessionManager.isSessionLimit(e) {
            Log.connection.notice("Limit sesji — narzędzie w sesji głównej (\(e.code, privacy: .public))")
            sessions.noteToolLimit(connection)
            return try await mainSessionForTool(connection)
        }
    }

    /// Sesja główna dla narzędzia przy limicie sesji — odmowa, gdy okno ma w niej otwartą transakcję.
    private func mainSessionForTool(_ connection: UUID) async throws -> any DatabaseSession {
        // Tylko tryb Multi: okna mają tam własne sesje. W trybach Dual i jednej sesji okna wykonują polecenia w sesji
        // głównej — COMMIT, ROLLBACK, DDL i ALTER SESSION narzędzia sięgałyby ich zmian także po sprawdzeniu niżej.
        guard settings.sessionMode == .multi else {
            throw CommandError.notAvailable(L10n.tr("Osiągnięto limit sesji bazy — zamknij nieużywane okna i narzędzia (w trybie Multi narzędzie skorzystałoby z sesji głównej)"))
        }
        let mainKey = SessionKey(connectionID: connection, purpose: .main)
        let main = try await sessions.session(mainKey)
        let windowTransaction = documents.contains { $0.transactionOpen && sessionKey(for: $0) == mainKey }
        let open = (try? await SessionUtilities.transactionOpen(main)) ?? true
        if windowTransaction || open {
            throw CommandError.notAvailable(L10n.tr("Osiągnięto limit sesji bazy, a sesja główna ma otwartą transakcję — zatwierdź albo wycofaj ją, albo zamknij nieużywane okna i narzędzia"))
        }
        return main
    }
}

extension CommandContext {
    /// Parametr komend wołanych z okna narzędzia: połączenie ustalone przy otwarciu okna.
    nonisolated static let toolConnectionParam = CommandParameter("connection", .string, L10n.tr("Identyfikator połączenia (domyślnie połączenie aktywnego okna albo główne)"))

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
