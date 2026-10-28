import Foundation
import PelikanDB
import PelikanSQL

/// Jednostka programu w pliku (UG 4.1): `CREATE OR REPLACE … /` — specyfikacja, ciało, funkcja, procedura, typ, wyzwalacz.
public struct ProgramUnit: Sendable, Hashable, Identifiable {
    public var type: DBObjectType
    public var owner: String?
    public var name: String
    /// Zakres polecenia w tekście (UTF-16) i numer pierwszej linii (od 0).
    public var range: Range<Int>
    public var line: Int
    public var text: String
    /// Linia dokumentu (od 0) i kolumna (UTF-16, od 0) słowa typu: Oracle zapisuje źródło od niego (`PACKAGE BODY …`),
    /// więc linia 1 ALL_SOURCE/ALL_ERRORS to ta linia, nie linia CREATE — przy `CREATE OR REPLACE` w osobnej linii albo
    /// komentarzu przed typem różnią się (WS2-10).
    public var sourceLine = 0
    public var sourceColumn = 0
    public var id: String { "\(type.rawValue):\(owner ?? "").\(name)@\(range.lowerBound)" }

    /// Linia i kolumna dokumentu (od 1) dla pozycji w źródle obiektu w bazie (ALL_SOURCE, ALL_ERRORS, DBMS_DEBUG — od 1).
    public func documentPosition(line l: Int, column c: Int = 1) -> (line: Int, column: Int) {
        (sourceLine + l, l == 1 ? c + sourceColumn : c)
    }

    /// Nazwa karty jednostki.
    public var tabTitle: String {
        let base = name.lowercased()
        switch type {
        case .package, .type: return base + " (" + L10n.tr("specyfikacja") + ")"
        case .packageBody, .typeBody: return base + " (" + L10n.tr("ciało") + ")"
        default: return base
        }
    }
}

/// Komunikat kompilacji: błąd, ostrzeżenie (PLW), podpowiedź; pozycja w dokumencie (linia i kolumna od 1).
public struct CompileMessage: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Hashable { case error, warning, hint }
    public var severity: Severity
    public var unit: String
    public var line: Int
    public var column: Int
    public var text: String
    public var id: String { "\(unit):\(line):\(column):\(text.prefix(40))" }
}

public enum ProgramCompiler {
    /// Jednostki programu w tekście (D192): polecenia CREATE PL/SQL — zakończone `/` w osobnej linii albo bez niego
    /// (następna jednostka zaczyna się od nagłówka CREATE na początku linii).
    public static func units(in text: String) -> [ProgramUnit] {
        programStatements(text).compactMap { s in
            guard let h = headerTokens(s.text) else { return nil }
            var u = ProgramUnit(type: h.type, owner: h.owner, name: h.name, range: s.start..<s.end, line: s.line, text: s.text)
            u.sourceLine = s.line
            // Java i MLE: ALL_SOURCE zawiera sam kod, bez nagłówka — zostaje linia CREATE.
            if ![.javaSource, .mleModule].contains(h.type) {
                let before = (s.text as NSString).substring(to: h.typeStart)
                let lines = before.components(separatedBy: "\n")
                u.sourceLine += lines.count - 1
                u.sourceColumn = (lines.last ?? "").utf16.count
            }
            return u
        }
    }

    /// Polecenia okna programu: podział skryptu (`/` w osobnej linii kończy blok PL/SQL, jak w SQL*Plus), a w poleceniu
    /// także na każdym nagłówku jednostki (`CREATE [OR REPLACE] [EDITIONABLE|NONEDITIONABLE] PACKAGE|TYPE|PROCEDURE|
    /// FUNCTION|TRIGGER|LIBRARY|JAVA|MLE MODULE …`) na początku linii — pliki jednostek bez `/` (konwencja właściciela,
    /// D192). Komentarze i literały nie są nagłówkami (lekser). Polecenie kończy się na ostatnim znaczącym znaku przed
    /// następnym nagłówkiem (komentarz przed CREATE należy do następnej jednostki). Na początku linii tnie też `GRANT`,
    /// `REVOKE` i `SHOW ERRORS` (nie są poleceniami PL/SQL) — nie doklejają się do jednostki bez `/` przed nimi.
    /// Treść źródła Java i modułu MLE nie jest leksowana jak PL/SQL (apostrof w `// don't` otwierałby literał) —
    /// następny nagłówek szukany tekstowo. Jedno przejście po tokenach na polecenie (pliki z setkami jednostek).
    static func programStatements(_ text: String) -> [(start: Int, end: Int, line: Int, text: String)] {
        let ns = text as NSString
        var out: [(start: Int, end: Int, line: Int, text: String)] = []
        for s in ScriptSplitter.split(text) {
            let start = min(s.start, ns.length), end = min(max(s.end, start), ns.length)
            let body = ns.substring(with: NSRange(location: start, length: end - start)) as NSString
            // Linie liczone przyrostowo od początku polecenia (cięcia rosną).
            var scanned = 0, newlines = 0
            for piece in pieces(body) where piece.end > piece.start {
                while scanned < piece.start { if body.character(at: scanned) == 0x0A { newlines += 1 }; scanned += 1 }
                out.append((start + piece.start, start + piece.end, s.line + newlines,
                            body.substring(with: NSRange(location: piece.start, length: piece.end - piece.start))))
            }
        }
        return out
    }

