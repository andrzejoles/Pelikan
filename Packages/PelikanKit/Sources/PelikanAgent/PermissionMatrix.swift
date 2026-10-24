#if canImport(Darwin)
import Foundation
import PelikanWorkspace

/// Macierz uprawnień sesji agenta przy starcie (PROMPT §7.4, AI-PERM-001): narzędzia katalogu z poziomem bazowym
/// (komenda obniżona ustawieniami); dla sesji poziom można tylko obniżyć, a obniżenia trafiają do `accessOverrides`.
public struct PermissionRow: Identifiable, Hashable, Sendable {
    public let tool: String
    public let command: CommandID
    public let title: String
    public let base: AgentAccess
    public var chosen: AgentAccess
    public var id: String { tool }
}

public enum PermissionMatrix {
    /// Wiersze dla narzędzi z poziomem wyższym niż Brak (po obniżeniu ustawieniami).
    @MainActor
    public static func rows(registry: CommandRegistry, settings: AgentSettings) -> [PermissionRow] {
        ToolCatalog.entries.compactMap { e in
            guard let d = registry.command(e.command)?.descriptor else { return nil }
            var base = d.agentAccess
            if let o = settings.accessOverrides[e.command.rawValue] { base = min(base, o) }
            guard base > .none else { return nil }
            return PermissionRow(tool: e.tool, command: e.command, title: d.title, base: base, chosen: base)
        }
    }

    /// „Wszystko tylko do odczytu”: każdy wiersz najwyżej Odczyt.
    public static func readOnly(_ rows: [PermissionRow]) -> [PermissionRow] {
        rows.map { var r = $0; r.chosen = min(r.base, .read); return r }
    }

    /// Obniżenia dla sesji (tylko wiersze z poziomem niższym niż bazowy; wyższego wybrać się nie da).
    public static func overrides(_ rows: [PermissionRow]) -> [CommandID: AgentAccess] {
        var out: [CommandID: AgentAccess] = [:]
        for r in rows where r.chosen < r.base { out[r.command] = r.chosen }
        return out
    }
}
#endif
