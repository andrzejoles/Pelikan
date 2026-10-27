import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// Object Browser z wieloma połączeniami (PD-OB-001, D185): czynności na obiekcie z gałęzi drugiego połączenia działają
/// na tym połączeniu — okna są do niego przypięte, kompilacja idzie jego sesją; rozłączenie usuwa gałąź.
@MainActor
@Suite("Object Browser: obiekty drugiego połączenia", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct ObjectBrowserConnectionsDBTests {
    func workspace() throws -> (Workspace, TestUI, main: UUID, second: UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let main = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        let second = ConnectionDefinition(name: "dev_test_druga", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(main, password: c.password)
        try ws.connections.upsert(second, password: c.password)
        ws.sessions.setMainConnection(main.id)
        return (ws, ui, main.id, second.id)
    }

    @Test("Pokaż dane i Edytuj z gałęzi drugiego połączenia: okno przypięte do niego, połączenie główne bez zmian")
    func windowsOnBranchConnection() async throws {
        let (ws, ui, main, second) = try workspace()
        defer { withExtendedLifetime(ui) {} }   // interfejs obszaru roboczego jest słaby
        _ = try await ws.invoke("connection.connect", CommandArguments(["connection": .string("dev_test_druga")]))
        #expect(ws.sessions.openConnections == [main, second])
        ws.selectedObjectConnection = second
        ws.selectedObject = DBObject(owner: TestDatabase.config!.user.uppercased(), name: "DEPT", type: .table)
        _ = try await ws.invoke("ob.queryData")
        let data = try #require(ws.activeDocument)
        #expect(data.connectionID == second && data.connectionPinned)
        #expect(ws.effectiveConnection(of: data) == second)
        #expect(data.results.first?.grid != nil)

        ws.selectedObject = DBObject(owner: TestDatabase.config!.user.uppercased(), name: "EMP_API", type: .package)
        _ = try await ws.invoke("ob.edit")
        let program = try #require(ws.activeDocument)
        #expect(program.kind == .program && program.connectionID == second)
        #expect(ws.sessions.mainConnectionID == main)

        // Obiekt z gałęzi połączenia głównego — okno jak dotąd za połączeniem głównym.
        ws.selectedObjectConnection = main
        _ = try await ws.invoke("ob.ddl")
        #expect(ws.activeDocument?.connectionID == nil)
        await ws.sessions.disconnectAll()
    }

    @Test("Otwarcie obiektu z narzędzia (wyszukiwanie, testy, debuger) na połączeniu, z którego pochodzi, nie aktywnego okna")
    func openObjectFromTool() async throws {
        let (ws, ui, main, second) = try workspace()
        defer { withExtendedLifetime(ui) {} }   // interfejs obszaru roboczego jest słaby
        let api = DBObject(owner: TestDatabase.config!.user.uppercased(), name: "EMP_API", type: .package)
        // Aktywne okno przypięte do drugiego połączenia, obiekt znaleziony na głównym.
        let other = ws.newDocument(.sql)
        ws.bind(other, to: second)
        try await ws.openObject(api, connection: main)
        let fromMain = try #require(ws.activeDocument)
        #expect(fromMain.kind == .program && fromMain.id != other.id)
        #expect(!fromMain.connectionPinned && ws.effectiveConnection(of: fromMain) == main)
        // Aktywne okno na głównym, obiekt z drugiego — okno przypięte do drugiego.
        try await ws.openObject(api, connection: second)
        let fromSecond = try #require(ws.activeDocument)
        #expect(fromSecond.connectionPinned && fromSecond.connectionID == second)
        // Bez połączenia — jak dotąd połączenie aktywnego okna.
        ws.activate(other.id)
        try await ws.openObject(api)
        #expect(ws.activeDocument?.connectionID == second)
        await ws.sessions.disconnectAll()
    }

    @Test("Rekompilacja w sesji kompilacji połączenia gałęzi; upuszczenie obiektu przekazuje połączenie; rozłączenie usuwa gałąź")
    func compileAndDisconnect() async throws {
        let (ws, ui, main, second) = try workspace()
        defer { withExtendedLifetime(ui) {} }   // interfejs obszaru roboczego jest słaby
        _ = try await ws.sessions.session(SessionKey(connectionID: second, purpose: .main))
        ws.selectedObjectConnection = second
        ws.selectedObject = DBObject(owner: TestDatabase.config!.user.uppercased(), name: "EMP_API", type: .package)
        _ = try await ws.invoke("ob.recompile")
        #expect(ws.sessions.existingSession(ws.sessions.compileKey(connection: second)) != nil)
        #expect(ws.sessions.existingSession(ws.sessions.compileKey(connection: main)) == nil)

        ws.selectedObjectConnection = nil
        ws.settings.browserWorkspaceDrop = .queryData
        _ = try await ws.invoke("ob.dropOnWorkspace", CommandArguments(["object": "DEPT", "type": "TABLE", "connection": .string(second.uuidString)]))
        #expect(ws.activeDocument.map { ws.effectiveConnection(of: $0) } == second)

        _ = try await ws.invoke("connection.disconnect", CommandArguments(["connection": .string(second.uuidString)]))
        #expect(!ws.sessions.openConnections.contains(second))
        #expect(ws.sessions.openConnections.contains(main))
        await ws.sessions.disconnectAll()
    }

    @Test("Kod z obiektu drugiego połączenia: przeciągnięcie SELECT i nowe okno na jego połączeniu; RECOMPILE okna poleceń na połączeniu okna")
    func codeAndRecompileOnBranchConnection() async throws {
        let (ws, ui, main, second) = try workspace()
        defer { withExtendedLifetime(ui) {} }   // interfejs obszaru roboczego jest słaby
        let mainKey = SessionKey(connectionID: main, purpose: .main)
        // Upuszczenie z akcją SELECT: kolumny z połączenia gałęzi, sesja połączenia głównego nieotwierana (ZMIANY-08).
        let r = try await ws.invoke("ob.dropText", CommandArguments(["object": "DEPT", "type": "TABLE", "action": "select",
                                                                     "connection": .string(second.uuidString)]))
        #expect(r.value?.stringValue?.lowercased().contains("deptno") == true, "\(String(describing: r.value))")
        #expect(ws.sessions.existingSession(mainKey) == nil)
        // Generuj kod w nowym oknie — okno przypięte do połączenia obiektu (ZMIANY-09).
        _ = try await ws.invoke("ob.generateCode", CommandArguments(["object": "DEPT", "type": "TABLE", "kind": "select", "newWindow": .bool(true),
                                                                     "connection": .string(second.uuidString)]))
        let generated = try #require(ws.activeDocument)
        #expect(generated.connectionID == second && generated.connectionPinned)
        #expect(ws.sessions.existingSession(mainKey) == nil)

        // RECOMPILE w oknie poleceń drugiego połączenia, gdy aktywne jest okno połączenia głównego (WS2-14).
        let command = ws.newDocument(.command)
        command.connectionID = second
        let engine = ws.sqlplusEngine(for: command)
        _ = ws.newDocument(.sql)
        let outcome = await engine.run("recompile emp_api")
        #expect(outcome == .finished, "\(command.console.map(\.text))")
        #expect(ws.sessions.existingSession(ws.sessions.compileKey(connection: second)) != nil)
        #expect(ws.sessions.existingSession(ws.sessions.compileKey(connection: main)) == nil)
        await ws.sessions.disconnectAll()
    }
}
