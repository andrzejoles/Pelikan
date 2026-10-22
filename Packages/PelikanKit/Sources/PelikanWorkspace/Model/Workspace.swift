import Foundation
import Observation
import PelikanDB

/// Usługi interfejsu, których potrzebują komendy (implementuje aplikacja; w testach — atrapy).
@MainActor
public protocol UIServices: AnyObject {
    func showError(_ message: String)
    func showCommandPalette()
    /// Pytanie z wyborem (np. zapis zmian przy zamykaniu). Zwraca indeks wybranego przycisku albo nil (anuluj).
    func ask(_ title: String, message: String, buttons: [String]) async -> Int?
}

/// Rejestr wszystkich komend (kolejność = kolejność w menu i palecie).
public struct CommandRegistry: Sendable {
    public private(set) var commands: [Command] = []
    private var index: [CommandID: Int] = [:]

    public init(_ commands: [Command] = []) {
        for c in commands { register(c) }
    }

    public mutating func register(_ command: Command) {
        if let i = index[command.id] {
            commands[i] = command
        } else {
            index[command.id] = commands.count
            commands.append(command)
        }
    }

    public func command(_ id: CommandID) -> Command? { index[id].map { commands[$0] } }
    public var descriptors: [CommandDescriptor] { commands.map(\.descriptor) }
}

/// Wpis o wywołaniu komendy (dziennik, panel aktywności agenta, raport testów).
public struct CommandInvocationRecord: Sendable {
    public enum Outcome: Sendable { case success(String?), failure(String) }
    public var command: CommandID
    public var arguments: CommandArguments
    public var invoker: Invoker
    public var started: Date
    public var outcome: Outcome
}

/// Model stanu aplikacji — jedno źródło prawdy dla interfejsu i API agenta (docs/ARCHITECTURE.md §3).
@MainActor
@Observable
public final class Workspace {
    public private(set) var documents: [Document] = []
    public var activeDocumentID: DocumentID?
    public private(set) var registry: CommandRegistry
    public private(set) var keymap: Keymap
    public var shortcutProfile: ShortcutProfile {
        didSet { rebuildKeymap() }
    }
    public var keyOverrides: [String: String] = [:] {
        didSet { rebuildKeymap() }
    }
    public var statusMessage: String?
    public var settings: Settings {
        didSet {
            if settings.shortcutProfile != oldValue.shortcutProfile { shortcutProfile = settings.shortcutProfile }
            if settings.keyOverrides != oldValue.keyOverrides { keyOverrides = settings.keyOverrides }
            saveSettings()
        }
    }
    public let connections: ConnectionStore
    public let sessions: SessionManager
    /// Katalog danych aplikacji (nil = bez zapisu: testy, `persists: false`).
    public let dataDirectory: URL?

    @ObservationIgnored public weak var ui: (any UIServices)?
    @ObservationIgnored private var invocationObservers: [@MainActor (CommandInvocationRecord) -> Void] = []
    @ObservationIgnored private var ordinals: [DocumentKind: Int] = [:]

    /// - Parameters:
    ///   - dataDirectory: katalog danych (`~/Library/Application Support/Pelikan`); nil = nic nie jest zapisywane.
    ///   - secrets: przechowywanie haseł (aplikacja: Pęk kluczy; testy: pamięć).
    ///   - drivers: sterowniki bazy wstrzykiwane przez aplikację.
    public init(profile: ShortcutProfile? = nil, commands: [Command]? = nil, dataDirectory: URL? = nil,
                secrets: any SecretStore = MemorySecretStore(), drivers: [DriverKind: any DatabaseDriver] = [:]) {
        self.dataDirectory = dataDirectory
        var loaded = Settings()
        if let dir = dataDirectory, let data = try? Data(contentsOf: dir.appendingPathComponent("settings.json")),
           let s = try? JSONDecoder.pelikan.decode(Settings.self, from: data) {
            loaded = s
        }
        if let profile { loaded.shortcutProfile = profile }
        settings = loaded
        shortcutProfile = loaded.shortcutProfile
        keyOverrides = loaded.keyOverrides
        let all = commands ?? BuiltinCommands.all
        registry = CommandRegistry(all)
        keymap = Keymap(commands: all.map(\.descriptor), profile: loaded.shortcutProfile, overrides: loaded.keyOverrides)
        let store = ConnectionStore(fileURL: dataDirectory?.appendingPathComponent("connections.json"), secrets: secrets)
        connections = store
        let box = SettingsBox()
        sessions = SessionManager(store: store, drivers: drivers, settings: { box.value })
        box.value = loaded
        settingsBox = box
    }

