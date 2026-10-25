import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@Suite("Edytor tabeli: DDL partycji, adnotacji, uprawnień i ROW ARCHIVAL bez bazy")
struct TableEditorStage8OfflineTests {
    @Test("CREATE z partycjami RANGE/INTERVAL, HASH i LIST, ROW ARCHIVAL, adnotacjami, domeną i uprawnieniem")
    func create() {
        var d = TableDefinition(owner: "HR", name: "T")
        var c = TableDefinition.Column(name: "EMAIL", type: "VARCHAR2(100)")
        c.domain = "HR.EMAIL_D"
        c.annotations = [.init(name: "Display", value: "E-mail")]
        d.columns = [TableDefinition.Column(name: "D", type: "DATE"), c]
        var p = TableDefinition.Partitioning(method: .range, columns: ["D"])
        p.interval = "NUMTOYMINTERVAL(1,'MONTH')"
        p.partitions = [.init(name: "P0", values: "DATE '2026-01-01'")]
        d.partitioning = p
        d.rowArchival = true
        d.annotations = [.init(name: "Opis", value: "it's")]
        d.grants = [.init(grantee: "APP", privilege: "select", grantable: true)]
        let s = TableDDL.statements(from: nil, to: d)
        #expect(s[0].contains("EMAIL VARCHAR2(100) DOMAIN HR.EMAIL_D ANNOTATIONS (\"Display\" 'E-mail')"))
        #expect(s[0].contains("PARTITION BY RANGE (D) INTERVAL (NUMTOYMINTERVAL(1,'MONTH')) (\n  PARTITION P0 VALUES LESS THAN (DATE '2026-01-01')\n)"))
        #expect(s[0].contains("ROW ARCHIVAL") && s[0].contains("ANNOTATIONS (\"Opis\" 'it''s')"))
        #expect(s.last == "GRANT SELECT ON HR.T TO APP WITH GRANT OPTION")
        var h = TableDefinition.Partitioning(method: .hash, columns: ["D"]); h.partitions = [.init(name: "H1"), .init(name: "H2")]
        #expect(TableDDL.partitionClause(h) == "PARTITION BY HASH (D) (PARTITION H1, PARTITION H2)")
    }

    @Test("Zmiany: domena kolumny, adnotacje (DROP/ADD), ROW ARCHIVAL, uprawnienia (REVOKE/GRANT)")
    func alter() {
        var old = TableDefinition(owner: "HR", name: "T")
        old.originalName = "T"
        var c = TableDefinition.Column(name: "E", type: "VARCHAR2(10)"); c.originalName = "E"
        c.annotations = [.init(name: "A", value: "1")]
        old.columns = [c]
        old.grants = [.init(grantee: "APP", privilege: "SELECT"), .init(grantee: "RPT", privilege: "SELECT")]
        var new = old
        new.columns[0].domain = "HR.D1"
        new.columns[0].annotations = [.init(name: "A", value: "2"), .init(name: "B")]
        new.rowArchival = true
        new.grants = [.init(grantee: "APP", privilege: "SELECT", grantable: true), .init(grantee: "NEW", privilege: "UPDATE")]
        let s = TableDDL.statements(from: old, to: new)
        #expect(s.contains("ALTER TABLE HR.T MODIFY (E DOMAIN HR.D1)"))
        #expect(s.contains("ALTER TABLE HR.T MODIFY (E ANNOTATIONS (DROP A))"))
        #expect(s.contains("ALTER TABLE HR.T MODIFY (E ANNOTATIONS (ADD A '2', ADD B))"))
        #expect(s.contains("ALTER TABLE HR.T ROW ARCHIVAL"))
        #expect(s.contains("REVOKE SELECT ON HR.T FROM RPT") && s.contains("REVOKE SELECT ON HR.T FROM APP"))
        #expect(s.contains("GRANT SELECT ON HR.T TO APP WITH GRANT OPTION") && s.contains("GRANT UPDATE ON HR.T TO NEW"))
    }
}

@MainActor
@Suite("Edytor tabeli Etapu 8 na bazie", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(2)))
struct TableEditorStage8DBTests {
    @Test("Tabela partycjonowana z domeną, adnotacjami i ROW ARCHIVAL: utworzenie, wczytanie, zmiany, uprawnienia; DDL domeny")
    func roundTrip() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let m = try #require(ws.metadata())
        let s = try await TestDatabase.connect()
        let owner = try await m.currentSchema()
        _ = try? await s.execute("drop table pelikan_oed purge")
        _ = try? await s.execute("drop domain pelikan_oed_d")
        _ = try await s.execute("create domain pelikan_oed_d as varchar2(50) constraint pelikan_oed_dc check (value like '%@%')")
        var d = TableDefinition(owner: owner, name: "PELIKAN_OED")
        var email = TableDefinition.Column(name: "EMAIL", type: "VARCHAR2(50)")
        email.domain = "\(owner).PELIKAN_OED_D"
        email.annotations = [.init(name: "Display", value: "E-mail")]
        d.columns = [TableDefinition.Column(name: "ID", type: "NUMBER", nullable: false), email]
        var p = TableDefinition.Partitioning(method: .hash, columns: ["ID"]); p.partitions = [.init(name: "P1"), .init(name: "P2")]
        d.partitioning = p
        d.rowArchival = true
        d.annotations = [.init(name: "Opis", value: "Tabela testowa")]
        for sql in TableDDL.statements(from: nil, to: d) { _ = try await s.execute(sql) }
        var loaded = try await TableDDL.load(owner: owner, name: "PELIKAN_OED", metadata: m)
        #expect(loaded.columns.first { $0.name == "EMAIL" }?.domain == "\(owner).PELIKAN_OED_D")
        #expect(loaded.columns.first { $0.name == "EMAIL" }?.annotations.first?.value == "E-mail")
        #expect(loaded.annotations.contains { $0.name.uppercased() == "OPIS" } && loaded.rowArchival && loaded.partitionInfo.hasPrefix("HASH"))
        var changed = loaded
        changed.rowArchival = false
        changed.grants = [.init(grantee: "PUBLIC", privilege: "SELECT")]
        if let i = changed.columns.firstIndex(where: { $0.name == "EMAIL" }) { changed.columns[i].annotations = [.init(name: "Display", value: "Poczta")] }
        for sql in TableDDL.statements(from: loaded, to: changed) { _ = try await s.execute(sql) }
        loaded = try await TableDDL.load(owner: owner, name: "PELIKAN_OED", metadata: m)
        #expect(!loaded.rowArchival && loaded.grants.contains { $0.grantee == "PUBLIC" && $0.privilege == "SELECT" })
        #expect(loaded.columns.first { $0.name == "EMAIL" }?.annotations.first?.value == "Poczta")
        #expect(TableDDL.statements(from: loaded, to: loaded).isEmpty)
        let ddl = try await m.ddl(of: DBObject(owner: owner, name: "PELIKAN_OED_D", type: .domain))
        #expect(ddl.uppercased().contains("CREATE DOMAIN") && ddl.contains("PELIKAN_OED_D"))
        _ = try await s.execute("drop table pelikan_oed purge")
        _ = try await s.execute("drop domain pelikan_oed_d")
        await s.close()
        await ws.sessions.disconnectAll()
    }
}
