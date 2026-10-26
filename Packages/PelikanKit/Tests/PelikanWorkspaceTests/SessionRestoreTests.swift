import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Przywracanie okien po ponownym uruchomieniu (D176): autozapis workseta przy zamknięciu aplikacji obejmuje wszystkie
/// rodzaje okien; okno bez pliku wraca z treścią jako okno bez pliku i z niezapisaną zmianą.
@MainActor
@Suite("Przywracanie okien")
struct SessionRestoreTests {
    @Test("wszystkie rodzaje okien wracają z treścią; bez pliku — nadal bez pliku i ze zmianą; aktywne okno zachowane")
    func roundTrip() async throws {
        let t = try TempDirectory()
        let file = t.url.appendingPathComponent("zapisany.sql")
        try "select 1 from dual;\n".write(to: file, atomically: true, encoding: .utf8)
        let ws = Workspace(dataDirectory: t.url)
        let sql = ws.newDocument(.sql, text: "select * from emp where deptno = 10")
        sql.isModified = true
        sql.selectedRange = 7..<8
        let prog = ws.newDocument(.program, text: "create or replace procedure p is begin null; end;")
        prog.isModified = true
        let test = ws.newDocument(.test, text: "begin :x := 1; end;")
        test.testVariables = [TestVariable(name: "x", type: .integer)]
        test.testWatches = ["l_licznik"]
        let plan = ws.newDocument(.explainPlan, text: "select * from dept")
        let diagram = ws.newDocument(.diagram)
        diagram.diagram.items = [DiagramItem(kind: .note, frame: DiagramRect(x: 10, y: 20, width: 100, height: 40))]
        diagram.isModified = true
        let notebook = ws.newDocument(.notebook)
        notebook.notebook.cells = [NotebookCell(kind: .sql, text: "select 42 from dual")]
        let report = ws.newDocument(.report, text: "select ename from emp")
        report.report = ReportDefinition(title: "Pracownicy", sql: "select ename from emp")
        let saved = try ws.openFile(file)
        ws.activate(prog.id)
        try ws.saveCurrentWorkset()

        let back = Workspace(dataDirectory: t.url)
        let loaded = try #require(try back.worksets.load(back.worksets.current))
        #expect(try await back.applyWorkset(loaded).isEmpty)
        let docs = back.documents
        #expect(docs.map(\.kind) == [.sql, .program, .test, .explainPlan, .diagram, .notebook, .report, .sql])
        #expect(docs[0].text == sql.text && docs[0].fileURL == nil && docs[0].isModified && docs[0].selectedRange == 7..<8)
        #expect(docs[1].text == prog.text && docs[1].fileURL == nil)
        #expect(docs[2].testVariables.map(\.name) == ["x"] && docs[2].testWatches == ["l_licznik"])
        #expect(docs[3].text == plan.text)
        #expect(docs[4].diagram.items.count == 1 && docs[4].fileURL == nil && docs[4].isModified)
        #expect(docs[5].notebook.cells.map(\.text) == ["select 42 from dual"])
        #expect(docs[6].report.title == "Pracownicy")
        #expect(docs[7].fileURL?.standardizedFileURL == saved.fileURL?.standardizedFileURL && !docs[7].isModified && docs[7].text == "select 1 from dual;\n")
        #expect(back.activeDocumentID == docs[1].id)
    }

    @Test("konsola połączenia wraca jako konsola (tekst z magazynu konsol), nie jako zwykłe okno")
    func console() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let def = ConnectionDefinition(name: "dev_konsola", target: ConnectionTarget(user: "u", connectString: "dev"))
        try ws.connections.upsert(def)
        let c = ws.openConsole(connection: def.id)
        c.text = "select 1 from dual"
        c.isModified = true
        ws.persistConsoles()
        try ws.saveCurrentWorkset()
        let back = Workspace(dataDirectory: t.url)
        try await back.applyWorkset(try #require(try back.worksets.load(back.worksets.current)))
        #expect(back.documents.count == 1)
        #expect(back.documents.first?.consoleConnectionID == def.id && back.documents.first?.text == "select 1 from dual")
    }

    @Test("starszy workset bez nowych pól — odczyt bez zmian")
    func oldFormat() throws {
        let json = #"{"name":"Domyślny","documents":[{"kind":"sql","text":"select 1","modified":true,"selectionStart":0,"selectionEnd":0}],"saved":0}"#
        let w = try JSONDecoder().decode(Workset.self, from: Data(json.utf8))
        #expect(w.documents.first?.diagram == nil && w.documents.first?.consoleConnectionID == nil)
    }
}
