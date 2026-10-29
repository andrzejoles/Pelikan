import Foundation

/// Pasek narzędzi okna głównego i Quick Access Toolbar (UG 34, PD-UI-006): elementy to komendy z rejestru. Układ paska
/// dostosowuje się standardowo (macOS: Dostosuj pasek narzędzi), a pasek szybkiego dostępu to lista komend z Preferencji.
public enum ToolbarModel {
    /// Identyfikator grupy szybkiego dostępu i odstępu elastycznego w układzie paska.
    public static let quickAccessItem = "quickAccess"
    public static let flexibleSpaceItem = "-"
    /// Kapsułki grup kart (D200) — na początku paska, w wolnym miejscu obok tytułu okna.
    public static let tabGroupsItem = "tabGroups"

    /// Domyślny układ paska (identyfikatory komend, `-` — elastyczny odstęp, `quickAccess` — grupa szybkiego dostępu).
    public static let defaultItems: [String] = [
        "tabGroups", "file.new.sql", "file.open", "file.save", "-", "sql.execute", "sql.break", "session.commit", "session.rollback", "-",
        "quickAccess", "-", "session.logon",
    ]

    /// Komendy w palecie dostosowania paska (najczęstsze czynności wzorca).
    public static let paletteCommands: [String] = [
        "file.new.sql", "file.new.program", "file.new.test", "file.new.command", "file.new.explainPlan", "file.new.report",
        "file.open", "file.save", "file.saveAs", "file.print",
        "sql.execute", "sql.break", "sql.historyBack", "sql.historyForward",
        "session.commit", "session.rollback", "session.logon",
        "edit.find", "edit.beautify", "edit.commentLine",
        "tools.explainPlan", "tools.findObjects", "tools.sessions",
        "debug.start", "debug.stepInto", "debug.stepOver", "debug.stepOut", "debug.stop", "debug.toggleBreakpoint",
        "view.commandPalette", "view.objectBrowser", "view.snippets",
    ]

    /// Symbol SF dla komendy (znane komendy; inne — wspólny symbol).
    public static func symbol(for id: String) -> String {
        CommandSymbols.symbol(for: id) ?? "command"
    }

    /// Lista szybkiego dostępu po dodaniu komendy (bez powtórzeń, tylko komendy z rejestru, limit 20).
    @MainActor
    public static func adding(_ id: String, to list: [String], in ws: Workspace) -> [String] {
        guard ws.registry.command(CommandID(rawValue: id)) != nil, !list.contains(id) else { return list }
        return Array((list + [id]).suffix(20))
    }

    /// Lista bez nieznanych komend (np. po usunięciu makra) i powtórzeń.
    @MainActor
    public static func sanitized(_ list: [String], in ws: Workspace) -> [String] {
        var seen = Set<String>()
        return list.filter { ws.registry.command(CommandID(rawValue: $0)) != nil && seen.insert($0).inserted }
    }
}
