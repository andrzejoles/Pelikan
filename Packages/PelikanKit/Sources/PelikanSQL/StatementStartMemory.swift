import Foundation

/// Kontekst formatowania linii przy Enter (D205): od którego miejsca dokumentu formater przechodzi tekst (z nagłówkiem
/// zastępczym, gdy kontekst zaczyna się od podprogramu w długim ciele pakietu albo typu) i czy w ogóle formatuje.
public struct EnterContext: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        /// Formatowanie w kontekście polecenia (albo podprogramu).
        case format
        /// Długie polecenie bez podprogramu w zasięgu — tylko wielkość liter linii.
        case caseOnly
        /// Bez formatowania: linia w literale albo komentarzu, w regionie bez formatowania, w kompilacji warunkowej,
        /// w kodzie Java/JavaScript.
        case none
    }

    public var start: Int
    public var header: String
    public var mode: Mode

    public init(start: Int, header: String = "", mode: Mode = .format) {
        self.start = start
        self.header = header
        self.mode = mode
    }
}

/// Pamięć podziału skryptu dla formatowania przy Enter (D205): początki poleceń wyznaczone podziałem (`ScriptSplitter`,
/// tryb Command Window — jak formater) i punkty kontrolne w blokach PL/SQL (początki linii podprogramów i co 200 linii,
/// ze stanem regionów bez formatowania i kompilacji warunkowej oraz jednostki CREATE … BODY, w której leżą) zostają
/// ważne, dopóki tekst przed nimi się nie zmienia — podział i leksowanie idą od początku tekstu, więc zmiana dalej nie
/// zmienia niczego przed nią. Enter leksuje tylko od ostatniego ważnego punktu do linii kursora, a nie cały plik.
public struct StatementStartMemory: Sendable, Equatable {
    /// Region bez formatowania (`-- NoFormat Start`, `-- @formatter:off`) i głębokość `$IF … $END` w danym miejscu.
    struct Region: Sendable, Equatable {
        var noFormat = false
        var ifDepth = 0
        var open: Bool { noFormat || ifDepth > 0 }
    }

    /// Jednostka CREATE … PACKAGE|TYPE [BODY]: ciało (podprogramy jako punkty kontrolne), typ, wcięcie podprogramów
    /// najwyższego poziomu.
    struct Unit: Sendable, Equatable {
        var body: Bool
        var typeBody: Bool
        var topIndent: Int?
    }

    struct Checkpoint: Sendable, Equatable {
        /// Początek linii (stan leksera — zwykły tekst).
        var position: Int
        /// Początek polecenia, w którym leży.
        var statement: Int
        var region: Region
        var unit: Unit?
        /// Linia zaczyna podprogram najwyższego poziomu ciała.
        var subprogram: Bool
    }

    /// Znane początki poleceń (UTF-16), rosnąco.
    public private(set) var starts: [Int] = []
    var regions: [Int: Region] = [:]
    var checkpoints: [Checkpoint] = []
    /// Łączna długość tekstu przeleksowanego przez pamięć (UTF-16) — test, że Enter nie leksuje całego pliku.
    public private(set) var scannedLength = 0

    public init() {}

    /// Zmiana tekstu od `location`: początki i punkty kontrolne od tego miejsca przestają obowiązywać.
    public mutating func invalidate(from location: Int) {
        if let k = starts.firstIndex(where: { $0 >= location }) {
            for s in starts[k...] { regions[s] = nil }
            starts.removeSubrange(k...)
        }
        if let k = checkpoints.firstIndex(where: { $0.position >= location }) { checkpoints.removeSubrange(k...) }
    }

    /// Początek polecenia, w którym leży linia zaczynająca się w `lineStart` (albo sam `lineStart`, gdy poprzednie
    /// polecenie skończyło się przed nią).
    public mutating func contextStart(forLineAt lineStart: Int, in text: NSString) -> Int {
        statement(forLineAt: lineStart, in: text).statement
    }

    /// Kontekst formatowania linii zaczynającej się w `lineStart`: polecenie nie dłuższe niż `lineLimit` linii przed
    /// nią — od jego początku; dłuższe ciało pakietu albo typu — od początku bieżącego podprogramu najwyższego poziomu
    /// (z nagłówkiem zastępczym); inne długie — tylko wielkość liter.
    public mutating func context(forLineAt lineStart: Int, in text: NSString, lineLimit: Int = Beautifier.enterLineLimit) -> EnterContext {
        let s = statement(forLineAt: lineStart, in: text)
        if !s.normal || s.region.open || Self.isRawUnit(at: s.statement, in: text) { return EnterContext(start: lineStart, mode: .none) }
        if Self.lines(from: s.statement, to: lineStart, in: text, limit: lineLimit) <= lineLimit { return EnterContext(start: s.statement) }
        if let cp = checkpoints.last(where: { $0.subprogram && $0.statement == s.statement && $0.position <= lineStart }),
           let unit = cp.unit, unit.body, Self.lines(from: cp.position, to: lineStart, in: text, limit: lineLimit) <= lineLimit {
            return EnterContext(start: cp.position, header: "CREATE OR REPLACE \(unit.typeBody ? "TYPE" : "PACKAGE") BODY pelikan_context IS\n")
        }
        return EnterContext(start: lineStart, mode: .caseOnly)
    }

