import Foundation
import PelikanDB
import PelikanSQL

/// Szablony kodu (UG 31, PD-TPL-001…003) i nowy program z szablonu (PD-PROG-002).
enum TemplateCommands {
    static let insertParams = [
        CommandParameter("template", .string, L10n.tr("Szablon: folder/nazwa albo nazwa (bez argumentu — wybór z listy)")),
        CommandParameter("values", .object, L10n.tr("Wartości zmiennych szablonu (nazwa → tekst); brakujące — domyślne")),
    ]

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "edit.insertTemplate", title: L10n.tr("Wstaw szablon…"), category: .edit,
                                      parameters: insertParams, agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Wstawia szablon w miejscu kursora (zmienne z formularza albo z argumentów); bez okna edytora — w nowym oknie."),
                                      inMenu: false, feature: "PD-TPL-002")) { ctx in
                try await insert(ctx, newWindow: false)
            },
            Command(CommandDescriptor(id: "file.newFromTemplate", title: L10n.tr("Nowy program z szablonu…"), category: .file, submenu: L10n.tr("Nowy"),
                                      parameters: insertParams, agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera nowe okno programu (albo SQL dla szablonów spoza jednostek programów) z tekstem szablonu."),
                                      inMenu: false, feature: "PD-PROG-002")) { ctx in
                try await insert(ctx, newWindow: true)
            },
            Command(CommandDescriptor(id: "templates.save", title: L10n.tr("Zapisz zaznaczenie jako szablon…"), category: .tools, submenu: L10n.tr("Szablony"),
                                      parameters: [
                                          CommandParameter("folder", .string, required: true, L10n.tr("Folder szablonu")),
                                          CommandParameter("name", .string, required: true, L10n.tr("Nazwa szablonu")),
                                          CommandParameter("text", .string, L10n.tr("Tekst (domyślnie zaznaczenie albo cały tekst okna)")),
                                      ],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Zapisuje szablon użytkownika (folder/nazwa) w katalogu danych."), feature: "PD-TPL-003")) { ctx in
                var folder = ctx.arguments.string("folder") ?? ""
                var name = ctx.arguments.string("name") ?? ""
                if folder.isEmpty || name.isEmpty {
                    guard let f = await ctx.ui?.askText(L10n.tr("Folder szablonu"), message: "", defaultValue: L10n.tr("Moje")), !f.isEmpty,
                          let n = await ctx.ui?.askText(L10n.tr("Nazwa szablonu"), message: "", defaultValue: ""), !n.isEmpty else {
                        throw CommandError.cancelledByUser
                    }
                    folder = f
                    name = n
                }
                var text = ctx.arguments.string("text")
                if text == nil, let doc = ctx.workspace.activeDocument {
                    let ns = doc.text as NSString
                    let r = doc.selectedRange.clamped(to: 0..<ns.length)
                    text = r.isEmpty ? doc.text : ns.substring(with: NSRange(location: r.lowerBound, length: r.count))
                }
                guard let text, !text.isEmpty else { throw CommandError.missingArgument("text") }
                try ctx.workspace.templates.save(CodeTemplate(folder: folder, name: name, text: text))
                ctx.workspace.templatesGeneration += 1
                return CommandResult(message: L10n.tr("Zapisano szablon \(folder)/\(name)"))
            },
            Command(CommandDescriptor(id: "templates.delete", title: L10n.tr("Usuń szablon"), category: .tools, submenu: L10n.tr("Szablony"),
                                      parameters: [CommandParameter("template", .string, L10n.tr("Szablon użytkownika: folder/nazwa (bez argumentu — wybór z listy)"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Usuwa szablon użytkownika (szablony wbudowane zostają)."), inMenu: false, feature: "PD-TPL-003")) { ctx in
                var id = ctx.arguments.string("template")
                if id == nil, ctx.askingUI != nil {
                    let own = ctx.workspace.templates.all.filter { !$0.isBuiltIn }.map(\.id).sorted()
                    guard !own.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak szablonów użytkownika do usunięcia")) }
                    id = try await ctx.choose(L10n.tr("Usuń szablon"), own.map { (label: $0, value: $0) })
                }
                guard let id, let t = ctx.workspace.templates.template(id), !t.isBuiltIn else {
                    throw CommandError.invalidArgument("template", L10n.tr("brak szablonu użytkownika"))
                }
                try ctx.workspace.templates.delete(t)
                ctx.workspace.templatesGeneration += 1
                return CommandResult(message: L10n.tr("Usunięto szablon \(t.id)"))
            },
            Command(CommandDescriptor(id: "templates.edit", title: L10n.tr("Edytuj szablon…"), category: .tools, submenu: L10n.tr("Szablony"),
                                      parameters: [
                                          CommandParameter("template", .string, L10n.tr("Szablon: folder/nazwa; pusty — nowy szablon")),
                                          CommandParameter("folder", .string, L10n.tr("Nowy folder")),
                                          CommandParameter("name", .string, L10n.tr("Nowa nazwa")),
                                          CommandParameter("text", .string, L10n.tr("Nowy tekst")),
                                      ],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Edytuje tekst, nazwę i folder szablonu (wbudowany — zapisany jako szablon użytkownika) albo tworzy nowy."),
                                      feature: "PD-TPL-003")) { ctx in
                let lib = ctx.workspace.templates
                let old = ctx.arguments.string("template").flatMap { lib.template($0) }
                if ctx.arguments.string("template") != nil, old == nil { throw CommandError.invalidArgument("template", L10n.tr("nie znaleziono szablonu")) }
                let base = old ?? CodeTemplate(folder: L10n.tr("Moje"), name: "", text: "")
                var new = CodeTemplate(folder: ctx.arguments.string("folder") ?? base.folder, name: ctx.arguments.string("name") ?? base.name,
                                       text: ctx.arguments.string("text") ?? base.text)
                // Użytkownik bez argumentów zmian — edytor szablonu.
                if ctx.invoker == .user, ctx.arguments.string("text") == nil, ctx.arguments.string("name") == nil, let ui = ctx.ui {
                    guard let edited = await ui.editTemplate(new, folders: lib.folders) else { throw CommandError.cancelledByUser }
                    new = edited
                }
                guard !new.name.trimmingCharacters(in: .whitespaces).isEmpty, !new.text.isEmpty else { throw CommandError.missingArgument("name") }
                if let old { try lib.update(old, to: new) } else { try lib.save(new) }
                ctx.workspace.templatesGeneration += 1
                return CommandResult(message: L10n.tr("Zapisano szablon \(new.folder)/\(new.name)"))
            },
            Command(CommandDescriptor(id: "templates.newFolder", title: L10n.tr("Nowy folder szablonów…"), category: .tools, submenu: L10n.tr("Szablony"),
                                      parameters: [CommandParameter("folder", .string, L10n.tr("Nazwa folderu"))],
                                      agent: .none, effect: .settings, summary: L10n.tr("Tworzy pusty folder szablonów użytkownika."),
                                      inMenu: false, feature: "PD-TPL-003")) { ctx in
                var name = ctx.arguments.string("folder") ?? ""
                if name.isEmpty {
                    guard let n = await ctx.ui?.askText(L10n.tr("Nowy folder szablonów"), message: "", defaultValue: ""), !n.isEmpty else {
                        throw CommandError.cancelledByUser
                    }
                    name = n
                }
                try ctx.workspace.templates.createFolder(name)
                ctx.workspace.templatesGeneration += 1
                return .ok
            },
            Command(CommandDescriptor(id: "templates.renameFolder", title: L10n.tr("Zmień nazwę folderu szablonów…"), category: .tools,
                                      submenu: L10n.tr("Szablony"),
                                      parameters: [CommandParameter("folder", .string, L10n.tr("Folder (bez argumentu — wybór z listy folderów użytkownika)")),
                                                   CommandParameter("name", .string, L10n.tr("Nowa nazwa"))],
                                      agent: .none, effect: .settings, summary: L10n.tr("Zmienia nazwę folderu szablonów użytkownika (z szablonami)."),
                                      inMenu: false, feature: "PD-TPL-003")) { ctx in
                let folder = try await userFolder(ctx, title: L10n.tr("Zmień nazwę folderu szablonów"))
                var name = ctx.arguments.string("name") ?? ""
                if name.isEmpty {
                    guard let n = await ctx.ui?.askText(L10n.tr("Zmień nazwę folderu szablonów"), message: "", defaultValue: folder), !n.isEmpty else {
                        throw CommandError.cancelledByUser
                    }
                    name = n
                }
                try ctx.workspace.templates.renameFolder(folder, to: name)
                ctx.workspace.templatesGeneration += 1
                return .ok
            },
            Command(CommandDescriptor(id: "templates.deleteFolder", title: L10n.tr("Usuń folder szablonów"), category: .tools, submenu: L10n.tr("Szablony"),
                                      parameters: [CommandParameter("folder", .string, L10n.tr("Folder (bez argumentu — wybór z listy folderów użytkownika)"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Usuwa folder szablonów użytkownika z jego szablonami (wbudowane zostają)."),
                                      inMenu: false, feature: "PD-TPL-003")) { ctx in
                let folder = try await userFolder(ctx, title: L10n.tr("Usuń folder szablonów"))
                if ctx.invoker == .user, let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Usuń folder szablonów"), message: L10n.tr("Usunąć folder „\(folder)” razem z jego szablonami użytkownika?"),
                                       buttons: [L10n.tr("Usuń"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                try ctx.workspace.templates.deleteFolder(folder)
                ctx.workspace.templatesGeneration += 1
                return .ok
            },
        ]
    }

    /// Folder z argumentu, a dla użytkownika bez argumentu — wybór z folderów szablonów użytkownika.
    @MainActor
    static func userFolder(_ ctx: CommandContext, title: String) async throws -> String {
        if let f = ctx.arguments.string("folder") { return f }
        if ctx.askingUI != nil {
            let folders = ctx.workspace.templates.userFolders
            guard !folders.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak folderów szablonów użytkownika")) }
            if let f = try await ctx.choose(title, folders.map { (label: $0, value: $0) }) { return f }
        }
        throw CommandError.missingArgument("folder")
    }

    @MainActor
    static func insert(_ ctx: CommandContext, newWindow: Bool) async throws -> CommandResult {
        let ws = ctx.workspace
        var id = ctx.arguments.string("template")
        // Ze wstążki, menu i palety — bez argumentu: wybór z listy szablonów (jak w panelu Szablony).
        if id == nil, ctx.invoker == .user, let ui = ctx.ui {
            guard let chosen = await ui.chooseValue(newWindow ? L10n.tr("Nowy program z szablonu") : L10n.tr("Wstaw szablon"),
                                                    values: ws.templates.all.map(\.id).sorted()) else { throw CommandError.cancelledByUser }
            id = chosen
        }
        guard let id, let t = ws.templates.template(id) else {
            throw CommandError.invalidArgument("template", L10n.tr("nie znaleziono szablonu"))
        }
        var values: [String: String] = [:]
        if case .object(let o)? = ctx.arguments.values["values"] {
            for (k, v) in o { values[k] = v.stringValue ?? "" }
        }
        let vars = TemplateEngine.variables(t.text).filter { values[$0.name] == nil }
        // Formularz zmiennych (okno „Zmienne”) — tylko dla użytkownika; agent dostaje wartości domyślne.
        if !vars.isEmpty, ctx.invoker == .user, let ui = ctx.ui {
            let requests = vars.map { v -> VariableRequest in
                var o = VariableOptions(name: v.name)
                o.defaultValue = v.defaultValue
                if !v.choices.isEmpty { o.list = v.choices.joined(separator: ","); o.restricted = false }
                return VariableRequest(name: v.name, kind: .substitution, options: o, value: nil)
            }
            guard let host = ws.activeDocument ?? ws.documents.last else {
                // Bez okien formularz nie ma okna nadrzędnego — wartości domyślne.
                return try await finish(ws, t, values: values, newWindow: newWindow)
            }
            guard let answers = await ui.askTemplateValues(requests, document: host) else { throw CommandError.cancelledByUser }
            for (k, v) in answers {
                if case .text(let s) = v { values[k] = s } else if case .list(let l) = v { values[k] = l.joined(separator: ", ") }
            }
        }
        return try await finish(ws, t, values: values, newWindow: newWindow)
    }

    @MainActor
    static func finish(_ ws: Workspace, _ t: CodeTemplate, values: [String: String], newWindow: Bool) async throws -> CommandResult {
        let user = (ws.activeDocument.flatMap { ws.effectiveConnection(of: $0) } ?? ws.sessions.mainConnectionID).flatMap { ws.connections.connection($0)?.target.user }
        let (text, cursor) = TemplateEngine.apply(t.text, values: values, builtins: TemplateEngine.builtins(databaseUser: user))
        let target: Document
        let base: Int
        if !newWindow, let doc = BuiltinCommands.editable(ws) {
            try BuiltinCommands.checkWritable(doc)
            let ns = doc.text as NSString
            let r = doc.selectedRange.clamped(to: 0..<ns.length)
            doc.text = ns.replacingCharacters(in: NSRange(location: r.lowerBound, length: r.count), with: text)
            target = doc
            base = r.lowerBound
        } else {
            target = ws.newDocument(t.folder == TemplateLibrary.programFolder ? .program : .sql, text: text)
            base = 0
        }
        let c = base + (cursor ?? (text as NSString).length)
        target.selectedRange = c..<c
        return CommandResult(message: L10n.tr("Wstawiono szablon \(t.name)"))
    }
}
