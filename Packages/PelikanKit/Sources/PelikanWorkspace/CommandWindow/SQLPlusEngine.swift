import Foundation
import PelikanDB
import PelikanSQL

/// Podstawianie zmiennych SQL*Plus (`&x`, `&&x`, `&1`, znak DEFINE, CONCAT, ESCAPE) — UG 8.3.
public enum SQLPlusSubstitution {
    public struct Reference: Sendable, Hashable {
        public var name: String
        public var persistent: Bool
    }

    /// Odwołania w tekście (kolejność wystąpień, bez powtórzeń nazw).
    public static func references(in text: String, state: SQLPlusState) -> [Reference] {
        var out: [Reference] = []
        scan(text, state: state) { ref in
            if !out.contains(where: { $0.name == ref.name }) { out.append(ref) }
            return nil
        }
        return out
    }

    /// Tekst po podstawieniu; `values` — wartości dla nazw (wielkie litery).
    public static func substitute(_ text: String, state: SQLPlusState, values: [String: String]) -> String {
        scan(text, state: state) { values[$0.name] }
    }

    @discardableResult
    static func scan(_ text: String, state: SQLPlusState, replace: (Reference) -> String?) -> String {
        guard state.defineEnabled, state.scan else { return text }
        let chars = Array(text)
        var out = ""
        var i = 0
        let d = state.defineChar
        while i < chars.count {
            let ch = chars[i]
            if let esc = state.escapeChar, ch == esc, i + 1 < chars.count, chars[i + 1] == d {
                out.append(d)
                i += 2
                continue
            }
            guard ch == d else { out.append(ch); i += 1; continue }
            var j = i + 1
            var persistent = false
            if j < chars.count, chars[j] == d { persistent = true; j += 1 }
            let start = j
            while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "$" || chars[j] == "#" { j += 1 }
            guard j > start else { out.append(ch); i += 1; continue }
            let name = String(chars[start..<j]).uppercased()
            // Znak CONCAT kończy nazwę i znika (np. &tab._audit).
            var end = j
            if end < chars.count, chars[end] == state.concatChar { end += 1 }
            if let v = replace(Reference(name: name, persistent: persistent)) {
                out += v
            } else {
                out += String(chars[i..<end])
            }
            i = end
        }
        return out
    }
}

/// Silnik Command Window (UG 8): wykonuje skrypt polecenie po poleceniu, polecenia SQL*Plus obsługuje lokalnie,
/// SQL i PL/SQL wysyła do sesji okna; wyjście trafia do `Document.console` (i do pliku SPOOL).
@MainActor
public final class SQLPlusEngine {
    public let workspace: Workspace
    public let document: Document
    public var state = SQLPlusState()
    var depth = 0
    var cancelled = false

    public enum Outcome: Sendable, Equatable { case finished, stopped, exit }

    public init(workspace: Workspace, document: Document) {
        self.workspace = workspace
        self.document = document
    }

    // MARK: Wyjście

    func emit(_ text: String, _ kind: ConsoleLine.Kind = .output) {
        let lines = text.components(separatedBy: "\n")
        if state.termOut || kind == .error || kind == .prompt {
            document.console.append(contentsOf: lines.map { ConsoleLine($0, kind) })
            if document.console.count > 100_000 { document.console.removeFirst(document.console.count - 100_000) }
        }
        if let url = state.spoolURL { Self.append(lines.joined(separator: "\n") + "\n", to: url) }
    }

    static func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    public func cancel() { cancelled = true }

    // MARK: Wykonanie skryptu

    /// Wykonuje skrypt (tekst karty Editor albo linię karty Dialog). `arguments` — &1, &2… dla @plik.
    @discardableResult
    public func run(_ script: String, arguments: [String] = [], baseDirectory: URL? = nil) async -> Outcome {
        cancelled = false
        if depth == 0 { document.isExecuting = true }
        defer { if depth == 0 { document.isExecuting = false } }
        for (i, a) in arguments.enumerated() { state.defines[String(i + 1)] = a }
        let statements = ScriptSplitter.split(script, mode: .commandWindow)
        for s in statements {
            if cancelled { emit(L10n.tr("Przerwano"), .info); return .stopped }
            let outcome = await execute(s, baseDirectory: baseDirectory)
            if outcome != .finished { return outcome }
        }
        return .finished
    }

