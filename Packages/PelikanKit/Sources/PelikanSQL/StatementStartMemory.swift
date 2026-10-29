import Foundation

/// Pamięć podziału skryptu na polecenia dla formatowania przy Enter (D205): początki poleceń wyznaczone podziałem
/// (`ScriptSplitter`, tryb Command Window — jak formater) zostają ważne, dopóki tekst przed nimi się nie zmienia (podział
/// idzie od początku tekstu, więc zmiana dalej nie przesuwa wcześniejszych początków). Enter dzieli tylko tekst od
/// ostatniego znanego początku do linii kursora, a nie cały plik.
public struct StatementStartMemory: Sendable, Equatable {
    /// Znane początki poleceń (UTF-16), rosnąco.
    public private(set) var starts: [Int] = []

    public init() {}

    /// Zmiana tekstu od `location`: początki od tego miejsca przestają obowiązywać.
    public mutating func invalidate(from location: Int) {
        if let k = starts.firstIndex(where: { $0 >= location }) { starts.removeSubrange(k...) }
    }

    /// Początek kontekstu formatowania linii zaczynającej się w `lineStart`: początek polecenia, w którym linia leży,
    /// albo sam `lineStart`, gdy poprzednie polecenie skończyło się przed nią (linia zaczyna nowe polecenie).
    public mutating func contextStart(forLineAt lineStart: Int, in text: NSString) -> Int {
        let base = starts.last { $0 <= lineStart } ?? 0
        guard base < lineStart else { return base }
        let parts = ScriptSplitter.split(text.substring(with: NSRange(location: base, length: lineStart - base)), mode: .commandWindow)
        for p in parts where base + p.start > (starts.last ?? -1) { starts.append(base + p.start) }
        guard let last = parts.last else { return base }
        // Polecenie niezakończone przed linią (blok PL/SQL, SQL bez średnika) — linia jest jego dalszym ciągiem.
        return last.terminator == .endOfText ? base + last.start : lineStart
    }
}
