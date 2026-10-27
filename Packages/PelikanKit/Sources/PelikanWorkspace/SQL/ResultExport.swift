import Foundation
import PelikanDB
import PelikanSQL

/// Formaty eksportu i kopiowania wyniku (UG 7.2: Export Results, Copy…, Copy to Excel).
public enum ExportFormat: String, CaseIterable, Sendable, Codable {
    case csv, tsv, html, xml, sql, expressionList, xlsx

    public var displayName: String {
        switch self {
        case .csv: L10n.tr("CSV")
        case .tsv: L10n.tr("TSV (tabulatory)")
        case .html: L10n.tr("HTML")
        case .xml: L10n.tr("XML")
        case .sql: L10n.tr("SQL (INSERT)")
        case .expressionList: L10n.tr("Lista wyrażeń (IN)")
        case .xlsx: L10n.tr("Excel (xlsx)")
        }
    }

    public var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .tsv: "tsv"
        case .html: "html"
        case .xml: "xml"
        case .sql: "sql"
        case .expressionList: "txt"
        case .xlsx: "xlsx"
        }
    }
}

/// Dane do eksportu: kolumny i wiersze w kolejności widoku (po sortowaniu i zaznaczeniu).
public struct ExportData: Sendable {
    public var title: String
    public var columns: [ColumnInfo]
    public var rows: [[OracleValue]]
    /// Tabela dla INSERT (z zapytania); brak → `TABELA`.
    public var tableName: String?
    public var sql: String?

    public init(title: String, columns: [ColumnInfo], rows: [[OracleValue]], tableName: String? = nil, sql: String? = nil) {
        self.title = title; self.columns = columns; self.rows = rows; self.tableName = tableName; self.sql = sql
    }
}

public struct ExportOptions: Sendable {
    public var includeHeader = true
    public var csvSeparator: Character = ","
    public var format = ValueFormat.default
    public init() {}
}

public enum ResultExporter {
    // MARK: Formaty tekstowe

    public static func text(_ format: ExportFormat, _ data: ExportData, options: ExportOptions = ExportOptions()) -> String {
        switch format {
        case .csv: delimited(data, separator: options.csvSeparator, options: options)
        case .tsv: delimited(data, separator: "\t", options: options)
        case .html: html(data, options: options)
        case .xml: xml(data, options: options)
        case .sql: sqlInserts(data)
        case .expressionList: expressionList(data)
        case .xlsx: delimited(data, separator: "\t", options: options)   // schowek: Excel wkleja TSV
        }
    }

    /// Tekst wartości do eksportu: LOB z treścią (jeśli pobrana), reszta jak w siatce.
    static func cell(_ v: OracleValue, _ f: ValueFormat) -> String {
        if case .lob(let l) = v, let t = l.text { return t }
        return v.format(f)
    }

