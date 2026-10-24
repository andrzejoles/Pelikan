@testable import PelikanWorkspace
import Testing

@Suite("Wyszukiwarka Preferencji (PD-PREF-001)")
struct PreferenceSearchTests {
    @Test("Bez wielkości liter i polskich znaków; puste zapytanie — brak wyników; procent w etykiecie")
    func filter() {
        let entries = [(pane: "GeneralPane", label: "Tryb sesji"), (pane: "SQLWindowPane", label: "AutoCommit poleceń SQL"),
                       (pane: "EditorPane", label: "Wcięcie nowej linii"), (pane: "X", label: "Pokrycie 50%")]
        #expect(PreferenceSearch.filter(entries, query: "autocommit").map(\.pane) == ["SQLWindowPane"])
        #expect(PreferenceSearch.filter(entries, query: "polecen").map(\.label) == ["AutoCommit poleceń SQL"])
        #expect(PreferenceSearch.filter(entries, query: "WCIECIE").map(\.pane) == ["EditorPane"])
        #expect(PreferenceSearch.filter(entries, query: "50%").map(\.label) == ["Pokrycie 50%"])
        #expect(PreferenceSearch.filter(entries, query: "  ").isEmpty)
    }
}
