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
        } else if let enc = guessSingleByte(data), let s = String(data: data, encoding: enc) {
            f.encoding = enc
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

    /// Kodowanie jednobajtowe pliku bez BOM i spoza UTF-8: bajty 0x80–0x9F to znaki Windows-1250 (w ISO-8859-2 są
    /// tam znaki sterujące); polskie litery na pozycjach ISO-8859-2 (ą ś ź Ą Ś Ź = B1 B6 BC A1 A6 AC) bez 0x80–0x9F →
    /// ISO-8859-2 (pliki z AIX/Unix); w innym razie Windows-1250 (pliki z PL/SQL Developer).
    public static func guessSingleByte(_ data: Data) -> String.Encoding? {
        var c1 = false, latin2 = false
        for b in data {
            if (0x80...0x9F).contains(b) { c1 = true; break }
            if [0xB1, 0xB6, 0xBC, 0xA1, 0xA6, 0xAC].contains(b) { latin2 = true }
        }
        return c1 ? .windowsCP1250 : latin2 ? .isoLatin2 : .windowsCP1250
    }

    /// Kodowania wybieralne dla plików i projektów.
    public static let encodingNames = ["UTF-8", "ISO-8859-2", "Windows-1250"]

    public static func encoding(named name: String) -> String.Encoding? {
        switch name.uppercased() {
        case "UTF-8", "UTF8": .utf8
        case "ISO-8859-2", "LATIN2", "ISO8859-2": .isoLatin2
        case "WINDOWS-1250", "CP1250": .windowsCP1250
        default: nil
        }
    }

    /// Kodowanie istniejących plików: pierwszy plik spoza UTF-8 rozstrzyga (ISO-8859-2 albo Windows-1250), inaczej UTF-8.
    public static func detectEncoding(of files: [URL]) -> String {
        for f in files {
            guard let d = try? Data(contentsOf: f), String(data: d, encoding: .utf8) == nil else { continue }
            return guessSingleByte(d) == .isoLatin2 ? "ISO-8859-2" : "Windows-1250"
        }
        return "UTF-8"
    }

    /// Pierwszy znak, którego nie da się zapisać w kodowaniu: linia i kolumna (od 1) oraz znak.
    public static func firstUnencodable(_ text: String, encoding: String.Encoding) -> (line: Int, column: Int, character: Character)? {
        var line = 1, column = 1
        for ch in text {
            if ch == "\n" { line += 1; column = 1; continue }
            if String(ch).data(using: encoding, allowLossyConversion: false) == nil { return (line, column, ch) }
            column += 1
        }
        return nil
    }

    /// Dane do zapisu; nil — tekst zawiera znaki spoza kodowania pliku.
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

/// Błąd zapisu pliku tekstowego.
public enum TextFileError: Error, LocalizedError, Equatable {
    case unencodable(line: Int, column: Int, character: String, encoding: String)

    public var errorDescription: String? {
        switch self {
        case let .unencodable(line, column, character, encoding):
            L10n.tr("Znak „\(character)” (linia \(line), kolumna \(column)) nie istnieje w kodowaniu \(encoding) — zapis zablokowany. Zmień znak albo jawnie zmień kodowanie pliku (Plik › Kodowanie pliku).")
        }
    }
}

extension DocumentKind {
    /// Typ okna dla rozszerzenia pliku (skojarzenia jak we wzorcu: .sql → SQL Window, pliki programów → Program Window,
    /// .tst → Test Window).
    public static func forFile(_ url: URL) -> DocumentKind {
        switch url.pathExtension.lowercased() {
        case "pck", "pks", "pkb", "spc", "bdy", "fnc", "prc", "trg", "typ", "tps", "tpb", "jav", "mle": .program
        case "tst": .test
        case "pdd": .diagram
        case "rep": .report
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
        var (text, format) = TextFileCodec.decode(data)
        // Plik projektu bez BOM: kodowanie ustawione w projekcie (np. ISO-8859-2 dla źródeł Pro*C z AIX), żeby nie
        // przekodował się po cichu przy pierwszej edycji (D55).
        if let enc = projectEncoding(for: std), !format.hasBOM, enc != format.encoding, let s = String(data: data, encoding: enc) {
            format.encoding = enc
            text = format.lineEnding == .lf ? s : s.replacingOccurrences(of: format.lineEnding.rawValue, with: "\n")
        }
        // Puste, niezmienione okno SQL zastępujemy otwieranym plikiem (jak przy starcie aplikacji).
        if let active = activeDocument, active.fileURL == nil, !active.isModified, active.text.isEmpty, active.kind == (kind ?? DocumentKind.forFile(std)) {
            close(active.id)
        }
        let docKind = kind ?? DocumentKind.forFile(std)
        let doc: Document
        if docKind == .report {
            // Raport Pelikana: definicja JSON z zapytaniem (PD-REP-004).
            let def = try ReportDefinition.decode(data)
            doc = newDocument(.report, text: def.sql, fileURL: std)
            doc.report = def
        } else if docKind == .diagram {
            // Diagram Pelikana: JSON (PD-DIAG-003).
            doc = newDocument(.diagram, fileURL: std)
            doc.diagram = try Diagram.decode(data)
        } else if docKind == .test {
            // .tst Pelikana: blok i zmienne (UG 5.4).
            let f = TestScriptFile.decode(text)
            doc = newDocument(.test, text: f.block, fileURL: std)
            doc.testVariables = f.variables
            TestRunner.synchronize(doc)
        } else {
            doc = newDocument(docKind, text: text, fileURL: std)
        }
        doc.fileFormat = format
        doc.isModified = false
        rememberRecentFile(std)
        return doc
    }

    /// Kodowanie z opcji otwartego projektu dla pliku w jego katalogu (albo nil).
    func projectEncoding(for url: URL) -> String.Encoding? {
        guard let p = project, let pu = projectURL, let name = p.options.encoding, let enc = TextFileCodec.encoding(named: name) else { return nil }
        let base = pu.deletingLastPathComponent().standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(base) ? enc : nil
    }

    /// Zapis dokumentu do pliku (w formacie, w jakim go otwarto; znaki spoza kodowania — UTF-8).
    public func save(_ doc: Document, to url: URL) throws {
        if settings.beautifier.beforeSave { autoBeautify(doc) }
        // Plik okna programu zgodny z SQL*Plus: ostatnia jednostka zakończona „/” (UG 4.2).
        if doc.kind == .program, !ProgramCompiler.units(in: doc.text).isEmpty,
           doc.text.trimmingCharacters(in: .whitespacesAndNewlines).last != "/" {
            doc.text = doc.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n/\n"
        }
        let format = doc.fileFormat
        if doc.kind == .report {
            var def = doc.report
            def.sql = doc.text
            try def.encoded().write(to: url, options: .atomic)
            doc.fileURL = url.standardizedFileURL
            doc.isModified = false
            rememberRecentFile(url)
            return
        }
        if doc.kind == .diagram {
            try doc.diagram.encoded().write(to: url, options: .atomic)
            doc.fileURL = url.standardizedFileURL
            doc.isModified = false
            rememberRecentFile(url)
            return
        }
        if doc.kind == .test, url.pathExtension.lowercased() == "tst" {
            try TestScriptFile(block: doc.text, variables: doc.testVariables).encoded().write(to: url, options: .atomic)
            doc.fileURL = url.standardizedFileURL
            doc.isModified = false
            rememberRecentFile(url)
            return
        }
        // Plik nie zmienia po cichu kodowania (np. ISO-8859-2 → UTF-8): znak spoza kodowania blokuje zapis z dokładnym
        // miejscem (Pro*C, D55); zmiana kodowania tylko jawnie (Plik › Kodowanie pliku).
        guard let data = TextFileCodec.encode(doc.text, format: format) else {
            let bad = TextFileCodec.firstUnencodable(doc.text, encoding: format.encoding)
            throw TextFileError.unencodable(line: bad?.line ?? 0, column: bad?.column ?? 0, character: bad.map { String($0.character) } ?? "?",
                                            encoding: format.displayName.components(separatedBy: " ").first ?? "")
        }
        try data.write(to: url, options: .atomic)
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
