import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Poprawki trzeciej rundy przeglądu (D182) w edytorze i oknach: jednostki programu w pamięci podręcznej, Zamień jako
/// komendy, To-Do i okno w trakcie wykonania, QBE i Filtr kolumn na karcie wskazanej argumentem.
@MainActor
@Suite("Edytor i okna — przegląd 3")
struct EditorReviewFixesTests {
    let package = """
    create or replace package kadry as procedure a; end;
    /
    create or replace package body kadry as
      procedure a is
      begin
        null;
      end;
    end;
    /
    """

    @Test("Jednostki okna programu liczone raz na zmianę tekstu; wynik z tła trafia do pamięci tylko dla bieżącego tekstu")
    func unitsCache() {
        let doc = Document(kind: .program, ordinal: 1, text: package)
        #expect(doc.programUnits.map(\.type) == [.package, .packageBody])
        let revision = doc.textRevision
        _ = doc.programUnits
        #expect(doc.textRevision == revision)
        // Wynik dla nieaktualnego tekstu jest pomijany, dla bieżącego — używany bez ponownego podziału.
        doc.cacheProgramUnits([], forText: "inny tekst")
        #expect(doc.programUnits.count == 2)
        doc.cacheProgramUnits([], forText: doc.text)
        #expect(doc.programUnits.isEmpty)
        // Zmiana tekstu unieważnia pamięć.
        doc.text += "\ncreate or replace procedure log_it is begin null; end;\n/\n"
        #expect(doc.textRevision == revision + 1)
        #expect(doc.programUnits.map(\.name) == ["KADRY", "KADRY", "LOG_IT"])
        doc.text = doc.text
        #expect(doc.textRevision == revision + 1)
    }

    @Test("Margines okna programu: bez punktów przerwania jednostek — pusto; z punktem — linia w oknie")
    func breakpointLines() {
        let ws = Workspace()
        let doc = ws.newDocument(.program, text: package)
        #expect(ws.breakpointLines(in: doc).isEmpty)
        ws.breakpoints = [Breakpoint(document: UUID(), line: 3)]
        #expect(ws.breakpointLines(in: doc).isEmpty)
        let bp = Breakpoint(unit: "KADRY", type: .packageBody, line: 4)
        ws.breakpoints.append(bp)
        #expect(ws.breakpointLines(in: doc) == [6])
        #expect(ws.breakpointLines(in: doc, onlyUnapplied: true).isEmpty)
        ws.unappliedBreakpoints = [bp.id]
        #expect(ws.breakpointLines(in: doc, onlyUnapplied: true) == [6])
    }

    @Test("Usuń jednostkę: dostępne w oknie programu bez podziału tekstu; bez jednostek — błąd przy wykonaniu")
    func removeUnitValidation() async {
        let ws = Workspace()
        _ = ws.newDocument(.program, text: "-- bez jednostek\n")
        #expect(ws.isEnabled("prog.removeUnit"))
        await #expect(throws: CommandError.self) { try await ws.invoke("prog.removeUnit") }
        _ = ws.newDocument(.sql)
        #expect(!ws.isEnabled("prog.removeUnit"))
    }

