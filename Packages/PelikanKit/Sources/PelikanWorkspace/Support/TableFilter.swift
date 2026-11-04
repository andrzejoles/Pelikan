import Foundation

/// Filtr wartości kolumny tabeli (D214). Tekst wpisany w polu filtra kolumny:
/// - wzorzec LIKE bez wielkości liter: `%` — dowolny ciąg, `_` — jeden znak (`abc%` i `ABC%` dają to samo;
///   bez `%` i `_` — równość bez wielkości liter); `not like …` — zaprzeczenie;
/// - porównanie: `= 5`, `<> 5`, `!= 5`, `> 5`, `>= 6`, `< 5`, `<= 5`, `between 3 and 4` — liczby wg wartości, daty
///   `YYYY-MM-DD` (z dokładnością do dnia, albo `YYYY-MM-DD HH24:MI[:SS]`), inny tekst bez wielkości liter;
/// - `is null` / `is not null` — pusta / niepusta wartość.
public struct ValueFilter: Sendable, Hashable {
    public enum Value: Sendable, Hashable {
        case number(Double)
        /// Data; `dayOnly` — wpisana bez czasu, porównywana z dniem wartości.
        case date(Date, dayOnly: Bool)
        case text(String)
    }

    public enum Op: String, Sendable, Hashable { case eq = "=", ne = "<>", lt = "<", le = "<=", gt = ">", ge = ">=" }

    public enum Condition: Sendable, Hashable {
        case like(String, negated: Bool)
        case compare(Op, Value)
        case between(Value, Value)
        case isNull, notNull
    }

    public var condition: Condition
    public var text: String

    public init(condition: Condition, text: String) { self.condition = condition; self.text = text }

    /// Warunek z tekstu pola filtra; pusty tekst — brak filtra.
    public static func parse(_ raw: String) -> ValueFilter? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let lower = t.lowercased()
        func rest(after n: Int) -> String { unquote(String(t.dropFirst(n)).trimmingCharacters(in: .whitespaces)) }
        if lower == "is null" || lower == "null" { return ValueFilter(condition: .isNull, text: t) }
        if lower == "is not null" || lower == "not null" { return ValueFilter(condition: .notNull, text: t) }
        if lower.hasPrefix("between ") {
            let body = String(t.dropFirst(8))
            if let r = body.range(of: " and ", options: .caseInsensitive) {
                let a = unquote(body[..<r.lowerBound].trimmingCharacters(in: .whitespaces))
                let b = unquote(body[r.upperBound...].trimmingCharacters(in: .whitespaces))
                if !a.isEmpty, !b.isEmpty { return ValueFilter(condition: .between(value(a), value(b)), text: t) }
            }
        }
        if lower.hasPrefix("not like ") { return ValueFilter(condition: .like(rest(after: 9), negated: true), text: t) }
        if lower.hasPrefix("like ") { return ValueFilter(condition: .like(rest(after: 5), negated: false), text: t) }
        for (prefix, op) in [(">=", Op.ge), ("<=", .le), ("<>", .ne), ("!=", .ne), ("=", .eq), (">", .gt), ("<", .lt)] where t.hasPrefix(prefix) {
            let v = rest(after: prefix.count)
            return ValueFilter(condition: v.isEmpty ? (op == .eq ? .isNull : .notNull) : .compare(op, value(v)), text: t)
        }
        return ValueFilter(condition: .like(unquote(t), negated: false), text: t)
    }

    static func unquote(_ s: String) -> String {
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") { return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return s
    }

    /// Wartość z tekstu: liczba, data `YYYY-MM-DD[ HH24:MI[:SS]]` albo tekst.
    static func value(_ s: String) -> Value {
        if let d = date(s) { return .date(d.date, dayOnly: d.dayOnly) }
        if let n = CellOrder.number(s) { return .number(n) }
        return .text(s)
    }

    private static let dateRE = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?)?$"#)

    /// Data z tekstu w kalendarzu bieżącym (strefa lokalna, jak daty pokazywane w tabelach).
    static func date(_ s: String) -> (date: Date, dayOnly: Bool)? {
        let ns = s as NSString
        guard s.count <= 32, let m = dateRE.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func part(_ i: Int) -> Int? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : Int(ns.substring(with: r))
        }
        var c = DateComponents(year: part(1), month: part(2), day: part(3), hour: part(4) ?? 0, minute: part(5) ?? 0, second: part(6) ?? 0)
        c.calendar = Calendar(identifier: .gregorian)
        guard let month = c.month, (1...12).contains(month), let day = c.day, (1...31).contains(day), c.isValidDate, let d = c.date else { return nil }
        return (d, m.range(at: 4).location == NSNotFound)
    }

    /// Czy wartość komórki (tekst pokazany w tabeli i klucz sortowania kolumny) spełnia warunek; `like` — wzorzec
    /// skompilowany wcześniej (`TableFilter.compiled()`), inaczej kompilowany przy wywołaniu.
    public func matches(text: String, key: SortKey, like compiled: LikePattern? = nil) -> Bool {
        // Pusta: brak klucza albo pusty tekst przy kluczu tekstowym (liczba i data mają wartość także bez tekstu).
        let isEmpty: Bool = {
            switch key {
            case .none: return true
            case .text: return text.isEmpty
            default: return false
            }
        }()
        switch condition {
        case .isNull: return isEmpty
        case .notNull: return !isEmpty
        case .like(let p, let negated):
            let hit = !isEmpty && (compiled ?? LikePattern(p)).matches(text)
            return negated ? !hit && !isEmpty : hit
        case .compare(let op, let v):
            guard !isEmpty, let r = Self.compare(text: text, key: key, v) else { return false }
            switch op {
            case .eq: return r == .orderedSame
            case .ne: return r != .orderedSame
            case .lt: return r == .orderedAscending
            case .le: return r != .orderedDescending
            case .gt: return r == .orderedDescending
            case .ge: return r != .orderedAscending
            }
        case .between(let a, let b):
            guard !isEmpty, let ra = Self.compare(text: text, key: key, a), let rb = Self.compare(text: text, key: key, b) else { return false }
            return ra != .orderedAscending && rb != .orderedDescending
        }
    }

    /// Porównanie wartości komórki z wartością filtra (komórka względem filtra); nil — wartości nieporównywalne
    /// (np. liczba w filtrze, tekst w komórce).
    static func compare(text: String, key: SortKey, _ v: Value) -> ComparisonResult? {
        func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult { a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame }
        switch v {
        case .number(let n):
            if case .number(let x) = key { return order(x, n) }
            return CellOrder.number(text).map { order($0, n) }
        case .date(let d, let dayOnly):
            var cell: Date?
            if case .date(let x) = key { cell = x } else { cell = date(text)?.date }
            guard let cell else { return nil }
            let cal = Calendar(identifier: .gregorian)
            if dayOnly { return order(cal.startOfDay(for: cell), cal.startOfDay(for: d)) }
            // Tekst w tabeli i w filtrze ma dokładność do sekundy — ułamki klucza daty pomijane („tylko ta wartość”).
            return order(cell.timeIntervalSinceReferenceDate.rounded(.down), d.timeIntervalSinceReferenceDate.rounded(.down))
        case .text(let s):
            return text.compare(s, options: [.caseInsensitive, .numeric])
        }
    }
}

