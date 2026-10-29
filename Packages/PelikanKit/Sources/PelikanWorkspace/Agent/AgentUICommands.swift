import Foundation

/// Komendy agentów AI dla użytkownika (panel agenta, uruchamianie CLI, cofanie i kończenie sesji, dziennik). Obsługę
/// rejestruje aplikacja (AgentUIController), opisy są tu — żeby wstążka, „Szukaj czynności”, paleta i test pokrycia
/// wstążki widziały te same komendy. Agent nie ma do nich dostępu (poziom „Brak”).
public enum AgentUICommands {
    public static let togglePane: CommandID = "agent.togglePane"
    public static let undoSession: CommandID = "agent.undoSession"
    public static let endSession: CommandID = "agent.endSession"
    public static let showLog: CommandID = "agent.showLog"
    /// Prefiks komend uruchamiania (`agent.launch.<profil>`), jedna na profil z Ustawień › Agenci.
    public static let launchPrefix = "agent.launch."

    public static func launchID(_ profile: AgentProfile) -> CommandID { CommandID(rawValue: launchPrefix + profile.id) }

    /// Komendy agenta, które są czynnościami użytkownika (a nie narzędziami API agenta `agent.*`).
    public static func isUserCommand(_ id: CommandID) -> Bool {
        [togglePane, undoSession, endSession, showLog].contains(id) || id.rawValue.hasPrefix(launchPrefix)
    }

    private static var submenu: String { L10n.tr("Agent AI") }

    public static func launch(_ profile: AgentProfile) -> CommandDescriptor {
        CommandDescriptor(
            id: launchID(profile), title: L10n.tr("Uruchom \(profile.name)"), category: .tools,
            submenu: submenu, agent: .none, effect: .external,
            summary: L10n.tr("Uruchamia \(profile.name) w panelu agenta z serwerem MCP Pelikana tylko dla tej sesji; najpierw macierz uprawnień sesji."),
            feature: "AI-PANEL-001")
    }

    /// Komendy stałe (bez uruchamiania profili).
    public static var fixed: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: togglePane, title: L10n.tr("Panel agenta"), category: .view,
                agent: .none, effect: .uiState, summary: L10n.tr("Pokazuje lub ukrywa panel agenta z terminalem i aktywnością."),
                feature: "AI-PANEL-002"),
            CommandDescriptor(
                id: undoSession, title: L10n.tr("Cofnij sesję agenta…"), category: .tools, submenu: submenu,
                agent: .none, effect: .modifiesEditor,
                summary: L10n.tr("Cofa zmiany wybranej sesji agenta: tekst okien, okna otwarte przez agenta; z podglądem i wykrywaniem konfliktów."),
                feature: "AI-SEC-008"),
            CommandDescriptor(
                id: endSession, title: L10n.tr("Zakończ sesję agenta"), category: .tools, submenu: submenu,
                agent: .none, effect: .external,
                summary: L10n.tr("Kończy proces CLI, unieważnia token sesji, wycofuje niezatwierdzone zmiany agenta i zamyka jego sesje bazy."),
                feature: "AI-PANEL-001"),
            CommandDescriptor(
                id: showLog, title: L10n.tr("Dziennik agentów…"), category: .tools, submenu: submenu,
                agent: .none, effect: .uiState, summary: L10n.tr("Przeglądarka dziennika wywołań narzędzi agentów (JSONL)."),
                feature: "AI-LOG-001"),
        ]
    }
}
