import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

@MainActor
@Suite("Narzędzia na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ToolsTests {
    func workspace() throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    @Test("Compile Invalid Objects: lista, kompilacja w kolejności zależności, błędy obiektu, który nadal jest niepoprawny")
    func compileInvalid() async throws {
        let (ws, id) = try workspace()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        for sql in ["create table pelikan_inv_t (a number)",
                    "create or replace view pelikan_inv_v as select a from pelikan_inv_t",
                    "create or replace procedure pelikan_inv_ok as v number; begin select count(*) into v from pelikan_inv_v; end;",
                    "create or replace procedure pelikan_inv_bad as begin pelikan_inv_brak; end;",
                    "alter table pelikan_inv_t add (b number)"] {
            _ = try? await s.execute(sql)
        }
        let listed = try await ws.invoke("tools.compileInvalid")
        let names = (listed.value?.arrayValue ?? []).compactMap(\.stringValue)
        #expect(names.contains { $0.hasSuffix(".PELIKAN_INV_BAD") })
        let r = try await ws.invoke("tools.compileInvalid", CommandArguments(["run": .bool(true)]))
        // Schemat testowy może mieć inne niepoprawne obiekty (np. z testów ręcznych) — sprawdzamy własne.
        let failed = (r.value?.arrayValue ?? []).filter { $0.objectValue?["object"]?.stringValue?.contains("PELIKAN_INV_") == true }
        #expect(failed.count == 1)
        #expect(failed.first?.objectValue?["object"]?.stringValue?.hasSuffix("PELIKAN_INV_BAD") == true)
        #expect(failed.first?.objectValue?["errors"]?.arrayValue?.first?.stringValue?.contains("PLS-00201") == true)
        let m = ws.metadata()!
        let still = try await InvalidObjects.list(m, owner: try await m.currentSchema()).map(\.name)
        #expect(!still.contains("PELIKAN_INV_OK") && !still.contains("PELIKAN_INV_V"))
        for o in ["view pelikan_inv_v", "table pelikan_inv_t purge", "procedure pelikan_inv_ok", "procedure pelikan_inv_bad"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }

    @Test("Find Database Objects: tekst, całe słowa, regex, wielkość liter, widoki, nazwy")
    func find() async throws {
        let (ws, id) = try workspace()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        _ = try? await s.execute("""
            create or replace procedure pelikan_find_p as
              v_Znacznik_Xyz number;
            begin
              v_Znacznik_Xyz := 1; -- Znacznik_Xyz_Inny
            end;
            """)
        _ = try? await s.execute("create or replace view pelikan_find_v as select 'Znacznik_Xyz' x from dual")
        let m = ws.metadata()!
        var c = DatabaseSearchCriteria(text: "znacznik_xyz")
        let all = try await DatabaseSearch.search(c, metadata: m)
        #expect(all.filter { $0.object.name == "PELIKAN_FIND_P" }.map(\.line) == [2, 4])
        #expect(all.contains { $0.object.name == "PELIKAN_FIND_V" && $0.object.type == .view })
        c.caseSensitive = true
        #expect(try await DatabaseSearch.search(c, metadata: m).filter { $0.object.name == "PELIKAN_FIND_P" }.isEmpty)
        c.caseSensitive = false
        c.text = "v_znacznik"
        c.wholeWords = true
        #expect(try await DatabaseSearch.search(c, metadata: m).filter { $0.object.name == "PELIKAN_FIND_P" }.isEmpty)
        c.wholeWords = false
        c.text = "znacznik_xyz_[a-z]+"
        c.regularExpression = true
        #expect(try await DatabaseSearch.search(c, metadata: m).filter { $0.object.name == "PELIKAN_FIND_P" }.map(\.line) == [4])
        let byName = try await ws.invoke("tools.findObjects", CommandArguments(["text": .string("pelikan_find_")]))
        #expect((byName.value?.arrayValue ?? []).contains { $0.objectValue?["text"]?.stringValue == "nazwa obiektu" })
        for o in ["procedure pelikan_find_p", "view pelikan_find_v"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Otwieranie obiektu na linii", .enabled(if: TestDatabase.isAvailable), .serialized)
struct OpenObjectLineTests {
    @Test("Linia ciała pakietu w oknie ze specyfikacją i ciałem")
    func openLine() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try? await s.execute("create or replace package pelikan_line_p as procedure a; end;")
        _ = try? await s.execute("create or replace package body pelikan_line_p as\n  procedure a is\n  begin\n    null; -- cel\n  end;\nend;")
        let schema = try await ws.metadata()!.currentSchema()
        try await ws.openObject(DBObject(owner: schema, name: "PELIKAN_LINE_P", type: .packageBody, status: "VALID"), line: 4)
        let doc = try #require(ws.activeDocument)
        let ns = doc.text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: doc.selectedRange.lowerBound, length: 0))
        #expect(ns.substring(with: lineRange).contains("-- cel"))
        for o in ["package pelikan_line_p"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}
