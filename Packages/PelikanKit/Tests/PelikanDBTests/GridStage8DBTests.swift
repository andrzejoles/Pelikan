import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu dla siatki Etapu 8: zmienne, pytania, schowek, zapis, powiadomienia, wybór wartości.
@MainActor
final class Stage8UI: UIServices {
    var variables: [String: VariableValue] = [:]
    var variableAsks = 0
    var clipboard: String?
    var saveURL: URL?
    var notifications: [(String, Bool)] = []
    var choice: String?
    var largeData: LargeDataModel?
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { 0 }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { variableAsks += 1; return variables }
    func copyToClipboard(_ text: String, html: String?) { clipboard = text }
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { true }
    func showLargeDataEditor(_ model: LargeDataModel) { largeData = model }
    func chooseFilesToOpen() async -> [URL] { [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { saveURL }
    func notifyExecutionFinished(title: String, elapsed: String, success: Bool) { notifications.append((elapsed, success)) }
    func chooseValue(_ title: String, values: [String]) async -> String? { choice }
}

@MainActor
@Suite("Siatka i SQL Window — Etap 8 na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(5)))
struct GridStage8DBTests {
    func open(_ sql: String) async throws -> (Workspace, Document, Stage8UI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = Stage8UI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql, text: sql)
        try await ws.invoke("sql.execute")
        return (ws, doc, ui)
    }

    func activeGrid(_ doc: Document) throws -> (ResultTab, ResultGridModel) {
        let tab = try #require(doc.results.first { $0.id == doc.activeResultID })
        return (tab, try #require(tab.grid))
    }

    @Test("Kursor zagnieżdżony <Cursor> otwiera nową kartę z wynikiem")
    func nestedCursor() async throws {
        let (ws, doc, _) = try await open("select d.dname, cursor(select ename from emp e where e.deptno = d.deptno order by ename) emps from dept d where d.deptno = 10")
        let (tab, grid) = try activeGrid(doc)
        #expect(grid.text(row: 0, column: 1) == "<Cursor>")
        tab.selectedRows = [0]
        tab.currentColumn = 1
        try await ws.invoke("grid.openCursor")
        let (child, cg) = try activeGrid(doc)
        let s = try await TestDatabase.connect()
        let count = Int(try await s.scalar("select count(*) from emp where deptno = 10") ?? "0") ?? 0
        let first = try await s.scalar("select min(ename) from emp where deptno = 10") ?? ""
        await s.close()
        #expect(child.id != tab.id && cg.lastError == nil && cg.columns.map(\.name) == ["ENAME"])
        #expect(cg.rowCount == count && cg.text(row: 0, column: 0) == first)
        tab.currentColumn = 0
        doc.activeResultID = tab.id
        await #expect(throws: (any Error).self) { try await ws.invoke("grid.openCursor") }
        await ws.sessions.disconnectAll()
    }

    @Test("Słownik w siatce: typ, NOT NULL, PK, komentarz; lista z CHECK IN i z FK; filtr kolumn po kluczach; wybór wartości")
    func dictionary() async throws {
        let s = try await TestDatabase.connect()
        _ = try? await s.execute("drop table pelikan_g8_chk purge")
        _ = try await s.execute("create table pelikan_g8_chk (id number(5) primary key, status varchar2(1) not null check (status in ('A', 'B')), deptno number(2) references dept)")
        _ = try await s.execute("comment on column pelikan_g8_chk.status is 'Stan rekordu'")
        _ = try await s.execute("insert into pelikan_g8_chk values (1, 'A', 10)")
        try await s.commit()
        let (ws, doc, ui) = try await open("select c.id, c.status, c.deptno, c.rowid from pelikan_g8_chk c")
        let (tab, grid) = try activeGrid(doc)
        let r = try await ws.invoke("grid.columnInfo", CommandArguments(["column": "status"]))
        guard case .object(let o)? = r.value else { Issue.record("brak informacji"); return }
        #expect(o["info"] == .string("STATUS: VARCHAR2(1) NOT NULL — Stan rekordu") && o["values"] == .array([.string("A"), .string("B")]))
        #expect(tab.columnInfo?[0]?.statusLine == "NUMBER(5) NOT NULL · PK" && tab.columnInfo?[2]?.values == ["10", "20", "30", "40"])
        try await ws.invoke("grid.columnFilter", CommandArguments(["keys": "primary,foreign"]))
        #expect(tab.hiddenColumns == [1, 3])
        try await ws.invoke("grid.columnFilter", CommandArguments(["mandatory": .bool(true)]))
        // ROWID w opisie wyniku jest NOT NULL — zostaje widoczny.
        #expect(tab.hiddenColumns == [2])
        try await ws.invoke("grid.edit")
        tab.selectedRows = [0]
        tab.currentColumn = 1
        ui.choice = "B"
        try await ws.invoke("grid.valueList")
        #expect(grid.text(row: 0, column: 1) == "B")
        grid.cancelChanges()
        await ws.sessions.disconnectAll()
        _ = try await s.execute("drop table pelikan_g8_chk purge")
        await s.close()
    }

    @Test("Dyrektywy Totals=, AltRowColor=, CSV= i Excel=; sumy pamiętane po ponownym wykonaniu")
    func directives() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-g8-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sql = """
        -- Totals=sum+max:sal; count:ename
        -- AltRowColor=#EEF4FF
        -- CSV=\(dir.path)/emp_%dbuser%.csv
        -- Excel=\(dir.path)/emp.xlsx
        select ename, sal from emp order by empno
        """
        let s = try await TestDatabase.connect()
        let count = Int(try await s.scalar("select count(*) from emp") ?? "0") ?? 0
        let total = try await s.scalar("select sum(sal) from emp") ?? ""
        await s.close()
        let (ws, doc, _) = try await open(sql)
        let (tab, grid) = try activeGrid(doc)
        #expect(tab.totals[1] == [.sum, .max] && tab.totals[0] == [.count] && tab.altRowColor == "#EEF4FF")
        #expect(ColumnTotals.summary(grid, totals: [1: [.sum]]) == "SAL: Suma \(total)")
        let csv = try String(contentsOf: dir.appendingPathComponent("emp_\(TestDatabase.config!.user).csv"), encoding: .utf8)
        #expect(csv.components(separatedBy: .newlines).filter { !$0.isEmpty }.count == count + 1 && csv.hasPrefix("ENAME,SAL"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("emp.xlsx").path))
        // Suma z komendy zostaje dla kolumny po ponownym wykonaniu bez dyrektywy.
        doc.text = "select empno, sal from emp"
        try await ws.invoke("sql.execute")
        let (tab2, _) = try activeGrid(doc)
        try await ws.invoke("grid.totals", CommandArguments(["column": "empno", "functions": "count"]))
        try await ws.invoke("sql.execute")
        let (tab3, _) = try activeGrid(doc)
        #expect(tab3.id != tab2.id && tab3.totals[0] == [.count])
        await ws.sessions.disconnectAll()
    }

    @Test("Odświeżenie karty z zapamiętanymi zmiennymi, Query By Example, automatyczne odświeżanie")
    func refreshQBEAutoRefresh() async throws {
        let s = try await TestDatabase.connect()
        _ = try? await s.execute("drop table pelikan_g8_ar purge")
        _ = try await s.execute("create table pelikan_g8_ar (n number, txt varchar2(20))")
        _ = try await s.execute("insert into pelikan_g8_ar values (1, 'jeden')")
        try await s.commit()
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = Stage8UI()
        ui.variables = ["min": .text("0")]
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql, text: "select n, txt from pelikan_g8_ar where n > :min order by n")
        try await ws.invoke("sql.execute")
        #expect(ui.variableAsks == 1)
        var (tab, grid) = try activeGrid(doc)
        #expect(grid.rowCount == 1)
        _ = try await s.execute("insert into pelikan_g8_ar values (2, 'dwa')")
        try await s.commit()
        try await ws.invoke("sql.refreshResult")
        (tab, grid) = try activeGrid(doc)
        #expect(grid.rowCount == 2 && ui.variableAsks == 1)
        let q = try await ws.invoke("grid.queryByExample", CommandArguments(["criteria": .object(["TXT": .string("DW%")])]))
        #expect(tab.grid?.rowCount == 1 && tab.grid?.text(row: 0, column: 1) == "dwa")
        #expect(q.value?.stringValue?.contains("UPPER(x.TXT) LIKE UPPER('DW%')") == true)
        await #expect(throws: (any Error).self) { try await ws.invoke("grid.queryByExample", CommandArguments(["criteria": .object(["N": .string("abc")])])) }
        try await ws.invoke("grid.clearQueryByExample")
        #expect(tab.grid?.rowCount == 2)
        try await ws.invoke("sql.autoRefresh", CommandArguments(["seconds": .int(1)]))
        _ = try await s.execute("insert into pelikan_g8_ar values (3, 'trzy')")
        try await s.commit()
        var waited = 0
        while (tab.grid?.rowCount ?? 0) < 3, waited < 60 { try await Task.sleep(for: .milliseconds(100)); waited += 1 }
        #expect(tab.grid?.rowCount == 3 && ui.variableAsks == 1)
        try await ws.invoke("sql.autoRefresh", CommandArguments(["seconds": .int(0)]))
        #expect(doc.autoRefreshTask == nil && doc.autoRefreshSeconds == nil)
        await ws.sessions.disconnectAll()
        _ = try await s.execute("drop table pelikan_g8_ar purge")
        await s.close()
    }

    @Test("Eksport bezpośredni do CSV, xlsx i schowka bez siatki")
    func directExport() async throws {
        let (ws, doc, ui) = try await open("select 1 from dual")
        doc.text = "select empno, ename from emp order by empno"
        doc.results = []
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-g8-\(UUID().uuidString.prefix(6)).csv")
        defer { try? FileManager.default.removeItem(at: file) }
        let s = try await TestDatabase.connect()
        let count = Int64(try await s.scalar("select count(*) from emp") ?? "0") ?? 0
        let first = try await s.scalar("select empno || ',' || ename from emp order by empno fetch first 1 row only") ?? ""
        await s.close()
        let r = try await ws.invoke("sql.exportQuery", CommandArguments(["format": "csv", "file": .string(file.path)]))
        #expect(r.value == .int(count) && doc.results.isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines).filter { !$0.isEmpty }.prefix(2) == ["EMPNO,ENAME", first])
        try await ws.invoke("sql.exportQuery", CommandArguments(["format": "tsv", "file": "clipboard"]))
        #expect(ui.clipboard?.hasPrefix("EMPNO\tENAME") == true)
        let x = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-g8-\(UUID().uuidString.prefix(6)).xlsx")
        defer { try? FileManager.default.removeItem(at: x) }
        ui.saveURL = x
        try await ws.invoke("sql.exportQuery", CommandArguments(["format": "xlsx"]))
        #expect((try Data(contentsOf: x)).starts(with: [0x50, 0x4B]))
        await ws.sessions.disconnectAll()
    }

    @Test("LOB na żądanie: w siatce początek wartości, całość w Large Data Editor; wielkość liter w edytowalnej siatce; kolumna wirtualna po Post")
    func lobCaseVirtual() async throws {
        let s = try await TestDatabase.connect()
        _ = try? await s.execute("drop table pelikan_g8_lob purge")
        _ = try await s.execute("create table pelikan_g8_lob (id number primary key, name varchar2(20), n number, v number generated always as (n * 2) virtual, body clob)")
        _ = try await s.execute("declare c clob := rpad('x', 10000, 'x'); begin insert into pelikan_g8_lob (id, name, n, body) values (1, 'Mixed', 5, c); end;")
        try await s.commit()
        let (ws, doc, ui) = try await open("select t.rowid, t.id, t.name, t.n, t.v, t.body from pelikan_g8_lob t")
        #expect(ws.settings.fetchLOBsOnDemand)
        let (tab, grid) = try activeGrid(doc)
        guard case .lob(let l) = grid.value(row: 0, column: 5) else { Issue.record("brak LOB"); return }
        #expect(l.truncated && (l.text?.count ?? 0) == SQLExecutor.lobPreviewBytes && l.length == 10000)
        tab.selectedRows = [0]
        tab.currentColumn = 5
        try await ws.invoke("grid.largeData")
        #expect(ui.largeData?.text?.count == 10000)
        try await ws.invoke("grid.edit")
        tab.currentColumn = 2
        try await ws.invoke("grid.upperCase")
        #expect(grid.text(row: 0, column: 2) == "MIXED")
        try await ws.invoke("grid.lowerCase")
        #expect(grid.text(row: 0, column: 2) == "mixed")
        try grid.setText("21", row: 0, column: 3)
        try await ws.invoke("grid.post")
        #expect(grid.text(row: 0, column: 4) == "42")
        try await ws.invoke("session.rollback")
        await ws.sessions.disconnectAll()
        _ = try await s.execute("drop table pelikan_g8_lob purge")
        await s.close()
    }

    @Test("Powiadomienie po długim wykonaniu")
    func notification() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = Stage8UI()
        ws.ui = ui
        ws.settings.notifyLongQuerySeconds = 1
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql, text: "begin dbms_session.sleep(1.2); end;")
        try await ws.invoke("sql.execute")
        #expect(ui.notifications.count == 1 && ui.notifications[0].1)
        doc.text = "select 1 from dual"
        try await ws.invoke("sql.execute")
        #expect(ui.notifications.count == 1)
        await ws.sessions.disconnectAll()
    }
}
