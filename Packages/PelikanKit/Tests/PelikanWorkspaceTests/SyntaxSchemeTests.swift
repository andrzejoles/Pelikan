import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@Suite("Motywy kolorowania składni (D227)")
struct SyntaxSchemeTests {
    @Test("Wbudowane: do 100, unikalne identyfikatory i nazwy w trybie, tryb zgodny z tłem, kontrast tekstu i kategorii")
    func builtin() {
        let all = SyntaxScheme.builtin
        #expect(all.count <= 100 && all.count >= 90)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map { "\($0.isDark)|\($0.name)" }).count == all.count)
        #expect(all.filter(\.isDark).count >= 30 && all.filter { !$0.isDark }.count >= 30)
        #expect(all.allSatisfy { $0.isBuiltin })
        for s in all where s.background != nil {
            let bg = s.background!
            #expect(s.isDark == (bg.luminance < 0.4), "\(s.name)")
            #expect(s.text!.contrast(with: bg) >= SyntaxScheme.minimumTextContrast - 0.01, "\(s.name)")
            for style in SyntaxStyle.allCases {
                #expect((s.style(style).color ?? s.text!).contrast(with: bg) >= SyntaxScheme.minimumTokenContrast - 0.01, "\(s.name) \(style)")
            }
        }
        // Domyślny motyw Pelikana: kolory systemu dla tła i tekstu, kategorie sprzed D227.
        #expect(SyntaxScheme.pelikanLight.background == nil && SyntaxScheme.pelikanLight.style(.keyword).color == RGB(hex: "9b2494"))
        #expect(SyntaxScheme.pelikanDark.style(.dataType) == SyntaxScheme.pelikanDark.style(.keyword))
    }

    @Test("Zapis JSON, kopia do edycji, nieznana kategoria pomijana, ustawienia z domyślnymi")
    func codable() throws {
        let solarized = try #require(SyntaxScheme.builtin("builtin.solarized-light"))
        let copy = solarized.copy(named: "Mój")
        #expect(!copy.isBuiltin && copy.name == "Mój" && copy.styles == solarized.styles)
        let back = try JSONDecoder().decode(SyntaxScheme.self, from: try SyntaxSchemeImport.export(copy))
        #expect(back == copy)
        let odd = ##"{"id":"user.x","name":"X","isDark":true,"styles":{"keyword":{"color":"#ff0000","bold":true},"future":{"color":"#00ff00"}}}"##
        let s = try JSONDecoder().decode(SyntaxScheme.self, from: Data(odd.utf8))
        #expect(s.style(.keyword) == TokenStyle(RGB(255, 0, 0), bold: true) && s.styles.count == 1)
        var st = PelikanWorkspace.Settings()
        #expect(st.activeSyntaxScheme(dark: true).id == SyntaxScheme.pelikanDark.id)
        st.customSyntaxSchemes = [copy]
        st.syntaxSchemeLight = copy.id
        let decoded = try JSONDecoder().decode(PelikanWorkspace.Settings.self, from: try JSONEncoder().encode(st))
        #expect(decoded.activeSyntaxScheme(dark: false) == copy)
        st.syntaxSchemeLight = "user.usunięty"
        #expect(st.activeSyntaxScheme(dark: false).id == SyntaxScheme.pelikanLight.id)
    }

