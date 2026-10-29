import Foundation
import PelikanSQL

/// Tryb wcięcia nowej linii (UG 23.12 Indent): bez wcięcia, jak linia bieżąca, inteligentne (struktura PL/SQL).
public enum IndentMode: String, Sendable, Codable, Hashable, CaseIterable { case none, automatic, smart }

/// Wcięcia przy pisaniu (PD-EDIT-004): Enter w trybach None/Automatic/Smart, wyrównanie słowa zamykającego
/// blok w trybie Smart i Backspace usuwający całą jednostkę wcięcia.
public enum SmartIndent {
    /// Słowa, po których (na końcu linii) Smart wcina następną linię o jednostkę.
    static let openers: Set<String> = ["BEGIN", "THEN", "LOOP", "ELSE", "DECLARE", "IS", "AS", "EXCEPTION", "CASE"]
    /// Słowa zamykające albo dzielące blok — w trybie Smart linia wraca do poziomu struktury.
    static let closers: Set<String> = ["END", "ELSE", "ELSIF", "EXCEPTION"]

    /// Wcięcie nowej linii po Enter; `lineBeforeCaret` — tekst linii od jej początku do kursora.
    public static func newlineIndent(lineBeforeCaret line: String, mode: IndentMode, unit: String) -> String {
        let indent = leading(line)
        switch mode {
        case .none: return ""
        case .automatic: return indent
        case .smart:
            guard let last = significant(line).last else { return indent }
            return last == "(" || openers.contains(last) ? indent + unit : indent
        }
    }

    /// Smart: linia zaczynająca się od END/ELSE/ELSIF/EXCEPTION z wcięciem nadanym automatycznie (jak poprzednia
    /// linia albo o jednostkę więcej po słowie otwierającym) dostaje wcięcie struktury; nil — bez zmiany.
    public static func reindentClosingLine(_ line: String, previous: String?, unit: String) -> String? {
        guard let first = significant(line).first, closers.contains(first), let previous else { return nil }
        let current = leading(line), prev = leading(previous)
        let prevOpens = significant(previous).last.map { openers.contains($0) || $0 == "(" } ?? false
        let target = prevOpens ? prev : String(prev.dropLast(min(prev.count, unit.count)))
        guard current != target, current == prev || current == prev + unit else { return nil }
        return target + line.dropFirst(current.count)
    }

    /// Backspace w wiodących odstępach linii: liczba znaków do usunięcia (do poprzedniej wielokrotności jednostki);
    /// nil — zwykłe usunięcie jednego znaku.
    public static func backspaceUnindent(lineBeforeCaret line: String, unit: String) -> Int? {
        guard !line.isEmpty, line.allSatisfy({ $0 == " " }), !unit.contains("\t"), unit.count > 1 else { return nil }
        let n = line.count
        return (n - 1) % unit.count + 1
    }

    /// Czy znak przed kursorem to znak nowej linii (Enter nie został zużyty, np. przez AutoReplace z miejscem kursora).
    public static func followsNewline(_ text: NSString, caret: Int) -> Bool {
        caret > 0 && caret <= text.length && [0x0A, 0x0D].contains(text.character(at: caret - 1))
    }

    static func leading(_ line: String) -> String { String(line.prefix { $0 == " " || $0 == "\t" }) }

    /// Słowa i nawiasy linii (wielkimi literami), bez komentarzy i literałów.
    static func significant(_ line: String) -> [String] {
        let ns = line as NSString
        return Lexer(line).tokenize().compactMap { t in
            switch t.kind {
            case .keyword, .identifier: return ns.substring(with: NSRange(location: t.start, length: t.length)).uppercased()
            case .whitespace, .newline, .lineComment, .blockComment: return nil
            default: return ns.substring(with: NSRange(location: t.start, length: t.length))
            }
        }
    }
}

/// Margines numerów linii (UG 23.12 „Line numbers”, PD-EDIT-003): numer co n-tą linię, zawsze pierwsza i bieżąca.
public enum LineNumbering {
    public static func shows(line: Int, caretLine: Int, interval: Int) -> Bool {
        interval <= 1 || line == 0 || line == caretLine || (line + 1) % interval == 0
    }

    /// Znak pokazywany w miejscu znaku specjalnego (spacja, tabulacja, koniec linii) albo nil.
    public static func specialMark(_ c: unichar) -> String? {
        switch c {
        case 0x20: "·"
        case 0x09: "→"
        case 0x0A: "¶"
        case 0xA0: "°"
        default: nil
        }
    }
}
