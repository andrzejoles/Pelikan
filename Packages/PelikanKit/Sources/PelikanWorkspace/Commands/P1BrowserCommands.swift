import Foundation
import PelikanDB
import PelikanSQL

/// Object Browser — domknięcia P1: zmiana nazwy i duplikowanie obiektów (PD-OB-016), upuszczanie obiektu w edytorze
/// i na obszarze okien (PD-OB-010).
@MainActor
enum P1BrowserCommands {
    static let objectMenu = L10n.tr("Obiekt")

    static func command(_ id: CommandID, _ title: String, params: [CommandParameter] = [], agent: AgentAccess, effect: CommandEffect,
                        summary: String, feature: String, validate: (@MainActor @Sendable (Workspace) -> Bool)? = nil,
                        _ run: @escaping CommandHandler) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: .tools, submenu: objectMenu, parameters: params, agent: agent, effect: effect,
                                  summary: summary, feature: feature), validate: validate, run: run)
    }

    /// Nowa nazwa z argumentu `newName` albo z pytania.
    static func newName(_ ctx: CommandContext, title: String, current: String) async throws -> String {
        let raw: String
        if let n = ctx.arguments.string("newName") { raw = n } else {
            guard let n = await ctx.ui?.askText(title, message: L10n.tr("Nowa nazwa"), defaultValue: current.lowercased()) else {
                throw CommandError.cancelledByUser
            }
            raw = n
        }
        guard let name = ObjectRename.normalizedName(raw) else { throw CommandError.invalidArgument("newName", raw) }
        guard name != current else { throw CommandError.cancelledByUser }
        return name
    }

    static func execute(_ sql: String, _ ctx: CommandContext, _ m: MetadataProvider) async throws {
        try await ctx.workspace.guardModification([sql], connectionID: m.connectionID)
        let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: m.connectionID))
        _ = try await s.execute(sql)
    }

    /// Tekst upuszczenia obiektu w edytorze dla akcji (nazwa, kolumny, kod SQL, DDL).
    static func dropText(_ action: BrowserDropAction, _ o: DBObject, _ m: MetadataProvider, ws: Workspace) async throws -> String {
        let schema = (try? await m.currentSchema()) ?? ""
        switch action {
        case .ask, .name: return BrowserDrop.name(o, currentSchema: schema, qualified: false)
        case .qualifiedName: return BrowserDrop.name(o, currentSchema: schema, qualified: true)
        case .columns: return BrowserDrop.namesList(try await m.columns(of: o).filter { $0.kind == .column }.map(\.name))
        case .ddl: return o.type.isProgram ? try await m.source(of: o) : try await m.ddl(of: o)
        case .select, .insert, .update, .delete, .call:
            let r = try await ws.invoke("ob.generateCode", CommandArguments(["object": .string("\"\(o.owner)\".\"\(o.name)\""),
                                                                             "type": .string(o.type.rawValue),
                                                                             "kind": .string(action.codeKind?.rawValue ?? ""),
                                                                             "returnOnly": .bool(true)]))
            return r.value?.stringValue ?? ""
        }
    }

    static var all: [Command] {
        let objectParams = ObjectCommands.objectParams
        return [
            // MARK: Zmiana nazwy (PD-OB-016)
            command("ob.rename", L10n.tr("Zmień nazwę…"),
                    params: objectParams + [CommandParameter("newName", .string, L10n.tr("Nowa nazwa (w cudzysłowie — z zachowaniem wielkości liter)"))],
                    agent: .none, effect: .modifiesDatabase,
                    summary: L10n.tr("Zmienia nazwę tabeli, widoku, sekwencji, synonimu, indeksu albo wyzwalacza (ALTER … RENAME TO / RENAME)."),
                    feature: "PD-OB-016",
                    validate: { ws in ws.selectedObject.map { ObjectRename.renamable.contains($0.type) } ?? false }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                guard ObjectRename.renamable.contains(o.type) else {
                    throw CommandError.notAvailable(L10n.tr("Zmiana nazwy nie jest dostępna dla \(o.type.rawValue)"))
                }
                let name = try await newName(ctx, title: L10n.tr("Zmień nazwę \(o.qualifiedName)"), current: o.name)
                let sql = try ObjectRename.statement(o, to: name, currentSchema: try await m.currentSchema())
                try await execute(sql, ctx, m)
                var renamed = o
                renamed.name = name
                if ctx.workspace.selectedObject == o { ctx.workspace.selectedObject = renamed }
                m.refresh()
                return CommandResult(message: L10n.tr("Zmieniono nazwę na \(name)"), value: .string(sql))
            },
            command("ob.renameChild", L10n.tr("Zmień nazwę elementu…"),
                    params: objectParams + [CommandParameter("kind", .string, required: true, L10n.tr("column, constraint, index albo trigger")),
                                            CommandParameter("name", .string, required: true, L10n.tr("Bieżąca nazwa elementu")),
                                            CommandParameter("newName", .string, L10n.tr("Nowa nazwa"))],
                    agent: .none, effect: .modifiesDatabase,
                    summary: L10n.tr("Zmienia nazwę kolumny, więzu, indeksu albo wyzwalacza tabeli."), feature: "PD-OB-016") { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                guard let rawKind = ctx.arguments.string("kind"), let kind = DBObjectChild.Kind(rawValue: rawKind) else {
                    throw CommandError.invalidArgument("kind", ctx.arguments.string("kind") ?? "")
                }
                guard let child = ctx.arguments.string("name") else { throw CommandError.missingArgument("name") }
                let name = try await newName(ctx, title: L10n.tr("Zmień nazwę \(child)"), current: child)
                let sql = try ObjectRename.childStatement(table: o, kind: kind, name: child, to: name)
                try await execute(sql, ctx, m)
                m.refresh(o)
                return CommandResult(message: L10n.tr("Zmieniono nazwę na \(name)"), value: .string(sql))
            },
            // MARK: Duplikowanie (PD-OB-016)
            command("ob.duplicate", L10n.tr("Duplikuj…"),
                    params: objectParams + [CommandParameter("newName", .string, L10n.tr("Nazwa kopii")),
                                            CommandParameter("withData", .boolean, L10n.tr("Tabela: także wiersze (INSERT … SELECT)"))],
                    agent: .none, effect: .uiState,
                    summary: L10n.tr("Otwiera skrypt kopii obiektu pod nową nazwą (DDL albo źródło) w nowym oknie — do przejrzenia i wykonania."),
                    feature: "PD-OB-016",
                    validate: { ws in ws.selectedObject.map { !$0.type.isGlobal && ![.annotation, .packageBody, .typeBody].contains($0.type) } ?? false }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                let name = try await newName(ctx, title: L10n.tr("Duplikuj \(o.qualifiedName)"), current: o.name)
                var withData = ctx.arguments.bool("withData") ?? false
                if o.type == .table, ctx.arguments.bool("withData") == nil, ctx.arguments.string("newName") == nil {
                    let choice = await ctx.ui?.ask(L10n.tr("Duplikuj \(o.qualifiedName)"), message: L10n.tr("Skopiować także wiersze tabeli?"),
                                                   buttons: [L10n.tr("Tylko struktura"), L10n.tr("Struktura i dane"), L10n.tr("Anuluj")])
                    guard let choice, choice < 2 else { throw CommandError.cancelledByUser }
                    withData = choice == 1
                }
                let source = o.type.isProgram ? try await m.source(of: o) : try await m.ddl(of: o)
                var script = try ObjectRename.duplicateScript(source, object: o, newName: name)
                if o.type.isProgram, !script.hasSuffix("/") { script += "\n/" }
                if o.type == .table, withData {
                    script += "\n\nINSERT INTO \(ResultExporter.identifier(o.owner)).\(ResultExporter.identifier(name)) SELECT * FROM \(o.qualifiedName);\n"
                }
                let doc = ctx.workspace.newDocument(.sql, text: script)
                ctx.workspace.bind(doc, to: m.connectionID)
                doc.isModified = false
                return CommandResult(message: L10n.tr("Skrypt kopii: \(name)"), value: .string(script))
            },
            // MARK: Upuszczenie obiektu (PD-OB-010)
            command("ob.dropText", L10n.tr("Wstaw obiekt do edytora"),
                    params: objectParams + [CommandParameter("action", .string, L10n.tr("Co wstawić; brak — wg preferencji"),
                                                             allowed: BrowserDropAction.allCases.filter { $0 != .ask }.map(\.rawValue))],
                    agent: .none, effect: .modifiesEditor,
                    summary: L10n.tr("Wstawia w miejscu kursora nazwę, listę kolumn, SELECT/INSERT/UPDATE/DELETE, wywołanie albo DDL obiektu (przeciąganie z Object Browsera)."),
                    feature: "PD-OB-010") { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                let raw = ctx.arguments.string("action") ?? ctx.workspace.settings.browserDropAction.rawValue
                guard let action = BrowserDropAction(rawValue: raw) else { throw CommandError.invalidArgument("action", raw) }
                let text = try await dropText(action, o, m, ws: ctx.workspace)
                if let doc = Stage7Commands.editor(ctx.workspace) { try Stage7Commands.insert(text, into: doc) }
                return CommandResult(value: .string(text))
            },
            command("ob.dropOnWorkspace", L10n.tr("Upuść obiekt na obszar okien"),
                    params: objectParams, agent: .none, effect: .uiState,
                    summary: L10n.tr("Akcja z preferencji dla obiektu upuszczonego poza edytorem: Edytuj, Pokaż dane, DDL, Opis albo Właściwości."),
                    feature: "PD-OB-010") { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                let id = ctx.workspace.settings.browserWorkspaceDrop.command(for: o.type)
                return try await ctx.workspace.invoke(id, CommandArguments(["object": .string("\"\(o.owner)\".\"\(o.name)\""),
                                                                           "type": .string(o.type.rawValue),
                                                                           "connection": .string(m.connectionID.uuidString)]))
            },
        ]
    }
}
