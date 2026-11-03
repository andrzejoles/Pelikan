import Foundation

/// Klucz sortowania kolumny tabeli (D212): każda tabela sortuje się po dowolnej kolumnie (klik nagłówka).
/// Puste wartości są na końcu przy sortowaniu rosnącym; tekst z liczbami (wartości z bazy jako tekst — SID, rozmiary)
/// porównywany liczbowo, inny tekst — jak w Finderze (bez wielkości liter, liczby w tekście wg wartości).
public enum SortKey: Sendable, Hashable {
    case none
    case number(Double)
    case date(Date)
    case text(String)

    public static func compare(_ a: SortKey, _ b: SortKey) -> ComparisonResult {
        switch (a, b) {
        case (.none, .none): return .orderedSame
        case (.none, _): return .orderedDescending
        case (_, .none): return .orderedAscending
        case let (.number(x), .number(y)): return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
        case let (.date(x), .date(y)): return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
        case let (.text(x), .text(y)): return CellOrder.compare(x, y)
        case (.number, _): return .orderedAscending
        case (_, .number): return .orderedDescending
        case (.date, _): return .orderedAscending
        case (_, .date): return .orderedDescending
        }
    }
}

/// Porównanie wartości komórek w postaci tekstu.
public enum CellOrder {
    /// Liczba z tekstu komórki (kropka albo przecinek dziesiętny, spacje tysięcy); nil — to nie liczba.
    public static func number(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count < 40, t.first.map({ $0.isNumber || $0 == "-" || $0 == "+" || $0 == "." || $0 == "," }) == true else { return nil }
        if let d = Double(t) { return d }
        let compact = t.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        if let d = Double(compact) { return d }
        if !compact.contains("."), compact.filter({ $0 == "," }).count == 1 { return Double(compact.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        if a.isEmpty || b.isEmpty { return a.isEmpty == b.isEmpty ? .orderedSame : a.isEmpty ? .orderedDescending : .orderedAscending }
        if let x = number(a), let y = number(b) { return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame }
        return a.localizedStandardCompare(b)
    }
}

/// Wartość, po której można sortować kolumnę.
public protocol SortKeyConvertible {
    var sortKey: SortKey { get }
}

extension String: SortKeyConvertible { public var sortKey: SortKey { isEmpty ? .none : .text(self) } }
extension Substring: SortKeyConvertible { public var sortKey: SortKey { String(self).sortKey } }
extension Int: SortKeyConvertible { public var sortKey: SortKey { .number(Double(self)) } }
extension Int64: SortKeyConvertible { public var sortKey: SortKey { .number(Double(self)) } }
extension Int32: SortKeyConvertible { public var sortKey: SortKey { .number(Double(self)) } }
extension UInt64: SortKeyConvertible { public var sortKey: SortKey { .number(Double(self)) } }
extension Double: SortKeyConvertible { public var sortKey: SortKey { isNaN ? .none : .number(self) } }
extension Float: SortKeyConvertible { public var sortKey: SortKey { isNaN ? .none : .number(Double(self)) } }
extension Decimal: SortKeyConvertible { public var sortKey: SortKey { .number(NSDecimalNumber(decimal: self).doubleValue) } }
extension Date: SortKeyConvertible { public var sortKey: SortKey { .date(self) } }
extension Bool: SortKeyConvertible { public var sortKey: SortKey { .number(self ? 1 : 0) } }
extension UUID: SortKeyConvertible { public var sortKey: SortKey { .text(uuidString) } }
extension Optional: SortKeyConvertible where Wrapped: SortKeyConvertible {
    public var sortKey: SortKey { self?.sortKey ?? .none }
}
