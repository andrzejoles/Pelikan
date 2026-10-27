import Foundation
import PelikanDB

/// Zestaw preferencji (UG 23.35, PD-PREF-002): częściowe wartości preferencji (klucz = nazwa pola `Settings`,
/// wartość = JSON) dla wszystkich połączeń albo dla połączeń pasujących do wzorca.
public struct PreferenceSet: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// Kolejność = pierwszeństwo rosnąco (wzorzec: osobisty połączenia > osobisty użytkownika > domyślny połączenia
        /// > domyślny globalny).
        case defaultGlobal, defaultConnection, personalUser, personalConnection

        public var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
        public var isConnection: Bool { self == .defaultConnection || self == .personalConnection }
        public var isDefault: Bool { self == .defaultGlobal || self == .defaultConnection }

        public var displayName: String {
            switch self {
            case .defaultGlobal: L10n.tr("Domyślny (wszystkie połączenia)")
            case .defaultConnection: L10n.tr("Domyślny połączenia")
            case .personalUser: L10n.tr("Osobisty")
            case .personalConnection: L10n.tr("Osobisty połączenia")
            }
        }
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// Wzorzec połączeń (`użytkownik@baza`, nazwa połączenia; `*` i `%` — dowolny ciąg, `?` i `_` — jeden znak).
    public var pattern: String?
    public var values: [String: JSONValue]

    public init(id: UUID = UUID(), name: String, kind: Kind, pattern: String? = nil, values: [String: JSONValue] = [:]) {
        self.id = id; self.name = name; self.kind = kind; self.pattern = pattern; self.values = values
    }

    /// Czy zestaw obowiązuje dla połączenia (zestawy bez wzorca — zawsze; połączeniowe bez połączenia — nie).
    public func applies(to candidates: [String]) -> Bool {
        guard kind.isConnection else { return true }
        guard let p = pattern?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return false }
        return candidates.contains { PreferenceSets.matches(p, $0) }
    }
}

extension JSONValue {
    /// Krótki opis wartości (lista nadpisań w Preferencjach).
    public var summary: String {
        switch self {
        case .null: "—"
        case .bool(let b): b ? L10n.tr("tak") : L10n.tr("nie")
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .string(let s): s
        case .array(let a): "[\(a.count)]"
        case .object(let o): "{\(o.count)}"
        }
    }
}

public enum PreferenceSets {
    /// Pola preferencji jako słownik JSON (pola `nil` — `null`, żeby zestaw mógł je jawnie wyzerować).
    public static func values(of s: Settings) -> [String: JSONValue] {
        guard let data = try? JSONEncoder.pelikan.encode(s), case .object(var o)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        for k in optionalKeys where o[k] == nil { o[k] = .null }
        return o
    }

    /// Pola opcjonalne `Settings` (koder je pomija, gdy są `nil`) — wykrywane z typu, żeby nowe pole nie wypadło
    /// z nakładania zestawów.
    static let optionalKeys: [String] = Mirror(reflecting: Settings()).children.compactMap { child in
        guard let label = child.label, Mirror(reflecting: child.value).displayStyle == .optional else { return nil }
        return label
    }

    /// Preferencje z nałożonych zestawów (w kolejności pierwszeństwa rosnąco) na wartości wbudowane.
    public static func merge(_ sets: [PreferenceSet], base: Settings = Settings()) -> Settings {
        var o = values(of: base)
        for set in sets.sorted(by: { $0.kind.rank < $1.kind.rank }) {
            for (k, v) in set.values where o[k] != nil { o[k] = v }
        }
        guard let data = try? JSONEncoder().encode(JSONValue.object(o)),
              let s = try? JSONDecoder.pelikan.decode(Settings.self, from: data) else { return base }
        return s
    }

    /// Wartości różniące się od podstawy (zapis częściowy zestawu).
    public static func difference(_ s: Settings, from base: Settings) -> [String: JSONValue] {
        let a = values(of: s), b = values(of: base)
        return a.filter { b[$0.key] != $0.value }
    }

    /// Zestaw, z którego pochodzi wartość pola (najwyższe pierwszeństwo), albo nil — wartość wbudowana.
    public static func source(of key: String, in sets: [PreferenceSet]) -> PreferenceSet? {
        sets.filter { $0.values[key] != nil }.max { $0.kind.rank < $1.kind.rank }
    }

