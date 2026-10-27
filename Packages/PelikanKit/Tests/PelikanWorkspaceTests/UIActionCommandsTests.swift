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
}
