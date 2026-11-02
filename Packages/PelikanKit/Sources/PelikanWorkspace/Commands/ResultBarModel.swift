import Foundation

/// Pasek ikon bezpośrednio nad wynikiem zapytania (D207): wszystkie czynności dotyczące wyniku — pobieranie, edycja
/// danych, filtr i QBE, kopiowanie i eksport, analiza, karty wyników — w grupach karty kontekstowej „Wynik” wstążki
/// (ta sama kolejność i te same listy rozwijane, więc pasek nie rozjeżdża się ze wstążką). Bez czynności okna
/// (wykonanie, przerwanie, edytor) i sesji (COMMIT/ROLLBACK) — te są na pasku narzędzi i we wstążce.
public enum ResultBarModel {
    /// Komendy karty „Wynik”, które nie dotyczą samego wyniku.
    public static let excluded: Set<String> = ["sql.execute", "sql.break", "sql.toggleEditor", "session.commit", "session.rollback"]

    /// Komendy wyniku z innych kart wstążki — dopisywane za komendą z karty „Wynik” (panel wartości komórki na karcie
    /// Widok — obok widoku rekordu).
    static let added: [(after: String, id: String)] = [("grid.toggleRecordView", "grid.valuePanel")]

    /// Grupy paska: grupy karty „Wynik” bez komend spoza wyniku (grupy puste pominięte) i z komendami `added`.
    @MainActor public static var groups: [RibbonGroup] {
        RibbonModel.result.groups.compactMap { g in
            var items = g.items
            for a in added {
                if let i = items.firstIndex(where: { if case .small(a.after, _) = $0 { true } else { false } }) {
                    items.insert(.small(a.id), at: i + 1)
                }
            }
            return RibbonGroup(g.title, items)
        }.compactMap { g in
            let items: [RibbonItem] = g.items.compactMap { item in
                switch item {
                case .large(let id, let label), .small(let id, let label):
                    return excluded.contains(id) ? nil : .small(id, label: label)
                case .menu(let title, let symbol, let commands, _):
                    let rest = commands.filter { !excluded.contains($0) }
                    return rest.contains { $0 != RibbonModel.separator } ? .menu(title, symbol: symbol, commands: rest) : nil
                }
            }
            return items.isEmpty ? nil : RibbonGroup(g.title, items)
        }
    }

    /// Wszystkie komendy paska (z list rozwijanych także).
    @MainActor public static var commands: [String] { groups.flatMap { $0.items.flatMap(\.commands) } }

    /// Ile elementów (od początku, w kolejności paska) mieści się w `available` punktach: szerokości elementów
    /// `widths` (separatory grup to też elementy). Gdy nie mieszczą się wszystkie, zostaje miejsce na przycisk „»”
    /// (`overflowWidth`) z resztą elementów; separator na końcu widocznej części jest odcinany.
    public static func fit(widths: [Double], available: Double, overflowWidth: Double, isSeparator: (Int) -> Bool = { _ in false }) -> Int {
        let total = widths.reduce(0, +)
        guard total > available else { return widths.count }
        var used = 0.0
        var count = 0
        for w in widths {
            guard used + w + overflowWidth <= available else { break }
            used += w
            count += 1
        }
        while count > 0, isSeparator(count - 1) { count -= 1 }
        return count
    }
}