    @ObservationIgnored private var settingsBox: SettingsBox

    private func saveSettings() {
        settingsBox.value = settings
        guard let dir = dataDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pelikan.encode(settings) {
            try? data.write(to: dir.appendingPathComponent("settings.json"), options: [.atomic])
        }
    }

    // MARK: Dokumenty

    public var activeDocument: Document? {
        guard let id = activeDocumentID else { return nil }
        return documents.first { $0.id == id }
    }

    @discardableResult
    public func newDocument(_ kind: DocumentKind, text: String = "", fileURL: URL? = nil) -> Document {
        let n = (ordinals[kind] ?? 0) + 1
        ordinals[kind] = n
        let doc = Document(kind: kind, ordinal: n, text: text, fileURL: fileURL)
        documents.append(doc)
        activeDocumentID = doc.id
        return doc
    }

    public func activate(_ id: DocumentID) {
        guard documents.contains(where: { $0.id == id }) else { return }
        activeDocumentID = id
    }

    public func close(_ id: DocumentID) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        documents.remove(at: i)
        if activeDocumentID == id {
            activeDocumentID = documents.isEmpty ? nil : documents[min(i, documents.count - 1)].id
        }
    }

    /// Następne / poprzednie okno w kolejności Window List (Ctrl+Tab / Ctrl+Shift+Tab, NF11).
    public func cycleDocuments(forward: Bool) {
        guard !documents.isEmpty else { return }
        let i = documents.firstIndex { $0.id == activeDocumentID } ?? 0
        let j = (i + (forward ? 1 : documents.count - 1)) % documents.count
        activeDocumentID = documents[j].id
    }

    // MARK: Komendy

    func rebuildKeymap() {
        keymap = Keymap(commands: registry.descriptors, profile: shortcutProfile, overrides: keyOverrides)
    }

    public func register(_ commands: [Command]) {
        for c in commands { registry.register(c) }
        rebuildKeymap()
    }

    public func onInvocation(_ observer: @escaping @MainActor (CommandInvocationRecord) -> Void) {
        invocationObservers.append(observer)
    }

    /// Czy komenda jest teraz dostępna (stan menu, palety, narzędzia agenta).
    public func isEnabled(_ id: CommandID) -> Bool {
        guard let c = registry.command(id) else { return false }
        return c.validate?(self) ?? true
    }

    /// Jedyny punkt wywołania komendy — menu, skróty, paleta, linia poleceń i agent.
    @discardableResult
    public func invoke(_ id: CommandID, _ arguments: CommandArguments = .empty, invoker: Invoker = .user) async throws -> CommandResult {
        guard let command = registry.command(id) else { throw CommandError.unknownCommand(id) }
        let context = CommandContext(workspace: self, invoker: invoker, arguments: arguments)
        let started = Date()
        do {
            let result = try await command.run(context)
            notify(CommandInvocationRecord(command: id, arguments: arguments, invoker: invoker, started: started, outcome: .success(result.message)))
            return result
        } catch {
            notify(CommandInvocationRecord(command: id, arguments: arguments, invoker: invoker, started: started, outcome: .failure(error.localizedDescription)))
            throw error
        }
    }

    /// Skutki komendy „na sucho” (okno zgody, potwierdzenia).
    public func preview(_ id: CommandID, _ arguments: CommandArguments = .empty, invoker: Invoker = .user) async throws -> EffectPreview {
        guard let command = registry.command(id) else { throw CommandError.unknownCommand(id) }
        let context = CommandContext(workspace: self, invoker: invoker, arguments: arguments)
        if let preview = command.preview { return try await preview(context) }
        return EffectPreview(summary: command.descriptor.summary)
    }

    /// Wywołanie z interfejsu: błędy pokazywane użytkownikowi zamiast rzucane.
    public func perform(_ id: CommandID, _ arguments: CommandArguments = .empty) {
        Task {
            do {
                try await invoke(id, arguments)
            } catch CommandError.cancelledByUser {
            } catch {
                ui?.showError(error.localizedDescription)
            }
        }
    }

    private func notify(_ record: CommandInvocationRecord) {
        for o in invocationObservers { o(record) }
    }
}

/// Bieżące ustawienia dla menedżera sesji (unika cyklu referencji do Workspace).
@MainActor
final class SettingsBox {
    var value = Settings()
}
