// Pochodzi z BiFold (Remote/SSH.swift @ a1ee643), dalej rozwijany w Pelikanie.
import Foundation

/// Kodowanie nazw i tekstu poleceń na serwerze (AIX z polską lokalizacją często używa ISO-8859-2).
public enum NameEncoding: String, Codable, Sendable, CaseIterable {
    case utf8 = "utf-8"
    case latin2 = "iso-8859-2"

    public var displayName: String { self == .utf8 ? "UTF-8" : "ISO-8859-2 (Latin-2)" }

    public var encoding: String.Encoding { self == .utf8 ? .utf8 : .isoLatin2 }

    public func encode(_ s: String) throws -> [UInt8] {
        let normalized = s.precomposedStringWithCanonicalMapping
        guard let data = normalized.data(using: encoding) else { throw SSHError.unencodable(s) }
        return Array(data)
    }

    public func decode(_ data: Data) -> String {
        String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
    }
}

/// Dekoder tekstu strumienia w porcjach: znak UTF-8 rozcięty między porcjami czeka w buforze resztek na resztę
/// bajtów; opcjonalnie `\r\n` → `\n` (wyjście z pty), także gdy `\r` kończy porcję.
public struct StreamTextDecoder: Sendable {
    public let encoding: NameEncoding
    public let normalizeNewlines: Bool
    private var pending = Data()
    private var pendingCR = false

    public init(encoding: NameEncoding, normalizeNewlines: Bool = false) {
        self.encoding = encoding
        self.normalizeNewlines = normalizeNewlines
    }

    /// Długość najdłuższego prefiksu, który kończy się na granicy znaku UTF-8.
    static func completeUTF8Prefix(_ bytes: [UInt8]) -> Int {
        var i = bytes.count
        var back = 0
        while i > 0, back < 4 {
            let b = bytes[i - 1]
            if b & 0xC0 == 0x80 { i -= 1; back += 1; continue }
            // Bajt początkowy: ile bajtów wymaga znak?
            let need = b & 0x80 == 0 ? 1 : b & 0xE0 == 0xC0 ? 2 : b & 0xF0 == 0xE0 ? 3 : b & 0xF8 == 0xF0 ? 4 : 1
            return back + 1 >= need ? bytes.count : i - 1
        }
        return bytes.count
    }

    public mutating func decode(_ data: Data) -> String {
        pending.append(data)
        let bytes = [UInt8](pending)
        let n = encoding == .utf8 ? Self.completeUTF8Prefix(bytes) : bytes.count
        let text = encoding.decode(Data(bytes[0..<n]))
        pending = Data(bytes[n...])
        return normalize(text)
    }

    /// Reszta bufora na końcu strumienia (niepełny znak — jak `String(decoding:)`, z U+FFFD).
    public mutating func finish() -> String {
        var text = pending.isEmpty ? "" : encoding.decode(pending)
        pending = Data()
        if pendingCR { text = "\r" + text; pendingCR = false }
        return text
    }

    private mutating func normalize(_ text: String) -> String {
        guard normalizeNewlines else { return text }
        var t = pendingCR ? "\r" + text : text
        pendingCR = false
        if t.hasSuffix("\r") {
            pendingCR = true
            t.removeLast()
        }
        return t.replacingOccurrences(of: "\r\n", with: "\n")
    }
}
