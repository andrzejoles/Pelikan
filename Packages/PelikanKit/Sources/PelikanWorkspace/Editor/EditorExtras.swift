import Foundation
import PelikanDB
import PelikanSQL

// MARK: - Przesuwanie pozycji po zmianie tekstu

/// Zmiana tekstu jako wspólny początek i koniec (UTF-16); pozycje przed zmianą zostają, za nią — przesuwane.
public enum EditorShift {
    public struct Change: Sendable {
        public let prefix: Int
        public let oldEnd: Int
        public let delta: Int

        public init(old: String, new: String) {
            let a = old as NSString, b = new as NSString
            let minLen = min(a.length, b.length)
            var p = 0
            while p < minLen, a.character(at: p) == b.character(at: p) { p += 1 }
            var s = 0
            while s < minLen - p, a.character(at: a.length - 1 - s) == b.character(at: b.length - 1 - s) { s += 1 }
            prefix = p
            oldEnd = a.length - s
            delta = b.length - a.length
        }

        /// Pozycja po zmianie: wewnątrz zmienionego fragmentu — jego początek.
        public func shift(_ offset: Int) -> Int {
            if offset <= prefix { return offset }
            if offset >= oldEnd { return offset + delta }
            return prefix
        }

        /// Zakres po zmianie; zmiana wewnątrz zakresu rozszerza go albo zwęża, pusty po zmianie — nil.
        public func shift(_ r: Range<Int>) -> Range<Int>? {
            let lower = r.lowerBound < prefix ? r.lowerBound : (r.lowerBound >= oldEnd ? r.lowerBound + delta : prefix)
            let upper = r.upperBound <= prefix ? r.upperBound : (r.upperBound >= oldEnd ? r.upperBound + delta : prefix)
            return upper > lower ? lower..<upper : nil
        }
    }
}

// MARK: - Zakładki (PD-EDIT-011) i znaczniki kolorów (PD-EDIT-012)

/// Zakładka 0–9 na początku linii, z opcjonalną nazwą.
public struct Bookmark: Sendable, Hashable, Codable, Identifiable {
    public var number: Int
    public var offset: Int
    public var name: String?
    public var id: Int { number }
    public init(number: Int, offset: Int, name: String? = nil) { self.number = number; self.offset = offset; self.name = name }
}

/// Tło fragmentu w jednym z kolorów (numer palety 1–6).
public struct ColorMark: Sendable, Hashable, Codable {
    public var range: Range<Int>
    public var color: Int
    public init(range: Range<Int>, color: Int) { self.range = range; self.color = color }
}

public enum Bookmarks {
    static func lineStart(_ offset: Int, in text: String) -> Int {
        let ns = text as NSString
        return ns.lineRange(for: NSRange(location: min(max(0, offset), ns.length), length: 0)).location
    }

    /// Ustawia zakładkę `number` na linii pozycji (ta sama zakładka na tej samej linii — usuwa); bez numeru —
    /// pierwszy wolny numer 1…9, 0.
    public static func toggle(_ list: [Bookmark], number: Int?, at offset: Int, in text: String) -> [Bookmark] {
        let start = lineStart(offset, in: text)
        var out = list
        if let n = number {
            if out.contains(where: { $0.number == n && $0.offset == start }) { return out.filter { $0.number != n } }
            out.removeAll { $0.number == n }
            out.append(Bookmark(number: n, offset: start))
        } else if let existing = out.firstIndex(where: { $0.offset == start }) {
            out.remove(at: existing)
        } else {
            let used = Set(out.map(\.number))
            guard let n = (Array(1...9) + [0]).first(where: { !used.contains($0) }) else { return out }
            out.append(Bookmark(number: n, offset: start))
        }
        return out.sorted { $0.offset < $1.offset }
    }

    /// Następna / poprzednia zakładka względem pozycji (z zawinięciem).
    public static func next(_ list: [Bookmark], from offset: Int, forward: Bool) -> Bookmark? {
        let sorted = list.sorted { $0.offset < $1.offset }
        if forward { return sorted.first { $0.offset > offset } ?? sorted.first }
        return sorted.last { $0.offset < lineStart(offset, in: "") || $0.offset < offset } ?? sorted.last
    }
}

