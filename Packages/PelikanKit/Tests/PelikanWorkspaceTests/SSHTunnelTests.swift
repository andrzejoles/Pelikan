import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@Suite("Tunel SSH — bez serwera")
struct SSHTunnelUnitTests {
    @Test("Host i port z EZConnect, URL tcps, IPv6 i deskryptora")
    func endpoint() {
        #expect(ConnectStringRewriter.endpoint(of: "db.example.org:1522/ORCL") == .init(host: "db.example.org", port: 1522))
        #expect(ConnectStringRewriter.endpoint(of: "db/ORCL") == .init(host: "db", port: 1521))
        #expect(ConnectStringRewriter.endpoint(of: "tcps://adb.region.oraclecloud.com:1522/x_high.adb") == .init(host: "adb.region.oraclecloud.com", port: 1522))
        #expect(ConnectStringRewriter.endpoint(of: "//[fd00::5]:1530/svc") == .init(host: "fd00::5", port: 1530))
        #expect(ConnectStringRewriter.endpoint(of: "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=10.0.0.5)(PORT=1525))(CONNECT_DATA=(SERVICE_NAME=S)))") == .init(host: "10.0.0.5", port: 1525))
        #expect(ConnectStringRewriter.endpoint(of: "ALIAS_TNS") == nil)
    }

    @Test("Przepisanie na 127.0.0.1:port lokalny (EZConnect, tcps, deskryptor, alias TNS)")
    func rewrite() {
        #expect(ConnectStringRewriter.rewrite("db.example.org:1522/ORCL", localPort: 40001) == "127.0.0.1:40001/ORCL")
        #expect(ConnectStringRewriter.rewrite("tcps://adb.example:1522/svc?wallet_location=/w", localPort: 40001) == "tcps://127.0.0.1:40001/svc?wallet_location=/w")
        let d = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST = 10.0.0.5)(PORT = 1525))(CONNECT_DATA=(SERVICE_NAME=S)))"
        #expect(ConnectStringRewriter.rewrite(d, localPort: 40002) == "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=127.0.0.1)(PORT=40002))(CONNECT_DATA=(SERVICE_NAME=S)))")
        let tns = TNSNames.parse("PROD = \(d)")
        #expect(ConnectStringRewriter.rewrite("prod", localPort: 40003, tns: tns)?.contains("(PORT=40003)") == true)
    }

    @Test("Argumenty ssh: przekierowanie, port, klucz, ProxyJump, BatchMode (bez haseł)")
    func arguments() {
        let t = SSHTunnel(host: "bastion.example", port: 2200, user: "ops", identityFile: "~/.ssh/id_ed25519", jumpHost: "jump.example")
        let a = SSHTunnelManager.arguments(t, localPort: 41000, remote: .init(host: "db.internal", port: 1521), extra: [])
        #expect(a.contains("127.0.0.1:41000:db.internal:1521"))
        #expect(a.contains("BatchMode=yes") && a.contains("ExitOnForwardFailure=yes"))
        #expect(a[a.firstIndex(of: "-p")! + 1] == "2200")
        #expect(a[a.firstIndex(of: "-J")! + 1] == "jump.example")
        #expect(a.last == "ops@bastion.example")
        #expect(!a.contains { $0.hasPrefix("~") })        // ścieżka klucza rozwinięta
        #expect(SSHTunnelManager.freePort().map { $0 > 1024 } == true)
    }
}
