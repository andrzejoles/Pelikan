import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

@MainActor
@Suite("Okno testu na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct TestWindowTests {
    @Test("Test z Object Browsera: notacja nazwana, IN OUT, OUT, wynik funkcji; kursor; BOOLEAN; stos błędu")
    func testWindow() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await s.execute("""
            create or replace function pelikan_tw_f(p_a number, p_b in out varchar2, p_c out date) return number is
            begin
              p_b := p_b || '!';
              p_c := date '2024-01-02';
              return p_a * 2;
            end;
            """)
        _ = try await s.execute("""
            create or replace package pelikan_tw_p as procedure boom; end;
            """)
        _ = try await s.execute("""
            create or replace package body pelikan_tw_p as
              procedure boom is
              begin
                raise_application_error(-20001, 'awaria testowa');
              end;
            end;
            """)
        try await ws.invoke("ob.test", CommandArguments(["object": .string("pelikan_tw_f")]))
        let doc = try #require(ws.activeDocument)
        #expect(doc.kind == .test)
        #expect(doc.text.contains(":result := ") && doc.text.contains("p_a => :p_a") && doc.text.contains("p_c => :p_c"))
        #expect(doc.testVariables.map(\.name) == ["result", "p_a", "p_b", "p_c"])
        #expect(doc.testVariables.map(\.type) == [.integer, .integer, .plsqlString, .date])
        doc.testVariables[1].value = "21"; doc.testVariables[1].isNull = false
        doc.testVariables[2].value = "x"; doc.testVariables[2].isNull = false
        let r = try await ws.invoke("sql.execute")
        #expect(r.value?.objectValue?["result"]?.stringValue == "42")
        #expect(doc.testVariables[2].value == "x!" && doc.testVariables[2].changed)
        #expect(doc.testVariables[3].value.hasPrefix("2024-01-02"))
        #expect(!doc.testVariables[1].changed)

        let cur = ws.newDocument(.test, text: "begin\n  open :c for select level n from dual connect by level <= 3;\n  :b := 1 = 1;\nend;")
        TestRunner.synchronize(cur)
        cur.testVariables[0].type = .cursor
        cur.testVariables[1].type = .boolean
        try await ws.invoke("sql.execute")
        #expect(cur.testVariables[0].cursorColumns == ["N"] && cur.testVariables[0].cursorRows.map { $0.first ?? "" } == ["1", "2", "3"])
        #expect(cur.testVariables[1].value.lowercased() == "true")

        let err = ws.newDocument(.test, text: "begin\n  null;\n  pelikan_tw_p.boom;\nend;")
        await #expect(throws: OracleError.self) { try await ws.invoke("sql.execute") }
        #expect(err.errorStack.contains { $0.unit == "PELIKAN_TW_P" && $0.line == 4 })
        #expect(err.errorStack.contains { $0.unit.isEmpty && $0.line == 3 })
        #expect(err.errorRange != nil)

        for o in ["function pelikan_tw_f", "package pelikan_tw_p"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Profiler i statystyki okna testu", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ProfilerTests {
    @Test("DBMS_PROFILER: linie procedury z liczbą wykonań; DBMS_HPROF: funkcje z wywołaniami; statystyki sesji")
    func profilers() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await s.execute("""
            create or replace procedure pelikan_prof_p(n number) is
              v number := 0;
            begin
              for i in 1 .. n loop
                v := v + sqrt(i);
              end loop;
            end;
            """)
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_prof_p(100);\nend;")
        try await ws.invoke("test.profiler", CommandArguments(["kind": .string("lines")]))
        try await ws.invoke("sql.execute")
        let lines = try #require(doc.profilerReport?.lines)
        let loopLine = lines.first { $0.unitName == "PELIKAN_PROF_P" && $0.line == 5 }
        #expect(loopLine?.occurrences == 100)
        #expect(loopLine?.text.contains("sqrt") == true)
        #expect(!doc.statistics.isEmpty)

        try await ws.invoke("test.profiler", CommandArguments(["kind": .string("hierarchical")]))
        try await ws.invoke("sql.execute")
        let f = try #require(doc.profilerReport?.functions)
        #expect(f.contains { $0.module == "PELIKAN_PROF_P" && $0.calls == 1 })
        #expect(doc.profilerReport?.kind == .hierarchical)
        _ = try? await s.execute("drop procedure pelikan_prof_p")
        await ws.sessions.disconnectAll()
    }
}