    /// Polecenie linii, stan regionów i leksera na jej początku: od ostatniego ważnego punktu kontrolnego (blok PL/SQL
    /// kończy tylko `/` sam w linii) albo podziałem od ostatniego znanego początku polecenia.
    mutating func statement(forLineAt lineStart: Int, in text: NSString) -> (statement: Int, region: Region, normal: Bool) {
        if let k = checkpoints.lastIndex(where: { $0.position <= lineStart }) {
            let cp = checkpoints[k]
            var scan = Scan(statement: cp.statement, region: cp.region, unit: cp.unit, checkpointsFrom: cp.position + 1, plsql: true)
            scan.run(text, from: cp.position, to: lineStart, expectSubprogram: cp.subprogram)
            scannedLength += lineStart - cp.position
            if !scan.ended, !scan.stale {
                merge(scan.checkpoints)
                return (cp.statement, scan.region, scan.normal)
            }
            checkpoints.removeSubrange(k...)
        }
        let base = starts.last { $0 <= lineStart } ?? 0
        guard base < lineStart else { return (base, regions[base] ?? Region(), true) }
        let chunk = text.substring(with: NSRange(location: base, length: lineStart - base))
        let parts = ScriptSplitter.split(chunk, mode: .commandWindow)
        for p in parts where base + p.start > (starts.last ?? -1) { starts.append(base + p.start) }
        // Polecenie niezakończone przed linią (blok PL/SQL, SQL bez średnika) — linia jest jego dalszym ciągiem.
        let open = parts.last.map { $0.terminator == .endOfText } ?? false
        let statement = open ? base + parts.last!.start : lineStart
        var scan = Scan(statement: statement, region: regions[base] ?? Region(), unit: nil, checkpointsFrom: statement,
                        plsql: open && parts.last!.isPLSQL)
        scan.statementStarts = Set(parts.map { base + $0.start })
        scan.run(text, from: base, to: lineStart, expectSubprogram: false)
        scannedLength += lineStart - base
        for (pos, r) in scan.regionsAt where regions[pos] == nil { regions[pos] = r }
        merge(scan.checkpoints)
        return (statement, scan.region, scan.normal)
    }

    mutating func merge(_ new: [Checkpoint]) {
        for c in new where c.position > (checkpoints.last?.position ?? -1) { checkpoints.append(c) }
    }

    /// Liczba linii między pozycjami (najwyżej `limit + 1` — liczenie od końca).
    static func lines(from a: Int, to b: Int, in text: NSString, limit: Int) -> Int {
        var n = 0, p = b
        while p > a, n <= limit {
            p -= 1
            if text.character(at: p) == 0x0A { n += 1 }
        }
        return n
    }

    /// Polecenie CREATE … JAVA albo MLE (kod Java/JavaScript — formater kopiuje go bez zmian).
    static func isRawUnit(at start: Int, in text: NSString) -> Bool {
        let head = text.substring(with: NSRange(location: start, length: min(400, text.length - start)))
        let lexer = Lexer(head)
        let words = lexer.tokenize().filter { $0.kind == .keyword || $0.kind == .identifier }.prefix(8).map { lexer.string($0).uppercased() }
        guard words.first == "CREATE" else { return false }
        return words.contains("JAVA") || words.contains("MLE")
    }

    /// Przejście leksera po fragmencie: regiony, jednostki CREATE … BODY, punkty kontrolne, `/` sam w linii.
    struct Scan {
        var statement: Int
        var region: Region
        var unit: Unit?
        var checkpointsFrom: Int
        var plsql: Bool
        var statementStarts: Set<Int> = []
        var regionsAt: [Int: Region] = [:]
        var checkpoints: [Checkpoint] = []
        var ended = false
        var stale = false
        var normal = true

        static let packageStarters: Set<String> = ["PROCEDURE", "FUNCTION"]
        static let typeStarters: Set<String> = ["PROCEDURE", "FUNCTION", "MEMBER", "STATIC", "CONSTRUCTOR", "MAP", "ORDER", "OVERRIDING", "FINAL"]
        static let createModifiers: Set<String> = ["OR", "REPLACE", "EDITIONABLE", "NONEDITIONABLE", "FORCE", "NOFORCE"]

