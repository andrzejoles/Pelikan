import Foundation
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Rejestr komend i model")
struct CommandRegistryTests {
    @Test("Identyfikatory komend są unikalne")
    func uniqueIDs() {
        let ids = BuiltinCommands.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Brak konfliktów skrótów w obu profilach")
    func noShortcutConflicts() {
        let d = BuiltinCommands.all.map(\.descriptor)
        for profile in ShortcutProfile.allCases {
            let c = Keymap.conflicts(in: d, profile: profile)
            #expect(c.isEmpty, "\(profile): \(c)")
        }
    }

    @Test("Skróty potwierdzone we wzorcu: F8 wykonuje, Ctrl+F8 odwrotnie, F5 Explain Plan, Ctrl+E historia")
    func plsqlDeveloperProfile() {
        let ws = Workspace(profile: .plsqlDeveloper)
        #expect(ws.keymap.command(for: KeyChord(string: "f8")!) == "sql.execute")
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+f8")!) == "sql.executeAlternate")
        #expect(ws.keymap.command(for: KeyChord(string: "f5")!) == "tools.explainPlan")
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+e")!) == "edit.recallStatement")
    }

    @Test("Profil macOS: Cmd+Enter wykonuje, F-klawisze wzorca nadal działają")
    func macProfile() {
        let ws = Workspace(profile: .macOS)
        #expect(ws.keymap.command(for: KeyChord(string: "cmd+enter")!) == "sql.execute")
        #expect(ws.keymap.command(for: KeyChord(string: "f8")!) == "sql.execute")
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+e")!) == nil)
    }

    @Test("Nadpisanie skrótu przez użytkownika")
    func overrides() {
        let ws = Workspace(profile: .plsqlDeveloper)
        ws.keyOverrides = ["ctrl+enter": "sql.executeAlternate", "f8": ""]
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+enter")!) == "sql.executeAlternate")
        #expect(ws.keymap.command(for: KeyChord(string: "f8")!) == nil)
    }

    @Test("Nowe okna, numeracja, aktywacja, zamykanie i przełączanie")
    func documents() async throws {
        let ws = Workspace()
        try await ws.invoke("file.new.sql")
        try await ws.invoke("file.new.sql")
        try await ws.invoke("file.new.program")
        #expect(ws.documents.map(\.fullTitle) == ["Okno SQL – Nowe", "Okno SQL – Nowe 2", "Okno programu – Nowe"])
        #expect(ws.activeDocument?.kind == .program)
        ws.cycleDocuments(forward: true)
        #expect(ws.activeDocument?.ordinal == 1 && ws.activeDocument?.kind == .sql)
        try await ws.invoke("file.close")
        #expect(ws.documents.count == 2)
        #expect(ws.activeDocument?.fullTitle == "Okno SQL – Nowe 2")
    }

    @Test("Komenda zapowiedziana jest wyłączona i zwraca czytelny błąd")
    func plannedCommand() async {
        let ws = Workspace()
        #expect(!ws.isEnabled("tools.scheduler"))
        await #expect(throws: CommandError.self) { try await ws.invoke("tools.scheduler") }
    }

    @Test("Komenda wyłączona w bieżącym stanie (COMMIT bez transakcji) nie wykonuje się — także dla agenta")
    func disabledCommand() async {
        let ws = Workspace()
        _ = ws.newDocument(.sql)
        #expect(!ws.isEnabled("session.commit"))
        await #expect(throws: CommandError.self) { try await ws.invoke("session.commit", invoker: .agent(sessionID: "t", agentName: "test")) }
    }

    @Test("Każda komenda wskazuje istniejący wiersz macierzy funkcji")
    func featureIDsExist() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/FEATURES.md").standardizedFileURL
        let text = try String(contentsOf: url, encoding: .utf8)
        for c in BuiltinCommands.all {
            guard let f = c.descriptor.feature else { continue }
            #expect(text.contains("| \(f) |"), "\(c.id) → \(f)")
        }
    }

    /// docs/SKROTY.md generowany z rejestru (PROMPT §4.2 p.1). PELIKAN_WRITE_DOCS=1 nadpisuje plik; bez tego test
    /// sprawdza, czy plik jest aktualny.
    @Test("docs/SKROTY.md jest aktualny")
    func shortcutsDoc() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/SKROTY.md").standardizedFileURL
        let generated = ShortcutsDocument.markdown(for: BuiltinCommands.all.map(\.descriptor))
        if ProcessInfo.processInfo.environment["PELIKAN_WRITE_DOCS"] == "1" {
            try generated.write(to: url, atomically: true, encoding: .utf8)
        }
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        #expect(current == generated, "Uruchom: PELIKAN_WRITE_DOCS=1 swift test --filter shortcutsDoc")
    }
}

@MainActor
@Suite("Własne skróty klawiszowe")
struct KeyboardCustomizationTests {
    @Test("Przypisanie skrótu przejmuje go od innej komendy; usunięcie domyślnego; przywrócenie domyślnych")
    func customize() {
        let ws = Workspace(profile: .plsqlDeveloper)
        let f9 = KeyChord(string: "f9")!
        let f8 = KeyChord(string: "f8")!
        #expect(ws.keymap.command(for: f8) == "sql.execute")
        ws.assignShortcut(f9, to: "sql.execute")
        #expect(ws.keymap.command(for: f9) == "sql.execute")
        #expect(ws.keymap.chords(for: "sql.execute").contains(f8))     // domyślny zostaje, dopóki go nie usunąć
        ws.removeShortcut(f8)
        #expect(ws.keymap.command(for: f8) == nil)
        #expect(ws.conflictingCommand(for: KeyChord(string: "f10")!, assigning: "sql.execute") == "session.commit")
        ws.resetShortcuts(for: "sql.execute")
        #expect(ws.keymap.command(for: f8) == "sql.execute")
        #expect(ws.keymap.command(for: f9) == ws.defaultCommand(for: f9))    // F9 wraca do domyślnej komendy profilu
        ws.assignShortcut(f9, to: "session.commit")
        ws.resetShortcuts()
        #expect(ws.settings.keyOverrides.isEmpty)
    }

    @Test("Zmiana profilu skrótów przebudowuje mapę klawiszy")
    func profile() {
        let ws = Workspace(profile: .plsqlDeveloper)
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+f8")!) == "sql.executeAlternate")
        ws.settings.shortcutProfile = .macOS
        #expect(ws.keymap.command(for: KeyChord(string: "cmd+shift+enter")!) == "sql.executeAlternate")
    }
}
