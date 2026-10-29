import Foundation

/// Rodzaj grupy kart okien (D200).
public enum TabGroupKind: String, Sendable, Hashable, Codable {
    /// Grupa utworzona przez użytkownika (pierwszeństwo przed kaskadą).
    case manual
    /// Okna z plikami otwartego projektu Pelikana.
    case project
    /// Okna z plikami repozytorium gita ze zdalnym repozytorium (repozytorium · gałąź).
    case repository
    /// Okna jednego połączenia (efektywne połączenie okna).
    case connection
    /// Okna bez połączenia (przy grupowaniu po połączeniach).
    case noConnection
    /// Okna jednego rodzaju (gdy wszystkie pozostałe okna używają jednej bazy).
    case windowKind
}

/// Rodzaj okna w grupowaniu po rodzaju (poziom d kaskady): okna SQL, programy, testy, konsole SQL*Plus, inne.
public enum TabGroupWindowKind: String, Sendable, Hashable, CaseIterable {
    case sql, program, test, command, other

    public init(_ kind: DocumentKind) {
        switch kind {
        case .sql: self = .sql
        case .program: self = .program
        case .test: self = .test
        case .command: self = .command
        default: self = .other
        }
    }

    public var displayName: String {
        switch self {
        case .sql: L10n.tr("Okna SQL")
        case .program: L10n.tr("Programy")
        case .test: L10n.tr("Testy")
        case .command: L10n.tr("Konsole SQL*Plus")
        case .other: L10n.tr("Inne okna")
        }
    }
}

/// Repozytorium gita pliku okna (dla grupowania): katalog roboczy, nazwa, gałąź, czy ma zdalne repozytorium.
public struct RepositoryGroupInfo: Sendable, Hashable {
    /// Katalog roboczy (worktree) — różne worktree tego samego repozytorium to różne grupy.
    public var root: String
    /// Nazwa repozytorium (katalog głównego repozytorium, także dla worktree).
    public var name: String
    /// Gałąź (nil — odłączony HEAD).
    public var branch: String?
    public var hasRemote: Bool
    /// Katalog gita worktree (plik HEAD z gałęzią) — odświeżanie gałęzi bez uruchamiania gita.
    public var gitDirectory: String?

    public init(root: String, name: String, branch: String?, hasRemote: Bool, gitDirectory: String? = nil) {
        self.root = root; self.name = name; self.branch = branch; self.hasRemote = hasRemote; self.gitDirectory = gitDirectory
    }
}

/// Grupa ręczna (nazwa nadana przez użytkownika); kolejność tablicy = kolejność utworzenia.
public struct ManualTabGroup: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

/// Grupa kart: identyfikator (stały dla tych samych okien), nazwa i szczegół do kapsułki, okna w kolejności otwarcia.
public struct TabGroup: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: TabGroupKind
    public var name: String
    /// Drugi wiersz kapsułki przed liczbą okien (gałąź, środowisko połączenia, „projekt”); nil — sama liczba okien.
    public var detail: String?
    public var documents: [DocumentID]
    /// Połączenie grupy połączenia (kolor połączenia z palety).
    public var connectionID: UUID?
    /// Grupa ręczna.
    public var manualID: UUID?
    /// Kolor z palety (`TabColorPalette`); nil — neutralny (okna bez połączenia).
    public var colorIndex: Int?

    public init(id: String, kind: TabGroupKind, name: String, detail: String? = nil, documents: [DocumentID] = [],
                connectionID: UUID? = nil, manualID: UUID? = nil, colorIndex: Int? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.detail = detail; self.documents = documents
        self.connectionID = connectionID; self.manualID = manualID; self.colorIndex = colorIndex
    }

    /// Klucz koloru grupy w palecie: grupa połączenia ma kolor połączenia.
    public var colorKey: String? {
        switch kind {
        case .connection: connectionID.map(TabColorPalette.connectionKey)
        case .noConnection: nil
        default: id
        }
    }

    /// Drugi wiersz kapsułki: „szczegół · liczba” albo „N okien” (odmiana liczebnika).
    public var caption: String {
        if let detail { return "\(detail) · \(documents.count)" }
        return TabGrouping.windowCount(documents.count)
    }
}

/// Grupowanie po połączeniu (poziom c) albo po rodzaju okna (poziom d) — z histerezą (D200).
public enum TabGroupingMode: String, Sendable, Hashable {
    case byConnection, byKind
}

/// Okno w danych wejściowych grupowania.
public struct TabGroupItem: Sendable, Hashable {
    public var id: DocumentID
    public var kind: DocumentKind
    /// Pliki okna (ścieżki standaryzowane; okno pary — oba pliki).
    public var files: [String]
    /// Efektywne połączenie okna.
    public var connection: UUID?
    /// Przydział do grupy ręcznej.
    public var manualGroup: UUID?