    @Test("Zamień i Zamień wszystko jako komendy: ostatnie wyszukiwanie, zaznaczenie, tylko do odczytu, trwające wykonanie")
    func replaceCommands() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.sql, text: "select a from t where a = 1 and a > 0")
        #expect(!ws.isEnabled("edit.replace"))
        var search = TextSearch(pattern: "a")
        search.wholeWords = true
        search.replacement = "b"
        ws.lastSearch = search
        #expect(ws.isEnabled("edit.replace") && ws.isEnabled("edit.replaceAll"))
        // Zaznaczenie nie jest dopasowaniem — tylko przejście do następnego.
        doc.selectedRange = 0..<0
        try await ws.invoke("edit.replace")
        #expect(doc.text == "select a from t where a = 1 and a > 0" && doc.selectedRange == 7..<8)
        try await ws.invoke("edit.replace")
        #expect(doc.text == "select b from t where a = 1 and a > 0" && doc.selectedRange == 22..<23)
        let r = try await ws.invoke("edit.replaceAll")
        #expect(r.value == .int(2) && doc.text == "select b from t where b = 1 and b > 0")
        // Argumenty nadpisują i zapamiętują wyszukiwanie; zakres — zaznaczenie.
        doc.selectedRange = 0..<15
        try await ws.invoke("edit.replaceAll", CommandArguments(["pattern": .string("b"), "replacement": .string("c"), "inSelection": .bool(true)]))
        #expect(doc.text == "select c from t where b = 1 and b > 0" && ws.lastSearch?.replacement == "c")
        doc.isReadOnly = true
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.replaceAll") }
        doc.isReadOnly = false
        doc.isExecuting = true
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.replaceAll") }
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.replace") }
        #expect(doc.text == "select c from t where b = 1 and b > 0")
        doc.isExecuting = false
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.replace", CommandArguments(["pattern": .string("")])) }
    }

    @Test("To-Do: okno w trakcie wykonania nie zmienia tekstu")
    func todoToggleWhileExecuting() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.sql, text: "-- TODO: sprawdzić\nselect 1 from dual")
        doc.isExecuting = true
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.todoToggle", CommandArguments(["line": .int(1)])) }
        #expect(doc.text.hasPrefix("-- TODO"))
        doc.isExecuting = false
        try await ws.invoke("edit.todoToggle", CommandArguments(["line": .int(1)]))
        #expect(doc.text.hasPrefix("-- DONE"))
    }

    @Test("Komendy edycji (komentarz linii, formatowanie, To-Do, snippet) odmawiają w oknie tylko do odczytu i w trakcie wykonania")
    func editCommandsRefuseLockedWindow() async throws {
        let ws = Workspace()
        let original = "select 1 from dual"
        let doc = ws.newDocument(.sql, text: original)
        for (readOnly, executing) in [(true, false), (false, true)] {
            doc.isReadOnly = readOnly
            doc.isExecuting = executing
            for id: CommandID in ["edit.commentLine", "edit.beautify", "edit.uppercase", "edit.todoInsert"] {
                await #expect(throws: CommandError.self, "\(id.rawValue)") { try await ws.invoke(id) }
            }
            #expect(throws: CommandError.self) { try Stage7Commands.insert("x", into: doc) }
            #expect(doc.text == original)
        }
        doc.isReadOnly = false
        doc.isExecuting = false
        try await ws.invoke("edit.commentLine")
        #expect(doc.text.hasPrefix("--"))
    }

    @Test("Filtr kolumn i Pokaż wszystkie kolumny na karcie wskazanej argumentem tab, nie na aktywnej")
    func columnFilterOnTab() async throws {
        let ws = Workspace()
        ws.ui = GridUI()
        let columns = [ColumnInfo(name: "EMPNO", type: .number, typeName: "NUMBER"), ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2(10)")]
        func tab() async -> ResultTab {
            let g = ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession([[.number("1"), .text("KING")]]),
                                    sql: "select * from emp", format: ValueFormat())
            await g.fetchAll()
            return ResultTab(title: "t", statementRange: 0..<17, grid: g)
        }
        let first = ws.newDocument(.sql, text: "select * from emp")
        let source = await tab()
        first.results = [source]
        first.activeResultID = source.id
        let second = ws.newDocument(.sql, text: "select * from emp")
        let active = await tab()
        second.results = [active]
        second.activeResultID = active.id
        #expect(ws.activeDocument === second)
        try await ws.invoke("grid.columnFilter", CommandArguments(["names": .string("ename"), "tab": .string(source.id.uuidString)]))
        #expect(source.hiddenColumns == [0] && active.hiddenColumns.isEmpty)
        try await ws.invoke("grid.clearColumnFilter", CommandArguments(["tab": .string(source.id.uuidString)]))
        #expect(source.hiddenColumns.isEmpty)
        await #expect(throws: CommandError.self) {
            try await ws.invoke("grid.columnFilter", CommandArguments(["names": .string("x"), "tab": .string(UUID().uuidString)]))
        }
    }
}