public enum ColorMarks {
    /// Nakłada kolor na zaznaczenie (zastępuje znaczniki, które przecina); kolor 0 — usuwa znaczniki z zakresu.
    public static func apply(_ list: [ColorMark], range: Range<Int>, color: Int) -> [ColorMark] {
        guard !range.isEmpty else { return list }
        var out: [ColorMark] = []
        for m in list {
            if m.range.upperBound <= range.lowerBound || m.range.lowerBound >= range.upperBound { out.append(m); continue }
            if m.range.lowerBound < range.lowerBound { out.append(ColorMark(range: m.range.lowerBound..<range.lowerBound, color: m.color)) }
            if m.range.upperBound > range.upperBound { out.append(ColorMark(range: range.upperBound..<m.range.upperBound, color: m.color)) }
        }
        if color > 0 { out.append(ColorMark(range: range, color: color)) }
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}

// MARK: - Wiele kursorów i zaznaczenie kolumnowe (PD-EDIT-007, PD-EDIT-023)

public enum MultiCursor {
    public static func sorted(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for r in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, r.lowerBound < last.upperBound || (r == last) {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else { out.append(r) }
        }
        return out
    }

    /// Wstawia tekst w każdym zakresie (zastępując zaznaczenie); zwraca nowy tekst i kursory za wstawionym tekstem.
    public static func insert(_ s: String, in text: String, ranges: [Range<Int>]) -> (text: String, ranges: [Range<Int>]) {
        let m = NSMutableString(string: text)
        let ins = (s as NSString).length
        var shift = 0
        var cursors: [Range<Int>] = []
        for r in sorted(ranges) {
            let lo = min(r.lowerBound + shift, m.length), hi = min(r.upperBound + shift, m.length)
            m.replaceCharacters(in: NSRange(location: lo, length: hi - lo), with: s)
            shift += ins - (hi - lo)
            cursors.append((lo + ins)..<(lo + ins))
        }
        return (m as String, cursors)
    }

    /// Backspace w każdym zakresie: zaznaczenie — usunięte, kursor — znak przed nim (nie przez koniec linii).
    public static func deleteBackward(in text: String, ranges: [Range<Int>]) -> (text: String, ranges: [Range<Int>]) {
        let m = NSMutableString(string: text)
        var shift = 0
        var cursors: [Range<Int>] = []
        for r in sorted(ranges) {
            var lo = r.lowerBound + shift
            let hi = r.upperBound + shift
            if r.isEmpty, lo > 0, m.character(at: lo - 1) != 0x0A { lo -= 1 }
            m.deleteCharacters(in: NSRange(location: lo, length: hi - lo))
            shift -= hi - lo
            cursors.append(lo..<lo)
        }
        return (m as String, cursors)
    }

    static func lines(_ text: String) -> [Range<Int>] {
        let ns = text as NSString
        var out: [Range<Int>] = []
        var i = 0
        repeat {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: i, length: 0))
            out.append(start..<contentsEnd)
            i = end
        } while i < ns.length
        if ns.length > 0, ns.character(at: ns.length - 1) == 0x0A { out.append(ns.length..<ns.length) }
        return out
    }

    static func position(_ offset: Int, in lines: [Range<Int>]) -> (line: Int, column: Int) {
        let l = lines.lastIndex { $0.lowerBound <= offset } ?? 0
        return (l, offset - lines[l].lowerBound)
    }

    /// Zaznaczenie kolumnowe między dwiema pozycjami: w każdej linii te same kolumny (krótsza linia — kursor na końcu).
    public static func column(in text: String, from a: Int, to b: Int) -> [Range<Int>] {
        let ls = lines(text)
        let p = position(a, in: ls), q = position(b, in: ls)
        let c0 = min(p.column, q.column), c1 = max(p.column, q.column)
        return (min(p.line, q.line)...max(p.line, q.line)).map { i in
            let l = ls[i]
            let lo = min(l.lowerBound + c0, l.upperBound), hi = min(l.lowerBound + c1, l.upperBound)
            return lo..<hi
        }
    }

    /// Dodatkowy kursor w linii powyżej najwyższego / poniżej najniższego kursora, w tej samej kolumnie.
    public static func addCursor(in text: String, ranges: [Range<Int>], below: Bool) -> [Range<Int>] {
        guard !ranges.isEmpty else { return ranges }
        let ls = lines(text)
        let edge = below ? ranges.map(\.upperBound).max()! : ranges.map(\.lowerBound).min()!
        let p = position(edge, in: ls)
        let target = below ? p.line + 1 : p.line - 1
        guard target >= 0, target < ls.count else { return ranges }
        let o = min(ls[target].lowerBound + p.column, ls[target].upperBound)
        return sorted(ranges + [o..<o])
    }
}