        mutating func run(_ text: NSString, from: Int, to: Int, expectSubprogram: Bool) {
            guard from < to else { return }
            let chunk = text.substring(with: NSRange(location: from, length: to - from))
            let lexer = Lexer(chunk)
            let utf = lexer.text
            var lineStart = 0
            var firstOnLine = true
            var lines = 0
            var header: [String]?
            /// ORDER/MAP na początku linii w ciele typu — podprogram tylko, gdy następne słowo to MEMBER.
            var pending: (position: Int, indent: Int)?
            var checkedFirst = !expectSubprogram
            for s in statementStarts where s == from { regionsAt[s] = region }
            let state = lexer.scan(range: 0..<utf.count, state: .normal) { t in
                if ended || stale { return }
                if t.kind == .newline {
                    lineStart = t.end
                    firstOnLine = true
                    lines += 1
                    let pos = from + lineStart
                    if statementStarts.contains(pos) { regionsAt[pos] = region }
                    if plsql, lines % 200 == 0, pos >= checkpointsFrom, pos < to {
                        checkpoints.append(Checkpoint(position: pos, statement: statement, region: region, unit: unit, subprogram: false))
                    }
                    return
                }
                if t.kind == .whitespace { return }
                let pos = from + t.start
                if statementStarts.contains(pos) {
                    if regionsAt[pos] == nil { regionsAt[pos] = region }
                    // Nowe polecenie — jednostka poprzedniego się skończyła (nagłówek nowej ustawi ją od nowa).
                    unit = nil
                    header = nil
                    pending = nil
                }
                let first = firstOnLine
                firstOnLine = false
                let word = t.kind == .keyword || t.kind == .identifier ? lexer.string(t).uppercased() : ""
                if !checkedFirst {
                    checkedFirst = true
                    if !(Self.packageStarters.union(Self.typeStarters)).contains(word) { stale = true; return }
                }
                switch t.kind {
                case .lineComment:
                    let m = lexer.string(t).uppercased().replacingOccurrences(of: " ", with: "")
                    if m.hasPrefix("--NOFORMATSTART") || m.hasPrefix("--@FORMATTER:OFF") { region.noFormat = true }
                    if m.hasPrefix("--NOFORMATEND") || m.hasPrefix("--@FORMATTER:ON") { region.noFormat = false }
                    return
                case .blockComment, .hint:
                    return
                case .directive:
                    let d = lexer.string(t).uppercased()
                    if d == "$IF" || d == "$ERROR" { region.ifDepth += 1 }
                    if d == "$END" { region.ifDepth = max(0, region.ifDepth - 1) }
                case .slash where first:
                    // `/` sam w linii kończy blok PL/SQL.
                    var p = t.end
                    while p < utf.count, utf[p] == 0x20 || utf[p] == 0x09 { p += 1 }
                    if plsql, pos > statement, p >= utf.count || utf[p] == 0x0A || utf[p] == 0x0D { ended = true; return }
                default:
                    break
                }
                // Nagłówek jednostki: CREATE [OR REPLACE …] PACKAGE|TYPE [BODY] (słowa bez komentarzy).
                if word == "CREATE", first {
                    header = ["CREATE"]
                } else if var h = header {
                    if word.isEmpty || h.count > 8 {
                        header = nil
                        if word.isEmpty, h.count > 1 { unit = nil }
                    } else {
                        h.append(word)
                        header = h
                        if let u = h.firstIndex(where: { $0 == "PACKAGE" || $0 == "TYPE" }) {
                            if h.count > u + 1 {
                                unit = Unit(body: h[u + 1] == "BODY", typeBody: h[u] == "TYPE")
                                header = nil
                            }
                        } else if !Self.createModifiers.contains(word) {
                            unit = nil
                            header = nil
                        }
                    }
                }
                // Podprogram najwyższego poziomu ciała: punkt kontrolny na początku jego linii.
                func subprogram(at pos: Int, indent: Int) {
                    guard var u = unit else { return }
                    if u.topIndent.map({ indent < $0 }) ?? true { u.topIndent = indent; unit = u }
                    if indent == u.topIndent, pos >= checkpointsFrom, pos < to {
                        checkpoints.append(Checkpoint(position: pos, statement: statement, region: region, unit: u, subprogram: true))
                    }
                }
                if let p = pending {
                    pending = nil
                    if word == "MEMBER" { subprogram(at: p.position, indent: p.indent) }
                }
                if first, plsql, let u = unit, u.body, (u.typeBody ? Self.typeStarters : Self.packageStarters).contains(word) {
                    if word == "ORDER" || word == "MAP" {
                        pending = (from + lineStart, t.start - lineStart)
                    } else {
                        subprogram(at: from + lineStart, indent: t.start - lineStart)
                    }
                }
            }
            normal = state == .normal && !stale
        }
    }
}