    public init(id: DocumentID, kind: DocumentKind, files: [String] = [], connection: UUID? = nil, manualGroup: UUID? = nil) {
        self.id = id; self.kind = kind; self.files = files; self.connection = connection; self.manualGroup = manualGroup
    }
}

/// Nazwa połączenia na kapsułce: nazwa i szczegół (środowisko).
public struct TabGroupConnectionLabel: Sendable, Hashable {
    public var name: String
    public var detail: String?
    public init(name: String, detail: String? = nil) { self.name = name; self.detail = detail }
}

/// Dane wejściowe grupowania — bez AppKit i bez gita (repozytoria wstrzyknięte), testowalne także na Linuksie.
public struct TabGroupInput: Sendable {
    public var items: [TabGroupItem]
    public var manualGroups: [ManualTabGroup] = []
    public var projectName: String?
    /// Pliki projektu (ścieżki standaryzowane).
    public var projectFiles: Set<String> = []
    /// Repozytorium pliku (ścieżka standaryzowana → repozytorium); brak wpisu — poza repozytorium albo jeszcze nieznane.
    public var repositories: [String: RepositoryGroupInfo] = [:]
    public var connections: [UUID: TabGroupConnectionLabel] = [:]

    public init(items: [TabGroupItem], manualGroups: [ManualTabGroup] = [], projectName: String? = nil, projectFiles: Set<String> = [],
                repositories: [String: RepositoryGroupInfo] = [:], connections: [UUID: TabGroupConnectionLabel] = [:]) {
        self.items = items; self.manualGroups = manualGroups; self.projectName = projectName; self.projectFiles = projectFiles
        self.repositories = repositories; self.connections = connections
    }
}

/// Kaskada automatycznych grup kart (D200): grupa ręczna → projekt → repozytorium ze zdalnym (repozytorium · gałąź) →
/// połączenie albo — gdy pozostałe okna używają jednej bazy — rodzaj okna.
public enum TabGrouping {
    /// Grupy w stałej kolejności: ręczne (kolejność utworzenia), projekt, repozytoria alfabetycznie, połączenia
    /// alfabetycznie albo rodzaje w stałej kolejności, „Bez połączenia” na końcu. Okna w grupie — w kolejności `items`.
    /// `mode` — tryb poziomu c/d z poprzedniego wyliczenia (histereza), uaktualniany.
    public static func groups(_ input: TabGroupInput, mode: inout TabGroupingMode) -> [TabGroup] {
        var manual: [UUID: TabGroup] = [:]
        var project: TabGroup?
        var repos: [String: TabGroup] = [:]
        var rest: [TabGroupItem] = []
        let manualIDs = Set(input.manualGroups.map(\.id))
        for item in input.items {
            if let g = item.manualGroup, manualIDs.contains(g), let def = input.manualGroups.first(where: { $0.id == g }) {
                manual[g, default: TabGroup(id: "manual:" + g.uuidString, kind: .manual, name: def.name, manualID: g)].documents.append(item.id)
            } else if let name = input.projectName, item.files.contains(where: input.projectFiles.contains) {
                if project == nil { project = TabGroup(id: "project", kind: .project, name: name, detail: L10n.tr("projekt")) }
                project?.documents.append(item.id)
            } else if let repo = item.files.lazy.compactMap({ input.repositories[$0] }).first(where: \.hasRemote) {
                let key = "repo:" + repo.root + "|" + (repo.branch ?? "")
                repos[key, default: TabGroup(id: key, kind: .repository, name: repo.name, detail: repo.branch ?? L10n.tr("(odłączony HEAD)"))]
                    .documents.append(item.id)
            } else {
                rest.append(item)
            }
        }
        var result = input.manualGroups.compactMap { manual[$0.id] }
        if let project { result.append(project) }
        result += repos.values.sorted { order($0.name, $0.detail, $1.name, $1.detail) }
        // Poziom c/d: liczby okien na bazach (okna bez połączenia nie używają bazy).
        var perConnection: [UUID: Int] = [:]
        for item in rest { if let c = item.connection { perConnection[c, default: 0] += 1 } }
        mode = nextMode(mode, counts: Array(perConnection.values))
        switch mode {
        case .byConnection:
            var conns: [UUID: TabGroup] = [:]
            var none: TabGroup?
            for item in rest {
                if let c = item.connection {
                    let label = input.connections[c] ?? TabGroupConnectionLabel(name: L10n.tr("Nieznane połączenie"))
                    conns[c, default: TabGroup(id: "conn:" + c.uuidString, kind: .connection, name: label.name, detail: label.detail, connectionID: c)]
                        .documents.append(item.id)
                } else {
                    if none == nil { none = TabGroup(id: "none", kind: .noConnection, name: L10n.tr("Bez połączenia")) }
                    none?.documents.append(item.id)
                }
            }
            result += conns.values.sorted { order($0.name, $0.connectionID?.uuidString, $1.name, $1.connectionID?.uuidString) }
            if let none { result.append(none) }
        case .byKind:
            var kinds: [TabGroupWindowKind: TabGroup] = [:]
            for item in rest {
                let k = TabGroupWindowKind(item.kind)
                kinds[k, default: TabGroup(id: "kind:" + k.rawValue, kind: .windowKind, name: k.displayName)].documents.append(item.id)
            }
            result += TabGroupWindowKind.allCases.compactMap { kinds[$0] }
        }
        return result
    }

