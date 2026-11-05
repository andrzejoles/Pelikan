import Foundation
import PelikanSQL

/// Komendy motywów kolorowania składni (D227): wybór dla trybu jasnego i ciemnego, kopia do edycji, zmiana stylu
/// kategorii w motywie własnym, usuwanie, import i eksport. Poza menu — działają na motywie z argumentu (paleta,
/// skrypty, karta Ustawienia › Kolory); agent ich nie widzi (ustawienia aplikacji, D33).
@MainActor
enum SyntaxSchemeCommands {
    static let feature = "PD-EDIT-001"

    /// Motyw z argumentu `scheme`: identyfikator albo nazwa (bez wielkości liter; przy kilku — pierwszy pasujący trybem).
    static func scheme(_ ctx: CommandContext, dark: Bool? = nil) throws -> SyntaxScheme {
        guard let key = ctx.arguments.string("scheme")?.trimmingCharacters(in: .whitespaces), !key.isEmpty else {
            throw CommandError.invalidArgument("scheme", "")
        }
        let all = ctx.workspace.settings.syntaxSchemes
        if let s = all.first(where: { $0.id == key }) { return s }
        let named = all.filter { $0.name.caseInsensitiveCompare(key) == .orderedSame }
        if let s = named.first(where: { dark == nil || $0.isDark == dark }) ?? named.first { return s }
        throw CommandError.invalidArgument("scheme", key)
    }

    static func custom(_ ctx: CommandContext) throws -> Int {
        let s = try scheme(ctx)
        guard let i = ctx.workspace.settings.customSyntaxSchemes.firstIndex(where: { $0.id == s.id }) else {
            throw CommandError.notAvailable(L10n.tr("Motyw wbudowany „\(s.name)” jest tylko do odczytu — najpierw zapisz go jako własny"))
        }
        return i
    }

    static func describe(_ s: SyntaxScheme) -> JSONValue {
        .object(["id": .string(s.id), "name": .string(s.name), "dark": .bool(s.isDark), "builtin": .bool(s.isBuiltin),
                 "author": .string(s.author), "source": .string(s.source)])
    }

    static func mode(_ ctx: CommandContext, _ s: SyntaxScheme) -> Bool {
        switch ctx.arguments.string("mode")?.lowercased() {
        case "light": false
        case "dark": true
        default: s.isDark
        }
    }

