import AppKit
import PelikanWorkspace
import SwiftUI

/// Sortowanie kolumny tabeli SwiftUI po kluczu (D212; kolumny `DataColumn`, D214): klik nagłówka sortuje rosnąco, drugi — malejąco. Porównanie
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

extension Sequence {
    /// Wiersze w kolejności wybranej w nagłówkach tabeli (pusta lista — kolejność oryginalna).
    func sorted(by sort: [ColumnSort<Element>]) -> [Element] {
        sort.isEmpty ? Array(self) : sorted(using: sort)
    }
}

extension Binding: @retroactive SortKeyConvertible where Value: SortKeyConvertible {
    /// Kolumny tabel edytowalnych (wiersze jako wiązania, `Binding.rows`) sortują po wartości pola.
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
