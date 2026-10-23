import Foundation
import PelikanDB
import PelikanSQL

// MARK: Sumy kolumn (PD-GRID-024)

/// Funkcja sumy kolumny w siatce (UG 7.2, dyrektywa `Totals=` — UG 7.12).
public enum ColumnAggregate: String, Sendable, Codable, CaseIterable, Hashable {
    case sum, count, avg, min, max

    public var displayName: String {
        switch self {
        case .sum: L10n.tr("Suma")
        case .count: L10n.tr("Liczba")
        case .avg: L10n.tr("Średnia")
        case .min: L10n.tr("Minimum")
        case .max: L10n.tr("Maksimum")
        }
    }
}

public enum ColumnTotals {
    static let posix = Locale(identifier: "en_US_POSIX")

    static func decimal(_ v: OracleValue) -> Decimal? {
        switch v {
        case .number(let s): Decimal(string: s, locale: posix)
        case .double(let d): Decimal(d)
        default: nil
        }
    }

    static func text(_ d: Decimal) -> String {
        var x = d, r = Decimal()
        NSDecimalRound(&r, &x, 6, .plain)
        return NSDecimalNumber(decimal: r).stringValue
    }

    /// Wartości funkcji dla kolumny (wiersze widoku — z filtrem lokalnym; pobrane wiersze).
    @MainActor
    public static func compute(_ grid: ResultGridModel, column: Int, _ aggregates: [ColumnAggregate]) -> [(ColumnAggregate, String)] {
        let values = (0..<grid.rowCount).map { grid.value(row: $0, column: column) }.filter { !$0.isNull }
        let numbers = values.compactMap(decimal)
        let numeric = grid.columns[column].type.isNumeric
        return aggregates.map { a in
            switch a {
            case .count: return (a, String(values.count))
            case .sum: return (a, numeric ? text(numbers.reduce(0, +)) : "")
            case .avg: return (a, numeric && !numbers.isEmpty ? text(numbers.reduce(0, +) / Decimal(numbers.count)) : "")
            case .min, .max:
                let want: ComparisonResult = a == .min ? .orderedAscending : .orderedDescending
                let best = values.reduce(nil as OracleValue?) { acc, v in
                    guard let acc else { return v }
                    return ResultGridModel.compare(v, acc, type: grid.columns[column].type, caseSensitive: false) == want ? v : acc
                }
                return (a, best?.format(grid.format) ?? "")
            }
        }
    }

    /// Wiersz podsumowania pod siatką: `SAL: Suma 29025 · Średnia 2073,21`.
    @MainActor
    public static func summary(_ grid: ResultGridModel, totals: [Int: [ColumnAggregate]]) -> String {
        totals.keys.sorted().compactMap { c in
            guard c < grid.columns.count, let aggs = totals[c], !aggs.isEmpty else { return nil }
            return grid.columns[c].name + ": " + compute(grid, column: c, aggs).map { "\($0.0.displayName) \($0.1)" }.joined(separator: " · ")
        }.joined(separator: "   ")
    }

    /// Dyrektywa `Totals=[funkcja:]kolumny[; …]` (domyślnie suma); nazwy kolumn bez rozróżniania wielkości liter.
    public static func parse(_ directive: String, columns: [ColumnInfo]) -> [Int: [ColumnAggregate]] {
        var out: [Int: [ColumnAggregate]] = [:]
        for group in directive.split(separator: ";") {
            var aggs: [ColumnAggregate] = [.sum]
            var list = Substring(group)
            if let colon = group.firstIndex(of: ":") {
                aggs = group[..<colon].split(separator: "+").compactMap { ColumnAggregate(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
                list = group[group.index(after: colon)...]
            }
            for name in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).uppercased() }) where !name.isEmpty {
                guard let i = columns.firstIndex(where: { $0.name.uppercased() == name }) else { continue }
                out[i, default: []].append(contentsOf: aggs.filter { !(out[i] ?? []).contains($0) })
            }
        }
        return out
    }
}