    static var all: [Command] {
        let schemeParam = CommandParameter("scheme", .string, required: true, L10n.tr("Identyfikator albo nazwa motywu"))
        let modeParam = CommandParameter("mode", .string, L10n.tr("Tryb systemu: light albo dark (puste — według motywu)"), allowed: ["light", "dark"])
        return [
            Command(CommandDescriptor(id: "prefs.syntaxSchemes", title: L10n.tr("Kolory składni…"), category: .tools, submenu: L10n.tr("Ustawienia"),
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Lista motywów kolorowania składni (wbudowane i własne) i motywy wybrane dla trybu jasnego i ciemnego; w aplikacji otwiera Ustawienia › Kolory."),
                                      feature: feature)) { ctx in
                ctx.ui?.showSyntaxSchemes()
                let st = ctx.workspace.settings
                return CommandResult(value: .object(["light": .string(st.syntaxSchemeLight), "dark": .string(st.syntaxSchemeDark),
                                                     "schemes": .array(st.syntaxSchemes.map(describe))]))
            },
            Command(CommandDescriptor(id: "editor.syntaxScheme.use", title: L10n.tr("Użyj motywu kolorów składni"), category: .tools, submenu: L10n.tr("Ustawienia"),
                                      parameters: [schemeParam, modeParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Ustawia motyw kolorowania składni dla trybu jasnego albo ciemnego systemu (domyślnie dla trybu motywu); zmienia kolory wszystkich edytorów i podglądów kodu."),
                                      inMenu: false, feature: feature)) { ctx in
                let s = try scheme(ctx, dark: ctx.arguments.string("mode").map { $0.lowercased() == "dark" })
                if mode(ctx, s) { ctx.workspace.settings.syntaxSchemeDark = s.id } else { ctx.workspace.settings.syntaxSchemeLight = s.id }
                return CommandResult(message: s.name)
            },
            Command(CommandDescriptor(id: "editor.syntaxScheme.duplicate", title: L10n.tr("Zapisz motyw kolorów jako własny"), category: .tools, submenu: L10n.tr("Ustawienia"),
                                      parameters: [schemeParam, CommandParameter("name", .string, L10n.tr("Nazwa nowego motywu (puste — „nazwa (kopia)”)"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Kopia motywu (wbudowanego albo własnego) jako motyw własny do zmian; wbudowane zostają bez zmian."),
                                      inMenu: false, feature: feature)) { ctx in
                let s = try scheme(ctx)
                let name = ctx.arguments.string("name").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? L10n.tr("\(s.name) (kopia)")
                let copy = s.copy(named: name)
                ctx.workspace.settings.customSyntaxSchemes.append(copy)
                return CommandResult(message: copy.name, value: describe(copy))
            },
            Command(CommandDescriptor(id: "editor.syntaxScheme.setStyle", title: L10n.tr("Zmień kolor kategorii w motywie"), category: .tools, submenu: L10n.tr("Ustawienia"),
                                      parameters: [schemeParam,
                                                   CommandParameter("style", .string, required: true, L10n.tr("Kategoria składni albo element edytora"),
                                                                    allowed: SyntaxStyle.allCases.map(\.rawValue) + ["background", "text", "selection", "currentLine", "lineNumber", "cursor"]),
                                                   CommandParameter("color", .string, L10n.tr("Kolor #rrggbb (puste — bez zmiany; „none” — kolor systemu albo tekstu)")),
                                                   CommandParameter("bold", .boolean, L10n.tr("Pogrubienie")), CommandParameter("italic", .boolean, L10n.tr("Kursywa"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Zmienia kolor, pogrubienie albo kursywę kategorii składni lub kolor elementu edytora w motywie własnym."),
                                      inMenu: false, feature: feature)) { ctx in
                let i = try custom(ctx)
                let key = ctx.arguments.string("style") ?? ""
                let raw = ctx.arguments.string("color")?.trimmingCharacters(in: .whitespaces)
                var color: RGB?? = nil
                if let raw, !raw.isEmpty {
                    if raw.lowercased() == "none" { color = .some(nil) }
                    else if let c = RGB(hex: raw) { color = .some(c) }
                    else { throw CommandError.invalidArgument("color", raw) }
                }
                var s = ctx.workspace.settings.customSyntaxSchemes[i]
                if let style = SyntaxStyle(rawValue: key) {
                    var t = s.style(style)
                    if let color { t.color = color }
                    if let b = ctx.arguments.bool("bold") { t.bold = b }
                    if let it = ctx.arguments.bool("italic") { t.italic = it }
                    s.styles[style] = t
                } else {
                    let path: WritableKeyPath<SyntaxScheme, RGB?>
                    switch key {
                    case "background": path = \.background
                    case "text": path = \.text
                    case "selection": path = \.selection
                    case "currentLine": path = \.currentLine
                    case "lineNumber": path = \.lineNumber
                    case "cursor": path = \.cursor
                    default: throw CommandError.invalidArgument("style", key)
                    }
                    if let color { s[keyPath: path] = color }
                }
                ctx.workspace.settings.customSyntaxSchemes[i] = s
                return CommandResult(message: s.name)
            },
            Command(CommandDescriptor(id: "editor.syntaxScheme.rename", title: L10n.tr("Zmień nazwę motywu kolorów"), category: .tools, submenu: L10n.tr("Ustawienia"),
                                      parameters: [schemeParam, CommandParameter("name", .string, required: true, L10n.tr("Nowa nazwa")),
                                                   CommandParameter("dark", .boolean, L10n.tr("Motyw dla trybu ciemnego"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Zmienia nazwę motywu własnego i jego przypisanie do trybu jasnego albo ciemnego na liście."),
                                      inMenu: false, feature: feature)) { ctx in
                let i = try custom(ctx)
                if let n = ctx.arguments.string("name")?.trimmingCharacters(in: .whitespaces), !n.isEmpty { ctx.workspace.settings.customSyntaxSchemes[i].name = n }
                if let d = ctx.arguments.bool("dark") { ctx.workspace.settings.customSyntaxSchemes[i].isDark = d }
                return CommandResult(message: ctx.workspace.settings.customSyntaxSchemes[i].name)
            },
            Command(CommandDescriptor(id: "editor.syntaxScheme.delete", title: L10n.tr("Usuń motyw kolorów"), category: .tools, submenu: L10n.tr("Ustawienia"),
                                      parameters: [schemeParam], agent: .none, effect: .settings,
                                      summary: L10n.tr("Usuwa motyw własny; tryb, który go używał, wraca do domyślnego motywu Pelikana. Wbudowanych nie można usunąć."),
                                      inMenu: false, feature: feature)) { ctx in
                let i = try custom(ctx)
                let s = ctx.workspace.settings.customSyntaxSchemes.remove(at: i)
                if ctx.workspace.settings.syntaxSchemeLight == s.id { ctx.workspace.settings.syntaxSchemeLight = SyntaxScheme.pelikanLight.id }
                if ctx.workspace.settings.syntaxSchemeDark == s.id { ctx.workspace.settings.syntaxSchemeDark = SyntaxScheme.pelikanDark.id }
                return CommandResult(message: s.name)
            },
            Command(CommandDescriptor(id: "editor.syntaxScheme.import", title: L10n.tr("Importuj motyw kolorów…"), category: .tools, submenu: L10n.tr("Ustawienia"),
                                      parameters: [CommandParameter("file", .string, L10n.tr("Plik motywu: Pelikan .json, base16/base24 .yaml, Xcode .xccolortheme, TextMate .tmTheme, Visual Studio Code .json"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Wczytuje motyw z pliku jako motyw własny: Pelikan, base16/base24, Xcode, TextMate albo Visual Studio Code."),
                                      feature: feature)) { ctx in
                let url: URL
                if let f = ctx.arguments.string("file") { url = URL(fileURLWithPath: (f as NSString).expandingTildeInPath) }
                else if let u = await ctx.ui?.chooseFilesToOpen().first { url = u }
                else { throw CommandError.cancelledByUser }
                let s = try SyntaxSchemeImport.scheme(from: try Data(contentsOf: url), fileName: url.lastPathComponent)
                ctx.workspace.settings.customSyntaxSchemes.append(s)
                return CommandResult(message: s.name, value: describe(s))
            },
            Command(CommandDescriptor(id: "editor.syntaxScheme.export", title: L10n.tr("Eksportuj motyw kolorów…"), category: .tools, submenu: L10n.tr("Ustawienia"),
                                      parameters: [schemeParam, CommandParameter("file", .string, L10n.tr("Plik .json"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje motyw (wbudowany albo własny) do pliku JSON Pelikana — do przeniesienia na inny komputer albo udostępnienia."),
                                      inMenu: false, feature: feature)) { ctx in
                let s = try scheme(ctx)
                let url: URL
                if let f = ctx.arguments.string("file") { url = URL(fileURLWithPath: (f as NSString).expandingTildeInPath) }
                else if let u = await ctx.ui?.chooseSaveURL(suggestedName: s.name, fileExtension: "json") { url = u }
                else { throw CommandError.cancelledByUser }
                try SyntaxSchemeImport.export(s).write(to: url, options: .atomic)
                return CommandResult(message: url.lastPathComponent)
            },
        ]
    }
}
