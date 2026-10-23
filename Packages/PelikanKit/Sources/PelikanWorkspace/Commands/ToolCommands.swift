import Foundation
import PelikanDB

/// Narzędzia (menu Narzędzia): Find Database Objects, Compile Invalid Objects.
enum ToolCommands {
    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "tools.findObjects", title: L10n.tr("Znajdź obiekty bazy…"), category: .tools,
                                      pd: ["ctrl+shift+o"], mac: ["cmd+shift+o"],
                                      parameters: [
                                          CommandParameter("text", .string, L10n.tr("Szukany tekst (bez — okno wyszukiwania)")),
                                          CommandParameter("caseSensitive", .boolean, L10n.tr("Rozróżniaj wielkość liter")),
                                          CommandParameter("wholeWords", .boolean, L10n.tr("Całe słowa")),
                                          CommandParameter("regex", .boolean, L10n.tr("Wyrażenie regularne (składnia REGEXP_LIKE)")),
                                          CommandParameter("owner", .string, L10n.tr("Właściciel (domyślnie bieżący schemat)")),
                                          CommandParameter("name", .string, L10n.tr("Filtr nazw obiektów z %")),
                                      ],
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Wyszukuje tekst w źródłach PL/SQL, zapytaniach widoków i nazwach obiektów; wynik: obiekt, linia, tekst."),
                                      feature: "PD-TOOL-001"),
                    validate: { $0.metadata() != nil }) { ctx in
                var c = DatabaseSearchCriteria(text: ctx.arguments.string("text") ?? "")
                c.caseSensitive = ctx.arguments.bool("caseSensitive") ?? false
                c.wholeWords = ctx.arguments.bool("wholeWords") ?? false
                c.regularExpression = ctx.arguments.bool("regex") ?? false
                if let o = ctx.arguments.string("owner") { c.owners = [o.uppercased()] }
                c.nameFilter = ctx.arguments.string("name") ?? ""
                guard !c.text.isEmpty else {
                    ctx.ui?.showFindObjects(c)
                    return .ok
                }
                guard let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
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
                                      agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Lista nieprawidłowych obiektów schematu i ich kompilacja w kolejności zależności (ALTER … COMPILE) z błędami."),
                                      feature: "PD-TOOL-002"),
                    validate: { $0.metadata() != nil }) { ctx in
                guard let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
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
