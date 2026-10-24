import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// Program z innego schematu: nagłówek z właścicielem (kompilacja trafia do właściciela, nie do schematu sesji) i analiza
/// kodu rozwiązująca nazwy w schemacie właściciela.
@MainActor
@Suite("Program z innego schematu — właściciel w nagłówku i w analizie nazw", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ForeignSchemaSourceDBTests {
    func ownerSchema() async throws -> ODPISession {
        let c = TestDatabase.config!
        let sys = try await ODPISession.connect(target: ConnectionTarget(user: "SYSTEM", connectString: c.connectString),
                                                credentials: Credentials(password: c.systemPassword), options: ConnectOptions())
        _ = try? await sys.execute("drop user pelikan_own cascade")
        _ = try await sys.execute("create user pelikan_own no authentication quota 5m on users")
        _ = try await sys.execute("create table pelikan_own.own_t (id number, nazwa varchar2(10))")
        _ = try await sys.execute("""
            create or replace procedure pelikan_own.own_p is
              n number;
            begin
              select count(*) into n from own_t t where t.nazwa is not null;
            end;
            """)
        _ = try await sys.execute("grant execute on pelikan_own.own_p to \(c.user)")
        _ = try await sys.execute("grant select on pelikan_own.own_t to \(c.user)")
        return sys
    }

    @Test("Źródło z innego schematu ma właściciela w nagłówku; własne — bez zmian")
    func qualifiedHeader() async throws {
        let sys = try await ownerSchema()
        let s = try await TestDatabase.connect()
        let text = try await MetadataProvider.source(of: DBObject(owner: "PELIKAN_OWN", name: "OWN_P", type: .procedure), in: s)
        let own = try await MetadataProvider.source(of: DBObject(owner: TestDatabase.config!.user.uppercased(), name: "EMP_API", type: .package), in: s)
        await cleanUp(s, sys)
        let h = try #require(ProgramCompiler.header(text))
        #expect(h.0 == .procedure && h.1 == "PELIKAN_OWN" && h.2 == "OWN_P", "\(text.prefix(80))")
        #expect(ProgramCompiler.header(own)?.1 == nil, "\(own.prefix(80))")
        #expect(ProgramCompiler.withOwner(text, owner: "PELIKAN_OWN") == text)
    }

    @Test("Analiza nazw w schemacie właściciela: tabela bez schematu znaleziona, kolumny sprawdzone; hurtowo")
    func namesInOwnerSchema() async throws {
        let sys = try await ownerSchema()
        let s = try await TestDatabase.connect()
        let text = try await MetadataProvider.source(of: DBObject(owner: "PELIKAN_OWN", name: "OWN_P", type: .procedure), in: s)
        let inOwner = await NameResolver.unresolved(in: text, source: MetadataNameSource(session: s, defaultSchema: "PELIKAN_OWN"))
        #expect(inOwner.isEmpty, "\(inOwner.map(\.message))")
        let inSession = await NameResolver.unresolved(in: text, source: MetadataNameSource(session: s))
        #expect(inSession.contains { $0.code == "unknown-table" })
        let bad = text.replacingOccurrences(of: "t.nazwa", with: "t.brak")
        let wrong = await NameResolver.unresolved(in: bad, source: MetadataNameSource(session: s, defaultSchema: "PELIKAN_OWN"))
        #expect(wrong.map(\.code) == ["unknown-column"])
        await cleanUp(s, sys)
    }

    /// Synchronicznie (nie w `defer { Task … }`) — następny test tworzy tego samego użytkownika.
    func cleanUp(_ s: ODPISession, _ sys: ODPISession) async {
        await s.close()
        _ = try? await sys.execute("drop user pelikan_own cascade")
        await sys.close()
    }
}
