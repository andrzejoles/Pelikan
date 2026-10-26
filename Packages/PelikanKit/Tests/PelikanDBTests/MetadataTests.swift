import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Metadane słownika na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct MetadataTests {
    func provider() throws -> (Workspace, MetadataProvider) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, ws.metadata()!)
    }

    @Test("Foldery wg wersji (MLE i domeny na 23ai+), obiekty schematu, niepoprawny pakiet, filtr nazw i Status=")
    func objects() async throws {
        let (ws, m) = try provider()
        let types = try await m.availableTypes()
        #expect(types.contains(.mleModule) && types.contains(.domain))
        let schema = try await m.currentSchema()
        let tables = try await m.objects(.table, owner: schema)
        #expect(Set(tables.map(\.name)).isSuperset(of: ["DEPT", "EMP", "DOCS", "BIG_ROWS"]))
        let bodies = try await m.objects(.packageBody, owner: schema)
        #expect(bodies.first { $0.name == "BROKEN_PKG" }?.isValid == false)
        #expect(try await m.objects(.table, owner: schema, filter: ObjectFilter("DE%, emp", contains: false)).map(\.name).sorted() == ["DEPT", "EMP", "EMP_AUDIT"])
        // Domyślnie fragment nazwy (%tekst%); jawny % — wzorzec bez zmian.
        let contains = try await m.objects(.table, owner: schema, filter: ObjectFilter("mp_aud")).map(\.name)
        #expect(contains == ["EMP_AUDIT"])
        #expect(try await m.objects(.table, owner: schema, filter: ObjectFilter("mp_aud%")).isEmpty)
        // Schemat testowy jest wspólny: inny test może mieć chwilowo niepoprawne ciało — liczy się filtr, nie lista.
        let invalid = try await m.objects(.packageBody, owner: schema, filter: ObjectFilter("status=invalid"))
        #expect(invalid.map(\.name).contains("BROKEN_PKG") && invalid.allSatisfy { !$0.isValid } && !invalid.map(\.name).contains("EMP_API"))
        #expect(try await m.objects(.package, owner: schema, filter: ObjectFilter("source=raise_salary")).map(\.name).contains("EMP_API"))
        #expect(!(try await m.objects(.package, owner: schema, filter: ObjectFilter("source=raise_salary")).map(\.name).contains("BROKEN_PKG")))
        #expect(try await m.objects(.mleModule, owner: schema).map(\.name).contains("GREET_MOD"))
        #expect(try await m.objects(.domain, owner: schema).map(\.name) == ["EMAIL_D"])
        #expect(try await m.users().contains(schema))
        await ws.sessions.disconnectAll()
    }

    @Test("Elementy tabeli i pakietu: kolumny z typami, PK/FK, indeksy, wyzwalacz, podprogramy, zależności")
    func children() async throws {
        let (ws, m) = try provider()
        let schema = try await m.currentSchema()
        let emp = DBObject(owner: schema, name: "EMP", type: .table)
        let c = try await m.children(of: emp)
        #expect(c.contains { $0.kind == .column && $0.name == "EMPNO" && $0.detail.hasPrefix("NUMBER(6)") && $0.detail.contains("NOT NULL") })
        #expect(c.contains { $0.kind == .constraint && $0.detail.hasPrefix("PRIMARY KEY") })
        #expect(c.contains { $0.kind == .constraint && $0.detail.hasPrefix("FOREIGN KEY") })
        #expect(c.contains { $0.kind == .trigger && $0.name == "EMP_SAL_TRG" })
        #expect(c.contains { $0.kind == .referencedBy && $0.name.hasSuffix("EMP_API") })
        let pkg = try await m.children(of: DBObject(owner: schema, name: "EMP_API", type: .package))
        #expect(pkg.contains { $0.kind == .subprogram && $0.name == "RAISE_SALARY" })
        await ws.sessions.disconnectAll()
    }

    @Test("Źródło (CREATE OR REPLACE), DDL z DBMS_METADATA, właściwości, wyszukanie po nazwie, Recent")
    func sourceDDL() async throws {
        let (ws, m) = try provider()
        let schema = try await m.currentSchema()
        let spec = DBObject(owner: schema, name: "EMP_API", type: .package)
        let src = try await m.source(of: spec)
        #expect(src.uppercased().hasPrefix("CREATE OR REPLACE PACKAGE EMP_API"))
        let ddl = try await m.ddl(of: DBObject(owner: schema, name: "DEPT", type: .table))
        #expect(ddl.contains("CREATE TABLE") && ddl.contains("\"DEPT\"") && ddl.hasSuffix(";"))
        let props = try await m.properties(of: DBObject(owner: schema, name: "DEPT", type: .table))
        #expect(props.contains { $0.0 == "STATUS" && $0.1 == "VALID" })
        let found = try await m.find("emp_api")
        #expect(found?.type == .package)
        m.touch(spec)
        #expect(m.recent.first == spec)
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Komendy Object Browsera na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ObjectCommandTests {
    func make() throws -> (Workspace, TestUI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, ui)
    }

    @Test("Pokaż dane, Edytuj dane (ROWID, tryb edycji), DDL, Opis, Właściwości, Edytuj program (spec + ciało)")
    func readCommands() async throws {
        let (ws, ui) = try make()
        try await ws.invoke("ob.queryData", CommandArguments(["object": .string("dept")]))
        #expect(ws.activeDocument?.results.first?.grid?.rowCount == 4)
        try await ws.invoke("ob.editData", CommandArguments(["object": .string("dept"), "type": .string("TABLE")]))
        #expect(ws.activeDocument?.results.first?.grid?.edit.isEditing == true)
        let ddl = try await ws.invoke("ob.ddl", CommandArguments(["object": .string("emp_v")]))
        #expect(ddl.message?.contains("CREATE OR REPLACE") == true && ddl.message?.contains("VIEW") == true)
        try await ws.invoke("ob.describe", CommandArguments(["object": .string("emp")]))
        #expect(ui.objectInfo?.1.contains { $0.first == "SAL" } == true)
        try await ws.invoke("ob.properties", CommandArguments(["object": .string("emp")]))
        #expect(ui.objectInfo?.1.contains { $0.first == "STATUS" } == true)
        try await ws.invoke("ob.edit", CommandArguments(["object": .string("emp_api"), "type": .string("PACKAGE")]))
        let prog = try #require(ws.activeDocument)
        #expect(prog.kind == .program && prog.title == "emp_api.pck")
        #expect(prog.text.components(separatedBy: "CREATE OR REPLACE").count == 3)       // specyfikacja i ciało
        await ws.sessions.disconnectAll()
    }

    @Test("Rekompiluj: niepoprawny pakiet zostaje niepoprawny, poprawny — VALID; Usuń z potwierdzeniem; agent DDL bez okna")
    func changingCommands() async throws {
        let (ws, ui) = try make()
        let bad = try await ws.invoke("ob.recompile", CommandArguments(["object": .string("broken_pkg"), "type": .string("PACKAGE BODY")]))
        #expect(bad.value == .string("INVALID"))
        let ok = try await ws.invoke("ob.recompile", CommandArguments(["object": .string("emp_api"), "type": .string("PACKAGE")]))
        #expect(ok.value == .string("VALID"))
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: ws.sessions.mainConnectionID!))
        _ = try await s.execute("create or replace view pelikan_tmp_v as select 1 x from dual")
        ui.askAnswer = 1
        await #expect(throws: CommandError.cancelledByUser) { try await ws.invoke("ob.drop", CommandArguments(["object": .string("pelikan_tmp_v")])) }
        ui.askAnswer = 0
        try await ws.invoke("ob.drop", CommandArguments(["object": .string("pelikan_tmp_v")]))
        #expect(try await ws.metadata()!.find("pelikan_tmp_v") == nil)
        let before = ws.documents.count
        let gate = AllowingGate()
        ws.agentGate = gate
        _ = try await ws.invoke("ob.ddl", CommandArguments(["object": .string("dept")]), invoker: .agent(sessionID: "t", agentName: "test"))
        #expect(ws.documents.count == before)
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Kompilacja w oknie programu na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ProgramCompileTests {
    @Test("Błąd w ciele: zatrzymanie, linia dokumentu, ostrzeżenie PLW; poprawka — kompilacja bez błędów; Edytuj z bazy nie jest nieskompilowany")
    func compile() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.program, text: """
            create or replace package pelikan_prog_t as
              function f(p number) return number;
            end;
            /
            create or replace package body pelikan_prog_t as
              function f(p number) return number is
                v number;
              begin
                return p + brak_zmiennej;
              end;
            end;
            /
            """)
        try await ws.invoke("sql.execute")
        let errors = doc.compileMessages.filter { $0.severity == .error }
        #expect(errors.contains { $0.line == 9 && $0.text.contains("PLS-00201") })
        #expect(doc.compileMessages.contains { $0.severity == .warning })       // nieużywana zmienna v (PLW-06009 / PLW-07206)
        #expect(doc.isCompileStale)
        #expect(doc.errorRange != nil)
        doc.text = doc.text.replacingOccurrences(of: "brak_zmiennej", with: "1")
        try await ws.invoke("sql.execute")
        #expect(!doc.compileMessages.contains { $0.severity == .error })
        #expect(!doc.isCompileStale)
        #expect(doc.statusText?.hasPrefix("Skompilowano jednostek: 2") == true)
        try await ws.invoke("ob.edit", CommandArguments(["object": .string("pelikan_prog_t"), "type": .string("PACKAGE")]))
        #expect(ws.activeDocument?.isCompileStale == false)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await s.execute("drop package pelikan_prog_t")
        await ws.sessions.disconnectAll()
    }
}

/// Bramka agenta przepuszczająca wszystko (testy zachowania komend wywołanych przez agenta, bez PelikanAgent).
@MainActor
final class AllowingGate: AgentInvocationGate {
    func authorize(_ command: Command, context: CommandContext) async throws -> CommandArguments { context.arguments }
}
