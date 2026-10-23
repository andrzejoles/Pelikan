import Foundation
import PelikanSQL

/// Zadanie do zrobienia w komentarzu (UG 18 To-Do Items). Składnia Pelikana (D-EDYTOR-2):
/// `-- TODO(właściciel) !priorytet #kategoria: tekst`, także w `/* … */`; wszystkie atrybuty opcjonalne,
/// zamknięte zadanie to `DONE` zamiast `TODO`.
public struct TodoItem: Sendable, Hashable, Identifiable {
    /// Linia (od 1).
    public var line: Int
    /// Zakres słowa TODO/DONE w tekście (UTF-16) — zamykanie zamienia je na DONE.
    public var keywordRange: Range<Int>
    public var text: String
    public var owner: String?
    public var priority: Int?
    public var category: String?
    public var closed: Bool
    public var id: String { "\(line):\(keywordRange.lowerBound)" }
}

public enum TodoItems {
    nonisolated(unsafe) static let regex = try! NSRegularExpression(
        pattern: #"\b(TODO|DONE)\b(?:\s*\(([^)]*)\))?((?:\s*(?:![0-9]+|#[\p{L}\p{N}_-]+))*)\s*:?\s*(.*)"#, options: [.caseInsensitive])

    /// Zadania w komentarzach tekstu (literały i kod pomijane — lekser).
    public static func parse(_ text: String) -> [TodoItem] {
        let ns = text as NSString
        var items: [TodoItem] = []
        for t in Lexer(text).tokenize() where t.kind == .lineComment || t.kind == .blockComment {
            let comment = ns.substring(with: NSRange(location: t.start, length: t.length))
            // Komentarz blokowy może mieć zadanie w każdej linii.
            var offset = 0
            for part in comment.components(separatedBy: "\n") {
                defer { offset += (part as NSString).length + 1 }
                let pns = part as NSString
                guard let m = regex.firstMatch(in: part, range: NSRange(location: 0, length: pns.length)) else { continue }
                // Słowo musi otwierać treść komentarza (po `--`, `/*`, `*` i odstępach), nie stać w środku zdania.
                let lead = pns.substring(to: m.range.location).trimmingCharacters(in: CharacterSet(charactersIn: "-/* \t"))
                guard lead.isEmpty else { continue }
                func group(_ i: Int) -> String? {
                    let r = m.range(at: i)
                    guard r.location != NSNotFound else { return nil }
                    let s = pns.substring(with: r).trimmingCharacters(in: .whitespaces)
                    return s.isEmpty ? nil : s
                }
                let attrs = (group(3) ?? "").split(whereSeparator: \.isWhitespace)
                var body = group(4) ?? ""
                if t.kind == .blockComment, body.hasSuffix("*/") { body = String(body.dropLast(2)).trimmingCharacters(in: .whitespaces) }
                let start = t.start + offset + m.range(at: 1).location
                let line = ns.substring(to: start).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                items.append(TodoItem(line: line, keywordRange: start..<(start + 4), text: body, owner: group(2),
                                      priority: attrs.first { $0.hasPrefix("!") }.flatMap { Int($0.dropFirst()) },
                                      category: attrs.first { $0.hasPrefix("#") }.map { String($0.dropFirst()) },
                                      closed: pns.substring(with: m.range(at: 1)).uppercased() == "DONE"))
            }
        }
        return items
    }

    /// Zamyka zadanie (TODO → DONE) albo otwiera ponownie.
    public static func toggle(_ item: TodoItem, in text: String) -> String {
        (text as NSString).replacingCharacters(in: NSRange(location: item.keywordRange.lowerBound, length: 4), with: item.closed ? "TODO" : "DONE")
    }

    /// Wstawia nowe zadanie w linii nad kursorem z wcięciem bieżącej linii; zwraca tekst i pozycję kursora.
    public static func insert(in text: String, at offset: Int, owner: String?) -> (text: String, caret: Int) {
        let ns = text as NSString
        let lineStart = ns.lineRange(for: NSRange(location: min(offset, ns.length), length: 0)).location
        let rest = ns.substring(from: lineStart)
        let indent = String(rest.prefix { $0 == " " || $0 == "\t" })
        let item = indent + "-- TODO" + (owner.map { "(\($0))" } ?? "") + ": "
        let new = ns.replacingCharacters(in: NSRange(location: lineStart, length: 0), with: item + "\n")
        return (new, lineStart + (item as NSString).length)
    }
}
