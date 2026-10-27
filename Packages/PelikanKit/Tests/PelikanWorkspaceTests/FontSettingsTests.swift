import Foundation
@testable import PelikanWorkspace
import Testing

/// Czcionki z Preferencji (D178): wartości domyślne, zapis i odczyt, starszy plik ustawień.
@Suite("Ustawienia czcionek")
struct FontSettingsTests {
    @Test("domyślnie systemowe; zapis i odczyt kroju, stylu i wielkości; starszy plik bez kluczy")
    func roundTrip() throws {
        let d = Settings()
        #expect(d.uiFontName.isEmpty && d.uiFontSize == 13 && d.uiFontWeight == .regular)
        #expect(d.gridFontName.isEmpty && d.browserFontName.isEmpty && d.editorFontWeight == .regular)
        var s = Settings()
        s.uiFontName = "Avenir Next"; s.uiFontSize = 15; s.uiFontWeight = .medium
        s.gridFontName = "Menlo"; s.gridFontWeight = .bold; s.browserFontName = "Helvetica Neue"; s.browserFontWeight = .light
        s.editorFontWeight = .semibold
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back.uiFontName == "Avenir Next" && back.uiFontSize == 15 && back.uiFontWeight == .medium)
        #expect(back.gridFontName == "Menlo" && back.gridFontWeight == .bold && back.browserFontName == "Helvetica Neue")
        #expect(back.browserFontWeight == .light && back.editorFontWeight == .semibold)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"editorFontName":"Menlo","gridFontSize":14}"#.utf8))
        #expect(old.editorFontName == "Menlo" && old.gridFontSize == 14 && old.uiFontSize == 13 && old.gridFontWeight == .regular)
    }

    @Test("czcionki w sekcjach eksportu Preferencji (Ogólne, Okno SQL, Edytor)")
    func sections() {
        let keys = Set(PreferenceSets.sections.flatMap(\.keys))
        for k in ["uiFontName", "uiFontSize", "uiFontWeight", "gridFontName", "gridFontWeight", "editorFontWeight", "browserFontName", "browserFontWeight"] {
            #expect(keys.contains(k), "\(k)")
        }
        // Krój, styl i wielkość czcionki Object Browsera w jednej sekcji; ustawienia karty Object Browser — w swojej (R3-18).
        for k in ["browserFontName", "browserFontSize", "browserFontWeight"] { #expect(PreferenceSets.section(of: k) == L10n.tr("Edytor"), "\(k)") }
        for k in ["browserFolders", "browserFilterContains", "browserDoubleClick", "browserDropAction"] {
            #expect(PreferenceSets.section(of: k) == L10n.tr("Object Browser"), "\(k)")
        }
        let known = PreferenceSets.values(of: Settings())
        for k in PreferenceSets.sections.flatMap(\.keys) { #expect(known[k] != nil, "\(k)") }
    }
}
