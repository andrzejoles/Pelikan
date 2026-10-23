import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Instalacja utPLSQL na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(10)))
struct UtplsqlInstallTests {
    @Test("Oficjalne wydanie: pobranie z sumą SHA-256 i instalacja silnikiem Command Window w osobnym schemacie")
    func installSideBySide() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "sys", target: ConnectionTarget(user: "SYS", connectString: c.connectString, role: .sysdba),
                                       environment: .test)
        try ws.connections.upsert(def, password: c.systemPassword)
        ws.sessions.setMainConnection(def.id)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-utplsql-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: cache) }
        let release = try await UtplsqlInstaller.release(version: "v.3.2.3")
        let source = try await UtplsqlInstaller.prepare(release, cache: cache)

        let doc = ws.newDocument(.command, text: "")
        doc.connectionID = def.id
        let engine = SQLPlusEngine(workspace: ws, document: doc)
        let owner = "UT3_PELIKAN_INST"
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try? await s.execute("drop user \(owner) cascade")
        let ok = await UtplsqlInstaller.run(UtplsqlInstaller.script(owner: owner, upgrade: false, publicSynonyms: false), source: source, engine: engine)
        let errors = doc.console.filter { $0.kind == .error }.map(\.text)
        #expect(ok, "\(errors.prefix(10)) \(doc.console.suffix(12).map(\.text))")
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("params.sql.tmp").path))
        let invalid = try await s.scalar("select count(*) from dba_objects where owner = '\(owner)' and status <> 'VALID'")
        // SYS nie wywołuje kodu z prawami wywołującego innego schematu (INHERIT PRIVILEGES) — wersja ze źródła.
        let version = try await s.scalar("select text from dba_source where owner = '\(owner)' and name = 'UT_UTILS' and type = 'PACKAGE' and text like '%gc_version%:=%'")
        let objects = try await s.scalar("select count(*) from dba_objects where owner = '\(owner)'")
        #expect(invalid == "0" && (Int(objects ?? "") ?? 0) > 200 && version?.contains("3.2.3") == true, "\(invalid ?? "?") \(objects ?? "?") \(version ?? "?")")
        #expect(try await s.scalar("select account_status from dba_users where username = '\(owner)'")?.contains("LOCKED") == true)

        // Aktualizacja: odinstalowanie obiektów i instalacja w istniejącym schemacie (EXIT kończy tylko krok).
        let upgraded = await UtplsqlInstaller.run(UtplsqlInstaller.script(owner: owner, upgrade: true, publicSynonyms: false), source: source, engine: engine)
        #expect(upgraded, "\(doc.console.suffix(8).map(\.text))")
        #expect(try await s.scalar("select count(*) from dba_objects where owner = '\(owner)' and status <> 'VALID'") == "0")
        #expect(try await s.scalar("select count(*) from all_synonyms where owner = 'PUBLIC' and synonym_name = 'UT' and table_owner = 'UT3'") == "1")
        _ = try? await s.execute("drop user \(owner) cascade")
        await ws.sessions.disconnectAll()
    }

    @Test("Komenda instalacji odmawia dla połączenia produkcyjnego")
    func refusesProduction() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "prod", target: ConnectionTarget(user: c.user, connectString: c.connectString), environment: .production)
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        await #expect(throws: CommandError.self) { try await ws.invoke("utplsql.install") }
        #expect(ws.documents.allSatisfy { $0.kind != .command })
        await ws.sessions.disconnectAll()
    }
}
