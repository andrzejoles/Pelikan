import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Okno testu na bazie — Substitution i AutoCommit (PD-TEST-002, PD-TEST-003)", .enabled(if: TestDatabase.isAvailable), .serialized)
struct P1SessionDBTests {
    @Test("Zmienna Substitution wstawia nazwę tabeli; AutoCommit po wykonaniu zatwierdza zmiany widoczne w innej sesji")
    func substitutionAutoCommit() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let other = try await TestDatabase.connect()
        _ = try? await other.execute("drop table pelikan_ac purge")
        _ = try await other.execute("create table pelikan_ac (n number)")
        defer { Task { _ = try? await other.execute("drop table pelikan_ac purge") } }
        let doc = ws.newDocument(.test, text: "begin\n  insert into :tab values (1);\n  select count(*) into :n from :tab;\nend;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        TestRunner.synchronize(doc)
        doc.testVariables[0].type = .substitution
        doc.testVariables[0].value = "pelikan_ac"
        doc.testVariables[0].isNull = false
        doc.testVariables[1].type = .integer
        _ = try await TestRunner.execute(doc, in: ws)
        #expect(doc.testVariables[1].value == "1")
        var seen = try await other.queryAll("select count(*) from pelikan_ac").rows[0][0].format(.default)
        #expect(seen == "0")
        try await ws.endTransactions(of: [doc], commit: false)
        ws.settings.autoCommitTestWindow = true
        _ = try await TestRunner.execute(doc, in: ws)
        seen = try await other.queryAll("select count(*) from pelikan_ac").rows[0][0].format(.default)
        #expect(seen == "1" && !doc.transactionOpen)
        ws.settings.autoCommitTestWindow = false
    }

    @Test("BFile: wartość KATALOG:plik na wejściu i odczyt lokalizatora przypisanego w bloku (PD-TEST-002)")
    func bfile() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.test, text: "begin\n  :nazwa := case when :wej is null then 'brak' else 'jest' end;\n  :wej := bfilename('NOWY_KAT', 'b.txt');\nend;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        TestRunner.synchronize(doc)
        let i = try #require(doc.testVariables.firstIndex { $0.name == "wej" })
        doc.testVariables[i].type = .bfile
        doc.testVariables[i].value = "KAT:a.txt"
        doc.testVariables[i].isNull = false
        _ = try await TestRunner.execute(doc, in: ws)
        #expect(doc.testVariables.first { $0.name == "nazwa" }?.value == "jest")
        #expect(doc.testVariables[i].value == "NOWY_KAT:b.txt" && doc.testVariables[i].changed)
        await ws.sessions.disconnectAll()
    }
}
