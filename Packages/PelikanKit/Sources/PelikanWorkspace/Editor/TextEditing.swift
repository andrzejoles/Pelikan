import Foundation
import PelikanSQL

/// Wynik operacji na tekście edytora: nowy tekst i zaznaczenie (UTF-16).
public struct TextEdit: Sendable, Equatable {
    public var text: String
    public var selection: Range<Int>
    public init(text: String, selection: Range<Int>) { self.text = text; self.selection = selection }
}

/// Numery linii dla kolejnych (rosnących) pozycji jednym przejściem po tekście — zamiast liczenia od początku tekstu
/// dla każdej pozycji osobno.
struct LineCounter {
    let ns: NSString
    private var position = 0
    private var line = 1

    init(_ ns: NSString) { self.ns = ns }

    /// Linia (od 1) pozycji UTF-16; pozycja wcześniejsza niż poprzednia liczy od początku.
    mutating func line(at offset: Int) -> Int {
        let end = min(max(offset, 0), ns.length)
        if end < position { position = 0; line = 1 }
        guard position < end else { return line }
        var buffer = [unichar](repeating: 0, count: min(4096, end - position))
        while position < end {
            let n = min(buffer.count, end - position)
            ns.getCharacters(&buffer, range: NSRange(location: position, length: n))
            for i in 0..<n where buffer[i] == 0x0A { line += 1 }
            position += n
        }
        return line
    }
}

/// Funkcje zaznaczenia edytora (UG 25.1, NF15): komentarz linii, wcięcia, wielkość liter bez literałów,
/// usuwanie końcowych spacji, powielenie linii, przejście do linii. Czyste funkcje na tekście (bez AppKit).
public enum TextEditing {
    /// Zakres pełnych linii obejmujących zaznaczenie (UTF-16; bez końcowego znaku nowej linii ostatniej linii).
    static func lineRange(_ ns: NSString, _ sel: Range<Int>) -> NSRange {
        var r = NSRange(location: sel.lowerBound, length: sel.count)
        // Zaznaczenie kończące się na początku linii nie obejmuje tej linii.
        if r.length > 0, r.location + r.length <= ns.length, r.location + r.length > 0,
           ns.character(at: r.location + r.length - 1) == 0x0A { r.length -= 1 }
        var lines = ns.lineRange(for: r)
        if lines.length > 0, lines.location + lines.length <= ns.length, ns.character(at: lines.location + lines.length - 1) == 0x0A {
            lines.length -= 1
        }
        return lines
    }

    static func apply(_ text: String, lines: NSRange, transform: ([String]) -> [String]) -> TextEdit {
        let ns = text as NSString
        let block = ns.substring(with: lines)
        let out = transform(block.components(separatedBy: "\n")).joined(separator: "\n")
        let newText = ns.replacingCharacters(in: lines, with: out)
        return TextEdit(text: newText, selection: lines.location..<(lines.location + (out as NSString).length))
    }

    /// Komentarz linii (Ctrl+−): wszystkie niepuste linie zakomentowane → usuń `--`, w przeciwnym razie dodaj.
    public static func toggleLineComment(_ text: String, selection: Range<Int>) -> TextEdit {
        let lines = lineRange(text as NSString, selection)
        return apply(text, lines: lines) { ls in
            let nonEmpty = ls.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
            if allCommented {
                return ls.map { l in
                    guard let r = l.range(of: "--") else { return l }
                    var s = l
                    s.removeSubrange(r)
                    if s[r.lowerBound...].hasPrefix(" ") { s.remove(at: r.lowerBound) }
                    return s
                }
            }
            // Komentarz na wspólnym wcięciu (jak w edytorze wzorca: kolumna najmniej wciętej linii).
            let indent = nonEmpty.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
            return ls.map { l in
                l.trimmingCharacters(in: .whitespaces).isEmpty ? l : String(l.prefix(indent)) + "-- " + String(l.dropFirst(indent))
            }
        }
    }

