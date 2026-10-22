import Foundation
import PelikanDB

/// Wynik zapytania jako tekst w stylu SQL*Plus (UG 8.3; PD-CMDW-013): nagłówki z podkreśleniem, kolumny o szerokości
/// z danych (z limitem COLWIDTH), liczby do prawej, COLSEP, powtarzanie nagłówków co PAGESIZE wierszy, COLUMN FORMAT.
public struct TextResultFormatter {
    public let columns: [ColumnInfo]
    public let state: SQLPlusState
    public let format: ValueFormat
    private(set) var widths: [Int] = []
    private var linesOnPage = 0

    public init(columns: [ColumnInfo], state: SQLPlusState, format: ValueFormat) {
        self.columns = columns
        self.state = state
        self.format = format
    }

    func heading(_ i: Int) -> String {
        state.columns[columns[i].name.uppercased()]?.heading ?? columns[i].name
    }

    /// Szerokości z pierwszej porcji danych (SQL*Plus liczy z typów — tu czytelniej z danych, jak w Command Window wzorca).
    public mutating func measure(_ rows: [[OracleValue]]) {
        widths = columns.indices.map { i in
            let c = columns[i]
            let fmt = state.columns[c.name.uppercased()]?.format
            if let fmt, fmt.uppercased().hasPrefix("A"), let n = Int(fmt.dropFirst()) { return max(n, 1) }
            if let fmt, !fmt.uppercased().hasPrefix("A") { return max(fmt.count, heading(i).count) }
            var w = heading(i).count
            for r in rows.prefix(1000) { w = max(w, cell(r[i], column: i).count) }
            if c.type.isNumeric { w = max(w, min(state.numWidth, 10)) }
            return min(max(w, 1), c.type.isNumeric ? 40 : max(state.colWidth, heading(i).count))
        }
    }

    func cell(_ v: OracleValue, column i: Int) -> String {
        let c = columns[i]
        if case .lob(let l) = v, let t = l.text { return String(t.prefix(state.long)).replacingOccurrences(of: "\n", with: " ") }
        var s = v.format(format)
        if case .lob = v { s = "<\(c.type.rawValue)>" }
        if let fmt = state.columns[c.name.uppercased()]?.format, c.type.isNumeric, !fmt.uppercased().hasPrefix("A"),
           case .number(let n) = v, let d = Double(n) {
            s = Self.number(d, format: fmt)
        }
        if c.type == .long { s = String(s.prefix(state.long)) }
        return s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
    }

    /// Format liczby wg maski SQL*Plus (podzbiór: 9, 0, przecinek grup, kropka dziesiętna).
    static func number(_ d: Double, format: String) -> String {
        let decimals = format.split(separator: ".", maxSplits: 1).dropFirst().first.map { $0.filter { $0 == "9" || $0 == "0" }.count } ?? 0
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        f.usesGroupingSeparator = format.contains(",")
        f.groupingSeparator = ","
        f.minimumIntegerDigits = format.split(separator: ".").first.map { $0.contains("0") ? 1 : 0 } ?? 1
        let s = f.string(from: NSNumber(value: d)) ?? String(d)
        let width = format.count
        return s.count > width ? String(repeating: "#", count: width) : s
    }

    func pad(_ s: String, _ i: Int) -> String {
        let w = widths[i]
        let t = s.count > w ? String(s.prefix(w)) : s
        let fill = String(repeating: " ", count: w - t.count)
        return columns[i].type.isNumeric ? fill + t : t + fill
    }

    func headerLines() -> [String] {
        guard state.heading else { return [] }
        let names = columns.indices.map { i -> String in
            let h = heading(i)
            let t = h.count > widths[i] ? String(h.prefix(widths[i])) : h
            let fill = String(repeating: " ", count: widths[i] - t.count)
            return columns[i].type.isNumeric ? fill + t : t + fill
        }
        let underline = widths.map { String(repeating: "-", count: $0) }
        return [names.joined(separator: state.colSep).trimmingTrailingSpaces, underline.joined(separator: state.colSep)]
    }

    /// Linie dla porcji wierszy (nagłówek na początku i co PAGESIZE wierszy; PAGESIZE 0 — bez nagłówków).
    public mutating func lines(_ rows: [[OracleValue]], first: Bool) -> [String] {
        if widths.isEmpty { measure(rows) }
        var out: [String] = []
        if first, state.pageSize > 0 { out += headerLines(); linesOnPage = 0 }
        for r in rows {
            if state.pageSize > 0, linesOnPage >= state.pageSize {
                out.append("")
                out += headerLines()
                linesOnPage = 0
            }
            out.append(columns.indices.map { pad(cell(r[$0], column: $0), $0) }.joined(separator: state.colSep).trimmingTrailingSpaces)
            linesOnPage += 1
        }
        return out
    }
}

extension String {
    var trimmingTrailingSpaces: String {
        var s = self
        while s.last == " " { s.removeLast() }
        return s
    }
}
