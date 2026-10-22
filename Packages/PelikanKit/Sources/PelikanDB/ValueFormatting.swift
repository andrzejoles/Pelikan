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
    /// Formatowanie wg podzbioru masek Oracle: YYYY, YY, MM, MON, DD, HH24, HH, MI, SS, FF[1-9], AM/PM, TZH, TZM.
    func formatted(_ mask: String, zone: Bool = false) -> String {
        var out = ""
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
            if take("YYYY") { out += String(format: "%04d", Int(year)) }
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
            else if take("TZH") { out += String(format: "%+03d", tzHourOffset) }
            else if take("TZM") { out += String(format: "%02d", abs(Int(tzMinuteOffset))) }
            else { out.append(mask[i]); i = mask.index(after: i) }
        }
        if zone, !mask.uppercased().contains("TZH") {
            out += String(format: " %+03d:%02d", tzHourOffset, abs(Int(tzMinuteOffset)))
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
