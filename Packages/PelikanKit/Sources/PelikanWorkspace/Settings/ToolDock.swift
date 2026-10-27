import Foundation

/// Miejsce narzędzia (PD-UI-003, D183): prawy albo dolny panel okna głównego albo osobne, pływające okno.
public enum ToolPlacement: String, Codable, Sendable, CaseIterable {
    case right, bottom, floating

    public var displayName: String {
        switch self {
        case .right: L10n.tr("Panel po prawej")
        case .bottom: L10n.tr("Panel na dole")
        case .floating: L10n.tr("Osobne okno")
        }
    }
}

/// Dokowanie narzędzi: zapamiętane miejsce każdego rodzaju narzędzia i autoukrywanie paneli.
public struct ToolDockSettings: Codable, Sendable, Hashable {
    /// Rodzaj narzędzia (`ToolDockSettings.kind(of:)`) → miejsce wybrane przez użytkownika.
    public var placements: [String: ToolPlacement] = [:]
    /// Miejsce narzędzi bez własnego wyboru (domyślnie panel po prawej).
    public var defaultPlacement: ToolPlacement = .right
    /// Panele chowają się, gdy fokus przechodzi do edytora okna; pokazanie narzędzia albo komenda panelu je rozwija.
    public var autoHide = false

    public init() {}

    /// Narzędzia domyślnie w osobnym oknie. `approval` to okno podglądu zgody ze scenariusza zrzutów
    /// (`debug.approval`); w aplikacji zgoda na operację agenta jest arkuszem na oknie głównym, nie narzędziem.
    public static let floatingByDefault: Set<String> = ["approval"]

    /// Przedrostki kluczy jednorazowych (`diff-<UUID>`, `table-APP.T`, `debugger-<id>`): okna dzielą miejsce rodzaju
    /// i nie zapamiętują własnej ramki. Jedyna lista — okno narzędzia rozpoznaje klucz jednorazowy przez `kind(of:)`.
    static let transientPrefixes = ["diff-", "table-", "graph-", "spatial-", "debugger-", "html-", "objectInfo-", "largeData-"]

    /// Rodzaj narzędzia z klucza okna: klucze jednorazowe dzielą miejsce z innymi oknami tego rodzaju; pozostałe klucze
    /// są rodzajem same w sobie (`kind(of:) == key`).
    public static func kind(of key: String) -> String {
        for prefix in transientPrefixes where key.hasPrefix(prefix) {
            return String(prefix.dropLast())
        }
        return key
    }

    /// Miejsce, w którym otwiera się narzędzie: wybór użytkownika, a bez niego miejsce domyślne (`floatingByDefault` — okno).
    public func placement(for key: String) -> ToolPlacement {
        let kind = Self.kind(of: key)
        return placements[kind] ?? standard(for: kind)
    }

    /// Zapamiętuje miejsce rodzaju narzędzia; miejsce równe domyślnemu usuwa wpis (ustawienia bez zbędnych kluczy).
    public mutating func remember(_ placement: ToolPlacement, for key: String) {
        let kind = Self.kind(of: key)
        placements[kind] = placement == standard(for: kind) ? nil : placement
    }

    private func standard(for kind: String) -> ToolPlacement {
        Self.floatingByDefault.contains(kind) ? .floating : defaultPlacement
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Nieznane miejsca (np. z nowszej wersji) pomijamy zamiast odrzucać całe ustawienia.
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .placements)) ?? [:]
        placements = raw.compactMapValues(ToolPlacement.init(rawValue:))
        defaultPlacement = (try? c.decodeIfPresent(String.self, forKey: .defaultPlacement)).flatMap { $0 }.flatMap(ToolPlacement.init(rawValue:)) ?? .right
        autoHide = (try? c.decodeIfPresent(Bool.self, forKey: .autoHide)) ?? false
    }
}
