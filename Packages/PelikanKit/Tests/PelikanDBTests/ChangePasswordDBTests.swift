import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// Atrapa okien: bieżące i nowe hasło podane z góry.
@MainActor
final class ChangePasswordPrompter: ConnectionPrompter {
    let current: String, new: String
    init(current: String, new: String) { self.current = current; self.new = new }
    func askPassword(for connection: ConnectionDefinition, reason: String?) async -> (password: String, remember: Bool)? { (current, false) }
    func askNewPassword(for connection: ConnectionDefinition, message: String) async -> String? { new }
}

@MainActor
@Suite("Zmiana hasła z menu (PD-CONN-017)", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ChangePasswordDBTests {
    @Test("Zmień hasło: OCIPasswordChange w sesji, logowanie nowym hasłem, nowe hasło w Pęku kluczy, gdy definicja zapisuje")
    func change() async throws {
        let c = TestDatabase.config!
        let sys = try await ODPISession.connect(target: ConnectionTarget(user: "SYSTEM", connectString: c.connectString),
                                                credentials: Credentials(password: c.systemPassword), options: ConnectOptions())
        let old = "S" + UUID().uuidString.prefix(12).replacingOccurrences(of: "-", with: "")
        let new = "N" + UUID().uuidString.suffix(12).replacingOccurrences(of: "-", with: "")
        _ = try? await sys.execute("drop user pelikan_pwd cascade")
        _ = try await sys.execute("create user pelikan_pwd identified by \"\(old)\"")
        _ = try await sys.execute("grant create session to pelikan_pwd")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-pwd-\(UUID().uuidString.prefix(6))")
        let secrets = MemorySecretStore()
        let ws = Workspace(dataDirectory: dir, secrets: secrets, drivers: [.instantClient: ODPIDriver()])
        let prompter = ChangePasswordPrompter(current: old, new: new)
        ws.sessions.prompter = prompter
        var def = ConnectionDefinition(name: "dev_pwd", target: ConnectionTarget(user: "pelikan_pwd", connectString: c.connectString))
        def.savePassword = true
        try ws.connections.upsert(def, password: old)
        ws.sessions.setMainConnection(def.id)
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        _ = try await ws.invoke("session.setPassword")
        #expect(ws.connections.password(for: def.id) == new)
        let again = try await ODPISession.connect(target: ConnectionTarget(user: "pelikan_pwd", connectString: c.connectString),
                                                  credentials: Credentials(password: new), options: ConnectOptions())
        #expect(try await again.scalar("select user from dual") == "PELIKAN_PWD")
        await again.close()
        await ws.sessions.disconnectAll()
        _ = try? await sys.execute("drop user pelikan_pwd cascade")
        await sys.close()
        try? FileManager.default.removeItem(at: dir)
    }
}
