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
        /// Data z dokładnością, z jaką ją wpisano (dzień, minuta, sekunda) — wartość komórki porównywana z tą samą
        /// dokładnością („= 2026-11-04 12:00” obejmuje całą minutę).
        case date(Date, precision: DatePrecision)
        case text(String)
        /// Tekst w apostrofach — dokładnie, z wielkością liter („tylko ta wartość” z menu).
        case exact(String)
    }

    public enum DatePrecision: Sendable, Hashable { case day, minute, second }

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
                // W apostrofach — tekst dosłownie (jak przy =, <, >).
                func bound(_ raw: String) -> Value? {
                    let v = unquote(raw)
                    guard !v.isEmpty else { return nil }
                    return raw.count >= 2 && raw.hasPrefix("'") && raw.hasSuffix("'") ? .exact(v) : value(v)
                }
                if let a = bound(body[..<r.lowerBound].trimmingCharacters(in: .whitespaces)),
                   let b = bound(body[r.upperBound...].trimmingCharacters(in: .whitespaces)) {
                    return ValueFilter(condition: .between(a, b), text: t)
                }
            }
        }
        if lower.hasPrefix("not like ") { return ValueFilter(condition: .like(rest(after: 9), negated: true), text: t) }
        if lower.hasPrefix("like ") { return ValueFilter(condition: .like(rest(after: 5), negated: false), text: t) }
        for (prefix, op) in [(">=", Op.ge), ("<=", .le), ("<>", .ne), ("!=", .ne), ("=", .eq), (">", .gt), ("<", .lt)] where t.hasPrefix(prefix) {
            let raw = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let v = unquote(raw)
            // W apostrofach — tekst dosłownie (jak w SQL): „= '1,234'” porównuje tekst komórki, nie liczbę.
            let quoted = raw.count >= 2 && raw.hasPrefix("'") && raw.hasSuffix("'")
            return ValueFilter(condition: v.isEmpty ? (op == .eq ? .isNull : .notNull) : .compare(op, quoted ? .exact(v) : value(v)), text: t)
        }
        return ValueFilter(condition: .like(unquote(t), negated: false), text: t)
    }

    static func unquote(_ s: String) -> String {
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") { return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return s
    }

    /// Wartość z tekstu: liczba, data `YYYY-MM-DD[ HH24:MI[:SS]]` albo tekst.
    static func value(_ s: String) -> Value {
        if let d = date(s) { return .date(d.date, precision: d.precision) }
        if let n = CellOrder.number(s) { return .number(n) }
        return .text(s)
    }

    private static let dateRE = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?)?$"#)

    /// Data z tekstu w kalendarzu bieżącym (strefa lokalna, jak daty pokazywane w tabelach).
    static func date(_ s: String) -> (date: Date, precision: DatePrecision)? {
        let ns = s as NSString
        guard s.count <= 32, let m = dateRE.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func part(_ i: Int) -> Int? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : Int(ns.substring(with: r))
        }
        var c = DateComponents(year: part(1), month: part(2), day: part(3), hour: part(4) ?? 0, minute: part(5) ?? 0, second: part(6) ?? 0)
        c.calendar = Calendar(identifier: .gregorian)
        guard let month = c.month, (1...12).contains(month), let day = c.day, (1...31).contains(day), c.isValidDate, let d = c.date else { return nil }
        let precision: DatePrecision = m.range(at: 4).location == NSNotFound ? .day : m.range(at: 6).location == NSNotFound ? .minute : .second
        return (d, precision)
    }

    /// Czy wartość komórki (tekst pokazany w tabeli i klucz sortowania kolumny) spełnia warunek; `like` — wzorzec
    /// skompilowany wcześniej (`TableFilter.compiled()`), inaczej kompilowany przy wywołaniu.
    public func matches(text: String, key: SortKey, like compiled: LikePattern? = nil) -> Bool {
        // Pusta: brak klucza albo pusty tekst przy kluczu tekstowym (liczba i data mają wartość także bez tekstu).
        let isEmpty: Bool = {
            switch key {
            // Bez klucza: pusta, gdy pusty jest też tekst (komórka z samym opisem, np. „Łączenie…” w kolumnie postępu).
            case .none: return text.isEmpty
            case .text: return text.isEmpty
            default: return false
            }
        }()
        switch condition {
        case .isNull: return isEmpty
        case .notNull: return !isEmpty
        case .like(let p, let negated):
            let hit = !isEmpty && (compiled ?? LikePattern.cached(p)).matches(text)
            return negated ? !hit && !isEmpty : hit
        case .compare(let op, let v):
            // Puste komórki nie spełniają porównań, także „<>” — jak NULL w SQL (filtr ma składnię i znaczenie SQL).
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

    /// Wartość liczbowa komórki — jedna dla wszystkich porównań (`=`, `<`, between): liczba pokazana w tekście, gdy
    /// zgadza się z kluczem z dokładnością do wyświetlonych cyfr („12.35” przy kluczu 12.345678 — „= 12.35” i „>= 12.35”
    /// trafiają tak samo); inaczej klucz (tekst z jednostką „1.2 s”, „1,234” z separatorem tysięcy, procent w innej
    /// skali). Bez klucza liczbowego — liczba z tekstu.
    static func cellNumber(text: String, key: SortKey) -> Double? {
        let shown = CellOrder.number(text)
        guard case .number(let x) = key else { return shown }
        guard let shown else { return x }
        let decimals = text.split(whereSeparator: { $0 == "." || $0 == "," }).dropFirst().first.map { $0.prefix { $0.isNumber }.count } ?? 0
        let unit = pow(10, -Double(decimals))
        return abs(shown - x) <= unit / 2 + unit * 1e-9 ? shown : x
    }

    /// Porównanie wartości komórki z wartością filtra (komórka względem filtra); nil — wartości nieporównywalne
    /// (np. liczba w filtrze, tekst w komórce).
    static func compare(text: String, key: SortKey, _ v: Value) -> ComparisonResult? {
        func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult { a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame }
        switch v {
        case .number(let n):
            // Klucz całkowity i tekst bez części ułamkowej — wprost klucz (bez parsowania tekstu przy każdym wierszu);
            // klucz ułamkowy pokazany jako liczba całkowita („13” przy 12.6) — przez `cellNumber`.
            if case .number(let x) = key, x == x.rounded(), !text.contains("."), !text.contains(",") { return order(x, n) }
            return cellNumber(text: text, key: key).map { order($0, n) }
        case .date(let d, let precision):
            var cell: Date?
            if case .date(let x) = key { cell = x } else { cell = date(text)?.date }
            guard let cell else { return nil }
            let cal = Calendar(identifier: .gregorian)
            switch precision {
            case .day: return order(cal.startOfDay(for: cell), cal.startOfDay(for: d))
            case .minute:
                let start = { (x: Date) in cal.dateInterval(of: .minute, for: x)?.start ?? x }
                return order(start(cell), start(d))
            case .second:
                // Tekst w tabeli i w filtrze ma dokładność do sekundy — ułamki klucza daty pomijane („tylko ta wartość”).
                return order(cell.timeIntervalSinceReferenceDate.rounded(.down), d.timeIntervalSinceReferenceDate.rounded(.down))
            }
        case .text(let s):
            // Tekst wpisany bez apostrofów — bez wielkości liter (jak wzorce LIKE), dosłownie dla =, <, between.
            return text.caseInsensitiveCompare(s)
        case .exact(let s):
            // W apostrofach — dokładnie, z wielkością liter (nazwy Oracle w cudzysłowach: „Emp” ≠ „EMP”; „EMP2” ≠ „EMP02”).
            return text.compare(s)
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
                            if case .like(let p, _) = f.condition { return (f, LikePattern.cached(p)) }
                            return (f, nil)
                        },
                        quick: pattern.map(LikePattern.cached))
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
