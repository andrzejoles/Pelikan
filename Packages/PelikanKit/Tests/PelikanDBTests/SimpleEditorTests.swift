import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

@MainActor
@Suite("Proste edytory obiektów na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct SimpleEditorTests {
    func workspace(user: String, password: String) throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: user, connectString: c.connectString))
        try ws.connections.upsert(def, password: password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    @Test("Sekwencja, synonim, indeks: utworzenie, wczytanie, zmiana, brak zmian po wczytaniu")
    func schemaObjects() async throws {
        let c = TestDatabase.config!
        let (ws, id) = try workspace(user: c.user, password: c.password)
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        for o in ["sequence pelikan_se_seq", "sequence pelikan_se_seq2", "synonym pelikan_se_syn", "table pelikan_se_t purge"] { _ = try? await s.execute("drop \(o)") }
        _ = try await s.execute("create table pelikan_se_t (a number, b varchar2(10))")

        var seq = SimpleObjectEditor(kind: .sequence, owner: schema, values: ["name": "PELIKAN_SE_SEQ", "start": "100", "increment": "5", "cache": "0", "cycle": "N"])
        #expect(seq.statements() == ["CREATE SEQUENCE \(schema).PELIKAN_SE_SEQ START WITH 100 INCREMENT BY 5 NOCACHE"])
        #expect(try await seq.apply(in: ws, connectionID: id).error == nil)
        seq = try await SimpleObjectEditor.load(.sequence, owner: schema, name: "PELIKAN_SE_SEQ", metadata: m)
        #expect(seq.value("increment") == "5" && seq.value("cache") == "0")
        #expect(seq.statements().isEmpty)
        seq.values["increment"] = "10"
        seq.values["cycle"] = "Y"
        seq.values["name"] = "PELIKAN_SE_SEQ2"
        #expect(seq.statements() == ["RENAME PELIKAN_SE_SEQ TO PELIKAN_SE_SEQ2", "ALTER SEQUENCE \(schema).PELIKAN_SE_SEQ2 INCREMENT BY 10 CYCLE"])
        let r = try await seq.apply(in: ws, connectionID: id)
        #expect(r.error == nil, "\(r.error ?? "")")
        #expect(try await SimpleObjectEditor.load(.sequence, owner: schema, name: "PELIKAN_SE_SEQ2", metadata: m).value("cycle") == "Y")

        var syn = SimpleObjectEditor(kind: .synonym, owner: schema, values: ["name": "PELIKAN_SE_SYN", "target": "PELIKAN_SE_T"])
        #expect(try await syn.apply(in: ws, connectionID: id).error == nil)
        syn = try await SimpleObjectEditor.load(.synonym, owner: schema, name: "PELIKAN_SE_SYN", metadata: m)
        #expect(syn.value("target") == "PELIKAN_SE_T" && syn.statements().isEmpty)

        var ix = SimpleObjectEditor(kind: .index, owner: schema, values: ["name": "PELIKAN_SE_IX", "table": "PELIKAN_SE_T", "columns": "A, B", "type": "UNIQUE"])
        #expect(try await ix.apply(in: ws, connectionID: id).error == nil)
        ix = try await SimpleObjectEditor.load(.index, owner: schema, name: "PELIKAN_SE_IX", metadata: m)
        #expect(ix.value("type") == "UNIQUE" && ix.value("columns") == "A, B")
        ix.values["invisible"] = "Y"
        #expect(ix.statements() == ["ALTER INDEX \(schema).PELIKAN_SE_IX INVISIBLE"])
        #expect(try await ix.apply(in: ws, connectionID: id).error == nil)

        for o in ["sequence pelikan_se_seq2", "synonym pelikan_se_syn", "table pelikan_se_t purge"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }

    @Test("Użytkownik i rola (konto SYSTEM kontenera testowego): hasło maskowane w podglądzie, role, uprawnienia, limity")
    func userAndRole() async throws {
        let c = TestDatabase.config!
        let (ws, id) = try workspace(user: "SYSTEM", password: c.systemPassword)
        let m = try #require(ws.metadata())
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        for o in ["user pelikan_se_user cascade", "role pelikan_se_role"] { _ = try? await s.execute("drop \(o)") }
        var role = SimpleObjectEditor(kind: .role, owner: "SYSTEM", values: ["name": "PELIKAN_SE_ROLE", "privileges": "CREATE SESSION"])
        #expect(try await role.apply(in: ws, connectionID: id).error == nil)
        role = try await SimpleObjectEditor.load(.role, owner: "SYSTEM", name: "PELIKAN_SE_ROLE", metadata: m)
        #expect(role.value("privileges") == "CREATE SESSION")

        let secret = "Pk" + UUID().uuidString.prefix(12).replacingOccurrences(of: "-", with: "") + "9"
        var user = SimpleObjectEditor(kind: .user, owner: "SYSTEM", values: ["name": "PELIKAN_SE_USER", "password": secret,
                                                                            "defaultTablespace": "USERS", "roles": "PELIKAN_SE_ROLE",
                                                                            "privileges": "CREATE TABLE", "quotas": "USERS:UNLIMITED"])
        #expect(user.statements(masked: true).allSatisfy { !$0.contains(secret) })
        #expect(user.statements(masked: true).first?.contains("IDENTIFIED BY ********") == true)
        let r = try await user.apply(in: ws, connectionID: id)
        #expect(r.error == nil, "\(r.failed ?? ""): \(r.error ?? "")")
        #expect(r.executed.allSatisfy { !$0.contains(secret) })
        user = try await SimpleObjectEditor.load(.user, owner: "SYSTEM", name: "PELIKAN_SE_USER", metadata: m)
        #expect(user.value("roles") == "PELIKAN_SE_ROLE" && user.value("privileges") == "CREATE TABLE" && user.value("quotas") == "USERS:UNLIMITED")
        #expect(user.value("password").isEmpty && user.statements().isEmpty)
        user.values["roles"] = ""
        user.values["locked"] = "Y"
        #expect(user.statements() == ["ALTER USER PELIKAN_SE_USER ACCOUNT LOCK", "REVOKE PELIKAN_SE_ROLE FROM PELIKAN_SE_USER"])
        #expect(try await user.apply(in: ws, connectionID: id).error == nil)
        for o in ["user pelikan_se_user cascade", "role pelikan_se_role"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}
