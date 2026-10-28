import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// Foldery DBA i DBMS Object Browsera: obiekty z przedrostkiem, do których użytkownik ma uprawnienia (ALL_OBJECTS), bez
/// synonimów i ciał; użytkownik bez uprawnień do słownika widzi publiczny synonim DBA_USERS, ale nie widok.
@MainActor
@Suite("Object Browser: foldery DBA i DBMS", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct SystemFoldersDBTests {
    func metadata(user: String, password: String) throws -> MetadataProvider {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test_\(user.lowercased())", target: ConnectionTarget(user: user, connectString: c.connectString))
        try ws.connections.upsert(def, password: password)
        ws.sessions.setMainConnection(def.id)
        return try #require(ws.metadata())
    }

    @Test("Użytkownik z uprawnieniami do słownika: widoki DBA_ i pakiety DBMS_ (bez synonimów i ciał), filtr nazw")
    func privilegedUser() async throws {
        let c = TestDatabase.config!
        let m = try metadata(user: c.user, password: c.password)
        let dba = try await m.systemObjects(.dba)
        #expect(dba.contains { $0.owner == "SYS" && $0.name == "DBA_DB_LINKS" && $0.type == .view })
        #expect(dba.allSatisfy { $0.name.hasPrefix("DBA_") && ![.synonym, .packageBody, .typeBody].contains($0.type) })
        let dbms = try await m.systemObjects(.dbms)
        #expect(dbms.contains { $0.owner == "SYS" && $0.name == "DBMS_OUTPUT" && $0.type == .package })
        #expect(dbms.allSatisfy { $0.name.hasPrefix("DBMS_") && ![.synonym, .packageBody, .typeBody].contains($0.type) })
        // `_` w przedrostku nie jest symbolem wieloznacznym: obiekt DBAX… nie trafia do folderu DBA.
        #expect(!dba.contains { $0.name.hasPrefix("DBAX") })
        let filtered = try await m.systemObjects(.dba, filter: ObjectFilter("db_li"))
        #expect(filtered.contains { $0.name == "DBA_DB_LINKS" } && filtered.allSatisfy { $0.name.contains("DB_LI") })
    }

    @Test("Użytkownik bez uprawnień do słownika: pusty folder DBA mimo publicznych synonimów, pakiety DBMS_ z PUBLIC")
    func unprivilegedUser() async throws {
        let c = TestDatabase.config!
        let m = try metadata(user: c.agentUser, password: c.agentPassword)
        #expect(!(try await m.systemObjects(.dba)).contains { $0.name == "DBA_USERS" })
        #expect((try await m.systemObjects(.dbms)).contains { $0.name == "DBMS_OUTPUT" && $0.type == .package })
    }
}
