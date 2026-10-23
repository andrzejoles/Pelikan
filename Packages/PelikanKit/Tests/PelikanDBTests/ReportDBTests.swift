import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Raporty na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ReportDBTests {
    func workspace(dataDirectory: URL? = nil) throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(dataDirectory: dataDirectory, drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "Testowa", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    @Test("Raport standardowy Błędy kompilacji: okno raportu z HTML i grupami obiektów; eksport danych")
    func compilationErrors() async throws {
        let (ws, _) = try workspace()
        try await ws.invoke("reports.compilationErrors")
        let doc = try #require(ws.activeDocument)
        #expect(doc.kind == .report && doc.reportError == nil)
        let html = try #require(doc.reportHTML)
        #expect(html.contains("<h1>Błędy kompilacji</h1>") && html.contains("PACKAGE BODY BROKEN_PKG") && html.contains("class=\"break\""))
        let export = try #require(ReportRunner.exportData(doc))
        #expect(export.columns.map(\.name) == ["OBIEKT", "LINIA", "KOLUMNA", "RODZAJ", "TEKST"] && !export.rows.isEmpty)
        #expect(ResultExporter.text(.csv, export).contains("BROKEN_PKG"))
        await ws.sessions.disconnectAll()
    }

    @Test("Własny raport ze zmienną (&<…>, :bind), formatem liczb i sumą; F8 w oknie raportu; zapis .rep i menu Raporty")
    func customReport() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-rep-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (ws, _) = try workspace(dataDirectory: dir)
        var def = ReportDefinition(title: "Pensje działu", sql: """
            select ename, sal from emp where deptno = &<name="Dział" type="integer" default="10"> and sal >= :minimum order by sal desc
            """)
        var sal = ReportColumnFormat(column: "SAL"); sal.numberFormat = "0.00"; sal.sum = true
        def.columns = [sal]
        def.header = "#title (#Dział)"
        let doc = ws.openReport(def)
        let html = try await ReportRunner.run(doc, in: ws, values: ["Dział": .text("10"), "minimum": .text("1000")])
        #expect(html.contains("Pensje działu (10)") && html.contains("KOWALSKI") && !html.contains("NOWAK"))
        #expect(html.contains("5000.00") || html.contains("5000,00"))
        #expect(html.contains("class=\"sum\""))
        // F8 w oknie raportu wykonuje raport (zmienne zapamiętane w oknie — bez pytania tylko przez values; tu tylko walidacja).
        #expect(ws.isEnabled("sql.execute"))
        try await ws.invoke("report.addToMenu")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Reports/Pensje działu.rep").path))
        let menu = ws.registry.commands.first { $0.id.rawValue.hasPrefix("reports.user.") }
        #expect(menu?.descriptor.title == "Pensje działu")
        let reopened = try ws.openFile(dir.appendingPathComponent("Reports/Pensje działu.rep"))
        #expect(reopened.kind == .report && reopened.report.columns.first?.sum == true && reopened.text.contains("&<name=\"Dział\""))
        doc.report.connection = "Nieznane połączenie"
        #expect(ReportRunner.connection(for: doc, in: ws) == ws.sessions.mainConnectionID)
        await ws.sessions.disconnectAll()
    }
}