    /// Kawałki polecenia (zakresy w `body`): od cięcia do ostatniego znaczącego znaku przed następnym cięciem.
    static func pieces(_ body: NSString) -> [(start: Int, end: Int)] {
        let trivia: Set<TokenKind> = [.whitespace, .newline, .lineComment, .blockComment]
        var out: [(start: Int, end: Int)] = []
        var pieceStart = 0
        var lexFrom = 0
        func header(at o: Int) -> (type: DBObjectType, owner: String?, name: String, nameStart: Int, typeStart: Int)? {
            headerTokens(body.substring(with: NSRange(location: o, length: min(600, body.length - o))))
        }
        func isForeign(_ o: Int) -> Bool { header(at: o).map { [.javaSource, .mleModule].contains($0.type) } ?? false }
        /// Koniec znaczącego tekstu przed pozycją (bez białych znaków).
        func trimmedEnd(before limit: Int, from lower: Int) -> Int {
            var e = limit
            while e > lower, let u = Unicode.Scalar(body.character(at: e - 1)), CharacterSet.whitespacesAndNewlines.contains(u) { e -= 1 }
            return e
        }
        /// Koniec źródła Java/JS przed następnym nagłówkiem: bez pustych linii i komentarzy PL/SQL między jednostkami
        /// (linie zaczynające się od `--`, blok `/* … */` zaczęty w osobnej linii) — nie trafiają do kodu Java/JS.
        func foreignEnd(before limit: Int, from lower: Int) -> Int {
            var end = limit
            while end > lower {
                let line = body.lineRange(for: NSRange(location: end - 1, length: 0))
                guard line.location > lower else { break }
                let t = body.substring(with: NSRange(location: line.location, length: end - line.location)).trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty || t.hasPrefix("--") {
                    end = line.location
                } else if t.hasSuffix("*/") {
                    // Blok komentarza: cofnij do linii, która go zaczyna (`/*` na początku linii); inaczej to kod Java/JS.
                    var start = line.location
                    var found = false
                    while start > lower {
                        let l = body.lineRange(for: NSRange(location: start, length: 0))
                        if body.substring(with: l).trimmingCharacters(in: .whitespaces).hasPrefix("/*") { start = l.location; found = true; break }
                        guard l.location > lower else { break }
                        start = body.lineRange(for: NSRange(location: l.location - 1, length: 0)).location
                    }
                    guard found, start > lower else { break }
                    end = start
                } else {
                    break
                }
            }
            return trimmedEnd(before: end, from: lower)
        }
        while true {
            if isForeign(pieceStart) {
                // Java / JavaScript: następny nagłówek tekstowo — CREATE na początku linii z nagłówkiem jednostki.
                var next: Int?
                var lineStart = NSMaxRange(body.lineRange(for: NSRange(location: pieceStart, length: 0)))
                while lineStart < body.length {
                    let line = body.lineRange(for: NSRange(location: lineStart, length: 0))
                    var k = line.location
                    while k < NSMaxRange(line), body.character(at: k) == 0x20 || body.character(at: k) == 0x09 { k += 1 }
                    if k + 6 <= body.length, body.substring(with: NSRange(location: k, length: 6)).uppercased() == "CREATE", header(at: k) != nil {
                        next = k
                        break
                    }
                    lineStart = NSMaxRange(line)
                }
                guard let next else { out.append((pieceStart, body.length)); return out }
                out.append((pieceStart, foreignEnd(before: next, from: pieceStart)))
                pieceStart = next
                lexFrom = next
                continue
            }
            let region = body.substring(from: lexFrom)
            let tokens = Lexer(region).tokenize()
            var lineStart = true
            var lastSignificantEnd = pieceStart
            var restart = false
            var i = 0
            while i < tokens.count {
                let t = tokens[i]
                let at = lexFrom + t.start
                i += 1
                if t.kind == .newline { lineStart = true; continue }
                if t.kind == .whitespace { continue }
                let wasLineStart = lineStart
                lineStart = false
                if wasLineStart, at > pieceStart, t.kind == .keyword || t.kind == .identifier {
                    let word = body.substring(with: NSRange(location: at, length: t.length)).uppercased()
                    var cut = false
                    if word == "CREATE" {
                        cut = header(at: at) != nil
                    } else if word == "GRANT" || word == "REVOKE" {
                        cut = true
                    } else if word == "SHOW", let n = tokens[i...].first(where: { !trivia.contains($0.kind) }) {
                        cut = ["ERRORS", "ERR", "ERROR"].contains((region as NSString).substring(with: NSRange(location: n.start, length: n.length)).uppercased())
                    }
                    if cut {
                        out.append((pieceStart, lastSignificantEnd))
                        pieceStart = at
                        lastSignificantEnd = at
                        if isForeign(at) { lexFrom = at; restart = true; break }
                    }
                }
                if !trivia.contains(t.kind) { lastSignificantEnd = at + t.length }
            }
            if restart { continue }
            out.append((pieceStart, body.length))
            return out
        }
    }