    @Test("Import: base16 YAML, Xcode, TextMate i VS Code z komentarzami, przezroczystością i zakresami SQL")
    func importFormats() throws {
        let yaml = """
        system: "base16"
        name: "Próba"
        author: "Ktoś"
        variant: "light"
        palette:
          base00: "#ffffff"  # tło
          base01: "#f0f0f0"
          base02: "#d0d0d0"
          base03: "#999999"
          base04: "#666666"
          base05: "#222222"
          base06: "#111111"
          base07: "#000000"
          base08: "#aa0000"
          base09: "#aa5500"
          base0A: "#886600"
          base0B: "#007700"
          base0C: "#007777"
          base0D: "#0000aa"
          base0E: "#770077"
          base0F: "#553300"
        """
        let b = try SyntaxSchemeImport.scheme(from: Data(yaml.utf8), fileName: "proba.yaml")
        #expect(b.name == "Próba" && !b.isDark && b.style(.keyword).color == RGB(hex: "770077") && !b.isBuiltin)
        #expect(b.style(.comment).italic && b.style(.comment).color!.contrast(with: RGB(255, 255, 255)) >= 3)   // #999 rozjaśniony do 3:1

        let xcode = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
        <key>DVTSourceTextBackground</key><string>0.1 0.1 0.1 1</string>
        <key>DVTSourceTextSelectionColor</key><string>0.3 0.3 0.3 1</string>
        <key>DVTSourceTextSyntaxColors</key><dict>
          <key>xcode.syntax.plain</key><string>1 1 1 1</string>
          <key>xcode.syntax.keyword</key><string>1 0 0.5 1</string>
          <key>xcode.syntax.comment</key><string>0.5 0.5 0.5 1</string>
          <key>xcode.syntax.preprocessor</key><string>1 0.5 0 1</string>
        </dict>
        <key>DVTSourceTextSyntaxFonts</key><dict><key>xcode.syntax.keyword</key><string>SFMono-Bold - 12.0</string></dict>
        </dict></plist>
        """
        let x = try SyntaxSchemeImport.scheme(from: Data(xcode.utf8), fileName: "Mój.xccolortheme")
        #expect(x.isDark && x.name == "Mój" && x.style(.keyword).bold && x.style(.keyword).color == RGB(255, 0, 128))
        #expect(x.style(.directive).color == RGB(255, 128, 0) && x.style(.string).color == RGB(255, 255, 255))

        let tm = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>name</key><string>TM</string><key>settings</key><array>
          <dict><key>settings</key><dict><key>background</key><string>#FDF6E3</string><key>foreground</key><string>#586E75</string></dict></dict>
          <dict><key>scope</key><string>keyword, storage</string><key>settings</key><dict><key>foreground</key><string>#859900</string></dict></dict>
          <dict><key>scope</key><string>keyword.operator</string><key>settings</key><dict><key>foreground</key><string>#657B83</string></dict></dict>
          <dict><key>scope</key><string>comment</string><key>settings</key><dict><key>foreground</key><string>#93A1A1</string><key>fontStyle</key><string>italic</string></dict></dict>
        </array></dict></plist>
        """
        let t = try SyntaxSchemeImport.scheme(from: Data(tm.utf8), fileName: "x.tmTheme")
        #expect(t.name == "TM" && !t.isDark && t.style(.keyword).color == RGB(hex: "859900") && t.style(.operator).color == RGB(hex: "657b83"))
        #expect(t.style(.comment).italic && t.style(.dataType).color == RGB(hex: "859900"))   // storage.type → storage

        let vs = """
        // Motyw VS Code (JSONC)
        { "name": "VS", "type": "dark",
          "colors": { "editor.background": "#1e1e1e", "editor.foreground": "#d4d4d4", "editor.selectionBackground": "#ffffff80", },
          "tokenColors": [
            { "scope": ["keyword.control", "keyword"], "settings": { "foreground": "#c586c0" } },
            { "scope": "support.function", "settings": { "foreground": "#dcdcaa", "fontStyle": "bold" } },
            { "scope": "string", "settings": { "foreground": "#ce9178" } }, /* koniec */
          ] }
        """
        let v = try SyntaxSchemeImport.scheme(from: Data(vs.utf8), fileName: "dark.json")
        #expect(v.isDark && v.name == "VS" && v.style(.keyword).color == RGB(hex: "c586c0") && v.style(.function).bold)
        #expect(v.selection == RGB(hex: "1e1e1e")!.mixed(with: RGB(255, 255, 255), 128.0 / 255))
        // Przecinek na końcu z komentarzem przed zamknięciem (częste w motywach VS Code).
        let jsonc = """
        {"type": "light", "colors": {"editor.background": "#ffffff", // tło
        }, "tokenColors": [{"scope": "keyword", "settings": {"foreground": "#0000ff"}}, /* x */ ]}
        """
        #expect(try SyntaxSchemeImport.scheme(from: Data(jsonc.utf8), fileName: "l.json").style(.keyword).color == RGB(0, 0, 255))
        #expect(throws: SyntaxSchemeImport.Failure.self) { try SyntaxSchemeImport.scheme(from: Data("{}".utf8), fileName: "pusty.json") }
    }

    @Test("Komendy: wybór dla trybu, kopia, zmiana stylu tylko we własnym, usunięcie przywraca domyślny")
    @MainActor func commands() async throws {
        let ws = Workspace()
        _ = try await ws.invoke("editor.syntaxScheme.use", CommandArguments(["scheme": .string("Solarized Dark")]))
        #expect(ws.settings.syntaxSchemeDark == "builtin.solarized-dark")
        await #expect(throws: CommandError.self) {
            _ = try await ws.invoke("editor.syntaxScheme.setStyle", CommandArguments(["scheme": .string("builtin.solarized-dark"), "style": .string("keyword"), "color": .string("#ff0000")]))
        }
        let r = try await ws.invoke("editor.syntaxScheme.duplicate", CommandArguments(["scheme": .string("builtin.solarized-dark"), "name": .string("Mój ciemny")]))
        guard case .object(let o)? = r.value, case .string(let id)? = o["id"] else { Issue.record("brak id"); return }
        _ = try await ws.invoke("editor.syntaxScheme.setStyle", CommandArguments(["scheme": .string(id), "style": .string("keyword"), "color": .string("#ff0000"), "bold": .bool(true)]))
        _ = try await ws.invoke("editor.syntaxScheme.setStyle", CommandArguments(["scheme": .string(id), "style": .string("background"), "color": .string("#000000")]))
        _ = try await ws.invoke("editor.syntaxScheme.use", CommandArguments(["scheme": .string(id)]))
        let mine = ws.settings.activeSyntaxScheme(dark: true)
        #expect(mine.id == id && mine.style(.keyword) == TokenStyle(RGB(255, 0, 0), bold: true) && mine.background == RGB(0, 0, 0))
        #expect(SyntaxScheme.builtin("builtin.solarized-dark")!.style(.keyword).bold == false)
        _ = try await ws.invoke("editor.syntaxScheme.delete", CommandArguments(["scheme": .string(id)]))
        #expect(ws.settings.syntaxSchemeDark == SyntaxScheme.pelikanDark.id && ws.settings.customSyntaxSchemes.isEmpty)
    }
}
