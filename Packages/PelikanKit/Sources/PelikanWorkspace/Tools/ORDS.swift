import Foundation
import PelikanDB

/// Oracle REST Data Services (SD-ORDS-001): wykrycie ORDS w bazie, lista modułów i obiektów z REST, skrypty
/// włączenia REST dla schematu i obiektu (do okna SQL — Pelikan ich sam nie wykonuje).
public enum ORDSTools {
    public struct Module: Sendable, Hashable, Identifiable {
        public var name: String
        public var uriPrefix: String
        public var status: String
        public var templates: [String]
        public var id: String { name }
    }

    /// Czy w bazie jest ORDS (pakiet ORDS_METADATA.ORDS widoczny dla użytkownika).
    public static func isInstalled(_ s: any DatabaseSession) async throws -> Bool {
        (try await s.scalar("select count(*) from all_objects where owner = 'ORDS_METADATA' and object_name = 'ORDS' and object_type = 'PACKAGE'")) != "0"
    }

    public static func modules(_ s: any DatabaseSession) async throws -> [Module] {
        let (_, rows) = try await s.queryAll("""
            select m.name, m.uri_prefix, m.status, t.uri_template from user_ords_modules m
              left join user_ords_templates t on t.module_id = m.id order by m.name, t.uri_template
            """, limit: 100_000)
        var out: [Module] = []
        for r in rows {
            let name = r[0].displayText ?? ""
            if out.last?.name != name { out.append(Module(name: name, uriPrefix: r[1].displayText ?? "", status: r[2].displayText ?? "", templates: [])) }
            if let t = r[3].displayText { out[out.count - 1].templates.append(t) }
        }
        return out
    }

    /// Obiekty z włączonym AutoREST: nazwa, typ, alias URL, status.
    public static func enabledObjects(_ s: any DatabaseSession) async throws -> [[String]] {
        let (_, rows) = try await s.queryAll("select parsing_object, object_type, object_alias, status from user_ords_enabled_objects order by parsing_object", limit: 100_000)
        return rows.map { $0.map { $0.displayText ?? "" } }
    }

    static func literal(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    /// Włączenie REST dla schematu (alias URL, autoryzacja metadanych).
    public static func enableSchemaScript(schema: String, urlAlias: String? = nil, requireAuthorization: Bool = true) -> String {
        """
        begin
          ords.enable_schema(p_enabled => true, p_schema => \(literal(schema.uppercased())),
                             p_url_mapping_type => 'BASE_PATH', p_url_mapping_pattern => \(literal((urlAlias?.isEmpty == false ? urlAlias! : schema).lowercased())),
                             p_auto_rest_auth => \(requireAuthorization ? "true" : "false"));
          commit;
        end;
        /
        """
    }

    /// AutoREST dla tabeli, widoku albo pakietu/procedury.
    public static func enableObjectScript(schema: String, object: String, type: String, alias: String? = nil, requireAuthorization: Bool = true) -> String {
        let t = type.uppercased() == "PACKAGE BODY" ? "PACKAGE" : type.uppercased()
        return """
        begin
          ords.enable_object(p_enabled => true, p_schema => \(literal(schema.uppercased())), p_object => \(literal(object.uppercased())),
                             p_object_type => \(literal(t)), p_object_alias => \(literal((alias?.isEmpty == false ? alias! : object).lowercased())),
                             p_auto_rest_auth => \(requireAuthorization ? "true" : "false"));
          commit;
        end;
        /
        """
    }

    /// Wyłączenie AutoREST obiektu.
    public static func disableObjectScript(schema: String, object: String) -> String {
        "begin\n  ords.enable_object(p_enabled => false, p_schema => \(literal(schema.uppercased())), p_object => \(literal(object.uppercased())));\n  commit;\nend;\n/\n"
    }
}

@MainActor
enum ORDSCommands {
    static func session(_ ctx: CommandContext) async throws -> (any DatabaseSession, String) {
        let (s, owner) = try await Oracle23Commands.session(ctx.workspace)
        guard try await ORDSTools.isInstalled(s) else { throw CommandError.notAvailable(L10n.tr("W tej bazie nie ma Oracle REST Data Services (ORDS)")) }
        return (s, owner)
    }

