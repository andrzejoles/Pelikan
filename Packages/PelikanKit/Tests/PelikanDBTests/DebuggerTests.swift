import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

@MainActor
@Suite("Debuger na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(1)))
struct DebuggerTests {
    @Test("Start, krok do procedury, kroki, zmienne (liczba, rekord, kolekcja), stos, krok wyjścia, punkt przerwania, koniec")
    func debugSession() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await s.execute("""
            create or replace procedure pelikan_dbg_p(n number, wynik out number) is
              type t_tab is table of number index by pls_integer;
              v number := 0;
              tab t_tab;
              r dept%rowtype;
            begin
              select * into r from dept where rownum = 1;
              for i in 1 .. n loop
                v := v + i;
                tab(i) := v;
              end loop;
              wynik := v;
            end;
            """)
        _ = try await s.execute("alter procedure pelikan_dbg_p compile debug")
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_dbg_p(3, :w);\n  :w := :w + 1;\nend;")
        TestRunner.synchronize(doc)
        doc.testVariables[0].type = .integer
        let schema = try await ws.metadata()!.currentSchema()
        _ = schema
        let d = ws.debugger(for: doc)
        try await d.start()
        print("DBG start", d.location as Any)
        #expect(d.state == .paused)
        #expect(d.location?.isTestBlock == true && d.location?.line == 2)
        try await d.step(.into)
        #expect(d.location?.name == "PELIKAN_DBG_P")
        #expect(d.stack.count >= 2)
        // Kroki do wnętrza pętli po kilku iteracjach.
        for _ in 0..<8 where d.state == .paused { try await d.step(.over) }
        print("DBG at", d.location as Any, d.variables.map { "\($0.name)=\($0.value) \($0.children?.count ?? -1)" })
        #expect(d.variables.contains { $0.name == "v" })
        #expect(d.variables.first { $0.name == "r" }?.children?.contains { $0.name == "deptno" } == true)
        #expect(d.variables.first { $0.name == "tab" }?.children?.isEmpty == false)
        try await d.step(.out)
        #expect(d.location?.isTestBlock == true)
        try await d.step(.run)
        #expect(d.state == .finished)
        #expect(doc.testVariables[0].value == "7")
        _ = try? await s.execute("drop procedure pelikan_dbg_p")
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Debuger: pakiet z wyzwalaczem", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(1)))
struct DebuggerTriggerTests {
    @Test("Krok do pakietu i do wyzwalacza (bez :new), punkt przerwania w bloku, zatrzymanie na wyjątku, typy jednostek na stosie")
    func packageAndTrigger() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        for o in ["table pelikan_dbg_t purge", "package pelikan_dbg_k"] { _ = try? await s.execute("drop \(o)") }
        _ = try await s.execute("create table pelikan_dbg_t (id number, opis varchar2(30))")
        _ = try await s.execute("""
            create or replace trigger pelikan_dbg_trg before insert on pelikan_dbg_t for each row
            begin
              :new.opis := upper(:new.opis);
            end;
            """)
        _ = try await s.execute("create or replace package pelikan_dbg_k as g_publiczna number := 7; procedure dodaj(p_id number); end;")
        _ = try await s.execute("""
            create or replace package body pelikan_dbg_k as
              g_prywatna varchar2(10) := 'abc';
              procedure dodaj(p_id number) is
              begin
                insert into pelikan_dbg_t values (p_id, 'abc');
                if p_id > 1 then
                  raise_application_error(-20001, 'za duże');
                end if;
              end;
            end;
            """)
        for o in ["package pelikan_dbg_k compile debug", "package pelikan_dbg_k compile debug body", "trigger pelikan_dbg_trg compile debug"] {
            _ = try await s.execute("alter \(o)")
        }
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_dbg_k.dodaj(1);\n  pelikan_dbg_k.dodaj(2);\nend;")
        ws.breakpoints = [Breakpoint(document: doc.id.raw, line: 3)]
        let d = ws.debugger(for: doc)
        try await d.start()
        #expect(d.location?.line == 2)
        // Najpierw inicjalizacja pakietu (specyfikacja i ciało z wartościami początkowymi), potem procedura.
        for _ in 0..<6 where !(d.location?.objectType == .packageBody && d.location?.line ?? 0 >= 4) { try await d.step(.into) }
        #expect(d.location?.name == "PELIKAN_DBG_K" && d.location?.objectType == .packageBody)
        let globals = d.variables.filter { $0.path.hasPrefix("#") }.flatMap { $0.children ?? [] }
        #expect(globals.first { $0.name == "g_prywatna" }?.value == "abc")
        #expect(globals.first { $0.name == "g_publiczna" }?.value == "7")
        // BEGIN i INSERT, potem wyzwalacz.
        for _ in 0..<3 where d.location?.name != "PELIKAN_DBG_TRG" { try await d.step(.into) }
        print("DBG trg", d.location as Any, d.stack.map { "\($0.name)/\($0.unitType):\($0.line)" }, d.variables.map { "\($0.name)=\($0.value)" })
        #expect(d.location?.name == "PELIKAN_DBG_TRG" && d.location?.objectType == .trigger)
        #expect(d.stack.count >= 3)
        try await d.step(.run)           // do punktu przerwania w linii 3 bloku
        #expect(d.location?.isTestBlock == true && d.location?.line == 3)
        try await d.step(.runToException)
        print("DBG exc", d.location as Any, d.lastReason)
        #expect(d.location?.name == "PELIKAN_DBG_K" && d.stoppedOnException)
        await d.stop()
        #expect(d.state == .finished)
        for o in ["table pelikan_dbg_t purge", "package pelikan_dbg_k"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}

@MainActor
@Suite("Debuger: wyjście, obserwowane, zmiana wartości, błędy", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(1)))
struct DebuggerExtrasTests {
    @Test("DBMS_OUTPUT w trakcie, obserwowana zmienna, SET_VALUE zmienia przebieg, punkt przerwania na ORA-20002, Dodaj informację debugowania")
    func extras() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await s.execute("""
            create or replace procedure pelikan_dbg_q(n number) is
              v number := n;
            begin
              dbms_output.put_line('przed');
              v := v * 10;
              dbms_output.put_line('v=' || v);
              if v > 25 then
                raise_application_error(-20002, 'duże');
              end if;
            end;
            """)
        try await ws.invoke("ob.addDebugInfo", CommandArguments(["object": .string("pelikan_dbg_q")]))
        let dbg = try await s.scalar("select plsql_debug from user_plsql_object_settings where name = 'PELIKAN_DBG_Q'")
        #expect(dbg == "TRUE")

        let doc = ws.newDocument(.test, text: "begin\n  pelikan_dbg_q(3);\nend;")
        let d = ws.debugger(for: doc)
        try await d.start()
        try await d.step(.into)
        await d.addWatch("v")
        while d.state == .paused, d.location?.line != 5 { try await d.step(.over) }
        #expect(doc.output.contains("przed"))
        #expect(d.watchValues.first?.value == "3")
        #expect(try await d.executeInTarget("select dname from dept where deptno = 10") == ["KSIĘGOWOŚĆ"])
        _ = try await d.executeInTarget("begin dbms_output.put_line('z debugera'); end;")
        try await d.setValue("v", to: "1")
        #expect(d.variables.first { $0.name == "v" }?.value == "1")
        try await d.step(.run)
        #expect(d.state == .finished && doc.errorStack.isEmpty)
        #expect(doc.output.contains("v=10"))

        ws.errorBreakpoints = [20002]
        doc.output = []
        try await d.start()
        try await d.step(.run)
        #expect(d.stoppedOnException && d.location?.line == 8)
        await d.stop()
        _ = try? await s.execute("drop procedure pelikan_dbg_q")
        await ws.sessions.disconnectAll()
    }
}
