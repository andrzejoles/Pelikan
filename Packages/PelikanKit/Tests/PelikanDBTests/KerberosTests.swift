import Foundation
import PelikanDB
@testable import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// PD-CONN-014 z KDC MIT (scripts/testdb.sh kdc-up): uwierzytelnianie zewnętrzne (`/`) biletem Kerberos z pamięci
/// podręcznej wskazanej w sqlnet.ora użytkownika (dołączonym do katalogu Oracle Net Pelikana), bez hasła w Pelikanie.
/// Na macOS adapter Kerberos Instant Client nie działa w procesie z Kerberos.framework (D159) — test na żywo
/// uruchamia `scripts/testdb.sh kdc-linux` (Instant Client dla Linuksa, jak w CI).
@MainActor
@Suite("Kerberos na bazie testowej", .enabled(if: TestDatabase.isKerberosAvailable), .serialized)
struct KerberosTests {
    @Test("Połączenie / z biletem Kerberos: użytkownik IDENTIFIED EXTERNALLY, metoda KERBEROS; także przez SessionManager")
    func kerberosLogin() async throws {
        let c = TestDatabase.config!
        let user = try #require(c.kerberosUser)
        var t = ConnectionTarget(user: "", connectString: c.connectString)
        t.externalAuth = true
        let s = try await ODPISession.connect(target: t, credentials: Credentials(password: nil))
        #expect(try await s.scalar("select user from dual") == user.uppercased())
        #expect(try await s.scalar("select sys_context('userenv', 'authentication_method') from dual") == "KERBEROS")
        #expect(try await s.scalar("select sys_context('userenv', 'authenticated_identity') from dual") == "dev_krb@PELIKAN.TEST")
        await s.close()

        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        var def = ConnectionDefinition(name: "dev_kerberos", target: t)
        def.savePassword = false
        try ws.connections.upsert(def, password: nil)
        let main = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(try await main.scalar("select user from dual") == user.uppercased())
        #expect(ws.connections.password(for: def.id) == nil)
        await ws.sessions.disconnectAll()

        // Logowanie hasłem w tym samym procesie działa dalej (Kerberos tylko dla połączeń zewnętrznych).
        let p = try await TestDatabase.connect()
        #expect(try await p.scalar("select sys_context('userenv', 'authentication_method') from dual") == "PASSWORD")
        await p.close()
    }
}

@Suite("Kerberos: blokada zamiast awarii procesu na macOS")
struct KerberosGuardTests {
    @Test("KERBEROS5 w sqlnet.ora (także przez IFILE) przy załadowanym Kerberos.framework — czytelny błąd, bez KERBEROS5 — nic")
    func guardOnMacOS() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("krb-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "SQLNET.AUTHENTICATION_SERVICES = (BEQ, KERBEROS5)\n".write(to: dir.appendingPathComponent("user.ora"), atomically: true, encoding: .utf8)
        try "IFILE=\"\(dir.path)/user.ora\"\n".write(to: dir.appendingPathComponent("sqlnet.ora"), atomically: true, encoding: .utf8)
        #expect(DirectoryNaming.sqlnetParameter("SQLNET.AUTHENTICATION_SERVICES", directories: ["/nonexistent", dir.path]) == "(BEQ,KERBEROS5)")
#if os(macOS)
        // Proces testów (jak aplikacja z AppKit) ma załadowany Kerberos.framework.
        let loaded = dlopen("/System/Library/Frameworks/Kerberos.framework/Kerberos", RTLD_LAZY | RTLD_NOLOAD) != nil
        if loaded {
            #expect(throws: DatabaseError.self) { try DirectoryLookup.checkKerberos(directories: [dir.path]) }
        }
#else
        try DirectoryLookup.checkKerberos(directories: [dir.path])
#endif
        try "SQLNET.AUTHENTICATION_SERVICES = (BEQ)\n".write(to: dir.appendingPathComponent("user.ora"), atomically: true, encoding: .utf8)
        try DirectoryLookup.checkKerberos(directories: [dir.path])
    }
}