/// Filtr tabeli (D214): warunki na kolumnach (wszystkie muszą być spełnione) i szybki filtr — fragment tekstu w dowolnej
/// kolumnie (`_` — jeden dowolny znak), a z `%` — wzorzec LIKE całej wartości.
public struct TableFilter: Sendable, Hashable {
    /// Tekst filtra po identyfikatorze kolumny.
    public var columns: [String: String] = [:]
    public var quick = ""

    public init(columns: [String: String] = [:], quick: String = "") { self.columns = columns; self.quick = quick }

    public var isActive: Bool { !quick.trimmingCharacters(in: .whitespaces).isEmpty || columns.values.contains { ValueFilter.parse($0) != nil } }

    /// Warunki gotowe do sprawdzania wierszy.
    public func compiled() -> Compiled {
        let q = quick.trimmingCharacters(in: .whitespaces)
        // `_` jest częste w nazwach Oracle (DBA_USERS, SQL_ID) — nie wyłącza wyszukiwania fragmentu; tylko `%` tak.
        let pattern = q.isEmpty ? nil : (q.contains("%") ? q : "%\(q)%")
        let filters = columns.compactMapValues(ValueFilter.parse)
        return Compiled(columns: filters.mapValues { f in
                            if case .like(let p, _) = f.condition { return (f, LikePattern(p)) }
                            return (f, nil)
                        },
                        quick: pattern.map(LikePattern.init))
    }

    public struct Compiled: Sendable {
        public let columns: [String: (filter: ValueFilter, like: LikePattern?)]
        public let quick: LikePattern?
        public var isEmpty: Bool { columns.isEmpty && quick == nil }

        /// Wiersz spełnia filtr; `cell` podaje tekst i klucz komórki po identyfikatorze kolumny, `all` — identyfikatory
        /// wszystkich kolumn (dla szybkiego filtra).
        public func matches(all: [String], cell: (String) -> (text: String, key: SortKey)) -> Bool {
            for (id, f) in columns {
                let c = cell(id)
                if !f.filter.matches(text: c.text, key: c.key, like: f.like) { return false }
            }
            if let quick { return all.contains { quick.matches(cell($0).text) } }
            return true
        }
    }
}
