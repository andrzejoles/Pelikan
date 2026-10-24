import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Debuger: SELF, obiekty, warunki, komunikaty, logpointy (PD-DBG-004, PD-DBG-007)", .enabled(if: TestDatabase.isAvailable), .serialized,
       .timeLimit(.minutes(1)))
struct DebuggerP1Tests {
    func setUp() async throws -> (Workspace, any DatabaseSession) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        return (ws, s)
    }

    @Test("SELF w metodzie typu i zmienna obiektu jako drzewo; wyzwalacz bez :new/:old; nazwa z dwukropkiem nie zawiesza")
    func selfAndObjects() async throws {
        let (ws, s) = try await setUp()
        for o in ["table pelikan_p1d_t purge", "type pelikan_p1d_o force"] { _ = try? await s.execute("drop \(o)") }
        _ = try await s.execute("create table pelikan_p1d_t (id number, opis varchar2(30))")
        _ = try await s.execute("create or replace trigger pelikan_p1d_trg before insert on pelikan_p1d_t for each row\nbegin\n  :new.opis := upper(:new.opis);\nend;")
        _ = try await s.execute("create or replace type pelikan_p1d_o as object (a number, b varchar2(10), member function f return number)")
        _ = try await s.execute("create or replace type body pelikan_p1d_o as\n  member function f return number is\n  begin\n    return a * 2;\n  end;\nend;")
        for o in ["trigger pelikan_p1d_trg compile debug", "type pelikan_p1d_o compile debug body"] { _ = try await s.execute("alter \(o)") }
        let doc = ws.newDocument(.test, text: "declare\n  o pelikan_p1d_o := pelikan_p1d_o(5, 'x');\n  n number;\nbegin\n  insert into pelikan_p1d_t values (1, 'abc');\n  n := o.f;\n  rollback;\nend;")
        let d = ws.debugger(for: doc)
        try await d.start()
        for _ in 0..<6 where d.location?.name != "PELIKAN_P1D_TRG" { try await d.step(.into) }
        #expect(d.location?.name == "PELIKAN_P1D_TRG")
        #expect(d.variables.contains { $0.path == "#trigger" })
        #expect(await d.getValue(":NEW.OPIS", frame: 0).0 == 3)
        for _ in 0..<8 where d.location?.name != "PELIKAN_P1D_O" { try await d.step(.into) }
        #expect(d.location?.name == "PELIKAN_P1D_O")
        let me = try #require(d.variables.first { $0.name == "self" })
        #expect(me.children?.first { $0.name == "a" }?.value == "5" && me.children?.first { $0.name == "b" }?.value == "x")
        try await d.step(.out)
        #expect(d.variables.first { $0.name == "o" }?.children?.first { $0.name == "a" }?.value == "5")
        await d.stop()
        for o in ["table pelikan_p1d_t purge", "type pelikan_p1d_o force"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }

    @Test("Warunek zatrzymuje dopiero przy spełnieniu; komunikat z wartością; logpoint nie zatrzymuje; niezastosowany punkt")
    func conditionsAndLogpoints() async throws {
        let (ws, s) = try await setUp()
        _ = try await s.execute("""
            create or replace procedure pelikan_p1d_p is
              v number := 0;
            begin
              for i in 1 .. 5 loop
                v := v + i;
                v := v * 1;
              end loop;
            end;
            """)
        _ = try await s.execute("alter procedure pelikan_p1d_p compile debug")
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_p1d_p;\nend;")
        var cond = Breakpoint(owner: nil, unit: "PELIKAN_P1D_P", type: .procedure, line: 6)
        cond.condition = "i = 4"
        var log = Breakpoint(owner: nil, unit: "PELIKAN_P1D_P", type: .procedure, line: 5)
        log.message = "i={i} v={v}"
        log.dontBreak = true
        let bad = Breakpoint(owner: nil, unit: "PELIKAN_NIE_MA", type: .procedure, line: 1)
        ws.breakpoints = [log, cond, bad]
        let d = ws.debugger(for: doc)
        try await d.start()
        try await d.step(.run)
        #expect(d.state == .paused && d.location?.name == "PELIKAN_P1D_P" && d.location?.line == 6)
        #expect(d.variables.first { $0.name == "v" }?.value == "10")
        #expect(doc.output.filter { $0.hasPrefix("▸ i=") }.count == 4 && doc.output.contains("▸ i=1 v=0"))
        #expect(ws.unappliedBreakpoints.contains(bad.id) && !ws.unappliedBreakpoints.contains(cond.id))
        try await d.step(.run)
        #expect(d.state == .finished)
        _ = try? await s.execute("drop procedure pelikan_p1d_p")
        await ws.sessions.disconnectAll()
    }
}
