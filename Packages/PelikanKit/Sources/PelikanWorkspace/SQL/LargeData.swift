import Foundation
import Observation
import PelikanDB

/// Rozpoznany format treści (UG 27: Large Data Editor — tekst, RTF/XML/HTML, obraz, hex).
public enum LargeDataFormat: String, Sendable {
    case text, xml, json, html, rtf, png, jpeg, gif, pdf, binary

    public var isImage: Bool { [.png, .jpeg, .gif].contains(self) }
    public var isText: Bool { [.text, .xml, .json, .html, .rtf].contains(self) }

    public var fileExtension: String {
        switch self {
        case .text: "txt"
        case .xml: "xml"
        case .json: "json"
        case .html: "html"
        case .rtf: "rtf"
        case .png: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .pdf: "pdf"
        case .binary: "bin"
        }
    }

    /// Rozpoznanie po sygnaturze bajtów i początku tekstu.
    public static func detect(text: String?, bytes: Data?) -> LargeDataFormat {
        if let b = bytes, !b.isEmpty {
            if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
            if b.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
            if b.starts(with: Array("GIF8".utf8)) { return .gif }
            if b.starts(with: Array("%PDF".utf8)) { return .pdf }
            if let s = String(data: b.prefix(4096), encoding: .utf8), !s.contains("\0") { return detect(text: s, bytes: nil) }
            return .binary
        }
        let s = (text ?? "").drop { $0.isWhitespace }.prefix(200).lowercased()
        if s.hasPrefix("{\\rtf") { return .rtf }
        if s.hasPrefix("<!doctype html") || s.hasPrefix("<html") { return .html }
        if s.hasPrefix("<?xml") || (s.hasPrefix("<") && s.contains(">")) { return .xml }
        if s.hasPrefix("{") || s.hasPrefix("[") { return .json }
        return .text
    }
}

/// Model Large Data Editor dla komórki siatki: pełna treść (ponowne pobranie po ROWID, gdy w siatce obcięta),
/// format, formatowanie JSON/XML, zapis zmian do siatki (zatwierdzany razem z resztą zmian przez Post).
@MainActor
@Observable
public final class LargeDataModel {
    public let grid: ResultGridModel
    public let row: Int
    public let column: Int
    public private(set) var text: String?
    public private(set) var bytes: Data?
    public private(set) var totalLength: UInt64
    public private(set) var truncated: Bool
    public private(set) var format: LargeDataFormat
    public private(set) var isLoading = false
    public var modified = false

    public var columnName: String { grid.columns[column].name }
    public var typeName: String { grid.columns[column].typeName }
    public var isBinary: Bool { [.blob, .raw, .longRaw, .bfile].contains(grid.columns[column].type) }
    /// Zmiana możliwa przy włączonej edycji wyniku i kolumnie z tabeli edytowanej (BFILE — tylko odczyt).
    public var isEditable: Bool {
        guard grid.edit.isEditing, let t = grid.edit.target, grid.columns[column].type != .bfile else { return false }
        return t.editableColumns.contains(column) || t.largeDataColumns.contains(column)
    }

    public init(grid: ResultGridModel, row: Int, column: Int) {
        self.grid = grid
        self.row = row
        self.column = column
        let v = grid.value(row: row, column: column)
        var t: String?, b: Data?, len: UInt64 = 0, cut = false
        switch v {
        case .lob(let l):
            t = l.text; b = l.bytes; len = l.length; cut = l.truncated
        case .raw(let d):
            b = d; len = UInt64(d.count)
        case .null:
            if grid.columns[column].type.isCharacter { t = "" } else { b = Data() }
        default:
            let s = grid.text(row: row, column: column)
            t = s; len = UInt64(s.count)
        }
        text = t; bytes = b; totalLength = len; truncated = cut
        format = LargeDataFormat.detect(text: t, bytes: b)
    }

    /// Pełna treść LOB (siatka pobiera do limitu) — ponowne zapytanie po ROWID; bez ROWID zostaje obcięta.
    public func loadFull(limit: Int = 256 << 20) async throws {
        guard truncated, let rid = grid.rowidColumn, let name = grid.edit.target?.qualifiedName ?? ResultExporter.tableName(fromQuery: grid.sql).map(ResultExporter.qualifiedIdentifier) else { return }
        let col = grid.edit.target?.tableColumn[column] ?? grid.columns[column].name
        isLoading = true
        defer { isLoading = false }
        let r = try await grid.session.execute("SELECT \(ResultExporter.identifier(col)) FROM \(name) WHERE ROWID = :rid",
                                              binds: [BindVariable(name: "rid", value: .text(grid.value(row: row, column: rid).format(.default)))],
                                              options: ExecuteOptions(lobLimit: limit))
        guard let rs = r.resultSet else { return }
        let batch = try await grid.session.fetch(rs.id, maxRows: 1)
        await grid.session.closeResultSet(rs.id)
        guard case .lob(let l)? = batch.rows.first?.first else { return }
        text = l.text; bytes = l.bytes; totalLength = l.length; truncated = l.truncated
        format = LargeDataFormat.detect(text: text, bytes: bytes)
    }

