import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@Suite("Oracle Net i Oracle Wallet bez bazy")
struct OracleNetTests {
    @Test("Katalog zarządzany: IFILE plików użytkownika, portfel w sqlnet.ora; bez konfiguracji — nic")
    func managedDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-net-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let user = tmp.appendingPathComponent("user"), wallet = tmp.appendingPathComponent("my wallet")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wallet, withIntermediateDirectories: true)
        try "x=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=h)(PORT=1))(CONNECT_DATA=(SERVICE_NAME=s)))".write(to: user.appendingPathComponent("tnsnames.ora"), atomically: true, encoding: .utf8)
        #expect(try OracleNet.prepareManagedDirectory(tmp.appendingPathComponent("none"), userDirectory: nil, walletDirectory: nil) == nil)
        let dir = try #require(try OracleNet.prepareManagedDirectory(tmp.appendingPathComponent("net"), userDirectory: user.path, walletDirectory: wallet.path))
        let sqlnet = try String(contentsOfFile: dir + "/sqlnet.ora", encoding: .utf8)
        #expect(sqlnet.contains("DIRECTORY=\"\(wallet.path)\"") && sqlnet.contains("SQLNET.WALLET_OVERRIDE=TRUE") && !sqlnet.contains("IFILE"))
        #expect(try String(contentsOfFile: dir + "/tnsnames.ora", encoding: .utf8).contains("IFILE=\"\(user.path)/tnsnames.ora\""))
        #expect(!FileManager.default.fileExists(atPath: dir + "/ldap.ora"))
        // ldap.ora użytkownika — dowiązanie w katalogu zarządzanym (LDAP, PD-CONN-013).
        try "DEFAULT_ADMIN_CONTEXT = \"dc=example,dc=invalid\"".write(to: user.appendingPathComponent("ldap.ora"), atomically: true, encoding: .utf8)
        _ = try OracleNet.prepareManagedDirectory(tmp.appendingPathComponent("net"), userDirectory: user.path, walletDirectory: wallet.path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: dir + "/ldap.ora") == user.path + "/ldap.ora")
        #expect(OracleNet.walletStatus(wallet.path) == .missing)
        FileManager.default.createFile(atPath: wallet.appendingPathComponent("ewallet.p12").path, contents: Data())
        #expect(OracleNet.walletStatus(wallet.path) == .passwordOnly)
        FileManager.default.createFile(atPath: wallet.appendingPathComponent("cwallet.sso").path, contents: Data())
        #expect(OracleNet.walletStatus(wallet.path) == .autoLogin)
    }

    @Test("Connect string: portfel TLS połączenia w tcps:// i deskryptorze TCPS; alias magazynu haseł bez rozwijania")
    func resolve() {
        #expect(TNSNames.resolveForConnection("tcps://h:1522/s", configDirectory: nil, walletDirectory: "/w") == "tcps://h:1522/s?wallet_location=/w")
        #expect(TNSNames.resolveForConnection("tcps://h:1522/s?x=1", configDirectory: nil, walletDirectory: "/w") == "tcps://h:1522/s?x=1&wallet_location=/w")
        let d = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=h)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=s)))"
        #expect(TNSNames.resolveForConnection(d, configDirectory: "/cfg", walletDirectory: "/w").contains("(SECURITY=(MY_WALLET_DIRECTORY=/w))"))
        #expect(TNSNames.resolveForConnection(d, configDirectory: "/cfg").contains("MY_WALLET_DIRECTORY=/cfg"))
        #expect(TNSNames.resolveForConnection("h:1521/s", configDirectory: nil, walletDirectory: nil) == "h:1521/s")
        #expect(TNSNames.resolveForConnection("MOJ_ALIAS", configDirectory: "/nie/ma", keepAlias: true) == "MOJ_ALIAS")
        var t = ConnectionTarget(user: "", connectString: "a")
        #expect(!t.usesExternalCredentials)
        t.walletAuth = true
        #expect(t.usesExternalCredentials)
    }
}

@MainActor
@Suite("Oracle Wallet na bazie testowej", .enabled(if: TestDatabase.isWalletAvailable), .serialized)
struct OracleWalletDBTests {
    @Test("Połączenie /@alias poświadczeniem z portfela (bez hasła w Pelikanie), także przez SessionManager")
    func sepsConnection() async throws {
        var t = ConnectionTarget(user: "", connectString: "dev_pelikan_seps")
        t.walletAuth = true
        let s = try await ODPISession.connect(target: t, credentials: Credentials(password: nil))
        #expect(try await s.scalar("select user from dual") == TestDatabase.config!.user.uppercased())
        await s.close()
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        var def = ConnectionDefinition(name: "dev_portfel", target: t)
        def.savePassword = false
        try ws.connections.upsert(def, password: nil)
        ws.sessions.setMainConnection(def.id)
        let main = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(try await main.scalar("select 'OK' from dual") == "OK")
        #expect(ws.connections.password(for: def.id) == nil)
        await ws.sessions.disconnectAll()
    }
}
