import Foundation
import PelikanDB
import PelikanLog
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
            || u.range(of: #"^\s*CONN(ECT)?\s+[^@\s]*/"#, options: .regularExpression) != nil   // u/hasło[@baza]; bez „/” — bez hasła
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
        try await ws.guardModification(stmts.map(\.text), connectionID: ws.effectiveConnection(of: doc))
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
        // Karta Statystyki (PD-SQLW-008): różnica V$MYSTAT przed i po wykonaniu (bez uprawnień — karta pusta).
        let statsBefore = ws.settings.sqlWindowStatistics ? await Profiler.statistics(session) : nil
        var ok = true
        var changedData = false
        var newTabs: [ResultTab] = []
        for s in stmts {
            let prepared = doc.substitutionEnabled ? Variables.prepare(s.text, values: values) : Variables.Prepared(sql: s.text, binds: [])
            let binds = bindVariables(prepared)
            let statementStart = ContinuousClock.now
            do {
                let r = try await session.execute(prepared.sql, binds: binds, options: executeOptions(ws))
                // Dziennik (D170): rodzaj polecenia, czas i liczba wierszy — nigdy treść polecenia ani wartości.
                Log.sql.debug("Polecenie \(r.kind.rawValue, privacy: .public): \(ms: statementStart), wierszy zmienionych \(r.rowsAffected)")
                ws.recordHistory(s.text)
                // Historia poleceń okna bez haseł (CONNECT, IDENTIFIED BY) — jak historia SQL.
                if !containsPassword(s.text) { doc.statementHistory.append(s.text) }
                doc.historyPosition = nil
                let range = s.start..<s.end
                switch r.kind {
                case .query:
                    guard let rs = r.resultSet else { break }
                    let grid = ResultGridModel(columns: rs.columns, resultSet: rs.id, session: session, sql: prepared.sql, format: ws.settings.valueFormat)
                    configure(grid, ws: ws)
                    let tab = ResultTab(title: tabTitle(for: s), statementRange: range, grid: grid)
                    tab.elapsed = r.elapsed
                    tab.statementText = s.text
                    await grid.fetchMore(initialRows(for: s, settings: ws.settings))
                    if directive("tab", in: s.text)?.range(of: "&Count", options: .caseInsensitive) != nil {
                        tab.title = tabTitle(for: s, rowCount: grid.rowCount)
                    }
                    try await applyDirectives(s.text, tab: tab, grid: grid, doc: doc, ws: ws, values: values)
                    newTabs.append(tab)
                default:
                    // Także DDL: niejawny COMMIT zamyka transakcję — stan odczytywany z sesji.
                    changedData = true
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
                        configure(g, ws: ws)
                        await g.fetchMore(initialRows(for: s, settings: ws.settings))
                        newTabs.append(ResultTab(title: tabTitle(for: s) + " #\(newTabs.count + 1)", statementRange: range, grid: g))
                    }
                    newTabs.append(tab)
                }
            } catch let e as OracleError {
                Log.sql.info("Polecenie zakończone błędem po \(ms: statementStart): \(e as any Error)")
                // Pozycja błędu tylko dla błędów w tekście polecenia (nie przy przerwaniu ani utracie połączenia).
                if !e.isCancelled, !e.isConnectionLost {
                    let local = SessionUtilities.utf16Offset(ofUTF8Offset: Int(e.offset), in: prepared.sql)
                    let pos = min(s.start + min(local, s.end - s.start), s.end)
                    doc.errorRange = pos..<pos
                }
                newTabs.append(ResultTab(title: tabTitle(for: s), statementRange: s.start..<s.end, message: e.message))
                doc.statusText = SQLExecutor.statusMessage(for: e)
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
        if let before = statsBefore, let after = await Profiler.statistics(session) {
            doc.recordStatistics(Profiler.difference(before, after))
        }
        let elapsed = ContinuousClock.now - start
        Log.sql.info("Okno SQL: poleceń \(stmts.count), czas \(ms: start)\(ok ? "" : ", przerwane błędem", privacy: .public)")
        if ok {
            // Liczbę wierszy aktywnej siatki pokazuje `Document.resultSummary` (zmienia się przy dociąganiu).
            doc.statusText = [newTabs.first?.message, L10n.tr("Czas: \(format(elapsed))")].compactMap { $0 }.joined(separator: "   ·   ")
        }
        // Powiadomienie o końcu długiego wykonania (PD-SQLW-015, NF8).
        let threshold = ws.settings.notifyLongQuerySeconds
        if threshold > 0, elapsed >= .seconds(threshold) { ws.ui?.notifyExecutionFinished(title: doc.title, elapsed: format(elapsed), success: ok) }
        return ok
    }

    /// Tekst paska stanu dla błędu: pierwsza linia komunikatu; przy wyczyszczonym stanie pakietów — wyjaśnienie.
    public static func statusMessage(for e: OracleError) -> String {
        let first = e.message.components(separatedBy: "\n").first ?? e.message
        guard e.isDiscardedPackageState else { return first }
        return L10n.tr("⚠️ Stan pakietów sesji został wyczyszczony (pakiet zrekompilowano) — wykonaj ponownie. \(first)")
    }

    /// Zmienne wiązane z przygotowanego polecenia (listy jako tekst po przecinku).
    static func bindVariables(_ prepared: Variables.Prepared) -> [BindVariable] {
        prepared.binds.map { b -> BindVariable in
            switch b.value {
            case .null: BindVariable(name: b.name, type: .varchar2, value: .null, maxSize: 4000)
            case .text(let t): BindVariable(name: b.name, type: .varchar2, value: .text(t), maxSize: 32767)
            case .list(let l): BindVariable(name: b.name, type: .varchar2, value: .text(l.joined(separator: ",")), maxSize: 32767)
            }
        }
    }

    /// LOB na żądanie (PD-GRID-023): w siatce tylko początek wartości, całość w Large Data Editor.
    static let lobPreviewBytes = 4000

    static func executeOptions(_ ws: Workspace) -> ExecuteOptions {
        ExecuteOptions(autoCommit: ws.settings.autoCommitSQL, lobLimit: ws.settings.fetchLOBsOnDemand ? lobPreviewBytes : nil)
    }

    /// Limit rozmiaru wyniku z pytaniem przed dalszym pobieraniem (PD-SQLW-026).
    static func configure(_ grid: ResultGridModel, ws: Workspace) {
        grid.sizeLimitBytes = max(0, ws.settings.maximumResultSetMegabytes) << 20
        grid.confirmSizeLimit = { [weak ws] bytes in
            guard let ui = ws?.ui else { return false }
            return await ui.ask(L10n.tr("Wynik zajmuje ponad \(bytes >> 20) MB"),
                                message: L10n.tr("Pobieranie kolejnych wierszy zwiększy zużycie pamięci (limit w Preferencjach › SQL Window)."),
                                buttons: [L10n.tr("Pobieraj dalej"), L10n.tr("Zatrzymaj")]) == 0
        }
    }

    /// Dyrektywy wyniku (UG 7.12): `Totals=`, `AltRowColor=`, `Excel=`/`CSV=` (eksport całego wyniku do pliku); sumy
    /// zapamiętane w oknie dla nazw kolumn i szablon wyrównania zapytania.
    static func applyDirectives(_ text: String, tab: ResultTab, grid: ResultGridModel, doc: Document, ws: Workspace,
                                values: [String: VariableValue]) async throws {
        var totals = ColumnTotals.parse(directive("totals", in: text) ?? "", columns: grid.columns)
        for (i, c) in grid.columns.enumerated() {
            if let aggs = doc.columnTotals[c.name.uppercased()], totals[i] == nil { totals[i] = aggs }
        }
        tab.totals = totals
        tab.altRowColor = directive("altrowcolor", in: text)
        if ws.settings.autoAlign, let t = ws.settings.alignTemplates[GridAlign.key(for: grid.sql)] { GridAlign.apply(t, to: grid, tab: tab) }
        let targets: [(String, ExportFormat)] = [("excel", ExportFormat.xlsx), ("csv", .csv)].compactMap { k, f in directive(k, in: text).map { ($0, f) } }
        guard !targets.isEmpty else { return }
        await grid.fetchAll()
        let data = grid.exportData(title: tab.title)
        let def = ws.effectiveConnection(of: doc).flatMap { ws.connections.connection($0) }
        let base = doc.fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        var o = ExportOptions()
        o.format = ws.settings.valueFormat
        for (template, format) in targets {
            let url = ExportDirectives.path(template, user: def?.target.user ?? "", database: def?.target.connectString ?? "", values: values,
                                            now: Date(), base: base)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = format == .xlsx ? ResultExporter.xlsx([data], options: o) : Data(ResultExporter.text(format, data, options: o).utf8)
            try bytes.write(to: url, options: .atomic)
            doc.output.append(L10n.tr("Wynik zapisany do pliku \(url.path) (wierszy: \(data.rows.count))"))
        }
    }

    /// Ponowne wykonanie polecenia karty (Refresh, Auto Refresh, QBE — PD-SQLW-006, PD-SQLW-022): wartości zmiennych
    /// zapamiętane w oknie bez pytania (PD-VAR-008), kryteria QBE karty, sumy i filtr kolumn zachowane.
    public static func rerun(_ tab: ResultTab, in doc: Document, ws: Workspace) async throws {
        guard let text = tab.statementText else { throw CommandError.notAvailable(L10n.tr("Karta nie pochodzi z zapytania")) }
        let session = try await ws.session(for: doc)
        let prepared = doc.substitutionEnabled ? Variables.prepare(text, values: doc.variableValues) : Variables.Prepared(sql: text, binds: [])
        var sql = prepared.sql
        if let old = tab.grid, !tab.qbeCriteria.isEmpty {
            let criteria = tab.qbeCriteria.sorted { $0.key < $1.key }.compactMap { k, v in k < old.columns.count ? (old.columns[k], v) : nil }
            sql = try QueryByExample.apply(sql: sql, criteria: criteria, options: qbeOptions(ws))
        }
        doc.isExecuting = true
        defer { doc.isExecuting = false }
        let r = try await session.execute(sql, binds: bindVariables(prepared), options: executeOptions(ws))
        guard let rs = r.resultSet else { throw CommandError.notAvailable(L10n.tr("Polecenie nie zwróciło wyniku")) }
        let grid = ResultGridModel(columns: rs.columns, resultSet: rs.id, session: session, sql: sql, format: ws.settings.valueFormat)
        configure(grid, ws: ws)
        let previous = tab.grid
        await previous?.close()
        await grid.fetchMore(max(previous?.rowCount ?? 0, ws.settings.recordsPerPage.initialRows))
        tab.grid = grid
        tab.elapsed = r.elapsed
        tab.columnInfo = nil
        if let f = tab.columnFilter { tab.hiddenColumns = Set(grid.columns.indices).subtracting(f.visible(grid.columns)) }
        doc.statusText = L10n.tr("Odświeżono: \(grid.rowCount) wierszy   ·   Czas: \(format(r.elapsed))")
    }

    static func qbeOptions(_ ws: Workspace) -> QBEOptions {
        QBEOptions(caseInsensitive: ws.settings.qbeCaseInsensitive, autoContains: ws.settings.qbeAutoContains, ignoreTime: ws.settings.qbeIgnoreTime)
    }

    /// Automatyczne odświeżanie wyników okna co `seconds` sekund (nil/0 — wyłączone; PD-SQLW-006).
    public static func setAutoRefresh(_ doc: Document, seconds: Int?, ws: Workspace) {
        doc.autoRefreshTask?.cancel()
        doc.autoRefreshTask = nil
        guard let seconds, seconds > 0 else { doc.autoRefreshSeconds = nil; return }
        doc.autoRefreshSeconds = seconds
        doc.autoRefreshTask = Task { @MainActor [weak doc, weak ws] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let doc, let ws, ws.documents.contains(where: { $0 === doc }) else { return }
                guard !doc.isExecuting else { continue }
                for tab in doc.results where tab.statementText != nil && tab.grid != nil {
                    do { try await rerun(tab, in: doc, ws: ws) } catch {
                        doc.statusText = error.localizedDescription
                        break
                    }
                }
            }
        }
    }

    /// Liczba wierszy pobieranych na start (UG 23.20 Records per page; dyrektywa `-- Records=` — UG 7.12).
    static func initialRows(for s: ScriptStatement, settings: Settings) -> Int {
        if let d = directive("records", in: s.text)?.lowercased() {
            if d == "all" { return 5_000_000 }
            if d == "page" { return 100 }
            if let n = Int(d), n > 0 { return n }
        }
        return settings.recordsPerPage.initialRows
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
