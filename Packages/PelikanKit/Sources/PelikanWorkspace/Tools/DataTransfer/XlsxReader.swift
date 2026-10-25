import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Odczyt archiwum ZIP (wpisy „stored” i „deflate”) bez bibliotek zewnętrznych — dla plików xlsx (PD-TOOL-009).
public struct ZipReader {
    public enum Failure: Error, LocalizedError {
        case notZip, unsupported(String), corrupted(String)
        public var errorDescription: String? {
            switch self {
            case .notZip: L10n.tr("To nie jest plik ZIP/xlsx")
            case .unsupported(let n): L10n.tr("Nieobsługiwana kompresja wpisu \(n)")
            case .corrupted(let n): L10n.tr("Uszkodzony wpis \(n)")
            }
        }
    }

    struct Entry { var name: String; var method: UInt16; var compressedSize: Int; var size: Int; var localOffset: Int }

    let data: Data
    let entries: [String: Entry]

    public init(_ data: Data) throws {
        self.data = data
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        // Koniec katalogu centralnego: sygnatura 0x06054b50 w ostatnich 64 KiB.
        guard bytes.count >= 22 else { throw Failure.notZip }
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 65_557) {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.notZip }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var map: [String: Entry] = [:]
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else { throw Failure.notZip }
            let method = UInt16(u16(p + 10))
            let csize = u32(p + 20), size = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let offset = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            map[name] = Entry(name: name, method: method, compressedSize: csize, size: size, localOffset: offset)
            p += 46 + nlen + elen + clen
        }
        entries = map
    }

    public var names: [String] { entries.keys.sorted() }

    public func read(_ name: String) throws -> Data {
        guard let e = entries[name] else { throw Failure.corrupted(name) }
        let bytes = [UInt8](data)
        let lo = e.localOffset
        guard lo + 30 <= bytes.count else { throw Failure.corrupted(name) }
        let nlen = Int(bytes[lo + 26]) | Int(bytes[lo + 27]) << 8
        let elen = Int(bytes[lo + 28]) | Int(bytes[lo + 29]) << 8
        let start = lo + 30 + nlen + elen
        guard start + e.compressedSize <= bytes.count else { throw Failure.corrupted(name) }
        let raw = Data(bytes[start..<(start + e.compressedSize)])
        switch e.method {
        case 0: return raw
        case 8:
            #if canImport(Darwin)
            // Algorytm .zlib frameworku Compression to surowy DEFLATE (RFC 1951) — taki jak w ZIP.
            guard let out = try? (raw as NSData).decompressed(using: .zlib) as Data else { throw Failure.corrupted(name) }
            return out
            #else
            throw Failure.unsupported(name)
            #endif
        default: throw Failure.unsupported(name)
        }
    }
}

/// Skoroszyt xlsx: arkusze i komórki jako tekst (liczby w zapisie z pliku, wartości logiczne 0/1).
public struct XlsxWorkbook {
    public struct Sheet: Sendable, Hashable { public var name: String; public var path: String }
    public let sheets: [Sheet]
    let zip: ZipReader
    let sharedStrings: [String]

    public init(_ data: Data) throws {
        zip = try ZipReader(data)
        sharedStrings = (try? zip.read("xl/sharedStrings.xml")).map(Self.parseSharedStrings) ?? []
        let rels = (try? zip.read("xl/_rels/workbook.xml.rels")).map(Self.parseRelationships) ?? [:]
        let wb = try zip.read("xl/workbook.xml")
        sheets = Self.parseSheets(wb).map { name, rid in
            var target = rels[rid] ?? ""
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            return Sheet(name: name, path: target)
        }
    }