// MARK: Filtr kolumn (PD-GRID-011)

/// Filtr kolumn siatki: fragmenty nazw (także wklejone wiele linii), grupy typów, obowiązkowe, klucze (UG 7.2).
public struct ColumnFilter: Sendable, Hashable, Codable {
    public enum TypeGroup: String, Sendable, Hashable, Codable, CaseIterable { case text, number, date, lob, other }
    public enum KeyKind: String, Sendable, Hashable, Codable, CaseIterable { case primary, unique, foreign }

    public var names: [String] = []
    public var types: Set<TypeGroup> = []
    public var mandatoryOnly = false
    public var keys: Set<KeyKind> = []

    public init(names: [String] = [], types: Set<TypeGroup> = [], mandatoryOnly: Bool = false, keys: Set<KeyKind> = []) {
        self.names = names; self.types = types; self.mandatoryOnly = mandatoryOnly; self.keys = keys
    }

    public var isEmpty: Bool { names.isEmpty && types.isEmpty && !mandatoryOnly && keys.isEmpty }

    /// Nazwy z tekstu: linie, przecinki, średniki i tabulatory rozdzielają (wklejona lista kolumn).
    public static func names(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n\r,;\t")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func group(_ t: OracleType) -> TypeGroup {
        if t.isNumeric { return .number }
        if t.isTemporal { return .date }
        if t.isLOB { return .lob }
        if [.varchar2, .nvarchar2, .char, .nchar, .long].contains(t) { return .text }
        return .other
    }

    /// Kolumny widoczne; `keyInfo` — klucze kolumn wg nazwy (ze słownika), `mandatory` — NOT NULL ze słownika.
    public func visible(_ columns: [ColumnInfo], keyInfo: [String: Set<KeyKind>] = [:], mandatory: Set<String> = []) -> Set<Int> {
        Set(columns.indices.filter { i in
            let c = columns[i]
            let upper = c.name.uppercased()
            if !names.isEmpty, !names.contains(where: { upper.contains($0.uppercased()) }) { return false }
            if !types.isEmpty, !types.contains(Self.group(c.type)) { return false }
            if mandatoryOnly, c.nullable, !mandatory.contains(upper) { return false }
            if !keys.isEmpty, (keyInfo[upper] ?? []).isDisjoint(with: keys) { return false }
            return true
        })
    }

