import Foundation
import PelikanSQL

/// Formatowanie podczas pisania w edytorze (D205, PD-BEAU-003): Enter w oknie SQL, programu albo testu formatuje
/// opuszczaną linię i wcina nową według reguł formatera (`Beautifier.formatOnEnter`). Edytor wykonuje dwie zmiany:
/// najpierw zwykły Enter z wcięciem automatycznym, potem — w osobnej grupie cofania — formatowanie. Pierwsze ⌘Z cofa
/// samo formatowanie, drugie — Enter. Konsola SQL*Plus i okna bez kodu — bez formatowania.
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
        /// Krok 1 — zwykły Enter: znak nowej linii z wcięciem automatycznym w miejscu kursora.
        public var enter: Edit
        /// Krok 2 — formatowanie (zakres w tekście po kroku 1); nil — formatowanie niczego nie zmienia.
        public var format: Edit?
        /// Kursor po obu krokach: początek nowej linii za wcięciem.
        public var caret: Int
    }

    /// Czy Enter formatuje w oknie tego rodzaju (ustawienie Formatera „Formatuj linię przy Enter”).
    public static func applies(to kind: DocumentKind, options: BeautifierOptions) -> Bool {
        options.formatOnEnter && [.sql, .program, .test].contains(kind)
    }

    /// Plan Entera w `caret` (bez zaznaczenia); nil — zwykły Enter edytora (wyłączone, konsola, linia w literale,
    /// komentarzu blokowym, kompilacji warunkowej…).
    public static func plan(text: String, caret: Int, kind: DocumentKind, options: BeautifierOptions, indentMode: IndentMode,
                            unit: String, tabWidth: Int, memory: inout StatementStartMemory) -> Plan? {
        guard applies(to: kind, options: options) else { return nil }
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let start = memory.contextStart(forLineAt: lineStart, in: ns)
        guard let result = Beautifier.formatOnEnter(text, caret: caret, contextStart: start, options: options, tabWidth: tabWidth) else {
            return nil
        }
        let left = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let auto = SmartIndent.newlineIndent(lineBeforeCaret: left, mode: indentMode, unit: unit)
        let enter = Edit(range: caret..<caret, text: "\n" + auto)
        // Po kroku 1: odstępy na początku nowej linii (wcięcie automatyczne i odstępy reszty linii) zastępuje wcięcie formatera.
        let after = enter.applied(to: text) as NSString
        var wsEnd = caret + 1
        while wsEnd < after.length, after.character(at: wsEnd) == 0x20 || after.character(at: wsEnd) == 0x09 { wsEnd += 1 }
        let indent = result.indent ?? SmartIndent.newlineIndent(lineBeforeCaret: result.line, mode: indentMode, unit: unit)
        let replacement = result.line + "\n" + indent
        let range = lineStart..<wsEnd
        let current = after.substring(with: NSRange(location: range.lowerBound, length: range.count))
        let format = current == replacement ? nil : Edit(range: range, text: replacement)
        let caretAfter = format.map { lineStart + ($0.text as NSString).length } ?? caret + (enter.text as NSString).length
        return Plan(enter: enter, format: format, caret: caretAfter)
    }
}
