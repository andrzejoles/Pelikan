import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Sonda debugera", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ZProbeDebugTests {
    @Test func probe() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        for o in ["table pelikan_pr_t purge", "type pelikan_pr_o force"] { _ = try? await s.execute("drop \(o)") }
        _ = try await s.execute("create table pelikan_pr_t (id number, opis varchar2(30))")
        _ = try await s.execute("create or replace trigger pelikan_pr_trg before insert on pelikan_pr_t for each row\nbegin\n  :new.opis := upper(:new.opis);\nend;")
        _ = try await s.execute("create or replace type pelikan_pr_o as object (a number, b varchar2(10), member function f return number)")
        _ = try await s.execute("create or replace type body pelikan_pr_o as\n  member function f return number is\n  begin\n    return a * 2;\n  end;\nend;")
        for o in ["trigger pelikan_pr_trg compile debug", "type pelikan_pr_o compile debug body"] { _ = try await s.execute("alter \(o)") }
        let doc = ws.newDocument(.test, text: "declare o pelikan_pr_o := pelikan_pr_o(5, 'x'); n number;\nbegin\n  insert into pelikan_pr_t values (1, 'abc');\n  n := o.f;\nend;")
        let d = ws.debugger(for: doc)
        try await d.start()
        print("PROBE start", d.location as Any); fflush(stdout)
        for _ in 0..<4 where d.location?.name != "PELIKAN_PR_TRG" { try await d.step(.into); print("PROBE at", d.location as Any); fflush(stdout) }
        for n in ["NEW.OPIS", "OLD.OPIS", "NEW"] {
            let r = await d.getValue(n, frame: 0)
            print("PROBE trg", n, r.0, r.1 ?? "nil"); fflush(stdout)
        }
        for _ in 0..<6 where d.location?.name != "PELIKAN_PR_O" { try await d.step(.into); print("PROBE at", d.location as Any); fflush(stdout) }
        for n in ["SELF.A", "SELF.B", "SELF", "A"] {
            let r = await d.getValue(n, frame: 0)
            print("PROBE self", n, r.0, r.1 ?? "nil"); fflush(stdout)
        }
        await d.stop()
        for o in ["table pelikan_pr_t purge", "type pelikan_pr_o force"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}
