#if canImport(Darwin)
import Foundation
import MCP
import PelikanWorkspace

/// Narzędzia MCP jako widok na rejestr komend (PROMPT §7.5, ARCHITECTURE §5).
public enum ToolCatalog {
    public struct Entry: Sendable {
        public let tool: String
        public let command: CommandID

        init(_ tool: String, _ command: CommandID) {
            self.tool = tool
            self.command = command
        }
    }

    public static let runCommand = "run_command"
    public static let viaRunCommandKey = "__viaRunCommand"

    public static let entries: [Entry] = [
        Entry("list_connections", "agent.connections"),
        Entry("get_state", "agent.state"),
        Entry("get_editor", "agent.editor"),
        Entry("open_editor", "agent.openEditor"),
        Entry("insert_text", "agent.insertText"),
        Entry("replace_range", "agent.replaceRange"),
        Entry("navigate_to", "agent.navigate"),
        Entry("format_code", "agent.format"),
        Entry("open_object", "agent.openObject"),
        Entry("search_objects", "agent.searchObjects"),
        Entry("describe_object", "agent.describe"),
        Entry("get_source", "agent.source"),
        Entry("get_ddl", "agent.ddl"),
        Entry("get_dependencies", "agent.dependencies"),
        Entry("find_usages", "agent.findUsages"),
        Entry("run_query", "agent.query"),
        Entry("explain_plan", "agent.explain"),
        Entry("get_compile_errors", "agent.compileErrors"),
        Entry("get_dbms_output", "agent.dbmsOutput"),
        Entry("list_tests", "agent.listTests"),
        Entry("get_test_results", "agent.testResults"),
        Entry("get_coverage", "agent.coverage"),
        Entry("session_list", "agent.sessions"),
    ]

    public static func entry(named name: String) -> Entry? { entries.first { $0.tool == name } }

    /// Schemat JSON argumentów z parametrów komendy.
    static func schema(for params: [CommandParameter]) -> Value {
        var properties: [String: Value] = [:]
        for p in params {
            var prop: [String: Value] = ["description": .string(p.description)]
            switch p.type {
            case .string, .sql: prop["type"] = "string"
            case .integer: prop["type"] = "integer"
            case .boolean: prop["type"] = "boolean"
            case .object: prop["type"] = "object"
            }
            if let allowed = p.allowedValues { prop["enum"] = .array(allowed.map { .string($0) }) }
            properties[p.name] = .object(prop)
        }
        let required = params.filter(\.required).map { Value.string($0.name) }
        return .object(["type": "object", "properties": .object(properties), "required": .array(required), "additionalProperties": false])
    }

    static func levelNote(_ level: AgentAccess) -> String {
        switch level {
        case .approval: " [Wymaga zatwierdzenia przez użytkownika — Pelikan pokaże mu podgląd skutków.]"
        case .read: " [Tylko odczyt.]"
        default: ""
        }
    }

    /// Narzędzia widoczne dla sesji (poziom > Brak).
    @MainActor
    public static func tools(for session: AgentSession, registry: CommandRegistry, settings: AgentSettings) -> [Tool] {
        var tools: [Tool] = []
        for e in entries {
            guard let command = registry.command(e.command) else { continue }
            let level = AgentPolicy.effectiveAccess(command: command.descriptor, session: session, settings: settings)
            guard level > .none else { continue }
            let readOnly = command.descriptor.effect == .none || command.descriptor.effect == .uiState
            tools.append(Tool(
                name: e.tool,
                description: command.descriptor.summary + levelNote(level),
                inputSchema: schema(for: command.descriptor.parameters),
                annotations: .init(title: command.descriptor.title, readOnlyHint: readOnly,
                                   destructiveHint: [.modifiesDatabase, .transaction].contains(command.descriptor.effect))))
        }
        let available = registry.commands.filter {
            !$0.isPlanned && AgentPolicy.effectiveAccess(command: $0.descriptor, session: session, settings: settings, viaRunCommand: true) > .none
        }
        if !available.isEmpty {
            let list = available.map { "\($0.id.rawValue) — \($0.descriptor.title)" }.joined(separator: "; ")
            tools.append(Tool(
                name: runCommand,
                description: "Wywołuje komendę Pelikana z rejestru (poziom dostępu nie wyższy niż „Za zgodą” i nie wyższy niż poziom komendy). Dostępne: \(list)",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "command": .object(["type": "string", "description": "Identyfikator komendy, np. window.next"]),
                        "arguments": .object(["type": "object", "description": "Argumenty komendy"]),
                    ]),
                    "required": ["command"],
                ]),
                annotations: .init(title: "Komenda Pelikana")))
        }
        return tools
    }
}

extension JSONValue {
    init(mcp value: MCP.Value) {
        switch value {
        case .null: self = .null
        case .bool(let b): self = .bool(b)
        case .int(let i): self = .int(Int64(i))
        case .double(let d): self = .double(d)
        case .string(let s): self = .string(s)
        case .array(let a): self = .array(a.map(JSONValue.init(mcp:)))
        case .object(let o): self = .object(o.mapValues(JSONValue.init(mcp:)))
        case .data(mimeType: _, let d): self = .string(d.base64EncodedString())
        }
    }
}
#endif
