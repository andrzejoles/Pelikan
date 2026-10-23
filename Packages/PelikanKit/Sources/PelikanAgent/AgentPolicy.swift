#if canImport(Darwin)
import Foundation
import PelikanWorkspace

/// Limit wywołań: przesuwne okno 60 s na sesję.
final class RateLimiter {
    private var calls: [String: [Date]] = [:]

    func allow(session: String, limit: Int, now: Date = Date()) -> Bool {
        var list = calls[session, default: []].filter { now.timeIntervalSince($0) < 60 }
        guard list.count < limit else {
            calls[session] = list
            return false
        }
        list.append(now)
        calls[session] = list
        return true
    }
}

/// Zasada najmniejszego poziomu (PROMPT §7.4): poziom wywołania = minimum z poziomu komendy, macierzy sesji,
/// ustawień i poziomu połączenia (środowiska).
public enum AgentPolicy {
    /// Skutki zmieniające tylko interfejs albo edytor (bez bazy; poziom połączenia nie ma znaczenia).
    static let appCommandEffects: Set<CommandEffect> = [.uiState, .modifiesEditor]

    /// Zwykłe komendy aplikacji dostępne dla agenta przez `run_command` (D33): tylko takie, które zmieniają
    /// interfejs albo tekst edytora i nie czytają bazy sesjami użytkownika ani nie ujawniają danych połączeń.
    /// Okno poleceń, szablony z pytaniami, zamykanie okien (utrata zmian) i wszystko, co dotyka bazy — poza listą.
    public static let appCommands: Set<CommandID> = [
        "file.new.sql", "file.new.program", "file.new.test",
        "edit.findNext", "edit.findPrevious", "edit.gotoLine", "edit.beautify", "edit.commentLine", "edit.duplicateLine",
        "edit.uppercase", "edit.lowercase", "edit.indent", "edit.outdent", "edit.removeTrailingSpaces",
        "edit.navigateBack", "edit.navigateForward", "sql.historyBack", "sql.historyForward", "window.next", "window.previous",
    ]

    public static func isAgentCommand(_ id: CommandID) -> Bool { id.rawValue.hasPrefix("agent.") }

    public static func effectiveAccess(command: CommandDescriptor, session: AgentSession, settings: AgentSettings,
                                       viaRunCommand: Bool = false) -> AgentAccess {
        var level = command.agentAccess
        // Komendy spoza `agent.*` i spoza listy używałyby sesji użytkownika albo okna poleceń — niedostępne.
        if !isAgentCommand(command.id), !appCommands.contains(command.id) { return .none }
        if let o = session.accessOverrides[command.id] { level = min(level, o) }
        if let o = settings.accessOverrides[command.id.rawValue] { level = min(level, o) }
        if viaRunCommand { level = min(level, .approval) }
        return level
    }

    /// Poziom połączenia dla agenta: niewidoczne — Brak; tylko do odczytu albo bez zgody na zmiany (prod
    /// domyślnie) — Odczyt; w innym razie bez ograniczenia.
    public static func connectionAccess(_ def: ConnectionDefinition) -> AgentAccess {
        guard def.agent.visibleToAgent else { return .none }
        return def.readOnly || !def.agent.allowChanges ? .read : .full
    }

    /// Czy wywołanie o danym poziomie i skutkach może się odbyć bez zgody, wymaga zgody, czy jest zabronione.
    public enum Decision: Equatable, Sendable { case allow, needsApproval, deny(String) }

    public static func decide(level: AgentAccess, effect: CommandEffect) -> Decision {
        let readOnly = effect == .none || effect == .uiState
        switch level {
        case .none: return .deny("narzędzie niedostępne dla agenta")
        case .read: return readOnly ? .allow : .deny("poziom Odczyt nie pozwala na zmiany")
        case .approval: return readOnly ? .allow : .needsApproval
        case .full: return .allow
        }
    }
}
#endif
