import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Interfejs eksportu i importu z hasłami: odpowiedzi na pytania, fraza, plik zapisu.
@MainActor
final class TransferUI: UIServices {
    var answers: [Int?] = []
    var asked: [String] = []
    var phrase: String?
    /// Kolejne frazy (przed `phrase`) i komunikaty okien frazy.
    var phrases: [String?] = []
    var secretMessages: [String] = []
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
    func askSecret(_ title: String, message: String, confirm: Bool) async -> String? {
        secretMessages.append(message)
        return phrases.isEmpty ? phrase : phrases.removeFirst()
    }
}

/// Pęk kluczy, którego zapis zawodzi przy `failAt`-tym haśle (odmowa dostępu, zablokowany pęk).
final class FailingSecretStore: SecretStore {
    let inner = MemorySecretStore()
    let failAt = Mutex(Int.max)
    private let writes = Mutex(0)
    func password(for account: String) throws -> String? { try inner.password(for: account) }
    func setPassword(_ password: String, for account: String) throws {
        let n = writes.withLock { $0 += 1; return $0 }
        if n == failAt.withLock({ $0 }) { throw SecretStoreError.keychain(-25293) }
        try inner.setPassword(password, for: account)
    }
    func deletePassword(for account: String) throws { try inner.deletePassword(for: account) }
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
    func pbkdf2() throws {
        let hex: (Data) -> String = { $0.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(ConnectionTransfer.pbkdf2HMAC("password", salt: Data("salt".utf8), iterations: 1))
                == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        #expect(hex(ConnectionTransfer.pbkdf2HMAC("password", salt: Data("salt".utf8), iterations: 2))
                == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        let salt = Data((0..<16).map { UInt8($0) })
        #expect(try ConnectionTransfer.pbkdf2("zażółć gęślą", salt: salt, iterations: 1000) == ConnectionTransfer.pbkdf2HMAC("zażółć gęślą", salt: salt, iterations: 1000))
    }

    @Test("Pusta fraza, pusta sól i iteracje ponad limit — błąd zamiast zatrzymania aplikacji")
    func malformedEnvelope() throws {
        typealias E = ConnectionTransfer.TransferError
        let sealed = try ConnectionTransfer.envelope([UUID(): ConnectionSecrets(password: Self.dbValue)], mode: .encrypted,
                                                     passphrase: "fraza testowa", iterations: 1000)
        #expect(throws: E.wrongPassphrase) { try ConnectionTransfer.open(sealed, passphrase: "") }
        #expect(throws: E.wrongPassphrase) { try ConnectionTransfer.open(sealed, passphrase: nil) }
        var noSalt = sealed
        noSalt.encrypted?.salt = Data()
        #expect(throws: E.unsupported("salt")) { try ConnectionTransfer.open(noSalt, passphrase: "fraza testowa") }
        var slow = sealed
        slow.encrypted?.iterations = ConnectionTransfer.maximumIterations + 1
        #expect(throws: E.self) { try ConnectionTransfer.open(slow, passphrase: "fraza testowa") }
        // CommonCrypto z pustą frazą i solą: wynik albo błąd — bez precondition.
        _ = try? ConnectionTransfer.pbkdf2("", salt: Data(), iterations: 1)
    }

    @Test("Definicje uwierzytelnione szyfrowaniem: zmieniony host odrzuca hasła; układ JSON bez znaczenia; plik bez ochrony czytany")
    func definitionsAuthenticated() throws {
        typealias E = ConnectionTransfer.TransferError
        let store = ConnectionStore(fileURL: nil, secrets: MemorySecretStore())
        let def = ConnectionDefinition(name: "dev_aad", target: ConnectionTarget(user: "u", connectString: "db.example.invalid:1521/s"))
        try store.upsert(def)
        let values = [def.id: ConnectionSecrets(password: Self.dbValue)]
        let definitions = try store.exportDefinitions()
        let sealed = try ConnectionTransfer.envelope(values, mode: .encrypted, passphrase: "fraza testowa", iterations: 1000, definitions: definitions)
        let file = try ConnectionStore.addingSecrets(sealed, to: definitions)
        let read = try #require(try ConnectionTransfer.envelope(in: file))
        #expect(read.encrypted?.authenticatesDefinitions == true)
        #expect(try ConnectionTransfer.open(read, passphrase: "fraza testowa", definitions: file) == [def.id.uuidString: values[def.id]!])
        let compact = try JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: file))
        #expect(try ConnectionTransfer.definitionsDigest(compact) == ConnectionTransfer.definitionsDigest(file))
        let changed = Data(String(decoding: file, as: UTF8.self).replacingOccurrences(of: "db.example.invalid", with: "obcy.example.invalid").utf8)
        #expect(throws: E.wrongPassphrase) { try ConnectionTransfer.open(read, passphrase: "fraza testowa", definitions: changed) }
        var stripped = read
        stripped.encrypted?.authenticatesDefinitions = nil
        #expect(throws: E.wrongPassphrase) { try ConnectionTransfer.open(stripped, passphrase: "fraza testowa", definitions: changed) }
        #expect(throws: E.unsupported("definitions")) { try ConnectionTransfer.open(read, passphrase: "fraza testowa") }
        // Plik sprzed ochrony definicji (bez danych dodatkowych).
        let old = try ConnectionTransfer.envelope(values, mode: .encrypted, passphrase: "fraza testowa", iterations: 1000)
        #expect(old.encrypted?.authenticatesDefinitions == nil)
        #expect(try ConnectionTransfer.open(old, passphrase: "fraza testowa", definitions: changed) == [def.id.uuidString: values[def.id]!])
    }

    @Test("Plik prywatny: prawa 0600 od utworzenia, także w miejsce istniejącego pliku 0644")
    func privateFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-prywatny-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FileManager.default.createFile(atPath: file.path, contents: Data("stare".utf8), attributes: [.posixPermissions: 0o644]))
        #expect(try PrivateFile.write(Data("nowe".utf8), to: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == "nowe")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).filter { $0.hasPrefix(".\(file.lastPathComponent)") }
        #expect(leftovers.isEmpty)
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
        // Za krótka i pusta fraza — ponowne pytanie od razu, bez ponownego uwierzytelnienia.
        ui.phrases = ["krótka", ""]
        _ = try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "encrypted"]))
        #expect(ui.secretMessages.count == 4 && owner.reasons.count == 3)
        #expect(ui.secretMessages[3] == ConnectionTransfer.TransferError.weakPassphrase.errorDescription)
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
        otherUI.phrase = ""                   // OK przy pustym polu frazy
        await #expect(throws: ConnectionTransfer.TransferError.wrongPassphrase) { try await other.invoke("connection.import") }
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

    @Test("Import: błąd Pęku kluczy przy drugim haśle wycofuje definicje i zapisane hasła; ponowny import bez duplikatów")
    func failedKeychainRollsBack() async throws {
        let (ws, ui, owner, id, file) = try workspace()
        defer { try? FileManager.default.removeItem(at: file) }
        defer { withExtendedLifetime(owner) {} }
        ui.answers = [0]
        _ = try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "plain"]))
        let keychain = FailingSecretStore()
        keychain.failAt.withLock { $0 = 2 }   // hasło bazy zapisane, hasło SSH — błąd
        let other = Workspace(secrets: keychain, drivers: [:])
        let otherUI = TransferUI()
        other.ui = otherUI
        otherUI.openURL = file
        otherUI.answers = [0]
        await #expect(throws: SecretStoreError.self) { try await other.invoke("connection.import") }
        #expect(other.connections.connections.isEmpty && other.connections.folders.isEmpty)
        #expect(try keychain.inner.password(for: id.uuidString) == nil, "zapisane hasło wycofane")
        #expect(FileManager.default.fileExists(atPath: file.path))
        keychain.failAt.withLock { $0 = .max }
        otherUI.answers = [0]
        _ = try await other.invoke("connection.import")
        #expect(other.connections.connections.filter { $0.name == "dev_eksport" }.count == 1)
        #expect(other.connections.password(for: id) == Self.dbValue)
    }

    @Test("Eksport: hasło podane przy logowaniu bez zapamiętania i nowsze niż hasło z edytora połączenia")
    func exportsSessionPassword() async throws {
        let driver = FakeDriver()
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: driver])
        let ui = TransferUI()
        ws.ui = ui
        let prompter = FakePrompter(answers: [("good", false)])
        prompter.ownerAnswers = [true]
        ws.sessions.prompter = prompter
        let def = ConnectionDefinition(name: "dev_sesja", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "stare")   // bez „zapisz hasło” — tylko pamięć magazynu
        _ = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))   // ORA-01017, nowe hasło w oknie
        #expect(ws.connections.password(for: def.id) == "stare")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-sesja-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        ui.answers = [0]
        _ = try await ws.invoke("connection.exportWithPasswords", CommandArguments(["mode": "plain", "file": .string(file.path)]))
        let envelope = try #require(try ConnectionTransfer.envelope(in: try Data(contentsOf: file)))
        #expect(envelope.plain?[def.id.uuidString]?.password == "good")
    }
}
