import Foundation

/// Generator docs/SKROTY.md z rejestru komend.
public enum ShortcutsDocument {
    public static func markdown(for commands: [CommandDescriptor]) -> String {
        var out = """
        # Skróty klawiszowe i komendy

        Plik generowany z rejestru komend (`PELIKAN_WRITE_DOCS=1 swift test --filter shortcutsDoc`) — nie edytuj ręcznie.
        Skróty profilu PL/SQL Developer oznaczone † są do weryfikacji ze wzorcem (docs/research/keys.md).
        Poziom agenta: Brak / Odczyt / Za zgodą / Pełny (docs/SECURITY.md). Etap > 0 = komenda zapowiedziana (wyszarzona).
        Skróty z ⌘ w profilu PL/SQL Developer to odpowiedniki macOS dodane przez Pelikana. Działają wszystkie skróty
        komendy, nie tylko ten pokazany w menu (D17).

        Kolizje z macOS: ⌃F8 (fokus do menu statusu), ⌃F2/⌃F3 i inne skróty z Ustawienia systemowe › Klawiatura ›
        Skróty klawiszowe › Klawiatura przechwytuje system — użyj odpowiednika z ⌘ albo wyłącz skrót systemowy.
        Klawisze F1–F12 działają jako klawisze funkcyjne po włączeniu „Używaj klawiszy F1, F2 itd. jako standardowych
        klawiszy funkcyjnych” albo z klawiszem fn.


        """
        let verified: Set<String> = ["f1", "f5", "f8", "ctrl+f8", "f11", "f12", "ctrl+e", "ctrl+f", "ctrl+g", "ctrl+-",
                                     "ctrl+tab", "ctrl+shift+tab", "cmd+shift+p"]
        for category in CommandCategory.allCases {
            let items = commands.filter { $0.category == category }
            guard !items.isEmpty else { continue }
            out += "## \(category.displayName)\n\n"
            out += "| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |\n|---|---|---|---|---|---|---|\n"
            for c in items {
                let pd = (c.shortcuts[.plsqlDeveloper] ?? []).map { $0.displayString + (verified.contains($0.description) || $0.modifiers.contains(.command) ? "" : " †") }
                let mac = (c.shortcuts[.macOS] ?? []).map(\.displayString)
                let title = c.submenu.map { "\($0) › \(c.title)" } ?? c.title
                out += "| \(title) | `\(c.id.rawValue)` | \(pd.joined(separator: ", ")) | \(mac.joined(separator: ", ")) | "
                out += "\(c.agentAccess.displayName) | \(c.stage) | \(c.feature ?? "") |\n"
            }
            out += "\n"
        }
        return out
    }
}
