import Foundation
import PelikanDB

/// Filtr lokalny siatki (DB-GRID-001): warunki na pobranych wierszach, bez ponownego zapytania.
/// Wyrażenie: `KOLUMNA op wartość` połączone AND/OR (AND wiąże mocniej), op: `= <> != < <= > >= LIKE NOT LIKE`,
/// `IS NULL`, `IS NOT NULL`; wartości tekstowe w apostrofach, liczby bez; LIKE z `%` i `_` bez wielkości liter.
public struct GridFilter: Sendable, Hashable {
    public enum Op: String, Sendable, Hashable { case eq = "=", ne = "<>", lt = "<", le = "<=", gt = ">", ge = ">=", like = "LIKE", notLike = "NOT LIKE", isNull = "IS NULL", notNull = "IS NOT NULL" }

    public struct Condition: Sendable, Hashable {
        public var column: String
        public var op: Op
        public var value: String
        public init(column: String, op: Op, value: String = "") { self.column = column; self.op = op; self.value = value }
    }

    /// Alternatywa koniunkcji: `[[a AND b], [c]]` = `(a AND b) OR c`.
    public var groups: [[Condition]]
    /// Tekst do wyświetlenia (wyrażenie użytkownika albo opis filtra po wartości).
    public var text: String

    public init(groups: [[Condition]], text: String) { self.groups = groups; self.text = text }

    /// Filtr „= / <> wartość komórki”.
    public static func value(column: String, value: OracleValue, format: ValueFormat, exclude: Bool) -> GridFilter {
        let shown = value.format(format)
        if case .null = value {
            let c = Condition(column: column, op: exclude ? .notNull : .isNull)
            return GridFilter(groups: [[c]], text: "\(column) \(c.op.rawValue)")
        }
        let c = Condition(column: column, op: exclude ? .ne : .eq, value: shown)
        return GridFilter(groups: [[c]], text: "\(column) \(c.op.rawValue) '\(shown)'")
    }

    public enum ParseError: Error, LocalizedError, Equatable {
        case syntax(String), unknownColumn(String)
        public var errorDescription: String? {
            switch self {
            case .syntax(let s): L10n.tr("Błąd wyrażenia filtra: \(s)")
            case .unknownColumn(let c): L10n.tr("Nieznana kolumna w filtrze: \(c)")
            }
        }
    }