    public var text: String {
        var parts: [String] = []
        if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        if !types.isEmpty { parts.append(types.map(\.rawValue).sorted().joined(separator: "/")) }
        if mandatoryOnly { parts.append("NOT NULL") }
        if !keys.isEmpty { parts.append(keys.map { $0 == .primary ? "PK" : $0 == .unique ? "UK" : "FK" }.sorted().joined(separator: "/")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Wyrównanie kolumn (PD-GRID-012)

public enum GridAlignMode: String, Sendable, CaseIterable { case header, content, both }

/// Szablon wyrównania zapisany dla zapytania: kolejność kolumn i szerokości (w znakach) wg nazw.
public struct AlignTemplate: Sendable, Hashable, Codable {
    public var order: [String]
    public var widths: [String: Int]
    public init(order: [String], widths: [String: Int]) { self.order = order; self.widths = widths }
}

public enum GridAlign {
    /// Szerokości (znaki) wg nagłówka, treści (pierwsze `sample` wierszy widoku) albo obu; od 2 do `maxChars`.
    @MainActor
    public static func widths(_ grid: ResultGridModel, mode: GridAlignMode, sample: Int = 500, maxChars: Int = 60) -> [Int: Int] {
        var out: [Int: Int] = [:]
        let rows = min(grid.rowCount, sample)
        for c in grid.columns.indices {
            let header = grid.columns[c].name.count
            let content = (0..<rows).map { grid.text(row: $0, column: c).count }.max() ?? 0
            let w = switch mode {
            case .header: header
            case .content: content
            case .both: Swift.max(header, content)
            }
            out[c] = Swift.min(Swift.max(w, 2), maxChars)
        }
        return out
    }

    /// Klucz szablonu: zapytanie bez komentarzy końcowych, białe znaki zwinięte, małe litery.
    public static func key(for sql: String) -> String {
        var s = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix(";") || s.hasSuffix("/") { s.removeLast() }
        return s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @MainActor
    public static func template(_ grid: ResultGridModel, tab: ResultTab) -> AlignTemplate {
        let order = (tab.columnOrder ?? Array(grid.columns.indices)).map { grid.columns[$0].name }
        let widths = (tab.columnWidths ?? widths(grid, mode: .both)).reduce(into: [String: Int]()) { $0[grid.columns[$1.key].name] = $1.value }
        return AlignTemplate(order: order, widths: widths)
    }

    /// Zastosowanie szablonu: kolejność (kolumny spoza szablonu na końcu) i szerokości po nazwach.
    @MainActor
    public static func apply(_ t: AlignTemplate, to grid: ResultGridModel, tab: ResultTab) {
        let names = grid.columns.map { $0.name }
        var order = t.order.compactMap { n in names.firstIndex(of: n) }
        order += names.indices.filter { !order.contains($0) }
        tab.columnOrder = order
        var w: [Int: Int] = [:]
        for (i, n) in names.enumerated() { if let x = t.widths[n] { w[i] = x } }
        tab.columnWidths = w.isEmpty ? nil : w
    }
}

// MARK: Query By Example (PD-SQLW-022)

public struct QBEOptions: Sendable, Hashable {
    public var caseInsensitive = true
    public var autoContains = false
    public var ignoreTime = true
    public init(caseInsensitive: Bool = true, autoContains: Bool = false, ignoreTime: Bool = true) {
        self.caseInsensitive = caseInsensitive; self.autoContains = autoContains; self.ignoreTime = ignoreTime
    }
}

public enum QueryByExample {
    public struct Failure: Error, LocalizedError, Equatable {
        public let column: String
        public let expression: String
        public var errorDescription: String? { L10n.tr("Kolumna \(column): niepoprawne kryterium „\(expression)”") }
    }

    /// Literał dla typu kolumny; tekst bez cudzysłowów (dopisywane), liczby sprawdzane, daty przez TO_DATE.
    static func literal(_ raw: String, column c: ColumnInfo) throws -> (sql: String, dateOnly: Bool) {
        var v = raw.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, v.hasPrefix("'"), v.hasSuffix("'") { v = String(v.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        if c.type.isNumeric {
            let n = v.replacingOccurrences(of: ",", with: ".")
            guard !n.isEmpty, Decimal(string: n, locale: ColumnTotals.posix) != nil, n.allSatisfy({ $0.isNumber || ".-+eE".contains($0) }) else {
                throw Failure(column: c.name, expression: raw)
            }
            return (n, false)
        }
        if c.type.isTemporal {
            let digits = v.filter { $0.isNumber }
            switch digits.count {
            case 8: return ("TO_DATE('\(v)', 'YYYY-MM-DD')", true)
            case 12: return ("TO_DATE('\(v)', 'YYYY-MM-DD HH24:MI')", false)
            case 14: return ("TO_DATE('\(v)', 'YYYY-MM-DD HH24:MI:SS')", false)
            default: throw Failure(column: c.name, expression: raw)
            }
        }
        return ("'" + v.replacingOccurrences(of: "'", with: "''") + "'", false)
    }

    /// Predykat dla kryterium: wartość, `%`/`_` (LIKE), `> < >= <= <> != =`, `in (…)`, `not in (…)`,
    /// `between … and …`, `null`, `not null`.
    public static func predicate(column c: ColumnInfo, expression raw: String, options o: QBEOptions = QBEOptions()) throws -> String {
        let e = raw.trimmingCharacters(in: .whitespaces)
        let lower = e.lowercased()
        let col = "x." + ResultExporter.identifier(c.name)
        let isText = ColumnFilter.group(c.type) == .text
        let ci = isText && o.caseInsensitive
        func side(_ s: String) -> String { ci ? "UPPER(\(s))" : s }
        func dateCol(_ dateOnly: Bool) -> String { c.type.isTemporal && dateOnly && o.ignoreTime ? "TRUNC(\(col))" : col }
        if lower == "null" || lower == "is null" { return "\(col) IS NULL" }
        if lower == "not null" || lower == "is not null" { return "\(col) IS NOT NULL" }
        if let m = lower.firstMatch(of: #/^(not\s+)?in\s*\((.*)\)$/#) {
            let inner = String(e[e.index(e.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: m.2.startIndex))..<e.index(e.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: m.2.endIndex))])
            let items = try inner.split(separator: ",").map { try literal(String($0), column: c) }
            guard !items.isEmpty else { throw Failure(column: c.name, expression: raw) }
            return "\(side(dateCol(items.allSatisfy(\.dateOnly)))) \(m.1 == nil ? "IN" : "NOT IN") (\(items.map { side($0.sql) }.joined(separator: ", ")))"
        }
        if lower.hasPrefix("between ") {
            let body = String(e.dropFirst(8))
            guard let r = body.range(of: " and ", options: .caseInsensitive) else { throw Failure(column: c.name, expression: raw) }
            let a = try literal(String(body[..<r.lowerBound]), column: c), b = try literal(String(body[r.upperBound...]), column: c)
            return "\(side(dateCol(a.dateOnly && b.dateOnly))) BETWEEN \(side(a.sql)) AND \(side(b.sql))"
        }
        for op in [">=", "<=", "<>", "!=", ">", "<", "="] where e.hasPrefix(op) {
            let l = try literal(String(e.dropFirst(op.count)), column: c)
            return "\(side(dateCol(l.dateOnly))) \(op == "!=" ? "<>" : op) \(side(l.sql))"
        }
        if lower.hasPrefix("like ") {
            let l = try literal(String(e.dropFirst(5)), column: c)
            return "\(side(col)) LIKE \(side(l.sql))"
        }
        if isText, e.contains("%") || e.contains("_") {
            return "\(side(col)) LIKE \(side(try literal(e, column: c).sql))"
        }
        if isText, o.autoContains {
            return "\(side(col)) LIKE \(side(try literal("%" + e + "%", column: c).sql))"
        }
        let l = try literal(e, column: c)
        return "\(side(dateCol(l.dateOnly))) = \(side(l.sql))"
    }

    /// Zapytanie z kryteriami: `select * from (<zapytanie>) x where …`; puste kryteria pomijane.
    public static func apply(sql: String, criteria: [(ColumnInfo, String)], options: QBEOptions = QBEOptions()) throws -> String {
        let preds = try criteria.filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }.map { try predicate(column: $0.0, expression: $0.1, options: options) }
        var base = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix(";") { base.removeLast() }
        guard !preds.isEmpty else { return base }
        return "select * from (\n\(base)\n) x\n where " + preds.joined(separator: "\n   and ")
    }
}

// MARK: Dyrektywy Excel= / CSV= (PD-SQLW-011)

public enum ExportDirectives {
    /// Nazwa pliku z dyrektywy: `%dbuser%`, `%dbname%`, `%date%` (RRRR-MM-DD), `%time%` (GGMMSS), `%&zmienna%`;
    /// ścieżka względna — wobec `base`.
    public static func path(_ template: String, user: String, database: String, values: [String: VariableValue], now: Date, base: URL) -> URL {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        var s = template.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: "%dbuser%", with: user, options: .caseInsensitive)
            .replacingOccurrences(of: "%dbname%", with: database, options: .caseInsensitive)
            .replacingOccurrences(of: "%date%", with: String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0), options: .caseInsensitive)
            .replacingOccurrences(of: "%time%", with: String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0), options: .caseInsensitive)
        while let r = s.range(of: #"%&([A-Za-z0-9_$#]+)%"#, options: .regularExpression) {
            let name = String(s[r].dropFirst(2).dropLast())
            let value: String = switch values.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value {
            case .text(let t)?: t
            case .list(let l)?: l.joined(separator: "_")
            default: ""
            }
            s.replaceSubrange(r, with: value)
        }
        // Znaki niedozwolone w nazwie pliku z wartości zmiennych (poza separatorem katalogów w szablonie).
        s = s.replacingOccurrences(of: ":", with: "-")
        let expanded = (s as NSString).expandingTildeInPath
        return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded)
    }
}

