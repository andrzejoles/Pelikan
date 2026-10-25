@testable import PelikanWorkspace
import Testing

@Suite("Wyszukiwarka Preferencji (PD-PREF-001)")
struct PreferenceSearchTests {
    @Test("Bez wielkości liter i polskich znaków; puste zapytanie — brak wyników; procent w etykiecie")
    func filter() {
        let entries = [(pane: "GeneralPane", label: "Tryb sesji"), (pane: "SQLWindowPane", label: "AutoCommit poleceń SQL"),
                       (pane: "EditorPane", label: "Wcięcie nowej linii"), (pane: "X", label: "Pokrycie 50%%")]
        #expect(PreferenceSearch.filter(entries, query: "autocommit").map(\.pane) == ["SQLWindowPane"])
        #expect(PreferenceSearch.filter(entries, query: "polecen").map(\.label) == ["AutoCommit poleceń SQL"])
        #expect(PreferenceSearch.filter(entries, query: "WCIECIE").map(\.pane) == ["EditorPane"])
        #expect(PreferenceSearch.filter(entries, query: "50%").map(\.label) == ["Pokrycie 50%"])
        #expect(PreferenceSearch.filter(entries, query: "  ").isEmpty)
    }

    @Test("Etykiety z wartością (Stepper): klucz z %@ pokazany z „…”, wyszukiwany po tekście przed i po wartości")
    func interpolatedLabels() {
        let entries = [(pane: "EditorPane", label: "Szerokość tabulacji: %@"),
                       (pane: "OraclePane", label: "Zamykaj sesje okien bezczynne ponad %@ min (bez otwartej transakcji)")]
        #expect(PreferenceSearch.filter(entries, query: "tabulacji").map(\.label) == ["Szerokość tabulacji: …"])
        #expect(PreferenceSearch.filter(entries, query: "otwartej transakcji").map(\.pane) == ["OraclePane"])
        #expect(PreferenceSearch.filter(entries, query: "%@").isEmpty)
        #expect(L10n.template("Wartość %2$@ z %1$@, 5%%") == "Wartość … z …, 5%")
    }
}
