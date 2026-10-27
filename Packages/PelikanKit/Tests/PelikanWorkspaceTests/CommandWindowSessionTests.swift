import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Sesja, której każde polecenie kończy się utratą połączenia (ORA-03113).
final class DeadSession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        throw OracleError(code: 3113, message: "ORA-03113: end-of-file on communication channel")
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

/// Pierwsza sesja martwa, kolejne zdrowe (FakeSession); liczy połączenia.
final class LostOnceDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    let connects = Mutex(0)
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession {
        let n = connects.withLock { $0 += 1; return $0 }
        return n == 1 ? DeadSession() : FakeSession()
    }
}

/// Sesja z REF CURSOR: blok PL/SQL zwraca kursor w zmiennej `rc`, opis kolumn i wiersze kursora.
final class CursorSession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        ExecutionResult(kind: .plsql, outBinds: ["rc": .cursor(ResultSetID(7))])
    }
    func columns(of resultSet: ResultSetID) async -> [ColumnInfo] { [ColumnInfo(name: "ENAME", type: .varchar2, typeName: "VARCHAR2(10)")] }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch {
        try await Task.sleep(for: .milliseconds(20))   // pobranie trwa — wiersze muszą wyprzedzić kolejne polecenia
        return RowBatch(rows: [[.text("KING")], [.text("FORD")]], hasMore: false)
    }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
}

final class CursorDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession { CursorSession() }
}

@MainActor
@Suite("Command Window: sesje, utrata połączenia, pliki skryptów, SPOOL (przegląd 4)")
struct CommandWindowSessionTests {
    func workspace(_ driver: any DatabaseDriver) throws -> (Workspace, ConnectionDefinition) {
        let ws = Workspace(drivers: [.instantClient: driver])
        let def = ConnectionDefinition(name: "dev_x", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        ws.sessions.setMainConnection(def.id)
        return (ws, def)
    }

    func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cmdw-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Tryb Dwie sesje: DISCONNECT i CONNECT w Oknie poleceń nie zamykają wspólnej sesji głównej (transakcja okna SQL zostaje)")
    func dualModeKeepsSharedSession() async throws {
        let driver = FakeDriver()
        let (ws, def) = try workspace(driver)
        let other = ConnectionDefinition(name: "dev_y", target: ConnectionTarget(user: "v", connectString: "db"))
        try ws.connections.upsert(other, password: "good")
        ws.settings.sessionMode = .dual
        let sql = ws.newDocument(.sql)
        _ = try await ws.session(for: sql)
        sql.transactionOpen = true
        let main = SessionKey(connectionID: def.id, purpose: .main)
        let shared = try #require(ws.sessions.existingSession(main) as? FakeSession)
        let cmd = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: cmd)
        _ = await engine.run("disconnect")
        #expect(cmd.isDisconnected && ws.sessions.existingSession(main) === shared && !shared.closedFlag.withLock { $0 })
        _ = await engine.run("connect dev_x")
        _ = await engine.run("connect dev_y")
        #expect(ws.effectiveConnection(of: cmd) == other.id && cmd.console.last?.text == "Połączono jako U.")
        #expect(ws.sessions.existingSession(main) === shared && !shared.closedFlag.withLock { $0 })
        #expect(sql.transactionOpen && shared.transactions.withLock { $0 }.isEmpty)
        // Tryb Wiele sesji: własna sesja okna jest zamykana.
        ws.settings.sessionMode = .multi
        _ = await engine.run("connect dev_x")
        let ownKey = try #require(ws.sessionKey(for: cmd))
        let own = try #require(ws.sessions.existingSession(ownKey) as? FakeSession)
        _ = await engine.run("disconnect")
        #expect(own.closedFlag.withLock { $0 } && ws.sessions.existingSession(main) === shared)
    }

