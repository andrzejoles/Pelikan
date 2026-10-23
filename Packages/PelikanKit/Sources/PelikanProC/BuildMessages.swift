import Foundation

/// Komunikat kompilatora z wyjścia `make` (zadanie Pro*C, „Parsery błędów”). Sukces builda wyznacza kod wyjścia
/// `make`, nie parser — parser tylko czyni komunikaty klikalnymi.
public struct BuildMessage: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Hashable {
        /// I — informacja.
        case info
        /// W — ostrzeżenie.
        case warning
        /// E — błąd (kompilacja kontynuowana).
        case error
        /// S — błąd poważny; F (proc) — błąd krytyczny.
        case severe
        /// U — błąd nienaprawialny (kompilator przerwał).
        case unrecoverable
    }

    public enum Tool: String, Sendable, Hashable { case proc, xlc }

    public var tool: Tool
    /// Ścieżka jak w wyjściu (serwer): bezwzględna albo względna wobec katalogu `make`.
    public var file: String?
    public var line: Int?
    public var column: Int?
    public var severity: Severity
    /// `PCC-S-02201`, `1506-045`.
    public var code: String
    public var text: String
    /// Numer linii wyjścia, w której zaczyna się komunikat (od 1).
    public var outputLine: Int
    public var id: String { "\(outputLine):\(code)" }

    public var isError: Bool { [.error, .severe, .unrecoverable].contains(severity) }
}

