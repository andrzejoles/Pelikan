import Foundation
import PelikanSQL

/// Karty jednostek okna programu (PD-PROG-001, D192): tekst okna dzielony na rozłączne odcinki pełnych linii — jeden
/// na jednostkę — a edytor pokazuje tylko odcinek wybranej karty. Dokument zostaje jeden (zapis, kompilacja F8,
/// historia, worksety); karta aktywna to zawsze karta odcinka z kursorem, więc każde przejście w inne miejsce tekstu
/// (komunikat kompilacji, Code Contents, wyszukiwanie, deklaracja, debuger) przełącza ją samo.
public struct ProgramUnitTab: Sendable, Hashable {
    /// Odcinek tekstu karty (UTF-16): od początku linii do początku linii następnej karty; ostatnia — do końca tekstu.
    /// Kończący „/” w osobnej linii należy do jednostki przed nim, puste linie i komentarz przed CREATE — do następnej.
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

/// Tekst okna programu z jednostek (D192): domyślnie bez „/” — jednostki rozdzielone pustą linią i rozpoznawane po
/// nagłówkach CREATE; z preferencją (albo w pliku, który już używa „/”) — każda jednostka zakończona „/”.
public enum ProgramText {
    public static func join(_ sources: [String], slash: Bool) -> String {
        let parts = sources.map { s -> String in
            var t = s
            while let c = t.last, c.isWhitespace { t.removeLast() }
            if slash, t.hasSuffix("\n/") || t == "/" { t.removeLast(); while let c = t.last, c.isWhitespace { t.removeLast() } }
            return t
        }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        return slash ? parts.map { $0 + "\n/\n" }.joined(separator: "\n") : parts.joined(separator: "\n\n") + "\n"
    }

    /// Tekst z „/” w osobnej linii po każdej jednostce, która go nie ma (szablon jednostek wstawiany do okna SQL, okna
    /// poleceń albo okna programu z konwencją „/”) — reszta tekstu bez zmian. `inserted` — pozycje (w tekście
    /// wejściowym), za którymi dopisano „\n/”, do przesunięcia kursora.
    public static func terminatingUnits(_ text: String) -> (text: String, inserted: [Int]) {
        let ns = text as NSString
        var out = text as NSString
        var inserted: [Int] = []
        for u in ProgramCompiler.units(in: text).sorted(by: { $0.range.upperBound > $1.range.upperBound }) {
            let end = min(u.range.upperBound, ns.length)
            var k = end
            while k < ns.length, [0x20, 0x09, 0x0D, 0x0A].contains(ns.character(at: k)) { k += 1 }
            if k < ns.length, ns.character(at: k) == 0x2F {
                let line = ns.lineRange(for: NSRange(location: k, length: 0))
                if ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == "/" { continue }
            }
            out = out.replacingCharacters(in: NSRange(location: end, length: 0), with: "\n/") as NSString
            inserted.append(end)
        }
        return (out as String, inserted.sorted())
    }

