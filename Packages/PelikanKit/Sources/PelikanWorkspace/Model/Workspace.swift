import Foundation
import Observation
import PelikanDB
import PelikanSQL

/// Usługi interfejsu, których potrzebują komendy (implementuje aplikacja; w testach — atrapy).
@MainActor
public protocol UIServices: AnyObject {
    func showError(_ message: String)
    func showCommandPalette()
    /// Pytanie z wyborem (np. zapis zmian przy zamykaniu). Zwraca indeks wybranego przycisku albo nil (anuluj).
    func ask(_ title: String, message: String, buttons: [String]) async -> Int?
    /// Okno definicji połączenia (nil = nowe).
    func showConnectionEditor(connectionID: UUID?)
    /// Okno logowania (wybór połączenia).
    func showLogon()
    /// Okno „Zmienne” (UG 7.5, 12.3): wartości dla zmiennych &, : i parametrów Jaspera; nil = anulowano.
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]?
    /// Schowek: tekst i opcjonalnie HTML (wklejanie do Excela/Numbers z formatowaniem).
    func copyToClipboard(_ text: String, html: String?)
    /// Okno zapisu pliku; zwraca false przy anulowaniu.
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool
    /// Large Data Editor (UG 27) dla komórki siatki.
    func showLargeDataEditor(_ model: LargeDataModel)
    /// Pytanie o tekst (np. numer linii); nil — anulowano.
    func askText(_ title: String, message: String, defaultValue: String) async -> String?
    /// Okno Znajdź i zamień dla aktywnego edytora.
    func showFindReplace()
    /// Okno informacji o obiekcie (Opis, Właściwości): tabela kolumn i wierszy tekstu.
    func showObjectInfo(title: String, columns: [String], rows: [[String]])
    /// Ekran pomocy przy braku Oracle Instant Client (pobranie, wskazanie katalogu, sterownik thin).
    func showClientMissingHelp(_ message: String)
    /// Okno historii poleceń (Recall Statement, UG 25.5).
    func showRecallStatement()
    /// Okno wyboru plików do otwarcia.
    func chooseFilesToOpen() async -> [URL]
    /// Okno wyboru nazwy pliku do zapisu; nil — anulowano.
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL?
    /// Lista podpowiedzi Code Assistant w edytorze dokumentu (UG 25.4).
    func showCompletion(_ result: CompletionResult, for document: Document)
    /// Okno Find Database Objects (UG 24.2) z kryteriami początkowymi.
    func showFindObjects(_ criteria: DatabaseSearchCriteria)
    /// Okno Compile Invalid Objects (UG 24.3).
    func showCompileInvalid()
    /// Przeglądarka różnic (UG 26): lewy i prawy tekst z tytułami.
    func showDiff(left: String, right: String, leftTitle: String, rightTitle: String)
    /// Edytor definicji tabeli (UG 9.1): `original` nil — nowa tabela.
    func showTableEditor(_ definition: TableDefinition, original: TableDefinition?, connectionID: UUID)
    /// Prosty edytor obiektu (sekwencja, synonim, indeks, użytkownik, rola — UG 9.2–9.11).
    func showObjectEditor(_ editor: SimpleObjectEditor, connectionID: UUID)
    /// Okno punktów przerwania (UG 5.10).
    func showBreakpoints()
    /// Okno debugera (stos, zmienne, przyciski kroków) dla okna testu.
    func showDebugger(_ debugger: DebuggerEngine, document: Document)
    /// Formularz zmiennych szablonu (UG 31.2); nil = anulowano.
    func askTemplateValues(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]?

}

