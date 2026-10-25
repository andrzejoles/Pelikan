import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@Suite("Filtry nazwane i foldery Object Browsera bez bazy")
struct BrowserCustomizationOfflineTests {
    @Test("Zapis i odczyt browser.json, filtr domyślny per użytkownik, &browser_filter z apostrofem, widoczność folderu")
    func model() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ob-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        var c = BrowserCustomization()
        c.filters = [BrowserFilter(name: "Wszystkie", whereClause: "1 = 1", isDefault: true),
                     BrowserFilter(name: "Moje HR", whereClause: "o.owner = :browser_user", forUser: "HR", isDefault: true)]
        c.folders = [BrowserFolder(name: "Ważne", connectionPattern: "*@prod*")]
        try c.save(to: dir)
        let l = BrowserCustomization.load(from: dir)
        #expect(l == c)
        #expect(l.defaultFilter(user: "hr")?.name == "Moje HR" && l.defaultFilter(user: "scott")?.name == "Wszystkie")
        #expect(l.filters(for: "SCOTT").count == 1)
        #expect(BrowserFilter(name: "x", whereClause: "o.object_name like '&browser_filter%'").expandedWhere(filterText: "O'K") == "o.object_name like 'O''K%'")
        let prod = ConnectionDefinition(name: "p", target: ConnectionTarget(user: "app", connectString: "db@prod1"))
        let dev = ConnectionDefinition(name: "d", target: ConnectionTarget(user: "app", connectString: "dev"))
        #expect(c.folders[0].visible(for: prod) && !c.folders[0].visible(for: dev))
    }

    @MainActor @Test("Foldery typów i akcja dwukliku z preferencji")
    func preferences() {
        let ws = Workspace()
        let all: [DBObjectType] = [.table, .view, .package, .procedure]
        #expect(ws.browserFolderTypes(available: all) == all)
        ws.settings.browserFolders = ["PACKAGE", "TABLE", "NIEZNANY"]
        #expect(ws.browserFolderTypes(available: all) == [.package, .table])
        #expect(ws.browserDoubleClickCommand(for: .table) == "ob.queryData" && ws.browserDoubleClickCommand(for: .package) == "ob.edit")
        ws.settings.browserDoubleClick = ["TABLE": "ob.describe", "VIEW": "rm -rf"]
        #expect(ws.browserDoubleClickCommand(for: .table) == "ob.describe" && ws.browserDoubleClickCommand(for: .view) == "ob.queryData")
    }
}

@MainActor
@Suite("Filtry nazwane i foldery Object Browsera na bazie", .enabled(if: TestDatabase.isAvailable), .serialized)
struct BrowserCustomizationDBTests {
    @Test("Filtr nazwany (WHERE, ORDER BY, :browser_user, &browser_filter), folder z listą i zapytaniem, Dodaj do folderu, limit Recent")
    func onDatabase() async throws {
        let c = TestDatabase.config!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("obdb-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir, drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let m = try #require(ws.metadata())
        let owner = try await m.currentSchema()
        var cust = BrowserCustomization()
        cust.filters = [BrowserFilter(name: "E-tabele", whereClause: "o.owner = :browser_user and o.object_name like '&browser_filter%'", orderBy: "o.object_name desc")]
        try ws.saveBrowserCustomization(cust)
        _ = try await ws.invoke("ob.applyFilter", CommandArguments(["name": "e-tabele"]))
        let tables = try await m.objects(.table, owner: owner, filter: ObjectFilter("E", named: ws.browserFilter))
        #expect(!tables.isEmpty && tables.allSatisfy { $0.name.hasPrefix("E") } && tables.map(\.name) == tables.map(\.name).sorted(by: >))
        // Bez nazwy komenda pyta o filtr; ostatni przycisk to „Bez filtra”.
        ui.askAnswer = 1
        _ = try await ws.invoke("ob.applyFilter")
        ui.askAnswer = 0
        #expect(ws.browserFilter == nil && ui.asked.contains("Filtr nazwany"))
        ws.selectedObject = DBObject(owner: owner, name: "EMP", type: .table)
        _ = try await ws.invoke("ob.addToFolder", CommandArguments(["folder": "Kadry"]))
        var folder = try #require(ws.browserCustomization.folders.first { $0.name == "Kadry" })
        folder.query = "select owner, object_name, object_type from all_objects where owner = user and object_name = 'DEPT' and object_type = 'TABLE'"
        cust = ws.browserCustomization
        cust.folders = [folder]
        try ws.saveBrowserCustomization(cust)
        #expect(Set(try await m.objects(in: folder).map(\.name)) == ["EMP", "DEPT"])
        #expect(BrowserCustomization.load(from: dir).folders.first?.objects.count == 1)
        ws.settings.browserRecentLimit = 2
        for n in ["A", "B", "C"] { m.touch(DBObject(owner: owner, name: n, type: .table)) }
        #expect(m.recent.map(\.name) == ["C", "B"])
        await ws.sessions.disconnectAll()
    }
}
