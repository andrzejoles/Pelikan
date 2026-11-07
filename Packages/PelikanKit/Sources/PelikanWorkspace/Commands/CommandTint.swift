import Foundation

/// Barwa ikony komendy (kolorowe ikony wstążki): rodzaj czynności, nie karta wstążki — ta sama czynność ma ten sam kolor
/// na wstążce, pasku narzędzi, w palecie i menu. Kształt symbolu nadal niesie znaczenie (daltonizm, druk, tryb
/// jednobarwny); kolor tylko przyspiesza rozpoznanie.
public enum CommandTint: String, Sendable, CaseIterable {
    /// Wykonanie, uruchomienie, kompilacja, zatwierdzenie (COMMIT) — zielony.
    case run
    /// Przerwanie, zatrzymanie, usunięcie (DROP, DELETE) — czerwony.
    case stop
    /// Wycofanie (ROLLBACK), cofnięcie zmian — pomarańczowy.
    case revert
    /// Nowe okno, plik, zapis — niebieski.
    case document
    /// Debuger i testy (utPLSQL) — fioletowy.
    case debug
    /// Dane, siatka, obiekty bazy, połączenia — morski.
    case data
    /// Wydajność, plany, raporty — różowy.
    case insight
    /// Agenci AI — miętowy.
    case ai
    /// Zakładki, zadania (To-Do), ulubione — żółty.
    case mark
    /// Edycja, widok, ustawienia — jak etykieta (bez koloru).
    case neutral

    /// Barwy wyróżniane także w stylu „akcenty” (pozostałe jak etykieta).
    public var isAccent: Bool { [.run, .stop, .revert, .debug, .ai].contains(self) }

    /// Barwa komendy: najpierw wyjątki (najczęstsze czynności i czynności nieodwracalne), potem obszar z przedrostka
    /// identyfikatora.
    public static func tint(for id: String) -> CommandTint {
        if let t = overrides[id] { return t }
        let prefix = id.split(separator: ".").first.map(String.init) ?? id
        return prefixes[prefix] ?? .neutral
    }

    static let overrides: [String: CommandTint] = [
        // Wykonanie, kompilacja, zatwierdzenie
        "sql.execute": .run, "sql.executeAlternate": .run, "window.execute": .run, "prog.safeCompile": .run,
        "prog.runBlock": .run, "cmd.executeLine": .run, "session.commit": .run, "grid.post": .run, "report.run": .run,
        // Przerwanie i czynności nieodwracalne
        "sql.break": .stop, "debug.stop": .stop, "utplsql.cancel": .stop, "ob.drop": .stop, "ob.dropSelected": .stop,
        "grid.deleteRecord": .stop, "connection.delete": .stop, "connection.deleteFolder": .stop,
        // Wycofanie
        "session.rollback": .revert, "grid.cancelChanges": .revert, "grid.revertRowChanges": .revert, "prog.revert": .revert,
        // Połączenie okna i sesja
        "session.logon": .data, "session.logoff": .data, "session.windowConnection": .data, "window.reconnect": .data,
        "tools.findObjects": .data, "codeContents.test": .debug, "tools.testManager": .debug, "test.profiler": .insight,
        "test.trace": .insight, "tools.sessions": .data, "tools.export": .data, "tools.import": .data,
        // Zakładki i zadania
        "edit.todoInsert": .mark, "edit.todoToggle": .mark, "view.todoItems": .mark,
    ]

    static let prefixes: [String: CommandTint] = [
        "file": .document, "project": .document, "templates": .document, "fb": .document,
        "workset": .document, "vcs": .document, "proc": .document, "ssh": .document,
        "debug": .debug, "test": .debug, "utplsql": .debug, "testManager": .debug,
        "grid": .data, "ob": .data, "connection": .data, "session": .data, "transfer": .data, "dba": .data,
        "diagram": .data, "cart": .data,
        "perf": .insight, "plan": .insight, "stats": .insight, "reports": .insight, "report": .insight,
        "codeHierarchy": .insight,
        "agent": .ai,
        "localTasks": .mark,
        "prog": .document, "notebook": .document,
    ]
}
