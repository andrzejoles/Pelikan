import Foundation

/// Formatowanie podczas pisania (D205): po Enter opuszczana linia jest normalizowana w swoich granicach (wielkość
/// liter, odstępy wokół operatorów i przecinków, wyrównanie do rzeki linii zaczynającej się słowem klauzuli, AND/OR,
/// słowem struktury bloku albo nawiasem zamykającym), a nowa linia dostaje wcięcie według reguł formatera. Tekst nie
/// przechodzi między liniami.
public struct EnterFormatting: Sendable, Equatable {
    /// Nowa treść opuszczanej linii — od jej początku do kursora (bez końcowych odstępów).
    public var line: String
    /// Wcięcie nowej linii; nil — formater nie ma zdania (zostaje wcięcie automatyczne edytora).
    public var indent: String?

    public init(line: String, indent: String?) {
        self.line = line
        self.indent = indent
    }
}

extension Beautifier {
    /// Słowa, przed którymi formater łamie linię w toku instrukcji (klauzule, AND/OR, ON, gałęzie) — linia od nich
    /// wyrównana jak w formatowaniu; na początku instrukcji tylko słowa struktury bloku (zwykła instrukcja zachowuje
    /// wcięcie użytkownika).
    static let enterRealignWords: Set<String> = Formatter.clauseWords.union(["ON", "ELSIF", "EXCEPTION", "BEGIN"])
    static let enterBlockWords: Set<String> = ["END", "ELSE", "ELSIF", "EXCEPTION", "BEGIN", "WHEN"]
    /// Polecenie dłuższe (linie od jego początku do kursora) — tylko wielkość liter i wcięcie automatyczne edytora.
    public static let enterLineLimit = 2000
    /// Linie po kursorze brane pod uwagę (szerokość rzeki, długość warunku i list).
    static let enterLookahead = 200

