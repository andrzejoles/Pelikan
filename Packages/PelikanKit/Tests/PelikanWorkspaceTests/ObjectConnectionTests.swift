import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Połączenia w drzewie Object Browsera (PD-OB-001, D185): lista otwartych połączeń i połączenie komend obiektów
/// z kontekstu (argument, gałąź drzewa, okno), połączenie główne tylko jako zapas.
@MainActor
@Suite("Object Browser: otwarte połączenia i połączenie obiektu")
struct ObjectConnectionTests {
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

    @Test("Otwarte połączenia: kolejność połączenia, główne bez sesji, bez sesji agenta; zamknięcie sesji nie usuwa, rozłączenie usuwa")
    func openConnections() async throws {
        let (ws, ids) = try workspace(["dev_a", "dev_b", "dev_c"])
        let s = ws.sessions
        #expect(s.openConnections.isEmpty)
        _ = try await s.session(SessionKey(connectionID: ids[1], purpose: .main))
        s.setMainConnection(ids[0])
        #expect(s.openConnections == [ids[1], ids[0]])
        _ = try await s.session(SessionKey(connectionID: ids[2], purpose: .agent("claude")))
        #expect(!s.openConnections.contains(ids[2]), "sesja agenta nie otwiera połączenia w drzewie")
        await s.close(SessionKey(connectionID: ids[1], purpose: .main))
        #expect(s.openConnections.contains(ids[1]), "zamknięta sesja (np. bezczynna) — połączenie zostaje")
        await s.disconnect(ids[1])
        #expect(s.openConnections == [ids[0]])
        await s.disconnectAll()
        #expect(s.openConnections.isEmpty)
    }

    @Test("Połączenie obiektu: argument, nazwa obiektu — okno, zaznaczenie — gałąź drzewa, bez kontekstu — główne")
    func objectConnection() throws {
        let (ws, ids) = try workspace(["dev_main", "dev_other", "dev_window"])
        ws.sessions.setMainConnection(ids[0])
        func ctx(_ args: [String: JSONValue] = [:]) -> CommandContext {
            CommandContext(workspace: ws, invoker: .user, arguments: CommandArguments(args))
        }
        #expect(try ctx().objectConnection() == ids[0])
        ws.selectedObject = DBObject(owner: "APP", name: "T", type: .table)
        ws.selectedObjectConnection = ids[1]
        #expect(try ctx().objectConnection() == ids[1], "zaznaczenie w gałęzi drugiego połączenia")
        #expect(ws.objectBrowserConnection == ids[1])
        let doc = ws.newDocument(.sql)
        doc.connectionID = ids[2]
        #expect(try ctx(["object": .string("APP.X")]).objectConnection() == ids[2], "obiekt po nazwie z okna — połączenie okna")
        #expect(try ctx(["objects": .string("APP.X:TABLE")]).objectConnection() == ids[2])
        #expect(try ctx(["connection": .string(ids[1].uuidString), "object": .string("APP.X")]).objectConnection() == ids[1])
        // Komenda z własnym `connection` (druga baza porównania) bierze obiekt z kontekstu.
        #expect(try ctx(["connection": .string("dev_main")]).objectConnection(connectionArgument: false) == ids[1])
        #expect(throws: CommandError.self) { try ctx(["connection": .string("dev_main")]).objectConnection() }
        ws.selectedObjectConnection = nil
        #expect(try ctx().objectConnection() == ids[0], "bez gałęzi — połączenie główne")
    }

    @Test("Okno obiektu innego połączenia jest do niego przypięte; okno połączenia głównego idzie za głównym")
    func bindDocument() throws {
        let (ws, ids) = try workspace(["dev_main", "dev_other"])
        ws.sessions.setMainConnection(ids[0])
        let main = ws.newDocument(.sql)
        ws.bind(main, to: ids[0])
        #expect(main.connectionID == nil && !main.connectionPinned)
        let other = ws.newDocument(.program)
        ws.bind(other, to: ids[1])
        #expect(other.connectionID == ids[1] && other.connectionPinned)
        ws.sessions.setMainConnection(ids[1])
        #expect(ws.effectiveConnection(of: other) == ids[1] && ws.effectiveConnection(of: main) == ids[1])
    }

    @Test("Komendy obiektów przyjmują połączenie; porównanie z inną bazą zachowuje własny argument connection")
    func parameters() throws {
        let (ws, _) = try workspace([])
        for id in ["ob.queryData", "ob.edit", "ob.ddl", "ob.recompile", "ob.drop", "ob.rename", "ob.test", "ob.recompileSelected",
                   "ob.dropSelected", "ob.recycleBin", "ob.refresh", "ob.editTable", "ob.dropText"] {
            let d = try #require(ws.registry.command(CommandID(rawValue: id))?.descriptor, "\(id)")
            #expect(d.parameters.filter { $0.name == "connection" }.count == 1, "\(id)")
        }
        let compare = try #require(ws.registry.command("ob.compareWithConnection")?.descriptor)
        #expect(compare.parameters.filter { $0.name == "connection" }.count == 1)
    }

    @Test("utPLSQL z eksploratora i okna wyników: argument connection ma pierwszeństwo przed aktywnym oknem")
    func utplsqlConnection() throws {
        let (ws, ids) = try workspace(["dev_main", "dev_other"])
        ws.sessions.setMainConnection(ids[0])
        func ctx(_ args: [String: JSONValue] = [:]) -> CommandContext {
            CommandContext(workspace: ws, invoker: .user, arguments: CommandArguments(args))
        }
        #expect(try UtplsqlCommands.connection(ctx()) == ids[0])
        let doc = ws.newDocument(.sql)
        ws.bind(doc, to: ids[1])
        #expect(try UtplsqlCommands.connection(ctx()) == ids[1], "bez argumentu — połączenie aktywnego okna")
        #expect(try UtplsqlCommands.connection(ctx(["connection": .string(ids[0].uuidString)])) == ids[0])
        #expect(throws: CommandError.self) { try UtplsqlCommands.connection(ctx(["connection": .string("dev_main")])) }
        for id in ["utplsql.runAll", "utplsql.runPath", "utplsql.runWithOptions", "utplsql.coverage", "utplsql.export"] {
            let d = try #require(ws.registry.command(CommandID(rawValue: id))?.descriptor, "\(id)")
            #expect(d.parameters.filter { $0.name == "connection" }.count == 1, "\(id)")
        }
    }
}