// MARK: - AutoReplace (PD-EDIT-017)

/// Skrót zastępowany tekstem po wpisaniu znaku kończącego; `|` w zamianie wskazuje kursor.
public struct AutoReplaceRule: Sendable, Hashable, Codable, Identifiable {
    public var abbreviation: String
    public var replacement: String
    public var id: String { abbreviation }
    public init(abbreviation: String, replacement: String) { self.abbreviation = abbreviation; self.replacement = replacement }

    public static let defaults: [AutoReplaceRule] = [
        AutoReplaceRule(abbreviation: "sf", replacement: "SELECT * FROM "),
        AutoReplaceRule(abbreviation: "dbo", replacement: "dbms_output.put_line(|);"),
    ]
}

public enum AutoReplace {
    /// Po wpisaniu znaku kończącego (już w tekście przed `caret`): skrót bezpośrednio przed nim → zamiana.
    /// Skrót z liter musi stać na granicy słowa; skrót zaczynający się symbolem może następować po identyfikatorze.
    public static func apply(_ rules: [AutoReplaceRule], text: String, caret: Int) -> (range: Range<Int>, replacement: String, caret: Int)? {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length, !rules.isEmpty else { return nil }
        let end = caret - 1                    // pozycja znaku kończącego
        guard let terminator = UnicodeScalar(ns.character(at: end)), !isWordChar(terminator) else { return nil }
        guard !CompletionContext.analyze(text, offset: end).inLiteralOrComment else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: end, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: end - lineStart))
        for rule in rules.sorted(by: { $0.abbreviation.count > $1.abbreviation.count }) where !rule.abbreviation.isEmpty {
            let abbr = rule.abbreviation
            guard before.lowercased().hasSuffix(abbr.lowercased()) else { continue }
            let abbrLen = (abbr as NSString).length
            let start = end - abbrLen
            let firstIsWord = abbr.unicodeScalars.first.map(isWordChar) ?? false
            if firstIsWord, start > lineStart, let prev = UnicodeScalar(ns.character(at: start - 1)), isWordChar(prev) { continue }
            let cursorMarker = rule.replacement.range(of: "|")
            let clean = rule.replacement.replacingOccurrences(of: "|", with: "")
            // Zastępujemy skrót; znak kończący zostaje tylko wtedy, gdy zamiana nie ustawia kursora.
            if let marker = cursorMarker {
                let pos = start + (String(rule.replacement[..<marker.lowerBound]) as NSString).length
                return (start..<caret, clean, pos)
            }
            let repl = clean + ns.substring(with: NSRange(location: end, length: 1))
            return (start..<caret, repl, start + (repl as NSString).length)
        }
        return nil
    }

    static func isWordChar(_ c: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(c) || c == "_" || c == "$" || c == "#"
    }
}

// MARK: - Rozmiar czcionki (PD-EDIT-021)

public enum EditorZoom {
    public static let sizes: [Double] = [8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 40]

    /// Następny rozmiar z listy w kierunku `step` (+1 / −1); 0 — domyślny 13 pt.
    public static func next(_ size: Double, step: Int) -> Double {
        if step == 0 { return 13 }
        if step > 0 { return sizes.first { $0 > size } ?? sizes.last! }
        return sizes.last { $0 < size } ?? sizes.first!
    }
}

