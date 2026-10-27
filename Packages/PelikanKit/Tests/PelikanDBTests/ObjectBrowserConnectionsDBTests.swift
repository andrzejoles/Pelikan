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
    func workspace() throws -> (Workspace, main: UUID, second: UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let main = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        let second = ConnectionDefinition(name: "dev_test_druga", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(main, password: c.password)
        try ws.connections.upsert(second, password: c.password)
        ws.sessions.setMainConnection(main.id)
        return (ws, main.id, second.id)
    }

    @Test("Pokaż dane i Edytuj z gałęzi drugiego połączenia: okno przypięte do niego, połączenie główne bez zmian")
    func windowsOnBranchConnection() async throws {
        let (ws, main, second) = try workspace()
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

    @Test("Rekompilacja w sesji kompilacji połączenia gałęzi; upuszczenie obiektu przekazuje połączenie; rozłączenie usuwa gałąź")
    func compileAndDisconnect() async throws {
        let (ws, main, second) = try workspace()
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
}