    /// Tekst bez jednostki (PD-PROG-001): od początku jej linii przez kończący „/” i następujące puste linie.
    public static func removing(_ unit: ProgramUnit, from text: String) -> String {
        let ns = text as NSString
        let start = ns.lineRange(for: NSRange(location: min(unit.range.lowerBound, ns.length), length: 0)).location
        var end = min(unit.range.upperBound, ns.length)
        func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A }
        var k = end
        while k < ns.length, isSpace(ns.character(at: k)) { k += 1 }
        if k < ns.length, ns.character(at: k) == 0x2F {
            let line = ns.lineRange(for: NSRange(location: k, length: 0))
            if ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == "/" { end = line.upperBound }
        } else {
            end = ns.lineRange(for: NSRange(location: max(start, end - 1), length: 0)).upperBound
        }
        // Puste linie za jednostką.
        while end < ns.length {
            let line = ns.lineRange(for: NSRange(location: end, length: 0))
            guard ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, line.length > 0 else { break }
            end = line.upperBound
        }
        return ns.replacingCharacters(in: NSRange(location: start, length: end - start), with: "")
    }

    /// Typ i nazwa z nagłówka `CREATE [OR REPLACE] [EDITIONABLE|NONEDITIONABLE] <typ> [BODY] [schemat.]nazwa`.
    static func header(_ sql: String) -> (DBObjectType, String?, String)? {
        headerTokens(sql).map { ($0.type, $0.owner, $0.name) }
    }

    /// Nagłówek z właścicielem, gdy go nie ma (`CREATE OR REPLACE PACKAGE BODY WŁAŚCICIEL.nazwa`) — źródło obiektu z innego
    /// schematu kompiluje się u właściciela, nie w schemacie sesji.
    static func withOwner(_ sql: String, owner: String) -> String {
        guard let h = headerTokens(sql), h.owner == nil else { return sql }
        let simple = owner.range(of: "^[A-Z][A-Z0-9_$#]*$", options: .regularExpression) != nil
        let prefix = (simple ? owner : "\"" + owner.replacingOccurrences(of: "\"", with: "\"\"") + "\"") + "."
        let ns = NSMutableString(string: sql)
        ns.insert(prefix, at: h.nameStart)
        return ns as String
    }

    private static func headerTokens(_ sql: String) -> (type: DBObjectType, owner: String?, name: String, nameStart: Int, typeStart: Int)? {
        let tokens = Lexer(sql).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment].contains($0.kind) }
        let ns = sql as NSString
        let words = tokens.prefix(14).map { ns.substring(with: NSRange(location: $0.start, length: $0.length)) }
        let up = words.map { $0.uppercased() }
        guard up.first == "CREATE" else { return nil }
        var i = 1
        // CREATE [OR REPLACE] AND {RESOLVE|COMPILE} [NOFORCE] JAVA SOURCE — źródło Java (PD-PROG-002).
        let skip: Set<String> = ["OR", "REPLACE", "EDITIONABLE", "NONEDITIONABLE", "EDITIONING", "FORCE", "NOFORCE", "AND", "RESOLVE", "COMPILE"]
        while i < up.count, skip.contains(up[i]) { i += 1 }
        guard i < up.count else { return nil }
        let typeStart = tokens[i].start
        var type: DBObjectType
        switch up[i] {
        case "PACKAGE": type = .package
        case "TYPE": type = .type
        case "FUNCTION": type = .function
        case "PROCEDURE": type = .procedure
        case "TRIGGER": type = .trigger
        case "LIBRARY": type = .library
        case "JAVA": type = .javaSource
        case "MLE" where i + 1 < up.count && up[i + 1] == "MODULE":   // CREATE MLE MODULE nazwa … AS <JavaScript> (PD-PROG-014)
            type = .mleModule
            i += 1
        default: return nil
        }
        i += 1
        if i < up.count, up[i] == "BODY" {
            type = type == .package ? .packageBody : .typeBody
            i += 1
        }
        if type == .javaSource {     // CREATE JAVA SOURCE NAMED "x"
            while i < up.count, ["SOURCE", "NAMED", "RESOLVE", "COMPILE", "AND"].contains(up[i]) { i += 1 }
        }
        guard i < words.count else { return nil }
        func clean(_ s: String) -> String { s.hasPrefix("\"") ? String(s.dropFirst().dropLast()) : s.uppercased() }
        if i + 2 < words.count, words[i + 1] == "." { return (type, clean(words[i]), clean(words[i + 2]), tokens[i + 2].start, typeStart) }
        return (type, nil, clean(words[i]), tokens[i].start, typeStart)
    }

    /// Wynik kompilacji okna.
    public struct Result: Sendable {
        public var messages: [CompileMessage]
        public var compiled: Int
        public var stoppedAt: ProgramUnit?
        public var ok: Bool { !messages.contains { $0.severity == .error } }
    }

    /// Kompiluje jednostki po kolei w sesji kompilacji (UG 4.4); przy błędzie zatrzymuje się. Ostrzeżenia wg
    /// preferencji PLSQL_WARNINGS. Linie błędów przeliczane na linie dokumentu (od 1).
    @MainActor
    public static func compile(_ doc: Document, in ws: Workspace) async throws -> Result {
        // Od początku (przed strażnikiem i łączeniem): drugie F8 albo zamknięcie okna w tym czasie są odrzucane (D168).
        doc.isExecuting = true
        defer { doc.isExecuting = false }
        let wasOpen = ws.documents.contains { $0 === doc }
        if ws.settings.beautifier.beforeCompile { ws.autoBeautify(doc) }
        let units = units(in: doc.text)
        guard !units.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak jednostek do kompilacji (polecenia CREATE …)")) }
        guard let conn = ws.effectiveConnection(of: doc) else { throw CommandError.notConnected }
        // Plik tylko do odczytu (np. z systemu kontroli wersji) — kompilacja wyłączona preferencją (PD-PROG-017).
        if let url = doc.fileURL, !ws.settings.compileReadOnlyFiles, FileManager.default.fileExists(atPath: url.path),
           !FileManager.default.isWritableFile(atPath: url.path) {
            throw CommandError.notAvailable(L10n.tr("Plik „\(url.lastPathComponent)” jest tylko do odczytu — kompilacja wyłączona (Preferencje › Oracle)"))
        }
        try await ws.guardModification(units.map(\.text), connectionID: conn)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: conn))
        try await ws.ensureStillOpen(doc, wasOpen: wasOpen)
        // Jednostka bez właściciela w nagłówku trafia do bieżącego schematu sesji (np. SYS po zalogowaniu jako SYS) —
        // pytanie przed pierwszym poleceniem w bazie (także przed parametrami kompilatora).
        try await ws.confirmOracleMaintained(units.map { $0.owner ?? s.info.currentSchema })
        try await ws.ensureStillOpen(doc, wasOpen: wasOpen)
        // Ostrzeżenia i parametry kompilatora z Preferencji (PD-PROG-013); błąd parametru (np. NATIVE bez uprawnień)
        // nie zatrzymuje kompilacji — obowiązuje ustawienie serwera.
        for statement in ws.settings.compiler.statements(warnings: ws.settings.plsqlWarnings) {
            _ = try? await s.execute(statement)
        }
        var result = Result(messages: [], compiled: 0, stoppedAt: nil)
        let schema = s.info.currentSchema
        for u in units {
            do {
                _ = try await s.execute(u.text)
            } catch let e as OracleError {
                // Błąd samego CREATE (np. ORA-00900) — komunikat z pozycją w jednostce.
                let local = SessionUtilities.utf16Offset(ofUTF8Offset: Int(e.offset), in: u.text)
                let prefix = (u.text as NSString).substring(to: min(local, (u.text as NSString).length))
                let line = u.line + prefix.components(separatedBy: "\n").count
                result.messages.append(CompileMessage(severity: .error, unit: u.tabTitle, line: line, column: 1, text: e.message))
                result.stoppedAt = u
                break
            }
            result.compiled += 1
            // Historia lokalna obiektu (DG-HIST-001): wersja wysłana do bazy.
            ws.localHistory.record(key: LocalHistory.key(object: u.owner ?? schema, type: u.type.rawValue, name: u.name, connection: conn),
                                   title: "\(u.owner ?? schema).\(u.name) (\(u.type.rawValue))", text: u.text, label: L10n.tr("kompilacja"))
            if ws.addsDebugInfo(object: DBObject(owner: u.owner ?? schema, name: u.name, type: u.type), connectionID: conn),
               let dbg = ObjectCommands.debugCompileStatement(DBObject(owner: u.owner ?? schema, name: u.name, type: u.type)) {
                _ = try? await s.execute(dbg)
            }
            let (_, rows) = try await s.queryAll("""
                select line, position, text, attribute, message_number from all_errors
                where owner = :o and name = :n and type = :t order by sequence
                """, binds: [BindVariable(name: "o", value: .text(u.owner ?? schema)), BindVariable(name: "n", value: .text(u.name)),
                             BindVariable(name: "t", value: .text(u.type.rawValue))], limit: 10_000)
            for r in rows {
                let at = u.documentPosition(line: Int(r[0].format(.default)) ?? 1, column: Int(r[1].format(.default)) ?? 1)
                let attr = (r[3].displayText ?? "ERROR").uppercased()
                result.messages.append(CompileMessage(severity: attr == "WARNING" ? .warning : .error, unit: u.tabTitle,
                                                      line: at.line, column: at.column,
                                                      text: (r[2].displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            if rows.contains(where: { ($0[3].displayText ?? "").uppercased() == "ERROR" }) {
                result.stoppedAt = u
                break
            }
        }
        // Podpowiedzi Pelikana dla skompilowanych bez błędów jednostek (PD-PROG-005): inspekcje i konwencje nazw.
        if ws.settings.compilerHints {
            for u in units.prefix(result.compiled) {
                for h in CompilerHints.hints(for: u.text, conventions: ws.settings.namingConventions) {
                    result.messages.append(CompileMessage(severity: .hint, unit: u.tabTitle, line: u.line + h.line, column: h.column, text: h.text))
                }
            }
        }
        // Adnotacje utPLSQL w specyfikacjach z --%suite albo --%test: nieznane nazwy, listy procedur, brak --%suite,
        // niesparowane konteksty — ostrzeżenia (UT-CA-002).
        for u in units where u.type == .package && (u.text.lowercased().contains("--%suite") || u.text.lowercased().contains("--%test")) {
            for a in UtplsqlExplorer.annotationProblems(in: u.text) {
                result.messages.append(CompileMessage(severity: .warning, unit: u.tabTitle, line: u.line + a.line, column: 1, text: a.message))
            }
        }
        ws.compileGeneration += 1
        doc.compileMessages = result.messages
        // Znaczniki czasu skompilowanych obiektów — zmiana przez kogoś innego później będzie wykryta.
        let compiled = units.prefix(result.compiled).map { DBObject(owner: $0.owner ?? schema, name: $0.name, type: $0.type) }
        for (k, v) in (try? await ObjectAdmin.lastDDLTimes(compiled, in: s)) ?? [:] { doc.objectTimestamps[k] = v }
        doc.isCompileStale = !result.ok
        if let first = result.messages.first(where: { $0.severity == .error }) {
            let o = offset(line: first.line, column: first.column, in: doc.text)
            doc.errorRange = o..<o
        }
        ws.metadata(for: conn)?.refresh()
        return result
    }

    /// Przesunięcie UTF-16 dla linii i kolumny (od 1).
    public static func offset(line: Int, column: Int, in text: String) -> Int {
        let start = TextEditing.offset(ofLine: line, in: text)
        let ns = text as NSString
        let lineEnd = ns.lineRange(for: NSRange(location: min(start, ns.length), length: 0))
        // Kolumna Oracle liczona w znakach — emoji spoza BMP zajmuje dwie jednostki UTF-16.
        let last = max(start, lineEnd.location + lineEnd.length - 1)
        return min(TextEditing.utf16Offset(ns, from: start, characters: max(0, column - 1), limit: last), last)
    }
}
