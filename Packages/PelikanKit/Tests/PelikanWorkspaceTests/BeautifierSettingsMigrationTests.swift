import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Migracja ustawień formatera (D202) — tylko przy odczycie plików: settings.json, sets.json i eksportu w wersji
/// formatu 1. Opcje z wartością równą dawnej domyślnej dostają nową domyślną, zmienione przez użytkownika zostają;
/// częściowy JSON bez znacznika (prefs.import z komendy, agent, makro) to wartości bieżące.
@MainActor
@Suite("Formater — migracja ustawień D202")
struct BeautifierSettingsMigrationTests {
    static let oldBeautifier = #"{"indent":3,"clauseLayout":"leftAligned","caseLayout":"inline","alignDeclarations":false,"alignAssignments":false,"beforeSave":true}"#

    func checkMigrated(_ b: BeautifierOptions) {
        #expect(b.indent == 3 && b.beforeSave)
        #expect(b.clauseLayout == .rightAligned && b.caseLayout == .auto && b.alignDeclarations && b.alignAssignments)
        #expect(b.defaultsVersion == BeautifierOptions.currentDefaultsVersion)
    }

    func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-beau-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
        return dir
    }

    @Test("settings.json sprzed D202 — migracja przy starcie; zapis ze znacznikiem nie migruje ponownie")
    func settingsFile() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"beautifier":\#(Self.oldBeautifier)}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        checkMigrated(Workspace(dataDirectory: dir).settings.beautifier)
        // Plik ze znacznikiem: wybór „do lewej” zostaje.
        var chosen = BeautifierOptions()
        chosen.clauseLayout = .leftAligned
        let json = String(decoding: try JSONEncoder().encode(chosen), as: UTF8.self)
        try Data(#"{"beautifier":\#(json)}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(Workspace(dataDirectory: dir).settings.beautifier.clauseLayout == .leftAligned)
    }

    @Test("sets.json sprzed D202 (zestaw połączenia) — migracja przy odczycie")
    func setsFile() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try JSONDecoder().decode(JSONValue.self, from: Data(Self.oldBeautifier.utf8))
        let set = PreferenceSet(name: "stary", kind: .personalConnection, pattern: "*", values: ["beautifier": old])
        try JSONEncoder().encode([set]).write(to: dir.appendingPathComponent("Preferences/sets.json"))
        var store = PreferenceSetStore(directory: dir)
        let loaded = store.load()
        checkMigrated(PreferenceSets.merge(loaded).beautifier)
    }

    @Test("import: plik eksportu w wersji 1 — migracja; w wersji 2 i częściowy JSON bez znacznika — bez migracji")
    func importFiles() throws {
        let v1 = #"{"format":"pelikan-preferences","version":1,"values":{"beautifier":\#(Self.oldBeautifier)}}"#
        checkMigrated(PreferenceSets.merge([PreferenceSet(name: "i", kind: .personalUser,
                                                          values: try PreferenceSets.importValues(Data(v1.utf8), sections: nil))]).beautifier)
        let v2 = #"{"format":"pelikan-preferences","version":2,"values":{"beautifier":\#(Self.oldBeautifier)}}"#
        let current = PreferenceSets.merge([PreferenceSet(name: "i", kind: .personalUser,
                                                          values: try PreferenceSets.importValues(Data(v2.utf8), sections: nil))]).beautifier
        #expect(current.clauseLayout == .leftAligned && current.caseLayout == .inline && !current.alignDeclarations)
        // Eksport zapisuje wersję 2.
        let exported = try JSONSerialization.jsonObject(with: PreferenceSets.export(Settings(), sections: nil)) as? [String: Any]
        #expect(exported?["version"] as? Int == 2)
        // Częściowy JSON (komenda, agent, makro) — bez migracji.
        let partial = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"clauseLayout":"leftAligned"}"#.utf8))
        #expect(PreferenceSets.merge([PreferenceSet(name: "p", kind: .personalUser, values: ["beautifier": partial])]).beautifier.clauseLayout == .leftAligned)
    }
}
