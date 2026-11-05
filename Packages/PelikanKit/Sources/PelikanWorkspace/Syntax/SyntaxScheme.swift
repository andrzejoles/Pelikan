import Foundation
import PelikanSQL

extension SyntaxStyle {
    /// Nazwa w Ustawieniach.
    public var title: String {
        switch self {
        case .plain: L10n.tr("Zwykły tekst")
        case .keyword: L10n.tr("Słowa kluczowe")
        case .dataType: L10n.tr("Typy danych")
        case .function: L10n.tr("Funkcje wbudowane")
        case .package: L10n.tr("Pakiety dostarczane z bazą")
        case .string: L10n.tr("Napisy")
        case .number: L10n.tr("Liczby")
        case .comment: L10n.tr("Komentarze")
        case .hint: L10n.tr("Wskazówki optymalizatora")
        case .variable: L10n.tr("Zmienne wiązane i podstawienia")
        case .quotedIdentifier: L10n.tr("Nazwy w cudzysłowie")
        case .operator: L10n.tr("Operatory i interpunkcja")
        case .directive: L10n.tr("Dyrektywy kompilacji i preprocesora")
        }
    }
}

/// Barwa sRGB (w JSON jako `#rrggbb`).
public struct RGB: Codable, Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        if h.count == 8 { h = String(h.prefix(6)) }   // #rrggbbaa — bez przezroczystości
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    public init(red: Double, green: Double, blue: Double) {
        func c(_ x: Double) -> UInt8 { UInt8((min(max(x, 0), 1) * 255).rounded()) }
        self.init(c(red), c(green), c(blue))
    }

    public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }
    public var components: (red: Double, green: Double, blue: Double) { (Double(r) / 255, Double(g) / 255, Double(b) / 255) }

    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let v = RGB(hex: s) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "kolor \(s)")) }
        self = v
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }

    /// Luminancja względna (WCAG 2).
    public var luminance: Double {
        func f(_ c: UInt8) -> Double { let x = Double(c) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }

    /// Kontrast WCAG z drugą barwą (1…21).
    public func contrast(with o: RGB) -> Double {
        let a = luminance, b = o.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public func mixed(with o: RGB, _ t: Double) -> RGB {
        let a = components, b = o.components
        return RGB(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t, blue: a.blue + (b.blue - a.blue) * t)
    }

    /// Najmniejsze przesunięcie w stronę `toward` (zwykle koloru tekstu), przy którym kontrast z tłem osiąga `minimum`.
    public func ensuringContrast(_ minimum: Double, on background: RGB, toward: RGB) -> RGB {
        guard contrast(with: background) < minimum else { return self }
        let target = toward.contrast(with: background) >= minimum ? toward : (background.luminance < 0.5 ? RGB(255, 255, 255) : RGB(0, 0, 0))
        var lo = 0.0, hi = 1.0
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if mixed(with: target, mid).contrast(with: background) >= minimum { hi = mid } else { lo = mid }
        }
        return mixed(with: target, hi)
    }
}

/// Styl kategorii: kolor (nil — kolor zwykłego tekstu), pogrubienie, kursywa.
public struct TokenStyle: Codable, Hashable, Sendable {
    public var color: RGB?
    public var bold: Bool
    public var italic: Bool

    public init(_ color: RGB?, bold: Bool = false, italic: Bool = false) { self.color = color; self.bold = bold; self.italic = italic }

    enum CodingKeys: String, CodingKey { case color, bold, italic }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(RGB.self, forKey: .color)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
    }
}