    /// Czy tekst okna kończy jednostki „/” (konwencja pliku — nowa jednostka dopisywana tak samo).
    public static func usesSlash(_ text: String) -> Bool {
        ScriptSplitter.split(text).contains { $0.terminator == .slash && ProgramCompiler.header($0.text) != nil }
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
            // Za poprzednią jednostką: kończący „/” w osobnej linii należy do niej; puste linie i komentarz przed CREATE
            // — już do następnej karty (Enter w pierwszej linii karty zostaje na tej karcie także po ponownej analizie).
            // Bez „/” (pliki właściciela, D192): granica za ostatnią linią poprzedniej jednostki.
            let prevEnd = min(units[i - 1].range.upperBound, length)
            var boundary = min(unitLine, prevEnd > 0 ? NSMaxRange(ns.lineRange(for: NSRange(location: prevEnd - 1, length: 0))) : unitLine)
            var p = prevEnd
            while p < length, [0x20, 0x09, 0x0D, 0x0A].contains(ns.character(at: p)) { p += 1 }
            if p < length, ns.character(at: p) == 0x2F {
                let line = ns.lineRange(for: NSRange(location: p, length: 0))
                if isBlank(NSRange(location: line.location, length: p - line.location)),
                   ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == "/" {
                    // Kolejne linie z samym „/” (np. powielona linia) — też przy jednostce przed nimi.
                    var end = line.upperBound
                    while end < unitLine {
                        let next = ns.lineRange(for: NSRange(location: end, length: 0))
                        guard next.length > 0, ns.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines) == "/" else { break }
                        end = next.upperBound
                    }
                    boundary = min(end, unitLine)
                }
            }
            // Polecenia między jednostkami, które nie doklejają się do jednostki bez „/” (GRANT, REVOKE, SHOW ERRORS —
            // D192), należą do jednostki przed nimi (D194): plik specyfikacji z uprawnieniami za jednostką zapisuje się
            // razem z nimi. Komentarze, puste linie i inny tekst przed CREATE zostają przy następnej.
            var q = boundary, grants = boundary
            while q < unitLine {
                let line = ns.lineRange(for: NSRange(location: q, length: 0))
                let t = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if t.isEmpty { q = NSMaxRange(line); continue }
                let word = t.prefix { $0.isLetter }
                if word == "SHOW", t.dropFirst(4).trimmingCharacters(in: .whitespaces).hasPrefix("ERR") { q = NSMaxRange(line); grants = q; continue }
                guard word == "GRANT" || word == "REVOKE" else { break }
                // Polecenie do linii, której ostatni znak kodu (bez komentarza) to „;”.
                func endsStatement(_ r: NSRange) -> Bool {
                    Lexer(ns.substring(with: r)).tokenize().last(where: { !$0.isTrivia })?.kind == .semicolon
                }
                var e = line
                while !endsStatement(e), NSMaxRange(e) < unitLine {
                    e = ns.lineRange(for: NSRange(location: NSMaxRange(e), length: 0))
                }
                q = NSMaxRange(e)
                grants = q
            }
            boundary = min(max(boundary, grants), unitLine)
            // Odcinki niepuste i rosnące (tekst niepoprawny: dwie jednostki w jednej linii — linia należy do pierwszej).
            starts.append(max(boundary, starts.last! + 1))
        }
        return units.enumerated().map { i, u in
            let end = i + 1 < starts.count ? starts[i + 1] : length
            let body = [.packageBody, .typeBody].contains(u.type)
            return ProgramUnitTab(segment: min(starts[i], end)..<max(starts[i], end), sourceOffset: min(sourceOffset(u), length),
                                  title: u.tabTitle, key: u.name + (body ? " body" : ""))
        }
    }

    /// Czy czyste wstawienie z modelu w punkcie `location` zastosować o znak wcześniej (`true`), żeby zostało na karcie
    /// przed granicą. Najmniejsza różnica tekstów stawia wstawienie na granicy także wtedy, gdy komenda dopisała tekst
    /// na końcu poprzedniej karty (Powiel linię w ostatniej linii: kopia „\n/” za „/” wygląda jak „/\n” na granicy).
    /// Tylko gdy: `location` jest granicą kart, widoczna jest karta kończąca się w tej granicy, wstawiony tekst kończy
    /// się tym samym znakiem co tekst przed granicą (zwykle „\n”), a kursor po zmianie leży wewnątrz wstawionego
    /// tekstu (w kopii, nie na jego początku). Wstawienie z innej karty (To-Do w pierwszej linii ciała, agent dopisujący komentarz przed
    /// CREATE) zostaje na karcie późniejszej.
    public static func appliesBeforeBoundary(_ tabs: [ProgramUnitTab], shownTab: Int?, location: Int, inserted: String,
                                             characterBefore: unichar?, selectionAfter: Int) -> Bool {
        let ins = inserted as NSString
        guard ins.length > 0, let before = characterBefore, before == ins.character(at: ins.length - 1),
              let shown = shownTab, tabs.indices.contains(shown), shown + 1 < tabs.count,
              tabs[shown].segment.upperBound == location, tabs[shown + 1].segment.lowerBound == location else { return false }
        return selectionAfter > location && selectionAfter < location + ins.length
    }

    /// Pozycja słowa typu w tekście okna: od początku polecenia jednostki (linie nagłówka w jej tekście), bez liczenia
    /// linii całego dokumentu (pakiet 50 000 linii).
    static func sourceOffset(_ u: ProgramUnit) -> Int {
        let ns = u.text as NSString
        var line = u.line, o = 0
        while line < u.sourceLine, o < ns.length {
            if ns.character(at: o) == 0x0A { line += 1 }
            o += 1
        }
        return u.range.lowerBound + o + u.sourceColumn
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
    /// tekst wstawiony dokładnie na granicy należy do karty późniejszej (kursor na początku karty stoi na granicy —
    /// Enter albo wklejenie w pierwszej kolumnie zostaje na tej karcie).
    public static func shift(_ tabs: [ProgramUnitTab], edited: Range<Int>, delta: Int) -> [ProgramUnitTab] {
        let oldEnd = edited.upperBound - delta
        let pureInsertion = oldEnd == edited.lowerBound
        func move(_ o: Int) -> Int {
            if o < edited.lowerBound || (pureInsertion && o == edited.lowerBound) { return o }
            if o >= oldEnd { return o + delta }
            return edited.upperBound
        }
        return tabs.enumerated().map { i, t in
            var t = t
            // Początek pierwszej karty zawsze 0, koniec ostatniej — koniec tekstu; koniec karty = początek następnej.
            let lower = i == 0 ? 0 : move(t.segment.lowerBound)
            let upper = max(lower, i == tabs.count - 1 ? t.segment.upperBound + delta : move(t.segment.upperBound))
            t.segment = lower..<upper
            t.sourceOffset = move(t.sourceOffset)
            return t
        }
    }
}
