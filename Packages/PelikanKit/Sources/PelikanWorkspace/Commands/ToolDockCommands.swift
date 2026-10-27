import Foundation

/// Panele narzędzi okna głównego (PD-UI-003, D183): pokazanie paneli, przenoszenie narzędzi między panelami
/// i osobnym oknem, autoukrywanie. Miejsce przeniesionego narzędzia zostaje zapamiętane dla jego rodzaju.
@MainActor
enum ToolDockCommands {
    static let toolParam = CommandParameter("tool", .string, L10n.tr("Klucz narzędzia (puste — bieżące)"))

    static func command(_ id: CommandID, _ title: String, params: [CommandParameter] = [], effect: CommandEffect, summary: String,
                        _ run: @escaping CommandHandler) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: .view, submenu: L10n.tr("Panele narzędzi"), parameters: params,
                                  agent: .none, effect: effect, summary: summary, feature: "PD-UI-003"), run: run)
    }

    /// Przenosi narzędzie i zapamiętuje miejsce jego rodzaju (następne otwarcie trafia w to samo miejsce).
    static func place(_ ctx: CommandContext, _ placement: ToolPlacement) throws -> CommandResult {
        guard let key = ctx.ui?.placeTool(ctx.arguments.string("tool"), at: placement) else { throw CommandError.notAvailable(L10n.tr("Brak otwartego narzędzia")) }
        ctx.workspace.settings.toolDock.remember(placement, for: key)
        return CommandResult(message: placement.displayName)
    }

    static var all: [Command] {
        [
            command("view.toolDockRight", L10n.tr("Pokaż lub ukryj panel po prawej"), effect: .uiState,
                    summary: L10n.tr("Pokazuje albo chowa prawy panel narzędzi okna głównego.")) { ctx in
                ctx.ui?.toggleToolDock(.right)
                return .ok
            },
            command("view.toolDockBottom", L10n.tr("Pokaż lub ukryj panel na dole"), effect: .uiState,
                    summary: L10n.tr("Pokazuje albo chowa dolny panel narzędzi okna głównego.")) { ctx in
                ctx.ui?.toggleToolDock(.bottom)
                return .ok
            },
            command("view.dockToolRight", L10n.tr("Zadokuj narzędzie po prawej"), params: [toolParam], effect: .settings,
                    summary: L10n.tr("Przenosi narzędzie do prawego panelu; narzędzia tego rodzaju będą się tam otwierać.")) { ctx in
                try place(ctx, .right)
            },
            command("view.dockToolBottom", L10n.tr("Zadokuj narzędzie na dole"), params: [toolParam], effect: .settings,
                    summary: L10n.tr("Przenosi narzędzie do dolnego panelu; narzędzia tego rodzaju będą się tam otwierać.")) { ctx in
                try place(ctx, .bottom)
            },
            command("view.floatTool", L10n.tr("Odłącz narzędzie do osobnego okna"), params: [toolParam], effect: .settings,
                    summary: L10n.tr("Przenosi narzędzie z panelu do osobnego okna; narzędzia tego rodzaju będą się otwierać w oknie.")) { ctx in
                try place(ctx, .floating)
            },
            command("view.closeTool", L10n.tr("Zamknij narzędzie"), params: [toolParam], effect: .uiState,
                    summary: L10n.tr("Zamyka narzędzie w panelu albo jego okno.")) { ctx in
                guard ctx.ui?.closeTool(ctx.arguments.string("tool")) != nil else { throw CommandError.notAvailable(L10n.tr("Brak otwartego narzędzia")) }
                return .ok
            },
            command("view.toolDockAutoHide", L10n.tr("Autoukrywanie paneli narzędzi"), effect: .settings,
                    summary: L10n.tr("Panele narzędzi chowają się, gdy praca wraca do edytora; otwarcie narzędzia je pokazuje.")) { ctx in
                ctx.workspace.settings.toolDock.autoHide.toggle()
                return CommandResult(message: ctx.workspace.settings.toolDock.autoHide ? L10n.tr("Autoukrywanie włączone") : L10n.tr("Autoukrywanie wyłączone"))
            },
        ]
    }
}
