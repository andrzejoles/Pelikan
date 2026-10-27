import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Sesja, której kolejne polecenia kończą się błędami z kolejki (pusta kolejka — zapytanie bez wierszy).
final class QueuedErrorSession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 19, minor: 0),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    let errors = Mutex<[OracleError]>([])
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        if let e = errors.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { throw e }
        return ExecutionResult(kind: .query, resultSet: ResultSetDescriptor(id: ResultSetID(1), columns: []))
    }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch { RowBatch(rows: [], hasMore: false) }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
}

/// Sterownik zwracający zawsze tę samą sesję.
final class SingleSessionDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    let session: any DatabaseSession
    init(_ session: any DatabaseSession) { self.session = session }
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession { session }
}

/// Metadane słownika i czynności Object Browsera (czwarta runda przeglądu, D185, D187, D188) — bez bazy.
@MainActor
@Suite("Object Browser: słownik, łącza i DDL — bez bazy")
struct ObjectMetadataFixesTests {
    @Test("Czytelność widoku DBA_: błąd uprawnień pamiętany jako „nie”, inny błąd (utrata sesji) przekazany i niepamiętany")
    func readableView() async throws {
        let s = QueuedErrorSession()
        let ws = Workspace(drivers: [.instantClient: SingleSessionDriver(s)])
        let def = ConnectionDefinition(name: "dev_a", target: ConnectionTarget(user: "u", connectString: "a"))
        try ws.connections.upsert(def, password: "good")
        ws.sessions.setMainConnection(def.id)
        let m = try #require(ws.metadata())
        _ = try await m.session()
        s.errors.withLock { $0 = [OracleError(code: 3113, message: "ORA-03113: end-of-file on communication channel")] }
        await #expect(throws: OracleError.self) { try await m.readable("dba_db_links") }
        #expect(try await m.readable("dba_db_links"), "chwilowy błąd nie zostaje zapamiętany jako brak uprawnień")
        s.errors.withLock { $0 = [OracleError(code: 942, message: "ORA-00942: table or view does not exist")] }
        #expect(try await m.readable("dba_directories") == false)
        #expect(try await m.readable("dba_directories") == false, "wynik pamiętany do odświeżenia")
    }

    @Test("Prywatne łącze innego schematu: DROP i test odrzucone; własne i publiczne — dozwolone")
    func foreignLink() throws {
        #expect(throws: CommandError.self) {
            try MultiObjectCommands.requireOwnLink(DBObject(owner: "SYSTEM", name: "L", type: .databaseLink), sessionUser: "HR")
        }
        try MultiObjectCommands.requireOwnLink(DBObject(owner: "HR", name: "L", type: .databaseLink), sessionUser: "HR")
        try MultiObjectCommands.requireOwnLink(DBObject(owner: "PUBLIC", name: "L", type: .databaseLink), sessionUser: "HR")
        try MultiObjectCommands.requireOwnLink(DBObject(owner: "SYSTEM", name: "T", type: .table), sessionUser: "HR")
    }

    @Test("DDL: typy DBMS_METADATA zadań i kolejek, przywrócenie parametrów przekształcenia sesji")
    func ddlType() async throws {
        #expect(MetadataProvider.metadataType(.job) == "PROCOBJ")
        #expect(MetadataProvider.metadataType(.queue) == "AQ_QUEUE")
        #expect(MetadataProvider.metadataType(.packageBody) == "PACKAGE_BODY")
        #expect(MetadataProvider.metadataType(.materializedView) == "MATERIALIZED_VIEW")
        let s = SQLCaptureSession()
        _ = try await MetadataProvider.ddl(of: DBObject(owner: "U", name: "J1", type: .job), in: s)
        let q = try #require(s.queries.withLock { $0.first })
        #expect(q.binds.first { $0.name == "t" }?.value == .text("PROCOBJ"))
        #expect(q.sql.components(separatedBy: "session_transform, 'DEFAULT')").count == 3, "po GET_DDL i w obsłudze błędu")
    }

    @Test("Nazwa w cudzysłowie w diagramie i Query Builderze: bez zmiany wielkości liter, bez cudzysłowu — wielkie litery")
    func quotedResolve() async throws {
        let s = SQLCaptureSession()
        _ = try await SessionSchemaMetadata(session: s).resolve("hr.\"MojaTabela\"")
        _ = try await SessionSchemaMetadata(session: s).resolve("emp")
        let binds = s.queries.withLock { $0.map(\.binds) }
        #expect(binds[0].first { $0.name == "n" }?.value == .text("MojaTabela"))
        #expect(binds[0].first { $0.name == "o" }?.value == .text("HR"))
        #expect(binds.last { $0.contains { $0.name == "o" } }?.first { $0.name == "n" }?.value == .text("EMP"))
    }

    @Test("Edytor tabeli: indeks innego schematu usuwany i zmieniany w schemacie indeksu")
    func indexOwner() {
        var old = TableDefinition(owner: "HR", name: "T")
        old.originalName = "T"
        var a = TableDefinition.Index(name: "T_A", columns: ["ID"])
        a.originalName = "T_A"
        a.owner = "IDX"
        var b = TableDefinition.Index(name: "T_B", columns: ["X"])
        b.originalName = "T_B"
        b.owner = "IDX"
        old.indexes = [a, b]
        var new = old
        new.indexes.removeFirst()
        new.indexes[0].name = "T_B2"
        new.indexes[0].invisible = true
        let sql = TableDDL.statements(from: old, to: new)
        #expect(sql.contains("DROP INDEX IDX.T_A"), "\(sql)")
        #expect(sql.contains("ALTER INDEX IDX.T_B RENAME TO T_B2") && sql.contains("ALTER INDEX IDX.T_B2 INVISIBLE"), "\(sql)")
    }
}
