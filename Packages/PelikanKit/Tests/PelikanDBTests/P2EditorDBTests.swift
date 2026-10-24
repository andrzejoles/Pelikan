import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

@MainActor
@Suite("Edytor P2 na bazie: konstruktory w Code Assistant, parametry kompilatora", .enabled(if: TestDatabase.isAvailable), .serialized)
struct P2EditorDBTests {
    func connect() async throws -> (Workspace, any DatabaseSession) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        return (ws, s)
    }

    @Test("Konstruktor typu obiektowego: atrybuty jako parametry nazwane i „(all)” (PD-CA-006)")
    func constructor() async throws {
        let (ws, s) = try await connect()
        _ = try? await s.execute("drop type pelikan_p2e_typ force")
        _ = try await s.execute("create or replace type pelikan_p2e_typ as object (kod number, nazwa varchar2(30), data_od date)")
        let text = "declare o pelikan_p2e_typ := pelikan_p2e_typ("
        let r = await CodeAssistant.complete(text: text, offset: (text as NSString).length, metadata: ws.metadata())
        let labels = r?.items.map { $0.label.uppercased() } ?? []
        #expect(labels.first == "(ALL)" && Array(labels.dropFirst()) == ["KOD", "NAZWA", "DATA_OD"])
        #expect(r?.items.first?.insertText.lowercased() == "kod => , nazwa => , data_od => ")
        _ = try? await s.execute("drop type pelikan_p2e_typ force")
        await ws.sessions.disconnectAll()
    }

    @Test("Parametry kompilatora: PLSQL_CCFLAGS i PLSQL_OPTIMIZE_LEVEL obowiązują przy kompilacji okna programu (PD-PROG-013)")
    func compilerOptions() async throws {
        let (ws, s) = try await connect()
        ws.settings.compiler.ccflags = "pelikan_flag:TRUE"
        ws.settings.compiler.optimizeLevel = 1
        defer { ws.settings.compiler = CompilerOptions() }
        let doc = ws.newDocument(.program, text: """
            create or replace function pelikan_p2e_f return varchar2 is
            begin
              $IF $$pelikan_flag $THEN return 'tak'; $ELSE return 'nie'; $END
            end;
            /

            """)
        let r = try await ProgramCompiler.compile(doc, in: ws)
        #expect(r.ok, "\(r.messages.map(\.text))")
        #expect(try await s.queryAll("select pelikan_p2e_f from dual").rows.first?.first?.displayText == "tak")
        let level = try await s.queryAll("select plsql_optimize_level from user_plsql_object_settings where name = 'PELIKAN_P2E_F'")
        #expect(level.rows.first?.first?.displayText == "1")
        _ = try? await s.execute("drop function pelikan_p2e_f")
        await ws.sessions.disconnectAll()
    }
}
