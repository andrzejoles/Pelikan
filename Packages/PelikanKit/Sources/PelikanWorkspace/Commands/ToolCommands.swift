import Foundation
import PelikanDB

/// Narzędzia (menu Narzędzia): Find Database Objects, Compile Invalid Objects.
enum ToolCommands {
    /// Kryteria Find Database Objects z argumentów; `saved` — zapisane kryteria jako podstawa.
    @MainActor static func searchCriteria(_ ctx: CommandContext) throws -> DatabaseSearchCriteria {
        var c = DatabaseSearchCriteria()
        if let name = ctx.arguments.string("saved") {
            guard let s = ctx.workspace.settings.savedDatabaseSearches.first(where: { $0.name == name }) else {
                throw CommandError.invalidArgument("saved", name)
            }
            c = s.criteria
        }
        if let t = ctx.arguments.string("text") { c.text = t }
        if let b = ctx.arguments.bool("caseSensitive") { c.caseSensitive = b }
        if let b = ctx.arguments.bool("wholeWords") { c.wholeWords = b }
        if let b = ctx.arguments.bool("regex") { c.regularExpression = b }
        if let o = ctx.arguments.string("owner") {
            c.owners = o.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
        }
        if let n = ctx.arguments.string("name") { c.nameFilter = n }
        if let raw = ctx.arguments.string("types") {
            c.types = try raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }.map {
                guard let t = DBObjectType(rawValue: $0) else { throw CommandError.invalidArgument("types", $0) }
                return t
            }
        }
        if let b = ctx.arguments.bool("names") { c.searchNames = b }
        if let b = ctx.arguments.bool("tableDefinitions") { c.searchTableDefinitions = b }
        return c
    }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "tools.saveObjectSearch", title: L10n.tr("Zapisz kryteria wyszukiwania"), category: .tools,
                                      parameters: [
                                          CommandParameter("saveAs", .string, required: true, L10n.tr("Nazwa kryteriów")),
                                          CommandParameter("text", .string, L10n.tr("Szukany tekst")),
                                          CommandParameter("caseSensitive", .boolean, L10n.tr("Rozróżniaj wielkość liter")),
                                          CommandParameter("wholeWords", .boolean, L10n.tr("Całe słowa")),
                                          CommandParameter("regex", .boolean, L10n.tr("Wyrażenie regularne (składnia REGEXP_LIKE)")),
                                          CommandParameter("owner", .string, L10n.tr("Właściciele po przecinku")),
                                          CommandParameter("name", .string, L10n.tr("Filtr nazw obiektów z %")),
                                          CommandParameter("types", .string, L10n.tr("Typy po przecinku, np. PACKAGE BODY, VIEW, TABLE, MLE MODULE")),
                                          CommandParameter("names", .boolean, L10n.tr("Szukaj także w nazwach obiektów (domyślnie tak)")),
                                          CommandParameter("tableDefinitions", .boolean, L10n.tr("Szukaj w definicjach tabel (kolumny, komentarze, CHECK)")),
                                      ],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Zapisuje kryteria Find Database Objects pod nazwą (zastępuje kryteria o tej samej nazwie)."),
                                      inMenu: false, feature: "PD-TOOL-001")) { ctx in
                guard let name = ctx.arguments.string("saveAs")?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                    throw CommandError.missingArgument("saveAs")
                }
                let c = try searchCriteria(ctx)
                var list = ctx.workspace.settings.savedDatabaseSearches.filter { $0.name != name }
                list.append(SavedDatabaseSearch(name: name, criteria: c))
                ctx.workspace.settings.savedDatabaseSearches = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                return CommandResult(message: L10n.tr("Zapisano kryteria: \(name)"))
            },
            Command(CommandDescriptor(id: "tools.deleteObjectSearch", title: L10n.tr("Usuń zapisane kryteria wyszukiwania"), category: .tools,
                                      parameters: [CommandParameter("saved", .string, required: true, L10n.tr("Nazwa zapisanych kryteriów"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Usuwa zapisane kryteria Find Database Objects."), inMenu: false, feature: "PD-TOOL-001")) { ctx in
                guard let name = ctx.arguments.string("saved") else { throw CommandError.missingArgument("saved") }
                ctx.workspace.settings.savedDatabaseSearches.removeAll { $0.name == name }
                return .ok
            },
            Command(CommandDescriptor(id: "tools.findObjects", title: L10n.tr("Znajdź obiekty bazy…"), category: .tools,
                                      pd: ["ctrl+shift+o"], mac: ["cmd+shift+o"],
                                      parameters: [
                                          CommandParameter("text", .string, L10n.tr("Szukany tekst (bez — okno wyszukiwania)")),
                                          CommandParameter("caseSensitive", .boolean, L10n.tr("Rozróżniaj wielkość liter")),
                                          CommandParameter("wholeWords", .boolean, L10n.tr("Całe słowa")),
                                          CommandParameter("regex", .boolean, L10n.tr("Wyrażenie regularne (składnia REGEXP_LIKE)")),
                                          CommandParameter("owner", .string, L10n.tr("Właściciel (domyślnie bieżący schemat)")),
                                          CommandParameter("name", .string, L10n.tr("Filtr nazw obiektów z %")),
                                          CommandParameter("types", .string, L10n.tr("Typy po przecinku, np. PACKAGE BODY, VIEW, TABLE, MLE MODULE")),
                                          CommandParameter("names", .boolean, L10n.tr("Szukaj także w nazwach obiektów (domyślnie tak)")),
                                          CommandParameter("tableDefinitions", .boolean, L10n.tr("Szukaj w definicjach tabel (kolumny, komentarze, CHECK)")),
                                          CommandParameter("saved", .string, L10n.tr("Nazwa zapisanych kryteriów")),
                                      ],
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Wyszukuje tekst w źródłach PL/SQL, zapytaniach widoków i nazwach obiektów; wynik: obiekt, linia, tekst."),
                                      feature: "PD-TOOL-001"),
                    validate: { $0.metadata(for: $0.toolConnection()) != nil }) { ctx in
                let c = try searchCriteria(ctx)
                guard !c.text.isEmpty else {
                    ctx.ui?.showFindObjects(c)
                    return .ok
                }
                guard let m = ctx.workspace.metadata(for: ctx.workspace.toolConnection()) else { throw CommandError.notConnected }
                let hits = try await DatabaseSearch.search(c, metadata: m, limit: 2000)
                return CommandResult(message: L10n.tr("Znaleziono: \(hits.count)"), value: .array(hits.map { h in
                    .object(["object": .string("\(h.object.owner).\(h.object.name)"), "type": .string(h.object.type.rawValue),
                             "line": .int(Int64(h.line)), "text": .string(h.text)])
                }))
            },
            Command(CommandDescriptor(id: "tools.compileInvalid", title: L10n.tr("Kompiluj niepoprawne obiekty…"), category: .tools,
                                      parameters: [
                                          CommandParameter("owner", .string, L10n.tr("Właściciel (domyślnie bieżący schemat)")),
                                          CommandParameter("run", .boolean, L10n.tr("Kompiluj od razu (bez — tylko lista)")),
                                      ],
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Lista nieprawidłowych obiektów schematu i ich kompilacja w kolejności zależności (ALTER … COMPILE) z błędami."),
                                      feature: "PD-TOOL-002"),
                    validate: { $0.metadata(for: $0.toolConnection()) != nil }) { ctx in
                guard let m = ctx.workspace.metadata(for: ctx.workspace.toolConnection()) else { throw CommandError.notConnected }
                if ctx.arguments.isEmpty, ctx.ui != nil, ctx.invoker == .user {
                    ctx.ui?.showCompileInvalid()
                    return .ok
                }
                var owner = ctx.arguments.string("owner")?.uppercased() ?? ""
                if owner.isEmpty { owner = try await m.currentSchema() }
                let list = try await InvalidObjects.list(m, owner: owner)
                guard ctx.arguments.bool("run") == true, !list.isEmpty else {
                    return CommandResult(message: L10n.tr("Nieprawidłowe obiekty: \(list.count)"),
                                         value: .array(list.map { .string("\($0.type.rawValue) \($0.owner).\($0.name)") }))
                }
                let results = try await InvalidObjects.compile(list, in: ctx.workspace, connectionID: m.connectionID)
                let failed = results.filter { !$0.valid }
                return CommandResult(message: L10n.tr("Skompilowano: \(results.count - failed.count) z \(results.count)"),
                                     value: .array(failed.map { r in
                                         .object(["object": .string("\(r.object.type.rawValue) \(r.object.owner).\(r.object.name)"),
                                                  "errors": .array(r.errors.map { .string($0) })])
                                     }))
            },
        ]
    }
}

extension Workspace {
    /// Otwiera obiekt (źródło w oknie programu, pozostałe — DDL) i ustawia kursor w linii źródła danej jednostki.
    public func openObject(_ o: DBObject, line: Int = 0) async throws {
        recordJump()
        try await invoke("ob.edit", CommandArguments(["object": .string("\"\(o.owner)\".\"\(o.name)\""), "type": .string(o.type.rawValue)]))
        guard line > 0, let doc = activeDocument, doc.kind == .program else { return }
        let unit = ProgramCompiler.units(in: doc.text).first { $0.type == o.type } ?? ProgramCompiler.units(in: doc.text).first
        let offset = ProgramCompiler.offset(line: (unit?.line ?? 0) + line, column: 1, in: doc.text)
        doc.selectedRange = offset..<offset
    }
}
