import AppKit
import PelikanSQL
import Synchronization

/// Kolory składni (dynamiczne — tryb jasny i ciemny).
enum SyntaxTheme {
    static let keyword = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.99, green: 0.37, blue: 0.64, alpha: 1) : NSColor(srgbRed: 0.61, green: 0.14, blue: 0.58, alpha: 1) }
    static let string = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.99, green: 0.42, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.77, green: 0.10, blue: 0.09, alpha: 1) }
    static let comment = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.42, green: 0.75, blue: 0.40, alpha: 1) : NSColor(srgbRed: 0.18, green: 0.52, blue: 0.20, alpha: 1) }
    static let number = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.85, green: 0.79, blue: 0.49, alpha: 1) : NSColor(srgbRed: 0.11, green: 0.0, blue: 0.81, alpha: 1) }
    static let variable = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.40, green: 0.80, blue: 0.94, alpha: 1) : NSColor(srgbRed: 0.0, green: 0.45, blue: 0.62, alpha: 1) }
    static let quoted = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.85, green: 0.60, blue: 0.95, alpha: 1) : NSColor(srgbRed: 0.42, green: 0.22, blue: 0.62, alpha: 1) }
    static let hint = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.55, green: 0.85, blue: 0.75, alpha: 1) : NSColor(srgbRed: 0.10, green: 0.50, blue: 0.45, alpha: 1) }
    /// Własny kolor zwykłego tekstu edytora z Preferencji (PD-PREF-005); nil — kolor systemu (jasny/ciemny).
    /// Pod blokadą: czyta go dostawca dynamicznego koloru, którego AppKit może wywołać poza głównym wątkiem.
    nonisolated static var customPlain: NSColor? {
        get { customPlainStore.withLock { $0 } }
        set { customPlainStore.withLock { $0 = newValue } }
    }
    private nonisolated static let customPlainStore = Mutex<NSColor?>(nil)
    static let plain = NSColor(name: nil) { _ in customPlain ?? NSColor.textColor }
    static let op = NSColor.secondaryLabelColor

    static func color(for kind: TokenKind) -> NSColor? {
        switch kind {
        case .keyword: keyword
        case .string: string
        case .lineComment, .blockComment: comment
        case .hint: hint
        case .number: number
        case .bindVariable, .substitution, .jasperParameter: variable
        case .quotedIdentifier: quoted
        case .operator, .semicolon, .slash, .comma, .leftParen, .rightParen, .dot: op
        default: nil
        }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Podświetlanie przyrostowe (ADR 0002/0003): logika w `IncrementalLexer` (PelikanSQL, testy wydajności), tu tylko
/// nakładanie kolorów na NSTextStorage.
final class SyntaxHighlighter {
    private let lexer = IncrementalLexer()
    var lineStarts: [Int] { lexer.lineStarts }

    /// Pełne przeliczenie (otwarcie pliku, zmiana całego tekstu).
    func highlightAll(_ storage: NSTextStorage, font: NSFont) {
        let text = Self.utf16(of: storage)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: 0, length: text.count))
        lexer.lexAll(text, onLine: { _ in }, onToken: { Self.color($0, in: storage) })
        Self.overlayJavaScript(text, storage: storage, font: font)
        storage.endEditing()
    }

    /// Ciało modułów MLE kolorowane jako JavaScript (PD-PROG-014) — po kolorach PL/SQL, na całym ciele.
    private static func overlayJavaScript(_ text: [UInt16], storage: NSTextStorage, font: NSFont) {
        for body in JavaScriptLexer.mleBodies(text) {
            storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: body.lowerBound, length: body.count))
            for t in JavaScriptLexer.tokens(text, range: body) { color(t, in: storage) }
        }
    }

    /// Po edycji: `editedRange` (w nowym tekście) i `delta` (zmiana długości).
    func highlight(_ storage: NSTextStorage, editedRange: NSRange, delta: Int, font: NSFont) {
        let text = Self.utf16(of: storage)
        storage.beginEditing()
        lexer.relex(text, editedRange: editedRange.location..<(editedRange.location + editedRange.length), delta: delta,
                    onLine: { storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: $0.lowerBound, length: $0.count)) },
                    onToken: { Self.color($0, in: storage) })
        Self.overlayJavaScript(text, storage: storage, font: font)
        storage.endEditing()
    }

    private static func color(_ token: Token, in storage: NSTextStorage) {
        if let color = SyntaxTheme.color(for: token.kind), color != SyntaxTheme.plain {
            storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: token.start, length: token.length))
        }
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
