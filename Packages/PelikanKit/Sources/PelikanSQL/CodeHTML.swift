import Foundation

/// Kod SQL / PL/SQL jako HTML z kolorami składni (leksem jak w edytorze): podgląd Quick Look (MAC-QL-001) i druk
/// okna (PD-SQLW-016). Kolory jak w edytorze, w trybie jasnym i ciemnym (`prefers-color-scheme`); druk — jasne.
public enum CodeHTML {
    /// Klasa CSS rodzaju tokenu (nil — tekst zwykły).
    static func cssClass(_ kind: TokenKind) -> String? {
        switch kind {
        case .keyword, .directive: "kw"
        case .string: "str"
        case .lineComment, .blockComment: "cmt"
        case .hint: "hint"
        case .number: "num"
        case .bindVariable, .substitution, .jasperParameter: "var"
        case .quotedIdentifier: "qid"
        case .operator, .semicolon, .slash, .comma, .leftParen, .rightParen, .dot: "op"
        default: nil
        }
    }

    public static let css = """
        pre.code{font:12px/1.45 ui-monospace,Menlo,monospace;margin:0;white-space:pre-wrap;word-wrap:break-word;tab-size:4}
        pre.code .ln{display:inline-block;min-width:3.2em;padding-right:1em;text-align:right;color:#8e8e93;user-select:none}
        .kw{color:#9b2494}.str{color:#c41a16}.cmt{color:#2e8533;font-style:italic}.hint{color:#1a8073}.num{color:#1c00cf}
        .var{color:#00739e}.qid{color:#6b389e}.op{color:#6e6e73}
        @media (prefers-color-scheme: dark){body{background:#1e1e1e;color:#e5e5e7}
        .kw{color:#fc5fa3}.str{color:#fc6a5d}.cmt{color:#6bbf66}.hint{color:#8cd9bf}.num{color:#d9c97c}
        .var{color:#66ccf0}.qid{color:#d999f2}.op{color:#a1a1a6}}
        @media print{body{background:#fff;color:#000}.kw{color:#9b2494}.str{color:#c41a16}.cmt{color:#2e8533}.hint{color:#1a8073}
        .num{color:#1c00cf}.var{color:#00739e}.qid{color:#6b389e}.op{color:#6e6e73}}
        """

    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// `<pre class="code">` z kolorami; tokeny wieloliniowe (komentarze, literały) dzielone na liniach, żeby numery
    /// linii zostały poza kolorowanymi fragmentami.
    public static func pre(_ text: String, lineNumbers: Bool = true) -> String {
        let lexer = Lexer(text)
        var out = "<pre class=\"code\">"
        var line = 1
        func number() -> String { lineNumbers ? "<span class=\"ln\">\(line)</span>" : "" }
        out += number()
        for t in lexer.tokenize() {
            let cls = cssClass(t.kind)
            let parts = lexer.string(t).components(separatedBy: "\n")
            for (i, part) in parts.enumerated() {
                if i > 0 {
                    line += 1
                    out += "\n" + number()
                }
                guard !part.isEmpty else { continue }
                out += cls.map { "<span class=\"\($0)\">\(escape(part))</span>" } ?? escape(part)
            }
        }
        return out + "</pre>"
    }

    /// Pełny dokument HTML (podgląd Quick Look).
    public static func document(_ text: String, title: String, lineNumbers: Bool = true) -> String {
        "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>\(escape(title))</title><style>body{margin:12px}\(css)</style></head><body>\n"
            + pre(text, lineNumbers: lineNumbers) + "\n</body></html>\n"
    }

    /// Tekst pliku źródłowego: BOM UTF-8/UTF-16, poprawny UTF-8, inaczej kodowanie jednobajtowe (`singleByteGuess`).
    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) ?? "" }
        if data.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) ?? "" }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: singleByteGuess(data)) ?? String(decoding: data, as: UTF8.self)
    }

    /// Kodowanie jednobajtowe pliku bez BOM i spoza UTF-8: bajty 0x80–0x9F to znaki Windows-1250 (w ISO-8859-2 są
    /// tam znaki sterujące); polskie litery na pozycjach ISO-8859-2 (ą ś ź Ą Ś Ź = B1 B6 BC A1 A6 AC) bez 0x80–0x9F →
    /// ISO-8859-2 (pliki z AIX/Unix); w innym razie Windows-1250 (pliki z PL/SQL Developer).
    public static func singleByteGuess(_ data: Data) -> String.Encoding {
        var latin2 = false
        for b in data {
            if (0x80...0x9F).contains(b) { return .windowsCP1250 }
            if [0xB1, 0xB6, 0xBC, 0xA1, 0xA6, 0xAC].contains(b) { latin2 = true }
        }
        return latin2 ? .isoLatin2 : .windowsCP1250
    }
}