// MARK: - Stan okna pliku (PD-EDIT-029)

/// Stan okna zapamiętany dla pliku (jak .pfi wzorca): kursor, zakładki, znaczniki, zwinięcia, zmienne, tylko do odczytu.
public struct FileWindowState: Sendable, Codable, Equatable {
    public var length: Int
    public var selection: Range<Int>
    public var bookmarks: [Bookmark]
    public var colorMarks: [ColorMark]
    public var folded: [Int]
    public var variables: [String: String]
    public var readOnly: Bool
}

/// Magazyn stanów okien w katalogu danych (`WindowState/<skrót ścieżki>.json`, uprawnienia 0600).
public final class FileStateStore: @unchecked Sendable {
    let directory: URL?

    public init(directory: URL?) { self.directory = directory }

    /// Skrót FNV-1a 64 ścieżki pliku — nazwa pliku stanu bez ujawniania ścieżki.
    static func key(for url: URL) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in url.standardizedFileURL.path.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }

    func file(for url: URL) -> URL? { directory?.appendingPathComponent(Self.key(for: url) + ".json") }

    public func save(_ state: FileWindowState, for url: URL) {
        guard let dir = directory, let f = file(for: url), let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if (try? data.write(to: f, options: .atomic)) != nil { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path) }
    }

    public func load(for url: URL) -> FileWindowState? {
        guard let f = file(for: url), let data = try? Data(contentsOf: f) else { return nil }
        return try? JSONDecoder().decode(FileWindowState.self, from: data)
    }
}

extension Workspace {
    /// Zapisuje stan okna z plikiem (przy zamknięciu i zapisie).
    public func saveWindowState(_ doc: Document) {
        guard settings.rememberWindowState, let url = doc.fileURL else { return }
        var vars: [String: String] = [:]
        for (k, v) in doc.variableValues { if case .text(let s) = v { vars[k] = s } }
        let state = FileWindowState(length: (doc.text as NSString).length, selection: doc.selectedRange, bookmarks: doc.bookmarks,
                                    colorMarks: doc.colorMarks, folded: doc.foldedStarts.sorted(), variables: vars, readOnly: doc.isReadOnly)
        fileStates.save(state, for: url)
    }

    /// Przywraca stan okna po otwarciu pliku; przy zmienionej długości pliku tylko kursor i zmienne (pozycje mogłyby nie pasować).
    public func restoreWindowState(_ doc: Document) {
        guard settings.rememberWindowState, let url = doc.fileURL, let s = fileStates.load(for: url) else { return }
        let len = (doc.text as NSString).length
        doc.selectedRange = min(s.selection.lowerBound, len)..<min(s.selection.upperBound, len)
        for (k, v) in s.variables { doc.variableValues[k] = .text(v) }
        doc.isReadOnly = s.readOnly
        guard s.length == len else { return }
        doc.bookmarks = s.bookmarks
        doc.colorMarks = s.colorMarks
        doc.foldedStarts = Set(s.folded)
    }
}

// MARK: - Otwieranie plików (PD-FILE-004)

public enum FileOpening {
    /// Rozszerzenia skryptów i programów otwierane z katalogu.
    public static let extensions: Set<String> = ["sql", "pck", "pks", "pkb", "spc", "bdy", "fnc", "prc", "trg", "typ", "tps", "tpb", "tst", "vw", "seq", "mle"]

    /// Pliki do otwarcia: pliki wprost, a z katalogów — skrypty bezpośrednio w katalogu (bez podkatalogów, w kolejności nazw).
    public static func files(from urls: [URL], limit: Int = 200) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let items = ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                    .filter { extensions.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                out += items
            } else {
                out.append(u)
            }
        }
        return Array(out.prefix(limit))
    }
}

// MARK: - Wyszukiwanie w edytorach i plikach (PD-CA-015)

