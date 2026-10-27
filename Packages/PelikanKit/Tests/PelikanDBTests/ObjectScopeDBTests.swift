import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// Zakres folderów Object Browsera (D187): obiekty własne z publicznymi łączami i synonimami aplikacji, obiekty
/// dostępne (nadane z innych schematów), katalogi z uprawnieniem; publiczne synonimy schematów Oracle pominięte.
@MainActor
@Suite("Object Browser: obiekty własne, dostępne i publiczne", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct ObjectScopeDBTests {
    func prepare() async throws -> ODPISession {
        let c = TestDatabase.config!
        let sys = try await ODPISession.connect(target: ConnectionTarget(user: "SYSTEM", connectString: c.connectString),
                                                credentials: Credentials(password: c.systemPassword), options: ConnectOptions())
        await cleanUp(sys)
        _ = try await sys.execute("create user pelikan_scope no authentication quota 5m on users")
        _ = try await sys.execute("create table pelikan_scope.scope_t (id number)")
        _ = try await sys.execute("create table pelikan_scope.scope_hidden (id number)")
        _ = try await sys.execute("grant select on pelikan_scope.scope_t to \(c.user)")
        _ = try await sys.execute("create public synonym pelikan_scope_syn for pelikan_scope.scope_t")
        _ = try await sys.execute("create public database link pelikan_scope_link using 'pelikan_scope_nonexistent'")
        _ = try await sys.execute("create or replace directory pelikan_scope_dir as '/tmp'")
        _ = try await sys.execute("create or replace directory pelikan_scope_dir2 as '/tmp'")
        _ = try await sys.execute("grant read on directory pelikan_scope_dir to \(c.user)")
        return sys
    }

    func cleanUp(_ sys: ODPISession) async {
        for sql in ["drop public synonym pelikan_scope_syn", "drop public database link pelikan_scope_link", "drop directory pelikan_scope_dir",
                    "drop directory pelikan_scope_dir2", "drop user pelikan_scope cascade"] {
            _ = try? await sys.execute(sql)
        }
    }

    @Test("Bieżący użytkownik: własne + publiczne łącze i synonim aplikacji, bez obcych tabel i synonimów Oracle; dostępne: nadana tabela; katalog z uprawnieniem")
    func scopes() async throws {
        let sys = try await prepare()
        let started = ContinuousClock.now
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let names: ([DBObject]) -> Set<String> = { Set($0.map { "\($0.owner).\($0.name)" }) }

        let mineTables = names(try await m.objects(.table, scope: .mine(schema)))
        #expect(mineTables.contains("\(schema).DEPT") && !mineTables.contains("PELIKAN_SCOPE.SCOPE_T"))
        let mineLinks = names(try await m.objects(.databaseLink, scope: .mine(schema)))
        #expect(mineLinks.contains("PUBLIC.PELIKAN_SCOPE_LINK"), "\(mineLinks)")
        let mineSynonyms = names(try await m.objects(.synonym, scope: .mine(schema)))
        #expect(mineSynonyms.contains("PUBLIC.PELIKAN_SCOPE_SYN"), "publiczny synonim aplikacji")
        #expect(!mineSynonyms.contains("PUBLIC.DUAL") && !mineSynonyms.contains("PUBLIC.DBMS_OUTPUT"), "publiczne synonimy SYS pominięte")

        let accessibleTables = names(try await m.objects(.table, scope: .accessible))
        #expect(accessibleTables.contains("PELIKAN_SCOPE.SCOPE_T") && accessibleTables.contains("\(schema).DEPT"))
        #expect(!accessibleTables.contains("PELIKAN_SCOPE.SCOPE_HIDDEN"), "bez uprawnienia — niewidoczna")
        let accessibleSynonyms = names(try await m.objects(.synonym, scope: .accessible))
        #expect(accessibleSynonyms.contains("PUBLIC.PELIKAN_SCOPE_SYN") && !accessibleSynonyms.contains("PUBLIC.DUAL"))

        // Katalog z uprawnieniem READ widoczny (użytkownik testowy ma też CREATE ANY DIRECTORY — widzi wszystkie).
        #expect(try await m.objects(.directory, scope: .mine(schema)).contains { $0.name == "PELIKAN_SCOPE_DIR" })
        // Filtr nazw obejmuje publiczne synonimy; filtr stanu — nie.
        #expect(names(try await m.objects(.synonym, scope: .mine(schema), filter: ObjectFilter("scope_syn"))) == ["PUBLIC.PELIKAN_SCOPE_SYN"])
        #expect(try await m.objects(.synonym, scope: .mine(schema), filter: ObjectFilter("status=invalid")).allSatisfy { $0.owner != "PUBLIC" })
        #expect(try await m.objects(.table, scope: .user("PELIKAN_SCOPE")).allSatisfy { $0.owner == "PELIKAN_SCOPE" })

        #expect(ContinuousClock.now - started < .seconds(30), "foldery wczytują się szybko (połączenie ALL_OBJECTS z ALL_SYNONYMS trwało ponad minutę)")
        await ws.sessions.disconnectAll()
        await cleanUp(sys)
        await sys.close()
    }
}
