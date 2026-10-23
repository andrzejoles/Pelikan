import Foundation

/// Format kopiowania SQL jako literału w języku programowania (UG 25.6 Special Copy) i odwrotnie (UG 25.7 Paste from
/// host language). Linia `i` daje: `prefiks + cudzysłów + tekst z escapami + [znak nowej linii] + cudzysłów + sufiks`.
public struct CopyFormat: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Przed pierwszą linią (np. `String sql = `) i przed kolejnymi (wcięcie).
    public var firstPrefix: String
    public var linePrefix: String
    /// Po literale linii nie-ostatniej (np. ` +`) i ostatniej (np. `;`).
    public var lineSuffix: String
    public var lastSuffix: String
    public var quote: String
    /// Zamiany znaków w literale: `[z, na]`, np. `["\"", "\\\""]`.
    public var escapes: [[String]]
    /// Znak nowej linii wewnątrz literału (np. `\n`); pusty — nowa linia wynika z sufiksu (Delphi, VB).
    public var newline: String

    public init(id: String, name: String, firstPrefix: String, linePrefix: String, lineSuffix: String, lastSuffix: String,
                quote: String, escapes: [[String]], newline: String) {
        self.id = id; self.name = name; self.firstPrefix = firstPrefix; self.linePrefix = linePrefix; self.lineSuffix = lineSuffix
        self.lastSuffix = lastSuffix; self.quote = quote; self.escapes = escapes; self.newline = newline
    }

    static let backslash = [["\\", "\\\\"], ["\"", "\\\""], ["\t", "\\t"]]

    public static let builtIn: [CopyFormat] = [
        CopyFormat(id: "swift", name: "Swift", firstPrefix: "let sql = ", linePrefix: "    ", lineSuffix: " +", lastSuffix: "",
                   quote: "\"", escapes: backslash, newline: "\\n"),
        CopyFormat(id: "java", name: "Java", firstPrefix: "String sql = ", linePrefix: "    ", lineSuffix: " +", lastSuffix: ";",
                   quote: "\"", escapes: backslash, newline: "\\n"),
        CopyFormat(id: "csharp", name: "C#", firstPrefix: "string sql = ", linePrefix: "    ", lineSuffix: " +", lastSuffix: ";",
                   quote: "\"", escapes: backslash, newline: "\\n"),
        CopyFormat(id: "javascript", name: "JavaScript", firstPrefix: "const sql = ", linePrefix: "    ", lineSuffix: " +", lastSuffix: ";",
                   quote: "\"", escapes: backslash, newline: "\\n"),
        CopyFormat(id: "python", name: "Python", firstPrefix: "sql = (", linePrefix: "    ", lineSuffix: "", lastSuffix: ")",
                   quote: "\"", escapes: backslash, newline: "\\n"),
        CopyFormat(id: "c", name: "C/C++", firstPrefix: "const char *sql = ", linePrefix: "    ", lineSuffix: "", lastSuffix: ";",
                   quote: "\"", escapes: backslash, newline: "\\n"),
        CopyFormat(id: "php", name: "PHP", firstPrefix: "$sql = ", linePrefix: "    ", lineSuffix: " .", lastSuffix: ";",
                   quote: "\"", escapes: backslash + [["$", "\\$"]], newline: "\\n"),
        CopyFormat(id: "delphi", name: "Delphi", firstPrefix: "SQL := ", linePrefix: "  ", lineSuffix: " + sLineBreak +", lastSuffix: ";",
                   quote: "'", escapes: [["'", "''"]], newline: ""),
        CopyFormat(id: "vb", name: "Visual Basic", firstPrefix: "Dim sql As String = ", linePrefix: "    ", lineSuffix: " & vbCrLf & _", lastSuffix: "",
                   quote: "\"", escapes: [["\"", "\"\""]], newline: ""),
    ]

    /// Formaty wbudowane i z plików `CopyFormats/*.json` katalogu danych (ten sam identyfikator zastępuje wbudowany).
    public static func all(dataDirectory: URL?) -> [CopyFormat] {
        var list = builtIn
        guard let dir = dataDirectory?.appendingPathComponent("CopyFormats", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return list }
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f), let fmt = try? JSONDecoder().decode(CopyFormat.self, from: data),
                  !fmt.id.isEmpty, fmt.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { continue }
            if let i = list.firstIndex(where: { $0.id == fmt.id }) { list[i] = fmt } else { list.append(fmt) }
        }
        return list
    }

    /// SQL → literał języka.
    public func copy(_ sql: String) -> String {
        var lines = sql.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        while lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        return lines.enumerated().map { i, line in
            let last = i == lines.count - 1
            var body = line
            for e in escapes where e.count == 2 { body = body.replacingOccurrences(of: e[0], with: e[1]) }
            return (i == 0 ? firstPrefix : linePrefix) + quote + body + (last ? "" : newline) + quote + (last ? lastSuffix : lineSuffix)
        }.joined(separator: "\n")
    }

    /// Literał języka → SQL: zawartość literałów w każdej linii (escapy odwrócone); linie bez znaku nowej linii
    /// wewnątrz literału łączone nową linią.
    public func paste(_ code: String) -> String {
        let reverse = escapes.filter { $0.count == 2 }.map { ($0[1], $0[0]) } + (newline.isEmpty ? [] : [(newline, "\n")])
        return Self.extract(code, quote: quote, reverse: reverse)
    }

    /// Wklejenie bez wskazanego formatu: cudzysłów i styl escapów wykrywane z tekstu.
    public static func pasteDetecting(_ code: String) -> String {
        let dq = code.firstIndex(of: "\""), sq = code.firstIndex(of: "'")
        let quote: String = switch (dq, sq) {
        case let (d?, s?): d < s ? "\"" : "'"
        case (_?, nil): "\""
        case (nil, _?): "'"
        default: ""
        }
        guard !quote.isEmpty else { return code }
        if quote == "'" { return extract(code, quote: "'", reverse: [("''", "'"), ("\\'", "'"), ("\\n", "\n"), ("\\\\", "\\")]) }
        let backslashStyle = code.contains("\\\"") || code.contains("\\n") || code.contains("\\t")
        return extract(code, quote: "\"", reverse: backslashStyle ? [("\\\\", "\\"), ("\\\"", "\""), ("\\t", "\t"), ("\\n", "\n"), ("\\$", "$")] : [("\"\"", "\"")])
    }

    static func extract(_ code: String, quote: String, reverse: [(String, String)]) -> String {
        let ordered = reverse.sorted { $0.0.count > $1.0.count }
        var out = ""
        var first = true
        for line in code.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var content = "", found = false
            var i = line.startIndex
            while i < line.endIndex {
                guard line[i...].hasPrefix(quote) else { i = line.index(after: i); continue }
                found = true
                i = line.index(i, offsetBy: quote.count)
                scan: while i < line.endIndex {
                    for (from, to) in ordered where line[i...].hasPrefix(from) {
                        content += to
                        i = line.index(i, offsetBy: from.count)
                        continue scan
                    }
                    if line[i...].hasPrefix(quote) { i = line.index(i, offsetBy: quote.count); break }
                    content.append(line[i])
                    i = line.index(after: i)
                }
            }
            guard found else { continue }
            if !first, !out.hasSuffix("\n") { out += "\n" }
            out += content
            first = false
        }
        return out.hasSuffix("\n") ? String(out.dropLast()) : out
    }
}