    /// Formatowanie przy Enter wciśniętym w `caret` (bez zaznaczenia) w tekście sprzed Enter. `contextStart` — początek
    /// polecenia skryptu zawierającego linię kursora albo wcześniejszy początek polecenia (z pamięci podziału edytora,
    /// `StatementStartMemory`); formater przechodzi tylko od niego do nowej linii. nil — bez formatowania (linia w
    /// komentarzu blokowym, literale, kompilacji warunkowej, poleceniu SQL*Plus, kodzie Java/JavaScript, regionie bez
    /// formatowania, Enter wewnątrz literału albo komentarza): zwykły Enter. Linia z niedomkniętym nawiasem — tylko
    /// wielkość liter. Zmieniona linia musi przejść `verifier` (domyślnie `verify`: te same tokeny polecenia od jego
    /// początku do kursora przed zmianą i po niej — w kontekście, bo podział na polecenia zależy od tekstu przed linią)
    /// — inaczej zostaje bez zmian.
    public static func formatOnEnter(_ text: String, caret: Int, contextStart: Int = 0,
                                     options: BeautifierOptions = BeautifierOptions(), tabWidth: Int = 4,
                                     lineLimit: Int = enterLineLimit,
                                     verifier: (String, String) throws -> Void = { try Beautifier.verify(original: $0, formatted: $1) })
        -> EnterFormatting? {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        var lineEnd = caret
        while lineEnd < ns.length, ns.character(at: lineEnd) != 0x0A, ns.character(at: lineEnd) != 0x0D { lineEnd += 1 }
        let left = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let rest = String(ns.substring(with: NSRange(location: caret, length: lineEnd - caret)).drop { $0 == " " || $0 == "\t" })
        var start = min(max(0, contextStart), lineStart)
        var prefix = ""
        var newlines = 0
        for p in start..<lineStart where ns.character(at: p) == 0x0A { newlines += 1 }
        if newlines > lineLimit {
            // Długie polecenie: w ciele pakietu albo typu — kontekst od początku bieżącego podprogramu (z nagłówkiem
            // zastępczym); inaczej tylko wielkość liter, wcięcie automatyczne edytora.
            let head = ns.substring(with: NSRange(location: start, length: caret - start))
            let lexer = Lexer(head)
            if lexer.scan(range: 0..<lexer.text.count, state: .normal, { _ in }) != .normal { return nil }
            let toks = Formatter.tokens(head as NSString, from: 0)
            let from = lineStart - start
            if toks.contains(where: { $0.start < from && $0.end > from }) { return nil }
            if let sub = subprogramContext(toks, text: ns, offset: start, before: lineStart, lineLimit: lineLimit) {
                start = sub.start
                prefix = sub.header
            } else {
                return caseOnlyLine(left, tokens: toks.filter { $0.start >= from }.map { t in
                    Formatter.Tok(kind: t.kind, start: t.start - from, end: t.end - from, text: t.text, upper: t.upper, newlines: t.newlines)
                }, options: options, before: (head as NSString).substring(to: from), verifier: verifier)
            }
        }
        // Kontekst po Enter: polecenie do nowej linii (z resztą linii po kursorze) i kilkaset linii dalej.
        var end = lineEnd, lines = 0
        while end < ns.length, lines < enterLookahead, end - lineEnd < 40_000 {
            if ns.character(at: end) == 0x0A { lines += 1 }
            end += 1
        }
        let before = prefix + ns.substring(with: NSRange(location: start, length: caret - start))
        let context = before + "\n" + rest + ns.substring(with: NSRange(location: lineEnd, length: end - lineEnd))
        let shift = (prefix as NSString).length - start
        let leftFrom = lineStart + shift, leftTo = caret + shift
        let restFrom = leftTo + 1, restTo = restFrom + (rest as NSString).length
        let width = options.useTabs ? max(1, options.indent) : max(1, tabWidth)
        var f = Formatter(source: context as NSString, options: options)
        let toks = f.toks
        // Linia zaczyna się albo kursor stoi w komentarzu blokowym, literale, identyfikatorze w cudzysłowie.
        if toks.contains(where: { $0.start < leftFrom && $0.end > leftFrom || $0.start < leftTo && $0.end > leftTo }) { return nil }
        let leftIdx = toks.indices.filter { toks[$0].start >= leftFrom && toks[$0].end <= leftTo }
        let restIdx = toks.indices.filter { toks[$0].start >= restFrom && toks[$0].start < restTo }
        if (leftIdx + restIdx).contains(where: { toks[$0].kind == .directive }) { return nil }
        let ctx = context as NSString
        func sourceText(_ from: Int, _ to: Int) -> String { ctx.substring(with: NSRange(location: from, length: max(0, to - from))) }

        let lastBefore = leftIdx.last ?? (toks.lastIndex { $0.end <= leftFrom } ?? -1)
        var trace = Formatter.Trace(placed: Array(repeating: nil, count: toks.count))
        trace.watch = Set([leftIdx.first, restIdx.first].compactMap { $0 })
        trace.after = lastBefore
        trace.stop = restIdx.first ?? lastBefore
        f.trace = trace
        f.runTraced()
        guard let tr = f.trace else { return nil }
        // Fragmenty kopiowane bez zmian (SQL*Plus, Java/JavaScript, `$IF … $END`, regiony bez formatowania).
        if tr.raw.contains(where: { $0.lowerBound < max(restTo, leftTo + 1) && $0.upperBound > leftFrom }) { return nil }
        let placed = tr.placed

        func column(_ pos: Int) -> Int {
            var p = pos
            while p > 0, ctx.character(at: p - 1) != 0x0A { p -= 1 }
            var c = 0
            for q in p..<pos { c = ctx.character(at: q) == 0x09 ? (c / width + 1) * width : c + 1 }
            return c
        }
        func firstOnLine(_ k: Int) -> Bool {
            var p = toks[k].start
            while p > 0, ctx.character(at: p - 1) == 0x20 || ctx.character(at: p - 1) == 0x09 { p -= 1 }
            return p == 0 || ctx.character(at: p - 1) == 0x0A
        }
        func pad(_ n: Int) -> String {
            if options.useTabs, options.indent > 0 { return String(repeating: "\t", count: n / options.indent) + String(repeating: " ", count: n % options.indent) }
            return String(repeating: " ", count: n)
        }
        /// Kotwica wyrównania dla ramki otwartej tokenem `k`: sam token, gdy formater zaczyna od niego linię (słowo
        /// polecenia — rzeka względem jego miejsca w dokumencie), inaczej najbliższy wcześniejszy token, od którego
        /// linię zaczyna i formater, i dokument (np. FOR dla LOOP, PROCEDURE dla IS) — układ obu w tym miejscu zgodny.
        func lineAnchor(_ k: Int) -> Int? {
            guard k >= 0 else { return nil }
            if placed[k]?.startsLine == true { return k }
            var j = k
            while j >= 0, k - j < 5000 {
                if placed[j]?.startsLine == true, firstOnLine(j) { return j }
                j -= 1
            }
            return nil
        }

        // Opuszczana linia.
        var depth = 0
        for k in leftIdx { if toks[k].kind == .leftParen { depth += 1 } else if toks[k].kind == .rightParen { depth -= 1 } }
        let caseOnly = depth > 0
        let sourceIndent = leftIdx.first.map { sourceText(leftFrom, toks[$0].start) } ?? ""
        var indentText = sourceIndent
        var indentWidth = leftIdx.first.map { column(toks[$0].start) } ?? 0
        if !caseOnly, let first = leftIdx.first, let p = placed[first], p.startsLine, realigns(first, toks: toks, trace: tr),
           let frame = tr.frame[first], frame.opener >= 0, frame.opener < first {
            var target: Int?
            if frame.isSQL {
                // Instrukcja SQL: względem najbliższej wcześniejszej linii tej instrukcji (na tym samym poziomie nawiasów)
                // zaczynającej się słowem klauzuli, inaczej względem słowa otwierającego w dokumencie — jako kolumny
                // instrukcji (formater przesuwa je w prawo do rzeki, np. `  WITH`; linii instrukcji edytor nie przesuwa).
                var level = 0
                var j = first - 1
                while j > frame.opener, target == nil {
                    if toks[j].kind == .rightParen { level += 1 } else if toks[j].kind == .leftParen { level -= 1 }
                    if level == 0, toks[j].isWord, enterRealignWords.contains(toks[j].upper), let pj = placed[j], pj.startsLine, firstOnLine(j) {
                        target = column(toks[j].start) + p.column - pj.column
                    }
                    j -= 1
                }
                if target == nil, toks[frame.opener].start < leftFrom, let po = placed[frame.opener] {
                    // Słowo otwierające przesunięte w dokumencie jak przez formater (kod sformatowany) — względem niego;
                    // nieprzesunięte (wpisane w kolumnie instrukcji) — względem kolumny instrukcji.
                    let a = column(toks[frame.opener].start)
                    var shifted = !po.startsLine || po.column == frame.column
                    if !shifted {
                        var r = frame.opener - 1
                        while r >= 0, !(placed[r]?.startsLine == true && firstOnLine(r)) { r -= 1 }
                        shifted = r >= 0 ? a - column(toks[r].start) == po.column - placed[r]!.column : a == po.column
                    }
                    target = a + p.column - (shifted ? po.column : frame.column)
                }
            } else if let anchor = lineAnchor(frame.opener), anchor < first, toks[anchor].start < leftFrom, let pa = placed[anchor] {
                target = column(toks[anchor].start) + p.column - pa.column
            }
            if let target {
                indentWidth = max(0, target)
                indentText = pad(indentWidth)
            }
        }
        func isPlainOperatorOrComma(_ k: Int) -> Bool {
            toks[k].kind == .comma || (toks[k].kind == .operator || toks[k].kind == .slash) && toks[k].text != ":=" && toks[k].text != "=>"
        }
        func gap(_ a: Int, _ b: Int) -> String {
            let src = sourceText(toks[a].end, toks[b].start)
            let trivia: Set<TokenKind> = [.lineComment, .blockComment, .hint]
            if caseOnly || trivia.contains(toks[a].kind) || trivia.contains(toks[b].kind) { return src }
            guard let pa = placed[a], let pb = placed[b] else { return src }
            if pa.line == pb.line, pb.startsLine == false {
                let g = pb.column - (pa.column + pa.text.count)
                // Wyrównanie wpisane przez użytkownika (deklaracje, `:=`, `=>`) zostaje — poza operatorami i przecinkami.
                if g == 1, src.count > 1, !isPlainOperatorOrComma(a), !isPlainOperatorOrComma(b) { return src }
                return String(repeating: " ", count: max(0, g))
            }
            // Formater złamałby tu linię — w linii: odstęp jak w formatowaniu bez złamania.
            if src.isEmpty, !separable(toks[a].kind, toks[a].text, toks[b].kind, toks[b].text) { return "" }
            if [.comma, .semicolon, .dot].contains(toks[b].kind) || toks[a].kind == .dot { return "" }
            if toks[a].kind == .leftParen || toks[b].kind == .rightParen { return options.spaceInsideParentheses ? " " : "" }
            return " "
        }
        var body = ""
        for (n, k) in leftIdx.enumerated() {
            if n > 0 { body += gap(leftIdx[n - 1], k) }
            body += toks[k].isWord ? placed[k]?.text ?? toks[k].text : toks[k].text
        }
        var line = leftIdx.isEmpty ? "" : indentText + body
        if line != left {
            let head = sourceText(0, leftFrom)
            do { try verifier(head + left, head + line) } catch {
                line = left
                indentWidth = leftIdx.first.map { column(toks[$0].start) } ?? 0
            }
        }

        // Nowa linia: kolumna formatera względem ostatniej wcześniejszej linii, którą formater też zaczyna od jej
        // pierwszego tokenu (zwykle opuszczanej) — styl wcięć użytkownika zostaje, formater dodaje swoje kroki.
        var indent: String?
        if leftIdx.first.map({ placed[$0]?.startsLine == true }) ?? true {
            let target: Int?
            if let r = restIdx.first {
                target = placed[r].flatMap { $0.startsLine ? $0.column : nil }
            } else {
                target = tr.state?.nextColumn
            }
            if let target {
                var anchor: Int?
                var k = lastBefore
                while k >= 0, anchor == nil, lastBefore - k < 2000 {
                    if placed[k]?.startsLine == true, firstOnLine(k) { anchor = k }
                    k -= 1
                }
                if let a = anchor, let pa = placed[a] {
                    let base = a == leftIdx.first && line != left ? indentWidth : column(toks[a].start)
                    indent = pad(max(0, base + target - pa.column))
                } else if lastBefore < 0 {
                    indent = pad(target)
                }
            }
        }
        return EnterFormatting(line: line, indent: indent)
    }

