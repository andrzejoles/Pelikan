import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import PelikanDB

/// Zawartość panelu wartości obok siatki (DB-PANEL-001) dla bieżącej komórki: tekst, JSON i XML z wcięciami,
/// HTML do podglądu, obraz z BLOB/RAW, hex dla danych binarnych. Wartość z siatki (LOB-y w pobranej długości).
public struct CellValuePresentation: Sendable, Equatable {
    public enum Mode: String, Sendable, CaseIterable { case text, json, xml, html, image, hex }

    public var column: String
    public var typeName: String
    public var isNull: Bool
    /// Tryb wykryty automatycznie (domyślna karta panelu).
    public var detected: Mode
    /// Dostępne tryby dla wartości.
    public var modes: [Mode]
    public var text: String
    public var data: Data?
    public var truncated: Bool

    public static func make(_ value: OracleValue, column: ColumnInfo, format: ValueFormat) -> CellValuePresentation {
        var text = ""
        var data: Data?
        var truncated = false
        var isNull = false
        switch value {
        case .null: isNull = true
        case .lob(let l):
            text = l.text ?? ""
            data = l.bytes
            truncated = l.truncated
        case .raw(let d): data = d
        default: text = value.format(format)
        }
        let kind = LargeDataFormat.detect(text: data == nil ? text : nil, bytes: data)
        var modes: [Mode] = [.text]
        let detected: Mode
        switch kind {
        case .json: detected = .json
        case .xml: detected = .xml
        case .html: detected = .html
        case .png, .jpeg, .gif: detected = .image
        case .binary, .pdf: detected = .hex
        default: detected = .text
        }
        if detected != .text, !modes.contains(detected) { modes.append(detected) }
        if data != nil, !modes.contains(.hex) { modes.append(.hex) }
        if kind == .html, !modes.contains(.text) { modes.insert(.text, at: 0) }
        if let d = data, text.isEmpty, kind.isText { text = String(decoding: d, as: UTF8.self) }
        return CellValuePresentation(column: column.name, typeName: column.typeName, isNull: isNull, detected: detected, modes: modes,
                                     text: text, data: data, truncated: truncated)
    }

    /// Tekst dla trybu (JSON/XML z wcięciami, hex z offsetami i ASCII).
    public func rendered(_ mode: Mode) -> String {
        if isNull { return "NULL" }
        switch mode {
        case .json: return LargeDataModel.prettyJSON(text) ?? text
        case .xml: return Self.prettyXML(text) ?? text
        case .hex: return LargeDataModel.hexDump(data ?? Data(text.utf8), limit: 64 * 1024)
        case .text, .html, .image: return text
        }
    }

    /// XML z wcięciami (XMLDocument; niepoprawny XML — nil).
    public static func prettyXML(_ s: String) -> String? {
        guard let doc = try? XMLDocument(xmlString: s, options: []) else { return nil }
        return doc.xmlString(options: [.nodePrettyPrint])
    }
}
