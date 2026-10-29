import Foundation
import PelikanDB
import PelikanSQL

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
    public static let sections: [(name: String, keys: [String])] = definitions.map { ($0.name, $0.keys) }

    /// Definicje sekcji: nazwa w języku interfejsu, klucz polski i synonimy przyjmowane w parametrze `sections`
    /// (nazwa angielska i dawna sprzed D195; tłumaczenia na wszystkie języki dochodzą w `sectionNames`), pola.
    static let definitions: [(name: String, polish: String, synonyms: [String], keys: [String])] = [
        (L10n.tr("Ogólne"), "Ogólne", ["General"], ["sessionMode", "logoffWithOpenTransaction", "checkConnectionIntervalSeconds", "pinWindowConnectionsByDefault",
                             "appearance", "uiFontName", "uiFontSize", "uiFontWeight", "language", "confirmSaveNewWindows", "worksetAutosave", "autosaveLayout",
                             "quickAccessCommands", "showRibbon", "ribbonCollapsed", "toolDock", "logLevel", "logIncludeNames",
                             "specBodyExtensions", "openSpecBodyPair", "detectExternalFileChanges", "reloadExternalChangesSilently"]),
        (L10n.tr("Okno SQL"), "Okno SQL", ["SQL Window"], ["autoCommitSQL", "autoCommitTestWindow", "autoSelectStatement", "recordsPerPage", "maximumResultSetMegabytes",
                                 "fetchLOBsOnDemand", "dbmsOutputEnabled", "dbmsOutputClearBeforeExecute", "dbmsOutputBufferSize",
                                 "dateFormat", "timestampFormat", "standardQueries", "gridFontSize", "gridFontName", "gridFontWeight", "gridColors", "rowNumbersInCopyExport", "gridNumberLayout",
                                 "notifyLongQuerySeconds", "alignTemplates", "autoAlign", "qbeCaseInsensitive", "qbeAutoContains",
                                 "qbeIgnoreTime", "columnFilterHistory"]),
        (L10n.tr("Edytor"), "Edytor", ["Editor"], ["editorFontName", "editorFontSize", "editorFontWeight", "browserFontName", "browserFontSize", "browserFontWeight", "tabSize", "keywordCase", "editorColors", "browserColors", "highlightCurrentLine", "highlightOccurrences", "highlightTransactions", "liveCodeAnalysis",
                             "useTabCharacter", "indentMode", "backspaceUnindents", "wordWrap", "showLineStatus", "lineNumberInterval", "rightMarginColumn", "showSpecialCharacters", "showCodeContents", "codeContentsOrder", "codeAssistantAutomatic", "codeAssistantDelay",
                             "codeAssistantMatch", "codeAssistantCase", "codeAssistantMinChars", "codeAssistantStandardFunctions",
                             "codeAssistantAllPerLine", "codeAssistantCommaFirst", "autoReplace", "identifierLengthWarning", "editorLigatures",
                             "rememberWindowState"]),
        (L10n.tr("Formater"), "Formater", ["Formatter"], ["beautifier"]),
        (L10n.tr("Klawiatura"), "Klawiatura", ["Keyboard"], ["shortcutProfile", "keyOverrides"]),
        (L10n.tr("Oracle"), "Oracle", [], ["instantClientDirectory", "oracleNetDirectory", "walletDirectory", "requireOwnerForSavedPasswords",
                             "confirmCommitRollback", "confirmProductionChanges", "plsqlWarnings", "compiler", "useDBAViews",
                             "debugInfoOnCompile", "debugInfoNever", "debugInfoAlways", "debuggerSkipPackageInit", "debuggerSkipSys", "selectedStatistics", "profilerTimeUnit", "profilerMinShare"]),
        (L10n.tr("Przeglądarka obiektów"), "Przeglądarka obiektów", ["Object Browser"], ["browserFolders", "browserRecentLimit", "confirmRecompile", "browserFilterContains", "browserShowAccessible", "browserDoubleClick",
                                     "browserDropAction", "browserWorkspaceDrop"]),
        (L10n.tr("Agenci"), "Agenci", ["Agents"], ["agent"]),
        (L10n.tr("Narzędzia"), "Narzędzia", ["Tools"], ["sessionQueries", "schedulerReports", "userTools"]),
    ]

    /// Sekcja pól spoza listy.
    static let other: (name: String, polish: String, synonyms: [String]) = (L10n.tr("Inne"), "Inne", ["Other"])

    /// Pola nigdy nieeksportowane: prywatna historia użytkownika.
    static let privateKeys: Set<String> = ["recentFiles"]

    public static func section(of key: String) -> String {
        sections.first { $0.keys.contains(key) }?.name ?? other.name
    }

    /// Nazwy sekcji z parametru `sections` komend `prefs.export` i `prefs.import` (użytkownik, makro, agent) zamienione
    /// na nazwy z `sections`. Nazwy sekcji są przetłumaczone na język interfejsu, więc przyjmowane są też: klucz polski,
    /// synonimy (angielska i dawna nazwa) oraz tłumaczenie na każdy język interfejsu — makro nagrane w innym języku dalej
    /// trafia w sekcję. Bez względu na wielkość liter; nieznana nazwa — błąd z listą znanych.
    public static func sectionNames(_ names: Set<String>,
                                    translate: (String, String) -> String? = { L10n.translation(of: $0, language: $1) }) throws -> Set<String> {
        let all = definitions.map { ($0.name, $0.polish, $0.synonyms) } + [(other.name, other.polish, other.synonyms)]
        let languages = UserManual.languages.filter { $0 != "pl" }
        func matches(_ n: String, _ s: (String, String, [String])) -> Bool {
            let candidates = [s.0, s.1] + s.2 + languages.compactMap { translate(s.1, $0) }
            return candidates.contains { $0.caseInsensitiveCompare(n) == .orderedSame }
        }
        return try Set(names.map { n in
            guard let s = all.first(where: { matches(n, $0) }) else {
                throw CommandError.invalidArgument("sections", L10n.tr("nieznana sekcja „\(n)”; znane: \(all.map(\.0).joined(separator: ", "))"))
            }
            return s.0
        })
    }

    /// Plik eksportu: wybrane sekcje (nil — wszystkie), bez pól prywatnych. Hasła nie są częścią preferencji —
    /// leżą w Pęku kluczy.
    public static func export(_ s: Settings, sections chosen: Set<String>?) throws -> Data {
        let chosen = try chosen.map { try sectionNames($0) }
        let all = values(of: s).filter { !privateKeys.contains($0.key) && (chosen?.contains(section(of: $0.key)) ?? true) }
        let file = ExportFile(format: ExportFile.formatName, version: ExportFile.currentVersion, values: all)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(file)
    }

    /// Wartości z pliku eksportu (wybrane sekcje; nieznane pola pominięte).
    public static func importValues(_ data: Data, sections chosen: Set<String>?) throws -> [String: JSONValue] {
        let file = try JSONDecoder().decode(ExportFile.self, from: data)
        guard file.format == ExportFile.formatName else { throw CommandError.notAvailable(L10n.tr("To nie jest plik ustawień Pelikana")) }
        let known = values(of: Settings())
        let chosen = try chosen.map { try sectionNames($0) }
        // Plik w starszej wersji formatu (sprzed D202) — migracja ustawień formatera.
        let values = file.version < 2 ? migratingLegacyBeautifier(file.values) : file.values
        return values.filter { known[$0.key] != nil && !privateKeys.contains($0.key) && (chosen?.contains(section(of: $0.key)) ?? true) }
    }

    /// Migracja ustawień formatera zapisanych przed D202 (`BeautifierOptions.migratingLegacy`) — tylko przy odczycie
    /// plików: settings.json, sets.json i eksportu w wersji formatu 1. Częściowy JSON z komendy, agenta albo makra
    /// (bez znacznika) to wartości bieżące — nie przechodzi tędy.
    public static func migratingLegacyBeautifier(_ values: [String: JSONValue]) -> [String: JSONValue] {
        guard let b = values["beautifier"], case .object = b, let data = try? JSONEncoder().encode(b),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let migrated = try? JSONSerialization.data(withJSONObject: BeautifierOptions.migratingLegacy(object)),
              let value = try? JSONDecoder().decode(JSONValue.self, from: migrated) else { return values }
        var out = values
        out["beautifier"] = value
        return out
    }

    /// Pola, które uruchamiają programy albo ładują kod: narzędzia użytkownika (program i argumenty), polecenia CLI
    /// agentów i tryb ścisły, edytor i przeglądarka różnic zewnętrzne, Instant Client (biblioteka ładowana w proces),
    /// katalogi Oracle Net i portfela, wyszukiwania w sieci (zaznaczony tekst wysyłany pod adres). Import z cudzego pliku
    /// tylko ze świadomą zgodą — jak definicje połączeń z tunelem SSH albo skryptem inicjalizacji.
    static let codeRunningKeys: [(key: String, label: String)] = [
        ("userTools", L10n.tr("Narzędzia użytkownika")), ("agent", L10n.tr("Agenci")),
        ("externalEditor", L10n.tr("Edytor zewnętrzny")), ("externalDiff", L10n.tr("Zewnętrzna przeglądarka różnic")),
        ("instantClientDirectory", L10n.tr("Oracle Instant Client")), ("oracleNetDirectory", L10n.tr("Oracle Net i Oracle Wallet")),
        ("walletDirectory", L10n.tr("Oracle Net i Oracle Wallet")), ("webSearches", L10n.tr("Szukaj w sieci")),
    ]

    /// Ustawienia z `codeRunningKeys`, które import zmieniłby względem obecnych (nazwy do pytania, bez powtórzeń). Dla
    /// agentów liczą się tylko polecenia CLI i tryb ścisły — limity niczego nie uruchamiają.
    public static func changesRunningCode(_ imported: [String: JSONValue], current: Settings) -> [String] {
        let now = values(of: current)
        var labels: [String] = []
        for (key, label) in codeRunningKeys {
            guard let new = imported[key] else { continue }
            let changed = key == "agent"
                ? ["profiles", "strictMode"].contains { k in new[k].map { $0 != now[key]?[k] } ?? false }
                : new != now[key]
            if changed, !labels.contains(label) { labels.append(label) }
        }
        return labels
    }

    struct ExportFile: Codable {
        static let formatName = "pelikan-preferences"
        /// 2 — od D202 (ustawienia formatera ze znacznikiem `defaultsVersion`; plik w wersji 1 migrowany przy imporcie).
        static let currentVersion = 2
        var format: String
        var version: Int
        var values: [String: JSONValue]
    }
}