    /// Wcięcie (Tab) i cofnięcie wcięcia (Shift+Tab) zaznaczonych linii.
    public static func indent(_ text: String, selection: Range<Int>, unit: String = "  ", tabWidth: Int = 4, outdent: Bool = false) -> TextEdit {
        // Linia wcięta spacjami traci najwyżej jedną jednostkę wcięcia (tabulator = tabWidth spacji).
        let spaces = unit == "\t" ? tabWidth : max(1, unit.count)
        return apply(text, lines: lineRange(text as NSString, selection)) { ls in
            ls.map { l in
                if !outdent { return l.isEmpty ? l : unit + l }
                if l.hasPrefix(unit) { return String(l.dropFirst(unit.count)) }
                if l.hasPrefix("\t") { return String(l.dropFirst()) }
                return String(l.dropFirst(min(spaces, l.prefix { $0 == " " }.count)))
            }
        }
    }

    /// Usuwa końcowe spacje i tabulacje (zaznaczone linie albo cały tekst przy pustym zaznaczeniu).
    public static func removeTrailingSpaces(_ text: String, selection: Range<Int>) -> TextEdit {
        let ns = text as NSString
        let lines = selection.isEmpty ? NSRange(location: 0, length: ns.length) : lineRange(ns, selection)
        var e = apply(text, lines: lines) { ls in ls.map { l in var s = l; while s.last == " " || s.last == "\t" { s.removeLast() }; return s } }
        if selection.isEmpty { e.selection = min(selection.lowerBound, (e.text as NSString).length)..<min(selection.lowerBound, (e.text as NSString).length) }
        return e
    }

    /// Wielkie/małe litery z pominięciem literałów tekstowych i identyfikatorów w cudzysłowie (UG 25.1).
    public static func changeCase(_ text: String, selection: Range<Int>, upper: Bool) -> TextEdit {
        let ns = text as NSString
        let range = selection.isEmpty ? lineRange(ns, selection) : NSRange(location: selection.lowerBound, length: selection.count)
        // Lekser na całym tekście: zaznaczenie zaczęte w środku literału nie odwraca literału i kodu.
        let end = NSMaxRange(range)
        var out = ""
        var pos = range.location
        for t in Lexer(text).tokenize() where t.start + t.length > range.location && t.start < end {
            let a = max(t.start, range.location), b = min(t.start + t.length, end)
            if a > pos { out += ns.substring(with: NSRange(location: pos, length: a - pos)) }
            let s = ns.substring(with: NSRange(location: a, length: b - a))
            switch t.kind {
            case .string, .quotedIdentifier: out += s
            default: out += upper ? s.uppercased() : s.lowercased()
            }
            pos = b
        }
        if pos < end { out += ns.substring(with: NSRange(location: pos, length: end - pos)) }
        let newText = ns.replacingCharacters(in: range, with: out)
        return TextEdit(text: newText, selection: range.location..<(range.location + (out as NSString).length))
    }

    /// Powiela bieżącą linię (albo zaznaczone linie) pod nią; kursor w kopii.
    public static func duplicateLines(_ text: String, selection: Range<Int>) -> TextEdit {
        let ns = text as NSString
        let lines = lineRange(ns, selection)
        let block = ns.substring(with: lines)
        let insertAt = lines.location + lines.length
        let newText = ns.replacingCharacters(in: NSRange(location: insertAt, length: 0), with: "\n" + block)
        let shift = (block as NSString).length + 1
        return TextEdit(text: newText, selection: (selection.lowerBound + shift)..<(selection.upperBound + shift))
    }

    /// Usuwa od kursora do końca następnego słowa (PD-EDIT-020, „Delete next word”): najpierw odstępy, potem znaki
    /// słowa (litery, cyfry, `_ $ #`) albo jeden znak interpunkcji. Zaznaczenie — usuwane w całości.
    public static func deleteNextWord(_ text: String, selection: Range<Int>) -> TextEdit {
        let ns = text as NSString
        if !selection.isEmpty {
            return TextEdit(text: ns.replacingCharacters(in: NSRange(location: selection.lowerBound, length: selection.count), with: ""),
                            selection: selection.lowerBound..<selection.lowerBound)
        }
        func isWord(_ c: unichar) -> Bool {
            guard let s = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(s) || c == 0x5F || c == 0x24 || c == 0x23
        }
        var end = selection.lowerBound
        while end < ns.length, ns.character(at: end) == 0x20 || ns.character(at: end) == 0x09 { end += 1 }
        if end < ns.length, ns.character(at: end) == 0x0A { end += 1 } else if end < ns.length, isWord(ns.character(at: end)) {
            while end < ns.length, isWord(ns.character(at: end)) { end += 1 }
        } else if end < ns.length {
            end += 1
        }
        let start = selection.lowerBound
        return TextEdit(text: ns.replacingCharacters(in: NSRange(location: start, length: end - start), with: ""), selection: start..<start)
    }

