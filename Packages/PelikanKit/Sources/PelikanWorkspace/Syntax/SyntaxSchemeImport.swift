import Foundation
import PelikanSQL

/// Import motywów z innych edytorów jako motywów własnych (D227): Pelikan (JSON), base16/base24 (YAML, jak
/// wbudowane), Xcode (`.xccolortheme`), TextMate (`.tmTheme`) i Visual Studio Code (JSON z `tokenColors`).
/// Kategorie SQL dobierane z zakresów TextMate (najdłuższy pasujący przedrostek) albo nazw kolorów Xcode.
public enum SyntaxSchemeImport {
    public enum Failure: Error, LocalizedError {
        case unrecognized(String)
        public var errorDescription: String? {
            switch self {
            case .unrecognized(let name): L10n.tr("Nie rozpoznano motywu w pliku \(name) (obsługiwane: Pelikan .json, base16/base24 .yaml, Xcode .xccolortheme, TextMate .tmTheme, Visual Studio Code .json)")
            }
        }
    }

    /// Rozszerzenia plików w oknie wyboru.
    public static let fileExtensions = ["json", "yaml", "yml", "xccolortheme", "tmtheme"]

    public static func scheme(from data: Data, fileName: String) throws -> SyntaxScheme {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let base = ((fileName as NSString).lastPathComponent as NSString).deletingPathExtension
        var s: SyntaxScheme?
        switch ext {
        case "yaml", "yml": s = base16YAML(String(decoding: data, as: UTF8.self), fallbackName: base)
        case "xccolortheme": s = xcode(data, name: base)
        case "tmtheme": s = textMate(data, name: base)
        default:
            if let own = try? JSONDecoder().decode(SyntaxScheme.self, from: data) { s = own }
            else { s = vsCode(data, name: base) }
        }
        guard var out = s else { throw Failure.unrecognized((fileName as NSString).lastPathComponent) }
        out.id = "user." + UUID().uuidString.lowercased()
        if out.name.trimmingCharacters(in: .whitespaces).isEmpty { out.name = base }
        return out
    }

