import Foundation

/// Wyszukiwarka Preferencji (PD-PREF-001): dopasowanie etykiet ustawień bez wielkości liter i znaków diakrytycznych,
/// w języku interfejsu albo po polsku (klucz). Indeks etykiet generuje `scripts/prefs-index.py` z paneli aplikacji;
/// etykiety to klucze L10n (`%@` w miejscu wartości, `%%`), w wynikach wartość jest pokazywana jako „…”.
public enum PreferenceSearch {
    public static func filter(_ entries: [(pane: String, label: String)], query: String) -> [(pane: String, label: String)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return entries.compactMap { e in
            let shown = L10n.translated(format: e.label)
            return shown.range(of: q, options: opts) != nil || L10n.template(e.label).range(of: q, options: opts) != nil ? (e.pane, shown) : nil
        }
    }
}

/// Kolory tekstu i tła obszaru (edytor, siatka, Object Browser — PD-PREF-005). Puste — kolory motywu systemu
/// (jasny/ciemny); własny kolor obowiązuje w obu trybach.
public struct AreaColors: Sendable, Codable, Hashable {
    public var text: RGBColor?
    public var background: RGBColor?
    public init(text: RGBColor? = nil, background: RGBColor? = nil) { self.text = text; self.background = background }
    public var isSystem: Bool { text == nil && background == nil }
}
