import Foundation

/// Instrukcja użytkownika w aplikacji (PL-INFRA-010): rozdziały Markdown z zasobów aplikacji (`Manual/<język>/*.md`,
/// brak języka — polski; rozdział jeszcze nieprzetłumaczony — jego polska wersja), wyświetlane jako HTML bez skryptów,
/// z obrazkami z `Manual/img` osadzonymi jako `data:` (WKWebView nie dostaje dostępu do plików), oraz rozdział skrótów
/// generowany z rejestru komend (nazwy komend w bieżącym języku, skróty z bieżącego profilu i własnych ustawień).
public enum UserManual {
    public struct Chapter: Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var html: String
    }

    public static let languages = ["pl", "en", "de", "es", "uk"]

    /// Katalog rozdziałów dla języka interfejsu (pierwszy z preferowanych, który ma rozdziały; inaczej polski).
    public static func directory(in root: URL, preferred: [String]) -> URL? {
        let fm = FileManager.default
        for lang in preferred.map({ String($0.prefix(2)).lowercased() }) + ["pl"] where languages.contains(lang) {
            let d = root.appendingPathComponent(lang, isDirectory: true)
            if let files = try? fm.contentsOfDirectory(atPath: d.path), files.contains(where: { $0.hasSuffix(".md") }) { return d }
        }
        return nil
    }

    /// Rozdziały z katalogu w kolejności nazw plików (01-…, 02-…); tytuł z pierwszego nagłówka `#`. Rozdział, którego
    /// nie ma w katalogu języka, a jest w katalogu zapasowym (polskim), pochodzi z zapasowego — instrukcja w innym języku
    /// nie gubi rozdziałów dopisanych przed tłumaczeniem.
    public static func chapters(in directory: URL, fallback: URL? = nil) -> [Chapter] {
        let fm = FileManager.default
        func markdownFiles(_ d: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter { $0.hasSuffix(".md") } }
        let own = Set(markdownFiles(directory))
        let extra = fallback.map { markdownFiles($0).filter { !own.contains($0) } } ?? []
        let files = (Array(own) + extra).sorted()
        return files.compactMap { f in
            let dir = own.contains(f) ? directory : fallback!
            guard let text = try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8) else { return nil }
            let title = text.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) } ?? f
            return Chapter(id: f, title: title, html: html(markdown: text, imageBase: dir))
        }
    }

    /// Rozdział „Skróty klawiszowe” z rejestru (bez komend planowanych), pogrupowany według menu.
    public static func shortcutsChapter(commands: [CommandDescriptor], chords: (CommandID) -> [KeyChord]) -> Chapter {
        var body = "<h1>" + escape(L10n.tr("Skróty klawiszowe")) + "</h1>\n"
        for category in CommandCategory.allCases {
            let rows = commands.filter { $0.category == category && !chords($0.id).isEmpty }
            guard !rows.isEmpty else { continue }
            body += "<h2>" + escape(category.displayName) + "</h2>\n<table>\n"
            for d in rows {
                let title = (d.submenu.map { $0 + " › " } ?? "") + d.title
                body += "<tr><td>" + escape(title) + "</td><td class=\"keys\">" + escape(chords(d.id).map(\.displayString).joined(separator: ", ")) + "</td></tr>\n"
            }
            body += "</table>\n"
        }
        return Chapter(id: "99-shortcuts", title: L10n.tr("Skróty klawiszowe"), html: body)
    }

    /// Strona HTML rozdziału: styl systemowy, jasny i ciemny, bez skryptów i zasobów zewnętrznych.
    public static func page(_ chapter: Chapter) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <style>
        :root { color-scheme: light dark; }
        body { font: 13px -apple-system, sans-serif; line-height: 1.5; margin: 18px 24px; max-width: 760px; }
        h1 { font-size: 22px; margin-top: 0; } h2 { font-size: 16px; margin-top: 22px; } h3 { font-size: 14px; }
        code { font: 12px ui-monospace, Menlo, monospace; background: rgba(127,127,127,.15); padding: 1px 4px; border-radius: 4px; }
        pre code { display: block; padding: 8px; white-space: pre-wrap; }
        table { border-collapse: collapse; width: 100%; } td { padding: 3px 8px; border-bottom: 1px solid rgba(127,127,127,.25); }
        td.keys { white-space: nowrap; font-family: ui-monospace, Menlo, monospace; text-align: right; }
        th { text-align: left; padding: 3px 8px; border-bottom: 2px solid rgba(127,127,127,.35); vertical-align: bottom; }
        td { vertical-align: top; } table.md { margin: 8px 0 12px; }
        figure { margin: 12px 0 16px; } figcaption { font-size: 12px; color: rgba(127,127,127,1); margin-top: 4px; }
        figure img { max-width: 100%; height: auto; border: 1px solid rgba(127,127,127,.3); border-radius: 6px; }
        p.missing { color: rgba(127,127,127,1); font-style: italic; }
        </style></head><body>
        \(chapter.html)
        </body></html>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Formatowanie w linii: `kod`, **pogrubienie**, *kursywa*, [tekst](https://…) — tylko odnośniki http(s).
    static func inline(_ raw: String) -> String {
        let parts = raw.components(separatedBy: "`")
        // Nieparzysta liczba części = backticki w parach: części o nieparzystym indeksie to kod.
        let balanced = parts.count % 2 == 1
        return parts.enumerated().map { i, part in
            if balanced, i % 2 == 1 { return "<code>" + escape(part) + "</code>" }
            var t = escape(balanced ? part : part + (i < parts.count - 1 ? "`" : ""))
            t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, with: "<em>$1</em>", options: .regularExpression)
            t = t.replacingOccurrences(of: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
            return t
        }.joined()
    }

    /// Obrazek z linii `![opis](ścieżka)`: tylko plik PNG/JPEG wewnątrz katalogu instrukcji (rodzic katalogu języka),
    /// osadzony jako `data:` — bez odwołań do plików i sieci z WKWebView. Brak pliku albo ścieżka spoza instrukcji —
    /// sam opis.
    static func image(alt: String, path: String, base: URL?) -> String {
        let caption = alt.isEmpty ? "" : "<figcaption>" + inline(alt) + "</figcaption>"
        let missing = "<p class=\"missing\">[" + inline(alt.isEmpty ? path : alt) + "]</p>"
        let ext = (path as NSString).pathExtension.lowercased()
        guard let base, !path.contains(":"), !path.hasPrefix("/"), ["png", "jpg", "jpeg"].contains(ext) else { return missing }
        let root = base.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        let file = base.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root + "/"),
              let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int, size <= 4_000_000,
              let data = try? Data(contentsOf: file) else { return missing }
        let mime = ext == "png" ? "image/png" : "image/jpeg"
        return "<figure><img src=\"data:\(mime);base64,\(data.base64EncodedString())\" alt=\"\(escape(alt))\">\(caption)</figure>"
    }

    /// Wiersz tabeli `| a | b |` → komórki (bez skrajnych `|`; `\|` to znak `|` w komórce).
    static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "\u{1}")
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{1}", with: "|") }
    }

    /// Markdown (podzbiór: nagłówki, akapity, listy punktowane i numerowane z kontynuacją wcięciem, bloki kodu ```,
    /// tabele z wierszem nagłówka i obrazki w osobnej linii — `imageBase` to katalog pliku rozdziału).
    public static func html(markdown: String, imageBase: URL? = nil) -> String {
        var out: [String] = []
        var paragraph: [String] = []
        var list: (tag: String, items: [String])?
        var code: [String]?
        var table: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty { out.append("<p>" + inline(paragraph.joined(separator: " ")) + "</p>"); paragraph = [] }
        }
        func flushList() {
            if let l = list { out.append("<\(l.tag)>" + l.items.map { "<li>" + inline($0) + "</li>" }.joined() + "</\(l.tag)>"); list = nil }
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            defer { table = [] }
            let separator = table.count > 1 && table[1].allSatisfy { "|-: ".contains($0) } && table[1].contains("-")
            guard separator else { paragraph += table; flushParagraph(); return }
            var h = "<table class=\"md\"><thead><tr>" + tableCells(table[0]).map { "<th>" + inline($0) + "</th>" }.joined() + "</tr></thead><tbody>"
            for row in table.dropFirst(2) { h += "<tr>" + tableCells(row).map { "<td>" + inline($0) + "</td>" }.joined() + "</tr>" }
            out.append(h + "</tbody></table>")
        }
        for line in markdown.components(separatedBy: "\n") {
            if code != nil {
                if line.hasPrefix("```") { out.append("<pre><code>" + escape(code!.joined(separator: "\n")) + "</code></pre>"); code = nil } else { code!.append(line) }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") { flushParagraph(); flushList(); table.append(trimmed); continue }
            flushTable()
            if line.hasPrefix("```") { flushParagraph(); flushList(); code = []; continue }
            if trimmed.isEmpty { flushParagraph(); flushList(); continue }
            if let m = trimmed.firstMatch(of: #/^!\[([^\]]*)\]\(([^)\s]+)\)$/#) {
                flushParagraph(); flushList()
                out.append(image(alt: String(m.1), path: String(m.2), base: imageBase))
                continue
            }
            if let m = line.firstMatch(of: #/^(#{1,3}) (.+)$/#) {
                flushParagraph(); flushList()
                out.append("<h\(m.1.count)>" + inline(String(m.2)) + "</h\(m.1.count)>")
                continue
            }
            if let m = line.firstMatch(of: #/^- (.+)$/#) {
                flushParagraph()
                if list?.tag != "ul" { flushList(); list = ("ul", []) }
                list!.items.append(String(m.1))
                continue
            }
            if let m = line.firstMatch(of: #/^\d+\. (.+)$/#) {
                flushParagraph()
                if list?.tag != "ol" { flushList(); list = ("ol", []) }
                list!.items.append(String(m.1))
                continue
            }
            if line.hasPrefix("  "), list != nil, !list!.items.isEmpty {
                list!.items[list!.items.count - 1] += " " + trimmed
                continue
            }
            flushList()
            paragraph.append(trimmed)
        }
        flushTable(); flushParagraph(); flushList()
        if let c = code { out.append("<pre><code>" + escape(c.joined(separator: "\n")) + "</code></pre>") }
        return out.joined(separator: "\n")
    }
}
