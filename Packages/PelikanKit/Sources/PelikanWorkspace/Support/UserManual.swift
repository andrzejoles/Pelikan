import Foundation

/// Instrukcja użytkownika w aplikacji (PL-INFRA-010): rozdziały Markdown z zasobów aplikacji (`Manual/<język>/*.md`,
/// brak języka — polski), wyświetlane jako HTML bez skryptów, oraz rozdział skrótów generowany z rejestru komend
/// (nazwy komend w bieżącym języku, skróty z bieżącego profilu i własnych ustawień).
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

    /// Rozdziały z katalogu w kolejności nazw plików (01-…, 02-…); tytuł z pierwszego nagłówka `#`.
    public static func chapters(in directory: URL) -> [Chapter] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".md") }.sorted()
        return files.compactMap { f in
            guard let text = try? String(contentsOf: directory.appendingPathComponent(f), encoding: .utf8) else { return nil }
            let title = text.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) } ?? f
            return Chapter(id: f, title: title, html: html(markdown: text))
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
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <style>
        :root { color-scheme: light dark; }
        body { font: 13px -apple-system, sans-serif; line-height: 1.5; margin: 18px 24px; max-width: 760px; }
        h1 { font-size: 22px; margin-top: 0; } h2 { font-size: 16px; margin-top: 22px; } h3 { font-size: 14px; }
        code { font: 12px ui-monospace, Menlo, monospace; background: rgba(127,127,127,.15); padding: 1px 4px; border-radius: 4px; }
        pre code { display: block; padding: 8px; white-space: pre-wrap; }
        table { border-collapse: collapse; width: 100%; } td { padding: 3px 8px; border-bottom: 1px solid rgba(127,127,127,.25); }
        td.keys { white-space: nowrap; font-family: ui-monospace, Menlo, monospace; text-align: right; }
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

    /// Markdown (podzbiór: nagłówki, akapity, listy punktowane i numerowane z kontynuacją wcięciem, bloki kodu ```).
    public static func html(markdown: String) -> String {
        var out: [String] = []
        var paragraph: [String] = []
        var list: (tag: String, items: [String])?
        var code: [String]?
        func flushParagraph() {
            if !paragraph.isEmpty { out.append("<p>" + inline(paragraph.joined(separator: " ")) + "</p>"); paragraph = [] }
        }
        func flushList() {
            if let l = list { out.append("<\(l.tag)>" + l.items.map { "<li>" + inline($0) + "</li>" }.joined() + "</\(l.tag)>"); list = nil }
        }
        for line in markdown.components(separatedBy: "\n") {
            if code != nil {
                if line.hasPrefix("```") { out.append("<pre><code>" + escape(code!.joined(separator: "\n")) + "</code></pre>"); code = nil } else { code!.append(line) }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { flushParagraph(); flushList(); code = []; continue }
            if trimmed.isEmpty { flushParagraph(); flushList(); continue }
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
        flushParagraph(); flushList()
        if let c = code { out.append("<pre><code>" + escape(c.joined(separator: "\n")) + "</code></pre>") }
        return out.joined(separator: "\n")
    }
}