/// Parsery komunikatów Pro*C (`PCC-x-NNNNN`, przy SQLCHECK=SEMANTICS także `PLS-x-NNNNN`) i IBM XL C/C++ V12.1 (`"plik", line L.C: 1506-NNN (S) treść`, także
/// z `-qsrcmsg`). Wzorce zbudowane na formacie z dokumentacji — do potwierdzenia próbkami z serwera AIX (D-PC2-2).
public enum BuildMessageParser {
    static let xlcLine = try! NSRegularExpression(pattern: #"^"([^"]+)", line (\d+)(?:\.(\d+))?: (\d{4}-\d{3,4}) \(([IWESU])\) (.*)$"#)
    /// `-qsrcmsg`: `a - 1506-045 (S) treść` po linii źródła `  45 | …` i znaczniku `....a...`.
    static let xlcSrcMsg = try! NSRegularExpression(pattern: #"^([a-z]) - (\d{4}-\d{3,4}) \(([IWESU])\) (.*)$"#)
    static let xlcSourceLine = try! NSRegularExpression(pattern: #"^\s*(\d+)\s\|"#)
    static let pccCode = try! NSRegularExpression(pattern: #"^((?:PCC|PLS)-([SWFIE])-\d{5}),?\s*(.*)$"#)
    /// `Semantic error at line 12, column 5, file prog.pc:` / `Syntax error at line …` / `Error at line 12, column 5 in file prog.pc`
    static let pccLocation = try! NSRegularExpression(
        pattern: #"^(?:Semantic error|Syntax error|Error|Warning) at line (\d+), column (\d+),? (?:in )?file (.+?):?\s*$"#)
    /// Polecenie kompilacji w wyjściu `make` (plik bieżący dla `-qsrcmsg` bez nazwy pliku w komunikacie).
    static let compileCommand = try! NSRegularExpression(pattern: #"(?:^|\s)(?:xlc|xlc_r|cc|cc_r|xlC|xlC_r)\b.*\s-c\s+(\S+\.(?:c|C|cpp))\b"#)

    static func groups(_ re: NSRegularExpression, _ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }

    static func xlcSeverity(_ s: String) -> BuildMessage.Severity {
        switch s {
        case "I": .info
        case "W": .warning
        case "E": .error
        case "S": .severe
        default: .unrecoverable
        }
    }

    static func pccSeverity(_ s: String) -> BuildMessage.Severity {
        switch s {
        case "W": .warning
        case "I": .info
        case "E": .error
        case "F": .unrecoverable
        default: .severe
        }
    }

    /// Wszystkie komunikaty z wyjścia (`\n` jako separator, `\r` ignorowane).
    public static func parse(_ output: String) -> [BuildMessage] {
        var out: [BuildMessage] = []
        var pccPending: (file: String, line: Int, column: Int, outputLine: Int)?
        var srcLine: Int?
        var markerColumns: [Character: Int] = [:]
        var currentFile: String?
        let lines = output.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        for (i, raw) in lines.enumerated() {
            let line = raw
            if let g = groups(compileCommand, line), let f = g[0] { currentFile = f }
            if let g = groups(xlcLine, line) {
                out.append(BuildMessage(tool: .xlc, file: g[0], line: g[1].flatMap { Int($0) }, column: g[2].flatMap { Int($0) },
                                        severity: xlcSeverity(g[4] ?? "S"), code: g[3] ?? "", text: g[5] ?? "", outputLine: i + 1))
                currentFile = g[0] ?? currentFile
                continue
            }
            if let g = groups(xlcSourceLine, line) {
                srcLine = g[0].flatMap { Int($0) }
                markerColumns = [:]
                continue
            }
            // Znacznik kolumn pod linią źródła: kropki i litery; kolumna = pozycja litery względem `|` linii źródła.
            if srcLine != nil, line.trimmingCharacters(in: .whitespaces).first.map({ $0 == "." || $0.isLetter }) == true,
               line.contains("."),
               line.allSatisfy({ $0 == " " || $0 == "." || $0.isLowercase }), line.contains(where: { $0.isLowercase }) {
                let prev = i > 0 ? lines[i - 1] : ""
                let bar = prev.firstIndex(of: "|").map { prev.distance(from: prev.startIndex, to: $0) } ?? 0
                for (offset, ch) in line.enumerated() where ch.isLowercase {
                    markerColumns[ch] = max(1, offset - bar - 1)
                }
                continue
            }
            if let g = groups(xlcSrcMsg, line) {
                let letter = g[0].flatMap { $0.first }
                out.append(BuildMessage(tool: .xlc, file: currentFile, line: srcLine, column: letter.flatMap { markerColumns[$0] },
                                        severity: xlcSeverity(g[2] ?? "S"), code: g[1] ?? "", text: g[3] ?? "", outputLine: i + 1))
                continue
            }
            if let g = groups(pccLocation, line), let l = g[0].flatMap({ Int($0) }), let c = g[1].flatMap({ Int($0) }), let f = g[2] {
                pccPending = (f, l, c, i + 1)
                continue
            }
            if let g = groups(pccCode, line) {
                let p = pccPending
                out.append(BuildMessage(tool: .proc, file: p?.file, line: p?.line, column: p?.column,
                                        severity: pccSeverity(g[1] ?? "S"), code: g[0] ?? "", text: g[2] ?? "", outputLine: p?.outputLine ?? i + 1))
                pccPending = nil
            }
        }
        return out
    }

    /// Ścieżka względna wobec repozytorium (ta sama na serwerze i na Macu): `file` z komunikatu, `makeDirectory` —
    /// katalog, w którym działał `make`, `remoteRoot` — korzeń working copy na serwerze. Nil — plik poza repozytorium.
    public static func projectRelativePath(_ file: String, makeDirectory: String, remoteRoot: String) -> String? {
        func normalize(_ p: String) -> String {
            var parts: [Substring] = []
            for c in p.split(separator: "/") {
                if c == "." || c.isEmpty { continue }
                if c == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
                parts.append(c)
            }
            return "/" + parts.joined(separator: "/")
        }
        let absolute = normalize(file.hasPrefix("/") ? file : makeDirectory + "/" + file)
        let root = normalize(remoteRoot)
        guard absolute.hasPrefix(root + "/") else { return nil }
        return String(absolute.dropFirst(root.count + 1))
    }
}
