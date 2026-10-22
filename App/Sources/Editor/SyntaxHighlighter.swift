import AppKit
import PelikanSQL

/// Kolory składni (dynamiczne — tryb jasny i ciemny).
enum SyntaxTheme {
    static let keyword = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.99, green: 0.37, blue: 0.64, alpha: 1) : NSColor(srgbRed: 0.61, green: 0.14, blue: 0.58, alpha: 1) }
    static let string = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.99, green: 0.42, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.77, green: 0.10, blue: 0.09, alpha: 1) }
    static let comment = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.42, green: 0.75, blue: 0.40, alpha: 1) : NSColor(srgbRed: 0.18, green: 0.52, blue: 0.20, alpha: 1) }
    static let number = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.85, green: 0.79, blue: 0.49, alpha: 1) : NSColor(srgbRed: 0.11, green: 0.0, blue: 0.81, alpha: 1) }
    static let variable = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.40, green: 0.80, blue: 0.94, alpha: 1) : NSColor(srgbRed: 0.0, green: 0.45, blue: 0.62, alpha: 1) }
    static let quoted = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.85, green: 0.60, blue: 0.95, alpha: 1) : NSColor(srgbRed: 0.42, green: 0.22, blue: 0.62, alpha: 1) }
    static let hint = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.55, green: 0.85, blue: 0.75, alpha: 1) : NSColor(srgbRed: 0.10, green: 0.50, blue: 0.45, alpha: 1) }
    static let plain = NSColor.textColor
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

/// Podświetlanie przyrostowe (ADR 0002/0003): stan leksera na początku każdej linii w pamięci podręcznej; po zmianie
/// przeleksowujemy od zmienionej linii do miejsca, w którym stan na początku linii jest taki sam jak poprzednio.
final class SyntaxHighlighter {
    private(set) var lineStarts: [Int] = [0]
    private var startStates: [LexState] = [.normal]

    /// Pełne przeliczenie (otwarcie pliku, zmiana całego tekstu).
    func highlightAll(_ storage: NSTextStorage, font: NSFont) {
        let text = Array(storage.string.utf16)
        lineStarts = Self.computeLineStarts(text)
        startStates = Array(repeating: .normal, count: lineStarts.count)
        let lexer = Lexer(utf16: text)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: 0, length: text.count))
        var state = LexState.normal
        for i in 0..<lineStarts.count {
            startStates[i] = state
            let range = lineStarts[i]..<(i + 1 < lineStarts.count ? lineStarts[i + 1] : text.count)
            state = apply(lexer, range: range, state: state, storage: storage)
        }
        storage.endEditing()
    }

    /// Po edycji: `editedRange` (w nowym tekście) i `delta` (zmiana długości).
    func highlight(_ storage: NSTextStorage, editedRange: NSRange, delta: Int, font: NSFont) {
        let text = Array(storage.string.utf16)
        let oldStates = startStates
        let oldStarts = lineStarts
        lineStarts = Self.computeLineStarts(text)
        // Pierwsza dotknięta linia.
        let firstLine = max(0, line(containing: editedRange.location) )
        // Stany linii przed edycją zostają; od firstLine liczymy na nowo.
        var states = Array(oldStates.prefix(firstLine))
        if states.isEmpty { states = [.normal] }
        var state = firstLine < oldStates.count ? oldStates[firstLine] : .normal
        if firstLine == 0 { state = .normal }
        let lexer = Lexer(utf16: text)
        let editEnd = editedRange.location + editedRange.length
        storage.beginEditing()
        var i = firstLine
        while i < lineStarts.count {
            if i >= states.count { states.append(state) } else { states[i] = state }
            let lineStart = lineStarts[i]
            let range = lineStart..<(i + 1 < lineStarts.count ? lineStarts[i + 1] : text.count)
            storage.setAttributes([.font: font, .foregroundColor: SyntaxTheme.plain], range: NSRange(location: range.lowerBound, length: range.count))
            state = apply(lexer, range: range, state: state, storage: storage)
            // Za edycją: jeśli stan na początku następnej linii zgadza się ze starym — reszta bez zmian.
            if lineStart >= editEnd, i + 1 < lineStarts.count {
                let oldIndex = Self.index(of: lineStarts[i + 1] - delta, in: oldStarts)
                if let oi = oldIndex, oi < oldStates.count, oldStates[oi] == state {
                    states.append(contentsOf: oldStates[oi...].prefix(lineStarts.count - (i + 1)))
                    break
                }
            }
            i += 1
        }
        storage.endEditing()
        startStates = Array(states.prefix(lineStarts.count))
        while startStates.count < lineStarts.count { startStates.append(.normal) }
    }

    private func apply(_ lexer: Lexer, range: Range<Int>, state: LexState, storage: NSTextStorage) -> LexState {
        lexer.scan(range: range, state: state) { token in
            if let color = SyntaxTheme.color(for: token.kind), color != SyntaxTheme.plain {
                storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: token.start, length: token.length))
            }
        }
    }

    /// Numer linii (od 0) dla przesunięcia UTF-16.
    func line(containing offset: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    static func index(of start: Int, in starts: [Int]) -> Int? {
        var lo = 0, hi = starts.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if starts[mid] == start { return mid }
            if starts[mid] < start { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    static func computeLineStarts(_ text: [UInt16]) -> [Int] {
        var starts = [0]
        starts.reserveCapacity(text.count / 30)
        for (i, c) in text.enumerated() where c == 0x0A { starts.append(i + 1) }
        return starts
    }
}