    /// Ciało pakietu albo typu dłuższe niż limit: początek bieżącego podprogramu najwyższego poziomu (linia zaczynająca
    /// się od PROCEDURE/FUNCTION — i MEMBER, STATIC… w typie — z najmniejszym wcięciem) i nagłówek zastępczy, z którym
    /// formater widzi podprogram jak w ciele (poziom wcięcia względny — kotwice to linie dokumentu). `toks` — tokeny
    /// tekstu od `offset`.
    static func subprogramContext(_ toks: [Formatter.Tok], text ns: NSString, offset: Int, before lineStart: Int,
                                  lineLimit: Int) -> (start: Int, header: String)? {
        let words = toks.prefix(8).filter(\.isWord).map(\.upper)
        guard words.first == "CREATE" else { return nil }
        let unit = words.firstIndex { $0 == "PACKAGE" || $0 == "TYPE" }
        guard let u = unit, u + 1 < words.count, words[u + 1] == "BODY" else { return nil }
        let typeBody = words[u] == "TYPE"
        let starters: Set<String> = typeBody ? ["PROCEDURE", "FUNCTION", "MEMBER", "STATIC", "CONSTRUCTOR", "MAP", "ORDER", "OVERRIDING", "FINAL"]
            : ["PROCEDURE", "FUNCTION"]
        var candidates: [(start: Int, indent: Int)] = []
        for t in toks where t.isWord && starters.contains(t.upper) && offset + t.start <= lineStart {
            let ls = ns.lineRange(for: NSRange(location: offset + t.start, length: 0)).location
            let lead = ns.substring(with: NSRange(location: ls, length: offset + t.start - ls))
            guard lead.allSatisfy({ $0 == " " || $0 == "\t" }) else { continue }
            candidates.append((ls, lead.count))
        }
        guard let top = candidates.map(\.indent).min(), let c = candidates.last(where: { $0.indent == top }) else { return nil }
        var newlines = 0
        for p in c.start..<lineStart where ns.character(at: p) == 0x0A { newlines += 1 }
        guard newlines <= lineLimit else { return nil }
        return (c.start, "CREATE OR REPLACE \(typeBody ? "TYPE" : "PACKAGE") BODY pelikan_context IS\n")
    }

