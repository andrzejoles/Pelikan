import Foundation

/// Formaty wyświetlania wartości w siatce i eksporcie (odpowiednik ustawień NLS / Preferences → Date/Time).
public struct ValueFormat: Sendable, Hashable {
    /// Wzorzec dla DATE (jak NLS_DATE_FORMAT; obsługiwane: YYYY MM DD HH24 MI SS).
    public var dateFormat: String
    public var timestampFormat: String
    public var nullText: String
    public var decimalSeparator: Character

    public init(dateFormat: String = "YYYY-MM-DD HH24:MI:SS", timestampFormat: String = "YYYY-MM-DD HH24:MI:SS.FF",
                nullText: String = "", decimalSeparator: Character = ".") {
        self.dateFormat = dateFormat; self.timestampFormat = timestampFormat
        self.nullText = nullText; self.decimalSeparator = decimalSeparator
    }

    public static let `default` = ValueFormat()
}

public extension OracleValue {
    /// Tekst do wyświetlenia (siatka, eksport, Code Assistant) w domyślnym formacie.
    var displayText: String? { isNull ? nil : format(.default) }

    func format(_ f: ValueFormat) -> String {
        switch self {
        case .null: return f.nullText
        case .text(let s): return s
        case .number(let s):
            return f.decimalSeparator == "." ? s : s.replacingOccurrences(of: ".", with: String(f.decimalSeparator))
        case .double(let d):
            if d.isNaN { return "Nan" }
            if d.isInfinite { return d > 0 ? "Inf" : "-Inf" }
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return String(d)
        case .boolean(let b): return b ? "TRUE" : "FALSE"
        case .timestamp(let t, let type):
            return type == .date ? t.formatted(f.dateFormat) : t.formatted(f.timestampFormat, zone: type == .timestampTZ)
        case let .intervalDS(d, h, m, s, fs):
            let sign = (d < 0 || h < 0 || m < 0 || s < 0 || fs < 0) ? "-" : "+"
            return String(format: "%@%02d %02d:%02d:%02d.%06d", sign, abs(d), abs(h), abs(m), abs(s), abs(fs) / 1000)
        case let .intervalYM(y, m):
            let sign = (y < 0 || m < 0) ? "-" : "+"
            return "\(sign)\(String(format: "%02d", abs(y)))-\(String(format: "%02d", abs(m)))"
        case .raw(let d): return d.hexUpper
        case .lob(let l):
            if let e = l.readError { return "<\(l.kind.rawValue)> " + e }
            if let t = l.text { return t }
            if let b = l.bytes { return "<\(l.kind.rawValue) \(l.length) B> " + b.prefix(32).hexUpper }
            return "<\(l.kind.rawValue)>"
        case .rowid(let r): return r
        case .json(let j): return j
        case .vector(let v): return "[" + v.map { String($0) }.joined(separator: ",") + "]"
        case .object(let t, let d): return d.isEmpty ? "<\(t)>" : d
        case .cursor: return "<Cursor>"
        }
    }
}

public extension OracleTimestamp {
    /// Formatowanie wg podzbioru masek Oracle: YYYY, YY, MM, MON, DD, HH24, HH, MI, SS, FF[1-9], AM/PM, TZH, TZM;
    /// tekst w cudzysłowie (`"T"`, `"de"`) to literał bez cudzysłowów — jak w Oracle.
    func formatted(_ mask: String, zone: Bool = false) -> String {
        var out = ""
        // Przesunięcie strefy w minutach — znak z całości (-00:30: TZH = 0, TZM = -30).
        let offset = Int(tzHourOffset) * 60 + Int(tzMinuteOffset)
        let sign = offset < 0 ? "-" : "+"
        var i = mask.startIndex
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        func take(_ token: String) -> Bool {
            if mask[i...].uppercased().hasPrefix(token) {
                i = mask.index(i, offsetBy: token.count)
                return true
            }
            return false
        }
        while i < mask.endIndex {
            if mask[i] == "\"" {
                let from = mask.index(after: i)
                let to = mask[from...].firstIndex(of: "\"") ?? mask.endIndex
                out += mask[from..<to]
                i = to < mask.endIndex ? mask.index(after: to) : to
            }
            else if take("YYYY") { out += String(format: "%04d", Int(year)) }
            else if take("YY") { out += String(format: "%02d", Int(year) % 100) }
            else if take("MON") { out += months[max(0, min(11, Int(month) - 1))] }
            else if take("MM") { out += String(format: "%02d", month) }
            else if take("DD") { out += String(format: "%02d", day) }
            else if take("HH24") { out += String(format: "%02d", hour) }
            else if take("HH12") || take("HH") { out += String(format: "%02d", hour % 12 == 0 ? 12 : hour % 12) }
            else if take("MI") { out += String(format: "%02d", minute) }
            else if take("SS") { out += String(format: "%02d", second) }
            else if take("FF") {
                var digits = 6
                if i < mask.endIndex, let d = mask[i].wholeNumberValue, d >= 1 { digits = d; i = mask.index(after: i) }
                let ns = String(format: "%09d", fsecond)
                out += String(ns.prefix(digits))
            }
            else if take("AM") || take("PM") { out += hour < 12 ? "AM" : "PM" }
            else if take("TZH") { out += sign + String(format: "%02d", abs(offset) / 60) }
            else if take("TZM") { out += String(format: "%02d", abs(offset) % 60) }
            else { out.append(mask[i]); i = mask.index(after: i) }
        }
        if zone, !mask.uppercased().contains("TZH") {
            out += tzRegion.map { " " + $0 } ?? " " + sign + String(format: "%02d:%02d", abs(offset) / 60, abs(offset) % 60)
        }
        return out
    }
}

