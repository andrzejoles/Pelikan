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
    // BREAK/COMPUTE (PD-CMDW-004): kolumny przerwań, ostatnie wartości i akumulatory grup (ostatni — REPORT).
    private var breakColumns: [(index: Int, spec: SQLPlusBreak)] = []
    private var lastKeys: [String]?
    private var groups: [ComputeAccumulator] = []
    private var report = ComputeAccumulator()

    public init(columns: [ColumnInfo], state: SQLPlusState, format: ValueFormat) {
        self.columns = columns
        self.state = state
        self.format = format
        let names = columns.map { $0.name.uppercased() }
        breakColumns = state.breaks.compactMap { b in names.firstIndex(of: b.column).map { ($0, b) } }
        groups = Array(repeating: ComputeAccumulator(), count: breakColumns.count)
    }

    private var computeColumns: Set<Int> {
        let names = columns.map { $0.name.uppercased() }
        return Set(state.computes.flatMap(\.of).compactMap { names.firstIndex(of: $0) })
    }

    /// Linie podsumowania COMPUTE grupy (kolumna przerwania albo REPORT).
    private func summary(on breakName: String, at breakIndex: Int?, _ acc: ComputeAccumulator) -> [String] {
        let names = columns.map { $0.name.uppercased() }
        var out: [String] = []
        for c in state.computes where c.on.contains(breakName) {
            let of = Set(c.of.compactMap { names.firstIndex(of: $0) })
            guard !of.isEmpty else { continue }
            let labelColumn = breakIndex ?? 0
            let rule = columns.indices.map { i -> String in
                if of.contains(i) { return String(repeating: "-", count: widths[i]) }
                if i == breakIndex { return String(repeating: "*", count: widths[i]) }
                return String(repeating: " ", count: widths[i])
            }
            out.append(rule.joined(separator: state.colSep).trimmingTrailingSpaces)
            for f in c.functions {
                let cells = columns.indices.map { i -> String in
                    if of.contains(i) {
                        let v = acc.value(f, column: i)
                        let s = v.number.map { aggregate($0, column: i) } ?? v.text ?? ""
                        let t = s.count > widths[i] ? String(repeating: "#", count: widths[i]) : s
                        return String(repeating: " ", count: widths[i] - t.count) + t
                    }
                    if i == labelColumn {
                        let l = c.label ?? f.rawValue
                        let t = l.count > widths[i] ? String(l.prefix(widths[i])) : l
                        return t + String(repeating: " ", count: widths[i] - t.count)
                    }
                    return String(repeating: " ", count: widths[i])
                }
                out.append(cells.joined(separator: state.colSep).trimmingTrailingSpaces)
            }
        }
        return out
    }

    private func aggregate(_ d: Double, column i: Int) -> String {
        if let fmt = state.columns[columns[i].name.uppercased()]?.format, !fmt.uppercased().hasPrefix("A") { return Self.number(d, format: fmt) }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        var s = String(format: "%.6f", d)
        while s.last == "0" { s.removeLast() }
        if s.last == "." { s.removeLast() }
        return s
    }

    /// Podsumowania otwartych grup i REPORT po ostatnim wierszu (wywołać raz, na końcu wyniku).
    public mutating func finish() -> [String] {
        guard lastKeys != nil else { return [] }
        var out: [String] = []
        for level in breakColumns.indices.reversed() {
            out += summary(on: breakColumns[level].spec.column, at: breakColumns[level].index, groups[level])
        }
        out += summary(on: "REPORT", at: nil, report)
        lastKeys = nil
        return out
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
            var hidden = Set<Int>()
            if !breakColumns.isEmpty || !state.computes.isEmpty {
                let keys = breakColumns.map { cell(r[$0.index], column: $0.index) }
                if let last = lastKeys {
                    // Pierwszy poziom ze zmianą zamyka grupy od najgłębszej do niego (potem SKIP); kolumny przerwań
                    // nad nim (bez zmiany) są ukrywane, chyba że DUPLICATES.
                    let changed = keys.indices.first(where: { keys[$0] != last[$0] }) ?? breakColumns.count
                    for level in (changed..<breakColumns.count).reversed() {
                        out += summary(on: breakColumns[level].spec.column, at: breakColumns[level].index, groups[level])
                        groups[level] = ComputeAccumulator()
                    }
                    out += Array(repeating: "", count: breakColumns[changed...].map(\.spec.skip).max() ?? 0)
                    hidden = Set(breakColumns[..<changed].filter { !$0.spec.duplicates }.map(\.index))
                }
                lastKeys = keys
                let of = computeColumns
                for level in groups.indices { groups[level].add(r, columns: of) }
                report.add(r, columns: of)
            }
            out.append(columns.indices.map { pad(hidden.contains($0) ? "" : cell(r[$0], column: $0), $0) }
                .joined(separator: state.colSep).trimmingTrailingSpaces)
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
