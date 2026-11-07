import Foundation
import Observation
import PelikanDB

/// Rozpoznany format treści (UG 27: Large Data Editor — tekst, RTF/XML/HTML, obraz, hex).
public enum LargeDataFormat: String, Sendable {
    case text, xml, json, html, rtf, png, jpeg, gif, tiff, bmp, webp, heic, pdf, zip, docx, xlsx, pptx, gzip, doc, xls, ppt, binary

    public var isImage: Bool { [.png, .jpeg, .gif, .tiff, .bmp, .webp, .heic].contains(self) }
    public var isText: Bool { [.text, .xml, .json, .html, .rtf].contains(self) }
    /// Rozpoznany format pliku, który Quick Look umie pokazać (obrazy, PDF, dokumenty Office, archiwa).
    public var isPreviewable: Bool { !isText && self != .binary }

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
        case .tiff: "tiff"
        case .bmp: "bmp"
        case .webp: "webp"
        case .heic: "heic"
        case .pdf: "pdf"
        case .zip: "zip"
        case .docx: "docx"
        case .xlsx: "xlsx"
        case .pptx: "pptx"
        case .gzip: "gz"
        case .doc: "doc"
        case .xls: "xls"
        case .ppt: "ppt"
        case .binary: "bin"
        }
    }

    /// Rozpoznanie po sygnaturze bajtów (magic number) i początku tekstu.
    public static func detect(text: String?, bytes: Data?) -> LargeDataFormat {
        if let b = bytes, !b.isEmpty {
            if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
            if b.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
            if b.starts(with: Array("GIF8".utf8)) { return .gif }
            if b.starts(with: Array("%PDF".utf8)) { return .pdf }
            if b.starts(with: [0x49, 0x49, 0x2A, 0x00]) || b.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
            func u16(_ o: Int) -> Int { Int(b[b.startIndex + o]) | Int(b[b.startIndex + o + 1]) << 8 }
            func u32(_ o: Int) -> Int { (0..<4).reduce(0) { $0 | Int(b[b.startIndex + o + $1]) << (8 * $1) } }
            // BMP: „BM” i znany rozmiar nagłówka DIB (sam „BM” to też tekst); bfSize 0 (dozwolone dla BI_RGB) albo co
            // najmniej rozmiar nagłówków — wartość bywa ucięta do limitu siatki albo ma dane po obrazie.
            if b.starts(with: Array("BM".utf8)), b.count > 18, u32(2) == 0 || u32(2) >= 26,
               [12, 40, 52, 56, 108, 124].contains(u32(14)) { return .bmp }
            if b.starts(with: Array("RIFF".utf8)), b.count >= 12, b.subdata(in: b.startIndex + 8 ..< b.startIndex + 12) == Data("WEBP".utf8) { return .webp }
            if b.count >= 12, b.subdata(in: b.startIndex + 4 ..< b.startIndex + 8) == Data("ftyp".utf8) {
                let brand = String(decoding: b.subdata(in: b.startIndex + 8 ..< b.startIndex + 12), as: UTF8.self)
                // Marki HEIC/HEVC (mif1/msf1 dzieli z AVIF — bez zgadywania).
                if ["heic", "heix", "hevc", "hevx"].contains(brand) { return .heic }
            }
            if b.starts(with: [0x1F, 0x8B]) { return .gzip }
            if b.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
                // Stary Office (OLE): rodzaj z nazwy strumienia w katalogu pliku — UTF-16LE zakończona NUL (nie dowolny
                // tekst w treści); w pierwszych 256 KB (stały koszt w panelu wartości); nieznany — dane binarne.
                // Katalog: pierwszy sektor z nagłówka (0x30), rozmiar sektora 2^(0x1E); przeszukiwane 64 KB katalogu
                // i 256 KB od początku — stały koszt niezależnie od rozmiaru pliku.
                var areas = [b.prefix(256 * 1024)]
                if b.count >= 0x34 {
                    let shift = u16(0x1E), sector = u32(0x30)
                    if (7...16).contains(shift), sector < 0xFFFF_FFFA {
                        let start = (sector + 1) << shift
                        if start < b.count { areas.append(b[(b.startIndex + start)...].prefix(64 * 1024)) }
                    }
                }
                func has(_ name: String) -> Bool {
                    let pattern = Data((name.utf16 + [0]).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
                    return areas.contains { $0.range(of: pattern) != nil }
                }
                // Najpierw nazwy jednoznaczne; „Book” (Excel 5/95) na końcu — mogłoby wystąpić w treści innych plików.
                if has("WordDocument") { return .doc }
                if has("PowerPoint Document") { return .ppt }
                if has("Workbook") || has("Book") { return .xls }
                return .binary
            }
            if b.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
                // Dokumenty Office Open XML to ZIP — katalog części w nazwach pierwszych wpisów.
                // Nazwy części: nagłówki lokalne na początku i katalog centralny na końcu archiwum (64 KB z każdej strony).
                let head = b.prefix(64 * 1024), tail = b.suffix(64 * 1024)
                func has(_ s: String) -> Bool { head.range(of: Data(s.utf8)) != nil || tail.range(of: Data(s.utf8)) != nil }
                if has("[Content_Types].xml") || has("_rels/") {
                    if has("word/document") { return .docx }
                    if has("xl/workbook") { return .xlsx }
                    if has("ppt/presentation") { return .pptx }
                }
                return .zip
            }
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

extension ResultGridModel {
    /// Ile pełnych treści LOB trzymać w pamięci siatki (panel wartości wraca do nich bez ponownego pobierania).
    static let fullLOBCacheCount = 8

    /// Pełna treść LOB komórki, gdy już pobrana (panel wartości, Large Data Editor).
    public func cachedFullLOB(_ l: LOBValue) -> LOBValue? {
        guard l.truncated else { return l }
        guard let loc = l.locator else { return nil }
        return fullLOBs.last { $0.0 == loc }?.1
    }

    /// Pełna treść obciętego LOB-a z lokatora (bez ROWID — także widoki, złączenia, funkcje), do `limit` jednostek.
    public func fullLOB(_ l: LOBValue, limit: UInt64 = 256 << 20) async throws -> LOBValue {
        if let c = cachedFullLOB(l), !c.truncated || c.length > limit { return c }
        let full = try await session.fullLOB(l, limit: limit)
        if let loc = l.locator {
            fullLOBs.removeAll { $0.0 == loc }
            fullLOBs.append((loc, full))
            if fullLOBs.count > Self.fullLOBCacheCount { fullLOBs.removeFirst(fullLOBs.count - Self.fullLOBCacheCount) }
        }
        return full
    }

    /// Zapis pełnej wartości LOB do pliku porcjami (bez wczytywania całości do pamięci): CLOB w UTF-8, BLOB bez zmian.
    public func writeLOB(_ l: LOBValue, to url: URL) async throws {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.truncate(atOffset: 0)
        if let c = cachedFullLOB(l), !c.truncated {
            try h.write(contentsOf: c.bytes ?? Data((c.text ?? "").utf8))
            return
        }
        try await session.streamLOB(l) { part in
            try h.write(contentsOf: part.bytes ?? Data((part.text ?? "").utf8))
        }
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
    public private(set) var text: String? { didSet { contentVersion &+= 1 } }
    public private(set) var bytes: Data? { didSet { contentVersion &+= 1 } }
    public private(set) var totalLength: UInt64
    public private(set) var truncated: Bool
    public private(set) var format: LargeDataFormat
    public private(set) var isLoading = false
    public var modified = false
    /// Zmienia się przy każdej zmianie treści (dociągnięcie całości, edycja, wczytanie z pliku) — tożsamość treści
    /// dla podglądów bez porównywania dużych danych.
    public private(set) var contentVersion = 0

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

    /// Pełna treść LOB (siatka pobiera do limitu): z lokatora zachowanego przez sterownik, a bez niego (np. wartość
    /// spoza sterownika) — ponowne zapytanie po ROWID; bez obu zostaje obcięta.
    public func loadFull(limit: Int = 256 << 20) async throws {
        guard truncated else { return }
        if case .lob(let l) = grid.value(row: row, column: column), l.locator != nil {
            isLoading = true
            defer { isLoading = false }
            let full = try await grid.fullLOB(l, limit: UInt64(limit))
            guard !modified else { return }
            text = full.text; bytes = full.bytes; totalLength = full.length; truncated = full.truncated
            format = LargeDataFormat.detect(text: text, bytes: bytes)
            return
        }
        guard let rid = grid.rowidColumn, let name = grid.edit.target?.qualifiedName ?? ResultExporter.tableName(fromQuery: grid.sql).map(ResultExporter.qualifiedIdentifier) else { return }
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

    /// Zapis do pliku: zmieniona albo pełna treść z pamięci; obcięty LOB z lokatorem — całość porcjami z bazy.
    public func write(to url: URL) async throws {
        if !modified, truncated, case .lob(let l) = grid.value(row: row, column: column), l.locator != nil {
            try await grid.writeLOB(l, to: url)
        } else {
            try fileData.write(to: url)
        }
    }

    /// Treść karty „Tekst”: tekst kolumny albo bajty BLOB/RAW jako UTF-8; nil, gdy bajty nie są poprawnym UTF-8
    /// (obraz, ZIP) — karta pokazuje wtedy zrzut szesnastkowy tylko do odczytu, bo zapis jego tekstu zastąpiłby
    /// dane binarne (APP2-05).
    public var editableText: String? {
        guard let bytes, text == nil else { return text ?? "" }
        return String(data: bytes, encoding: .utf8)
    }

    /// „Wczytaj z pliku…”: BLOB/RAW — bajty bez zmian; kolumna tekstowa — tekst w wykrytym kodowaniu (BOM, UTF-8,
    /// jednobajtowe jak przy otwieraniu skryptów albo kodowanie projektu), z końcami linii z pliku.
    public func load(file data: Data, preferredEncoding: String.Encoding? = nil) {
        guard !isBinary else { setBytes(data); return }
        let format = TextFileCodec.decode(data, preferred: preferredEncoding).format
        let body = format.hasBOM ? data.dropFirst(format.encoding == .utf8 ? 3 : 2) : data
        setText(String(data: body, encoding: format.encoding) ?? String(decoding: data, as: UTF8.self))
    }

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
