import AppKit
import PelikanSQL
import PelikanWorkspace
import Synchronization

/// Kolory składni z motywów (D227): motyw dla trybu jasnego i ciemnego (Ustawienia › Kolory), kolory dynamiczne —
/// zmiana trybu systemu nie wymaga ponownego kolorowania, tylko pogrubienie i kursywa (krój) zależą od motywu.
enum SyntaxTheme {
    struct Schemes: Sendable {
        var light: SyntaxScheme = .pelikanLight
        var dark: SyntaxScheme = .pelikanDark
    }

    /// Pod blokadą: czyta je dostawca dynamicznego koloru, którego AppKit może wywołać poza głównym wątkiem.
    private nonisolated static let store = Mutex(Schemes())
    private nonisolated static let customPlainStore = Mutex<NSColor?>(nil)

    nonisolated static var schemes: Schemes {
        get { store.withLock { $0 } }
        set { store.withLock { $0 = newValue } }
    }

    /// Własny kolor zwykłego tekstu edytora z Preferencji (PD-PREF-005) — ma pierwszeństwo przed motywem.
    nonisolated static var customPlain: NSColor? {
        get { customPlainStore.withLock { $0 } }
        set { customPlainStore.withLock { $0 = newValue } }
    }

    nonisolated static func scheme(for appearance: NSAppearance) -> SyntaxScheme {
        let s = schemes
        return appearance.isDark ? s.dark : s.light
    }

    /// Motyw trybu, w którym aplikacja jest teraz wyświetlana.
    @MainActor static var current: SyntaxScheme { scheme(for: NSApp.effectiveAppearance) }

    nonisolated static func ns(_ c: RGB) -> NSColor { NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1) }

    /// Ustawienia → motywy i odświeżenie (zwraca true, gdy coś się zmieniło).
    @MainActor @discardableResult
    static func apply(_ settings: PelikanWorkspace.Settings) -> Bool {
        let new = Schemes(light: settings.activeSyntaxScheme(dark: false), dark: settings.activeSyntaxScheme(dark: true))
        let old = schemes
        guard old.light != new.light || old.dark != new.dark else { return false }
        schemes = new
        return true
    }

    private nonisolated static func resolve(_ style: SyntaxStyle, _ ap: NSAppearance) -> NSColor {
        let s = scheme(for: ap)
        if style == .plain { return customPlain ?? s.style(.plain).color.map(ns) ?? s.text.map(ns) ?? .textColor }
        if let c = s.style(style).color { return ns(c) }
        if style == .operator, s.text == nil { return .secondaryLabelColor }
        return resolve(.plain, ap)
    }

    nonisolated static let colors: [SyntaxStyle: NSColor] = Dictionary(uniqueKeysWithValues: SyntaxStyle.allCases.map { style in
        (style, NSColor(name: nil) { resolve(style, $0) })
    })

    static let plain = colors[.plain]!
    static let op = colors[.operator]!
    /// Kolory edytora z motywu; brak w motywie — kolory systemu.
    static let background = NSColor(name: nil) { scheme(for: $0).background.map(ns) ?? .textBackgroundColor }
    static let selection = NSColor(name: nil) { scheme(for: $0).selection.map(ns) ?? .selectedTextBackgroundColor }
    static let cursor = NSColor(name: nil) { customPlain ?? scheme(for: $0).cursor.map(ns) ?? .textColor }
    static let lineNumber = NSColor(name: nil) { scheme(for: $0).lineNumber.map(ns) ?? .tertiaryLabelColor }
    static let lineNumberCurrent = NSColor(name: nil) { ap in scheme(for: ap).text.map(ns) ?? .labelColor }
    static let currentLine = NSColor(name: nil) { ap in
        if let c = scheme(for: ap).currentLine { return ns(c) }
        return ap.isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(srgbRed: 0.95, green: 0.97, blue: 1, alpha: 1)
    }
    /// Czy motyw ma własne tło (wtedy edytor nie używa koloru tła systemu).
    @MainActor static var hasBackground: Bool { schemes.light.background != nil || schemes.dark.background != nil }

    static func color(for style: SyntaxStyle) -> NSColor { colors[style]! }

    /// Kolor tokenu leksera SQL bez kontekstu (podglądy formatera).
    static func color(for kind: TokenKind) -> NSColor? {
        switch kind {
        case .keyword: colors[.keyword]
        case .directive: colors[.directive]
        case .string: colors[.string]
        case .lineComment, .blockComment: colors[.comment]
        case .hint: colors[.hint]
        case .number: colors[.number]
        case .bindVariable, .substitution, .jasperParameter: colors[.variable]
        case .quotedIdentifier: colors[.quotedIdentifier]
        case .operator, .semicolon, .slash, .comma, .leftParen, .rightParen, .dot: colors[.operator]
        default: nil
        }
    }

    /// Kroje motywu (pogrubienie, kursywa kategorii) — ich zmiana wymaga ponownego kolorowania, zmiana koloru nie.
    nonisolated static func fontSignature(_ s: SyntaxScheme) -> String {
        SyntaxStyle.allCases.map { st in let t = s.style(st); return "\(t.bold ? 1 : 0)\(t.italic ? 1 : 0)" }.joined()
    }

    /// Krój z pogrubieniem/kursywą stylu w motywie bieżącego trybu (nil — bez zmiany kroju).
    @MainActor static func font(for style: SyntaxStyle, base: NSFont) -> NSFont? {
        let t = current.style(style)
        guard t.bold || t.italic else { return nil }
        var f = base
        if t.bold { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
        if t.italic {
            let it = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
            // Krój bez kursywy (SF Mono ma, Menlo ma; część krojów nie) — pochylenie macierzą.
            f = NSFontManager.shared.traits(of: it).contains(.italicFontMask) ? it
                : (NSFont(descriptor: f.fontDescriptor.withMatrix(AffineTransform(m11: 1, m12: 0, m21: 0.2, m22: 1, tX: 0, tY: 0)), size: f.pointSize) ?? f)
        }
        return f
    }
}

