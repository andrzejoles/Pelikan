import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@Suite("Silnik szablonów")
struct TemplateEngineTests {
    @Test("Zmienne, domyślne, lista, kursor, [[, zmienne wbudowane")
    func engine() {
        let text = "create [Typ=*procedure,function] [Nazwa=x] -- [[uwaga] $DBUSER $DATE\nbegin [#]null; end [Nazwa];"
        let v = TemplateEngine.variables(text)
        #expect(v.map(\.name) == ["Typ", "Nazwa"])
        #expect(v[0].choices == ["procedure", "function"] && v[0].defaultValue == "procedure")
        let date = Date(timeIntervalSince1970: 0)
        let (out, cursor) = TemplateEngine.apply(text, values: ["nazwa": "dodaj"], builtins: TemplateEngine.builtins(databaseUser: "SCOTT", now: date))
        #expect(out.hasPrefix("create procedure dodaj -- [uwaga] SCOTT 1970-01-01\nbegin null; end dodaj;"))
        #expect((out as NSString).substring(from: cursor!).hasPrefix("null;"))
    }
}

@MainActor
@Suite("Komendy szablonów")
struct TemplateCommandTests {
    @Test("Wstawienie w miejscu kursora, nowy program z szablonu, zapis i usunięcie szablonu użytkownika")
    func commands() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-tpl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        #expect(ws.templates.all.contains { $0.folder == "Jednostki programów" && $0.name == "Procedura" })
        let doc = ws.newDocument(.sql, text: "-- a\n")
        doc.selectedRange = 5..<5
        try await ws.invoke("edit.insertTemplate", CommandArguments(["template": .string("DML/update"),
                                                                     "values": .object(["Tabela": .string("emp"), "Kolumna": .string("sal")])]))
        #expect(doc.text == "-- a\nupdate emp t\nset    t.sal = \nwhere  1 = 1;")
        #expect(doc.selectedRange.lowerBound == ("-- a\nupdate emp t\nset    t.sal = " as NSString).length)
        try await ws.invoke("file.newFromTemplate", CommandArguments(["template": .string("Pakiet"), "values": .object(["Nazwa": .string("kadry")])]))
        let prog = try #require(ws.activeDocument)
        #expect(prog.kind == .program && prog.text.contains("create or replace package body kadry as"))
        #expect(ProgramCompiler.units(in: prog.text).count == 2)
        try await ws.invoke("templates.save", CommandArguments(["folder": .string("Moje"), "name": .string("log"), "text": .string("log('[Tekst]');[#]")]))
        #expect(ws.templates.template("Moje/log")?.isBuiltIn == false)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Templates/Moje/log.tpl").path))
        try await ws.invoke("templates.delete", CommandArguments(["template": .string("Moje/log")]))
        #expect(ws.templates.template("Moje/log") == nil)
        await #expect(throws: CommandError.self) { try await ws.invoke("templates.delete", CommandArguments(["template": .string("DML/select")])) }
    }
}

@MainActor
@Suite("Zapis okna programu")
struct ProgramSaveTests {
    @Test("Nazwa i rozszerzenie z jednostki, końcowy ukośnik")
    func save() throws {
        let ws = Workspace()
        let doc = ws.newDocument(.program, text: "create or replace function Licz return number is begin return 1; end;")
        #expect(BuiltinCommands.suggestedFileName(doc) == ("licz", "fnc"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-save-\(UUID().uuidString).fnc")
        defer { try? FileManager.default.removeItem(at: url) }
        try ws.save(doc, to: url)
        #expect(try String(contentsOf: url, encoding: .utf8).hasSuffix("end;\n/\n"))
        let pkg = ws.newDocument(.program, text: "create package p as end;\n/\ncreate package body p as end;\n/\n")
        #expect(BuiltinCommands.suggestedFileName(pkg) == ("p", "pck"))
    }
}
