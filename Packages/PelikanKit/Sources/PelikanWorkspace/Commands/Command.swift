import Foundation

/// Poziom dostępu agenta AI do komendy (PROMPT §7.4).
public enum AgentAccess: Int, Comparable, Codable, Sendable, CaseIterable {
    /// Narzędzie nie istnieje dla agenta.
    case none = 0
    /// Agent widzi stan lub wynik, nic nie zmienia.
    case read = 1
    /// Agent zgłasza operację, użytkownik zatwierdza po podglądzie.
    case approval = 2
    /// Agent wykonuje bez pytania; wszystko trafia do dziennika i da się cofnąć.
    case full = 3

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var displayName: String {
        switch self {
        case .none: L10n.tr("Brak")
        case .read: L10n.tr("Odczyt")
        case .approval: L10n.tr("Za zgodą")
        case .full: L10n.tr("Pełny")
        }
    }
}

public struct CommandID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible, Comparable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Kategoria = menu główne (kolejność menu jak wstążki PL/SQL Developer: File, Project, Edit, Session, Debug, Tools,
/// Reports, Configure, View, Window, Help — dopasowane do HIG: Configure → Ustawienia w menu aplikacji).
public enum CommandCategory: String, Sendable, Codable, CaseIterable {
    case file, project, edit, session, debug, tools, reports, view, window, help

    public var displayName: String {
        switch self {
        case .file: L10n.tr("Plik")
        case .project: L10n.tr("Projekt")
        case .edit: L10n.tr("Edycja")
        case .session: L10n.tr("Sesja")
        case .debug: L10n.tr("Debugowanie")
        case .tools: L10n.tr("Narzędzia")
        case .reports: L10n.tr("Raporty")
        case .view: L10n.tr("Widok")
        case .window: L10n.tr("Okno")
        case .help: L10n.tr("Pomoc")
        }
    }
}

/// Rodzaj skutków komendy (podgląd, polityka uprawnień agenta).
public enum CommandEffect: String, Sendable, Codable {
    /// Tylko odczyt stanu lub danych.
    case none
    /// Zmienia stan interfejsu (okna, karty, zaznaczenie, nawigacja).
    case uiState
    /// Zmienia tekst w edytorze (cofalne w aplikacji).
    case modifiesEditor
    /// Zmienia dane lub obiekty w bazie (DML, DDL, kompilacja, PL/SQL).
    case modifiesDatabase
    /// Kończy transakcję (COMMIT/ROLLBACK).
    case transaction
    /// Pliki, programy zewnętrzne, system operacyjny.
    case external
    /// Zmienia ustawienia aplikacji lub połączenia.
    case settings
}

public enum ParameterType: String, Sendable, Codable {
    case string, integer, boolean, object, sql
}

public struct CommandParameter: Sendable, Hashable {
    public var name: String
    public var type: ParameterType
    public var required: Bool
    public var description: String
    public var allowedValues: [String]?

    public init(_ name: String, _ type: ParameterType, required: Bool = false, _ description: String, allowed: [String]? = nil) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
        allowedValues = allowed
    }
}

/// Profil skrótów klawiszowych (PROMPT §3.4).
public enum ShortcutProfile: String, Codable, Sendable, CaseIterable {
    /// Klawisze jak w PL/SQL Developer (F-klawisze, Ctrl), z zamiennikami dla klawiatury MacBooka.
    case plsqlDeveloper
    /// Skróty macOS (Cmd).
    case macOS

    public var displayName: String {
        switch self {
        case .plsqlDeveloper: L10n.tr("PL/SQL Developer (F-klawisze, Ctrl)")
        case .macOS: L10n.tr("macOS (Cmd)")
        }
    }
}

public struct CommandDescriptor: Sendable {
    public let id: CommandID
    public let title: String
    public let category: CommandCategory
    /// Podmenu w menu kategorii (np. „Nowy”), nil = bezpośrednio w menu.
    public let submenu: String?
    public let shortcuts: [ShortcutProfile: [KeyChord]]
    public let parameters: [CommandParameter]
    public let agentAccess: AgentAccess
    public let effect: CommandEffect
    /// Opis skutków dla człowieka i dla agenta (opis narzędzia MCP).
    public let summary: String
    /// Czy pokazywać w menu (pomocnicze tylko w palecie i dla agenta).
    public let inMenu: Bool
    /// Identyfikator wiersza macierzy funkcji (docs/FEATURES.md).
    public let feature: String?