    /// Pierwszy znak w linii (PD-EDIT-020, „First Character on Line”): kursor na pierwszy niebiały znak linii, a gdy
    /// już tam jest — na początek linii (przełączanie jak Home w edytorze wzorca).
    public static func firstCharacterOnLine(_ text: String, selection: Range<Int>) -> TextEdit {
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: min(selection.lowerBound, ns.length), length: 0))
        var first = line.location
        while first < line.location + line.length, ns.character(at: first) == 0x20 || ns.character(at: first) == 0x09 { first += 1 }
        if first < ns.length, ns.character(at: first) == 0x0A || first == line.location + line.length { first = line.location }
        let target = selection.lowerBound == first ? line.location : first
        return TextEdit(text: text, selection: target..<target)
    }

    /// Identyfikator z kropkami (schemat.pakiet.element) obejmujący pozycję, bez cudzysłowów.
    public static func identifier(at offset: Int, in text: String) -> String? {
        BuiltinCommands.identifier(at: offset, in: text)?.0
    }

    /// Numer linii (od 0) zawierającej pozycję.
    public static func line(containing offset: Int, in text: String) -> Int {
        let ns = text as NSString
        var line = 0
        for i in 0..<min(offset, ns.length) where ns.character(at: i) == 0x0A { line += 1 }
        return line
    }

    /// Początek linii `line` (od 1); poza zakresem — ostatnia linia.
    public static func offset(ofLine line: Int, in text: String) -> Int {
        let ns = text as NSString
        var current = 1
        var i = 0
        while current < line, i < ns.length {
            if ns.character(at: i) == 0x0A { current += 1 }
            i += 1
        }
        if current < line {
            // Za końcem — początek ostatniej linii.
            return ns.lineRange(for: NSRange(location: ns.length, length: 0)).location
        }
        return i
    }
}

/// Znajdź i zamień (UG 25.3): tekst albo wyrażenie regularne (z `$1`, `\t`, `\n` w zamianie), całe słowa, wielkość liter,
/// zachowanie wielkości liter przy zamianie, zakres (całość/zaznaczenie), przeszukiwanie kodu / komentarzy / literałów.
public struct TextSearch: Sendable, Equatable {
    public var pattern: String
    public var replacement = ""
    public var regex = false
    public var wholeWords = false
    public var caseSensitive = false
    public var preserveCase = false
    public var inCode = true
    public var inComments = true
    public var inStrings = true

    public init(pattern: String) { self.pattern = pattern }

    func expression() throws -> NSRegularExpression {
        var p = regex ? pattern : NSRegularExpression.escapedPattern(for: pattern)
        if wholeWords { p = "(?<![\\p{L}\\p{N}_$#])(?:" + p + ")(?![\\p{L}\\p{N}_$#])" }
        return try NSRegularExpression(pattern: p, options: caseSensitive ? [] : [.caseInsensitive])
    }