// MARK: Informacje słownika w siatce (PD-GRID-022)

/// Kolumna ze słownika: typ, NOT NULL, komentarz, klucze i lista wartości (CHECK IN albo FK do małej tabeli).
public struct ColumnDictionaryInfo: Sendable, Hashable {
    public var type: String
    public var nullable: Bool
    public var comment: String?
    public var keys: Set<ColumnFilter.KeyKind>
    public var values: [String]

    public var statusLine: String {
        var s = type + (nullable ? "" : " NOT NULL")
        if !keys.isEmpty { s += " · " + keys.map { $0 == .primary ? "PK" : $0 == .unique ? "UK" : "FK" }.sorted().joined(separator: ", ") }
        if let c = comment, !c.isEmpty { s += " — " + c }
        return s
    }
}

public enum GridDictionary {
    /// Wartości z warunku CHECK `KOLUMNA IN ('A', 'B', 3)` (także w nawiasach i cudzysłowach identyfikatora).
    public static func checkValues(_ condition: String, column: String) -> [String]? {
        let pattern = #"^\s*\(?\s*"?"# + NSRegularExpression.escapedPattern(for: column) + #""?\s+IN\s*\((.*?)\)\s*\)?\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: condition, range: NSRange(condition.startIndex..., in: condition)),
              let r = Range(m.range(at: 1), in: condition) else { return nil }
        var out: [String] = []
        var cur = "", inQuote = false
        var chars = Array(condition[r])
        chars.append(",")
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "'" {
                if inQuote, i + 1 < chars.count, chars[i + 1] == "'" { cur.append("'"); i += 2; continue }
                inQuote.toggle()
            } else if ch == ",", !inQuote {
                let v = cur.trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { out.append(v) }
                cur = ""
            } else {
                cur.append(ch)
            }
            i += 1
        }
        return out.isEmpty ? nil : out
    }

    /// Słownik dla kolumn tabeli zapytania (wg nazw kolumn wyniku). `fkLimit` — FK do tabel o co najwyżej tylu wierszach.
    public static func load(owner: String, table: String, in s: any DatabaseSession, fkLimit: Int = 1000) async throws -> [String: ColumnDictionaryInfo] {
        func b(_ n: String, _ v: String) -> BindVariable { BindVariable(name: n, value: .text(v)) }
        let (_, cols) = try await s.queryAll("""
            select c.column_name, c.data_type, c.data_length, c.data_precision, c.data_scale, c.nullable, m.comments
              from all_tab_columns c left join all_col_comments m on m.owner = c.owner and m.table_name = c.table_name and m.column_name = c.column_name
             where c.owner = :o and c.table_name = :t order by c.column_id
            """, binds: [b("o", owner), b("t", table)], limit: 2000)
        var out: [String: ColumnDictionaryInfo] = [:]
        for r in cols {
            let name = r[0].displayText ?? ""
            let dt = r[1].displayText ?? ""
            var type = dt
            if let p = r[3].displayText, !p.isEmpty { type += r[4].displayText.map { $0 == "0" ? "(\(p))" : "(\(p),\($0))" } ?? "(\(p))" }
            else if ["VARCHAR2", "NVARCHAR2", "CHAR", "NCHAR", "RAW"].contains(dt), let l = r[2].displayText { type += "(\(l))" }
            out[name] = ColumnDictionaryInfo(type: type, nullable: r[5].displayText != "N", comment: r[6].displayText, keys: [], values: [])
        }
        let (_, cons) = try await s.queryAll("""
            select c.constraint_type, cc.column_name, c.search_condition_vc, p.owner, p.table_name, pc.column_name
              from all_constraints c join all_cons_columns cc on cc.owner = c.owner and cc.constraint_name = c.constraint_name
              left join all_constraints p on p.owner = c.r_owner and p.constraint_name = c.r_constraint_name
              left join all_cons_columns pc on pc.owner = p.owner and pc.constraint_name = p.constraint_name and pc.position = cc.position
             where c.owner = :o and c.table_name = :t and c.constraint_type in ('P', 'U', 'R', 'C')
            """, binds: [b("o", owner), b("t", table)], limit: 10_000)
        for r in cons {
            guard let col = r[1].displayText, out[col] != nil else { continue }
            switch r[0].displayText {
            case "P": out[col]?.keys.insert(.primary)
            case "U": out[col]?.keys.insert(.unique)
            case "R":
                out[col]?.keys.insert(.foreign)
                if out[col]?.values.isEmpty == true, let po = r[3].displayText, let pt = r[4].displayText, let pcol = r[5].displayText {
                    let src = ResultExporter.identifier(po) + "." + ResultExporter.identifier(pt)
                    let count = Int(try await s.scalar("select count(*) from (select 1 from \(src) where rownum <= \(fkLimit + 1))") ?? "0") ?? 0
                    if count > 0, count <= fkLimit {
                        let (_, vals) = try await s.queryAll("select distinct \(ResultExporter.identifier(pcol)) from \(src) order by 1", limit: fkLimit)
                        out[col]?.values = vals.compactMap { $0.first?.displayText }
                    }
                }
            case "C":
                if let cond = r[2].displayText, let v = checkValues(cond, column: col) { out[col]?.values = v }
            default: break
            }
        }
        return out
    }

    /// Tabela zapytania siatki (pierwsza po FROM) z właścicielem (domyślnie bieżący schemat).
    public static func table(of sql: String, in s: any DatabaseSession) async throws -> (owner: String, table: String)? {
        guard let raw = ResultExporter.tableName(fromQuery: sql) else { return nil }
        let parts = raw.split(separator: ".").map { String($0).replacingOccurrences(of: "\"", with: "") }
        let name = (parts.last ?? raw)
        let owner: String
        if parts.count == 2 { owner = parts[0] } else { owner = try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? "" }
        let quoted = raw.contains("\"")
        return (quoted ? owner : owner.uppercased(), quoted ? name : name.uppercased())
    }
}

extension RecordsPerPage {
    /// Liczba wierszy pobieranych na start.
    var initialRows: Int {
        switch self {
        case .automatic: 100
        case .fixed(let n): Swift.max(1, n)
        case .all: 5_000_000
        }
    }
}

/// Szacowany rozmiar wiersza w pamięci (PD-SQLW-026): tekst UTF-16, bajty, stały narzut na wartość.
enum ResultSize {
    static func bytes(_ row: [OracleValue]) -> Int {
        row.reduce(0) { acc, v in
            acc + 16 + {
                switch v {
                case .text(let s), .number(let s), .json(let s), .rowid(let s): return s.utf16.count * 2
                case .raw(let d): return d.count
                case .lob(let l): return (l.text?.utf16.count ?? 0) * 2 + (l.bytes?.count ?? 0)
                case .object(_, let d): return d.utf16.count * 2
                case .vector(let x): return x.count * 8
                default: return 8
                }
            }()
        }
    }
}
