import Foundation
import PelikanDB

/// `SET SQLFORMAT` (SC-CMD-002, jak w SQLcl): format wyników zapytań w oknie poleceń.
public enum SQLFormat: Sendable, Equatable {
    case csv, json, xml, html, insert, loader, fixed, ansiconsole
    /// `delimited separator [lewy [prawy]]` — separator i ograniczniki tekstu.
    case delimited(separator: String, left: String, right: String)

    public var name: String {
        switch self {
        case .csv: "csv"
        case .json: "json"
        case .xml: "xml"
        case .html: "html"
        case .insert: "insert"
        case .loader: "loader"
        case .fixed: "fixed"
        case .ansiconsole: "ansiconsole"
        case .delimited(let s, let l, let r): "delimited \(s) \(l) \(r)"
        }
    }

    /// Argumenty po `SET SQLFORMAT`; nil — format domyślny (bez argumentu albo `default`).
    public static func parse(_ args: [String]) throws -> SQLFormat? {
        guard let first = args.first?.lowercased(), first != "default" else { return nil }
        switch first {
        case "csv": return .csv
        case "json", "json-formatted": return .json
        case "xml": return .xml
        case "html": return .html
        case "insert": return .insert
        case "loader": return .loader
        case "fixed": return .fixed
        case "ansiconsole": return .ansiconsole
        case "delimited":
            let sep = args.count > 1 ? args[1] : ","
            let left = args.count > 2 ? args[2] : "\""
            let right = args.count > 3 ? args[3] : left
            return .delimited(separator: sep, left: left, right: right)
        default:
            throw SQLPlusError(L10n.tr("Nieznany format SQLFORMAT: \(first) (csv, json, xml, html, insert, loader, fixed, delimited, ansiconsole, default)"))
        }
    }
}

/// Formatowanie porcji wierszy zapytania w wybranym formacie (nagłówek, wiersze, zakończenie).
struct SQLFormatter {
    let format: SQLFormat
    let columns: [ColumnInfo]
    let valueFormat: ValueFormat
    let table: String
    private(set) var rowsWritten = 0
    private var widths: [Int] = []

    init(format: SQLFormat, columns: [ColumnInfo], valueFormat: ValueFormat, table: String) {
        self.format = format; self.columns = columns; self.valueFormat = valueFormat; self.table = table
    }

    static func isText(_ c: ColumnInfo) -> Bool {
        [.varchar2, .nvarchar2, .char, .nchar, .clob, .nclob, .long, .rowid, .urowid, .date, .timestamp, .timestampTZ, .timestampLTZ,
         .intervalDS, .intervalYM, .json, .xmltype].contains(c.type)
    }

    func text(_ v: OracleValue) -> String? {
        if case .null = v { return nil }
        if case .lob(let l) = v { return l.text ?? l.bytes.map { $0.map { String(format: "%02X", $0) }.joined() } }
        return v.format(valueFormat)
    }

    static func jsonString(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) } else { out.unicodeScalars.append(ch) }
            }
        }
        return out + "\""
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    func quoted(_ s: String, left: String, right: String) -> String {
        left + (right.isEmpty ? s : s.replacingOccurrences(of: right, with: right + right)) + right
    }

    func header() -> [String] {
        switch format {
        case .csv: return [columns.map { "\"\($0.name)\"" }.joined(separator: ",")]
        case .delimited(let s, let l, let r): return [columns.map { quoted($0.name, left: l, right: r) }.joined(separator: s)]
        case .json:
            let cols = columns.map { "{\"name\":\(Self.jsonString($0.name)),\"type\":\(Self.jsonString($0.typeName))}" }.joined(separator: ",")
            return ["{\"results\":[{\"columns\":[\(cols)],\"items\":["]
        case .xml: return ["<?xml version='1.0' encoding='UTF-8' ?>", "<RESULTS>"]
        case .html:
            return ["<table>", "<tr>" + columns.map { "<th>\(Self.xmlEscape($0.name))</th>" }.joined() + "</tr>"]
        case .insert, .loader, .fixed, .ansiconsole: return []
        }
    }

    mutating func lines(_ rows: [[OracleValue]]) -> [String] {
        var out: [String] = []
        if format == .fixed || format == .ansiconsole, widths.isEmpty {
            // Szerokość kolumny: nazwa albo najdłuższa wartość pierwszej porcji (do 60 znaków).
            widths = columns.indices.map { i in min(60, max(columns[i].name.count, rows.map { (text($0[i]) ?? "").count }.max() ?? 0)) }
            if format == .ansiconsole {
                out.append(columns.indices.map { columns[$0].name.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }.joined(separator: " "))
                out.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: " "))
            }
        }
        for row in rows {
            let values = row.map(text)
            switch format {
            case .csv:
                out.append(columns.indices.map { i in
                    guard let v = values[i] else { return "" }
                    return Self.isText(columns[i]) ? quoted(v, left: "\"", right: "\"") : v
                }.joined(separator: ","))
            case .delimited(let s, let l, let r):
                out.append(columns.indices.map { i in
                    guard let v = values[i] else { return "" }
                    return Self.isText(columns[i]) ? quoted(v, left: l, right: r) : v
                }.joined(separator: s))
            case .loader:
                out.append(columns.indices.map { i in values[i].map { quoted($0, left: "\"", right: "\"") } ?? "" }.joined(separator: "|") + "|")
            case .json:
                let fields = columns.indices.map { i -> String in
                    let v: String
                    if let s = values[i] {
                        v = Self.isText(columns[i]) || Double(s) == nil ? Self.jsonString(s) : s
                    } else { v = "null" }
                    return "\(Self.jsonString(columns[i].name.lowercased())):\(v)"
                }.joined(separator: ",")
                out.append((rowsWritten > 0 ? "," : "") + "{\(fields)}")
            case .xml:
                out.append("<ROW>" + columns.indices.map { i in
                    "<COLUMN NAME=\"\(Self.xmlEscape(columns[i].name))\">" + (values[i].map { "<![CDATA[\($0.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>"))]]>" } ?? "") + "</COLUMN>"
                }.joined() + "</ROW>")
            case .html:
                out.append("<tr>" + values.map { "<td>\(Self.xmlEscape($0 ?? ""))</td>" }.joined() + "</tr>")
            case .insert:
                let cols = columns.map { ResultExporter.identifier($0.name) }.joined(separator: ",")
                out.append("INSERT INTO \(table) (\(cols)) VALUES (\(row.map(ResultExporter.literal).joined(separator: ",")));")
            case .fixed, .ansiconsole:
                out.append(columns.indices.map { i in
                    let v = values[i] ?? ""
                    let w = widths[i]
                    let cut = v.count > w ? String(v.prefix(w)) : v
                    return Self.isText(columns[i]) ? cut.padding(toLength: w, withPad: " ", startingAt: 0)
                        : String(repeating: " ", count: max(0, w - cut.count)) + cut
                }.joined(separator: format == .fixed ? "" : " "))
            }
            rowsWritten += 1
        }
        return out
    }

    func footer() -> [String] {
        switch format {
        case .json: return ["]}]}"]
        case .xml: return ["</RESULTS>"]
        case .html: return ["</table>"]
        default: return []
        }
    }
}
