import Foundation
import PelikanSQL

/// Strażnik zmian (PD-CONN-006, PD-CONN-007): połączenie tylko do odczytu blokuje wszystko poza zapytaniami i sterowaniem
/// sesją (także SELECT … FOR UPDATE i bloki PL/SQL, które mogą zmieniać dane); na połączeniu produkcyjnym polecenia
/// zmieniające wymagają potwierdzenia (preferencja, domyślnie włączona).
extension Workspace {
    public enum ModificationCheck: Equatable { case allowed, blocked(String), needsConfirmation }

    /// Ocena poleceń dla połączenia (bez pytania użytkownika).
    public func modificationCheck(_ statements: [String], connectionID: UUID?) -> ModificationCheck {
        guard let id = connectionID, let def = connections.connection(id) else { return .allowed }
        let changing = statements.filter { s in
            let c = StatementClassifier.classify(s)
            switch c.category {
            case .query: return c.locksRows
            case .sessionControl, .transactionControl: return false
            default: return true
            }
        }
        guard !changing.isEmpty else { return .allowed }
        if def.readOnly || startupReadOnlyPatterns.contains(where: { p in PreferenceSets.candidates(for: def).contains { PreferenceSets.matches(p, $0) } }) {
            let first = changing[0].trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
            return .blocked(L10n.tr("Połączenie „\(def.displayName)” jest tylko do odczytu — polecenie zmieniające zablokowane: \(first)…"))
        }
        if def.environment == .production, settings.confirmProductionChanges { return .needsConfirmation }
        return .allowed
    }

    /// Sprawdzenie z pytaniem o potwierdzenie (produkcja); błąd — zablokowane albo anulowane.
    public func guardModification(_ statements: [String], connectionID: UUID?) async throws {
        switch modificationCheck(statements, connectionID: connectionID) {
        case .allowed: return
        case .blocked(let why): throw CommandError.notAvailable(why)
        case .needsConfirmation:
            let name = connectionID.flatMap { connections.connection($0)?.displayName } ?? ""
            let choice = await ui?.ask(L10n.tr("Zmiany na połączeniu produkcyjnym „\(name)”"),
                                       message: L10n.tr("Polecenie może zmienić dane lub obiekty bazy produkcyjnej. Wykonać?"),
                                       buttons: [L10n.tr("Wykonaj"), L10n.tr("Anuluj")])
            guard choice == 0 else { throw CommandError.cancelledByUser }
        }
    }
}