    @Test("Utrata połączenia w Oknie poleceń: martwa sesja usunięta, kolejne polecenie łączy się ponownie")
    func lostConnectionReconnects() async throws {
        let driver = LostOnceDriver()
        let (ws, _) = try workspace(driver)
        let cmd = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: cmd)
        cmd.transactionOpen = true
        _ = await engine.run("update t set x = 1;")
        #expect(cmd.console.map(\.text).contains("Połączenie utracone — kolejne polecenie połączy się ponownie."))
        #expect(!cmd.transactionOpen)
        cmd.console.removeAll()
        _ = await engine.run("select 1 from dual;")
        #expect(driver.connects.withLock { $0 } == 2 && cmd.console.last?.text == "Wykonano.", "\(cmd.console.map(\.text))")
    }

    @Test("Utrata połączenia w oknie SQL i oknie testu: kolejne wykonanie łączy się ponownie, sesja innego okna nietknięta")
    func lostConnectionSQLAndTestWindow() async throws {
        let driver = LostOnceDriver()
        let (ws, _) = try workspace(driver)
        let doc = ws.newDocument(.sql, text: "select 1 from dual")
        _ = try? await SQLExecutor.execute(doc, scope: .standard, in: ws)
        #expect(ws.sessions.openSessionCount == 0)
        _ = try? await SQLExecutor.execute(doc, scope: .standard, in: ws)
        #expect(driver.connects.withLock { $0 } == 2 && ws.sessions.openSessionCount == 1)
        // Okno testu: sesja martwa usunięta, zdrowa sesja okna SQL zostaje.
        let test = ws.newDocument(.test, text: "begin null; end;")
        ws.sessions.setDriver(LostDriverForExecute())
        test.transactionOpen = true
        await #expect(throws: OracleError.self) { try await TestRunner.execute(test, in: ws) }
        let sqlKey = try #require(ws.sessionKey(for: doc)), testKey = try #require(ws.sessionKey(for: test))
        #expect(!test.transactionOpen && ws.sessions.existingSession(sqlKey) != nil && ws.sessions.existingSession(testKey) == nil)
    }

    @Test("WHENEVER OSERROR EXIT ROLLBACK bez otwartej sesji nie łączy się tylko po to, by wycofać")
    func exitOnErrorDoesNotConnect() async throws {
        let driver = FakeDriver()
        let (ws, _) = try workspace(driver)
        let cmd = ws.newDocument(.command)
        let o = await ws.sqlplusEngine(for: cmd).run("whenever oserror exit rollback\n@/nie/ma/takiego/pliku.sql")
        #expect(o == .exit && driver.attempts.withLock { $0 }.isEmpty)
        // Z otwartą sesją — ROLLBACK w niej.
        let s = try #require(try await ws.session(for: cmd) as? FakeSession)
        _ = await ws.sqlplusEngine(for: cmd).run("@/nie/ma/takiego/pliku.sql")
        #expect(s.transactions.withLock { $0 } == ["rollback"])
    }

    @Test("PRINT REF CURSOR: wiersze z nagłówkiem przed wyjściem kolejnych poleceń skryptu")
    func printRefCursorInOrder() async throws {
        let (ws, _) = try workspace(CursorDriver())
        let cmd = ws.newDocument(.command)
        _ = await ws.sqlplusEngine(for: cmd).run("variable rc refcursor\nbegin open :rc for select ename from emp; end;\n/\nprint rc\nprompt koniec")
        let text = cmd.console.map(\.text)
        let king = try #require(text.firstIndex { $0.contains("KING") }, "\(text)")
        #expect(text.contains { $0.hasPrefix("ENAME") } && text.firstIndex(of: "koniec").map { $0 > king } == true, "\(text)")
    }

    @Test("@plik w Windows-1250 i z BOM: polskie litery bez U+FFFD, BOM nie psuje pierwszego polecenia; GET")
    func scriptEncodings() async throws {
        let (ws, _) = try workspace(FakeDriver())
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let polish = "insert into t values ('zażółć gęślą jaźń');\n"
        try #require(polish.data(using: .windowsCP1250)).write(to: dir.appendingPathComponent("cp.sql"))
        try (Data([0xEF, 0xBB, 0xBF]) + Data("prompt z BOM\r\nselect 1 from dual;\r\n".utf8)).write(to: dir.appendingPathComponent("bom.sql"))
        let cmd = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: cmd)
        engine.state.directory = dir
        _ = await engine.run("@cp\n@bom")
        let session = try #require(try await ws.session(for: cmd) as? FakeSession)
        let executed = session.executed.withLock { $0 }
        #expect(executed.contains { $0.contains("zażółć gęślą jaźń") } && !executed.contains { $0.contains("\u{FFFD}") }, "\(executed)")
        #expect(cmd.console.map(\.text).contains("z BOM"), "\(cmd.console.map(\.text))")
        _ = await engine.run("get cp")
        #expect(engine.state.buffer == "insert into t values ('zażółć gęślą jaźń');")
    }

    @Test("FORMAT FILE zachowuje kodowanie, BOM i CRLF pliku")
    func formatFileKeepsFormat() async throws {
        let ws = Workspace()
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("f.sql")
        try (Data([0xEF, 0xBB, 0xBF]) + Data("SELECT 'żółw' FROM dual;\r\n".utf8)).write(to: url)
        let cmd = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: cmd)
        engine.state.directory = dir
        _ = await engine.run("format file f.sql")
        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]), "\(cmd.console.map(\.text))")
        let (text, format) = TextFileCodec.decode(data)
        #expect(format.lineEnding == .crlf && text.contains("żółw"))
        // Windows-1250 zostaje Windows-1250.
        let cp = dir.appendingPathComponent("cp.sql")
        try #require("select 'gęślą' from dual;\r\n".data(using: .windowsCP1250)).write(to: cp)
        _ = await engine.run("format file cp.sql")
        #expect(String(data: try Data(contentsOf: cp), encoding: .utf8) == nil)
        #expect(TextFileCodec.decode(try Data(contentsOf: cp)).text.contains("gęślą"))
    }

    @Test("SPOOL: błąd zapisu wyłącza SPOOL z jednym komunikatem (bez wyjątku Objective-C)")
    func spoolWriteError() async throws {
        let ws = Workspace()
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cmd = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: cmd)
        engine.state.directory = dir
        _ = await engine.run("spool wynik.lst\nprompt pierwsza")
        let url = dir.appendingPathComponent("wynik.lst")
        #expect(try String(contentsOf: url, encoding: .utf8).contains("pierwsza"))
        // Plik zastąpiony katalogiem — zapis kończy się błędem.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        _ = await engine.run("prompt druga\nprompt trzecia")
        #expect(engine.state.spoolURL == nil)
        #expect(cmd.console.map(\.text).filter { $0.hasPrefix("SP2-0606") }.count == 1 && cmd.console.map(\.text).contains("trzecia"))
        #expect(throws: (any Error).self) { try SQLPlusEngine.append("x", to: url) }
    }

    @Test("Konsola przycinana partiami: po przekroczeniu limitu do 90 000 linii, kolejne linie bez przycinania")
    func consoleTrimmedInBatches() async {
        let ws = Workspace()
        let cmd = ws.newDocument(.command)
        let engine = ws.sqlplusEngine(for: cmd)
        engine.emit(Array(repeating: "x", count: SQLPlusEngine.consoleMaxLines + 1).joined(separator: "\n"))
        #expect(cmd.console.count == SQLPlusEngine.consoleTrimmedLines)
        let first = cmd.console.first?.id
        engine.emit("y")
        #expect(cmd.console.count == SQLPlusEngine.consoleTrimmedLines + 1 && cmd.console.first?.id == first)
    }
}