    /// Wiersze arkusza (indeks od 0): kolumny według adresów komórek, puste uzupełnione "".
    public func rows(sheet: Int) throws -> [[String]] {
        guard sheets.indices.contains(sheet) else { return [] }
        let d = SheetParser(shared: sharedStrings)
        let p = XMLParser(data: try zip.read(sheets[sheet].path))
        p.delegate = d
        _ = p.parse()
        guard let maxRow = d.cells.keys.map(\.row).max() else { return [] }
        let maxCol = d.cells.keys.map(\.col).max() ?? 0
        var out = Array(repeating: Array(repeating: "", count: maxCol + 1), count: maxRow + 1)
        for (k, v) in d.cells { out[k.row][k.col] = v }
        return out
    }

    /// Indeks kolumny z adresu komórki („AB12” → wiersz 11, kolumna 27).
    static func cellIndex(_ ref: String) -> (row: Int, col: Int)? {
        var col = 0
        var digits = ""
        for ch in ref.uppercased() {
            if let a = ch.asciiValue, a >= 65, a <= 90, digits.isEmpty { col = col * 26 + Int(a - 64) } else if ch.isNumber { digits.append(ch) }
        }
        guard col > 0, let r = Int(digits) else { return nil }
        return (r - 1, col - 1)
    }

    static func parseSharedStrings(_ data: Data) -> [String] {
        final class D: NSObject, XMLParserDelegate {
            var items: [String] = []
            var current = ""
            var inT = false, inSI = false, inRPh = false
            func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
                switch n {
                case "si": inSI = true; current = ""
                case "t": inT = true
                case "rPh": inRPh = true
                default: break
                }
            }
            func parser(_ p: XMLParser, foundCharacters s: String) { if inSI, inT, !inRPh { current += s } }
            func parser(_ p: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
                switch n {
                case "si": items.append(current); inSI = false
                case "t": inT = false
                case "rPh": inRPh = false
                default: break
                }
            }
        }
        let d = D()
        let p = XMLParser(data: data)
        p.delegate = d
        _ = p.parse()
        return d.items
    }

    static func parseRelationships(_ data: Data) -> [String: String] {
        final class D: NSObject, XMLParserDelegate {
            var map: [String: String] = [:]
            func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
                if n == "Relationship", let id = a["Id"], let t = a["Target"] { map[id] = t }
            }
        }
        let d = D()
        let p = XMLParser(data: data)
        p.delegate = d
        _ = p.parse()
        return d.map
    }

    static func parseSheets(_ data: Data) -> [(String, String)] {
        final class D: NSObject, XMLParserDelegate {
            var sheets: [(String, String)] = []
            func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
                if n == "sheet", let name = a["name"] { sheets.append((name, a["r:id"] ?? a.first { $0.key.hasSuffix(":id") }?.value ?? "")) }
            }
        }
        let d = D()
        let p = XMLParser(data: data)
        p.delegate = d
        _ = p.parse()
        return d.sheets
    }

    final class SheetParser: NSObject, XMLParserDelegate {
        struct Key: Hashable { var row: Int; var col: Int }
        let shared: [String]
        var cells: [Key: String] = [:]
        var ref: (row: Int, col: Int)?
        var type = ""
        var text = ""
        var capture = false
        var nextCol = 0
        var currentRow = -1

        init(shared: [String]) { self.shared = shared }

        func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            switch n {
            case "row":
                currentRow = (a["r"].flatMap(Int.init) ?? currentRow + 2) - 1
                nextCol = 0
            case "c":
                ref = a["r"].flatMap(XlsxWorkbook.cellIndex) ?? (currentRow, nextCol)
                type = a["t"] ?? "n"
                text = ""
            case "v", "t": capture = true
            default: break
            }
        }

        func parser(_ p: XMLParser, foundCharacters s: String) { if capture { text += s } }

        func parser(_ p: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
            switch n {
            case "v", "t": capture = false
            case "c":
                guard let r = ref else { return }
                let value = type == "s" ? (Int(text).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "") : text
                if !value.isEmpty { cells[Key(row: r.row, col: r.col)] = value }
                nextCol = r.col + 1
                ref = nil
            default: break
            }
        }
    }
}
