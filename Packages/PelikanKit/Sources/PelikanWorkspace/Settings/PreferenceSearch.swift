import Foundation

/// Wyszukiwarka Preferencji (PD-PREF-001): dopasowanie etykiet ustawień bez wielkości liter i znaków diakrytycznych,
/// w języku interfejsu albo po polsku (klucz). Indeks etykiet generuje `scripts/prefs-index.py` z paneli aplikacji.
public enum PreferenceSearch {
    public static func filter(_ entries: [(pane: String, label: String)], query: String) -> [(pane: String, label: String)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return entries.compactMap { e in
            let shown = L10n.translated(key: e.label)
            return shown.range(of: q, options: opts) != nil || e.label.range(of: q, options: opts) != nil ? (e.pane, shown) : nil
        }
    }
}
