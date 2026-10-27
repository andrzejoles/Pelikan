import Foundation
@testable import PelikanWorkspace
import Testing

/// Czynności interfejsu przeniesione do rejestru komend (R4-18): przypięcie połączenia okna, czyszczenie ostatnich
/// plików, wszystkie punkty przerwania naraz.
@MainActor
@Suite("Czynności interfejsu jako komendy")
struct UIActionCommandsTests {
    @Test("przypięcie połączenia okna: przełącza i bez własnego połączenia bierze połączenie główne")
    func pinWindowConnection() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.sql)
        #expect(!doc.connectionPinned)
        try await ws.invoke("session.pinWindowConnection")
        #expect(doc.connectionPinned)
        #expect(doc.connectionID == ws.sessions.mainConnectionID)
        try await ws.invoke("session.pinWindowConnection")
        #expect(!doc.connectionPinned)
    }

    @Test("czyszczenie listy ostatnich plików")
    func clearRecent() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.settings.recentFiles = ["/tmp/a.sql", "/tmp/b.sql"]
        try await ws.invoke("file.clearRecent")
        #expect(ws.settings.recentFiles.isEmpty)
    }

    @Test("włącz, wyłącz i usuń wszystkie punkty przerwania")
    func allBreakpoints() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.breakpoints = [Breakpoint(owner: "A", unit: "P", type: .procedure, line: 3), Breakpoint(owner: "A", unit: "P", type: .procedure, line: 7)]
        ws.breakpoints[1].enabled = false
        try await ws.invoke("debug.enableAllBreakpoints")
        #expect(ws.breakpoints.allSatisfy { $0.enabled })
        try await ws.invoke("debug.disableAllBreakpoints")
        #expect(ws.breakpoints.allSatisfy { !$0.enabled })
        #expect(ws.breakpoints.count == 2)
        try await ws.invoke("debug.removeAllBreakpoints")
        #expect(ws.breakpoints.isEmpty)
    }

    @Test("przypinanie nowych okien (Preferencje): okno SQL przypięte do połączenia głównego, bez głównego — nieprzypięte")
    func pinNewWindowsByDefault() {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.settings.pinWindowConnectionsByDefault = true
        let before = ws.newDocument(.sql)
        #expect(!before.connectionPinned && before.connectionID == nil)
        let main = UUID()
        ws.sessions.setMainConnection(main)
        let sql = ws.newDocument(.sql)
        #expect(sql.connectionPinned && sql.connectionID == main)
        #expect(!ws.newDocument(.diagram).connectionPinned)
        ws.settings.pinWindowConnectionsByDefault = false
        #expect(!ws.newDocument(.program).connectionPinned)
    }

    @Test("notatnik: dodanie, przesunięcie, wykres i usunięcie komórki komendami; nie w trakcie wykonania")
    func notebookCells() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.notebook)
        let start = doc.notebook.cells.count
        let added = try await ws.invoke("notebook.addSQLCell", CommandArguments(["text": "select 1 from dual"]))
        #expect(added.value?.intValue == Int64(start))
        try await ws.invoke("notebook.addMarkdownCell", CommandArguments(["text": "# A", "index": 0]))
        #expect(doc.notebook.cells.count == start + 2)
        #expect(doc.notebook.cells[0].kind == .markdown && doc.notebook.cells[0].text == "# A")
        #expect(doc.notebook.cells.last?.text == "select 1 from dual" && doc.isModified)
        let last = doc.notebook.cells.count - 1
        let id = doc.notebook.cells[last].id
        try await ws.invoke("notebook.moveCell", CommandArguments(["index": .int(Int64(last)), "by": -1]))
        #expect(doc.notebook.cells[last - 1].id == id)
        // Wykres tylko z wynikiem zapytania.
        await #expect(throws: CommandError.self) { try await ws.invoke("notebook.toggleChart", CommandArguments(["index": .int(Int64(last - 1))])) }
        var r = NotebookResult()
        r.columns = ["NAZWA", "ILE"]
        r.columnTypes = ["VARCHAR2", "NUMBER"]
        r.rows = [["a", "1"]]
        doc.notebook.cells[last - 1].result = r
        try await ws.invoke("notebook.toggleChart", CommandArguments(["index": .int(Int64(last - 1))]))
        #expect(doc.notebook.cells[last - 1].chart != nil)
        try await ws.invoke("notebook.toggleChart", CommandArguments(["index": .int(Int64(last - 1))]))
        #expect(doc.notebook.cells[last - 1].chart == nil)
        await #expect(throws: CommandError.self) { try await ws.invoke("notebook.removeCell", CommandArguments(["index": 99])) }
        doc.isExecuting = true
        #expect(!ws.isEnabled("notebook.removeCell") && !ws.isEnabled("notebook.moveCell"))
        doc.isExecuting = false
        try await ws.invoke("notebook.removeCell", CommandArguments(["index": .int(Int64(last - 1))]))
        #expect(!doc.notebook.cells.contains { $0.id == id })
        #expect(doc.notebook.cells.count == start + 1)
    }

    @Test("projekt: pliki, notatka, grupa, tekst notatki, opcje i usunięcie elementu komendami — z zapisem pliku")
    func projectItems() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-prj-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("p.prj")
        #expect(!ws.isEnabled("project.addNote"))
        try await ws.invoke("project.new", CommandArguments(["file": .string(url.path)]))
        let a = dir.appendingPathComponent("src/a.sql").path
        let files = try await ws.invoke("project.addFiles", CommandArguments(["files": .array([.string(a), .string(a)])]))
        #expect(files.message?.hasSuffix(": 1") == true, "\(files.message ?? "")")
        #expect(ws.project?.items.map(\.path) == ["src/a.sql"])
        let note = try await ws.invoke("project.addNote", CommandArguments(["text": "do przeglądu"]))
        let noteID = try #require(note.value?.stringValue)
        let fileID = try #require(ws.project?.items.first?.id.uuidString)
        try await ws.invoke("project.setItemGroup", CommandArguments(["item": .string(fileID), "group": "Pakiety"]))
        try await ws.invoke("project.setNote", CommandArguments(["item": .string(noteID), "text": "przejrzane"]))
        await #expect(throws: CommandError.self) {
            try await ws.invoke("project.setNote", CommandArguments(["item": .string(fileID), "text": "x"]))
        }
        try await ws.invoke("project.setOption", CommandArguments(["option": "haltOnFirstError", "value": false]))
        try await ws.invoke("project.setOption", CommandArguments(["option": "beautifyOnBuild", "value": "true"]))
        try await ws.invoke("project.setOption", CommandArguments(["option": "connection", "value": "dev_test"]))
        await #expect(throws: CommandError.self) {
            try await ws.invoke("project.setOption", CommandArguments(["option": "inna", "value": "x"]))
        }
        // Plik projektu zapisany po każdej zmianie.
        let saved = try Project.decode(Data(contentsOf: url))
        #expect(saved.items.first?.group == "Pakiety" && saved.items.last?.note == "przejrzane")
        #expect(!saved.options.haltOnFirstError && saved.options.beautifyOnBuild && saved.options.connection == "dev_test")
        try await ws.invoke("project.setOption", CommandArguments(["option": "connection", "value": ""]))
        try await ws.invoke("project.removeItem", CommandArguments(["item": .string(fileID)]))
        await #expect(throws: CommandError.self) { try await ws.invoke("project.removeItem", CommandArguments(["item": .string(fileID)])) }
        let after = try Project.decode(Data(contentsOf: url))
        #expect(after.items.count == 1 && after.items[0].kind == .note && after.options.connection == nil)
    }

    @Test("snippety: zapis, zmiana nazwy (bez kopii) i usunięcie komendami; wbudowanego nie można usunąć")
    func snippets() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        try await ws.invoke("snippets.save", CommandArguments(["category": "Moje", "name": "A", "text": "select 1 from dual"]))
        #expect(ws.snippets.all.contains { $0.id == "Moje/A" && !$0.isBuiltIn })
        try await ws.invoke("snippets.save", CommandArguments(["category": "Moje", "name": "B", "text": "select 2 from dual", "replaces": "Moje/A"]))
        #expect(!ws.snippets.all.contains { $0.id == "Moje/A" } && ws.snippets.all.contains { $0.id == "Moje/B" })
        try await ws.invoke("snippets.remove", CommandArguments(["id": "Moje/B"]))
        #expect(!ws.snippets.all.contains { $0.id == "Moje/B" })
        let builtIn = try #require(ws.snippets.all.first { $0.isBuiltIn })
        await #expect(throws: CommandError.self) { try await ws.invoke("snippets.remove", CommandArguments(["id": .string(builtIn.id)])) }
    }

    @Test("biblioteka makr: nazwa, skrót (zły odrzucony, pusty usuwa) i usunięcie komendami")
    func macroLibrary() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let m = Macro(name: "M", steps: [.text("x")])
        ws.updateMacros(MacroLibrary(macros: [m]))
        let id = JSONValue.string(m.id.uuidString)
        try await ws.invoke("edit.macroRename", CommandArguments(["macro": id, "name": "Nowa"]))
        #expect(ws.macroLibrary.macros.first?.name == "Nowa")
        #expect(ws.registry.command(m.commandID)?.descriptor.title.contains("Nowa") == true)
        try await ws.invoke("edit.macroSetKey", CommandArguments(["macro": id, "key": "ctrl+shift+9"]))
        #expect(ws.macroLibrary.macros.first?.key == "ctrl+shift+9")
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.macroSetKey", CommandArguments(["macro": id, "key": "nie+skrót+x"])) }
        try await ws.invoke("edit.macroSetKey", CommandArguments(["macro": id, "key": ""]))
        #expect(ws.macroLibrary.macros.first?.key == nil)
        try await ws.invoke("edit.macroRemove", CommandArguments(["macro": id]))
        #expect(ws.macroLibrary.macros.isEmpty && ws.registry.command(m.commandID) == nil)
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.macroRemove", CommandArguments(["macro": id])) }
    }

    @Test("debuger: usunięcie jednego punktu przerwania; czynności panelu tylko przy debugerze okna testu")
    func debuggerPanel() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.breakpoints = [Breakpoint(owner: "A", unit: "P", type: .procedure, line: 3), Breakpoint(owner: "A", unit: "P", type: .procedure, line: 7)]
        let first = ws.breakpoints[0].id
        try await ws.invoke("debug.removeBreakpoint", CommandArguments(["id": .string(first.uuidString)]))
        #expect(ws.breakpoints.count == 1 && !ws.breakpoints.contains { $0.id == first })
        await #expect(throws: CommandError.self) { try await ws.invoke("debug.removeBreakpoint", CommandArguments(["id": .string(first.uuidString)])) }
        #expect(!ws.isEnabled("debug.selectFrame") && !ws.isEnabled("debug.setValue") && !ws.isEnabled("debug.addWatch"))
        _ = ws.newDocument(.test)
        #expect(ws.isEnabled("debug.addWatch") && !ws.isEnabled("debug.setValue"))
        try await ws.invoke("debug.addWatch", CommandArguments(["expression": "v_licznik"]))
        let d = try #require(DebugP2Commands.debugger(ws))
        #expect(d.watches == ["v_licznik"])
        try await ws.invoke("debug.removeWatch", CommandArguments(["expression": "v_licznik"]))
        #expect(d.watches.isEmpty)
    }

    @Test("diagram: przesunięcie, punkty łamania, tekst notatki i kolor komendami kanwy")
    func diagramCanvas() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.diagram)
        doc.diagram.snapToGrid = false
        let noteID = doc.diagram.addNote("a", at: DiagramPoint(16, 16))
        let other = doc.diagram.addNote("b", at: DiagramPoint(400, 16))
        let link = DiagramLink(kind: .manual, from: noteID, to: other)
        doc.diagram.links.append(link)
        let x0 = try #require(doc.diagram.item(noteID)?.frame.x)
        doc.diagramSelection = [noteID]
        try await ws.invoke("diagram.move", CommandArguments(["dx": .double(24), "dy": 8]))
        #expect(doc.diagram.item(noteID)?.frame.x == x0 + 24 && doc.isModified)
        let l = JSONValue.string(link.id.uuidString)
        try await ws.invoke("diagram.addBend", CommandArguments(["link": l, "index": 0, "x": 203, "y": 100]))
        #expect(doc.diagram.links[0].bends == [DiagramPoint(Diagram.snap(203), Diagram.snap(100))])
        await #expect(throws: CommandError.self) { try await ws.invoke("diagram.addBend", CommandArguments(["link": l, "index": 5, "x": 1, "y": 1])) }
        try await ws.invoke("diagram.moveBend", CommandArguments(["link": l, "index": 0, "x": 240, "y": 120]))
        #expect(doc.diagram.links[0].bends == [DiagramPoint(Diagram.snap(240), Diagram.snap(120))])
        try await ws.invoke("diagram.removeBend", CommandArguments(["link": l, "index": 0]))
        #expect(doc.diagram.links[0].bends.isEmpty)
        try await ws.invoke("diagram.editNote", CommandArguments(["item": .string(noteID.uuidString), "text": "nowy"]))
        #expect(doc.diagram.item(noteID)?.text == "nowy")
        doc.diagramSelection = [noteID, link.id]
        let otherColor = doc.diagram.item(other)?.color
        try await ws.invoke("diagram.setColor", CommandArguments(["color": "#FF0000"]))
        #expect(doc.diagram.item(noteID)?.color == RGBColor(hex: "#FF0000") && doc.diagram.links[0].color == RGBColor(hex: "FF0000"))
        #expect(doc.diagram.item(other)?.color == otherColor)
        await #expect(throws: CommandError.self) { try await ws.invoke("diagram.setColor", CommandArguments(["color": "zielony"])) }
        try await ws.invoke("diagram.setColor", CommandArguments(["color": ""]))
        #expect(doc.diagram.item(noteID)?.color == nil)
    }

    @Test("kolejność Code Contents komendą (ustawienie Preferencji)")
    func codeContentsSort() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        try await ws.invoke("codeContents.sort", CommandArguments(["order": "name"]))
        #expect(ws.settings.codeContentsOrder == .name)
        await #expect(throws: CommandError.self) { try await ws.invoke("codeContents.sort", CommandArguments(["order": "x"])) }
    }
}