    static var all: [Command] {
        let connected: @MainActor (Workspace) -> Bool = { $0.sessions.mainConnectionID != nil }
        return [
            Command(CommandDescriptor(id: "tools.ordsModules", title: L10n.tr("Moduły REST (ORDS)"), category: .tools, submenu: L10n.tr("REST (ORDS)"),
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Moduły i szablony ORDS schematu oraz obiekty z włączonym AutoREST."), feature: "SD-ORDS-001"),
                    validate: connected) { ctx in
                let (s, _) = try await session(ctx)
                let modules = try await ORDSTools.modules(s)
                let objects = try await ORDSTools.enabledObjects(s)
                var text = L10n.tr("Moduły REST") + "\n"
                for m in modules { text += "  \(m.name)  \(m.uriPrefix)  [\(m.status)]\n" + m.templates.map { "      \($0)\n" }.joined() }
                text += "\n" + L10n.tr("Obiekty z AutoREST") + "\n" + objects.map { "  " + $0.joined(separator: "  ") + "\n" }.joined()
                ctx.ui?.showHTMLReport(title: L10n.tr("Moduły REST (ORDS)"), html: PackCommands.html("ORDS", text))
                return CommandResult(value: .array(modules.map { .object(["name": .string($0.name), "uriPrefix": .string($0.uriPrefix), "status": .string($0.status)]) }))
            },
            Command(CommandDescriptor(id: "tools.ordsEnableSchema", title: L10n.tr("Włącz REST dla schematu…"), category: .tools, submenu: L10n.tr("REST (ORDS)"),
                                      parameters: [CommandParameter("alias", .string, L10n.tr("Alias URL (domyślnie nazwa schematu)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Skrypt ORDS.ENABLE_SCHEMA do nowego okna SQL (do przejrzenia i wykonania)."), feature: "SD-ORDS-001"),
                    validate: connected) { ctx in
                let (_, owner) = try await session(ctx)
                let script = ORDSTools.enableSchemaScript(schema: owner, urlAlias: ctx.arguments.string("alias"))
                ctx.workspace.newDocument(.sql, text: script)
                return CommandResult(value: .string(script))
            },
            Command(CommandDescriptor(id: "tools.ordsEnableObject", title: L10n.tr("Włącz REST dla obiektu…"), category: .tools, submenu: L10n.tr("REST (ORDS)"),
                                      parameters: [CommandParameter("object", .string, required: true, L10n.tr("Obiekt")),
                                                   CommandParameter("type", .string, L10n.tr("Typ (TABLE, VIEW, PACKAGE, PROCEDURE, FUNCTION)")),
                                                   CommandParameter("alias", .string, L10n.tr("Alias URL"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Skrypt ORDS.ENABLE_OBJECT (AutoREST) do nowego okna SQL."), feature: "SD-ORDS-001"),
                    validate: connected) { ctx in
                let (s, owner) = try await session(ctx)
                let object = (ctx.arguments.string("object") ?? "").uppercased()
                var type = ctx.arguments.string("type")
                if type == nil {
                    type = try await s.scalar("select object_type from user_objects where object_name = :n and object_type in ('TABLE','VIEW','PACKAGE','PROCEDURE','FUNCTION') fetch first 1 rows only",
                                              binds: [BindVariable(name: "n", value: .text(object))])
                }
                let script = ORDSTools.enableObjectScript(schema: owner, object: object, type: type ?? "TABLE", alias: ctx.arguments.string("alias"))
                ctx.workspace.newDocument(.sql, text: script)
                return CommandResult(value: .string(script))
            },
        ]
    }
}
