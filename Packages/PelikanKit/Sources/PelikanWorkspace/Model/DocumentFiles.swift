import Foundation

/// Format pliku tekstowego: kodowanie, BOM, zakończenia linii.
public struct TextFileFormat: Sendable, Hashable {
    public enum LineEnding: String, Sendable, Hashable { case lf = "\n", crlf = "\r\n", cr = "\r" }
    public var encoding: String.Encoding = .utf8
    public var hasBOM = false
    public var lineEnding: LineEnding = .lf
    public init() {}

    public var displayName: String {
        let enc: String = switch encoding {
        case .utf8: "UTF-8"
        case .utf16LittleEndian, .utf16BigEndian, .utf16: "UTF-16"
        case .windowsCP1250: "Windows-1250"
        case .isoLatin2: "ISO-8859-2"
        case .windowsCP1252: "Windows-1252"
        default: String.localizedName(of: encoding)
        }
        return enc + (hasBOM ? " BOM" : "") + " · " + (lineEnding == .crlf ? "CRLF" : lineEnding == .cr ? "CR" : "LF")
    }
}

/// Odczyt i zapis plików skryptów (UG 7.13, 25): BOM UTF-8/UTF-16, poprawny UTF-8, inaczej Windows-1250
/// (pliki z PL/SQL Developer na polskim Windows); edytor pracuje na LF, zapis przywraca oryginalne zakończenia.
public enum TextFileCodec {
    public static func decode(_ data: Data) -> (text: String, format: TextFileFormat) {
        var f = TextFileFormat()
        var text: String
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            f.hasBOM = true
            text = String(decoding: data.dropFirst(3), as: UTF8.self)
        } else if data.starts(with: [0xFF, 0xFE]) {
            f.hasBOM = true
            f.encoding = .utf16LittleEndian
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) ?? ""
        } else if data.starts(with: [0xFE, 0xFF]) {
            f.hasBOM = true
            f.encoding = .utf16BigEndian
            text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) ?? ""
        } else if let s = String(data: data, encoding: .utf8) {
            text = s
        } else if let s = String(data: data, encoding: .windowsCP1250) {
            f.encoding = .windowsCP1250
            text = s
        } else {
            f.encoding = .isoLatin1
            text = String(data: data, encoding: .isoLatin1) ?? ""
        }
        if text.contains("\r\n") {
            f.lineEnding = .crlf
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
        } else if text.contains("\r") {
            f.lineEnding = .cr
            text = text.replacingOccurrences(of: "\r", with: "\n")
        }
        return (text, f)
    }

    /// Dane do zapisu; nil — tekst zawiera znaki spoza kodowania pliku (trzeba zapisać jako UTF-8).
    public static func encode(_ text: String, format f: TextFileFormat) -> Data? {
        let t = f.lineEnding == .lf ? text : text.replacingOccurrences(of: "\n", with: f.lineEnding.rawValue)
        guard var data = t.data(using: f.encoding, allowLossyConversion: false) else { return nil }
        if f.hasBOM {
            switch f.encoding {
            case .utf8: data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0)
            case .utf16LittleEndian: data.insert(contentsOf: [0xFF, 0xFE], at: 0)
            case .utf16BigEndian: data.insert(contentsOf: [0xFE, 0xFF], at: 0)
            default: break
            }
        }
        return data
    }
}

extension DocumentKind {
    /// Typ okna dla rozszerzenia pliku (skojarzenia jak we wzorcu: .sql → SQL Window, pliki programów → Program Window,
    /// .tst → Test Window).
    public static func forFile(_ url: URL) -> DocumentKind {
        switch url.pathExtension.lowercased() {
        case "pck", "pks", "pkb", "spc", "bdy", "fnc", "prc", "trg", "typ", "tps", "tpb", "jav", "mle": .program
        case "tst": .test
        default: .sql
        }
    }
}

extension Workspace {
    /// Otwiera plik (już otwarty — aktywuje okno). Typ okna z rozszerzenia albo podany.
    @discardableResult
    public func openFile(_ url: URL, as kind: DocumentKind? = nil) throws -> Document {
        let std = url.standardizedFileURL
        if let open = documents.first(where: { $0.fileURL?.standardizedFileURL == std }) {
            activate(open.id)
            return open
        }
        let data = try Data(contentsOf: std)
        let (text, format) = TextFileCodec.decode(data)
        // Puste, niezmienione okno SQL zastępujemy otwieranym plikiem (jak przy starcie aplikacji).
        if let active = activeDocument, active.fileURL == nil, !active.isModified, active.text.isEmpty, active.kind == (kind ?? DocumentKind.forFile(std)) {
            close(active.id)
        }
        let doc = newDocument(kind ?? DocumentKind.forFile(std), text: text, fileURL: std)
        doc.fileFormat = format
        doc.isModified = false
        rememberRecentFile(std)
        return doc
    }

    /// Zapis dokumentu do pliku (w formacie, w jakim go otwarto; znaki spoza kodowania — UTF-8).
    public func save(_ doc: Document, to url: URL) throws {
        if settings.beautifier.beforeSave { autoBeautify(doc) }
        var format = doc.fileFormat
        var data = TextFileCodec.encode(doc.text, format: format)
        if data == nil {
            format.encoding = .utf8
            format.hasBOM = false
            data = TextFileCodec.encode(doc.text, format: format)
        }
        try data!.write(to: url, options: .atomic)
        doc.fileURL = url.standardizedFileURL
        doc.fileFormat = format
        doc.isModified = false
        rememberRecentFile(url)
    }

    func rememberRecentFile(_ url: URL) {
        var list = settings.recentFiles.filter { $0 != url.path }
        list.insert(url.path, at: 0)
        settings.recentFiles = Array(list.prefix(20))
    }
}
