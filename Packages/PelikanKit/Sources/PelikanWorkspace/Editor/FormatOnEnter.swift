import Foundation
import PelikanSQL

/// Formatowanie podczas pisania w edytorze (D205, PD-BEAU-003): Enter w oknie SQL, programu albo testu formatuje
/// opuszczaną linię (gdy była edytowana w tej sesji) i wcina nową według reguł formatera (`Beautifier.formatOnEnter`).
/// Edytor wykonuje dwie zmiany tekstu w dwóch grupach cofania: najpierw zwykły Enter (z tym, co robi zwykły Enter:
/// wielkość liter słowa kluczowego przed kursorem, AutoReplace, wcięcie automatyczne), potem formatowanie. Pierwsze ⌘Z
/// cofa samo formatowanie, drugie — Enter. Konsola SQL*Plus i okna bez kodu — bez formatowania.
public enum FormatOnEnter {
    /// Zmiana tekstu: zakres (UTF-16) w tekście przed nią i nowy tekst.
    public struct Edit: Sendable, Equatable {
        public var range: Range<Int>
        public var text: String

        public init(range: Range<Int>, text: String) {
            self.range = range
            self.text = text
        }

        public func applied(to s: String) -> String {
            (s as NSString).replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: text)
        }
    }

    public struct Plan: Sendable, Equatable {
        /// Krok 0 (w grupie Entera) — to, co zwykły Enter robi z tekstem przed kursorem: wielkość liter słowa kluczowego
        /// (Ustawienia › Edytor) i AutoReplace; zakres w tekście wyjściowym, nil — bez zmian.
        public var prepare: Edit?
        /// Krok 1 — zwykły Enter: znak nowej linii z wcięciem automatycznym w miejscu kursora (po kroku 0).
        public var enter: Edit
        /// Krok 2 — formatowanie (zakres w tekście po kroku 1); nil — formatowanie niczego nie zmienia.
        public var format: Edit?
        /// Tekst w zakresie kroku 2 oczekiwany po kroku 1 — inny (coś zmieniło tekst po drodze) — krok 2 pominięty.
        public var expected: String
        /// Kursor po wszystkich krokach: początek nowej linii za wcięciem.
        public var caret: Int
    }

    /// Czy Enter formatuje w oknie tego rodzaju (ustawienie Formatera „Formatuj linię przy Enter”).
    public static func applies(to kind: DocumentKind, options: BeautifierOptions) -> Bool {
        options.formatOnEnter && [.sql, .program, .test].contains(kind)
    }

    /// Plan Entera w `caret` (bez zaznaczenia); nil — zwykły Enter edytora (wyłączone, konsola, Enter na początku linii
    /// albo w jej wiodących odstępach, linia w literale, komentarzu blokowym, kompilacji warunkowej…, AutoReplace z
    /// miejscem kursora — zamiana zużywa Enter). `lineEdited` — opuszczana linia była zmieniona w tej sesji edycji (inaczej
    /// zostaje bez zmian, formatowane jest tylko wcięcie nowej linii).
    public static func plan(text: String, caret: Int, kind: DocumentKind, options: BeautifierOptions, indentMode: IndentMode,
                            unit: String, tabWidth: Int, keywordCase: KeywordCase = .unchanged, autoReplace: [AutoReplaceRule] = [],
                            lineEdited: Bool = true, memory: inout StatementStartMemory) -> Plan? {
        guard applies(to: kind, options: options) else { return nil }
        var ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let original = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        // Krok 0: wielkość liter słowa kluczowego przed kursorem i AutoReplace (jak w zwykłym Enterze).
        var left = original
        if let cased = keywordCaseLine(left, keywordCase) { left = cased }
        if let r = autoReplaceLine(left, rules: autoReplace, text: ns, lineStart: lineStart, caret: caret) {
            guard let replaced = r else { return nil }   // zamiana z miejscem kursora zużywa Enter
            left = replaced
        }
        var working = text
        var at = caret
        var prepare: Edit?
        if left != original {
            prepare = Edit(range: lineStart..<caret, text: left)
            working = prepare!.applied(to: text)
            ns = working as NSString
            at = lineStart + (left as NSString).length
        }
        // Zamiana wieloliniowa (AutoReplace z tekstem z wieloma liniami) — sam Enter z wcięciem, bez formatowania.
        if left.contains(where: \.isNewline) {
            let last = String(left.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? "")
            let enter = Edit(range: at..<at, text: "\n" + SmartIndent.newlineIndent(lineBeforeCaret: last, mode: indentMode, unit: unit))
            return Plan(prepare: prepare, enter: enter, format: nil, expected: "", caret: at + (enter.text as NSString).length)
        }
        let context = memory.context(forLineAt: lineStart, in: ns)
        guard let result = Beautifier.formatOnEnter(working, caret: at, context: context, formatLine: lineEdited || prepare != nil,
                                                    options: options, tabWidth: tabWidth) else { return nil }
        let auto = SmartIndent.newlineIndent(lineBeforeCaret: left, mode: indentMode, unit: unit)
        let enter = Edit(range: at..<at, text: "\n" + auto)
        var line = result.line
        var formatterIndent = result.indent
        // Tryb Smart: linia, której formater nie wyrównał (np. nieedytowana), z END/ELSE/ELSIF/EXCEPTION — wcięcie struktury
        // (wcięcie nowej linii od formatera przesunięte o tyle samo).
        if indentMode == .smart, SmartIndent.leading(line) == SmartIndent.leading(left),
           let fixed = SmartIndent.reindentClosingLine(line, previous: previousLine(ns, before: lineStart), unit: unit) {
            let shift = SmartIndent.leading(fixed).count - SmartIndent.leading(line).count
            if let i = formatterIndent {
                formatterIndent = shift < 0 ? String(i.dropLast(min(i.count, -shift))) : i + String(repeating: " ", count: shift)
            }
            line = fixed
        }
        // Po kroku 1: odstępy na początku nowej linii (wcięcie automatyczne i odstępy reszty linii) zastępuje wcięcie
        // formatera — liczone z tekstu przed krokiem 1, bez kopiowania dokumentu.
        var ws = at
        while ws < ns.length, ns.character(at: ws) == 0x20 || ns.character(at: ws) == 0x09 { ws += 1 }
        let restIndent = ns.substring(with: NSRange(location: at, length: ws - at))
        let expected = left + "\n" + auto + restIndent
        let indent = formatterIndent ?? SmartIndent.newlineIndent(lineBeforeCaret: line, mode: indentMode, unit: unit)
        let replacement = line + "\n" + indent
        let range = lineStart..<(lineStart + (expected as NSString).length)
        let format = expected == replacement ? nil : Edit(range: range, text: replacement)
        let caretAfter = lineStart + ((format?.text ?? left + "\n" + auto) as NSString).length
        return Plan(prepare: prepare, enter: enter, format: format, expected: expected, caret: caretAfter)
    }

    /// Wielkość liter słowa kluczowego kończącego tekst linii przed kursorem (Ustawienia › Edytor › Wielkość liter słów
    /// kluczowych — jak przy wpisaniu znaku kończącego słowo); nil — bez zmian.
    public static func keywordCaseLine(_ line: String, _ keywordCase: KeywordCase) -> String? {
        guard keywordCase != .unchanged, let last = Lexer(line).tokenize().last, last.kind == .keyword,
              last.end == (line as NSString).length else { return nil }
        let word = (line as NSString).substring(with: NSRange(location: last.start, length: last.length))
        let cased: String = switch keywordCase {
        case .upper: word.uppercased()
        case .lower: word.lowercased()
        case .initCap: word.prefix(1).uppercased() + word.dropFirst().lowercased()
        case .unchanged: word
        }
        guard cased != word else { return nil }
        return (line as NSString).replacingCharacters(in: NSRange(location: last.start, length: last.length), with: cased)
    }

    /// AutoReplace po Enterze: nil — bez zamiany; `.some(nil)` — zamiana z miejscem kursora (zużywa Enter);
    /// `.some(linia)` — tekst linii przed kursorem po zamianie (znak nowej linii zostaje za nią).
    static func autoReplaceLine(_ left: String, rules: [AutoReplaceRule], text: NSString, lineStart: Int, caret: Int) -> String?? {
        let lower = left.lowercased()
        // Szybko: żaden skrót nie kończy linii — bez kopiowania dokumentu.
        guard rules.contains(where: { !$0.abbreviation.isEmpty && lower.hasSuffix($0.abbreviation.lowercased()) }) else { return nil }
        let before = text.substring(to: lineStart) + left
        let full = before + "\n" + text.substring(from: caret)
        let at = (before as NSString).length + 1
        guard let r = AutoReplace.apply(rules, text: full, caret: at) else { return nil }
        if r.caret != r.range.lowerBound + (r.replacement as NSString).length { return .some(nil) }
        let replaced = (full as NSString).replacingCharacters(in: NSRange(location: r.range.lowerBound, length: r.range.count), with: r.replacement)
        let newLeft = (replaced as NSString).substring(with: NSRange(location: lineStart, length: r.caret - 1 - lineStart))
        return .some(newLeft)
    }

    /// Poprzednia niepusta linia przed `lineStart` (wcięcie Smart).
    static func previousLine(_ ns: NSString, before lineStart: Int) -> String? {
        var p = lineStart
        while p > 0 {
            let r = ns.lineRange(for: NSRange(location: p - 1, length: 0))
            let s = ns.substring(with: r).trimmingCharacters(in: .newlines)
            if !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
            p = r.location
        }
        return nil
    }
}

