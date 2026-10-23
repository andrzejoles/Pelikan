import Foundation

/// Obszar zwijania kodu (UG 25.17): pierwsza linia zostaje widoczna, ukryte są linie od następnej do końca obszaru.
public struct FoldRegion: Sendable, Hashable {
    /// Początek struktury (BEGIN, IF, LOOP, CASE) — klucz zwinięcia, stabilny między przeliczeniami.
    public var start: Int
    /// Linie (od 0) pierwszej i ostatniej linii obszaru.
    public var startLine: Int
    public var endLine: Int
    /// Ukrywany zakres znaków (UTF-16): od początku linii po `startLine` do końca `endLine` (z jej znakiem nowej linii).
    public var hidden: Range<Int>
}

public enum CodeFolding {
    /// Obszary zwijania z parsera strukturalnego — tylko obejmujące co najmniej dwie linie.
    public static func regions(_ text: String) -> [FoldRegion] {
        let ns = text as NSString
        var lineStarts = [0]
        for i in 0..<ns.length where ns.character(at: i) == 0x0A { lineStarts.append(i + 1) }
        func line(_ offset: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }
        var seen = Set<Int>()
        return PLSQLOutline.foldingRanges(text).compactMap { r in
            let a = line(r.lowerBound), b = line(max(r.lowerBound, r.upperBound - 1))
            // Jedna struktura na linię (np. „begin if … then” — zwija zewnętrzna).
            guard b > a, seen.insert(a).inserted else { return nil }
            let hiddenStart = lineStarts[a + 1]
            let hiddenEnd = b + 1 < lineStarts.count ? lineStarts[b + 1] : ns.length
            return FoldRegion(start: r.lowerBound, startLine: a, endLine: b, hidden: hiddenStart..<hiddenEnd)
        }
    }

    /// Ukryte zakresy dla zwiniętych obszarów (zwinięcia zagnieżdżone w zwiniętych są pochłaniane).
    public static func hiddenRanges(_ regions: [FoldRegion], folded: Set<Int>) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for r in regions.filter({ folded.contains($0.start) }).sorted(by: { $0.hidden.lowerBound < $1.hidden.lowerBound }) {
            if let last = out.last, r.hidden.lowerBound < last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.hidden.upperBound)
            } else {
                out.append(r.hidden)
            }
        }
        return out
    }

    /// Przesunięcie kluczy zwinięć po zmianie tekstu (wspólny początek i koniec starego i nowego tekstu);
    /// zwinięcia, których początek był w zmienionym fragmencie, znikają.
    public static func shift(_ folded: Set<Int>, from old: String, to new: String) -> Set<Int> {
        guard !folded.isEmpty else { return folded }
        let a = old as NSString, b = new as NSString
        let minLen = min(a.length, b.length)
        var prefix = 0
        while prefix < minLen, a.character(at: prefix) == b.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < minLen - prefix, a.character(at: a.length - 1 - suffix) == b.character(at: b.length - 1 - suffix) { suffix += 1 }
        let changedEnd = a.length - suffix
        let delta = b.length - a.length
        return Set(folded.compactMap { s in
            if s < prefix { return s }
            if s >= changedEnd { return s + delta }
            return nil
        })
    }
}
