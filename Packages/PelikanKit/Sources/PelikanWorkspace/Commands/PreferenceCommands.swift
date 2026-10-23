import Foundation
import PelikanSQL

/// Komendy zestawów preferencji, eksportu i importu, paska narzędzi i parametrów startowych (Etap 8).
@MainActor
enum PreferenceCommands {
    static func sections(_ ctx: CommandContext) -> Set<String>? {
        guard let s = ctx.arguments.string("sections")?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return Set(s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    static var all: [Command] {
        let sectionsParam = CommandParameter("sections", .string, L10n.tr("Sekcje po przecinku (puste — wszystkie)"))
        return [
            Command(CommandDescriptor(id: "prefs.export", title: L10n.tr("Eksportuj preferencje…"), category: .tools, submenu: L10n.tr("Preferencje"),
                                      parameters: [CommandParameter("file", .string, L10n.tr("Plik .json")), sectionsParam],
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Zapisuje obowiązujące preferencje (wybrane sekcje) do pliku; bez haseł i historii plików."),
                                      feature: "PD-PREF-003")) { ctx in
                let url: URL
                if let f = ctx.arguments.string("file") { url = URL(fileURLWithPath: (f as NSString).expandingTildeInPath) }
                else if let u = await ctx.ui?.chooseSaveURL(suggestedName: L10n.tr("Preferencje Pelikana"), fileExtension: "json") { url = u }
                else { throw CommandError.cancelledByUser }
                try PreferenceSets.export(ctx.workspace.settings, sections: sections(ctx)).write(to: url, options: .atomic)
                return CommandResult(message: url.lastPathComponent)
            },
            Command(CommandDescriptor(id: "prefs.import", title: L10n.tr("Importuj preferencje…"), category: .tools, submenu: L10n.tr("Preferencje"),
                                      parameters: [CommandParameter("file", .string, L10n.tr("Plik .json")), sectionsParam],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Wczytuje preferencje z pliku (wybrane sekcje) do zestawu edytowanego w Preferencjach."),
                                      feature: "PD-PREF-003")) { ctx in
                let url: URL
                if let f = ctx.arguments.string("file") { url = URL(fileURLWithPath: (f as NSString).expandingTildeInPath) }
                else if let u = await ctx.ui?.chooseFilesToOpen().first { url = u }
                else { throw CommandError.cancelledByUser }
                let values = try PreferenceSets.importValues(try Data(contentsOf: url), sections: sections(ctx))
                try ctx.workspace.importPreferences(values)
                return CommandResult(message: L10n.tr("Wczytano ustawień: \(values.count)"))
            },
            Command(CommandDescriptor(id: "prefs.sets", title: L10n.tr("Zestawy preferencji…"), category: .tools, submenu: L10n.tr("Preferencje"),
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Zestawy preferencji: osobisty, domyślny i dla połączeń; źródło każdej wartości i przywracanie dziedziczonej."),
                                      feature: "PD-PREF-002")) { ctx in
                ctx.ui?.showPreferenceSets()
                return CommandResult(value: .array(ctx.workspace.activePreferenceSets.map {
                    .object(["name": .string($0.name), "kind": .string($0.kind.rawValue), "values": .int(Int64($0.values.count))])
                }))
            },
            Command(CommandDescriptor(id: "view.customizeToolbar", title: L10n.tr("Dostosuj pasek narzędzi…"), category: .view,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Układ paska narzędzi okna głównego: komendy, odstępy i grupa szybkiego dostępu."),
                                      feature: "PD-UI-006")) { ctx in
                ctx.ui?.customizeToolbar()
                return .ok
            },
            Command(CommandDescriptor(id: "view.addToQuickAccess", title: L10n.tr("Dodaj do paska szybkiego dostępu"), category: .view,
                                      parameters: [CommandParameter("command", .string, required: true, L10n.tr("Identyfikator komendy"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Dodaje komendę do paska szybkiego dostępu (Quick Access Toolbar)."), inMenu: false,
                                      feature: "PD-UI-006")) { ctx in
                let id = ctx.arguments.string("command") ?? ""
                guard ctx.workspace.registry.command(CommandID(rawValue: id)) != nil else { throw CommandError.invalidArgument("command", id) }
                ctx.workspace.settings.quickAccessCommands = ToolbarModel.adding(id, to: ctx.workspace.settings.quickAccessCommands, in: ctx.workspace)
                return .ok
            },
            Command(CommandDescriptor(id: "view.removeFromQuickAccess", title: L10n.tr("Usuń z paska szybkiego dostępu"), category: .view,
                                      parameters: [CommandParameter("command", .string, required: true, L10n.tr("Identyfikator komendy"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Usuwa komendę z paska szybkiego dostępu."), inMenu: false, feature: "PD-UI-006")) { ctx in
                let id = ctx.arguments.string("command") ?? ""
                ctx.workspace.settings.quickAccessCommands.removeAll { $0 == id }
                return .ok
            },
            Command(CommandDescriptor(id: "app.openStartupParameters", title: L10n.tr("Wykonaj parametry startowe"), category: .file,
                                      parameters: [CommandParameter("arguments", .string, required: true, L10n.tr("Parametry jak w linii poleceń (klucz=wartość)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Wykonuje parametry startowe (połączenie z definicji, obiekt, skrypt, projekt, workset, pliki) bez haseł."),
                                      inMenu: false, feature: "PD-CLI-001")) { ctx in
                let args = (ctx.arguments.string("arguments") ?? "").split(separator: " ").map(String.init)
                let messages = await ctx.workspace.applyStartup(StartupOptions.parse(args))
                return CommandResult(message: messages.isEmpty ? nil : messages.joined(separator: "\n"),
                                     value: .array(messages.map { .string($0) }))
            },
        ]
    }
}

/// Usługi macOS (MAC-SVC-001): czynności wywoływane z menu Usługi innych aplikacji.
@MainActor
public enum MacServices {
    /// „Formatuj SQL”: tekst zaznaczony w innej aplikacji po formaterze Pelikana (reguły z Preferencji).
    public static func formatSQL(_ text: String, in ws: Workspace) throws -> String {
        try Beautifier.format(text, options: ws.settings.beautifier)
    }

    /// „Otwórz w SQL Window”: nowe okno SQL z zaznaczonym tekstem.
    @discardableResult
    public static func openInSQLWindow(_ text: String, in ws: Workspace) -> Document {
        let doc = ws.newDocument(.sql, text: text)
        doc.isModified = true
        return doc
    }
}
