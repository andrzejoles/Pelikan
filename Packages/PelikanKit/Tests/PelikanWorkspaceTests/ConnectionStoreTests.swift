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
