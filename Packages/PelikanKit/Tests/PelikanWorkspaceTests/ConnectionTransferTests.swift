import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Interfejs eksportu i importu z hasłami: odpowiedzi na pytania, fraza, plik zapisu.
@MainActor
final class TransferUI: UIServices {
    var answers: [Int?] = []
    var asked: [String] = []
    var phrase: String?
    var saveURL: URL?
    var openURL: URL?
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? {
        asked.append(title)
        return answers.isEmpty ? nil : answers.removeFirst()
    }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { [:] }
    func copyToClipboard(_ text: String, html: String?) {}
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { true }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { openURL.map { [$0] } ?? [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { saveURL }
    func askSecret(_ title: String, message: String, confirm: Bool) async -> String? { phrase }
}

/// Właściciel Maca: zgoda albo odmowa uwierzytelnienia (Touch ID w aplikacji).
@MainActor
final class TransferOwner: ConnectionPrompter {
    var allow: Bool
    var reasons: [String] = []
    init(allow: Bool) { self.allow = allow }
    func askPassword(for connection: ConnectionDefinition, reason: String?) async -> (password: String, remember: Bool)? { nil }
    func askNewPassword(for connection: ConnectionDefinition, message: String) async -> String? { nil }
    func authenticateOwner(reason: String) async -> Bool {
        reasons.append(reason)
        return allow
    }
}

/// Eksport i import połączeń z hasłami (PD-CONN-010, D186).
@MainActor
@Suite("Połączenia: eksport i import z hasłami")
struct ConnectionTransferTests {
    /// Wartości testowe budowane z części (nie wyglądają jak sekret w kodzie).
    static let dbValue = ["wartosc", "bazy", "1"].joined(separator: "-")
    static let sshValue = ["wartosc", "ssh", "1"].joined(separator: "-")

    @Test("PBKDF2-HMAC-SHA256: wektory RFC 7914 (c=1, c=2); implementacja w Swifcie zgodna z CommonCrypto")
    func pbkdf2() {
        let hex: (Data) -> String = { $0.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(ConnectionTransfer.pbkdf2HMAC("password", salt: Data("salt".utf8), iterations: 1))
                == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        #expect(hex(ConnectionTransfer.pbkdf2HMAC("password", salt: Data("salt".utf8), iterations: 2))
                == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        let salt = Data((0..<16).map { UInt8($0) })
        #expect(ConnectionTransfer.pbkdf2("zażółć gęślą", salt: salt, iterations: 1000) == ConnectionTransfer.pbkdf2HMAC("zażółć gęślą", salt: salt, iterations: 1000))
    }

    @Test("Hasła zaszyfrowane: odczyt tą samą frazą, inna fraza i krótka fraza odrzucone, tryb jawny bez frazy")
    func envelope() throws {
        let id = UUID()
        let values = [id: ConnectionSecrets(password: Self.dbValue, sshPassword: Self.sshValue), UUID(): ConnectionSecrets()]
        let sealed = try ConnectionTransfer.envelope(values, mode: .encrypted, passphrase: "fraza testowa", iterations: 1000)
        #expect(sealed.plain == nil && sealed.encrypted?.salt.count == 16)
        let encoded = try JSONEncoder().encode(sealed)
        #expect(String(decoding: encoded, as: UTF8.self).contains(Self.dbValue) == false)
        #expect(try ConnectionTransfer.open(sealed, passphrase: "fraza testowa") == [id.uuidString: values[id]!])
        #expect(throws: ConnectionTransfer.TransferError.wrongPassphrase) { try ConnectionTransfer.open(sealed, passphrase: "inna fraza") }
        #expect(throws: ConnectionTransfer.TransferError.weakPassphrase) {
            try ConnectionTransfer.envelope(values, mode: .encrypted, passphrase: "krótka", iterations: 1000)
        }
        let plain = try ConnectionTransfer.envelope(values, mode: .plain, passphrase: nil)
        #expect(try ConnectionTransfer.open(plain, passphrase: nil) == [id.uuidString: values[id]!])
    }

    private func workspace() throws -> (Workspace, TransferUI, TransferOwner, UUID, URL) {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = TransferUI()
        let owner = TransferOwner(allow: true)
        ws.ui = ui
        ws.sessions.prompter = owner
        var def = ConnectionDefinition(name: "dev_eksport", target: ConnectionTarget(user: "u", connectString: "dev_eksport"))
        def.savePassword = true
        def.sshTunnel = SSHTunnel(host: "bastion.example.invalid", user: "tunel", usesPassword: true)
        try ws.connections.upsert(def, password: Self.dbValue)
        try ws.connections.setSSHPassword(Self.sshValue, for: def.id)
        try ws.connections.upsert(ConnectionDefinition(name: "dev_bez_hasla", target: ConnectionTarget(user: "u", connectString: "x")))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-eksport-\(UUID().uuidString).json")
        ui.saveURL = file
        return (ws, ui, owner, def.id, file)
    }

    @Test("Eksport: bez zgody właściciela nic nie powstaje; zaszyfrowany — plik 0600 bez haseł jawnych; agent nie ma komendy")
    func exportEncrypted() async throws {
        let (ws, ui, owner, _, file) = try workspace()
        defer { try? FileManager.default.removeItem(at: file) }
        owner.allow = false
        ui.phrase = "fraza testowa"
        await #expect(throws: CommandError.self) { try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "encrypted"])) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        owner.allow = true
        _ = try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "encrypted"]))
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains(Self.dbValue) && !text.contains(Self.sshValue) && text.contains("\"encrypted\""))
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(owner.reasons.count == 2)
        #expect(ws.registry.command("connection.exportWithPasswords")?.descriptor.agentAccess == AgentAccess.none)
        await #expect(throws: (any Error).self) {
            try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "plain"]), invoker: .agent(sessionID: "a", agentName: "x"))
        }
    }

    @Test("Eksport jawny po ostrzeżeniu; import do innego Pelikana: hasła w Pęku kluczy, „zapisz hasło”, plik usunięty")
    func plainRoundTrip() async throws {
        let (ws, ui, owner, id, file) = try workspace()
        defer { try? FileManager.default.removeItem(at: file) }
        defer { withExtendedLifetime(owner) {} }   // prompter menedżera sesji jest słaby — właściciel żyje do końca testu
        ui.answers = [1]                      // ostrzeżenie o haśle jawnym — Anuluj
        await #expect(throws: CommandError.self) { try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "plain"])) }
        ui.answers = [0]
        _ = try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "plain"]))
        #expect(try String(contentsOf: file, encoding: .utf8).contains(Self.dbValue))

        // Drugi Pelikan z definicją o tym samym id — import nadaje nowe id i zapisuje hasła pod nim.
        let other = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let otherUI = TransferUI()
        other.ui = otherUI
        try other.connections.upsert(ConnectionDefinition(id: id, name: "dev_istniejace", target: ConnectionTarget(user: "u", connectString: "y")))
        otherUI.openURL = file
        otherUI.answers = [0]                 // zgoda na import definicji z tunelem SSH
        _ = try await other.invoke("connection.import")
        let imported = try #require(other.connections.connections.first { $0.name == "dev_eksport" })
        #expect(imported.id != id && imported.savePassword)
        #expect(other.connections.password(for: imported.id) == Self.dbValue)
        #expect(other.connections.sshPassword(for: imported.id) == Self.sshValue)
        #expect(other.connections.password(for: id) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path), "plik z hasłami usunięty po imporcie")
    }

    @Test("Import zaszyfrowanego: zła fraza — nic nie zaimportowano, plik zostaje; dobra — hasła i usunięcie; plik bez haseł zostaje")
    func encryptedImport() async throws {
        let (ws, ui, owner, _, file) = try workspace()
        defer { try? FileManager.default.removeItem(at: file) }
        defer { withExtendedLifetime(owner) {} }
        ui.phrase = "fraza testowa"
        _ = try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "encrypted"]))
        let other = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let otherUI = TransferUI()
        other.ui = otherUI
        otherUI.openURL = file
        otherUI.phrase = "zła fraza!"
        await #expect(throws: ConnectionTransfer.TransferError.self) { try await other.invoke("connection.import") }
        #expect(other.connections.connections.isEmpty && FileManager.default.fileExists(atPath: file.path))
        otherUI.phrase = "fraza testowa"
        otherUI.answers = [0]
        _ = try await other.invoke("connection.import")
        let imported = try #require(other.connections.connections.first { $0.name == "dev_eksport" })
        #expect(other.connections.password(for: imported.id) == Self.dbValue)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // Zwykły eksport definicji (bez haseł) — import go nie usuwa.
        _ = try await ws.invoke("connection.export", CommandArguments(["file": .string(file.path)]))
        otherUI.answers = [0]
        _ = try await other.invoke("connection.import")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
