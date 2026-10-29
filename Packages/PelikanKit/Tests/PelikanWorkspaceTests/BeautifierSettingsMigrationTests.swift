import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Migracja ustawień formatera (D202) w pliku ustawień, zestawach preferencji (osobisty, połączenia) i imporcie:
/// opcje z wartością równą dawnej domyślnej dostają nową domyślną, zmienione przez użytkownika zostają.
@Suite("Formater — migracja ustawień D202")
struct BeautifierSettingsMigrationTests {
    static let oldBeautifier = #"{"indent":3,"clauseLayout":"leftAligned","caseLayout":"inline","alignDeclarations":false,"alignAssignments":false,"beforeSave":true}"#

    func check(_ b: BeautifierOptions) {
        #expect(b.indent == 3 && b.beforeSave)
        #expect(b.clauseLayout == .rightAligned && b.caseLayout == .auto && b.alignDeclarations && b.alignAssignments)
        #expect(b.defaultsVersion == BeautifierOptions.currentDefaultsVersion)
    }

    @Test("plik ustawień ze starym zapisem formatera")
    func settingsFile() throws {
        let s = try JSONDecoder.pelikan.decode(Settings.self, from: Data(#"{"beautifier":\#(Self.oldBeautifier)}"#.utf8))
        check(s.beautifier)
        // Zapisany po migracji — znacznik w pliku, wybór użytkownika po migracji zostaje.
        var chosen = s
        chosen.beautifier.clauseLayout = .leftAligned
        let again = try JSONDecoder.pelikan.decode(Settings.self, from: JSONEncoder.pelikan.encode(chosen))
        #expect(again.beautifier.clauseLayout == .leftAligned)
    }

    @Test("zestaw preferencji osobisty i połączenia oraz import ze starego pliku")
    func preferenceSetsAndImport() throws {
        let old = try JSONDecoder().decode(JSONValue.self, from: Data(Self.oldBeautifier.utf8))
        for kind in [PreferenceSet.Kind.personalUser, .personalConnection] {
            let set = PreferenceSet(name: "stary", kind: kind, pattern: kind.isConnection ? "*" : nil, values: ["beautifier": old])
            check(PreferenceSets.merge([set]).beautifier)
        }
        let file = #"{"format":"pelikan-preferences","version":1,"values":{"beautifier":\#(Self.oldBeautifier)}}"#
        let imported = try PreferenceSets.importValues(Data(file.utf8), sections: nil)
        let set = PreferenceSet(name: "import", kind: .personalUser, values: imported)
        check(PreferenceSets.merge([set]).beautifier)
    }
}