extension UIServices {
    public func showCompletion(_ result: CompletionResult, for document: Document) {}
    public func showFindObjects(_ criteria: DatabaseSearchCriteria) {}
    public func showCompileInvalid() {}
    public func showDebugger(_ debugger: DebuggerEngine, document: Document) {}
    public func showBreakpoints() {}
    public func showObjectEditor(_ editor: SimpleObjectEditor, connectionID: UUID) {}
    public func showTableEditor(_ definition: TableDefinition, original: TableDefinition?, connectionID: UUID) {}
    public func showDiff(left: String, right: String, leftTitle: String, rightTitle: String) {}
    public func askTemplateValues(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? {
        await askVariables(requests, document: document)
    }
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
    /// Obiekt zaznaczony w Object Browserze (cel komend `ob.*`).
    public var selectedObject: DBObject?
    /// Ostatnie wyszukiwanie (Znajdź następne — F3).
    public var lastSearch: TextSearch?
    /// Globalna historia wykonanych poleceń (Recall Statement, UG 25.5).
    public private(set) var history: [HistoryEntry] = []
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
    /// Szablony kodu (UG 31): wbudowane i użytkownika z katalogu danych.
    @ObservationIgnored public private(set) lazy var templates = TemplateLibrary(directory: dataDirectory?.appendingPathComponent("Templates", isDirectory: true))
    /// Zmienia się po zapisie lub usunięciu szablonu (Template Window przeładowuje listę).
    public var templatesGeneration = 0
    /// Punkty przerwania (UG 5.10) i debugery okien testu.
    public var breakpoints: [Breakpoint] = []
    /// Punkty przerwania na kodach błędów Oracle (bez „ORA-”, np. 1403).
    public var errorBreakpoints: [Int] = []
    @ObservationIgnored var debuggers: [DocumentID: DebuggerEngine] = [:]
    /// Historia skoków (UG 25.20) — Wstecz / Naprzód.
    public internal(set) var navigationBack: [NavigationPoint] = []
    public internal(set) var navigationForward: [NavigationPoint] = []

    @ObservationIgnored public weak var ui: (any UIServices)?
    @ObservationIgnored private var invocationObservers: [@MainActor (CommandInvocationRecord) -> Void] = []
    @ObservationIgnored private var ordinals: [DocumentKind: Int] = [:]
    /// Silniki SQL*Plus okien Command Window (stan SET/DEFINE/VARIABLE trwa przez życie okna).
    @ObservationIgnored private var sqlplusEngines: [DocumentID: SQLPlusEngine] = [:]
    /// Metadane słownika per połączenie (Object Browser, Code Assistant).
    @ObservationIgnored var metadataProviders: [UUID: MetadataProvider] = [:]

    public func sqlplusEngine(for doc: Document) -> SQLPlusEngine {
        if let e = sqlplusEngines[doc.id] { return e }
        let e = SQLPlusEngine(workspace: self, document: doc)
        sqlplusEngines[doc.id] = e
        return e
    }


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
        if let dir = dataDirectory, let data = try? Data(contentsOf: dir.appendingPathComponent("history.json")),
           let h = try? JSONDecoder.pelikan.decode([HistoryEntry].self, from: data) {
            history = h
        }
    }

    /// Dopisuje polecenie do historii (bez poleceń z hasłami, bez duplikatu ostatniego), limit 200 (UG 23.26).
    public func recordHistory(_ sql: String, limit: Int = 200) {
        let text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !SQLExecutor.containsPassword(text) else { return }
        if history.first?.text == text { history.removeFirst() }
        let user = sessions.mainConnectionID.flatMap { connections.connection($0)?.target.driverUserName } ?? ""
        history.insert(HistoryEntry(date: Date(), user: user, text: text), at: 0)
        if history.count > limit { history.removeLast(history.count - limit) }
        guard let dir = dataDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pelikan.encode(history) {
            try? data.write(to: dir.appendingPathComponent("history.json"), options: [.atomic])
        }
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
        sqlplusEngines[id] = nil
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
        // Stan menu obowiązuje wszystkich wywołujących (także agenta): komenda wyłączona nie wykonuje się. Komenda
        // wywołana z argumentami (np. obiekt wskazany nazwą zamiast zaznaczenia) sama sprawdza swój cel.
        if !command.isPlanned, arguments.values.isEmpty, let validate = command.validate, !validate(self) {
            throw CommandError.notAvailable(L10n.tr("„\(command.descriptor.title)” jest teraz niedostępne"))
        }
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
            } catch DatabaseError.clientMissing(let message) {
                ui?.showClientMissingHelp(message)
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

// MARK: - Połączenia okien

extension Workspace {
    /// Połączenie okna: przypięte albo główne (UG 20.2).
    public func effectiveConnection(of doc: Document) -> UUID? {
        doc.connectionID ?? sessions.mainConnectionID
    }

    /// Sesja okna wg trybu sesji (łączy, jeśli trzeba).
    public func session(for doc: Document) async throws -> any DatabaseSession {
        guard let c = effectiveConnection(of: doc) else { throw CommandError.notConnected }
        return try await sessions.session(sessions.key(forDocument: doc.id, connection: c))
    }

    /// Kończy transakcje okien (COMMIT/ROLLBACK) przed rozłączeniem lub zamknięciem.
    public func endTransactions(of docs: [Document], commit: Bool) async throws {
        for d in docs {
            guard let c = effectiveConnection(of: d),
                  let s = sessions.existingSession(sessions.key(forDocument: d.id, connection: c)) else { continue }
            if commit { try await s.commit() } else { try await s.rollback() }
            d.transactionOpen = false
        }
    }
}

/// Wpis historii poleceń.
public struct HistoryEntry: Sendable, Codable, Hashable {
    public var date: Date
    public var user: String
    public var text: String
}
