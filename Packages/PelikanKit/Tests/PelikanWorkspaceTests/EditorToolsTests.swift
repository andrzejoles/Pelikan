import Foundation
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Narzędzia edytora: makra, Special Copy, schowek, To-Do")
struct EditorToolsTests {
    @Test("Makro: nagrywanie tekstu, poprawek i komend edytora; odtwarzanie wielokrotne; komendy bazy nienagrywane")
    func macros() async throws {
        let ws = Workspace()
        let d = ws.newDocument(.sql, text: "")
        try await ws.invoke("edit.macroRecord")
        #expect(ws.isRecordingMacro)
        ws.recordTyping("selekt")
        for _ in 0..<3 { ws.recordDeleteBackward() }
        ws.recordTyping("ect 1 from dual")
        try await ws.invoke("edit.uppercase")
        try await ws.invoke("edit.macroRecord")
        #expect(!ws.isRecordingMacro)
        let m = try #require(ws.currentMacro)
        #expect(m.steps.count == 2)
        #expect(m.steps.first == .text("select 1 from dual"))
        if case .command(let id, _) = m.steps.last { #expect(id == "edit.uppercase") } else { Issue.record("brak komendy") }

        d.text = "x "
        d.selectedRange = 2..<2
        try await ws.invoke("edit.macroPlay")
        #expect(d.text == "X SELECT 1 FROM DUAL")

        ws.toggleMacroRecording()
        ws.recordTyping("ab;")
        ws.toggleMacroRecording()
        let m2 = try #require(ws.currentMacro)
        d.text = ""
        try await ws.invoke("edit.macroRepeat", CommandArguments(["times": 3]))
        #expect(d.text == "ab;ab;ab;")
        // Odtwarzanie nie nagrywa się w nowe makro i nie zmienia bieżącego.
        #expect(ws.currentMacro == m2 && m2 != m)
    }

    @Test("Biblioteka makr: zapis JSON, komenda ze skrótem, usunięcie")
    func macroLibrary() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-macros-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        let d = ws.newDocument(.sql, text: "")
        ws.toggleMacroRecording()
        ws.recordTyping("abc")
        ws.toggleMacroRecording()
        try await ws.invoke("edit.macroSave", CommandArguments(["name": "ABC", "key": "ctrl+alt+shift+9"]))
        let m = try #require(ws.macroLibrary.macros.first)
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+alt+shift+9")!) == m.commandID)
        try await ws.invoke(m.commandID)
        #expect(d.text == "abc")
        let reloaded = Workspace(dataDirectory: dir)
        #expect(reloaded.macroLibrary.macros.map(\.name) == ["ABC"] && reloaded.registry.command(m.commandID) != nil)
        reloaded.updateMacros(MacroLibrary())
        #expect(reloaded.registry.command(m.commandID) == nil)
    }

    @Test("Special Copy i wklejanie z języka: pętla dla każdego formatu, escapy, wykrywanie stylu")
    func specialCopy() {
        let sql = "select 'a\"b' x, '\\n' y\n  from dual\nwhere a = 'It''s'"
        for f in CopyFormat.builtIn {
            let code = f.copy(sql)
            #expect(f.paste(code) == sql, "\(f.id): \(code)")
        }
        let java = CopyFormat.builtIn.first { $0.id == "java" }!.copy("select 1\nfrom dual")
        #expect(java == "String sql = \"select 1\\n\" +\n    \"from dual\";")
        let delphi = CopyFormat.builtIn.first { $0.id == "delphi" }!.copy("select 'x'\nfrom dual")
        #expect(delphi == "SQL := 'select ''x''' + sLineBreak +\n  'from dual';")
        #expect(CopyFormat.pasteDetecting(java) == "select 1\nfrom dual")
        #expect(CopyFormat.pasteDetecting(delphi) == "select 'x'\nfrom dual")
        #expect(CopyFormat.pasteDetecting("Dim s = \"say \"\"hi\"\"\" & _\n  \"x\"") == "say \"hi\"\nx")
    }

    @Test("Komendy Special Copy i Paste from host language; formaty z plików katalogu danych")
    func specialCopyCommands() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-copy-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let formats = dir.appendingPathComponent("CopyFormats")
        try FileManager.default.createDirectory(at: formats, withIntermediateDirectories: true)
        let kotlin = CopyFormat(id: "kotlin", name: "Kotlin", firstPrefix: "val sql = ", linePrefix: "    ", lineSuffix: " +", lastSuffix: "",
                                quote: "\"", escapes: [["\\", "\\\\"], ["\"", "\\\""], ["$", "\\$"]], newline: "\\n")
        try JSONEncoder().encode(kotlin).write(to: formats.appendingPathComponent("kotlin.json"))
        let ws = Workspace(dataDirectory: dir)
        let d = ws.newDocument(.sql, text: "select $x from dual")
        let r = try await ws.invoke("edit.specialCopy.kotlin")
        #expect(r.value == .string("val sql = \"select \\$x from dual\""))
        d.text = ""
        try await ws.invoke("edit.pasteHostLanguage", CommandArguments(["text": "String s = \"a\\n\" +\n \"b\";"]))
        #expect(d.text == "a\nb")
    }

    @Test("Historia schowka: kolejność, bez duplikatów, limit, filtr słów, wklejanie")
    func clipboard() async throws {
        var h = ClipboardHistory()
        h.limit = 3
        for t in ["select 1", "update emp", "select 1", "  ", "delete dept", "merge x"] { h.add(t) }
        #expect(h.entries.map(\.text) == ["merge x", "delete dept", "select 1"])
        #expect(h.filtered("SEL 1").map(\.text) == ["select 1"])
        let ws = Workspace()
        let d = ws.newDocument(.sql, text: "-- ")
        d.selectedRange = 3..<3
        ws.recordClipboard("one")
        ws.recordClipboard("two")
        try await ws.invoke("edit.pasteFromHistory", CommandArguments(["index": 1]))
        #expect(d.text == "-- one" && ws.clipboardHistory.entries.first?.text == "one")
    }

    @Test("To-Do: składnia z właścicielem, priorytetem i kategorią, tylko komentarze, zamykanie, wstawianie")
    func todo() async throws {
        let text = """
            begin
              -- TODO(anna) !1 #wydajność: indeks na emp
              x := 'TODO: nie zadanie';
              /* DONE: zamknięte
                 todo: druga linia */
              -- to nie TODO
            end;
            """
        let items = TodoItems.parse(text)
        #expect(items.count == 3)
        #expect(items[0].line == 2 && items[0].owner == "anna" && items[0].priority == 1 && items[0].category == "wydajność" && items[0].text == "indeks na emp" && !items[0].closed)
        #expect(items[1].closed && items[1].text == "zamknięte" && items[1].line == 4)
        #expect(items[2].line == 5 && items[2].text == "druga linia")
        let closed = TodoItems.toggle(items[0], in: text)
        #expect(TodoItems.parse(closed)[0].closed)

        let ws = Workspace()
        let d = ws.newDocument(.program, text: "begin\n    null;\nend;")
        d.selectedRange = 10..<10
        try await ws.invoke("edit.todoInsert", CommandArguments(["owner": "jan"]))
        #expect(d.text == "begin\n    -- TODO(jan): \n    null;\nend;")
        try await ws.invoke("edit.todoToggle", CommandArguments(["line": 2]))
        #expect(d.text.contains("-- DONE(jan)"))
    }
}
