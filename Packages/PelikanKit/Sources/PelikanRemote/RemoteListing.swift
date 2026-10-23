// Pochodzi z BiFold (Remote/ScpFS.swift @ a1ee643), dalej rozwijany w Pelikanie.
import Foundation

/// Wpis katalogu na serwerze z wyjścia `ls -la`.
public struct RemoteFileEntry: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case file, directory, symlink, other }
    public var name: String
    public var kind: Kind
    /// Rozmiar w bajtach (katalogi: -1, urządzenia: 0).
    public var size: Int64
    public var modified: Date?
    public var permissions: UInt16
    /// Cel dowiązania (`nazwa -> cel`).
    public var linkTarget: String?
}

public enum RemoteListing {
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// `ls -la` w lokalizacji C (AIX, Linux, BSD): typ i prawa, liczba dowiązań, właściciel, grupa,
    /// rozmiar (albo „główny, poboczny” dla urządzeń), data „Mon DD HH:MM” lub „Mon DD  YYYY”, nazwa.
    public static func parse(_ text: String, now: Date = Date(), keepDots: Bool = false, timeZone: TimeZone = .current) -> [RemoteFileEntry] {
        var out: [RemoteFileEntry] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let currentYear = calendar.component(.year, from: now)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            guard let first = line.first, "-dlcbps".contains(first), !line.hasPrefix("total ") else { continue }
            // Słowa z zakresami (nazwa zaczyna się po trzecim polu daty).
            var words: [(String, Range<String.Index>)] = []
            var i = line.startIndex
            while i < line.endIndex, words.count < 12 {
                while i < line.endIndex, line[i] == " " { i = line.index(after: i) }
                guard i < line.endIndex else { break }
                let start = i
                while i < line.endIndex, line[i] != " " { i = line.index(after: i) }
                words.append((String(line[start..<i]), start..<i))
            }
            guard words.count >= 8, words[0].0.count >= 10 else { continue }
            var m: Int?
            for k in 4..<(words.count - 2) where months.contains(words[k].0) {
                if let d = Int(words[k + 1].0), (1...31).contains(d), words[k + 2].0.contains(":") || Int(words[k + 2].0) != nil {
                    m = k
                    break
                }
            }
            guard let k = m else { continue }
            let afterDate = words[k + 2].1.upperBound
            guard afterDate < line.endIndex else { continue }
            var name = String(line[line.index(after: afterDate)...])
            let mode = words[0].0
            let kind: RemoteFileEntry.Kind = switch mode.first {
            case "d": .directory
            case "l": .symlink
            case "-": .file
            default: .other
            }
            var target: String?
            if kind == .symlink, let arrow = name.range(of: " -> ") {
                target = String(name[arrow.upperBound...])
                name = String(name[..<arrow.lowerBound])
            }
            guard !name.isEmpty, keepDots || (name != "." && name != "..") else { continue }
            if keepDots, name.contains("/") { name = (name as NSString).lastPathComponent }
            // Urządzenia: „główny, poboczny” zamiast rozmiaru.
            let isDevice = words[k - 1].0.hasSuffix(",") || words[k - 2].0.hasSuffix(",")
            let size = isDevice ? 0 : (Int64(words[k - 1].0) ?? 0)
            let month = months.firstIndex(of: words[k].0)! + 1
            let day = Int(words[k + 1].0)!
            var comps = DateComponents(year: currentYear, month: month, day: day)
            let third = words[k + 2].0
            if let year = Int(third) {
                comps.year = year
            } else {
                let hm = third.split(separator: ":")
                comps.hour = Int(hm.first ?? "0")
                comps.minute = Int(hm.count > 1 ? hm[1] : "0")
            }
            var date = calendar.date(from: comps)
            // Bez roku = ostatnie pół roku; data „w przyszłości” to zeszły rok.
            if Int(third) == nil, let d = date, d > now.addingTimeInterval(86400) {
                comps.year = currentYear - 1
                date = calendar.date(from: comps)
            }
            out.append(RemoteFileEntry(name: name, kind: kind, size: kind == .directory ? -1 : size, modified: date,
                                       permissions: parseMode(mode), linkTarget: target))
        }
        return out
    }

    public static func parseMode(_ mode: String) -> UInt16 {
        let chars = Array(mode.dropFirst().prefix(9))
        guard chars.count == 9 else { return 0 }
        var bits: UInt16 = 0
        for (i, c) in chars.enumerated() where c != "-" && c != "S" && c != "T" {
            bits |= 1 << UInt16(8 - i)
        }
        if "sS".contains(chars[2]) { bits |= 0o4000 }
        if "sS".contains(chars[5]) { bits |= 0o2000 }
        if "tT".contains(chars[8]) { bits |= 0o1000 }
        return bits
    }
}
