import Foundation
import PelikanDB
import PelikanSQL

/// Co wykonać w SQL Window (UG 7.1, 23.20; D12).
public enum ExecuteScope: Sendable, Hashable {
    /// F8: zaznaczenie albo (AutoSelect) polecenie pod kursorem, albo wszystkie polecenia.
    case standard
    /// Ctrl+F8: odwrotnie do AutoSelect.
    case alternate
    case currentStatement
    case allStatements
}

/// Zmienna do okna „Zmienne” (UG 7.5, 12.3).
public struct VariableRequest: Sendable, Hashable {
    public var name: String
    public var kind: VariableKind
    public var options: VariableOptions
    /// Poprzednia wartość (zapamiętana w oknie) albo nil.
    public var value: VariableValue?

    public init(name: String, kind: VariableKind, options: VariableOptions, value: VariableValue?) {
        self.name = name; self.kind = kind; self.options = options; self.value = value
    }
}

/// Wykonanie poleceń okna SQL — logika bez AppKit (testowana na bazie testowej).
@MainActor
public enum SQLExecutor {
    /// Polecenia do wykonania wg zakresu i zaznaczenia; przesunięcia w tekście okna (UTF-16).
    public static func statements(text: String, selection: Range<Int>, scope: ExecuteScope, autoSelect: Bool) -> [ScriptStatement] {
        let utf16 = Array(text.utf16)
        let sel = selection.clamped(to: 0..<utf16.count)
        if !sel.isEmpty {
            let part = String(decoding: utf16[sel], as: UTF16.self)
            return ScriptSplitter.split(part).map { shifted($0, by: sel.lowerBound, lineOffset: lineNumber(of: sel.lowerBound, in: utf16)) }
        }
        let all = ScriptSplitter.split(text)
        let current: Bool
        switch scope {
        case .standard: current = autoSelect
        case .alternate: current = !autoSelect
        case .currentStatement: current = true
        case .allStatements: current = false
        }
        if current {
            return ScriptSplitter.statement(at: sel.lowerBound, in: all).map { [$0] } ?? []
        }
        return all
    }

    static func shifted(_ s: ScriptStatement, by offset: Int, lineOffset: Int) -> ScriptStatement {
        var c = s
        c.start += offset; c.end += offset; c.fullEnd += offset; c.line += lineOffset
        return c
    }

