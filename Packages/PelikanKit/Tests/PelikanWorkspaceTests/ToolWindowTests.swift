import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Okna narzędzi i Preferencje (trzecia runda przeglądu, D182): połączenie narzędzia, notatnik, wiersze Preferencji,
/// import, test obciążenia, raporty schedulera.
@MainActor
@Suite("Okna narzędzi: połączenie ustalone przy otwarciu, notatnik, Preferencje, eksport")
struct ToolWindowTests {
    private func workspace(_ names: [String]) throws -> (Workspace, [UUID]) {
        let ws = Workspace(drivers: [.instantClient: RunAllGateDriver()])
        var ids: [UUID] = []
        for n in names {
            let def = ConnectionDefinition(name: n, target: ConnectionTarget(user: "u", connectString: n))
            try ws.connections.upsert(def, password: "good")
            ids.append(def.id)
        }
        return (ws, ids)
    }

    @Test("Połączenie narzędzia: przypięte połączenie aktywnego okna, bez okna — główne; argument connection komendy wygrywa")
    func toolConnection() throws {
        let (ws, ids) = try workspace(["dev_a", "dev_b"])
        #expect(ws.toolConnection() == nil)
        ws.sessions.setMainConnection(ids[0])
        #expect(ws.toolConnection() == ids[0])
        let doc = ws.newDocument(.sql)
        doc.connectionID = ids[1]
        #expect(ws.toolConnection() == ids[1])
        doc.isDisconnected = true                        // okno rozłączone — narzędzie bierze główne
        #expect(ws.toolConnection() == ids[0])

        let explicit = CommandContext(workspace: ws, invoker: .user, arguments: CommandArguments(["connection": .string(ids[1].uuidString)]))
        #expect(try explicit.toolConnection() == ids[1])
        let implicit = CommandContext(workspace: ws, invoker: .user, arguments: .empty)
        #expect(try implicit.toolConnection() == ids[0])
        let unknown = CommandContext(workspace: ws, invoker: .user, arguments: CommandArguments(["connection": .string(UUID().uuidString)]))
        #expect(throws: CommandError.self) { try unknown.toolConnection() }
    }

    @Test("Komendy wołane z okien narzędzi przyjmują połączenie okna (parametr connection)")
    func commandsAcceptConnection() throws {
        let (ws, _) = try workspace([])
        for id in ["tools.sqlMonitorReport", "sessions.kill", "dba.alterParameter", "dba.lockUser", "tools.dualityViewDDL", "tools.debugMLE"] {
            let d = try #require(ws.registry.command(CommandID(rawValue: id))?.descriptor, "\(id)")
            #expect(d.parameters.contains { $0.name == "connection" }, "\(id)")
        }
    }

    @Test("Notatnik: Wykonaj wszystkie po identyfikatorach — usunięcie komórki w trakcie przebiegu bez awarii, reszta wykonana")
    func notebookRunAllSurvivesRemoval() async throws {
        let (ws, ids) = try workspace(["dev_nb"])
        ws.sessions.setMainConnection(ids[0])
        let doc = ws.newDocument(.notebook)
        doc.notebook.cells = [NotebookCell(kind: .markdown, text: "# x"), NotebookCell(kind: .sql, text: "select 'hold' from dual"),
                              NotebookCell(kind: .sql, text: "select 2 from dual"), NotebookCell(kind: .sql, text: "select 3 from dual")]
        let removed = doc.notebook.cells[2].id, last = doc.notebook.cells[3].id
        let task = Task { await NotebookRunner.runAll(doc, ws: ws) }
        for _ in 0..<1000 where !RunAllGateSession.waiting.withLock({ $0 }) { await Task.yield() }
        #expect(doc.isExecuting)
        doc.notebook.cells.removeAll { $0.id == removed }            // jak przycisk Usuń w trakcie przebiegu
        RunAllGateSession.open.withLock { $0 = true }
        await task.value
        #expect(!doc.isExecuting)
        #expect(doc.notebook.cells.count == 3)
        #expect(doc.notebook.cells[1].result != nil)
        #expect(doc.notebook.cells.first { $0.id == last }?.result != nil)
    }