    /// Plik eksportu motywu (JSON Pelikana).
    public static func export(_ s: SyntaxScheme) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(s)
    }

    // MARK: - base16 / base24 (YAML)

    public static func base16YAML(_ text: String, fallbackName: String = "") -> SyntaxScheme? {
        var pal: [Int: RGB] = [:]
        var meta: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            var l = line.trimmingCharacters(in: .whitespaces)
            guard let colon = l.firstIndex(of: ":") else { continue }
            let key = String(l[..<colon]).trimmingCharacters(in: .whitespaces)
            l = String(l[l.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            var value: String
            if let q = l.first, q == "\"" || q == "'" {
                let rest = l.dropFirst()
                value = String(rest[..<(rest.firstIndex(of: q) ?? rest.endIndex)])
            } else {
                value = String(l[..<(l.range(of: " #")?.lowerBound ?? l.endIndex)]).trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(in: .whitespaces)
            let lower = key.lowercased()
            if lower.hasPrefix("base0"), lower.count == 6, let n = Int(lower.suffix(1), radix: 16), let c = RGB(hex: value) { pal[n] = c }
            else if ["scheme", "name", "author", "variant"].contains(lower) { meta[lower] = value }
        }
        guard pal.count == 16 else { return nil }
        let palette = (0..<16).map { pal[$0]! }
        let dark = meta["variant"].map { $0.lowercased() != "light" } ?? (palette[0].luminance < 0.4)
        return SyntaxScheme.base16(id: "", name: meta["name"] ?? meta["scheme"] ?? fallbackName, author: meta["author"] ?? "",
                                   source: "base16", dark: dark, palette: palette)
    }

    // MARK: - Xcode

    static func xcode(_ data: Data, name: String) -> SyntaxScheme? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let colors = plist["DVTSourceTextSyntaxColors"] as? [String: String] else { return nil }
        let fonts = plist["DVTSourceTextSyntaxFonts"] as? [String: String] ?? [:]
        func rgb(_ s: String?) -> RGB? {
            guard let parts = s?.split(separator: " ").compactMap({ Double($0) }), parts.count >= 3 else { return nil }
            return RGB(red: parts[0], green: parts[1], blue: parts[2])
        }
        guard let bg = rgb(plist["DVTSourceTextBackground"] as? String) else { return nil }
        let plain = rgb(colors["xcode.syntax.plain"]) ?? (bg.luminance < 0.4 ? RGB(255, 255, 255) : RGB(0, 0, 0))
        func style(_ keys: [String]) -> TokenStyle {
            guard let key = keys.first(where: { colors[$0] != nil }) else { return TokenStyle(plain) }
            let font = fonts[key] ?? ""
            return TokenStyle(rgb(colors[key]), bold: font.contains("Bold") || font.contains("Heavy"), italic: font.contains("Italic"))
        }
        let styles: [SyntaxStyle: TokenStyle] = [
            .plain: style(["xcode.syntax.plain"]), .keyword: style(["xcode.syntax.keyword"]),
            .dataType: style(["xcode.syntax.identifier.type.system", "xcode.syntax.identifier.type", "xcode.syntax.keyword"]),
            .function: style(["xcode.syntax.identifier.function.system", "xcode.syntax.identifier.function"]),
            .package: style(["xcode.syntax.identifier.class.system", "xcode.syntax.identifier.class"]),
            .string: style(["xcode.syntax.string"]), .number: style(["xcode.syntax.number"]),
            .comment: style(["xcode.syntax.comment"]), .hint: style(["xcode.syntax.comment.doc", "xcode.syntax.comment"]),
            .variable: style(["xcode.syntax.identifier.variable.system", "xcode.syntax.identifier.variable"]),
            .quotedIdentifier: style(["xcode.syntax.identifier.constant", "xcode.syntax.character"]),
            .operator: style(["xcode.syntax.plain"]),
            .directive: style(["xcode.syntax.preprocessor", "xcode.syntax.attribute"]),
        ]
        return SyntaxScheme(id: "", name: name, source: "Xcode", isDark: bg.luminance < 0.4, background: bg, text: plain,
                            selection: rgb(plist["DVTSourceTextSelectionColor"] as? String),
                            currentLine: rgb(plist["DVTSourceTextCurrentLineHighlightColor"] as? String),
                            lineNumber: plain.mixed(with: bg, 0.45),
                            cursor: rgb(plist["DVTSourceTextInsertionPointColor"] as? String) ?? plain, styles: styles)
    }

    // MARK: - TextMate i Visual Studio Code

    /// Reguła zakresu TextMate: selektory (przedrostki zakresów), kolor, styl kroju.
    struct ScopeRule {
        var selectors: [String]
        var foreground: String?
        var fontStyle: String?
    }

    /// Zakresy TextMate sprawdzane dla kategorii — w kolejności od najbardziej szczegółowych (gramatyka SQL).
    static let scopes: [SyntaxStyle: [String]] = [
        .keyword: ["keyword.other.DML.sql", "keyword.other.sql", "keyword.control", "keyword"],
        .dataType: ["storage.type.sql", "support.type", "storage.type", "entity.name.type"],
        .function: ["support.function.sql", "support.function", "entity.name.function", "meta.function-call"],
        .package: ["support.class", "entity.name.type.class", "entity.name.namespace", "support.type"],
        .string: ["string.quoted.single.sql", "string"],
        .number: ["constant.numeric", "constant"],
        .comment: ["comment.line", "comment"],
        .hint: ["comment.block.documentation", "comment.documentation", "comment"],
        .variable: ["variable.other.bind", "variable.parameter", "variable"],
        .quotedIdentifier: ["string.quoted.double.sql", "variable.other.member", "entity.name.tag"],
        .operator: ["keyword.operator", "punctuation"],
        .directive: ["meta.preprocessor", "keyword.control.directive", "keyword.control.import", "keyword.other.special-method"],
    ]

    /// Reguła z najdłuższym selektorem będącym przedrostkiem zakresu (jak w TextMate, bez kontekstu przodków).
    static func resolve(_ scope: String, _ rules: [ScopeRule]) -> ScopeRule? {
        var best: (len: Int, rule: ScopeRule)?
        for r in rules where r.foreground != nil || r.fontStyle != nil {
            for sel in r.selectors {
                let last = sel.split(separator: " ").last.map(String.init) ?? sel   // „source.sql keyword” → keyword
                guard scope == last || scope.hasPrefix(last + ".") else { continue }
                if best == nil || last.count >= best!.len { best = (last.count, r) }
            }
        }
        return best?.rule
    }

    static func scheme(name: String, author: String, source: String, dark: Bool?, editor: [String: String], rules: [ScopeRule]) -> SyntaxScheme? {
        func color(_ s: String?, on bg: RGB?) -> RGB? {
            guard var h = s?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
            if h.hasPrefix("#") { h.removeFirst() }
            if h.count == 8, let bg, let a = UInt8(h.suffix(2), radix: 16), let c = RGB(hex: String(h.prefix(6))) {
                return bg.mixed(with: c, Double(a) / 255)      // przezroczystość (zaznaczenie, linia bieżąca) na tle
            }
            return RGB(hex: h)
        }
        guard let bg = color(editor["background"], on: nil) else { return nil }
        let fg = color(editor["foreground"], on: bg) ?? (bg.luminance < 0.4 ? RGB(255, 255, 255) : RGB(0, 0, 0))
        var styles: [SyntaxStyle: TokenStyle] = [.plain: TokenStyle(fg)]
        for (style, list) in scopes {
            let rule = list.lazy.compactMap { resolve($0, rules) }.first
            let fs = rule?.fontStyle?.lowercased() ?? ""
            styles[style] = TokenStyle(color(rule?.foreground, on: bg) ?? fg, bold: fs.contains("bold"),
                                       italic: fs.contains("italic") || (style == .comment && rule == nil))
        }
        return SyntaxScheme(id: "", name: name, author: author, source: source, isDark: dark ?? (bg.luminance < 0.4),
                            background: bg, text: fg, selection: color(editor["selection"], on: bg),
                            currentLine: color(editor["lineHighlight"], on: bg),
                            lineNumber: color(editor["lineNumber"], on: bg) ?? fg.mixed(with: bg, 0.45),
                            cursor: color(editor["caret"], on: bg) ?? fg, styles: styles)
    }

    static func textMate(_ data: Data, name: String) -> SyntaxScheme? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let settings = plist["settings"] as? [[String: Any]] else { return nil }
        var editor: [String: String] = [:]
        var rules: [ScopeRule] = []
        for entry in settings {
            let s = entry["settings"] as? [String: String] ?? [:]
            if let scope = entry["scope"] as? String {
                rules.append(ScopeRule(selectors: scope.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                       foreground: s["foreground"], fontStyle: s["fontStyle"]))
            } else if editor.isEmpty {
                editor = s
            }
        }
        return scheme(name: plist["name"] as? String ?? name, author: plist["author"] as? String ?? "", source: "TextMate",
                      dark: nil, editor: editor, rules: rules)
    }

    static func vsCode(_ data: Data, name: String) -> SyntaxScheme? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(stripJSONC(String(decoding: data, as: UTF8.self)).utf8)) as? [String: Any],
              obj["tokenColors"] != nil || obj["colors"] != nil else { return nil }
        let colors = obj["colors"] as? [String: String] ?? [:]
        var rules: [ScopeRule] = []
        for entry in obj["tokenColors"] as? [[String: Any]] ?? [] {
            let s = entry["settings"] as? [String: String] ?? [:]
            let sel: [String]
            if let one = entry["scope"] as? String { sel = one.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            else { sel = entry["scope"] as? [String] ?? [] }
            if !sel.isEmpty { rules.append(ScopeRule(selectors: sel, foreground: s["foreground"], fontStyle: s["fontStyle"])) }
        }
        let editor: [String: String] = [
            "background": colors["editor.background"] ?? "", "foreground": colors["editor.foreground"] ?? "",
            "selection": colors["editor.selectionBackground"] ?? "", "lineHighlight": colors["editor.lineHighlightBackground"] ?? "",
            "lineNumber": colors["editorLineNumber.foreground"] ?? "", "caret": colors["editorCursor.foreground"] ?? "",
        ]
        let type = (obj["type"] as? String)?.lowercased()
        let dark: Bool? = type.map { $0.contains("dark") || $0 == "hc" }
        var editorWithBG = editor
        if editorWithBG["background"]!.isEmpty { editorWithBG["background"] = dark == false ? "#ffffff" : "#1e1e1e" }   // domyślne tła VS Code
        return scheme(name: obj["name"] as? String ?? name, author: obj["author"] as? String ?? "", source: "Visual Studio Code",
                      dark: dark, editor: editorWithBG, rules: rules)
    }

    /// JSON z komentarzami i przecinkami na końcu list (format motywów VS Code) → zwykły JSON.
    static func stripJSONC(_ s: String) -> String {
        var out = ""
        let u = Array(s.unicodeScalars)
        var i = 0
        var inString = false
        while i < u.count {
            let c = u[i]
            if inString {
                out.unicodeScalars.append(c)
                if c == "\\", i + 1 < u.count { out.unicodeScalars.append(u[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
            } else if c == "\"" {
                inString = true; out.unicodeScalars.append(c); i += 1
            } else if c == "/", i + 1 < u.count, u[i + 1] == "/" {
                while i < u.count, u[i] != "\n" { i += 1 }
            } else if c == "/", i + 1 < u.count, u[i + 1] == "*" {
                i += 2
                while i + 1 < u.count, !(u[i] == "*" && u[i + 1] == "/") { i += 1 }
                i += 2
            } else if c == "," {
                var j = i + 1
                // Białe znaki i komentarze między przecinkiem a zamknięciem (`"a": 1, // ostatni` przed `}`).
                while j < u.count {
                    if u[j].properties.isWhitespace { j += 1 }
                    else if u[j] == "/", j + 1 < u.count, u[j + 1] == "/" { while j < u.count, u[j] != "\n" { j += 1 } }
                    else if u[j] == "/", j + 1 < u.count, u[j + 1] == "*" {
                        j += 2
                        while j + 1 < u.count, !(u[j] == "*" && u[j + 1] == "/") { j += 1 }
                        j += 2
                    } else { break }
                }
                if j < u.count, u[j] == "}" || u[j] == "]" { i += 1; continue }   // przecinek przed zamknięciem
                out.unicodeScalars.append(c); i += 1
            } else {
                out.unicodeScalars.append(c); i += 1
            }
        }
        return out
    }
}
