import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Zawartość kodu w każdym oknie z kodem (D199): stan panelu w oknie, domyślny z Ustawień, workset i odzyskiwanie,
/// komenda `view.codeContents` w oknie programu, SQL i testu, brak panelu w konsoli SQL*Plus.
@MainActor
@Suite("Zawartość kodu w oknach")
struct CodeContentsWindowTests {
    @Test("okno bez własnego wyboru idzie za Ustawieniami; wybór w oknie wygrywa")
    func defaultFromSettings() {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let sql = ws.newDocument(.sql)
        #expect(sql.codeContentsVisible == nil)
        #expect(ws.showsCodeContents(sql))
        ws.settings.showCodeContents = false
        #expect(!ws.showsCodeContents(sql))
        sql.codeContentsVisible = true
        #expect(ws.showsCodeContents(sql))
        ws.settings.showCodeContents = true
        sql.codeContentsVisible = false
        #expect(!ws.showsCodeContents(sql))
    }

    @Test("komenda przełącza panel tylko w aktywnym oknie programu, SQL i testu")
    func toggleActiveWindow() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.settings.showCodeContents = false
        let program = ws.newDocument(.program)
        let test = ws.newDocument(.test)
        let sql = ws.newDocument(.sql)
        for doc in [sql, test, program] {
            ws.activate(doc.id)
            let r = try await ws.invoke("view.codeContents")
            #expect(r.value == .bool(true))
            #expect(doc.codeContentsVisible == true && ws.showsCodeContents(doc))
        }
        ws.activate(sql.id)
        try await ws.invoke("view.codeContents")
        #expect(!ws.showsCodeContents(sql))
        // Inne okna i ustawienie domyślne bez zmian.
        #expect(ws.showsCodeContents(program) && ws.showsCodeContents(test))
        #expect(!ws.settings.showCodeContents)
        // Jawny stan argumentem (makra, scenariusze zrzutów).
        try await ws.invoke("view.codeContents", CommandArguments(["visible": .bool(true)]))
        try await ws.invoke("view.codeContents", CommandArguments(["visible": .bool(true)]))
        #expect(sql.codeContentsVisible == true)
    }

    @Test("konsola SQL*Plus, plan, raport i diagram bez panelu — komenda niedostępna")
    func noPanelWindows() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        for kind in [DocumentKind.command, .explainPlan, .report, .diagram, .notebook] {
            let doc = ws.newDocument(kind)
            ws.activate(doc.id)
            #expect(!kind.hasCodeContents)
            #expect(!ws.showsCodeContents(doc))
            #expect(!ws.isEnabled("view.codeContents"))
            await #expect(throws: CommandError.self) { try await ws.invoke("view.codeContents") }
            #expect(doc.codeContentsVisible == nil)
        }
        #expect(Set(DocumentKind.allCases.filter(\.hasCodeContents)) == [.sql, .program, .test])
    }

    @Test("stan panelu w worksecie i w migawce odzyskiwania; starszy workset — domyślne")
    func workset() throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let hidden = ws.newDocument(.sql, text: "select 1 from dual")
        hidden.codeContentsVisible = false
        let shown = ws.newDocument(.test, text: "begin null; end;")
        shown.codeContentsVisible = true
        let plain = ws.newDocument(.program, text: "create procedure p is begin null; end;")
        hidden.isModified = true
        let snap = ws.worksetSnapshot(name: "X")
        #expect(snap.documents.map(\.codeContents) == [false, true, nil])
        #expect(ws.recoverySnapshot().documents.first?.codeContents == false)

        let data = try JSONEncoder().encode(snap)
        let back = Workspace(secrets: MemorySecretStore(), drivers: [:])
        back.appendWorksetDocuments(try JSONDecoder().decode(Workset.self, from: data))
        #expect(back.documents.map(\.codeContentsVisible) == [false, true, nil])
        _ = plain

        let json = #"{"name":"X","documents":[{"kind":"sql","text":"x","modified":true,"selectionStart":0,"selectionEnd":0}],"saved":0}"#
        let older = try JSONDecoder().decode(Workset.self, from: Data(json.utf8))
        #expect(older.documents.first?.codeContents == nil)
        let w = Workspace(secrets: MemorySecretStore(), drivers: [:])
        w.appendWorksetDocuments(older)
        #expect(w.documents.first?.codeContentsVisible == nil)
    }

    @Test("komendy elementu w oknie SQL działają na zarysie skryptu (polecenia SQL)")
    func sqlWindowElementCommands() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let text = "select * from emp;\n\nupdate dept set loc = 'X';\n\nbegin\n  null;\nend;\n/\n"
        let doc = ws.newDocument(.sql, text: text)
        let at = (text as NSString).range(of: "update").location
        let r = try await ws.invoke("codeContents.copy", CommandArguments(["offset": .int(Int64(at))]))
        #expect(r.value == .string("update dept set loc = 'X';\n"))
        try await ws.invoke("codeContents.select", CommandArguments(["offset": .int(0)]))
        #expect(doc.selectedRange == 0..<("select * from emp;\n" as NSString).length)
        #expect(CodeContents.outline(text, kind: .sql).map(\.kind) == [.statement, .statement, .block])
        // Okno programu — zarys PL/SQL bez poleceń SQL.
        #expect(CodeContents.outline(text, kind: .program).map(\.kind) == [.block])
    }

    @Test("filtr nazw dopasowuje polecenie SQL także po dalszym tekście")
    func statementFilter() {
        let nodes = PLSQLOutline.parseScript("select * from emp;\nselect * from dept;\n")
        #expect(CodeContents.filtered(nodes, matching: "dept").map(\.detail) == ["* from dept"])
        #expect(CodeContents.filtered(nodes, matching: "SELECT").count == 2)
    }
}