    static func lineNumber(of offset: Int, in utf16: [UInt16]) -> Int {
        utf16.prefix(offset).reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// Zmienne we wszystkich poleceniach (kolejność pierwszego wystąpienia), z wartościami zapamiętanymi w oknie.
    public static func variableRequests(_ statements: [ScriptStatement], remembered: [String: VariableValue]) -> [VariableRequest] {
        var seen = Set<String>()
        var out: [VariableRequest] = []
        for s in statements {
            for o in Variables.find(in: s.text) where o.kind != .literalAmpersand {
                let key = o.name.uppercased()
                guard seen.insert(key).inserted else { continue }
                let options = o.options ?? VariableOptions(name: o.name)
                out.append(VariableRequest(name: o.name, kind: o.kind, options: options, value: remembered[o.name]))
            }
        }
        return out
    }

    /// Tytuł karty wyniku: dyrektywa `-- tab=…` (z `&Count`) albo „Select <tabela>” (UG 7.1, 7.12).
    public static func tabTitle(for s: ScriptStatement, rowCount: Int? = nil) -> String {
        if let t = directive("tab", in: s.text) {
            return t.replacingOccurrences(of: "&Count", with: rowCount.map(String.init) ?? "…", options: .caseInsensitive)
        }
        let lexer = Lexer(s.text)
        let words = lexer.tokenize().filter { !$0.isTrivia }.map { lexer.string($0) }
        guard let first = words.first else { return "SQL" }
        let verb = first.prefix(1).uppercased() + first.dropFirst().lowercased()
        let upper = words.map { $0.uppercased() }
        let anchors = ["FROM", "INTO", "UPDATE", "TABLE", "VIEW", "PACKAGE", "PROCEDURE", "FUNCTION", "TRIGGER", "TYPE", "INDEX", "SEQUENCE"]
        if let i = upper.firstIndex(where: { anchors.contains($0) }), i + 1 < words.count {
            var name = words[i + 1]
            if name.uppercased() == "BODY", i + 2 < words.count { name = words[i + 2] }
            return "\(verb) \(name.lowercased())"
        }
        return verb
    }

    /// Wartość dyrektywy w komentarzu przed poleceniem (`-- Tab=…`, `-- Records=…`), bez rozróżniania wielkości liter.
    public static func directive(_ name: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("--") else {
                if !t.isEmpty { break } else { continue }
            }
            let body = t.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if body.lowercased().hasPrefix(name.lowercased() + "=") {
                return String(body.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Polecenie zawiera hasło — nie trafia do historii (UG 25.5; SECURITY A17).
    public static func containsPassword(_ sql: String) -> Bool {
        let u = sql.uppercased()
        return u.range(of: #"IDENTIFIED\s+BY"#, options: .regularExpression) != nil
            || u.range(of: #"^\s*CONN(ECT)?\s"#, options: .regularExpression) != nil
            || u.contains("PASSWORD")
    }

    /// Wykonuje polecenia w sesji okna. Zwraca false, gdy przerwano na błędzie albo anulowano.
    @discardableResult
    public static func execute(_ doc: Document, scope: ExecuteScope, in ws: Workspace) async throws -> Bool {
        let stmts = statements(text: doc.text, selection: doc.selectedRange, scope: scope, autoSelect: ws.settings.autoSelectStatement)
        guard !stmts.isEmpty else {
            doc.statusText = L10n.tr("Brak polecenia do wykonania")
            return false
        }
        // Zmienne (& : Jasper) — jedno okno dla wszystkich poleceń.
        var values = doc.variableValues
        if doc.substitutionEnabled {
            let requests = variableRequests(stmts, remembered: doc.variableValues)
            if !requests.isEmpty {
                guard let answers = await ws.ui?.askVariables(requests, document: doc) else { throw CommandError.cancelledByUser }
                values.merge(answers) { $1 }
                doc.variableValues = values
            }
        }
        let session = try await ws.session(for: doc)
        doc.isExecuting = true
        doc.errorRange = nil
        defer { doc.isExecuting = false }

        // Karty: przypięte zostają, reszta zamykana (UG 7.10).
        for r in doc.results where !r.pinned { await r.grid?.close() }
        doc.results.removeAll { !$0.pinned }
        if doc.outputEnabled && ws.settings.dbmsOutputEnabled {
            if ws.settings.dbmsOutputClearBeforeExecute { doc.output = [] }
            try? await SessionUtilities.enableOutput(session, bufferSize: ws.settings.dbmsOutputBufferSize)
        }
        let start = ContinuousClock.now
        var ok = true
        var changedData = false
        var newTabs: [ResultTab] = []
        for s in stmts {
            let prepared = doc.substitutionEnabled ? Variables.prepare(s.text, values: values) : Variables.Prepared(sql: s.text, binds: [])
            let binds = prepared.binds.map { b -> BindVariable in
                switch b.value {
                case .null: BindVariable(name: b.name, type: .varchar2, value: .null, maxSize: 4000)
                case .text(let t): BindVariable(name: b.name, type: .varchar2, value: .text(t), maxSize: 32767)
                case .list(let l): BindVariable(name: b.name, type: .varchar2, value: .text(l.joined(separator: ",")), maxSize: 32767)
                }
            }
            do {
                let r = try await session.execute(prepared.sql, binds: binds, options: ExecuteOptions(autoCommit: ws.settings.autoCommitSQL))
                ws.recordHistory(s.text)
                doc.statementHistory.append(s.text)
                doc.historyPosition = nil
                let range = s.start..<s.end
                switch r.kind {
                case .query:
                    guard let rs = r.resultSet else { break }
                    let grid = ResultGridModel(columns: rs.columns, resultSet: rs.id, session: session, sql: prepared.sql, format: ws.settings.valueFormat)
                    let tab = ResultTab(title: tabTitle(for: s), statementRange: range, grid: grid)
                    tab.elapsed = r.elapsed
                    await grid.fetchMore(initialRows(for: s, settings: ws.settings))
                    if directive("tab", in: s.text)?.range(of: "&Count", options: .caseInsensitive) != nil {
                        tab.title = tabTitle(for: s, rowCount: grid.rowCount)
                    }
                    newTabs.append(tab)
                default:
                    changedData = changedData || r.kind != StatementKind.ddl
                    var msg: String
                    switch r.kind {
                    case .dml: msg = L10n.tr("Wierszy: \(r.rowsAffected)")
                    case .ddl: msg = r.warning?.code == 24344 ? L10n.tr("Utworzono z błędami kompilacji") : L10n.tr("Wykonano")
                    default: msg = L10n.tr("Wykonano")
                    }
                    for (name, v) in r.outBinds { msg += "   :\(name) = \(v.format(ws.settings.valueFormat))" }
                    let tab = ResultTab(title: tabTitle(for: s), statementRange: range, message: msg)
                    tab.elapsed = r.elapsed
                    for rs in r.implicitResults {
                        let g = ResultGridModel(columns: rs.columns, resultSet: rs.id, session: session, sql: prepared.sql, format: ws.settings.valueFormat)
                        await g.fetchMore(initialRows(for: s, settings: ws.settings))
                        newTabs.append(ResultTab(title: tabTitle(for: s) + " #\(newTabs.count + 1)", statementRange: range, grid: g))
                    }
                    newTabs.append(tab)
                }
            } catch let e as OracleError {
                let local = SessionUtilities.utf16Offset(ofUTF8Offset: Int(e.offset), in: prepared.sql)
                let pos = min(s.start + min(local, s.end - s.start), s.end)
                doc.errorRange = pos..<pos
                newTabs.append(ResultTab(title: tabTitle(for: s), statementRange: s.start..<s.end, message: e.message))
                doc.statusText = e.message
                ok = false
                if e.isConnectionLost { ws.sessions.dropLost(ws.sessions.key(forDocument: doc.id, connection: ws.effectiveConnection(of: doc)!)) }
                break
            }
        }
        doc.results.insert(contentsOf: newTabs, at: 0)
        doc.activeResultID = newTabs.first(where: { $0.grid != nil })?.id ?? newTabs.first?.id
        if doc.outputEnabled && ws.settings.dbmsOutputEnabled, let lines = try? await SessionUtilities.readOutput(session) {
            doc.output.append(contentsOf: lines)
        }
        if changedData || !ok {
            doc.transactionOpen = (try? await SessionUtilities.transactionOpen(session)) ?? doc.transactionOpen
        }
        if ok {
            let elapsed = ContinuousClock.now - start
            let rows = newTabs.first?.grid.map { g in g.hasMore ? L10n.tr("\(g.rowCount) wierszy (więcej…)") : L10n.tr("\(g.rowCount) wierszy") }
            doc.statusText = [rows, newTabs.first?.message, L10n.tr("Czas: \(format(elapsed))")].compactMap { $0 }.joined(separator: "   ·   ")
        }
        return ok
    }

    /// Liczba wierszy pobieranych na start (UG 23.20 Records per page; dyrektywa `-- Records=` — UG 7.12).
    static func initialRows(for s: ScriptStatement, settings: Settings) -> Int {
        if let d = directive("records", in: s.text)?.lowercased() {
            if d == "all" { return 5_000_000 }
            if d == "page" { return 100 }
            if let n = Int(d), n > 0 { return n }
        }
        switch settings.recordsPerPage {
        case .automatic: return 100
        case .fixed(let n): return max(1, n)
        case .all: return 5_000_000
        }
    }

    /// Czas jak we wzorcu: sekundy z ułamkiem, powyżej 100 s jako hh:mm:ss (NF17).
    public static func format(_ d: Duration) -> String {
        let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        if secs >= 100 {
            let s = Int(secs)
            return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
        }
        return String(format: "%.3f s", secs)
    }
}