    /// Czy dopasowanie leży w dozwolonym rodzaju tekstu (kod / komentarz / literał).
    func allowed(_ r: NSRange, kinds: [(NSRange, TokenKind)]) -> Bool {
        if inCode && inComments && inStrings { return true }
        // Tokeny leksera są posortowane i rozłączne — wyszukiwanie binarne ostatniego zaczynającego się przed dopasowaniem.
        var lo = 0, hi = kinds.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if kinds[mid].0.location <= r.location { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0, NSLocationInRange(r.location, kinds[lo - 1].0) else { return inCode }
        switch kinds[lo - 1].1 {
        case .lineComment, .blockComment, .hint: return inComments
        case .string: return inStrings
        default: return inCode
        }
    }

    static func tokenKinds(_ text: String) -> [(NSRange, TokenKind)] {
        Lexer(text).tokenize().map { (NSRange(location: $0.start, length: $0.length), $0.kind) }
    }

    /// Wszystkie dopasowania w zakresie.
    public func matches(in text: String, within scope: Range<Int>? = nil) throws -> [Range<Int>] {
        guard !pattern.isEmpty else { return [] }
        let ns = text as NSString
        let range = scope.map { NSRange(location: $0.lowerBound, length: $0.count) } ?? NSRange(location: 0, length: ns.length)
        let kinds = inCode && inComments && inStrings ? [] : Self.tokenKinds(text)
        return try expression().matches(in: text, range: range)
            .filter { $0.range.length > 0 && allowed($0.range, kinds: kinds) }
            .map { $0.range.location..<($0.range.location + $0.range.length) }
    }

    /// Następne dopasowanie od pozycji (z zawinięciem na początek/koniec).
    public func next(in text: String, from position: Int, backwards: Bool = false) throws -> Range<Int>? {
        let all = try matches(in: text)
        if backwards { return all.last { $0.upperBound <= position } ?? all.last }
        return all.first { $0.lowerBound >= position } ?? all.first
    }

    /// Tekst zamiany dla dopasowania (szablon regex, sekwencje \t \n, zachowanie wielkości liter).
    func replacementText(for match: NSTextCheckingResult, in text: String, expression: NSRegularExpression) -> String {
        var template = replacement
        if regex {
            template = template.replacingOccurrences(of: "\\t", with: "\t").replacingOccurrences(of: "\\n", with: "\n")
        } else {
            template = NSRegularExpression.escapedTemplate(for: template)
        }
        var out = expression.replacementString(for: match, in: text, offset: 0, template: template)
        if preserveCase {
            let found = (text as NSString).substring(with: match.range)
            if found == found.uppercased(), found != found.lowercased() { out = out.uppercased() }
            else if found == found.lowercased() { out = out.lowercased() }
            else if let f = found.first, f.isUppercase { out = out.prefix(1).uppercased() + out.dropFirst().lowercased() }
        }
        return out
    }

    /// Zamienia wszystkie dopasowania w zakresie; zwraca nowy tekst i liczbę zamian.
    public func replaceAll(in text: String, within scope: Range<Int>? = nil) throws -> (text: String, count: Int) {
        guard !pattern.isEmpty else { return (text, 0) }
        let ns = text as NSString
        let range = scope.map { NSRange(location: $0.lowerBound, length: $0.count) } ?? NSRange(location: 0, length: ns.length)
        let ex = try expression()
        let kinds = inCode && inComments && inStrings ? [] : Self.tokenKinds(text)
        let found = ex.matches(in: text, range: range).filter { $0.range.length > 0 && allowed($0.range, kinds: kinds) }
        let out = NSMutableString(string: text)
        for m in found.reversed() { out.replaceCharacters(in: m.range, with: replacementText(for: m, in: text, expression: ex)) }
        return (out as String, found.count)
    }

    /// Zamienia jedno dopasowanie, jeśli `selection` dokładnie je zaznacza; zwraca nowy tekst i zakres zamiany.
    public func replace(in text: String, selection: Range<Int>) throws -> (text: String, range: Range<Int>)? {
        let ex = try expression()
        let r = NSRange(location: selection.lowerBound, length: selection.count)
        // Granice przezroczyste i bez kotwic: lookaround i `^`/`$` oceniane jak przy „Znajdź” w całym tekście.
        guard let m = ex.firstMatch(in: text, options: [.withTransparentBounds, .withoutAnchoringBounds], range: r), m.range == r else { return nil }
        let rep = replacementText(for: m, in: text, expression: ex)
        let newText = (text as NSString).replacingCharacters(in: r, with: rep)
        return (newText, selection.lowerBound..<(selection.lowerBound + (rep as NSString).length))
    }
}