    func execute(_ s: ScriptStatement, baseDirectory: URL?) async -> Outcome {
        let raw = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .finished }
        if let cmd = s.sqlplusCommand {
            // REMARK bez podstawiania; reszta poleceń SQL*Plus z podstawianiem.
            if cmd == "REMARK" { return .finished }
            if state.echo, depth > 0 || cmd != "PROMPT" { emit(state.sqlPrompt + raw, .echo) }
            guard let text = await substitute(raw) else { return .stopped }
            do {
                return try await sqlplus(cmd, text, baseDirectory: baseDirectory)
            } catch {
                emit(error.localizedDescription, .error)
                return state.whenever == .continue ? .finished : await exitOnError()
            }
        }
        if raw == "/" {
            guard let b = state.buffer else { emit(L10n.tr("SP2-0103: Bufor SQL jest pusty."), .error); return .finished }
            return await executeSQL(b, original: b, isPLSQL: ScriptSplitter.split(b).first?.isPLSQL ?? false)
        }
        if state.echo { emit(state.sqlPrompt + raw, .echo) }
        guard let text = await substitute(s.text) else { return .stopped }
        state.buffer = text
        return await executeSQL(text, original: s.text, isPLSQL: s.isPLSQL)
    }

    /// Podstawianie z pytaniem o brakujące wartości (okno Zmienne); VERIFY — linie „stara/nowa”.
    func substitute(_ text: String) async -> String? {
        let refs = SQLPlusSubstitution.references(in: text, state: state)
        guard !refs.isEmpty else { return text }
        var values = state.defines
        let missing = refs.filter { values[$0.name] == nil }
        if !missing.isEmpty {
            let requests = missing.map { VariableRequest(name: $0.name, kind: .substitution, options: VariableOptions(name: $0.name), value: nil) }
            guard let answers = await workspace.ui?.askVariables(requests, document: document) else {
                emit(L10n.tr("Anulowano"), .info)
                return nil
            }
            for r in missing {
                let v: String
                switch answers[r.name] {
                case .text(let t)?: v = t
                case .list(let l)?: v = l.joined(separator: ",")
                default: v = ""
                }
                values[r.name] = v
                if r.persistent { state.defines[r.name] = v }
            }
        }
        let out = SQLPlusSubstitution.substitute(text, state: state, values: values)
        if state.verify, out != text, depth == 0 || state.echo {
            emit(L10n.tr("stara: ") + text.replacingOccurrences(of: "\n", with: " "), .info)
            emit(L10n.tr("nowa: ") + out.replacingOccurrences(of: "\n", with: " "), .info)
        }
        return out
    }

    func exitOnError() async -> Outcome {
        if case .exit(let commit) = state.whenever, let session = try? await workspace.session(for: document) {
            if commit { try? await session.commit() } else { try? await session.rollback() }
            document.transactionOpen = false
        }
        emit(L10n.tr("WHENEVER SQLERROR: przerwano skrypt"), .info)
        return .exit
    }

    // MARK: SQL i PL/SQL

    func executeSQL(_ sql: String, original: String, isPLSQL: Bool) async -> Outcome {
        let start = ContinuousClock.now
        do {
            let session = try await workspace.session(for: document)
            if state.serverOutput { try await SessionUtilities.enableOutput(session, bufferSize: workspace.settings.dbmsOutputBufferSize) }
            let names = Variables.distinct(Variables.find(in: sql, syntax: .sqlplus)).filter { $0.kind == .bind }.map(\.name)
            var binds: [BindVariable] = []
            for n in names {
                guard let slot = state.binds[n.uppercased()] else {
                    emit(L10n.tr("SP2-0552: Zmienna wiązana „\(n.uppercased())” nie jest zadeklarowana."), .error)
                    return state.whenever == .continue ? .finished : await exitOnError()
                }
                binds.append(BindVariable(name: n, type: slot.type, direction: .inputOutput, value: slot.value, maxSize: slot.size))
            }
            let r = try await session.execute(sql, binds: binds, options: ExecuteOptions())
            for (name, v) in r.outBinds { state.binds[name.uppercased()]?.value = v }
            switch r.kind {
            case .query:
                if let rs = r.resultSet { try await printQuery(rs, session: session) }
            case .dml:
                feedback(L10n.tr("Wierszy: \(r.rowsAffected)"), count: Int(r.rowsAffected))
                document.transactionOpen = true
            case .ddl:
                if r.warning?.code == 24344 {
                    emit(L10n.tr("Ostrzeżenie: utworzono z błędami kompilacji."), .error)
                } else if state.feedback > 0 {
                    emit(Self.ddlMessage(sql))
                }
                rememberCompiled(sql)
            case .plsql:
                if r.warning?.code == 24344 { emit(L10n.tr("Ostrzeżenie: blok PL/SQL z błędami kompilacji."), .error) }
                if state.feedback > 0 { emit(L10n.tr("Procedura PL/SQL została zakończona pomyślnie.")) }
                document.transactionOpen = (try? await SessionUtilities.transactionOpen(session)) ?? document.transactionOpen
            case .transaction:
                let word = sql.trimmingCharacters(in: .whitespaces).prefix(8).uppercased()
                if state.feedback > 0 { emit(word.hasPrefix("COMMIT") ? L10n.tr("Zatwierdzono.") : word.hasPrefix("ROLLBACK") ? L10n.tr("Wycofano.") : L10n.tr("Wykonano.")) }
                document.transactionOpen = (try? await SessionUtilities.transactionOpen(session)) ?? false
            default:
                if state.feedback > 0 { emit(L10n.tr("Wykonano.")) }
            }
            for rs in r.implicitResults { try await printQuery(rs, session: session) }
            if state.serverOutput {
                let lines = try await SessionUtilities.readOutput(session)
                if !lines.isEmpty { emit(lines.joined(separator: "\n")) }
            }
            if state.autoPrint, !names.isEmpty { printBinds(names.map { $0.uppercased() }) }
            if state.timing { emit(L10n.tr("Czas: ") + Self.elapsed(ContinuousClock.now - start), .info) }
            workspace.recordHistory(original)
            return .finished
        } catch let e as OracleError {
            emit(e.message, .error)
            if e.isConnectionLost { emit(L10n.tr("Połączenie utracone — kolejne polecenie połączy się ponownie."), .info) }
            return state.whenever == .continue ? .finished : await exitOnError()
        } catch {
            emit(error.localizedDescription, .error)
            return state.whenever == .continue ? .finished : await exitOnError()
        }
    }

    func feedback(_ message: String, count: Int) {
        if state.feedback > 0, count >= state.feedback || count == 0 { emit(message) }
    }

    nonisolated static func elapsed(_ d: Duration) -> String {
        let total = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        let h = Int(total) / 3600, m = Int(total) % 3600 / 60
        return String(format: "%02d:%02d:%05.2f", h, m, total.truncatingRemainder(dividingBy: 60))
    }

    nonisolated static func ddlMessage(_ sql: String) -> String {
        let words = sql.split(whereSeparator: { $0.isWhitespace }).prefix(6).map { $0.uppercased() }
        guard let verb = words.first else { return L10n.tr("Wykonano.") }
        let skip: Set<String> = ["OR", "REPLACE", "EDITIONABLE", "NONEDITIONABLE", "EDITIONING", "FORCE", "NOFORCE", "PUBLIC", "GLOBAL", "TEMPORARY", "UNIQUE", "BITMAP", "PRIVATE"]
        let object = words.dropFirst().first { !skip.contains($0) } ?? ""
        let what = object == "PACKAGE" && words.contains("BODY") ? "PACKAGE BODY" : object
        switch verb {
        case "CREATE": return L10n.tr("Utworzono: \(what).")
        case "ALTER": return L10n.tr("Zmieniono: \(what).")
        case "DROP": return L10n.tr("Usunięto: \(what).")
        case "TRUNCATE": return L10n.tr("Obcięto tabelę.")
        case "GRANT": return L10n.tr("Nadano uprawnienia.")
        case "REVOKE": return L10n.tr("Odebrano uprawnienia.")
        case "COMMENT": return L10n.tr("Dodano komentarz.")
        default: return L10n.tr("Wykonano.")
        }
    }

    /// Obiekt z CREATE … PROCEDURE/FUNCTION/PACKAGE/TRIGGER/TYPE — dla SHOW ERRORS.
    func rememberCompiled(_ sql: String) {
        let tokens = Lexer(sql).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment].contains($0.kind) }
        let ns = sql as NSString
        let words = tokens.prefix(12).map { ns.substring(with: NSRange(location: $0.start, length: $0.length)) }
        let upper = words.map { $0.uppercased() }
        guard upper.first == "CREATE" else { return }
        let types = ["PROCEDURE", "FUNCTION", "PACKAGE", "TRIGGER", "TYPE", "VIEW", "LIBRARY", "JAVA"]
        guard let ti = upper.firstIndex(where: { types.contains($0) }) else { return }
        var type = upper[ti]
        var ni = ti + 1
        if ni < upper.count, upper[ni] == "BODY" { type += " BODY"; ni += 1 }
        guard ni < words.count else { return }
        var owner: String?
        var name = words[ni]
        if ni + 2 < words.count, words[ni + 1] == "." { owner = words[ni]; name = words[ni + 2] }
        func clean(_ s: String) -> String { s.hasPrefix("\"") ? String(s.dropFirst().dropLast()) : s.uppercased() }
        state.lastCompiled = (type, owner.map(clean), clean(name))
    }

    func printQuery(_ rs: ResultSetDescriptor, session: any DatabaseSession) async throws {
        var formatter = TextResultFormatter(columns: rs.columns, state: state, format: workspace.settings.valueFormat)
        var total = 0
        var first = true
        var lastRow: [OracleValue]?
        let limit = 1_000_000
        while total < limit {
            if cancelled { session.breakExecution(); await session.closeResultSet(rs.id); emit(L10n.tr("Przerwano"), .info); return }
            let batch = try await session.fetch(rs.id, maxRows: first ? 200 : 2000)
            if batch.rows.isEmpty, !first { break }
            let lines = formatter.lines(batch.rows, first: first)
            if !(first && batch.rows.isEmpty) { emit(lines.joined(separator: "\n")) }
            first = false
            total += batch.rows.count
            lastRow = batch.rows.last ?? lastRow
            if !batch.hasMore { break }
        }
        if total >= limit { await session.closeResultSet(rs.id); emit(L10n.tr("Pokazano pierwszy milion wierszy."), .info) }
        // COLUMN … NEW_VALUE: wartość z ostatniego wiersza do zmiennej podstawiania.
        if let row = lastRow {
            for (i, c) in rs.columns.enumerated() {
                if let nv = state.columns[c.name.uppercased()]?.newValue { state.defines[nv.uppercased()] = row[i].format(workspace.settings.valueFormat) }
            }
        }
        if total == 0 { emit(L10n.tr("Nie wybrano wierszy.")) } else { feedback(L10n.tr("Wybrano wierszy: \(total)"), count: total) }
    }

    func printBinds(_ names: [String]) {
        for n in names {
            guard let slot = state.binds[n] else { emit(L10n.tr("SP2-0552: Zmienna wiązana „\(n)” nie jest zadeklarowana."), .error); continue }
            var f = TextResultFormatter(columns: [ColumnInfo(name: n, type: slot.type == .refCursor ? .varchar2 : slot.type, typeName: slot.type.rawValue)],
                                        state: state, format: workspace.settings.valueFormat)
            if case .cursor(let id) = slot.value, let session = try? workspace.sessions.existingSession(workspace.sessions.key(forDocument: document.id, connection: workspace.effectiveConnection(of: document)!)) {
                Task { [weak self] in
                    // REF CURSOR: opis kolumn z wyniku zagnieżdżonego nie jest dostępny bez ponownego opisu — pobierz wiersze.
                    let batch = try? await session.fetch(id, maxRows: 10_000)
                    self?.emit((batch?.rows ?? []).map { $0.map { $0.format(.default) }.joined(separator: " ") }.joined(separator: "\n"))
                }
                continue
            }
            emit("")
            emit(f.lines([[slot.value]], first: true).joined(separator: "\n"))
        }
    }
}
