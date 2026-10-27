import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Czwarta runda przeglądu (D189), grupa debuger i edytory obiektów — testy bez bazy.
@MainActor
@Suite("Przegląd 4: debuger, kompilator, edytory obiektów (bez bazy)")
struct Review4DebugEditorsTests {
    @Test("Nagłówek CREATE OR REPLACE w osobnej linii: linia 1 źródła to linia słowa typu (WS2-10)")
    func sourceLineOfUnit() throws {
        let text = "CREATE OR REPLACE\nPACKAGE pkg AS\n  procedure p;\nEND;\n/\n-- ciało\nCREATE OR REPLACE /* x */\n\n  PACKAGE BODY pkg AS\n  procedure p is begin null; end;\nEND;\n/\nCREATE OR REPLACE PROCEDURE q IS BEGIN NULL; END;\n/\n"
        let u = ProgramCompiler.units(in: text)
        #expect(u.count == 3)
        #expect(u[0].line == 0 && u[0].sourceLine == 1 && u[0].sourceColumn == 0)
        #expect(u[1].sourceLine == 8 && u[1].sourceColumn == 2)
        #expect(u[2].sourceLine == u[2].line && u[2].sourceColumn == "CREATE OR REPLACE ".count)
        // ALL_ERRORS linia 2 ciała → linia dokumentu 10 (od 1); linia 1 — kolumna przesunięta o wcięcie nagłówka.
        let p2 = u[1].documentPosition(line: 2, column: 5), p1 = u[1].documentPosition(line: 1, column: 1)
        #expect(p2.line == 10 && p2.column == 5)
        #expect(p1.line == 9 && p1.column == 3)
        #expect(u[2].documentPosition(line: 1, column: 11).column == 11 + "CREATE OR REPLACE ".count)
    }

    @Test("Punkt przerwania w oknie programu liczony od linii słowa typu; linia CREATE nad nim — bez punktu (WS2-10)")
    func breakpointLineInProgram() throws {
        let ws = Workspace()
        let doc = ws.newDocument(.program, text: "CREATE OR REPLACE\nPROCEDURE p IS\nBEGIN\n  NULL;\nEND;\n/\n")
        #expect(ws.breakpointAt(document: doc, line: 4)?.line == 3)
        #expect(ws.breakpointAt(document: doc, line: 1) == nil)
    }

    @Test("Wczytanie punktów: lista warunków do potwierdzenia, wczytanie bez warunków; komenda bez interfejsu pomija warunki (WS2-21)")
    func breakpointConditionsOnImport() async throws {
        let ws = Workspace()
        var bp = Breakpoint(owner: "HR", unit: "PKG", type: .packageBody, line: 3)
        bp.condition = "pkg_audyt.zapisz(1) = 1"
        bp.message = "v={v}"
        ws.breakpoints = [bp, Breakpoint(owner: "HR", unit: "PKG", type: .packageBody, line: 5)]
        let data = try ws.exportBreakpoints()
        #expect(Workspace.breakpointConditions(in: data) == ["pkg_audyt.zapisz(1) = 1"])
        ws.breakpoints = []
        #expect(try ws.importBreakpoints(data, replace: true, keepConditions: false) == 2)
        #expect(ws.breakpoints.allSatisfy { $0.condition == nil } && ws.breakpoints.first?.message == "v={v}")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bp-\(UUID().uuidString.prefix(6)).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        ws.breakpoints = []
        try await ws.invoke("debug.loadBreakpoints", CommandArguments(["file": .string(url.path), "replace": .bool(true)]))
        #expect(ws.breakpoints.count == 2 && ws.breakpoints.allSatisfy { $0.condition == nil })
    }

    @Test("Wykonanie SQL w sesji debugowanej — komenda rejestru bez dostępu agenta, na wstążce (APP2-06)")
    func executeInTargetCommand() throws {
        let ws = Workspace()
        let c = try #require(ws.registry.command("debug.executeInTarget"))
        #expect(c.descriptor.agentAccess == .none && c.descriptor.effect == .modifiesDatabase)
        #expect(!ws.isEnabled("debug.executeInTarget"))
        #expect(RibbonModel.expand(RibbonModel.tabs.flatMap(\.commands), in: ws.registry).contains("debug.executeInTarget"))
    }

    @Test("Zmiana nazwy widoku: najpierw CREATE nowego, potem DROP starego (WS2-04)")
    func viewRenameOrder() {
        let original = ["name": "V_STARY", "query": "select 1 x from dual", "force": "N", "readOnly": "N", "checkOption": "N", "comments": ""]
        var e = SimpleObjectEditor(kind: .view, owner: "HR", values: original, original: original)
        #expect(e.statements().isEmpty)
        e.values["name"] = "v_nowy"
        let sql = e.statements()
        #expect(sql.count >= 2 && sql[0].hasPrefix("CREATE OR REPLACE VIEW") && sql[1] == "DROP VIEW HR.V_STARY")
    }

    @Test("Słownik kolumn tabeli bez kolumn z 23ai (DATA_DEFAULT_VC), wariant 11g bez kolumn 12c; więzy z SEARCH_CONDITION (WS2-03)")
    func tableDictionaryQueries() {
        #expect(TableDDL.columnQueries.count == 2)
        #expect(TableDDL.columnQueries.allSatisfy { !$0.lowercased().contains("_vc") && $0.contains("c.data_default") })
        let v11 = TableDDL.columnQueries[1].lowercased()
        #expect(!v11.contains("default_on_null") && !v11.contains("identity_column") && !v11.contains("user_generated"))
        #expect(!TableDDL.constraintQuery.lowercased().contains("_vc") && !TableDDL.constraintQuery.lowercased().contains(" join "))
    }

    @Test("Query Builder: przecinek w literale q'[…]' i w komentarzu nie dzieli listy SELECT (WS2-19)")
    func queryBuilderSelectList() throws {
        let cols = [SchemaColumn(name: "EMPNO", type: "NUMBER")]
        let m = try #require(QueryModel.parse("select q'[a',b]' as napis, /* x, y */ e.empno from emp e", resolve: { o, n in (o ?? "HR", n, cols) }))
        #expect(m.fields.count == 2)
        #expect(m.fields.first?.expression.hasPrefix("q'[a',b]'") == true)
    }
}
