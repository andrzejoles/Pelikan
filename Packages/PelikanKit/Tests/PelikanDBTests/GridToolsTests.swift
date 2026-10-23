import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Narzędzia siatki na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct GridToolsTests {
    @Test("Zapytania powiązane z FK, porównanie rekordów i wyników, kolumna do plików, zapytanie standardowe")
    func gridTools() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql, text: "select empno, ename, deptno from emp order by empno;\nselect empno, ename, deptno from emp where deptno = 10 order by empno;")
        doc.connectionID = def.id
        _ = try await SQLExecutor.execute(doc, scope: .allStatements, in: ws)
        #expect(doc.results.count == 2)
        let tab = doc.results[0]
        doc.activeResultID = tab.id
        tab.selectedRows = [0, 1]
        let grid = try #require(tab.grid)
        #expect(GridTools.sourceTable(of: grid, defaultOwner: c.user.uppercased())?.table == "EMP")

        // Zapytania powiązane: DEPT nadrzędna dla EMP.
        try await ws.invoke("grid.linkedQueries")
        guard case .linkedQueries(let links, let values, _)? = ui.gridRequests.last else { Issue.record("brak okna zapytań powiązanych"); return }
        let parent = try #require(links.first { $0.direction == .parent && $0.table == "DEPT" })
        #expect(parent.sql(values: values).contains("t.DEPTNO = "))
        let before = ws.documents.count
        try await ws.invoke("grid.linkedQueries", CommandArguments(["constraint": .string(parent.constraint)]))
        #expect(ws.documents.count == before + 1 && ws.documents.last?.results.first?.grid?.rowCount == 1)

        // Porównanie rekordów i wyników.
        ws.activate(doc.id)
        try await ws.invoke("grid.compareRecords")
        guard case .compareRecords(let cmp)? = ui.gridRequests.last else { Issue.record("brak porównania rekordów"); return }
        #expect(cmp.first { $0.column == "EMPNO" }?.identical == false && cmp.count == 3)
        let diff = GridTools.compareResults(doc.results[0].grid!, doc.results[1].grid!)
        #expect(!diff.identical && diff.rowsOnlyLeft > 0 && diff.columnsOnlyLeft.isEmpty)
        #expect(GridTools.compareResults(doc.results[1].grid!, doc.results[1].grid!).identical)

        // Kolumna do plików.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-c2f-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try GridTools.columnToFiles(grid, column: 1, viewRows: [0, 1], directory: dir, template: "[EMPNO]_[#].txt")
        #expect(r.files == 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names.count == 2 && names[0].hasSuffix("_1.txt"))

        // Zapytanie standardowe: z siatki i dla obiektu.
        try await ws.invoke("grid.saveAsStandardQuery", CommandArguments(["name": "Pracownicy"]))
        let q = try #require(ws.settings.standardQueries.first { $0.name == "Pracownicy" })
        #expect(q.sql.contains("[owner].[table]"))
        try await ws.invoke("ob.standardQuery", CommandArguments(["object": "dept", "name": .string(StandardQuery.standard[0].name)]))
        #expect(ws.activeDocument?.text.contains("t.DNAME") == true && ws.activeDocument?.results.first?.grid != nil)
        await ws.sessions.disconnectAll()
    }

    @Test("Edytor zewnętrzny Large Data Editor: plik tymczasowy 0600 z rozszerzeniem RTF, wykrycie zapisu, sprzątanie")
    func externalEditor() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql, text: "select to_clob('{\\rtf1 tekst}') tresc from dual")
        doc.connectionID = def.id
        _ = try await SQLExecutor.execute(doc, scope: .allStatements, in: ws)
        let grid = try #require(doc.results.first?.grid)
        let model = LargeDataModel(grid: grid, row: 0, column: 0)
        #expect(model.format == .rtf)
        let edit = ExternalLargeDataEdit(model: model)
        let url = try edit.start()
        #expect(url.pathExtension == "rtf")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(!edit.checkForChanges())
        try Data("{\\rtf1 zmienione}".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        #expect(edit.checkForChanges() && model.text == "{\\rtf1 zmienione}" && model.modified)
        edit.finish()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        await ws.sessions.disconnectAll()
    }
}
