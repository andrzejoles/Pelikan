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
        // Rozdział bez tłumaczenia: wersja polska w kolejności plików.
        let en = UserManual.chapters(in: root.appendingPathComponent("en"), fallback: root.appendingPathComponent("pl"))
        #expect(en.map(\.title) == ["First", "Drugi"])
        let page = UserManual.page(ch[0])
        #expect(page.contains("Content-Security-Policy") && page.contains("default-src 'none'") && page.contains("img-src data:")
            && !page.contains("<script"))
    }

    @Test("Tabele z nagłówkiem; obrazki tylko z katalogu instrukcji, osadzone jako data:")
    func tablesAndImages() throws {
        let t = UserManual.html(markdown: "| Klawisz | Czynność |\n|---|---|\n| `F8` | Wykonaj **teraz** |\n| a \\| b | c |\n\nPo tabeli.")
        #expect(t.contains("<table class=\"md\"><thead><tr><th>Klawisz</th><th>Czynność</th></tr></thead>"))
        #expect(t.contains("<tr><td><code>F8</code></td><td>Wykonaj <strong>teraz</strong></td></tr>"))
        #expect(t.contains("<tr><td>a | b</td><td>c</td></tr>") && t.contains("<p>Po tabeli.</p>"))
        #expect(UserManual.html(markdown: "| bez | separatora |").contains("<p>| bez | separatora |</p>"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("manual-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: root) }
        let pl = root.appendingPathComponent("pl"), img = root.appendingPathComponent("img")
        try FileManager.default.createDirectory(at: pl, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: img, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: img.appendingPathComponent("okno.png"))
        try Data("x".utf8).write(to: root.appendingPathComponent("poza.png"))
        let ok = UserManual.html(markdown: "![Okno <główne>](../img/okno.png)", imageBase: pl)
        #expect(ok.contains("<figure><img src=\"data:image/png;base64,iVBORw==\" alt=\"Okno &lt;główne&gt;\"><figcaption>"))
        for bad in ["../../poza.png", "../img/brak.png", "https://example.invalid/a.png", "/etc/x.png", "../img/okno.svg"] {
            let h = UserManual.html(markdown: "![Opis](\(bad))", imageBase: pl)
            #expect(h.contains("<p class=\"missing\">") && !h.contains("<img"), "\(bad)")
        }
        #expect(!UserManual.html(markdown: "![Opis](../img/okno.png)").contains("<img"))
    }

    @MainActor @Test("Rozdział skrótów z rejestru i keymapy; komenda pomocy")
    func shortcuts() async throws {
        let ws = Workspace()
        let ch = UserManual.shortcutsChapter(commands: ws.registry.commands.filter { !$0.isPlanned }.map(\.descriptor), chords: { ws.keymap.chords(for: $0) })
        #expect(ch.html.contains("<h2>") && ch.html.contains(ws.keymap.chords(for: "sql.execute").first!.displayString))
        #expect(ws.registry.commands.contains { $0.descriptor.id == "help.manual" && !$0.isPlanned })
    }

    @Test("Instrukcja w repozytorium: tłumaczenia bez rozdziałów spoza polskiej; obrazki istnieją i są używane")
    func repositoryManual() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../docs/manual").standardizedFileURL
        let pl = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("pl").path).filter { $0.hasSuffix(".md") }.sorted()
        #expect(pl.count >= 10)
        // Rozdział jeszcze nieprzetłumaczony wyświetla się po polsku; plik bez polskiego odpowiednika to błąd nazwy.
        var referenced: Set<String> = []
        for lang in UserManual.languages {
            let dir = root.appendingPathComponent(lang)
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path).filter({ $0.hasSuffix(".md") }) else { continue }
            #expect(Set(files).isSubset(of: Set(pl)), "Rozdziały \(lang) spoza polskiej instrukcji: \(Set(files).subtracting(pl).sorted())")
            for f in files {
                let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
                for m in text.matches(of: #/!\[[^\]]*\]\(([^)\s]+)\)/#) {
                    let target = dir.appendingPathComponent(String(m.1)).standardizedFileURL
                    #expect(fm.fileExists(atPath: target.path), "\(lang)/\(f): brak obrazka \(m.1)")
                    referenced.insert(target.lastPathComponent)
                }
            }
        }
        // Katalog img trafia do pakietu aplikacji — bez plików, których żaden rozdział nie pokazuje.
        let images = (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("img").path)) ?? []
        #expect(Set(images.filter { !$0.hasPrefix(".") }).isSubset(of: referenced), "Nieużywane obrazki: \(Set(images).subtracting(referenced).sorted())")
    }
}
