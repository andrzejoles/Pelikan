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
            // WITH FUNCTION … SELECT: funkcja PL/SQL w zapytaniu może zmieniać dane (PRAGMA AUTONOMOUS_TRANSACTION).
            case .query: return c.locksRows || ScriptSplitter.split(s).contains(where: \.isPLSQL)
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

    /// Obiekty schematów utrzymywanych przez Oracle (SYS, XDB…; pod ręką w folderach DBA i DBMS, D190): kompilacja,
    /// DEBUG, DROP, zmiana nazwy albo włączenie może unieważnić obiekty zależne w całej bazie (ORA-04068 w innych
    /// sesjach) — zawsze osobne pytanie z domyślnym Anuluj, niezależnie od preferencji; bez interfejsu — odmowa.
    public func confirmOracleMaintained(_ owners: [String?]) async throws {
        let oracle = Set(owners.compactMap { $0?.uppercased() }).filter(MetadataProvider.oracleMaintainedSchemas.contains).sorted()
        guard !oracle.isEmpty else { return }
        let list = oracle.joined(separator: ", ")
        guard let ui else {
            throw CommandError.notAvailable(L10n.tr("Obiekty schematu Oracle (\(list)) można zmienić tylko po potwierdzeniu w oknie aplikacji"))
        }
        let choice = await ui.ask(L10n.tr("Zmienić obiekt schematu Oracle \(list)?"),
                                  message: L10n.tr("Obiekty schematów utrzymywanych przez Oracle zmienia się zwykle tylko na polecenie Oracle Support. Zmiana może unieważnić obiekty zależne w całej bazie i przerwać pracę innych sesji (ORA-04068)."),
                                  buttons: [L10n.tr("Anuluj"), L10n.tr("Zmień mimo to")])
        guard choice == 1 else { throw CommandError.cancelledByUser }
    }

    /// Jak wyżej dla obiektów; typy globalne (katalogi, użytkownicy, role, profile) pomijane — katalog ma zawsze
    /// właściciela SYS, a jego usunięcie nie dotyka obiektów schematu.
    public func confirmOracleMaintained(objects: [DBObject]) async throws {
        try await confirmOracleMaintained(objects.filter { !$0.type.isGlobal }.map(\.owner))
    }
}
