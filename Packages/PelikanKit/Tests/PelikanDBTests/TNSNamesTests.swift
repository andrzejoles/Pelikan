import Foundation
import PelikanDB
import Testing

@Suite("tnsnames.ora")
struct TNSNamesTests {
    let sample = """
    # Komentarz
    DEV =
      (DESCRIPTION =
        (ADDRESS = (PROTOCOL = TCP)(HOST = dev.example.com)(PORT = 1521))
        (CONNECT_DATA = (SERVICE_NAME = devpdb))  # komentarz w linii
      )

    PROD, PROD_ALIAS=(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=a)(PORT=1521))(ADDRESS=(PROTOCOL=TCP)(HOST=b)(PORT=1521)))
      (CONNECT_DATA=(SERVICE_NAME=prod)))
    ADB = (description= (retry_count=20)(address=(protocol=tcps)(port=1522)(host=adb.eu-frankfurt-1.oraclecloud.com))
           (connect_data=(service_name=x_high.adb.oraclecloud.com))(security=(ssl_server_dn_match=yes)))
    OLD = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=old)(PORT=1521))(CONNECT_DATA=(SID=ORCL)))
    BROKEN = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=x)
    """

    @Test("Aliasy, wiele nazw na wpis, komentarze, wielkość liter")
    func parse() {
        let e = TNSNames.parse(sample)
        #expect(e.map(\.name) == ["DEV", "PROD", "ADB", "OLD"])
        #expect(e[1].aliases == ["PROD", "PROD_ALIAS"])
        #expect(e[0].host == "dev.example.com")
        #expect(e[0].port == 1521)
        #expect(e[0].serviceName == "devpdb")
        #expect(e[3].sid == "ORCL")
        // Spacje w wartościach w cudzysłowie zostają (DN certyfikatu, katalog portfela) — przegląd kodu, D168.
        let dn = TNSNames.parse(#"TLS = (DESCRIPTION = (ADDRESS = (PROTOCOL = TCPS)(HOST = h)(PORT = 2484)) (SECURITY = (SSL_SERVER_CERT_DN = "CN=db, O=Oracle Corporation, L=Redwood City")))"#)
        #expect(dn.first?.descriptor == #"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=h)(PORT=2484))(SECURITY=(SSL_SERVER_CERT_DN="CN=db, O=Oracle Corporation, L=Redwood City")))"#)
    }

    @Test("Rozwinięcie do EZConnect dla sterownika thin (proste wpisy), złożone — nil")
    func easyConnect() {
        let e = TNSNames.parse(sample)
        #expect(TNSNames.easyConnect(for: e[0]) == "dev.example.com:1521/devpdb")
        #expect(TNSNames.easyConnect(for: e[1]) == nil)   // failover — tylko Instant Client
        #expect(TNSNames.easyConnect(for: e[2]) == "tcps://adb.eu-frankfurt-1.oraclecloud.com:1522/x_high.adb.oraclecloud.com")
    }

    @Test("IFILE dołącza inny plik (ścieżka względna)")
    func ifile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-tns-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "A = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=h)(PORT=1))(CONNECT_DATA=(SERVICE_NAME=s)))\nIFILE = extra.ora\n"
            .write(to: dir.appendingPathComponent("tnsnames.ora"), atomically: true, encoding: .utf8)
        try "B = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=h2)(PORT=2))(CONNECT_DATA=(SERVICE_NAME=s2)))\n"
            .write(to: dir.appendingPathComponent("extra.ora"), atomically: true, encoding: .utf8)
        let e = TNSNames.load(directories: [dir.path])
        #expect(e.map(\.name) == ["A", "B"])
    }

    @Test("Kolejność katalogów: ustawienia połączenia, TNS_ADMIN, ORACLE_HOME, Instant Client")
    func searchOrder() {
        let d = TNSNames.searchDirectories(configured: "/conf", environment: ["TNS_ADMIN": "/tns", "ORACLE_HOME": "/oh"],
                                           instantClientDirectory: "/ic")
        #expect(d == ["/conf", "/tns", "/oh/network/admin", "/ic/network/admin"])
    }
}

@Suite("Katalog konfiguracji połączenia")
struct ConnectionConfigDirectoryTests {
    @Test("Alias z katalogu połączenia → deskryptor; TCPS dostaje MY_WALLET_DIRECTORY; bez katalogu — bez zmian")
    func resolve() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-tns-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        ADB_HIGH = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=adb.example)(PORT=1522))(CONNECT_DATA=(SERVICE_NAME=x_high)))
        LOCAL = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=localhost)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=FREEPDB1)))
        """.write(to: dir.appendingPathComponent("tnsnames.ora"), atomically: true, encoding: .utf8)
        let adb = TNSNames.resolveForConnection("adb_high", configDirectory: dir.path)
        #expect(adb.contains("(HOST=adb.example)") && adb.contains("(SECURITY=(MY_WALLET_DIRECTORY=\(dir.path)))"))
        let local = TNSNames.resolveForConnection("LOCAL", configDirectory: dir.path)
        #expect(local.contains("(HOST=localhost)") && !local.contains("SECURITY"))
        #expect(TNSNames.resolveForConnection("LOCAL", configDirectory: nil) == "LOCAL")
        #expect(TNSNames.resolveForConnection("host:1521/svc", configDirectory: dir.path) == "host:1521/svc")
        // Deskryptor wklejony w polu „Baza” w zwykłym zapisie Oracle Net, w wielu liniach (R8-04).
        let pasted = """

        (DESCRIPTION =
          (ADDRESS = (PROTOCOL = TCPS)(HOST = db.example.org)(PORT = 2484))
          (CONNECT_DATA = (SERVICE_NAME = sklep))
        )
        """
        #expect(TNSNames.value("host", in: pasted) == "db.example.org" && TNSNames.value("PORT", in: pasted) == "2484")
        #expect(TNSNames.value("SERVICE_NAME", in: pasted) == "sklep" && TNSNames.value("SID", in: pasted) == nil)
        #expect(TNSNames.resolveForConnection(pasted, configDirectory: dir.path).contains("(SECURITY=(MY_WALLET_DIRECTORY=\(dir.path)))"))
        #expect(TNSNames.value("SSL_SERVER_CERT_DN", in: "(SECURITY = (SSL_SERVER_CERT_DN = \"CN=a b, O=c\"))") == "\"CN=a b, O=c\"")
    }
}