    /// Wzorzec połączenia: `*`/`%` — dowolny ciąg, `?`/`_` — jeden znak; bez rozróżniania wielkości liter.
    public static func matches(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(text.lowercased())
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "?" || p[pi] == "_" || p[pi] == t[ti] { pi += 1; ti += 1 }
            else if pi < p.count, p[pi] == "*" || p[pi] == "%" { star = pi; mark = ti; pi += 1 }
            else if star >= 0 { pi = star + 1; mark += 1; ti = mark }
            else { return false }
        }
        while pi < p.count, p[pi] == "*" || p[pi] == "%" { pi += 1 }
        return pi == p.count
    }

    /// Nazwy, z którymi porównywany jest wzorzec: `użytkownik@baza` i nazwa połączenia.
    public static func candidates(for def: ConnectionDefinition?) -> [String] {
        guard let def else { return [] }
        return ["\(def.target.user)@\(def.target.connectString)", def.name].filter { !$0.isEmpty }
    }

    // MARK: Sekcje (eksport i import, PD-PREF-003)

    /// Sekcje preferencji jak karty okna Preferencji; pola spoza listy — „Inne”.
    public static let sections: [(name: String, keys: [String])] = [
        (L10n.tr("Ogólne"), ["sessionMode", "logoffWithOpenTransaction", "checkConnectionIntervalSeconds", "pinWindowConnectionsByDefault",
                             "appearance", "uiFontName", "uiFontSize", "uiFontWeight", "language", "confirmSaveNewWindows", "worksetAutosave", "autosaveLayout",
                             "quickAccessCommands", "showRibbon", "ribbonCollapsed", "logLevel", "logIncludeNames"]),
        (L10n.tr("SQL Window"), ["autoCommitSQL", "autoCommitTestWindow", "autoSelectStatement", "recordsPerPage", "maximumResultSetMegabytes",
                                 "fetchLOBsOnDemand", "dbmsOutputEnabled", "dbmsOutputClearBeforeExecute", "dbmsOutputBufferSize",
                                 "dateFormat", "timestampFormat", "standardQueries", "gridFontSize", "gridFontName", "gridFontWeight", "gridColors", "rowNumbersInCopyExport", "gridNumberLayout",
                                 "notifyLongQuerySeconds", "alignTemplates", "autoAlign", "qbeCaseInsensitive", "qbeAutoContains",
                                 "qbeIgnoreTime", "columnFilterHistory"]),
        (L10n.tr("Edytor"), ["editorFontName", "editorFontSize", "editorFontWeight", "browserFontName", "browserFontSize", "browserFontWeight", "tabSize", "keywordCase", "editorColors", "browserColors", "highlightCurrentLine", "highlightOccurrences", "highlightTransactions", "liveCodeAnalysis",
                             "useTabCharacter", "indentMode", "backspaceUnindents", "wordWrap", "showLineStatus", "lineNumberInterval", "rightMarginColumn", "showSpecialCharacters", "showCodeContents", "codeContentsOrder", "codeAssistantAutomatic", "codeAssistantDelay",
                             "codeAssistantMatch", "codeAssistantCase", "codeAssistantMinChars", "codeAssistantStandardFunctions",
                             "codeAssistantAllPerLine", "codeAssistantCommaFirst", "autoReplace", "identifierLengthWarning", "editorLigatures",
                             "rememberWindowState"]),
        (L10n.tr("Formater"), ["beautifier"]),
        (L10n.tr("Klawiatura"), ["shortcutProfile", "keyOverrides"]),
        (L10n.tr("Oracle"), ["instantClientDirectory", "oracleNetDirectory", "walletDirectory", "requireOwnerForSavedPasswords",
                             "confirmCommitRollback", "confirmProductionChanges", "plsqlWarnings", "compiler", "useDBAViews",
                             "debugInfoOnCompile", "debugInfoNever", "debugInfoAlways", "debuggerSkipPackageInit", "debuggerSkipSys", "selectedStatistics", "profilerTimeUnit", "profilerMinShare"]),
        (L10n.tr("Object Browser"), ["browserFolders", "browserRecentLimit", "confirmRecompile", "browserFilterContains", "browserDoubleClick",
                                     "browserDropAction", "browserWorkspaceDrop"]),
        (L10n.tr("Agenci"), ["agent"]),
        (L10n.tr("Narzędzia"), ["sessionQueries", "schedulerReports", "userTools"]),
    ]

    /// Pola nigdy nieeksportowane: prywatna historia użytkownika.
    static let privateKeys: Set<String> = ["recentFiles"]

    public static func section(of key: String) -> String {
        sections.first { $0.keys.contains(key) }?.name ?? L10n.tr("Inne")
    }

    /// Plik eksportu: wybrane sekcje (nil — wszystkie), bez pól prywatnych. Hasła nie są częścią preferencji —
    /// leżą w Pęku kluczy.
    public static func export(_ s: Settings, sections chosen: Set<String>?) throws -> Data {
        let all = values(of: s).filter { !privateKeys.contains($0.key) && (chosen?.contains(section(of: $0.key)) ?? true) }
        let file = ExportFile(format: ExportFile.formatName, version: 1, values: all)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(file)
    }

    /// Wartości z pliku eksportu (wybrane sekcje; nieznane pola pominięte).
    public static func importValues(_ data: Data, sections chosen: Set<String>?) throws -> [String: JSONValue] {
        let file = try JSONDecoder().decode(ExportFile.self, from: data)
        guard file.format == ExportFile.formatName else { throw CommandError.notAvailable(L10n.tr("To nie jest plik preferencji Pelikana")) }
        let known = values(of: Settings())
        return file.values.filter { known[$0.key] != nil && !privateKeys.contains($0.key) && (chosen?.contains(section(of: $0.key)) ?? true) }
    }

    struct ExportFile: Codable {
        static let formatName = "pelikan-preferences"
        var format: String
        var version: Int
        var values: [String: JSONValue]
    }
}

/// Zestawy preferencji w katalogu danych (`Preferences/sets.json`); zestaw osobisty użytkownika — `settings.json`
/// (zapis częściowy względem zestawów domyślnych).
public struct PreferenceSetStore: Sendable {
    public let fileURL: URL?

    public init(directory: URL?) {
        fileURL = directory?.appendingPathComponent("Preferences", isDirectory: true).appendingPathComponent("sets.json")
    }

    public func load() -> [PreferenceSet] {
        guard let u = fileURL, let d = try? Data(contentsOf: u), let sets = try? JSONDecoder().decode([PreferenceSet].self, from: d) else { return [] }
        return sets.filter { $0.kind != .personalUser }
    }

    public func save(_ sets: [PreferenceSet]) throws {
        guard let u = fileURL else { return }
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(sets.filter { $0.kind != .personalUser }).write(to: u, options: .atomic)
    }
}
