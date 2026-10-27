import Foundation
import PelikanDB

/// Dekodowanie surowych formatów Oracle bez utraty precyzji (OracleNIO dekoduje NUMBER przez Double, DATE przez Date).
enum OracleRaw {
    /// NUMBER (format wewnętrzny: bajt wykładnika + cyfry o podstawie 100) → tekst dziesiętny, pełne 38 cyfr.
    static func number(_ b: [UInt8]) -> String? {
        guard let first = b.first else { return nil }
        if first == 0x80, b.count == 1 { return "0" }
        let positive = first & 0x80 != 0
        var digits: [Int] = []
        var exponent: Int
        if positive {
            exponent = Int(first & 0x7F) - 65
            for d in b.dropFirst() { digits.append(Int(d) - 1) }
        } else {
            exponent = Int(~first & 0x7F) - 65
            var body = Array(b.dropFirst())
            if body.last == 102 { body.removeLast() }
            for d in body { digits.append(101 - Int(d)) }
        }
        guard !digits.isEmpty, digits.allSatisfy({ (0...99).contains($0) }) else { return positive ? "0" : nil }
        // Cyfry dziesiętne: każda cyfra o podstawie 100 to dwie cyfry dziesiętne; pozycja przecinka z wykładnika.
        var dec = digits.map { String(format: "%02d", $0) }.joined()
        var pointPos = (exponent + 1) * 2           // liczba cyfr przed przecinkiem
        if pointPos <= 0 {
            dec = String(repeating: "0", count: -pointPos) + dec
            pointPos = 0
        } else if pointPos > dec.count {
            dec += String(repeating: "0", count: pointPos - dec.count)
        }
        var intPart = String(dec.prefix(pointPos))
        var fracPart = String(dec.dropFirst(pointPos))
        while intPart.hasPrefix("0") { intPart.removeFirst() }
        while fracPart.hasSuffix("0") { fracPart.removeLast() }
        if intPart.isEmpty { intPart = "0" }
        let text = fracPart.isEmpty ? intPart : intPart + "." + fracPart
        return (positive || text == "0" ? "" : "-") + text
    }

    /// DATE (7 bajtów) / TIMESTAMP (11) / TIMESTAMP WITH TIME ZONE (13).
    static func timestamp(_ b: [UInt8]) -> OracleTimestamp? {
        guard b.count >= 7 else { return nil }
        let year = (Int(b[0]) - 100) * 100 + Int(b[1]) - 100
        var ns: UInt32 = 0
        if b.count >= 11 { ns = (UInt32(b[7]) << 24) | (UInt32(b[8]) << 16) | (UInt32(b[9]) << 8) | UInt32(b[10]) }
        var tzh: Int8 = 0, tzm: Int8 = 0
        if b.count >= 13, b[11] & 0x80 == 0 {
            tzh = Int8(Int(b[11]) - 20)
            tzm = Int8(Int(b[12]) - 60)
        }
        // Strefa nazwana (bit 0x80: identyfikator regionu z pliku stref Oracle, bez publicznej tablicy nazw) — czas
        // zostaje w UTC i jest tak oznaczony; moment się zgadza, czas lokalny strefy pokaże Instant Client.
        let region: String? = b.count >= 13 && b[11] & 0x80 != 0 ? "UTC" : nil
        var t = OracleTimestamp(year: Int16(year), month: b[2], day: b[3], hour: b[4] &- 1, minute: b[5] &- 1, second: b[6] &- 1,
                                fsecond: ns, tzHourOffset: tzh, tzMinuteOffset: tzm, tzRegion: region)
        // TIMESTAMP WITH TIME ZONE przechowuje czas UTC — czas lokalny strefy = UTC + przesunięcie.
        if b.count >= 13, tzh != 0 || tzm != 0 {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let utc = DateComponents(year: year, month: Int(b[2]), day: Int(b[3]), hour: Int(t.hour), minute: Int(t.minute), second: Int(t.second))
            if let d = cal.date(from: utc) {
                let local = cal.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                               from: d.addingTimeInterval(TimeInterval(Int(tzh) * 3600 + Int(tzm) * 60)))
                t = OracleTimestamp(year: Int16(local.year!), month: UInt8(local.month!), day: UInt8(local.day!), hour: UInt8(local.hour!),
                                    minute: UInt8(local.minute!), second: UInt8(local.second!), fsecond: ns, tzHourOffset: tzh, tzMinuteOffset: tzm)
            }
        }
        return t
    }
}