/// Każda sesja martwa przy wykonaniu (okno testu).
final class LostDriverForExecute: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession { DeadSession() }
}

@MainActor
@Suite("Budowanie projektu, raporty użytkownika (przegląd 4)")
struct ProjectAndReportReviewTests {
    @Test("Build: parametry kompilatora z Preferencji, polecenia spoza jednostek programów — informacja bez błędu")
    func buildSkipsNonProgramStatements() async throws {
        let driver = FakeDriver()
        let ws = Workspace(drivers: [.instantClient: driver])
        let def = ConnectionDefinition(name: "dev_x", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        ws.sessions.setMainConnection(def.id)
        let t = try TempDirectory()
        try t.file("inst.sql", "create table t (x number);\n\ncreate or replace procedure p is begin null; end;\n/\n")
        var p = Project(name: "p")
        p.items = [.file("inst.sql")]
        let results = try await ProjectEngine.build(&p, projectURL: t.url.appendingPathComponent("p.prj"), make: false, in: ws)
        #expect(results.first?.status == .compiled)
        #expect(results.first?.messages == ["Pominięto poleceń innych niż jednostki programów: 1 (budowanie kompiluje tylko jednostki PL/SQL)."])
        let executed = try #require(driver.sessions.withLock { $0 }.first).executed.withLock { $0 }
        #expect(executed.contains("ALTER SESSION SET PLSQL_WARNINGS = 'ENABLE:ALL'"))
        #expect(executed.contains { $0.hasPrefix("create or replace procedure p") } && !executed.contains { $0.hasPrefix("create table") })
    }

    @Test("Raporty użytkownika o nazwach dających ten sam identyfikator — obie komendy w menu")
    func userReportIDCollision() throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let dir = try #require(ws.reportsDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["Sprzedaż 2026", "Sprzedaż-2026"] {
            try ReportDefinition(title: name, sql: "select 1 from dual").encoded().write(to: dir.appendingPathComponent(name + ".rep"))
        }
        ws.registerUserReports()
        let reports = ws.registry.commands.filter { $0.id.rawValue.hasPrefix("reports.user.") }
        #expect(Set(reports.map(\.descriptor.title)) == ["Sprzedaż 2026", "Sprzedaż-2026"])
        #expect(Set(reports.map(\.id.rawValue)) == ["reports.user.sprzedaż_2026", "reports.user.sprzedaż_2026_2"])
    }
}