    /// Linia bez formatera: tylko wielkość liter według rodzaju tokenu (słowo po kropce bez zmian), bez końcowych
    /// odstępów. `tokens` — tokeny linii (położenia względem jej początku), `before` — polecenie przed linią (weryfikacja).
    static func caseOnlyLine(_ left: String, tokens: [Formatter.Tok], options: BeautifierOptions,
                             before: String, verifier: (String, String) throws -> Void) -> EnterFormatting {
        var line = left as NSString
        for (n, t) in tokens.enumerated().reversed() where t.isWord && (n == 0 || tokens[n - 1].kind != .dot) && t.end <= line.length {
            let rule = t.kind == .keyword ? options.keywordCase : options.identifierCase
            line = line.replacingCharacters(in: NSRange(location: t.start, length: t.end - t.start), with: Formatter.apply(rule, to: t)) as NSString
        }
        var out = String((line as String).reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        if out != left, (try? verifier(before + left, before + out)) == nil { out = left }
        return EnterFormatting(line: out, indent: nil)
    }

    /// Czy linię zaczynającą się od tokenu `k` wyrównać do układu formatera.
    static func realigns(_ k: Int, toks: [Formatter.Tok], trace: Formatter.Trace) -> Bool {
        let t = toks[k]
        let atStatementStart = trace.statementStart[k] ?? true
        if t.kind == .rightParen || t.kind == .comma { return !atStatementStart }
        guard t.isWord else { return false }
        return atStatementStart ? enterBlockWords.contains(t.upper) : enterRealignWords.contains(t.upper)
    }
}

extension Formatter {
    /// Przebieg do tokenu `trace.stop` z zapisem położenia tokenów i stanu po tokenie `trace.after`.
    mutating func runTraced() {
        while i < toks.count, i <= trace!.stop { step() }
        if trace!.state == nil { trace!.state = Trace.State(nextColumn: nextLineColumn()) }
    }

