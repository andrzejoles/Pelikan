import Foundation

/// Identyfikator zapytania Oracle (D217): SQL_ID (13 znaków base32) i HASH_VALUE (32 bity). SQL_ID to dolne 64 bity
/// skrótu MD5 tekstu polecenia z bajtem zerowym na końcu; HASH_VALUE — jego dolne 32 bity
/// (jak DBMS_UTILITY.SQLID_TO_SQLHASH). Z SQL_ID hash liczy się lokalnie; z hasha SQL_ID — tylko odczytem z bazy.
public enum SQLIdentity {
    static let alphabet = Array("0123456789abcdfghjkmnpqrstuvwxyz")

    /// Czy tekst wygląda jak SQL_ID (13 znaków alfabetu base32 Oracle, małe litery).
    public static func isSQLID(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count == 13 && t.allSatisfy { alphabet.contains($0) } && t.contains { $0.isLetter }
    }

    /// Czy tekst wygląda jak HASH_VALUE (liczba 1…4294967295).
    public static func isHashValue(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count <= 10, let v = UInt64(t) else { return false }
        return v > 0 && v <= UInt64(UInt32.max)
    }

    /// Wartość 64-bitowa SQL_ID.
    static func value(_ sqlID: String) -> UInt64? {
        guard isSQLID(sqlID) else { return nil }
        var v: UInt64 = 0
        for c in sqlID.trimmingCharacters(in: .whitespaces) {
            guard let i = alphabet.firstIndex(of: c) else { return nil }
            v = v << 5 | UInt64(i)
        }
        return v
    }

    /// HASH_VALUE z SQL_ID (dolne 32 bity).
    public static func hashValue(sqlID: String) -> UInt32? { value(sqlID).map { UInt32(truncatingIfNeeded: $0) } }

    /// SQL_ID z wartości 64-bitowej.
    static func sqlID(_ v: UInt64) -> String {
        var out = ""
        var x = v
        for _ in 0..<13 {
            out = String(alphabet[Int(x & 31)]) + out
            x >>= 5
        }
        return out
    }

    /// SQL_ID tekstu polecenia dokładnie w postaci wysłanej do bazy.
    public static func sqlID(text: String) -> String {
        var bytes = Array(text.utf8)
        bytes.append(0)
        let d = MD5.digest(bytes)
        func le32(_ i: Int) -> UInt64 { UInt64(d[i]) | UInt64(d[i + 1]) << 8 | UInt64(d[i + 2]) << 16 | UInt64(d[i + 3]) << 24 }
        return sqlID(le32(8) << 32 | le32(12))
    }

    /// Wartość z komórki albo słowa: SQL_ID (małe litery) albo hash; nil — nic rozpoznawalnego.
    public static func parse(_ raw: String) -> Target? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        if isSQLID(t.lowercased()), t == t.lowercased() || t == t.uppercased() { return .sqlID(t.lowercased()) }
        if isHashValue(t) { return .hash(UInt32(t)!) }
        return nil
    }

    /// Co wskazano: SQL_ID albo sam hash (SQL_ID do ustalenia z bazy).
    public enum Target: Sendable, Hashable {
        case sqlID(String)
        case hash(UInt32)
    }

    /// Kolumny, których wartości to SQL_ID albo hash zapytania (nazwy z widoków V$/DBA_HIST i typowe aliasy).
    public static func columnKind(_ name: String) -> ColumnKind? {
        let n = name.uppercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        if n == "SQL_ID" || n.hasSuffix("_SQL_ID") || n.hasPrefix("SQL_ID_") || n == "SQLID" || n == "KEY1_SQL_ID" { return .sqlID }
        if ["HASH_VALUE", "SQL_HASH_VALUE", "PREV_HASH_VALUE", "OLD_HASH_VALUE", "SQL_HASH", "SQLHASH"].contains(n) { return .hash }
        return nil
    }

    public enum ColumnKind: Sendable { case sqlID, hash }

    /// Cel z wiersza: pierwsza kolumna SQL_ID z wartością, inaczej pierwsza kolumna hasha.
    public static func target(columns: [String], values: [String]) -> Target? {
        var hash: Target?
        for (i, c) in columns.enumerated() where i < values.count {
            switch columnKind(c) {
            case .sqlID?: if let t = parse(values[i]), case .sqlID = t { return t }
            case .hash?: if hash == nil, let t = parse(values[i]), case .hash = t { hash = t }
            case nil: break
            }
        }
        return hash
    }
}

/// MD5 (RFC 1321) — tylko do SQL_ID; bez zależności (CryptoKit nie ma na Linuksie).
enum MD5 {
    static let s: [UInt32] = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
                              5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
                              4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
                              6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21]
    static let k: [UInt32] = (0..<64).map { UInt32(truncatingIfNeeded: Int64(abs(sin(Double($0 + 1))) * 4294967296.0)) }

    static func digest(_ message: [UInt8]) -> [UInt8] {
        var m = message
        let bitLength = UInt64(message.count) * 8
        m.append(0x80)
        while m.count % 64 != 56 { m.append(0) }
        for i in 0..<8 { m.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(i)))) }
        var a0: UInt32 = 0x67452301, b0: UInt32 = 0xefcdab89, c0: UInt32 = 0x98badcfe, d0: UInt32 = 0x10325476
        for chunk in stride(from: 0, to: m.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(m[j]) | UInt32(m[j + 1]) << 8 | UInt32(m[j + 2]) << 16 | UInt32(m[j + 3]) << 24
            }
            var a = a0, b = b0, c = c0, d = d0
            for i in 0..<64 {
                var f: UInt32
                let g: Int
                switch i {
                case 0..<16: f = (b & c) | (~b & d); g = i
                case 16..<32: f = (d & b) | (~d & c); g = (5 * i + 1) % 16
                case 32..<48: f = b ^ c ^ d; g = (3 * i + 5) % 16
                default: f = c ^ (b | ~d); g = (7 * i) % 16
                }
                f = f &+ a &+ k[i] &+ w[g]
                a = d; d = c; c = b
                b = b &+ (f << s[i] | f >> (32 - s[i]))
            }
            a0 = a0 &+ a; b0 = b0 &+ b; c0 = c0 &+ c; d0 = d0 &+ d
        }
        var out: [UInt8] = []
        for v in [a0, b0, c0, d0] { for i in 0..<4 { out.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) } }
        return out
    }
}
