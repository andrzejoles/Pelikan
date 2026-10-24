import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

@MainActor
@Suite("Edytor P1 na bazie", .enabled(if: TestDatabase.isAvailable), .serialized)
struct P1EditorDBTests {
    func labels(_ ws: Workspace, _ marked: String) async -> [String] {
        let r = (marked as NSString).range(of: "|")
        let text = marked.replacingOccurrences(of: "|", with: "")
        return await CodeAssistant.complete(text: text, offset: r.location, metadata: ws.metadata())?.items.map { $0.label.uppercased() } ?? []
    }

    func connect() async throws -> (Workspace, any DatabaseSession) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        return (ws, s)
    }

    @Test("Synonimy publiczne, parametry nazwane z ALL_ARGUMENTS bez podanych, SELF typu z bazy")
    func assistant() async throws {
        let (ws, s) = try await connect()
        for sql in ["create table pelikan_p1e_t (id number)",
                    "create or replace public synonym pelikan_p1e_pub for pelikan_p1e_t",
                    "create or replace package pelikan_p1e_pkg as procedure zmien(p_a number, p_b varchar2, p_c date); end;",
                    "create or replace type pelikan_p1e_typ as object (a number, member function f return number)"] {
            _ = try? await s.execute(sql)
        }
        #expect(await labels(ws, "select * from pelikan_p1e_p|").contains("PELIKAN_P1E_PUB"))
        #expect(await labels(ws, "begin pelikan_p1e_pkg.zmien(p_b => 'x', |") == ["P_A", "P_C"])
        #expect(await labels(ws, "begin pelikan_p1e_pkg.zmien(1, p_|") .starts(with: ["P_A", "P_B", "P_C"]))
        let body = "create or replace type body pelikan_p1e_typ as\n  member function f return number is\n  begin\n    return self.|"
        let members = await labels(ws, body)
        #expect(members.contains("A") && members.contains("F"))
        for o in ["public synonym pelikan_p1e_pub", "table pelikan_p1e_t purge", "package pelikan_p1e_pkg", "type pelikan_p1e_typ"] {
            _ = try? await s.execute("drop \(o)")
        }
        await ws.sessions.disconnectAll()
    }

    @Test("Revert ze źródła w bazie: tekst jednostek okna programu jak w ALL_SOURCE")
    func revertFromDatabase() async throws {
        let (ws, s) = try await connect()
        _ = try await s.execute("create or replace procedure pelikan_p1e_proc is begin null; end;")
        let doc = ws.newDocument(.program, text: "create or replace procedure pelikan_p1e_proc is begin raise program_error; end;\n/\n")
        doc.text += "\n"
        try await ws.invoke("prog.revert", CommandArguments(["source": .string("database")]))
        #expect(doc.text.contains("begin null; end;") && !doc.text.contains("program_error"))
        #expect(!doc.isCompileStale)
        _ = try? await s.execute("drop procedure pelikan_p1e_proc")
        await ws.sessions.disconnectAll()
    }
}