    /// Zmiana tekstu (CLOB, LONG, VARCHAR2) albo bajtów (BLOB, RAW — np. wczytanie z pliku).
    public func setText(_ s: String) {
        text = s
        modified = true
        format = LargeDataFormat.detect(text: s, bytes: nil)
    }

    public func setBytes(_ d: Data) {
        bytes = d
        text = nil
        modified = true
        totalLength = UInt64(d.count)
        format = LargeDataFormat.detect(text: nil, bytes: d)
    }

    /// Treść do zapisu w pliku.
    public var fileData: Data { bytes ?? Data((text ?? "").utf8) }

    /// Zapis zmian w siatce (do zatwierdzenia przez Post).
    public func apply() throws {
        guard modified else { return }
        let type = grid.columns[column].type
        let value: OracleValue
        switch type {
        case .clob, .nclob:
            let s = text ?? String(decoding: bytes ?? Data(), as: UTF8.self)
            value = s.isEmpty ? .null : .lob(LOBValue(kind: type == .nclob ? .nclob : .clob, text: s, length: UInt64(s.count), truncated: false))
        case .blob:
            let d = bytes ?? Data((text ?? "").utf8)
            value = d.isEmpty ? .null : .lob(LOBValue(kind: .blob, bytes: d, length: UInt64(d.count), truncated: false))
        case .raw, .longRaw:
            let d = bytes ?? Data((text ?? "").utf8)
            value = d.isEmpty ? .null : .raw(d)
        default:
            let s = text ?? ""
            if grid.edit.target?.editableColumns.contains(column) == true {
                try grid.setText(s, row: row, column: column)
                modified = false
                return
            }
            value = s.isEmpty ? .null : .text(s)
        }
        try grid.setValue(value, row: row, column: column)
        modified = false
    }

    /// JSON z wcięciami (sortowanie kluczy wyłączone — kolejność jak w dokumencie nie jest gwarantowana przez parser).
    nonisolated public static func prettyJSON(_ s: String) -> String? {
        guard let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    /// XML z wcięciami (bez parsera z Foundation XML — także na Linuksie): elementy z samym tekstem w jednej linii,
    /// komentarze, CDATA, deklaracje bez zmian. nil — to nie XML.
    nonisolated public static func prettyXML(_ s: String, indent: String = "  ") -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"),
              let re = try? NSRegularExpression(pattern: #"<!\[CDATA\[.*?\]\]>|<!--.*?-->|<[^>]+>|[^<]+"#, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = trimmed as NSString
        var lines: [String] = []
        var depth = 0
        // Linia otwarcia elementu, do której dopisujemy tekst i zamknięcie (<a>tekst</a>).
        var openLine: Int?
        for m in re.matches(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
            let tok = ns.substring(with: m.range)
            let pad = { (d: Int) in String(repeating: indent, count: d) }
            if tok.hasPrefix("</") {
                depth = max(0, depth - 1)
                if let i = openLine { lines[i] += tok } else { lines.append(pad(depth) + tok) }
                openLine = nil
            } else if tok.hasPrefix("<") {
                lines.append(pad(depth) + tok)
                let standalone = tok.hasSuffix("/>") || tok.hasPrefix("<?") || tok.hasPrefix("<!")
                if standalone { openLine = nil } else { depth += 1; openLine = lines.count - 1 }
            } else {
                let text = tok.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if let i = openLine { lines[i] += text } else { lines.append(pad(depth) + text) }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Auto Format (PD-LDE-001): tekst JSON/XML sformatowany do wyświetlenia; nil — bez zmian (inny format, błąd).
    nonisolated public static func autoFormatted(_ s: String, format: LargeDataFormat) -> String? {
        let out: String? = switch format {
        case .json: prettyJSON(s)
        case .xml: prettyXML(s)
        default: nil
        }
        return out == s ? nil : out
    }

    /// Dokument podglądu HTML (PD-LDE-001): bez skryptów i zasobów zewnętrznych (CSP), obrazy tylko `data:`.
    nonisolated public static func htmlPreviewDocument(_ s: String) -> String {
        LocalHTML.contentSecurityPolicy + s
    }

    /// Szesnastkowy podgląd (offset, bajty, ASCII), ograniczony do `limit` bajtów.
    nonisolated public static func hexDump(_ d: Data, limit: Int = 1 << 20) -> String {
        var out = ""
        let bytes = [UInt8](d.prefix(limit))
        out.reserveCapacity(bytes.count * 4)
        var i = 0
        while i < bytes.count {
            let line = bytes[i..<min(i + 16, bytes.count)]
            out += String(format: "%08X  ", i)
            out += line.map { String(format: "%02X", $0) }.joined(separator: " ")
            out += String(repeating: "   ", count: 16 - line.count)
            out += "  " + String(line.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." }) + "\n"
            i += 16
        }
        if d.count > limit { out += L10n.tr("… (pokazano \(limit) z \(d.count) bajtów)\n") }
        return out
    }
}
