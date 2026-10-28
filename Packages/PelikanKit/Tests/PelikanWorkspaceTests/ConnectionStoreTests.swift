import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Lista połączeń")
struct ConnectionStoreTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-conn-\(UUID().uuidString)/connections.json")
    }

    @Test("Zapis bez haseł; hasło w SecretStore; odczyt po ponownym otwarciu")
    func persistence() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let secrets = MemorySecretStore()
        let store = ConnectionStore(fileURL: url, secrets: secrets)
        let def = ConnectionDefinition(name: "Dev", target: ConnectionTarget(user: "scott", connectString: "db:1521/dev"))
        try store.upsert(def, password: "Tajne-Haslo-123")
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(!json.contains("Tajne-Haslo-123"))
        #expect(json.contains("db:1521/dev"))
        let reopened = ConnectionStore(fileURL: url, secrets: secrets)
        #expect(reopened.connections.map(\.name) == ["Dev"])
        #expect(reopened.password(for: def.id) == "Tajne-Haslo-123")
    }

    @Test("Bez zapisu hasła: hasło tylko w pamięci sesji, nie w SecretStore")
    func sessionPassword() throws {
        let secrets = MemorySecretStore()
        let store = ConnectionStore(fileURL: nil, secrets: secrets)
        let def = ConnectionDefinition(target: ConnectionTarget(user: "a", connectString: "x"), savePassword: false)
        try store.upsert(def, password: "p")
        #expect(store.password(for: def.id) == "p")
        #expect(try secrets.password(for: def.id.uuidString) == nil)
    }

    @Test("Foldery i połączenia alfabetycznie: bez wielkości liter, liczby naturalnie, także w folderze z regułą")
    func alphabetical() throws {
        let store = ConnectionStore(fileURL: nil, secrets: MemorySecretStore())
        for name in ["zeta", "Alfa", "beta"] { try store.upsert(folder: ConnectionFolder(name: name)) }
        #expect(store.subfolders(of: nil).map(\.name) == ["Alfa", "beta", "zeta"])
        let rule = ConnectionFolder(name: "Prod", databasePattern: "prod*")
        try store.upsert(folder: rule)
        for (name, db) in [("Baza 10", "dev"), ("baza 2", "dev"), ("Archiwum", "dev"), ("prod-b", "PROD1"), ("Prod-A", "PROD2")] {
            try store.upsert(ConnectionDefinition(name: name, target: ConnectionTarget(user: "u", connectString: db)))
        }
        try store.upsert(ConnectionDefinition(name: "prod-c", folderID: rule.id, target: ConnectionTarget(user: "u", connectString: "x")))
        #expect(store.connections(in: nil).map(\.name) == ["Archiwum", "baza 2", "Baza 10"])
        #expect(store.connections(in: rule.id).map(\.name) == ["Prod-A", "prod-b", "prod-c"])   // jawne i z reguły razem
    }

    @Test("Przeniesienie połączenia do folderu i na poziom główny; nieznany folder — błąd")
    func moveToFolder() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConnectionStore(fileURL: url, secrets: MemorySecretStore())
        let f = ConnectionFolder(name: "Test")
        try store.upsert(folder: f)
        let def = ConnectionDefinition(name: "Dev", target: ConnectionTarget(user: "scott", connectString: "db"))
        try store.upsert(def)
        try store.move(def.id, to: f.id)
        #expect(store.connections(in: f.id).map(\.id) == [def.id])
        #expect(ConnectionStore(fileURL: url, secrets: MemorySecretStore()).connection(def.id)?.folderID == f.id)   // zapisane
        try store.move(def.id, to: nil)
        #expect(store.connections(in: nil).map(\.id) == [def.id])
        #expect(throws: CommandError.self) { try store.move(def.id, to: UUID()) }
        #expect(store.connection(def.id)?.folderID == nil)
    }

    @Test("Kopia połączenia: nowa nazwa i id, ten sam folder, hasła bazy i SSH skopiowane, bez historii użycia")
    func duplicate() throws {
        let secrets = MemorySecretStore()
        let store = ConnectionStore(fileURL: nil, secrets: secrets)
        let f = ConnectionFolder(name: "Test")
        try store.upsert(folder: f)
        var def = ConnectionDefinition(name: "Dev", folderID: f.id, target: ConnectionTarget(user: "scott", connectString: "db"))
        def.lastUsed = Date()
        def.connectOnStartup = true
        try store.upsert(def, password: "Tajne-1")
        try store.setSSHPassword("ssh-2", for: def.id)
        let copy = try store.duplicate(def.id, name: "Dev 2")
        #expect(copy.id != def.id && copy.name == "Dev 2" && copy.folderID == f.id && copy.lastUsed == nil)
        #expect(!copy.connectOnStartup)   // bez drugiego połączenia z tą samą bazą przy starcie
        #expect(throws: CommandError.self) { try store.duplicate(def.id, name: "dev 2") }   // nazwa zajęta (bez wielkości liter)
        #expect(copy.target == def.target)
        #expect(store.password(for: copy.id) == "Tajne-1")
        #expect(store.sshPassword(for: copy.id) == "ssh-2")
        #expect(store.connections(in: f.id).map(\.name) == ["Dev", "Dev 2"])
        // Hasło tylko z tej sesji (bez zapisu) — kopia też tylko w pamięci.
        let session = ConnectionDefinition(name: "S", target: ConnectionTarget(user: "a", connectString: "x"), savePassword: false)
        try store.upsert(session, password: "p")
        let sessionCopy = try store.duplicate(session.id, name: "S2")
        #expect(store.password(for: sessionCopy.id) == "p")
        #expect(try secrets.password(for: sessionCopy.id.uuidString) == nil)
        // Połączenie tymczasowe (CONNECT w oknie poleceń) — czytelny błąd zamiast „nieznane połączenie” i cichego OK.
        let temp = ConnectionDefinition(name: "", target: ConnectionTarget(user: "u", connectString: "x"))
        store.registerTemporary(temp, password: "t")
        for attempt in [{ _ = try store.duplicate(temp.id, name: "T") }, { try store.move(temp.id, to: f.id) }] {
            do { try attempt(); Issue.record("bez błędu") } catch let CommandError.notAvailable(m) { #expect(m.contains("tymczasow")) } catch { Issue.record("\(error)") }
        }
    }

    @Test("Obiekty schematów Oracle: zmiana tylko po osobnym potwierdzeniu; bez interfejsu — odmowa; inne schematy bez pytania")
    func oracleMaintainedConfirmation() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        try await ws.confirmOracleMaintained(["SCOTT", nil])
        await #expect(throws: CommandError.self) { try await ws.confirmOracleMaintained(["SYS"]) }
        let ui = FakeUI()
        ws.ui = ui
        ui.answers = [0]   // Anuluj (domyślny)
        await #expect(throws: CommandError.self) { try await ws.confirmOracleMaintained(["sys", "SCOTT"]) }
        ui.answers = [1]   // Zmień mimo to
        try await ws.confirmOracleMaintained(["XDB"])
        #expect(ui.asked.count == 2)
        // Katalog ma zawsze właściciela SYS — bez pytania; pakiet SYS — z pytaniem.
        try await ws.confirmOracleMaintained(objects: [DBObject(owner: "SYS", name: "DATA_DIR", type: .directory)])
        #expect(ui.asked.count == 2)
        ui.answers = [0]
        await #expect(throws: CommandError.self) {
            try await ws.confirmOracleMaintained(objects: [DBObject(owner: "SYS", name: "DBMS_OUTPUT", type: .package)])
        }
        #expect(ui.asked.count == 3)
    }

    @Test("Komendy connection.duplicate i connection.moveToFolder (nazwa folderu bez wielkości liter)")
    func duplicateAndMoveCommands() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let f = ConnectionFolder(name: "Testowe")
        try ws.connections.upsert(folder: f)
        let def = ConnectionDefinition(name: "Dev", target: ConnectionTarget(user: "scott", connectString: "db"))
        try ws.connections.upsert(def)
        let r = try await ws.invoke("connection.duplicate", CommandArguments(["connection": .string(def.id.uuidString),
                                                                                        "name": .string("  Dev kopia  ")]))
        guard case .string(let s)? = r.value, let copyID = UUID(uuidString: s) else { Issue.record("brak id kopii"); return }
        #expect(ws.connections.connection(copyID)?.name == "Dev kopia")
        await #expect(throws: CommandError.self) {
            try await ws.invoke("connection.duplicate", CommandArguments(["connection": .string(def.id.uuidString), "name": .string(" ")]))
        }
        _ = try await ws.invoke("connection.moveToFolder", CommandArguments(["connection": .string("dev kopia"), "folder": .string("TESTOWE")]))
        #expect(ws.connections.connection(copyID)?.folderID == f.id)
        _ = try await ws.invoke("connection.moveToFolder", CommandArguments(["connection": .string(copyID.uuidString)]))
        #expect(ws.connections.connection(copyID)?.folderID == nil)
        await #expect(throws: CommandError.self) {
            try await ws.invoke("connection.moveToFolder", CommandArguments(["connection": .string(copyID.uuidString), "folder": .string("brak")]))
        }
    }

    @Test("Folder z regułą dopasowania (sys*, *@prod*) i połączenia jawne")
    func folderRules() throws {
        let store = ConnectionStore(fileURL: nil, secrets: MemorySecretStore())
        let sys = ConnectionFolder(name: "SYS", userPattern: "sys*")
        let prod = ConnectionFolder(name: "Prod", databasePattern: "prod*")
        try store.upsert(folder: sys)
        try store.upsert(folder: prod)
        let a = ConnectionDefinition(name: "a", target: ConnectionTarget(user: "SYSTEM", connectString: "dev"))
        let b = ConnectionDefinition(name: "b", target: ConnectionTarget(user: "scott", connectString: "PROD_DB"))
        let c = ConnectionDefinition(name: "c", folderID: sys.id, target: ConnectionTarget(user: "app", connectString: "x"))
        for d in [a, b, c] { try store.upsert(d) }
        #expect(Set(store.connections(in: sys.id).map(\.name)) == ["a", "c"])
        #expect(store.connections(in: prod.id).map(\.name) == ["b"])
        #expect(store.connections(in: nil).isEmpty)   // a i b są w folderach z regułą
    }

    @Test("Wzorce * ? i user@database")
    func wildcards() {
        #expect(Wildcard.matches("SYSTEM", pattern: "sys*"))
        #expect(Wildcard.matches("db1", pattern: "db?"))
        #expect(!Wildcard.matches("db12", pattern: "db?"))
        #expect(Wildcard.matches(user: "sys", database: "PRODDB", pattern: "*@prod*"))
        #expect(Wildcard.matches(user: "sys", database: "anything", pattern: "sys@*"))
        #expect(!Wildcard.matches(user: "scott", database: "dev", pattern: "sys@*"))
    }

    @Test("Opis połączenia jak we wzorcu, alias dla agenta bez danych logowania")
    func descriptions() {
        let def = ConnectionDefinition(target: ConnectionTarget(user: "SYS", connectString: "chicago", role: .sysdba, edition: "R2"))
        #expect(def.connectionString == "sys@chicago as sysdba {R2}")
        #expect(def.displayName == "sys@chicago as sysdba {R2}")
        #expect(!def.agentAlias.contains("chicago"))
        #expect(!def.agentAlias.contains("sys"))
        let prod = ConnectionDefinition(target: ConnectionTarget(user: "x", connectString: "y"), environment: .production)
        #expect(prod.agent.allowChanges == false)
        #expect(prod.effectiveColor == .production)
    }

    @Test("Usunięcie folderu przenosi połączenia do rodzica; eksport/import bez haseł")
    func folderRemovalAndExport() throws {
        let secrets = MemorySecretStore()
        let store = ConnectionStore(fileURL: nil, secrets: secrets)
        let parent = ConnectionFolder(name: "P")
        let child = ConnectionFolder(name: "C", parentID: parent.id)
        try store.upsert(folder: parent)
        try store.upsert(folder: child)
        let d = ConnectionDefinition(name: "d", folderID: child.id, target: ConnectionTarget(user: "u", connectString: "c"))
        try store.upsert(d, password: "sekret")
        try store.remove(folder: child.id)
        #expect(store.connection(d.id)?.folderID == parent.id)
        let data = try store.exportDefinitions()
        #expect(!String(decoding: data, as: UTF8.self).contains("sekret"))
        let other = ConnectionStore(fileURL: nil, secrets: MemorySecretStore())
        #expect(try other.importDefinitions(data) == 1)
        #expect(other.password(for: other.connections[0].id) == nil)
    }

    @Test("Import z kolizją id folderów nie przenosi istniejących podfolderów pod folder z importu")
    func importKeepsExistingTree() throws {
        let store = ConnectionStore(fileURL: nil, secrets: MemorySecretStore())
        let parent = ConnectionFolder(name: "P")
        let child = ConnectionFolder(name: "C", parentID: parent.id)
        try store.upsert(folder: parent)
        try store.upsert(folder: child)
        _ = try store.importDefinitions(try store.exportDefinitions())
        #expect(store.folders.count == 4)
        #expect(store.folders.first { $0.id == child.id }?.parentID == parent.id)
        let imported = store.folders.filter { $0.id != parent.id && $0.id != child.id }
        let newParent = try #require(imported.first { $0.name == "P" })
        #expect(imported.first { $0.name == "C" }?.parentID == newParent.id)
    }
}