/// Fragmenty tekstu zmienione w tej sesji edycji (od otwarcia, zapisu albo wczytania — jak status linii): formatowanie
/// przy Enter zmienia tylko linię edytowaną, istniejący kod — tylko na żądanie (D205). Zakresy przesuwane przy zmianach.
public struct EditedRanges: Sendable, Equatable {
    public private(set) var ranges: [Range<Int>] = []

    public init() {}

    /// Zmiana tekstu: `edited` — zakres nowego tekstu w tekście po zmianie, `delta` — zmiana długości;
    /// `newlineFirst` — wstawiony tekst zaczyna się znakiem nowej linii (Enter na końcu linii): linia, za którą wstawiono,
    /// nie jest zmieniona.
    public mutating func record(edited input: Range<Int>, delta: Int, newlineFirst: Bool = false) {
        var edited = input
        if newlineFirst, delta == edited.count, !edited.isEmpty { edited = (edited.lowerBound + 1)..<edited.upperBound }
        let oldEnd = input.upperBound - delta
        var out: [Range<Int>] = []
        var merged = edited
        for r in ranges {
            if r.upperBound < edited.lowerBound {
                out.append(r)
            } else if r.lowerBound > oldEnd {
                out.append((r.lowerBound + delta)..<(r.upperBound + delta))
            } else {
                // Zakres nachodzi na zmieniony fragment — łączony z nim (w nowych położeniach).
                let lo = min(r.lowerBound, edited.lowerBound)
                let hi = r.upperBound > oldEnd ? r.upperBound + delta : edited.upperBound
                merged = min(merged.lowerBound, lo)..<max(merged.upperBound, hi)
            }
        }
        out.append(merged)
        ranges = out.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Czy treść linii (`line` — od początku linii do znaku nowej linii, bez niego) była zmieniona: zakres zmiany
    /// nachodzi na nią albo styka się z nią (wpisanie albo usunięcie na jej końcu). Zmiana od początku następnej linii
    /// jej nie oznacza, a Enter na jej końcu zapisany jest od następnej linii (`newlineFirst`).
    public func touches(line: Range<Int>) -> Bool {
        ranges.contains { $0.lowerBound <= line.upperBound && $0.upperBound >= line.lowerBound }
    }

    /// Nowa sesja edycji w zakresie (wczytany plik okna pary) — zmiany w nim zapomniane.
    public mutating func clear(_ range: Range<Int>) {
        var out: [Range<Int>] = []
        for r in ranges {
            if r.upperBound <= range.lowerBound || r.lowerBound >= range.upperBound {
                if !(r.isEmpty && range.contains(r.lowerBound)) { out.append(r) }
                continue
            }
            if r.lowerBound < range.lowerBound { out.append(r.lowerBound..<range.lowerBound) }
            if r.upperBound > range.upperBound { out.append(range.upperBound..<r.upperBound) }
        }
        ranges = out
    }

    public mutating func reset() { ranges = [] }
}