    /// Histereza poziomu c/d: na grupy połączeń, gdy co najmniej dwie bazy mają po więcej niż jednym oknie; z powrotem na
    /// rodzaje okien, gdy zostaje najwyżej jedna baza. Pomiędzy (np. 5 okien jednej bazy i 1 okno drugiej) tryb się
    /// nie zmienia — jedno okno na innej bazie nie przestawia całego paska.
    public static func nextMode(_ current: TabGroupingMode, counts: [Int]) -> TabGroupingMode {
        let sorted = counts.filter { $0 > 0 }.sorted(by: >)
        if sorted.count <= 1 { return .byKind }
        if sorted[1] >= 2 { return .byConnection }
        return current
    }

    private static func order(_ a: String, _ ad: String?, _ b: String, _ bd: String?) -> Bool {
        let c = a.localizedStandardCompare(b)
        if c != .orderedSame { return c == .orderedAscending }
        return (ad ?? "").localizedStandardCompare(bd ?? "") == .orderedAscending
    }

    /// „1 okno”, „2 okna”, „5 okien” — odmiana według reguł języka interfejsu (`L10n.plural`).
    public static func windowCount(_ n: Int) -> String {
        L10n.plural(n, one: L10n.tr("\(n) okno"), few: L10n.tr("\(n) okna"), many: L10n.tr("\(n) okien"))
    }
}

/// Paleta kolorów połączeń i grup (D200): 10 barw rozłożonych po kole barw. Kolor dostaje połączenie (albo grupa) przy
/// pierwszym oknie i trzyma go, dopóki ma okna; zwolniony wraca do puli. Przy więcej niż 10 naraz kolory się powtarzają
/// — wybierany najmniej używany, a z nich nigdy nieużywany, potem najdawniej zwolniony.
public struct TabColorPalette: Sendable, Hashable {
    public static let count = 10
    /// Odcienie (stopnie) w kolejności przydziału — kolejne barwy możliwie od siebie odległe.
    public static let hues: [Double] = [212, 25, 140, 300, 180, 355, 58, 262, 95, 328]

    public static func connectionKey(_ id: UUID) -> String { "conn:" + id.uuidString }

    public private(set) var assigned: [String: Int] = [:]
    /// Chwila zwolnienia koloru (licznik) — najdawniej zwolniony przydzielany pierwszy.
    private var released: [Int: Int] = [:]
    private var tick = 0
    /// Kolory zapamiętane w worksecie — klucz dostaje swój kolor, gdy jest wolny.
    private var preferred: [String: Int] = [:]

    public init() {}

    public func index(for key: String) -> Int? { assigned[key] }

    /// Kolory z workseta (te same kolory po ponownym otwarciu).
    public mutating func prefer(_ colors: [String: Int]) {
        for (k, v) in colors where (0..<Self.count).contains(v) { preferred[k] = v }
    }

    /// Uzgadnia przydział z kluczami, które mają teraz okna (w kolejności pierwszego okna): zwalnia nieobecne,
    /// przydziela nowym. Wywołanie z tym samym zbiorem niczego nie zmienia.
    public mutating func sync(_ keys: [String]) {
        let live = Set(keys)
        for (k, i) in assigned where !live.contains(k) {
            assigned[k] = nil
            tick += 1
            if !assigned.values.contains(i) { released[i] = tick }
        }
        for k in keys where assigned[k] == nil {
            assigned[k] = choose(for: k)
        }
    }

    private func choose(for key: String) -> Int {
        var usage = Array(repeating: 0, count: Self.count)
        for i in assigned.values { usage[i] += 1 }
        let least = usage.min() ?? 0
        if let p = preferred[key], usage[p] == least { return p }
        let candidates = (0..<Self.count).filter { usage[$0] == least }
        // Nigdy nie użyty (i niezarezerwowany w worksecie dla innego połączenia) — pierwszy w kolejności palety.
        let reserved = Set(preferred.filter { $0.key != key && assigned[$0.key] == nil }.values)
        if let fresh = candidates.first(where: { released[$0] == nil && !reserved.contains($0) }) { return fresh }
        if let fresh = candidates.first(where: { released[$0] == nil }) { return fresh }
        return candidates.min { (released[$0] ?? 0, $0) < (released[$1] ?? 0, $1) } ?? 0
    }