    /// Tokeny: identyfikatory/słowa, literały w apostrofach, liczby, operatory.
    nonisolated static func tokens(_ s: String) throws -> [String] {
        var out: [String] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c == "'" {
                var v = "'"
                i += 1
                while i < chars.count {
                    if chars[i] == "'" {
                        if i + 1 < chars.count, chars[i + 1] == "'" { v.append("'"); i += 2; continue }
                        break
                    }
                    v.append(chars[i]); i += 1
                }
                guard i < chars.count else { throw ParseError.syntax(L10n.tr("niezamknięty apostrof")) }
                i += 1
                out.append(v + "'")
                continue
            }
            if "<>=!".contains(c) {
                var op = String(c)
                if i + 1 < chars.count, "=>".contains(chars[i + 1]), !(c == "=" ) { op.append(chars[i + 1]); i += 1 }
                out.append(op); i += 1
                continue
            }
            if c == "\"" {
                var v = ""
                i += 1
                while i < chars.count, chars[i] != "\"" { v.append(chars[i]); i += 1 }
                i += 1
                out.append("\"" + v)
                continue
            }
            var w = ""
            while i < chars.count, !chars[i].isWhitespace, !"<>=!'".contains(chars[i]) { w.append(chars[i]); i += 1 }
            out.append(w)
        }
        return out
    }

    /// Parsowanie wyrażenia; nazwy kolumn sprawdzane z listą (bez wielkości liter; w cudzysłowie — dokładnie).
    public static func parse(_ expression: String, columns: [String]) throws -> GridFilter {
        let tk = try tokens(expression)
        var groups: [[Condition]] = [[]]
        var i = 0
        func colName(_ raw: String) throws -> String {
            if raw.hasPrefix("\"") {
                let n = String(raw.dropFirst())
                guard columns.contains(n) else { throw ParseError.unknownColumn(n) }
                return n
            }
            guard let n = columns.first(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) else { throw ParseError.unknownColumn(raw) }
            return n
        }
        func literal(_ raw: String) -> String {
            raw.hasPrefix("'") ? String(raw.dropFirst().dropLast()) : raw
        }
        while i < tk.count {
            let col = try colName(tk[i]); i += 1
            guard i < tk.count else { throw ParseError.syntax(L10n.tr("brak operatora po \(col)")) }
            let w = tk[i].uppercased()
            var cond: Condition
            if w == "IS" {
                if i + 1 < tk.count, tk[i + 1].uppercased() == "NULL" { cond = Condition(column: col, op: .isNull); i += 2 }
                else if i + 2 < tk.count, tk[i + 1].uppercased() == "NOT", tk[i + 2].uppercased() == "NULL" { cond = Condition(column: col, op: .notNull); i += 3 }
                else { throw ParseError.syntax("IS") }
            } else if w == "NOT", i + 1 < tk.count, tk[i + 1].uppercased() == "LIKE" {
                guard i + 2 < tk.count else { throw ParseError.syntax("NOT LIKE") }
                cond = Condition(column: col, op: .notLike, value: literal(tk[i + 2])); i += 3
            } else {
                let op: Op
                switch w {
                case "=": op = .eq
                case "<>", "!=": op = .ne
                case "<": op = .lt
                case "<=": op = .le
                case ">": op = .gt
                case ">=": op = .ge
                case "LIKE": op = .like
                default: throw ParseError.syntax(L10n.tr("nieznany operator \(tk[i])"))
                }
                guard i + 1 < tk.count else { throw ParseError.syntax(L10n.tr("brak wartości po \(w)")) }
                cond = Condition(column: col, op: op, value: literal(tk[i + 1])); i += 2
            }
            groups[groups.count - 1].append(cond)
            if i < tk.count {
                switch tk[i].uppercased() {
                case "AND": i += 1
                case "OR": groups.append([]); i += 1
                default: throw ParseError.syntax(L10n.tr("oczekiwano AND albo OR zamiast \(tk[i])"))
                }
                guard i < tk.count else { throw ParseError.syntax(L10n.tr("wyrażenie urwane po spójniku")) }
            }
        }
        guard !(groups.first ?? []).isEmpty else { throw ParseError.syntax(L10n.tr("puste wyrażenie")) }
        return GridFilter(groups: groups, text: expression)
    }

    nonisolated static func like(_ s: String, _ pattern: String) -> Bool {
        // (?s): `%` i `_` obejmują też znak nowej linii; \z — dokładnie koniec tekstu (jak LIKE w Oracle).
        let re = "(?s)^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "%", with: ".*").replacingOccurrences(of: "_", with: ".") + #"\z"#
        return s.range(of: re, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Czy wiersz spełnia filtr (wartości porównywane jako liczby, gdy obie są liczbami; inaczej jako tekst).
    public func matches(_ row: [OracleValue], columns: [ColumnInfo], format: ValueFormat) -> Bool {
        groups.contains { group in
            group.allSatisfy { c in
                guard let idx = columns.firstIndex(where: { $0.name == c.column }), idx < row.count else { return false }
                let v = row[idx]
                let isNull: Bool = { if case .null = v { return true }; return false }()
                switch c.op {
                case .isNull: return isNull
                case .notNull: return !isNull
                default: break
                }
                if isNull { return false }
                let s = v.format(format)
                switch c.op {
                case .like: return Self.like(s, c.value)
                case .notLike: return !Self.like(s, c.value)
                default: break
                }
                let cmp: ComparisonResult
                if let a = Decimal(string: s.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
                   let b = Decimal(string: c.value.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
                   Double(s.replacingOccurrences(of: ",", with: ".")) != nil, Double(c.value.replacingOccurrences(of: ",", with: ".")) != nil {
                    cmp = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
                } else {
                    cmp = s.compare(c.value, options: [.caseInsensitive])
                }
                switch c.op {
                case .eq: return cmp == .orderedSame
                case .ne: return cmp != .orderedSame
                case .lt: return cmp == .orderedAscending
                case .le: return cmp != .orderedDescending
                case .gt: return cmp == .orderedDescending
                case .ge: return cmp != .orderedAscending
                default: return false
                }
            }
        }
    }
}

extension ResultGridModel {
    /// Grupowanie z licznikami (DB-GRID-001): wartości kolumny w wierszach widoku (z filtrem) i ich liczba, malejąco.
    public func groupCounts(column: Int) -> [(value: String, isNull: Bool, count: Int)] {
        var counts: [String: (Bool, Int)] = [:]
        var firstSeen: [String] = []
        for r in 0..<rowCount {
            let v = value(row: r, column: column)
            let isNull: Bool = { if case .null = v { return true }; return false }()
            let key = isNull ? "\u{0}NULL" : v.format(format)
            if counts[key] == nil { firstSeen.append(key) }
            counts[key, default: (isNull, 0)].1 += 1
        }
        return firstSeen.map { k in (value: counts[k]!.0 ? "NULL" : k, isNull: counts[k]!.0, count: counts[k]!.1) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.value < $1.value }
    }
}
