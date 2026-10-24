import Foundation

/// Widok edytora: zawijanie wierszy (PD-EDIT-004), status linii na marginesie (PD-EDIT-003), okno szablonów (PD-TPL-001).
enum EditorViewCommands {
    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "view.wordWrap", title: L10n.tr("Zawijaj wiersze"), category: .view,
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Włącza lub wyłącza zawijanie długich wierszy w edytorach do szerokości okna."),
                                      feature: "PD-EDIT-004")) { ctx in
                ctx.workspace.settings.wordWrap.toggle()
                return .ok
            },
            Command(CommandDescriptor(id: "view.templateWindow", title: L10n.tr("Okno szablonów"), category: .view,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera szablony kodu w osobnym, pływającym oknie (odłączone od paska bocznego)."),
                                      feature: "PD-TPL-001")) { ctx in
                ctx.ui?.showTemplateWindow()
                return .ok
            },
            Command(CommandDescriptor(id: "view.specialCharacters", title: L10n.tr("Znaki specjalne"), category: .view,
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Pokazuje lub ukrywa w edytorach spacje, tabulacje i końce linii."),
                                      feature: "PD-EDIT-003")) { ctx in
                ctx.workspace.settings.showSpecialCharacters.toggle()
                return .ok
            },
            Command(CommandDescriptor(id: "view.lineStatus", title: L10n.tr("Status linii"), category: .view,
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Pokazuje lub ukrywa na marginesie znaczniki linii zmienionych i nowych od otwarcia albo zapisu."),
                                      feature: "PD-EDIT-003")) { ctx in
                ctx.workspace.settings.showLineStatus.toggle()
                return .ok
            },
        ]
    }
}