    @Test("Wiersze Preferencji: identyfikator reguły nie trafia do pliku ani do porównań, stare ustawienia się wczytują")
    func preferenceRowIdentity() throws {
        let a = ConnectionIndicator(pattern: "sys@*", color: RGBColor(red: 1, green: 0, blue: 0))
        let b = ConnectionIndicator(pattern: "sys@*", color: RGBColor(red: 1, green: 0, blue: 0))
        #expect(a.id != b.id && a == b && a.hashValue == b.hashValue)
        let json = String(decoding: try JSONEncoder().encode(a), as: UTF8.self)
        #expect(!json.contains("\"id\""))
        let old = try JSONDecoder().decode(ConnectionIndicator.self, from: Data(#"{"pattern":"x@*","color":{"red":0,"green":0,"blue":1}}"#.utf8))
        #expect(old.pattern == "x@*")

        var r = AutoReplaceRule(abbreviation: "sf", replacement: "SELECT * FROM ")
        let id = r.id
        r.abbreviation = "sff"                                  // edycja skrótu nie zmienia tożsamości wiersza
        #expect(r.id == id)
        #expect(AutoReplaceRule(abbreviation: "x", replacement: "y") == AutoReplaceRule(abbreviation: "x", replacement: "y"))
        #expect(!String(decoding: try JSONEncoder().encode(r), as: UTF8.self).contains("\"id\""))

        var s = Settings()
        s.autoReplace = [r]
        s.connectionIndicators = [a]
        #expect(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s)) == s)
    }

    @Test("Import z Excela: nagłówek z wybranej linii, puste nazwy POLEn, ostatnia linia")
    func sheetTable() {
        let all = [["tytuł"], ["A", "", "C"], ["1", "2", "3"], ["4", "5", "6"]]
        let t = TextImport.sheetTable(all, headerLine: 2, lastLine: 3)
        #expect(t.header == ["A", "POLE2", "C"] && t.rows == [["1", "2", "3"]])
        let none = TextImport.sheetTable(all, headerLine: 0, lastLine: 0)
        #expect(none.header == ["POLE1", "POLE2", "POLE3"] && none.rows.count == 4)
    }

    @Test("Test obciążenia: wyniki jako arkusz xlsx (czasy liczbowe, min bez wykonań puste)")
    func loadTestExport() throws {
        let (ws, ids) = try workspace(["dev_lt"])
        var test = LoadTest()
        test.steps = [LoadStep(name: "zapytanie", sql: "select 1 from dual")]
        let tester = LoadTester(test, connectionID: ids[0], in: ws)
        let data = tester.exportData()
        #expect(data.columns.count == 6 && data.columns[1].type == .number)
        #expect(data.rows.count == 1)
        if case .text(let name) = data.rows[0][0] { #expect(name == "zapytanie") } else { Issue.record("nazwa kroku") }
        if case .null = data.rows[0][4] {} else { Issue.record("min bez wykonań powinno być puste") }
        let xlsx = ResultExporter.xlsx([data])
        #expect(xlsx.starts(with: [0x50, 0x4B]))                // ZIP (xlsx)
    }

    @Test("Raporty przebiegów schedulera z edytora: bez pustych i powtórzonych nazw, reguły bez kolumny pominięte")
    func schedulerReports() {
        let red = RGBColor(red: 1, green: 0, blue: 0)
        let r = Scheduler.RunReport.normalized([
            .init(name: " Moje ", condition: " status = 'FAILED' \n", colors: [.init(column: " STATUS ", value: " FAILED ", color: red), .init(column: " ", value: "x", color: red)]),
            .init(name: "Moje", condition: "", colors: []),
            .init(name: "  ", condition: "1 = 1", colors: []),
        ])
        #expect(r.map(\.name) == ["Moje"])
        #expect(r[0].condition == "status = 'FAILED'")
        #expect(r[0].colors == [.init(column: "STATUS", value: "FAILED", color: red)])
    }
}

/// Sesja testowa „Wykonaj wszystkie”: polecenie z „hold” czeka na otwarcie bramki (osobna od `GateSession`, żeby
/// testy nie dzieliły stanu).
final class RunAllGateSession: DatabaseSession, @unchecked Sendable {
    static let waiting = Mutex(false)
    static let open = Mutex(false)
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        if sql.contains("hold") {
            Self.waiting.withLock { $0 = true }
            while !Self.open.withLock({ $0 }) { await Task.yield() }
        }
        return ExecutionResult(kind: .other)
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

final class RunAllGateDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession { RunAllGateSession() }
}
