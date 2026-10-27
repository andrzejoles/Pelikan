import Foundation
import PelikanDB

/// Akcje wspólne dla wielu obiektów zaznaczonych w Object Browserze (PD-OB-011): kopiowanie nazw po przecinku,
/// rekompilacja, DDL w jednym oknie, usuwanie po jednym potwierdzeniu.
enum MultiObjectCommands {
    static let objectsParam = CommandParameter("objects", .string,
                                               L10n.tr("Obiekty „SCHEMAT.NAZWA:TYP” po przecinku (domyślnie zaznaczone w Object Browserze)"))

    /// Część nazwy z argumentu: w cudzysłowie bez zmiany wielkości liter (jak `MetadataProvider.find`), inaczej wielkie litery.
    nonisolated static func identifierPart(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") else { return t.uppercased() }
        return String(t.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
    }

    /// `HR.EMP:TABLE, HR.PKG:PACKAGE BODY` → obiekty; bez argumentu — zaznaczenie (albo pojedynczy wybrany obiekt).
    @MainActor
    static func targets(_ ctx: CommandContext) throws -> [DBObject] {
        if let list = ctx.arguments.string("objects") {
            let objs = try list.split(separator: ",").map { item -> DBObject in
                let parts = item.trimmingCharacters(in: .whitespaces).split(separator: ":", maxSplits: 1).map(String.init)
                let name = parts[0].split(separator: ".", maxSplits: 1).map(String.init)
                guard parts.count == 2, name.count == 2, let type = DBObjectType(rawValue: parts[1].uppercased()) else {
                    throw CommandError.invalidArgument("objects", L10n.tr("Oczekiwano SCHEMAT.NAZWA:TYP, otrzymano „\(item)”"))
                }
                return DBObject(owner: identifierPart(name[0]), name: identifierPart(name[1]), type: type)
            }
            guard !objs.isEmpty else { throw CommandError.invalidArgument("objects", L10n.tr("Pusta lista obiektów")) }
            return objs
        }
        let sel = ctx.workspace.selectedObjects.isEmpty ? ctx.workspace.selectedObject.map { [$0] } ?? [] : ctx.workspace.selectedObjects
        guard !sel.isEmpty else { throw CommandError.notAvailable(L10n.tr("Nie zaznaczono obiektów")) }
        return sel
    }

    /// Nazwy po przecinku: bez schematu dla bieżącego, z kwalifikacją dla innych (jak Kopiuj nazwę).
    nonisolated static func commaSeparated(_ objs: [DBObject], currentSchema: String) -> String {
        objs.map { $0.owner == currentSchema ? ResultExporter.displayIdentifier($0.name) : ResultExporter.displayQualified(owner: $0.owner, name: $0.name) }
            .joined(separator: ", ")
    }

    /// DROP obiektu (Usuń obiekt i Usuń zaznaczone): synonim i łącze publiczne bez schematu, łącze bazy z nazwą
    /// z kropkami bez cudzysłowów, katalog bez schematu; zadań i kolejek nie usuwa DROP (DBMS_SCHEDULER, DBMS_AQADM).
    nonisolated static func dropStatement(_ o: DBObject, cascadeConstraints: Bool = true) throws -> String {
        switch o.type {
        case .job, .queue:
            throw CommandError.notAvailable(L10n.tr("Zadania i kolejki usuwa się przez DBMS_SCHEDULER i DBMS_AQADM, nie przez DROP"))
        case .synonym where o.owner == "PUBLIC":
            return "DROP PUBLIC SYNONYM \(ResultExporter.identifier(o.name))"
        case .databaseLink:
            return o.owner == "PUBLIC" ? "DROP PUBLIC DATABASE LINK \(o.name)" : "DROP DATABASE LINK \(o.name)"
        case .directory:
            return "DROP DIRECTORY \(ResultExporter.identifier(o.name))"
        case .table:
            return "DROP TABLE \(o.qualifiedName)" + (cascadeConstraints ? " CASCADE CONSTRAINTS" : "")
        default:
            return "DROP \(o.type.rawValue) \(o.qualifiedName)"
        }
    }

    @MainActor static var hasSelection: ValidationHandler { { $0.selectedObjects.count > 1 || $0.selectedObject != nil } }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "ob.copyNames", title: L10n.tr("Kopiuj nazwy po przecinku"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: [objectsParam], agent: .none, effect: .none,
                                      summary: L10n.tr("Kopiuje nazwy zaznaczonych obiektów oddzielone przecinkami (Cmd+C w Object Browserze)."),
                                      feature: "PD-OB-011"),
                    validate: hasSelection) { ctx in
                let objs = try targets(ctx)
                let schema = (try? await ctx.workspace.metadata()?.currentSchema()) ?? ""
                let text = commaSeparated(objs, currentSchema: schema)
                ctx.workspace.ui?.copyToClipboard(text, html: nil)
                return CommandResult(message: text, value: .string(text))
            },
            Command(CommandDescriptor(id: "ob.recompileSelected", title: L10n.tr("Rekompiluj zaznaczone"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: [objectsParam], agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Kompiluje ponownie zaznaczone obiekty; zwraca te, które pozostały nieprawidłowe."),
                                      feature: "PD-OB-011"),
                    validate: hasSelection) { ctx in
                let objs = try targets(ctx)
                guard let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
                let sql = objs.compactMap(ObjectCommands.compileStatement)
                guard !sql.isEmpty else { throw CommandError.notAvailable(L10n.tr("Żadnego z zaznaczonych obiektów nie da się kompilować")) }
                try await ctx.workspace.guardModification(sql, connectionID: m.connectionID)
                let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: m.connectionID))
                var invalid: [String] = []
                for o in objs {
                    guard let q = ObjectCommands.compileStatement(o) else { continue }
                    _ = try? await s.execute(q)
                    let st = try? await s.scalar("select status from all_objects where owner = :o and object_name = :n and object_type = :t",
                                                 binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name)),
                                                         BindVariable(name: "t", value: .text(o.type.rawValue))])
                    if st != "VALID" { invalid.append(o.qualifiedName) }
                }
                m.refresh()
                return CommandResult(message: invalid.isEmpty ? L10n.tr("Skompilowano: \(sql.count)") : L10n.tr("Nieprawidłowe po kompilacji: \(invalid.joined(separator: ", "))"),
                                     value: .array(invalid.map { .string($0) }))
            },
            Command(CommandDescriptor(id: "ob.ddlSelected", title: L10n.tr("DDL zaznaczonych"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: [objectsParam], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera DDL wszystkich zaznaczonych obiektów w jednym oknie SQL."), feature: "PD-OB-011"),
                    validate: hasSelection) { ctx in
                let objs = try targets(ctx)
                guard let m = ctx.workspace.metadata() else { throw CommandError.notConnected }
                var parts: [String] = []
                for o in objs { parts.append((try? await m.ddl(of: o)) ?? "-- \(o.qualifiedName): " + L10n.tr("brak DDL")) }
                let text = parts.joined(separator: "\n\n")
                _ = try await ObjectCommands.sqlWindow(ctx.workspace, title: L10n.tr("DDL (\(objs.count))"), text: text, execute: false)
                return CommandResult(message: text)
            },
            Command(CommandDescriptor(id: "ob.dropSelected", title: L10n.tr("Usuń zaznaczone…"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: [objectsParam], agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Usuwa zaznaczone obiekty (DROP) po jednym potwierdzeniu z listą; błędy nie przerywają pozostałych."),
                                      feature: "PD-OB-011"),
                    validate: hasSelection) { ctx in
                let objs = try targets(ctx).filter { ![.user, .role, .profile].contains($0.type) }
                guard let m = ctx.workspace.metadata(), !objs.isEmpty else { throw CommandError.notConnected }
                let sql = try objs.map { try dropStatement($0) }
                try await ctx.workspace.guardModification(sql, connectionID: m.connectionID)
                if ctx.invoker == .user, let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Usunąć \(objs.count) obiektów?"), message: objs.map(\.qualifiedName).joined(separator: "\n"),
                                       buttons: [L10n.tr("Usuń"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: m.connectionID))
                var failed: [String] = []
                for (o, q) in zip(objs, sql) {
                    do { _ = try await s.execute(q) } catch { failed.append("\(o.qualifiedName): \(error.localizedDescription)") }
                }
                ctx.workspace.selectedObjects = []
                ctx.workspace.selectedObject = nil
                m.refresh()
                return CommandResult(message: failed.isEmpty ? L10n.tr("Usunięto: \(objs.count)") : failed.joined(separator: "\n"),
                                     value: .int(Int64(objs.count - failed.count)))
            },
        ]
    }
}
