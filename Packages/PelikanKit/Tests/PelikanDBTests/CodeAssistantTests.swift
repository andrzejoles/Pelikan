import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

@MainActor
@Suite("Code Assistant na bazie", .enabled(if: TestDatabase.isAvailable), .serialized)
struct CodeAssistantTests {
    func labels(_ ws: Workspace, _ marked: String) async -> [String] {
        let r = (marked as NSString).range(of: "|")
        let text = marked.replacingOccurrences(of: "|", with: "")
        return await CodeAssistant.complete(text: text, offset: r.location, metadata: ws.metadata())?.items.map { $0.label.uppercased() } ?? []
    }

    @Test("Kolumny po aliasie i nazwie tabeli, %ROWTYPE, kursor, rekord pętli, NEXTVAL, elementy pakietu, obiekty schematu, :new")
    func complete() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        for sql in ["create table pelikan_ca_t (id number primary key, nazwa varchar2(30), kwota number(10,2))",
                    "create sequence pelikan_ca_seq",
                    "create or replace package pelikan_ca_pkg as procedure dodaj(p_id number); function suma return number; end;"] {
            _ = try? await s.execute(sql)
        }

        #expect(await labels(ws, "select t.| from pelikan_ca_t t") == ["(ALL)", "ID", "NAZWA", "KWOTA"])     // „(all)” — PD-CA-006
        #expect(await labels(ws, "select pelikan_ca_t.na| from pelikan_ca_t") == ["NAZWA"])
        #expect(await labels(ws, "select | from pelikan_ca_t").starts(with: ["ID", "NAZWA", "KWOTA"]))
        #expect(await labels(ws, "select pelikan_ca_seq.| from dual") == ["NEXTVAL", "CURRVAL"])
        #expect(await labels(ws, "begin pelikan_ca_pkg.| end;") == ["DODAJ", "SUMA"])
        #expect(await labels(ws, "begin \(c.user.lowercased()).pelikan_ca_pkg.s| end;") == ["SUMA"])
        #expect(await labels(ws, "begin x := pelikan_ca_| end;").contains("PELIKAN_CA_SEQ"))
        let plsql = """
            declare
              r pelikan_ca_t%rowtype;
              cursor cur is select id, nazwa as n from pelikan_ca_t;
            begin
              for q in cur loop
                for z in (select t.* from pelikan_ca_t t) loop
                  x := 
            """
        #expect(await labels(ws, plsql + "r.|") == ["(ALL)", "ID", "NAZWA", "KWOTA"])
        #expect(await labels(ws, plsql + "q.|") == ["(ALL)", "ID", "N"])
        #expect(await labels(ws, plsql + "z.k|") == ["KWOTA"])
        #expect(await labels(ws, "create or replace trigger trg before insert on pelikan_ca_t for each row begin :new.|") == ["(ALL)", "ID", "NAZWA", "KWOTA"])
        // Parametry podprogramu z ALL_ARGUMENTS (PD-CA-006).
        #expect(await labels(ws, "begin pelikan_ca_pkg.dodaj(|") == ["P_ID"])
        let args = try await ws.metadata()!.arguments(owner: nil, package: "PELIKAN_CA_PKG", name: "DODAJ")
        #expect(args.map(\.0) == ["P_ID"] && args.first?.1 == "IN NUMBER")
        // Wielkość liter jak w prefiksie.
        let lower = await CodeAssistant.complete(text: "select t.na from pelikan_ca_t t", offset: 11, metadata: ws.metadata())
        #expect(lower?.items.first?.insertText == "nazwa")
        for o in ["table pelikan_ca_t purge", "sequence pelikan_ca_seq", "package pelikan_ca_pkg"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}