public extension Data {
    var hexUpper: String {
        let digits = Array("0123456789ABCDEF".utf8)
        var out = [UInt8]()
        out.reserveCapacity(count * 2)
        for b in self {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0xF)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}

public extension OracleTimestamp {
    /// Odczyt tekstu wg podzbioru masek Oracle (jak `formatted`): YYYY, YY, MM, MON, DD, HH24, HH/HH12, MI, SS, FF[1-9], AM/PM.
    /// Separatory w masce dopasowują dowolny pojedynczy znak niebędący cyfrą, literał `"…"` — te same znaki; brakujący koniec tekstu (np. sama data
    /// przy masce z czasem) daje zera.
    static func parse(_ text: String, mask: String) -> OracleTimestamp? {
        let s = Array(text.trimmingCharacters(in: .whitespaces))
        let m = Array(mask.uppercased())
        var si = 0, mi = 0
        var y = 0, mo = 1, d = 1, h = 0, mi2 = 0, sec = 0, ns = 0, pm: Bool?
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        func number(maxDigits: Int) -> Int? {
            var v = 0, n = 0
            while si < s.count, n < maxDigits, let dgt = s[si].wholeNumberValue { v = v * 10 + dgt; si += 1; n += 1 }
            return n == 0 ? nil : v
        }
        func take(_ token: String) -> Bool {
            let t = Array(token)
            guard mi + t.count <= m.count, Array(m[mi..<(mi + t.count)]) == t else { return false }
            mi += t.count
            return true
        }
        while mi < m.count {
            if si >= s.count { break }    // reszta maski bez tekstu — wartości domyślne
            if m[mi] == "\"" {
                // Literał w cudzysłowie: te same znaki w tekście (bez względu na wielkość liter).
                let end = m[(mi + 1)...].firstIndex(of: "\"") ?? m.count
                for c in m[(mi + 1)..<end] {
                    guard si < s.count, String(s[si]).uppercased() == String(c) else { return nil }
                    si += 1
                }
                mi = min(end + 1, m.count)
            }
            else if take("YYYY") { guard let v = number(maxDigits: 4) else { return nil }; y = v }
            else if take("YY") { guard let v = number(maxDigits: 2) else { return nil }; y = 2000 + v }
            else if take("MON") {
                guard si + 3 <= s.count, let i = months.firstIndex(of: String(s[si..<(si + 3)]).uppercased()) else { return nil }
                mo = i + 1; si += 3
            }
            else if take("MM") { guard let v = number(maxDigits: 2) else { return nil }; mo = v }
            else if take("DD") { guard let v = number(maxDigits: 2) else { return nil }; d = v }
            else if take("HH24") { guard let v = number(maxDigits: 2) else { return nil }; h = v }
            else if take("HH12") || take("HH") { guard let v = number(maxDigits: 2) else { return nil }; h = v % 12 }
            else if take("MI") { guard let v = number(maxDigits: 2) else { return nil }; mi2 = v }
            else if take("SS") { guard let v = number(maxDigits: 2) else { return nil }; sec = v }
            else if take("FF") {
                var digits = 9
                if mi < m.count, let dgt = m[mi].wholeNumberValue { digits = dgt; mi += 1 }
                let start = si
                guard let v = number(maxDigits: max(1, digits)) else { return nil }
                ns = v * Int(pow(10.0, Double(9 - (si - start))))
            }
            else if take("AM") || take("PM") {
                guard si + 2 <= s.count else { return nil }
                pm = String(s[si..<(si + 2)]).uppercased() == "PM"; si += 2
            }
            else if take("TZH") || take("TZM") { _ = number(maxDigits: 2) }
            else {
                // Separator maski: w tekście dowolny znak niebędący cyfrą (albo ten sam znak).
                if s[si].isNumber && s[si] != m[mi] { return nil }
                si += 1; mi += 1
            }
        }
        if si < s.count { return nil }
        if pm == true { h += 12 }
        guard (1...12).contains(mo), (1...31).contains(d), h < 24, mi2 < 60, sec < 60, y > 0 else { return nil }
        return OracleTimestamp(year: Int16(y), month: UInt8(mo), day: UInt8(d), hour: UInt8(h), minute: UInt8(mi2), second: UInt8(sec), fsecond: UInt32(ns))
    }
}
