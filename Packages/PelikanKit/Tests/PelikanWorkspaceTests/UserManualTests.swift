import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Instrukcja użytkownika")
struct UserManualTests {
    @Test("Markdown: nagłówki, akapity, listy z kontynuacją, kod, pogrubienie, kursywa, odnośniki; HTML escapowany")
    func markdown() {
        let md = """
        # Tytuł

        Akapit z **pogrubieniem**, *kursywą* i `kodem <x>`
        w dwóch liniach.

        - punkt pierwszy
          ciąg dalszy
        - [strona](https://example.invalid/a) i [plik](file:///etc/passwd)

        1. krok
        2. drugi

        ```
        select * from emp where a < 1;
        ```
        """
        let h = UserManual.html(markdown: md)
        #expect(h.contains("<h1>Tytuł</h1>"))
        #expect(h.contains("<p>Akapit z <strong>pogrubieniem</strong>, <em>kursywą</em> i <code>kodem &lt;x&gt;</code> w dwóch liniach.</p>"))
        #expect(h.contains("<li>punkt pierwszy ciąg dalszy</li>"))
        #expect(h.contains("<a href=\"https://example.invalid/a\">strona</a>") && !h.contains("file:///etc/passwd\""))
        #expect(h.contains("<ol><li>krok</li><li>drugi</li></ol>"))
        #expect(h.contains("<pre><code>select * from emp where a &lt; 1;</code></pre>"))
        #expect(!UserManual.html(markdown: "<script>alert(1)</script>").contains("<script>"))
    }

    @Test("Rozdziały z katalogu języka (zapas: polski), kolejność plików, tytuły; strona z CSP bez skryptów")
    func chapters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("manual-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: root) }
        for (lang, files) in [("pl", ["02-b.md": "# Drugi\n", "01-a.md": "# Pierwszy\n\ntekst"]), ("en", ["01-a.md": "# First\n"])] {
            let d = root.appendingPathComponent(lang)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            for (f, t) in files { try Data(t.utf8).write(to: d.appendingPathComponent(f)) }
        }
        #expect(UserManual.directory(in: root, preferred: ["de-DE"])?.lastPathComponent == "pl")
        #expect(UserManual.directory(in: root, preferred: ["en-GB", "pl"])?.lastPathComponent == "en")
        let ch = UserManual.chapters(in: try #require(UserManual.directory(in: root, preferred: ["pl"])))
        #expect(ch.map(\.title) == ["Pierwszy", "Drugi"])
        let page = UserManual.page(ch[0])
        #expect(page.contains("Content-Security-Policy") && page.contains("default-src 'none'") && !page.contains("<script"))
    }

    @MainActor @Test("Rozdział skrótów z rejestru i keymapy; komenda pomocy")
    func shortcuts() async throws {
        let ws = Workspace()
        let ch = UserManual.shortcutsChapter(commands: ws.registry.commands.filter { !$0.isPlanned }.map(\.descriptor), chords: { ws.keymap.chords(for: $0) })
        #expect(ch.html.contains("<h2>") && ch.html.contains(ws.keymap.chords(for: "sql.execute").first!.displayString))
        #expect(ws.registry.commands.contains { $0.descriptor.id == "help.manual" && !$0.isPlanned })
    }

    @Test("Instrukcja w repozytorium: każdy język ma te same rozdziały co polski")
    func repositoryManual() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../docs/manual").standardizedFileURL
        let pl = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("pl").path).filter { $0.hasSuffix(".md") }.sorted()
        #expect(pl.count >= 10)
        for lang in UserManual.languages.dropFirst() {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(lang).path))?.filter { $0.hasSuffix(".md") }.sorted()
            #expect(files == nil || files == pl, "Rozdziały \(lang) różnią się od polskich")
        }
    }
}