extension NSAppearance {
    nonisolated var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Podświetlanie przyrostowe (ADR 0002/0003): logika w `IncrementalLexer` (PelikanSQL, testy wydajności), tu tylko
/// nakładanie kolorów na NSTextStorage. Pliki Pro*C (D227): kolory z `ProCLexer` na całym tekście.
@MainActor
final class SyntaxHighlighter {
    private let lexer = IncrementalLexer()
    var lineStarts: [Int] { lexer.lineStarts }
    /// Tekst C z wstawkami EXEC SQL (pliki .pc, .c, .h).
    var proC = false
    private var fonts: [SyntaxStyle: NSFont] = [:]
    private var fontsBase: NSFont?
    private var fontsScheme: String?

    /// Bufor krojów odświeżany raz na kolorowanie (nie przy każdym tokenie): klucz — motyw i jego kroje.
    private func refreshFonts(_ base: NSFont) {
        let cur = SyntaxTheme.current
        let key = cur.id + "|" + SyntaxTheme.fontSignature(cur)
        guard fontsBase != base || fontsScheme != key else { return }
        fonts = [:]
        fontsBase = base
        fontsScheme = key
        for s in SyntaxStyle.allCases { if let f = SyntaxTheme.font(for: s, base: base) { fonts[s] = f } }
    }

    /// Pełne przeliczenie (otwarcie pliku, zmiana całego tekstu albo motywu).
    func highlightAll(_ storage: NSTextStorage, font: NSFont) {
        refreshFonts(font)
        let text = Self.utf16(of: storage)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: 0, length: text.count))
        if proC {
            lexer.lexAll(text, onLine: { _ in }, onToken: { _ in })
            applyProC(text, storage: storage, font: font)
        } else {
            lexer.lexAll(text, onLine: { _ in }, onToken: { self.color($0, text, in: storage, font: font) })
            overlayJavaScript(text, storage: storage, font: font)
        }
        storage.endEditing()
    }

    /// Ciało modułów MLE kolorowane jako JavaScript (PD-PROG-014) — po kolorach PL/SQL, na całym ciele.
    private func overlayJavaScript(_ text: [UInt16], storage: NSTextStorage, font: NSFont) {
        for body in JavaScriptLexer.mleBodies(text) {
            storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: body.lowerBound, length: body.count))
            for t in JavaScriptLexer.tokens(text, range: body) { color(t, text, in: storage, font: font) }
        }
    }

    private func applyProC(_ text: [UInt16], storage: NSTextStorage, font: NSFont) {
        // Jak przy edycji linii SQL: atrybuty od nowa (także podkreślenia — analiza po zmianie nakłada je ponownie).
        storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: 0, length: text.count))
        for s in ProCLexer.spans(text) { apply(s.style, NSRange(location: s.start, length: s.length), in: storage, font: font) }
    }

    /// Po edycji: `editedRange` (w nowym tekście) i `delta` (zmiana długości).
    func highlight(_ storage: NSTextStorage, editedRange: NSRange, delta: Int, font: NSFont) {
        refreshFonts(font)
        let text = Self.utf16(of: storage)
        storage.beginEditing()
        if proC {
            lexer.relex(text, editedRange: editedRange.location..<(editedRange.location + editedRange.length), delta: delta,
                        onLine: { _ in }, onToken: { _ in })
            applyProC(text, storage: storage, font: font)
        } else {
            lexer.relex(text, editedRange: editedRange.location..<(editedRange.location + editedRange.length), delta: delta,
                        onLine: { storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: $0.lowerBound, length: $0.count)) },
                        onToken: { self.color($0, text, in: storage, font: font) })
            overlayJavaScript(text, storage: storage, font: font)
        }
        storage.endEditing()
    }

    private func color(_ token: Token, _ text: [UInt16], in storage: NSTextStorage, font: NSFont) {
        guard let style = SyntaxClassifier.style(token, in: text) else { return }
        apply(style, NSRange(location: token.start, length: token.length), in: storage, font: font)
    }

    private func apply(_ style: SyntaxStyle, _ range: NSRange, in storage: NSTextStorage, font: NSFont) {
        if style != .plain { storage.addAttribute(.foregroundColor, value: SyntaxTheme.color(for: style), range: range) }
        if let f = fonts[style] { storage.addAttribute(.font, value: f, range: range) }
    }

    /// Bufor UTF-16 tekstu (getCharacters = kopia pamięci, bez iterowania po znakach mostkowanego NSString).
    static func utf16(of storage: NSTextStorage) -> [UInt16] {
        let ns = storage.string as NSString
        let n = ns.length
        return [UInt16](unsafeUninitializedCapacity: n) { buf, count in
            if let base = buf.baseAddress { ns.getCharacters(base, range: NSRange(location: 0, length: n)) }
            count = n
        }
    }

    /// Numer linii (od 0) dla przesunięcia UTF-16.
    func line(containing offset: Int) -> Int { lexer.line(containing: offset) }
}
