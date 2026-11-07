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
    /// sesji (`SessionManager.isSessionLimit`) narzędzia z krótkimi odczytami dostają sesję główną (tryb Multi, bez
    /// otwartej transakcji); pozostałe — komunikat: COMMIT/ROLLBACK, DDL, ALTER SESSION i stan pakietów w sesji
    /// współdzielonej sięgałyby cudzej pracy, a długie operacje blokowałyby ją — D235.
    public func toolSession(_ purpose: String, connection: UUID?) async throws -> any DatabaseSession {
        guard let connection else { throw CommandError.notConnected }
        do {
            return try await sessions.session(SessionKey(connectionID: connection, purpose: .tool(purpose)))
        } catch let e as OracleError where SessionManager.isSessionLimit(e) {
            guard Self.readOnlyToolPurposes.contains(purpose) else {
                throw CommandError.notAvailable(L10n.tr("Osiągnięto limit sesji bazy — zamknij nieużywane okna i narzędzia (to narzędzie potrzebuje własnej sesji)"))
            }
            Log.connection.notice("Limit sesji — narzędzie tylko do odczytu w sesji głównej (\(e.code, privacy: .public))")
            return try await mainSessionForTool(connection)
        }
    }

    /// Narzędzia z krótkimi, bezstanowymi odczytami (podgląd bazy przy limicie sesji) — mogą pracować w sesji głównej.
    /// Bez narzędzi zmieniających stan sesji (transformacje DBMS_METADATA w eksporcie DDL), uruchamiających doradców
    /// (raporty wydajności, SQL Tuning) i długich operacji, które blokowałyby sesję główną (eksport, porównania).
    nonisolated static let readOnlyToolPurposes: Set<String> = ["sessions", "sessions.detail", "perf.list", "packs.list", "instance"]

    /// Sesja główna dla narzędzia odczytu przy limicie sesji: tylko tryb Multi (w Dual i jednej sesji okna wykonują w niej
    /// polecenia) i bez otwartej transakcji.
    private func mainSessionForTool(_ connection: UUID) async throws -> any DatabaseSession {
        guard settings.sessionMode == .multi else {
            throw CommandError.notAvailable(L10n.tr("Osiągnięto limit sesji bazy — zamknij nieużywane okna i narzędzia (w trybie Multi narzędzie skorzystałoby z sesji głównej)"))
        }
        let main = try await sessions.session(SessionKey(connectionID: connection, purpose: .main))
        if (try? await SessionUtilities.transactionOpen(main)) ?? true {
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