/// Zestawy preferencji w katalogu danych (`Preferences/sets.json`); zestaw osobisty użytkownika — `settings.json`
/// (zapis częściowy względem zestawów domyślnych).
public struct PreferenceSetStore: Sendable {
    public let fileURL: URL?
    /// Komunikat o nieczytelnym pliku zestawów (zachowanym jako `.bad-…`, D182).
    public private(set) var loadProblem: String?
    /// Kopia nieczytelnego pliku się nie udała — zapis zablokowany, żeby nie nadpisać oryginału.
    private var saveBlocked = false

    public init(directory: URL?) {
        fileURL = directory?.appendingPathComponent("Preferences", isDirectory: true).appendingPathComponent("sets.json")
    }

    /// Zestawy z pliku; nieczytelny plik (uszkodzony albo z nowszej wersji) jest zachowany obok, zanim pierwszy zapis
    /// nadpisze go pustą listą.
    public mutating func load() -> [PreferenceSet] {
        guard let u = fileURL, let d = try? Data(contentsOf: u) else { return [] }
        guard let sets = try? JSONDecoder().decode([PreferenceSet].self, from: d) else {
            let (message, preserved) = DamagedFile.preserve(u)
            loadProblem = message
            saveBlocked = !preserved
            return []
        }
        // Zestawy zapisane przed D202 — migracja ustawień formatera (bez znacznika `defaultsVersion`).
        return sets.filter { $0.kind != .personalUser }.map { set in
            var set = set
            set.values = PreferenceSets.migratingLegacyBeautifier(set.values)
            return set
        }
    }

    public func save(_ sets: [PreferenceSet]) throws {
        guard let u = fileURL else { return }
        guard !saveBlocked else { throw CommandError.notAvailable(loadProblem ?? "") }
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(sets.filter { $0.kind != .personalUser }).write(to: u, options: .atomic)
    }
}
