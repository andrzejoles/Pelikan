import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Etap 7 na bazie testowej: rozwiązywanie nazw, Find Usages, historia kompilacji", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct Stage7DataGripDBTests {
    func workspace() throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    @Test("Słownik: istniejące i nieznane tabele, kolumny EMP, kwalifikator schematu")
    func nameSource() async throws {
        let s = try await TestDatabase.connect()
        let src = MetadataNameSource(session: s)
        #expect(await src.relationExists(owner: nil, name: "EMP"))
        #expect(!(await src.relationExists(owner: nil, name: "NIE_MA_TAKIEJ_TABELI")))
        #expect(await src.columns(owner: nil, relation: "EMP")?.contains("ENAME") == true)
        #expect(await src.objectOrSchemaExists(s.info.currentSchema))
        let d = await NameResolver.unresolved(in: "select e.enam from emp e, brak_tabeli b", source: src)
        #expect(Set(d.map(\.code)) == ["unknown-column", "unknown-table"], "\(d.map(\.message))")
        await s.close()
    }

    @Test("Find Usages: procedura używająca EMP (zależność i linia kodu), kolumna SAL; analiza okna z sesją główną")
    func usages() async throws {
        let s = try await TestDatabase.connect()
        _ = try await s.execute("create or replace procedure dg_usage_p is n number; begin select sum(sal) into n from emp; end;")
        let hits = try await UsageFinder.inDatabase(owner: s.info.currentSchema, name: "EMP", session: s)
        #expect(hits.contains { $0.kind == .dependency && $0.name == "DG_USAGE_P" })
        #expect(hits.contains { $0.kind == .source && $0.name == "DG_USAGE_P" && $0.line == 1 })
        let cols = try await UsageFinder.inDatabase(owner: s.info.currentSchema, name: "EMP", column: "SAL", session: s)
        #expect(cols.contains { $0.name == "DG_USAGE_P" } && !cols.contains { $0.kind == .dependency })
        _ = try await s.execute("drop procedure dg_usage_p")
        await s.close()

        let (ws, id) = try workspace()
        _ = try await ws.sessions.session(SessionKey(connectionID: id, purpose: .main))
        let doc = ws.newDocument(.sql, text: "select x.ename from emp e")
        let found = await ws.analyzeCode(doc)
        #expect(found.map(\.code) == ["unknown-alias"], "\(found.map(\.message))")
        await ws.sessions.disconnectAll()
    }

    @Test("Kompilacja w oknie programu zapisuje wersję obiektu w historii lokalnej")
    func compileHistory() async throws {
        let (ws, id) = try workspace()
        let doc = ws.newDocument(.program, text: "create or replace procedure dg_hist_p is begin null; end;\n/\n")
        doc.connectionID = id
        _ = try await ProgramCompiler.compile(doc, in: ws)
        // Klucz okna (schemat bieżący połączenia) zgodny z kluczem zapisanym przy kompilacji.
        let key = try #require(ws.historyKey(for: doc)?.key)
        #expect(ws.localHistory.entries(key).first?.label == L10n.tr("kompilacja"), "\(key)")
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        _ = try await s.execute("drop procedure dg_hist_p")
        await ws.sessions.disconnectAll()
    }
}
