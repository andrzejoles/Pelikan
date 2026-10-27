import Foundation
import PelikanDB
@testable import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// PD-CONN-013 na serwerze LDAP (scripts/testdb.sh ldap-up): alias spoza tnsnames.ora rozwiązany przez katalog
/// (ldap.ora z katalogu użytkownika dowiązany do katalogu Oracle Net Pelikana, NAMES.DIRECTORY_PATH z jego sqlnet.ora).
@MainActor
@Suite("Nazewnictwo katalogowe (LDAP) na bazie testowej", .enabled(if: TestDatabase.isLDAPAvailable), .serialized)
struct DirectoryNamingTests {
    @Test("Alias dev_pelikan_ldap z serwera LDAP: połączenie definicją Pelikana przez Instant Client")
    func ldapAlias() async throws {
        let c = TestDatabase.config!
        let dir = try #require(TestDatabase.oracleNetDirectory)
        // Katalog zarządzany: ldap.ora jako dowiązanie (klient nie czyta go przez IFILE), alias nie jest w tnsnames.ora.
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: dir + "/ldap.ora")
        #expect(link.hasSuffix("oracle-net-user/ldap.ora"))
        let tns = (try? String(contentsOfFile: (link as NSString).deletingLastPathComponent + "/tnsnames.ora", encoding: .utf8)) ?? ""
        #expect(!tns.lowercased().contains("dev_pelikan_ldap"))

        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_pelikan_ldap", target: ConnectionTarget(user: c.user, connectString: "dev_pelikan_ldap"))
        try ws.connections.upsert(def, password: c.password)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(try await s.scalar("select user from dual") == c.user.uppercased())
        #expect(try await s.scalar("select upper(sys_context('userenv', 'service_name')) from dual") == "FREEPDB1")
        await ws.sessions.disconnectAll()

        // Alias, którego nie ma w katalogu: błąd rozwiązywania nazwy (ORA-12154), nie połączenie gdzie indziej.
        let missing = ConnectionTarget(user: c.user, connectString: "dev_pelikan_brak")
        do {
            _ = try await ODPISession.connect(target: missing, credentials: Credentials(password: c.password))
            Issue.record("połączenie z nieistniejącym aliasem")
        } catch let e as OracleError {
            #expect(e.code == 12154)
        }
    }
}

@Suite("Nazewnictwo katalogowe: konfiguracja ldap.ora i sqlnet.ora")
struct DirectoryNamingConfigTests {
    @Test("DIRECTORY_SERVERS, DEFAULT_ADMIN_CONTEXT, NAMES.DIRECTORY_PATH z IFILE; DN aliasu; alias vs EZConnect")
    func config() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ldap-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "DIRECTORY_SERVERS = (ldap1.example.test:389:636, ldap2.example.test)\nDEFAULT_ADMIN_CONTEXT = \"dc=example,dc=test\"\nDIRECTORY_SERVER_TYPE = OID\n"
            .write(to: dir.appendingPathComponent("ldap.ora"), atomically: true, encoding: .utf8)
        // Bez sqlnet.ora: kolejność domyślna obejmuje LDAP.
        var c = try #require(DirectoryNaming.config(directories: ["/nonexistent", dir.path]))
        #expect(c.path == ["tnsnames", "ezconnect", "ldap"])
        #expect(c.servers == [.init(host: "ldap1.example.test", port: 389), .init(host: "ldap2.example.test", port: 389)])
        #expect(c.adminContext == "dc=example,dc=test")
        try "NAMES.DIRECTORY_PATH = (LDAP, HOSTNAME)\n".write(to: dir.appendingPathComponent("user.ora"), atomically: true, encoding: .utf8)
        try "IFILE=\"\(dir.path)/user.ora\"\n".write(to: dir.appendingPathComponent("sqlnet.ora"), atomically: true, encoding: .utf8)
        c = try #require(DirectoryNaming.config(directories: [dir.path]))
        #expect(c.path == ["ldap", "ezconnect"])
        try "NAMES.DIRECTORY_PATH=(TNSNAMES)\n".write(to: dir.appendingPathComponent("user.ora"), atomically: true, encoding: .utf8)
        #expect(DirectoryNaming.config(directories: [dir.path]) == nil)
        #expect(DirectoryNaming.distinguishedName(alias: "dev_a", context: "dc=x,dc=y") == "cn=dev_a,cn=OracleContext,dc=x,dc=y")
        #expect(DirectoryNaming.distinguishedName(alias: "sales.example.com", context: nil) == "cn=sales,cn=OracleContext,dc=example,dc=com")
        #expect(DirectoryNaming.distinguishedName(alias: "dev_a", context: nil) == nil)
        #expect(DirectoryNaming.isBareAlias("dev_pelikan_ldap") && DirectoryNaming.isBareAlias("sales.example.com"))
        #expect(!DirectoryNaming.isBareAlias("127.0.0.1:1521/FREEPDB1") && !DirectoryNaming.isBareAlias("(DESCRIPTION=)")
                && !DirectoryNaming.isBareAlias("host/svc"))
    }

#if os(macOS)
    @Test("Metoda hostname/EZConnect przed LDAP: sama nazwa hosta zostaje klientowi zamiast ORA-12154")
    func hostnameMethod() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ldap-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Serwer LDAP pod portem bez nasłuchu — wyszukiwanie kończy się od razu błędem połączenia.
        try "DIRECTORY_SERVERS = (127.0.0.1:1:2)\nDEFAULT_ADMIN_CONTEXT = \"dc=example,dc=test\"\n"
            .write(to: dir.appendingPathComponent("ldap.ora"), atomically: true, encoding: .utf8)
        try "NAMES.DIRECTORY_PATH = (TNSNAMES, HOSTNAME, LDAP)\n".write(to: dir.appendingPathComponent("sqlnet.ora"), atomically: true, encoding: .utf8)
        #expect(try DirectoryLookup.resolve("localhost", directories: [dir.path]) == nil)
        #expect(throws: (any Error).self) { try DirectoryLookup.resolve("pelikan-nie-ma-takiego-hosta.invalid", directories: [dir.path]) }
        // LDAP przed EZConnect: klient użyłby najpierw własnego adaptera LDAP (D158) — Pelikan nie zostawia mu nazwy.
        try "NAMES.DIRECTORY_PATH = (LDAP, EZCONNECT)\n".write(to: dir.appendingPathComponent("sqlnet.ora"), atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try DirectoryLookup.resolve("localhost", directories: [dir.path]) }
    }
#endif
}