public struct TextSearchOptions: Sendable, Hashable {
    public var caseSensitive = false
    public var wholeWord = false
    public var regex = false
    public init(caseSensitive: Bool = false, wholeWord: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive; self.wholeWord = wholeWord; self.regex = regex
    }
}

public enum TextSearchScope: Sendable, Hashable {
    case currentEditor, allEditors, directories([URL])
}

public enum EditorSearch {
    /// Trafienia w tekście: linia (od 1), kolumna (od 1), zakres, treść linii.
    public static func find(_ query: String, in text: String, options: TextSearchOptions) -> [(line: Int, column: Int, range: Range<Int>, text: String)] {
        guard !query.isEmpty else { return [] }
        var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = "(?<![A-Za-z0-9_$#])(?:" + pattern + ")(?![A-Za-z0-9_$#])" }
        guard let re = try? NSRegularExpression(pattern: pattern, options: options.caseSensitive ? [] : [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        var out: [(Int, Int, Range<Int>, String)] = []
        var line = 1, lineStart = 0, scanned = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.range.length > 0 {
            while scanned < m.range.location {
                if ns.character(at: scanned) == 0x0A { line += 1; lineStart = scanned + 1 }
                scanned += 1
            }
            let lr = ns.lineRange(for: NSRange(location: m.range.location, length: 0))
            let lineText = ns.substring(with: lr).trimmingCharacters(in: .newlines)
            out.append((line, m.range.location - lineStart + 1, m.range.location..<(m.range.location + m.range.length), lineText))
            if out.count >= 5000 { break }
        }
        return out
    }

    /// Wyszukiwanie w zakresie: bieżący edytor, wszystkie edytory albo pliki skryptów w katalogach (rekurencyjnie).
    @MainActor
    public static func search(_ query: String, scope: TextSearchScope, options: TextSearchOptions, in ws: Workspace) -> [UsageHit] {
        var hits: [UsageHit] = []
        func add(_ text: String, document: DocumentID?, file: URL?, title: String) {
            for h in find(query, in: text, options: options) where hits.count < 5000 {
                hits.append(UsageHit(kind: file == nil ? .document : .file, owner: nil, name: title, type: nil, line: h.line,
                                     text: h.text.trimmingCharacters(in: .whitespaces), fileURL: file, document: document, title: title))
            }
        }
        switch scope {
        case .currentEditor:
            if let d = ws.activeDocument { add(d.text, document: d.id, file: nil, title: d.title) }
        case .allEditors:
            for d in ws.documents where [.sql, .program, .test, .command].contains(d.kind) { add(d.text, document: d.id, file: nil, title: d.title) }
        case .directories(let dirs):
            let fm = FileManager.default
            var count = 0
            for dir in dirs {
                guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
                for case let url as URL in e where FileOpening.extensions.contains(url.pathExtension.lowercased()) || url.pathExtension.lowercased() == "txt" {
                    count += 1
                    guard count <= 5000, hits.count < 5000 else { break }
                    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 5_000_000 { continue }
                    guard let data = try? Data(contentsOf: url) else { continue }
                    add(TextFileCodec.decode(data).text, document: nil, file: url, title: url.lastPathComponent)
                }
            }
        }
        return hits
    }
}

// MARK: - Podpowiedzi w Command Window (PD-CMDW-012)

public enum CommandWindowAssist {
    /// Po `@`, `@@`, `START` — pliki i katalogi z katalogu bieżącego (ścieżka względna); po `CONNECT użytkownik@` —
    /// aliasy z tnsnames.ora.
    public static func complete(line text: String, offset: Int, directory: URL, aliases: [String]) -> CompletionResult? {
        let ns = text as NSString
        let o = min(offset, ns.length)
        let lineStart = ns.lineRange(for: NSRange(location: o, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: o - lineStart))
        if let m = before.firstMatch(of: #/^\s*(?i:connect|conn)\s+[^\s@]+(?:/\S*)?@(\S*)$/#) {
            let prefix = String(m.1)
            let items = aliases.filter { $0.uppercased().hasPrefix(prefix.uppercased()) }.sorted().map { CompletionItem(label: $0, kind: .databaseLink, detail: "tnsnames.ora") }
            return items.isEmpty ? nil : CompletionResult(replaceRange: (o - (prefix as NSString).length)..<o, prefix: prefix, items: items)
        }
        guard let m = before.firstMatch(of: #/^\s*(?:@@?|(?i:start)\s+)(\S*)$/#) else { return nil }
        let typed = String(m.1)
        let slash = typed.lastIndex(of: "/")
        let dirPart = slash.map { String(typed[...$0]) } ?? ""
        let namePrefix = slash.map { String(typed[typed.index(after: $0)...]) } ?? typed
        let base = dirPart.hasPrefix("/") ? URL(fileURLWithPath: dirPart) : directory.appendingPathComponent(dirPart)
        let entries = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let items = entries.compactMap { u -> CompletionItem? in
            let name = u.lastPathComponent
            guard name.lowercased().hasPrefix(namePrefix.lowercased()) else { return nil }
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir || ["sql", "pkg", "pck", "pks", "pkb", "txt"].contains(u.pathExtension.lowercased()) else { return nil }
            return CompletionItem(label: name + (isDir ? "/" : ""), kind: isDir ? .schema : .object, detail: isDir ? L10n.tr("katalog") : L10n.tr("plik"))
        }.sorted { ($0.kind == .schema ? 0 : 1, $0.label.lowercased()) < ($1.kind == .schema ? 0 : 1, $1.label.lowercased()) }
        return items.isEmpty ? nil : CompletionResult(replaceRange: (o - (namePrefix as NSString).length)..<o, prefix: namePrefix, items: items)
    }
}

// MARK: - Deklaracja w dymku (PD-CA-008)

public enum DeclarationHover {
    /// Opis deklaracji identyfikatora w pozycji (zmienna, stała, parametr, kursor, typ, wyjątek, podprogram w zasięgu).
    public static func text(at offset: Int, in text: String) -> String? {
        guard let word = TextEditing.identifier(at: offset, in: text), !word.contains("."), !Keywords.isKeyword(word) else { return nil }
        let c = CompletionContext.analyze(text, offset: offset)
        guard !c.inLiteralOrComment, let d = c.declarations.first(where: { $0.name.uppercased() == word.uppercased() }) else { return nil }
        let kind: String = switch d.kind {
        case .constant: L10n.tr("stała")
        case .parameter: L10n.tr("parametr")
        case .cursor: L10n.tr("kursor")
        case .typeDeclaration: L10n.tr("typ")
        case .exception: L10n.tr("wyjątek")
        case .procedure: L10n.tr("procedura")
        case .function: L10n.tr("funkcja")
        default: L10n.tr("zmienna")
        }
        let ns = text as NSString
        let decl = d.range.upperBound <= ns.length ? ns.substring(with: NSRange(location: d.range.lowerBound, length: min(d.range.count, 300))) : d.detail
        let firstLines = decl.components(separatedBy: "\n").prefix(4).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let line = ns.substring(to: min(d.nameOffset, ns.length)).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        return "\(kind) — " + L10n.tr("linia \(line)") + "\n" + firstLines
    }
}

extension Workspace {
    /// Podpowiedzi dla okna: w Command Window najpierw pliki po `@`/`START` i aliasy po `CONNECT …@` (PD-CMDW-012),
    /// potem Code Assistant z preferencjami (PD-CA-006, PD-CA-007).
    public func completion(for doc: Document, text: String, offset: Int) async -> CompletionResult? {
        if doc.kind == .command {
            let aliases = TNSNames.load(directories: TNSNames.searchDirectories(configured: settings.oracleNetDirectory,
                                                                               instantClientDirectory: settings.instantClientDirectory))
                .flatMap(\.aliases)
            if let r = CommandWindowAssist.complete(line: text, offset: offset, directory: sqlplusEngine(for: doc).currentDirectory, aliases: aliases) {
                return r
            }
        }
        return await CodeAssistant.complete(text: text, offset: offset, metadata: metadata(for: effectiveConnection(of: doc)), options: CompletionOptions(settings))
    }
}
