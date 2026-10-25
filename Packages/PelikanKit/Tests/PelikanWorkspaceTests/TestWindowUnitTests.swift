import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

@MainActor
@Suite("Test Window — bez bazy (PD-TEST-002, PD-TEST-005)")
struct TestWindowUnitTests {
    @Test("Substitution: :nazwa zastąpione tekstem wartości, inne zmienne bez zmian, napisy i komentarze nietknięte")
    func substitution() {
        let vars = [TestVariable(name: "tab", type: .substitution, value: "emp", isNull: false), TestVariable(name: "x", type: .integer, value: "1", isNull: false)]
        let text = "begin select count(*) into :x from :tab where ':tab' <> 'a'; -- :tab\nend;"
        #expect(TestRunner.substitute(text, vars) == "begin select count(*) into :x from emp where ':tab' <> 'a'; -- :tab\nend;")
        #expect(TestRunner.substitute(text, [vars[1]]) == text)
    }

    @Test("BFile: blok obudowany zmienną lokalną w pierwszej linii, :nazwa zastąpiona, wiązania katalogu i pliku")
    func bfileWrap() {
        let v = TestVariable(name: "plik", type: .bfile, value: "KAT:a.txt", isNull: false)
        let w = TestRunner.bfileWrap("begin\n  :plik := bfilename('X', 'b'); -- :plik\nend;", [v, TestVariable(name: "n", type: .integer)])
        #expect(w.sql.hasPrefix("declare pelikan$bf1 bfile := case when :pelikan_bf1_d is null"))
        #expect(w.sql.components(separatedBy: "\n")[0].hasSuffix("begin begin"))
        #expect(w.sql.contains("pelikan$bf1 := bfilename('X', 'b'); -- :plik") && w.sql.contains("dbms_lob.filegetname(pelikan$bf1, :pelikan_bf1_d, :pelikan_bf1_f)"))
        #expect(w.binds.map(\.value) == [.text("KAT"), .text("a.txt")])
        #expect(TestRunner.bfileWrap("begin null; end;", [TestVariable(name: "x")]).sql == "begin null; end;")
    }

    @Test("Plik .tst z obserwowanymi wyrażeniami; stary plik bez nich; obserwowane debugera to lista dokumentu")
    func watches() throws {
        let f = TestScriptFile(block: "begin null; end;", variables: [TestVariable(name: "a")], watches: ["v_total", "r.ename"])
        let back = TestScriptFile.decode(String(decoding: try f.encoded(), as: UTF8.self))
        #expect(back == f && back.watches == ["v_total", "r.ename"])
        let old = #"{"format":"pelikan-test","version":1,"block":"begin null; end;","variables":[]}"#
        #expect(TestScriptFile.decode(old).watches == nil)
        let ws = Workspace()
        let doc = ws.newDocument(.test, text: "begin null; end;")
        let d = ws.debugger(for: doc)
        d.watches = ["a", "b"]
        #expect(doc.testWatches == ["a", "b"])
        d.removeWatch("a")
        #expect(doc.testWatches == ["b"])
    }

    @Test("Zapis i wczytanie okna testu z obserwowanymi")
    func saveLoad() throws {
        let ws = Workspace()
        let doc = ws.newDocument(.test, text: "begin :a := 1; end;")
        TestRunner.synchronize(doc)
        doc.testWatches = ["i"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID().uuidString.prefix(6)).tst")
        defer { try? FileManager.default.removeItem(at: url) }
        try ws.save(doc, to: url)
        ws.close(doc.id)
        let loaded = try ws.openFile(url)
        #expect(loaded.testWatches == ["i"] && loaded.testVariables.map(\.name) == ["a"])
    }

    @Test("Błąd COMMIT po udanym wykonaniu: statystyki sesji policzone raz (PD-TEST-003)")
    func statisticsOnceOnCommitError() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: StatsDriver()])
        ws.settings.autoCommitTestWindow = true
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        let doc = ws.newDocument(.test, text: "begin null; end;")
        doc.connectionID = def.id
        await #expect(throws: OracleError.self) { try await TestRunner.execute(doc, in: ws) }
        #expect(doc.statisticTotals["session logical reads"] == 10)
    }
}

/// Atrapa sesji: V$MYSTAT rośnie o 10 przy każdym odczycie, COMMIT kończy się błędem.
private final class StatsSession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    let reads = Mutex(0)
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        guard sql.contains("v$mystat") else { return ExecutionResult(kind: .other) }
        return ExecutionResult(kind: .query, resultSet: ResultSetDescriptor(id: ResultSetID(1), columns: [
            ColumnInfo(name: "NAME", type: .varchar2, typeName: "VARCHAR2(64)"), ColumnInfo(name: "VALUE", type: .number, typeName: "NUMBER")]))
    }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch {
        let n = reads.withLock { $0 += 10; return $0 }
        return RowBatch(rows: [[.text("session logical reads"), .number(String(n))]], hasMore: false)
    }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws { throw OracleError(code: 2091, message: "ORA-02091: transaction rolled back") }
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
}

private final class StatsDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession { StatsSession() }
}
