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
    public var id: String { "\(type.rawValue):\(owner ?? "").\(name)@\(range.lowerBound)" }

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
    /// Jednostki programu w tekście (polecenia CREATE PL/SQL zakończone `/`).
    public static func units(in text: String) -> [ProgramUnit] {
        ScriptSplitter.split(text).compactMap { s in
            guard let (type, owner, name) = header(s.text) else { return nil }
            return ProgramUnit(type: type, owner: owner, name: name, range: s.start..<s.end, line: s.line, text: s.text)
        }
    }

    /// Typ i nazwa z nagłówka `CREATE [OR REPLACE] [EDITIONABLE|NONEDITIONABLE] <typ> [BODY] [schemat.]nazwa`.
    static func header(_ sql: String) -> (DBObjectType, String?, String)? {
        let tokens = Lexer(sql).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment].contains($0.kind) }
        let ns = sql as NSString
        let words = tokens.prefix(14).map { ns.substring(with: NSRange(location: $0.start, length: $0.length)) }
        let up = words.map { $0.uppercased() }
        guard up.first == "CREATE" else { return nil }
        var i = 1
        let skip: Set<String> = ["OR", "REPLACE", "EDITIONABLE", "NONEDITIONABLE", "EDITIONING", "FORCE", "NOFORCE"]
        while i < up.count, skip.contains(up[i]) { i += 1 }
        guard i < up.count else { return nil }
        var type: DBObjectType
        switch up[i] {
        case "PACKAGE": type = .package
        case "TYPE": type = .type
        case "FUNCTION": type = .function
        case "PROCEDURE": type = .procedure
        case "TRIGGER": type = .trigger
        case "LIBRARY": type = .library
        case "JAVA": type = .javaSource
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
        if i + 2 < words.count, words[i + 1] == "." { return (type, clean(words[i]), clean(words[i + 2])) }
        return (type, nil, clean(words[i]))
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
        if ws.settings.beautifier.beforeCompile { ws.autoBeautify(doc) }
        let units = units(in: doc.text)
        guard !units.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak jednostek do kompilacji (CREATE … zakończone /)")) }
        guard let conn = ws.effectiveConnection(of: doc) else { throw CommandError.notConnected }
        try await ws.guardModification(units.map(\.text), connectionID: conn)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: conn))
        let warnings = ws.settings.plsqlWarnings.trimmingCharacters(in: .whitespaces)
        if !warnings.isEmpty, ws.settings.plsqlWarnings.range(of: #"^[A-Za-z0-9:_, ()]+$"#, options: .regularExpression) != nil {
            _ = try? await s.execute("ALTER SESSION SET PLSQL_WARNINGS = '\(warnings)'")
        }
        var result = Result(messages: [], compiled: 0, stoppedAt: nil)
        let schema = s.info.currentSchema
        doc.isExecuting = true
        defer { doc.isExecuting = false }
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
            if ws.settings.debugInfoOnCompile,
               let dbg = ObjectCommands.debugCompileStatement(DBObject(owner: u.owner ?? schema, name: u.name, type: u.type)) {
                _ = try? await s.execute(dbg)
            }
            let (_, rows) = try await s.queryAll("""
                select line, position, text, attribute, message_number from all_errors
                where owner = :o and name = :n and type = :t order by sequence
                """, binds: [BindVariable(name: "o", value: .text(u.owner ?? schema)), BindVariable(name: "n", value: .text(u.name)),
                             BindVariable(name: "t", value: .text(u.type.rawValue))], limit: 10_000)
            for r in rows {
                let line = Int(r[0].format(.default)) ?? 1
                let col = Int(r[1].format(.default)) ?? 1
                let attr = (r[3].displayText ?? "ERROR").uppercased()
                result.messages.append(CompileMessage(severity: attr == "WARNING" ? .warning : .error, unit: u.tabTitle,
                                                      line: u.line + line, column: col,
                                                      text: (r[2].displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            if rows.contains(where: { ($0[3].displayText ?? "").uppercased() == "ERROR" }) {
                result.stoppedAt = u
                break
            }
        }
        // Adnotacje utPLSQL w specyfikacjach z --%suite: nieznane nazwy jako ostrzeżenia (UT-CA-002).
        for u in units where u.type == .package && u.text.lowercased().contains("--%suite") {
            for a in UtplsqlExplorer.unknownAnnotations(in: u.text) {
                result.messages.append(CompileMessage(severity: .warning, unit: u.tabTitle, line: u.line + a.line, column: 1,
                                                      text: L10n.tr("Nieznana adnotacja utPLSQL --%\(a.name)")))
            }
        }
        ws.compileGeneration += 1
        doc.compileMessages = result.messages
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
        return min(start + max(0, column - 1), max(start, lineEnd.location + lineEnd.length - 1))
    }
}
