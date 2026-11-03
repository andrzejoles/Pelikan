import AppKit
import PelikanWorkspace
import SwiftUI

/// Sortowanie kolumny tabeli SwiftUI po kluczu (D212): klik nagłówka sortuje rosnąco, drugi — malejąco. Porównanie
/// wspólne dla wszystkich tabel (`SortKey`): liczby wg wartości, tekst bez wielkości liter, puste na końcu.
struct ColumnSort<Row>: SortComparator, @unchecked Sendable {
    let id: String
    let key: (Row) -> SortKey
    var order: SortOrder = .forward

    init(_ id: String, _ key: @escaping (Row) -> SortKey) {
        self.id = id
        self.key = key
    }

    func compare(_ a: Row, _ b: Row) -> ComparisonResult {
        let r = SortKey.compare(key(a), key(b))
        guard order == .reverse else { return r }
        switch r {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    static func == (l: Self, r: Self) -> Bool { l.id == r.id && l.order == r.order }
    func hash(into h: inout Hasher) {
        h.combine(id)
        h.combine(order)
    }
}

extension TableColumn where Sort == ColumnSort<RowValue>, Label == Text {
    /// Kolumna sortowana po kluczu z wiersza.
    init<K: SortKeyConvertible>(_ title: String, sortKey: @escaping (RowValue) -> K, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.init(title, sortUsing: ColumnSort(title) { sortKey($0).sortKey }, content: content)
    }
}

extension TableColumn where Sort == ColumnSort<RowValue>, Label == Text, Content == Text {
    /// Kolumna z tekstem z wiersza, sortowana po nim (liczby w tekście — wg wartości).
    init(_ title: String, text: @escaping (RowValue) -> String) {
        self.init(title, sortUsing: ColumnSort(title) { text($0).sortKey }) { Text(text($0)) }
    }
}

extension Sequence {
    /// Wiersze w kolejności wybranej w nagłówkach tabeli (pusta lista — kolejność oryginalna).
    func sorted(by sort: [ColumnSort<Element>]) -> [Element] {
        sort.isEmpty ? Array(self) : sorted(using: sort)
    }
}

extension Binding {
    /// Wiązanie z widokiem posortowanym tablicy edytowanej w tabeli (`Table($wiersze)`): zmiany wierszy wracają do
    /// oryginału po identyfikatorze, a kolejność w oryginale (np. kolejność kolumn tabeli) się nie zmienia.
    @MainActor
    static func sorted<Row: Identifiable>(_ base: Binding<[Row]>, by sort: [ColumnSort<Binding<Row>>]) -> Binding<[Row]> where Value == [Row] {
        guard !sort.isEmpty else { return base }
        return Binding<[Row]>(get: {
            base.wrappedValue.sorted { a, b in
                for s in sort {
                    let r = s.compare(.constant(a), .constant(b))
                    if r != .orderedSame { return r == .orderedAscending }
                }
                return false
            }
        }, set: { new in
            var rows = base.wrappedValue
            for r in new {
                if let i = rows.firstIndex(where: { $0.id == r.id }) { rows[i] = r }
            }
            base.wrappedValue = rows
        })
    }
}

extension Binding: @retroactive SortKeyConvertible where Value: SortKeyConvertible {
    /// Kolumny tabel edytowalnych (`Table($wiersze)`) sortują po wartości pola.
    public var sortKey: SortKey { wrappedValue.sortKey }
}

/// Sortowanie tabel AppKit kliknięciem nagłówka (D212): prototyp deskryptora z identyfikatora kolumny, kolejność
/// z tego samego porównania co w tabelach SwiftUI; równe wiersze zostają w kolejności pierwotnej.
@MainActor
enum HeaderSort {
    static func enable(_ table: NSTableView) {
        for c in table.tableColumns where c.sortDescriptorPrototype == nil {
            c.sortDescriptorPrototype = NSSortDescriptor(key: c.identifier.rawValue, ascending: true)
        }
    }

    static func sort<T>(_ items: [T], by descriptors: [NSSortDescriptor], key: (T, String) -> SortKey) -> [T] {
        guard !descriptors.isEmpty else { return items }
        return items.enumerated().sorted { a, b in
            for d in descriptors {
                guard let k = d.key else { continue }
                let r = SortKey.compare(key(a.element, k), key(b.element, k))
                if r != .orderedSame { return d.ascending ? r == .orderedAscending : r == .orderedDescending }
            }
            return a.offset < b.offset
        }.map(\.element)
    }
}