/// Motyw kolorowania składni (D227): kolory edytora i style kategorii. Kolor nil — kolor systemu (tryb jasny/ciemny);
/// tak jest zbudowany domyślny motyw Pelikana. Wbudowane (`builtin.…`) są tylko do odczytu — zmiany zapisuje się jako
/// własny motyw.
public struct SyntaxScheme: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var author: String
    /// Źródło (np. „tinted-theming base16”, „Xcode”, „Visual Studio Code”); puste — utworzony w Pelikanie.
    public var source: String
    public var isDark: Bool
    public var background: RGB?
    public var text: RGB?
    public var selection: RGB?
    public var currentLine: RGB?
    public var lineNumber: RGB?
    public var cursor: RGB?
    public var styles: [SyntaxStyle: TokenStyle]

    public init(id: String, name: String, author: String = "", source: String = "", isDark: Bool,
                background: RGB? = nil, text: RGB? = nil, selection: RGB? = nil, currentLine: RGB? = nil,
                lineNumber: RGB? = nil, cursor: RGB? = nil, styles: [SyntaxStyle: TokenStyle] = [:]) {
        self.id = id; self.name = name; self.author = author; self.source = source; self.isDark = isDark
        self.background = background; self.text = text; self.selection = selection; self.currentLine = currentLine
        self.lineNumber = lineNumber; self.cursor = cursor; self.styles = styles
    }

    public static let builtinPrefix = "builtin."
    public var isBuiltin: Bool { id.hasPrefix(Self.builtinPrefix) }

    /// Styl kategorii; brak wpisu — zwykły tekst.
    public func style(_ s: SyntaxStyle) -> TokenStyle { styles[s] ?? styles[.plain] ?? TokenStyle(nil) }

    enum CodingKeys: String, CodingKey { case id, name, author, source, isDark, background, text, selection, currentLine, lineNumber, cursor, styles }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        isDark = try c.decodeIfPresent(Bool.self, forKey: .isDark) ?? false
        background = try c.decodeIfPresent(RGB.self, forKey: .background)
        text = try c.decodeIfPresent(RGB.self, forKey: .text)
        selection = try c.decodeIfPresent(RGB.self, forKey: .selection)
        currentLine = try c.decodeIfPresent(RGB.self, forKey: .currentLine)
        lineNumber = try c.decodeIfPresent(RGB.self, forKey: .lineNumber)
        cursor = try c.decodeIfPresent(RGB.self, forKey: .cursor)
        // Słownik z kluczami-nazwami kategorii; nieznane kategorie (z nowszej wersji) pomijane.
        let raw = try c.decodeIfPresent([String: TokenStyle].self, forKey: .styles) ?? [:]
        styles = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in SyntaxStyle(rawValue: k).map { ($0, v) } })
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(author, forKey: .author)
        try c.encode(source, forKey: .source)
        try c.encode(isDark, forKey: .isDark)
        try c.encodeIfPresent(background, forKey: .background)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(selection, forKey: .selection)
        try c.encodeIfPresent(currentLine, forKey: .currentLine)
        try c.encodeIfPresent(lineNumber, forKey: .lineNumber)
        try c.encodeIfPresent(cursor, forKey: .cursor)
        try c.encode(Dictionary(uniqueKeysWithValues: styles.map { ($0.key.rawValue, $0.value) }), forKey: .styles)
    }

    /// Kopia do edycji (własny motyw): nowy identyfikator, nazwa, bez źródła wbudowanego.
    public func copy(named newName: String) -> SyntaxScheme {
        var s = self
        s.id = "user." + UUID().uuidString.lowercased()
        s.name = newName
        if isBuiltin, s.source.isEmpty { s.source = "Pelikan" }
        return s
    }

    // MARK: - base16

    struct Base16Entry: Sendable {
        let id: String, name: String, author: String, dark: Bool, palette: String
    }

    static func B(_ id: String, _ name: String, _ author: String, _ dark: Bool, _ palette: String) -> Base16Entry {
        Base16Entry(id: id, name: name, author: author, dark: dark, palette: palette)
    }

    /// Najmniejszy kontrast z tłem: tekst 4,5:1 (WCAG AA), kategorie i numery linii 3:1. Palety, które go nie
    /// osiągają (często przygaszone komentarze), są rozjaśniane/przyciemniane w stronę koloru tekstu.
    public static let minimumTextContrast = 4.5
    public static let minimumTokenContrast = 3.0

    /// Motyw z palety base16 (base00…base0F) według zaleceń stylu base16: tło 00, zaznaczenie 02, komentarze 03,
    /// tekst 05; zmienne 08, liczby 09, typy 0A, napisy 0B, biblioteki („support”) 0C, funkcje 0D, słowa kluczowe 0E,
    /// osadzone dyrektywy 0F.
    public static func base16(id: String, name: String, author: String, source: String, dark: Bool, palette: [RGB]) -> SyntaxScheme? {
        guard palette.count >= 16 else { return nil }
        let bg = palette[0]
        var fg = palette[5]
        if fg.contrast(with: bg) < minimumTextContrast { fg = fg.ensuringContrast(minimumTextContrast, on: bg, toward: palette[7]) }
        func c(_ i: Int) -> RGB { palette[i].ensuringContrast(minimumTokenContrast, on: bg, toward: fg) }
        let styles: [SyntaxStyle: TokenStyle] = [
            .plain: TokenStyle(fg), .keyword: TokenStyle(c(14)), .dataType: TokenStyle(c(10)), .function: TokenStyle(c(13)),
            .package: TokenStyle(c(12)), .string: TokenStyle(c(11)), .number: TokenStyle(c(9)), .comment: TokenStyle(c(3), italic: true),
            .hint: TokenStyle(c(15), italic: true), .variable: TokenStyle(c(8)), .quotedIdentifier: TokenStyle(c(12)),
            .operator: TokenStyle(fg), .directive: TokenStyle(c(15)),
        ]
        return SyntaxScheme(id: id, name: name, author: author, source: source, isDark: dark, background: bg, text: fg,
                            selection: palette[2], currentLine: palette[1], lineNumber: c(4), cursor: fg, styles: styles)
    }

    // MARK: - Wbudowane

    /// Domyślny motyw Pelikana (kolory sprzed D227): tło i tekst systemu, kategorie jak dotąd.
    public static let pelikanLight = SyntaxScheme(
        id: builtinPrefix + "pelikan-light", name: "Pelikan", author: "Pelikan", isDark: false,
        styles: pelikanStyles(keyword: "9b2494", string: "c41a16", comment: "2e8533", number: "1c00cf", variable: "00739e",
                              quoted: "6b389e", hint: "1a8073", op: "6e6e73"))
    public static let pelikanDark = SyntaxScheme(
        id: builtinPrefix + "pelikan-dark", name: "Pelikan", author: "Pelikan", isDark: true,
        styles: pelikanStyles(keyword: "fc5fa3", string: "fc6a5d", comment: "6bbf66", number: "d9c97c", variable: "66ccf0",
                              quoted: "d999f2", hint: "8cd9bf", op: "a1a1a6"))

    static func pelikanStyles(keyword: String, string: String, comment: String, number: String, variable: String,
                              quoted: String, hint: String, op: String) -> [SyntaxStyle: TokenStyle] {
        func s(_ h: String) -> TokenStyle { TokenStyle(RGB(hex: h)) }
        // Typy danych i dyrektywy jak słowa kluczowe, funkcje i pakiety jak zwykły tekst — wygląd sprzed D227.
        return [.plain: TokenStyle(nil), .keyword: s(keyword), .dataType: s(keyword), .directive: s(keyword),
                .function: TokenStyle(nil), .package: TokenStyle(nil), .string: s(string), .comment: s(comment),
                .number: s(number), .variable: s(variable), .quotedIdentifier: s(quoted), .hint: s(hint), .operator: s(op)]
    }

    /// Klasyczny jasny motyw narzędzi Oracle z lat 2000: granatowe słowa kluczowe, czerwone napisy, zielone komentarze
    /// kursywą, białe tło.
    public static let classic: SyntaxScheme = {
        func s(_ h: String, bold: Bool = false, italic: Bool = false) -> TokenStyle { TokenStyle(RGB(hex: h), bold: bold, italic: italic) }
        return SyntaxScheme(
            id: builtinPrefix + "classic", name: L10n.tr("Klasyczny"), author: "Pelikan", isDark: false,
            background: RGB(255, 255, 255), text: RGB(0, 0, 0), selection: RGB(hex: "c5d9f1"), currentLine: RGB(hex: "f2f6fc"),
            lineNumber: RGB(hex: "767676"), cursor: RGB(0, 0, 0),
            styles: [.plain: s("000000"), .keyword: s("00008b", bold: true), .dataType: s("00008b"), .function: s("8b008b"),
                     .package: s("8b4513"), .string: s("b22222"), .number: s("b22222"), .comment: s("008000", italic: true),
                     .hint: s("008080", italic: true), .variable: s("a0522d"), .quotedIdentifier: s("000000"),
                     .operator: s("000080"), .directive: s("800080")])
    }()

    /// Wszystkie wbudowane motywy: Pelikan, Klasyczny i palety base16/base24 z tinted-theming (D227).
    public static let builtin: [SyntaxScheme] = {
        [pelikanLight, pelikanDark, classic] + base16Builtin.compactMap { e in
            base16(id: builtinPrefix + e.id, name: e.name, author: e.author, source: "tinted-theming", dark: e.dark,
                   palette: e.palette.split(separator: " ").compactMap { RGB(hex: String($0)) })
        }
    }()

    public static func builtin(_ id: String) -> SyntaxScheme? { builtin.first { $0.id == id } }
}