    // MARK: Barwy

    /// Odcień tła i akcentu: tło aktywnej karty, tło nieaktywnej (słabsze), akcent (podkreślenie, kapsułka, próbka).
    public enum Shade: Sendable { case activeBackground, inactiveBackground, accent }

    /// Kolor palety w jasnym albo ciemnym wyglądzie; `increasedContrast` — tło jaśniejsze (jasny) / ciemniejsze
    /// (ciemny), akcent ciemniejszy (jasny), żeby tekst i podkreślenie miały większy kontrast.
    public static func color(_ index: Int, shade: Shade, dark: Bool, increasedContrast: Bool = false) -> RGBColor {
        let h = hues[((index % count) + count) % count]
        let (s, b): (Double, Double) = switch (shade, dark) {
        case (.activeBackground, false): increasedContrast ? (0.22, 0.98) : (0.30, 0.96)
        case (.inactiveBackground, false): increasedContrast ? (0.10, 0.99) : (0.14, 0.97)
        case (.accent, false): increasedContrast ? (0.90, 0.62) : (0.85, 0.78)
        case (.activeBackground, true): increasedContrast ? (0.55, 0.28) : (0.55, 0.34)
        case (.inactiveBackground, true): increasedContrast ? (0.40, 0.20) : (0.40, 0.28)
        case (.accent, true): increasedContrast ? (0.55, 1.0) : (0.65, 0.95)
        }
        return hsb(h, s, b)
    }

    /// HSB → RGB (odcień w stopniach).
    public static func hsb(_ hue: Double, _ s: Double, _ v: Double) -> RGBColor {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return RGBColor(red: r + m, green: g + m, blue: b + m)
    }

    /// Względna luminancja WCAG 2.
    public static func luminance(_ c: RGBColor) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.red) + 0.7152 * lin(c.green) + 0.0722 * lin(c.blue)
    }

    /// Współczynnik kontrastu WCAG 2 (1…21).
    public static func contrast(_ a: RGBColor, _ b: RGBColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Kolor `fg` z przezroczystością `alpha` nałożony na `bg`.
    public static func blend(_ fg: RGBColor, alpha: Double, over bg: RGBColor) -> RGBColor {
        RGBColor(red: fg.red * alpha + bg.red * (1 - alpha), green: fg.green * alpha + bg.green * (1 - alpha),
                 blue: fg.blue * alpha + bg.blue * (1 - alpha))
    }
}

/// Przewijanie paska kart przy przepełnieniu (D201): przyciski ‹ ›, kółko myszy i aktywna karta w widoku — obliczenia
/// bez AppKit (przesunięcie = początek widocznego obszaru w treści paska).
public enum TabStripScrolling {
    /// Karty nie mieszczą się w widocznej szerokości.
    public static func overflows(content: Double, visible: Double) -> Bool { content > visible + 0.5 }

    public static func maxOffset(content: Double, visible: Double) -> Double { max(0, content - visible) }

    public static func clamp(_ offset: Double, content: Double, visible: Double) -> Double {
        min(max(0, offset), maxOffset(content: content, visible: visible))
    }

    /// Czy da się przewinąć w danym kierunku (przycisk wyłączony na końcu paska).
    public static func canScroll(offset: Double, content: Double, visible: Double, forward: Bool) -> Bool {
        guard overflows(content: content, visible: visible) else { return false }
        return forward ? offset < maxOffset(content: content, visible: visible) - 0.5 : offset > 0.5
    }

    /// Krok przycisku: ok. 60% widocznej szerokości (kilka kart), najmniej 120 pt.
    public static func step(visible: Double) -> Double { max(120, visible * 0.6) }

    /// Przesunięcie po kliknięciu przycisku ‹ albo ›.
    public static func target(offset: Double, content: Double, visible: Double, forward: Bool) -> Double {
        clamp(offset + (forward ? 1 : -1) * step(visible: visible), content: content, visible: visible)
    }

    /// Przesunięcie po obrocie kółka (pionowy obrót przewija poziomo; dodatnia delta — w lewo, jak w macOS).
    public static func wheel(offset: Double, delta: Double, content: Double, visible: Double) -> Double {
        clamp(offset - delta, content: content, visible: visible)
    }

    /// Przesunięcie, przy którym karta `minX…maxX` jest w całości widoczna (z marginesem); już widoczna — bez zmian.
    public static func reveal(offset: Double, content: Double, visible: Double, minX: Double, maxX: Double, margin: Double = 8) -> Double {
        var o = offset
        if minX - margin < o { o = minX - margin } else if maxX + margin > o + visible { o = maxX + margin - visible }
        return clamp(o, content: content, visible: visible)
    }
}