    /// - Parameters:
    ///   - pd: skróty profilu PL/SQL Developer; `mac`: skróty profilu macOS (domyślnie pd + zamienniki z Cmd).
    public init(id: CommandID, title: String, category: CommandCategory, submenu: String? = nil,
                pd: [String] = [], mac: [String]? = nil, parameters: [CommandParameter] = [],
                agent: AgentAccess, effect: CommandEffect, summary: String, inMenu: Bool = true,
                feature: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.submenu = submenu
        let explicitPD = pd.compactMap(KeyChord.init(string:))
        let explicitMac = (mac ?? []).compactMap(KeyChord.init(string:))
        // Profil PL/SQL Developer: klawisze wzorca + skróty z Cmd z profilu macOS (wzorzec z Windows nie używa Cmd,
        // więc ⌘S, ⌘W, ⌘N działają w obu profilach bez kolizji).
        var pdChords: [KeyChord] = []
        for chord in explicitPD + explicitMac.filter({ $0.modifiers.contains(.command) }) where !pdChords.contains(chord) {
            pdChords.append(chord)
        }
        // Profil macOS: skróty z Cmd, potem F-klawisze wzorca (działają też z fn); Ctrl+litera wzorca tylko, gdy nie
        // podano jawnie skrótów macOS (Ctrl+litera w polach tekstowych macOS to skróty Emacsa).
        var macChords: [KeyChord] = []
        for chord in explicitMac + (mac == nil ? explicitPD : explicitPD.filter(\.isFunctionKey)) where !macChords.contains(chord) {
            macChords.append(chord)
        }
        shortcuts = [.plsqlDeveloper: pdChords, .macOS: macChords]
        self.parameters = parameters
        agentAccess = agent
        self.effect = effect
        self.summary = summary
        self.inMenu = inMenu
        self.feature = feature
    }
}

public struct CommandResult: Sendable {
    public var message: String?
    public var value: JSONValue?

    public init(message: String? = nil, value: JSONValue? = nil) {
        self.message = message
        self.value = value
    }

    public static let ok = CommandResult()
}

/// Skutki komendy policzone „na sucho” (okno zgody agenta, potwierdzenia użytkownika).
public struct EffectPreview: Sendable, Hashable, Codable {
    public var summary: String
    /// Tekst poleceń, które zostaną wykonane.
    public var statements: [String]
    /// Obiekty bazy, na które wpływa (z ALL_DEPENDENCIES).
    public var affectedObjects: [String]
    /// Szacowana liczba wierszy (DML) albo nil.
    public var estimatedRows: Int64?
    /// Plan wykonania (tekst) albo nil.
    public var plan: String?
    /// Czy zmiana jest nieodwracalna (COMMIT, DDL na tabelach).
    public var irreversible: Bool

    public init(summary: String, statements: [String] = [], affectedObjects: [String] = [], estimatedRows: Int64? = nil,
                plan: String? = nil, irreversible: Bool = false) {
        self.summary = summary
        self.statements = statements
        self.affectedObjects = affectedObjects
        self.estimatedRows = estimatedRows
        self.plan = plan
        self.irreversible = irreversible
    }
}

public enum CommandError: Error, LocalizedError, Sendable, Equatable {
    case unknownCommand(CommandID)
    case missingArgument(String)
    case invalidArgument(String, String)
    case notAvailable(String)
    case notConnected
    case cancelledByUser

    public var errorDescription: String? {
        switch self {
        case .unknownCommand(let id): L10n.tr("Nieznana komenda: \(id.rawValue)")
        case .missingArgument(let n): L10n.tr("Brak argumentu: \(n)")
        case .invalidArgument(let n, let why): L10n.tr("Nieprawidłowy argument \(n): \(why)")
        case .notAvailable(let why): why
        case .notConnected: L10n.tr("Brak połączenia z bazą")
        case .cancelledByUser: L10n.tr("Anulowano")
        }
    }
}

/// Kto wywołał komendę.
public enum Invoker: Codable, Sendable, Hashable {
    case user
    case agent(sessionID: String, agentName: String)

    public var isAgent: Bool { if case .agent = self { true } else { false } }
}

/// Kontekst wywołania: model, usługi interfejsu i kto wywołuje.
@MainActor
public struct CommandContext {
    public let workspace: Workspace
    public let invoker: Invoker
    public let arguments: CommandArguments

    public var ui: (any UIServices)? { workspace.ui }
    public var isAgent: Bool { invoker.isAgent }
}

public typealias CommandHandler = @MainActor @Sendable (CommandContext) async throws -> CommandResult
public typealias PreviewHandler = @MainActor @Sendable (CommandContext) async throws -> EffectPreview
public typealias ValidationHandler = @MainActor @Sendable (Workspace) -> Bool

public struct Command: Sendable {
    public let descriptor: CommandDescriptor
    let run: CommandHandler
    let preview: PreviewHandler?
    /// Czy komenda jest teraz dostępna (stan menu); nil = zawsze.
    let validate: ValidationHandler?

    public init(_ descriptor: CommandDescriptor, validate: ValidationHandler? = nil, preview: PreviewHandler? = nil,
                run: @escaping CommandHandler) {
        self.descriptor = descriptor
        self.run = run
        self.preview = preview
        self.validate = validate
    }

    public var id: CommandID { descriptor.id }
}