    /// CSV (RFC 4180: cudzysłów przy separatorze, cudzysłowie, nowej linii) i TSV (tabulatory i nowe linie → spacje).
    static func delimited(_ data: ExportData, separator: Character, options: ExportOptions) -> String {
        let isTab = separator == "\t"
        func field(_ s: String) -> String {
            if isTab { return s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ") }
            if s.contains(separator) || s.contains("\"") || s.contains("\n") || s.contains("\r") || s.hasPrefix(" ") || s.hasSuffix(" ") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        var lines: [String] = []
        if options.includeHeader { lines.append(data.columns.map { field($0.name) }.joined(separator: String(separator))) }
        for row in data.rows { lines.append(row.map { field(cell($0, options.format)) }.joined(separator: String(separator))) }
        return lines.joined(separator: isTab ? "\n" : "\r\n") + (isTab ? "" : "\r\n")
    }

    static func escapeHTML(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Styl tabeli wyniku (eksport HTML, druk).
    static let tableCSS = "table{border-collapse:collapse}th,td{border:1px solid #bbb;padding:2px 6px}"
        + "th{background:#eee;text-align:left}td.n{text-align:right}td.null{background:#fffbd0}thead{display:table-header-group}"

    static func html(_ data: ExportData, options: ExportOptions) -> String {
        var s = "<!DOCTYPE html>\n<html lang=\"pl\"><head><meta charset=\"utf-8\"><title>\(escapeHTML(data.title))</title>\n"
        s += "<style>body{font:13px -apple-system,system-ui,sans-serif}\(tableCSS)</style></head><body>\n"
        return s + htmlTable(data, options: options) + "</body></html>\n"
    }

    /// Sama tabela wyniku (`<table>…</table>`).
    static func htmlTable(_ data: ExportData, options: ExportOptions) -> String {
        var s = "<table>\n"
        if options.includeHeader {
            s += "<thead><tr>" + data.columns.map { "<th>\(escapeHTML($0.name))</th>" }.joined() + "</tr></thead>\n"
        }
        s += "<tbody>\n"
        for row in data.rows {
            s += "<tr>"
            for (i, v) in row.enumerated() {
                let cls = v.isNull ? " class=\"null\"" : (data.columns[i].type.isNumeric ? " class=\"n\"" : "")
                s += "<td\(cls)>\(escapeHTML(cell(v, options.format)).replacingOccurrences(of: "\n", with: "<br>"))</td>"
            }
            s += "</tr>\n"
        }
        return s + "</tbody>\n</table>\n"
    }

    /// Nazwa elementu XML z nazwy kolumny (znaki spoza nazw XML jako `_xHHHH_`, jak w kanonicznym XML Oracle).
    static func xmlName(_ name: String) -> String {
        var out = ""
        for (i, u) in name.unicodeScalars.enumerated() {
            let ok = u == "_" || CharacterSet.letters.contains(u) || (i > 0 && (CharacterSet.decimalDigits.contains(u) || u == "-" || u == "."))
            out += ok ? String(u) : String(format: "_x%04X_", u.value)
        }
        return out.isEmpty ? "_" : out
    }

    static func escapeXML(_ s: String) -> String {
        var out = escapeHTML(s).replacingOccurrences(of: "'", with: "&apos;")
        // Znaki sterujące niedozwolone w XML 1.0.
        out.unicodeScalars.removeAll { $0.value < 0x20 && $0 != "\t" && $0 != "\n" && $0 != "\r" }
        return out
    }

    /// XML w układzie ROWSET/ROW (jak DBMS_XMLGEN); NULL — element pominięty.
    static func xml(_ data: ExportData, options: ExportOptions) -> String {
        let names = data.columns.map { xmlName($0.name) }
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ROWSET>\n"
        for row in data.rows {
            s += " <ROW>\n"
            for (i, v) in row.enumerated() where !v.isNull {
                s += "  <\(names[i])>\(escapeXML(cell(v, options.format)))</\(names[i])>\n"
            }
            s += " </ROW>\n"
        }
        return s + "</ROWSET>\n"
    }

    // MARK: SQL

    /// Identyfikator w SQL: zwykły (wielkie litery, bez znaków specjalnych) albo w cudzysłowie.
    static func identifier(_ name: String) -> String {
        if name.range(of: #"^[A-Z][A-Z0-9_$#]*$"#, options: .regularExpression) != nil, !Keywords.reserved.contains(name) { return name }
        return "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Identyfikator wstawiany w tekst (kopiowanie nazw, przeciąganie z Object Browsera): zwykły małymi literami,
    /// w cudzysłowie bez zmian — `"MyTab"` to inny obiekt niż `"mytab"`.
    static func displayIdentifier(_ name: String) -> String {
        let id = identifier(name)
        return id.hasPrefix("\"") ? id : id.lowercased()
    }

    /// `właściciel.nazwa` w postaci `displayIdentifier`.
    static func displayQualified(owner: String, name: String) -> String { displayIdentifier(owner) + "." + displayIdentifier(name) }

    /// Nazwa z `tableName(fromQuery:)` (bez cudzysłowów, `WŁAŚCICIEL.TABELA`) w składni SQL.
    static func qualifiedIdentifier(_ name: String) -> String {
        name.split(separator: ".").map { identifier(String($0)) }.joined(separator: ".")
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    /// Literał SQL wartości (do INSERT i listy wyrażeń).
    public static func literal(_ v: OracleValue) -> String {
        switch v {
        case .null: return "NULL"
        case .number(let s): return s
        case .double(let d):
            if d.isNaN { return "BINARY_DOUBLE_NAN" }
            if d.isInfinite { return d > 0 ? "BINARY_DOUBLE_INFINITY" : "-BINARY_DOUBLE_INFINITY" }
            return String(d)
        case .boolean(let b): return b ? "TRUE" : "FALSE"
        case .text(let s), .rowid(let s): return quote(s)
        case .json(let s): return "JSON(" + quote(s) + ")"
        case .timestamp(let t, let type):
            switch type {
            case .date: return "TO_DATE('\(t.formatted("YYYY-MM-DD HH24:MI:SS"))', 'YYYY-MM-DD HH24:MI:SS')"
            case .timestampTZ:
                return "TO_TIMESTAMP_TZ('\(t.formatted("YYYY-MM-DD HH24:MI:SS.FF9 TZH:TZM", zone: true))', 'YYYY-MM-DD HH24:MI:SS.FF9 TZH:TZM')"
            default: return "TO_TIMESTAMP('\(t.formatted("YYYY-MM-DD HH24:MI:SS.FF9"))', 'YYYY-MM-DD HH24:MI:SS.FF9')"
            }
        case .intervalDS, .intervalYM:
            let s = v.format(.default)
            if case .intervalDS = v { return "INTERVAL '\(s)' DAY(9) TO SECOND(9)" }
            return "INTERVAL '\(s)' YEAR(9) TO MONTH"
        case .raw(let d): return "HEXTORAW('\(d.hexUpper)')"
        case .lob(let l):
            if let t = l.text, !l.truncated {
                // Literał tekstowy ma limit 4000 bajtów — CLOB składany z kawałków.
                if t.utf8.count <= 4000 { return "TO_CLOB(\(quote(t)))" }
                return chunks(t, maxBytes: 3000).map { "TO_CLOB(\(quote($0)))" }.joined(separator: " || ")
            }
            if let b = l.bytes, !l.truncated, b.count <= 2000 { return "TO_BLOB(HEXTORAW('\(b.hexUpper)'))" }
            return "NULL /* \(l.kind.rawValue) \(l.length) */"
        case .vector(let x): return "TO_VECTOR('[" + x.map { String($0) }.joined(separator: ",") + "]')"
        case .object(let t, _): return "NULL /* \(t) */"
        case .cursor: return "NULL /* CURSOR */"
        }
    }

    static func chunks(_ s: String, maxBytes: Int) -> [String] {
        var out: [String] = []
        var current = ""
        var bytes = 0
        for ch in s {
            let n = String(ch).utf8.count
            if bytes + n > maxBytes { out.append(current); current = ""; bytes = 0 }
            current.append(ch)
            bytes += n
        }
        if !current.isEmpty || out.isEmpty { out.append(current) }
        return out
    }

    /// Kolumny, których nie da się wstawić (ROWID, kursory) — pomijane w INSERT.
    static func insertable(_ c: ColumnInfo) -> Bool { ![.rowid, .urowid, .refCursor].contains(c.type) && c.name != "ROWID" }

    static func sqlInserts(_ data: ExportData) -> String {
        let table = data.tableName.map(qualifiedIdentifier) ?? "TABELA"
        let cols = data.columns.indices.filter { insertable(data.columns[$0]) }
        let list = cols.map { identifier(data.columns[$0].name) }.joined(separator: ", ")
        var s = ""
        for row in data.rows {
            s += "INSERT INTO \(table) (\(list)) VALUES (" + cols.map { literal(row[$0]) }.joined(separator: ", ") + ");\n"
        }
        return s
    }

    /// `EMPNO IN (7369, 7499)`; dla wielu kolumn `(A, B) IN ((1, 'x'), …)`. Wartości bez powtórzeń.
    static func expressionList(_ data: ExportData) -> String {
        guard !data.columns.isEmpty else { return "" }
        var seen = Set<String>()
        var items: [String] = []
        for row in data.rows {
            let lit = row.count == 1 ? literal(row[0]) : "(" + row.map(literal).joined(separator: ", ") + ")"
            if seen.insert(lit).inserted { items.append(lit) }
        }
        let lhs = data.columns.count == 1 ? identifier(data.columns[0].name) : "(" + data.columns.map { identifier($0.name) }.joined(separator: ", ") + ")"
        return "\(lhs) IN (\(items.joined(separator: ", ")))"
    }

    /// Tabela z zapytania (pierwsza po FROM, bez złączeń) — nazwa dla INSERT i edycji.
    public static func tableName(fromQuery sql: String) -> String? {
        let tokens = Lexer(sql).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment, .hint].contains($0.kind) }
        let ns = sql as NSString
        func text(_ t: Token) -> String { ns.substring(with: NSRange(location: t.start, length: t.length)) }
        var depth = 0
        for (i, t) in tokens.enumerated() {
            if t.kind == .leftParen { depth += 1 } else if t.kind == .rightParen { depth -= 1 }
            guard depth == 0, text(t).uppercased() == "FROM", i + 1 < tokens.count else { continue }
            var name = ""
            var j = i + 1
            while j < tokens.count {
                let k = tokens[j]
                if k.kind == .identifier || k.kind == .quotedIdentifier || (k.kind == .keyword && name.hasSuffix(".")) {
                    var part = text(k)
                    part = k.kind == .quotedIdentifier ? String(part.dropFirst().dropLast()) : part.uppercased()
                    name += part
                } else if k.kind == .dot {
                    name += "."
                } else { break }
                j += 1
                if j < tokens.count, tokens[j].kind != .dot, !name.hasSuffix(".") { break }
            }
            // Złączenie (przecinek, JOIN) — tabela niejednoznaczna dla INSERT, ale pierwsza wystarczy jako podpowiedź.
            return name.isEmpty ? nil : name
        }
        return nil
    }

    // MARK: Excel (xlsx)

    /// Skoroszyt xlsx: arkusz na wynik (UG 7.2 „Copy all”), nagłówek pogrubiony, liczby jako liczby, daty jako daty,
    /// opcjonalnie arkusz z poleceniem SQL.
    public static func xlsx(_ sheets: [ExportData], includeSQL: Bool = false, options: ExportOptions = ExportOptions()) -> Data {
        var all = sheets
        if includeSQL {
            let sqlText = sheets.compactMap(\.sql).joined(separator: "\n\n")
            all.append(ExportData(title: "SQL", columns: [ColumnInfo(name: "SQL", type: .varchar2, typeName: "VARCHAR2")],
                                  rows: sqlText.components(separatedBy: "\n").map { [.text($0)] }))
        }
        var names: [String] = []
        for s in all {
            // Nazwa arkusza: maks. 31 znaków, bez []:*?/\, unikalna.
            var n = String(s.title.map { "[]:*?/\\".contains($0) ? "_" : $0 }.prefix(31))
            if n.isEmpty { n = "Wynik" }
            var k = 2
            let base = n
            while names.contains(n) { n = String(base.prefix(28)) + " \(k)"; k += 1 }
            names.append(n)
        }
        let zip = ZipWriter()
        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\(all.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined())</Types>
        """)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """)
        zip.add("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(names.enumerated().map { "<sheet name=\"\(escapeXML($1))\" sheetId=\"\($0 + 1)\" r:id=\"rId\($0 + 1)\"/>" }.joined())</sheets></workbook>
        """)
        zip.add("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(all.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined())<Relationship Id="rId\(all.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
        """)
        // Style: 0 zwykły, 1 nagłówek pogrubiony, 2 data z czasem, 3 data.
        zip.add("xl/styles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd\\ hh:mm:ss"/><numFmt numFmtId="165" formatCode="yyyy\\-mm\\-dd"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="4"><xf/><xf fontId="1" applyFont="1"/><xf numFmtId="164" applyNumberFormat="1"/><xf numFmtId="165" applyNumberFormat="1"/></cellXfs></styleSheet>
        """)
        for (i, s) in all.enumerated() { zip.add("xl/worksheets/sheet\(i + 1).xml", sheetXML(s, options: options)) }
        return zip.finish()
    }

    static func columnLetter(_ index: Int) -> String {
        var n = index + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(65 + r)!) + s
            n = (n - 1) / 26
        }
        return s
    }

    /// Data Excela (liczba dni od 1899-12-30) z części daty i czasu.
    static func excelSerial(_ t: OracleTimestamp) -> Double? {
        var c = DateComponents()
        c.year = Int(t.year); c.month = Int(t.month); c.day = Int(t.day)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: c), let base = cal.date(from: DateComponents(year: 1899, month: 12, day: 30)) else { return nil }
        let days = (d.timeIntervalSince(base) / 86400).rounded()
        return days + (Double(t.hour) * 3600 + Double(t.minute) * 60 + Double(t.second) + Double(t.fsecond) / 1e9) / 86400
    }

    static func sheetXML(_ data: ExportData, options: ExportOptions) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        var r = 1
        func inline(_ ref: String, _ text: String, style: Int = 0) -> String {
            "<c r=\"\(ref)\" t=\"inlineStr\"\(style > 0 ? " s=\"\(style)\"" : "")><is><t xml:space=\"preserve\">\(escapeXML(String(text.prefix(32767))))</t></is></c>"
        }
        if options.includeHeader {
            s += "<row r=\"1\">" + data.columns.enumerated().map { inline("\(columnLetter($0))1", $1.name, style: 1) }.joined() + "</row>"
            r = 2
        }
        for row in data.rows {
            s += "<row r=\"\(r)\">"
            for (i, v) in row.enumerated() {
                let ref = "\(columnLetter(i))\(r)"
                switch v {
                case .null: continue
                case .number(let n) where Double(n) != nil && n.count <= 15: s += "<c r=\"\(ref)\"><v>\(n)</v></c>"
                case .double(let d) where d.isFinite: s += "<c r=\"\(ref)\"><v>\(d)</v></c>"
                case .timestamp(let t, let type):
                    if let serial = excelSerial(t) {
                        let dateOnly = type == .date && t.hour == 0 && t.minute == 0 && t.second == 0
                        s += "<c r=\"\(ref)\" s=\"\(dateOnly ? 3 : 2)\"><v>\(serial)</v></c>"
                    } else { s += inline(ref, cell(v, options.format)) }
                case .boolean(let b): s += "<c r=\"\(ref)\" t=\"b\"><v>\(b ? 1 : 0)</v></c>"
                default: s += inline(ref, cell(v, options.format))
                }
            }
            s += "</row>"
            r += 1
        }
        return s + "</sheetData></worksheet>"
    }
}

/// Minimalny zapis ZIP (metoda „stored”, bez kompresji) — wystarcza dla xlsx; bez zależności zewnętrznych.
final class ZipWriter {
    private var data = Data()
    private var central = Data()
    private var count: UInt16 = 0

    func add(_ name: String, _ text: String) { add(name, Data(text.utf8)) }

    func add(_ name: String, _ content: Data) {
        let nameData = Data(name.utf8)
        let crc = CRC32.checksum(content)
        let offset = UInt32(data.count)
        // Lokalny nagłówek pliku.
        data.append(le32: 0x0403_4B50); data.append(le16: 20); data.append(le16: 0x0800)   // UTF-8 nazwy
        data.append(le16: 0); data.append(le16: 0); data.append(le16: 0x21)               // stored, czas, data (1980-01-01)
        data.append(le32: crc); data.append(le32: UInt32(content.count)); data.append(le32: UInt32(content.count))
        data.append(le16: UInt16(nameData.count)); data.append(le16: 0)
        data.append(nameData); data.append(content)
        // Wpis katalogu centralnego.
        central.append(le32: 0x0201_4B50); central.append(le16: 20); central.append(le16: 20); central.append(le16: 0x0800)
        central.append(le16: 0); central.append(le16: 0); central.append(le16: 0x21)
        central.append(le32: crc); central.append(le32: UInt32(content.count)); central.append(le32: UInt32(content.count))
        central.append(le16: UInt16(nameData.count)); central.append(le16: 0); central.append(le16: 0)
        central.append(le16: 0); central.append(le16: 0); central.append(le32: 0); central.append(le32: offset)
        central.append(nameData)
        count += 1
    }

    func finish() -> Data {
        var out = data
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x0605_4B50); out.append(le16: 0); out.append(le16: 0)
        out.append(le16: count); out.append(le16: count)
        out.append(le32: UInt32(central.count)); out.append(le32: centralOffset); out.append(le16: 0)
        return out
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func append(le16 v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
