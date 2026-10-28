import Foundation

/// Karty jednostek okna programu (PD-PROG-001, D192): tekst okna dzielony na rozłączne odcinki pełnych linii — jeden
/// na jednostkę — a edytor pokazuje tylko odcinek wybranej karty. Dokument zostaje jeden (zapis, kompilacja F8,
/// historia, worksety); karta aktywna to zawsze karta odcinka z kursorem, więc każde przejście w inne miejsce tekstu
/// (komunikat kompilacji, Code Contents, wyszukiwanie, deklaracja, debuger) przełącza ją samo.
public struct ProgramUnitTab: Sendable, Hashable {
    /// Odcinek tekstu karty (UTF-16): od początku linii do początku linii następnej karty; ostatnia — do końca tekstu.
    public var segment: Range<Int>
    /// Pozycja słowa typu (`PACKAGE BODY …`) — linia 1 jednostki w ALL_SOURCE i ALL_ERRORS (D189).
    public var sourceOffset: Int
    public var title: String
    /// Argument komendy `prog.selectUnit`: nazwa, „nazwa body” dla ciała pakietu albo typu.
    public var key: String

    public init(segment: Range<Int>, sourceOffset: Int, title: String, key: String) {
        self.segment = segment; self.sourceOffset = sourceOffset; self.title = title; self.key = key
    }
}

public enum ProgramUnitTabs {
    /// Karty jednostek w kolejności tekstu; mniej niż dwie jednostki — brak kart (okno bez zmian zachowania).
    public static func tabs(_ units: [ProgramUnit], in text: String) -> [ProgramUnitTab] {
        let units = units.sorted { $0.range.lowerBound < $1.range.lowerBound }
        guard units.count > 1 else { return [] }
        let ns = text as NSString
        let length = ns.length
        func lineStart(_ o: Int) -> Int { ns.lineRange(for: NSRange(location: min(max(0, o), length), length: 0)).location }
        func isBlank(_ r: NSRange) -> Bool { ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var starts = [0]
        for i in 1..<units.count {
            let unitLine = lineStart(units[i].range.lowerBound)
            // Za poprzednią jednostką: kończący „/” w osobnej linii i puste linie należą do niej; komentarz przed CREATE
            // — już do następnej karty.
            var k = min(units[i - 1].range.upperBound, length)
            var boundary = unitLine
            var p = k
            while p < length, [0x20, 0x09, 0x0D, 0x0A].contains(ns.character(at: p)) { p += 1 }
            if p < length, ns.character(at: p) == 0x2F {
                let line = ns.lineRange(for: NSRange(location: p, length: 0))
                if isBlank(NSRange(location: line.location, length: p - line.location)),
                   ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == "/" {
                    k = line.upperBound
                    while k < unitLine {
                        let next = ns.lineRange(for: NSRange(location: k, length: 0))
                        guard next.length > 0, isBlank(next) else { break }
                        k = next.upperBound
                    }
                    boundary = min(k, unitLine)
                }
            }
            // Odcinki niepuste i rosnące (tekst niepoprawny: dwie jednostki w jednej linii — linia należy do pierwszej).
            starts.append(max(boundary, starts.last! + 1))
        }
        return units.enumerated().map { i, u in
            let end = i + 1 < starts.count ? starts[i + 1] : length
            let lineOffset = TextEditing.offset(ofLine: u.sourceLine + 1, in: text)
            let body = [.packageBody, .typeBody].contains(u.type)
            return ProgramUnitTab(segment: min(starts[i], end)..<max(starts[i], end), sourceOffset: min(lineOffset + u.sourceColumn, length),
                                  title: u.tabTitle, key: u.name + (body ? " body" : ""))
        }
    }

    /// Karta odcinka zawierającego pozycję (pozycja na granicy — karta, która się w niej zaczyna).
    public static func index(of offset: Int, in tabs: [ProgramUnitTab]) -> Int? {
        guard !tabs.isEmpty else { return nil }
        var lo = 0, hi = tabs.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tabs[mid].segment.lowerBound <= offset { lo = mid + 1 } else { hi = mid }
        }
        return max(0, lo - 1)
    }

    /// Najdalsza pozycja kursora na karcie: koniec ostatniej linii odcinka (bez znaku nowej linii, który oddziela
    /// kartę następną), na ostatniej karcie — koniec tekstu.
    public static func caretLimit(_ tab: ProgramUnitTab, isLast: Bool, in ns: NSString) -> Int {
        let end = min(tab.segment.upperBound, ns.length)
        if isLast || end <= tab.segment.lowerBound { return end }
        return ns.character(at: end - 1) == 0x0A ? end - 1 : end
    }

    /// Początek linii pozycji.
    public static func lineStart(_ o: Int, in ns: NSString) -> Int {
        ns.lineRange(for: NSRange(location: min(max(0, o), ns.length), length: 0)).location
    }

    /// Karta z argumentu komendy: numer od 1, nazwa, „nazwa body” albo tytuł karty (bez wielkości liter).
    public static func find(_ spec: String, in tabs: [ProgramUnitTab]) -> Int? {
        let s = spec.trimmingCharacters(in: .whitespaces)
        if let n = Int(s) { return tabs.indices.contains(n - 1) ? n - 1 : nil }
        let up = s.uppercased().split(separator: " ").joined(separator: " ")
        if let i = tabs.firstIndex(where: { $0.key.uppercased() == up || $0.title.uppercased() == up }) { return i }
        // Sama nazwa pakietu — specyfikacja (pierwsza karta o tej nazwie).
        return tabs.firstIndex { $0.key.uppercased().split(separator: " ").first.map(String.init) == up }
    }

    /// Numer linii jednostki (od 1) jak w ALL_SOURCE/ALL_ERRORS dla linii dokumentu (od 0); linie przed słowem typu
    /// (CREATE OR REPLACE w osobnej linii, komentarz przed jednostką) — nil.
    public static func unitLine(documentLine: Int, sourceLine: Int) -> Int? {
        documentLine >= sourceLine ? documentLine - sourceLine + 1 : nil
    }

    /// Granice kart po zmianie tekstu (`edited` — zakres wstawionego tekstu w nowym tekście, `delta` — zmiana długości):
    /// granica za zmianą przesuwa się o `delta`, granica w usuniętym fragmencie — na koniec wstawionego tekstu;
    /// tekst wstawiony dokładnie na granicy należy do karty wcześniejszej.
    public static func shift(_ tabs: [ProgramUnitTab], edited: Range<Int>, delta: Int) -> [ProgramUnitTab] {
        let oldEnd = edited.upperBound - delta
        func move(_ o: Int) -> Int {
            if o < edited.lowerBound { return o }
            if o >= oldEnd { return o + delta }
            return edited.upperBound
        }
        return tabs.enumerated().map { i, t in
            var t = t
            // Początek pierwszej karty zawsze 0; koniec karty = początek następnej (odcinki bez przerw).
            let lower = i == 0 ? 0 : move(t.segment.lowerBound)
            let upper = max(lower, move(t.segment.upperBound))
            t.segment = lower..<upper
            t.sourceOffset = move(t.sourceOffset)
            return t
        }
    }
}