    /// Wywoływane na początku kroku przy śledzeniu.
    mutating func observe() {
        if trace!.state == nil, i > trace!.after { trace!.state = Trace.State(nextColumn: nextLineColumn()) }
        if trace!.watch.contains(i) {
            trace!.frame[i] = frames.last.map { Trace.FrameInfo(opener: $0.opener, isSQL: $0.kind == .sql, column: $0.column) }
            trace!.statementStart[i] = statementStart
        }
    }

    /// Kolumna następnej linii po ostatnim przetworzonym tokenie: zaległe złamanie (lista po przecinku, treść bloku,
    /// następna instrukcja), w SQL po zakończonym elemencie — kolumna instrukcji (następna klauzula, wyrównywana
    /// potem do rzeki), w toku elementu — kolumna elementów; w nawiasie — za nawiasem; w PL/SQL — kontynuacja instrukcji.
    func nextLineColumn() -> Int {
        if let p = pendingBreak { return p }
        let last = i > 0 && i <= toks.count ? toks[i - 1] : nil
        guard let f = frames.last else { return statementStart || last == nil ? indentColumns(level) : curIndentColumns + options.indent }
        switch f.kind {
        case .sql:
            guard let last, Self.completesItem(last) else { return listColumn(f) }
            if options.commaBefore, Self.listClauses.contains(f.clause) { return max(0, listColumn(f) - 2) }
            return f.column
        case .paren:
            // Linia kończy się „(”: treść (podzapytanie, długa lista) od nowej linii — wcięta jak podzapytanie.
            guard last?.kind == .leftParen, options.subqueryLayout == .indented else { return f.column }
            let outer = frames.count > 1 ? frames[frames.count - 2] : nil
            let base = outer.map { $0.kind == .sql ? listColumn($0) : $0.kind == .paren ? $0.column : curIndentColumns } ?? curIndentColumns
            return base + options.indent
        case .caseExpr:
            // Linia złamana w wyrażeniu CASE — gałęzie wieloliniowo, wcięte pod CASE.
            return f.column + options.indent
        case .unit, .declare, .block, .exception, .ifStmt, .loop, .caseStmt, .branch:
            return statementStart ? indentColumns(level) : curIndentColumns + options.indent
        }
    }

    static let itemValues: Set<String> = [
        "NULL", "TRUE", "FALSE", "SYSDATE", "SYSTIMESTAMP", "USER", "ROWNUM", "ROWID", "LEVEL", "ASC", "DESC", "FIRST", "LAST",
        "ONLY", "CURRENT_DATE", "CURRENT_TIMESTAMP", "LOCALTIMESTAMP", "SQLCODE", "SQLERRM",
    ]

    /// Token kończy element (nazwa, literał, nawias zamykający, wartość) — następna linia to raczej nowa klauzula.
    static func completesItem(_ t: Tok) -> Bool {
        switch t.kind {
        case .identifier, .quotedIdentifier, .number, .string, .rightParen, .bindVariable, .substitution: true
        case .keyword: itemValues.contains(t.upper)
        default: false
        }
    }
}
