import Foundation
import PelikanDB
import PelikanSQL

/// Komendy siatki i SQL Window domknięte w Etapie 8: kursor zagnieżdżony, filtr kolumn, wyrównanie, słownik w siatce,
/// sumy, czcionka, wielkość liter, numery wierszy, odświeżanie, przypinanie, eksport bezpośredni, Query By Example,
/// wklejenie jako nowe SQL Window.
@MainActor
enum GridStage8Commands {
    static let resultMenu = L10n.tr("Wynik")

    static func grid(_ ctx: CommandContext) throws -> (ResultTab, ResultGridModel) {
        guard let g = GridCommands.activeGrid(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak siatki wyników")) }
        return g
    }

    static func command(_ id: CommandID, _ title: String, _ category: CommandCategory = .session, submenu: String? = resultMenu,
                        params: [CommandParameter] = [], mac: [String] = [], agent: AgentAccess = .none, effect: CommandEffect = .uiState,
                        summary: String, feature: String, validate: (@MainActor @Sendable (Workspace) -> Bool)? = nil,
                        _ run: @escaping CommandHandler) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: category, submenu: submenu, mac: mac, parameters: params,
                                  agent: agent, effect: effect, summary: summary, feature: feature), validate: validate, run: run)
    }

    /// Słownik kolumn tabeli wyniku (pamiętany w karcie).
    static func dictionary(_ tab: ResultTab, _ grid: ResultGridModel, ws: Workspace) async throws -> [Int: ColumnDictionaryInfo] {
        if let d = tab.columnInfo { return d }
        guard let doc = SQLCommands.sqlDocument(ws) else { return [:] }
        let s = try await ws.session(for: doc)
        guard let t = try await GridDictionary.table(of: grid.sql, in: s) else { tab.columnInfo = [:]; return [:] }
        let byName = try await GridDictionary.load(owner: t.owner, table: t.table, in: s)
        var out: [Int: ColumnDictionaryInfo] = [:]
        for (i, c) in grid.columns.enumerated() { if let x = byName[c.name] { out[i] = x } }
        tab.columnInfo = out
        return out
    }

    static func currentCells(_ tab: ResultTab, _ grid: ResultGridModel) -> (rows: [Int], column: Int)? {
        guard let col = tab.currentColumn, let rows = tab.selectedRows, !rows.isEmpty else { return nil }
        return (rows, col)
    }

    static func columnIndex(_ ctx: CommandContext, _ tab: ResultTab, _ grid: ResultGridModel) throws -> Int {
        if let name = ctx.arguments.string("column") {
            guard let i = grid.columns.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CommandError.invalidArgument("column", name)
            }
            return i
        }
        guard let c = tab.currentColumn else { throw CommandError.notAvailable(L10n.tr("Wybierz kolumnę w siatce")) }
        return c
    }

    static var all: [Command] {
        let hasGrid: @MainActor @Sendable (Workspace) -> Bool = { GridCommands.activeGrid($0) != nil }
        let hasDoc: @MainActor @Sendable (Workspace) -> Bool = { SQLCommands.sqlDocument($0) != nil }
        return [
            // MARK: Kursor zagnieżdżony (PD-GRID-006)
            command("grid.openCursor", L10n.tr("Otwórz kursor zagnieżdżony"),
                    summary: L10n.tr("Wynik kursora zagnieżdżonego z bieżącej komórki (<Cursor>) w nowej karcie wyniku."), feature: "PD-GRID-006",
                    validate: hasGrid) { ctx in
                let (tab, grid) = try grid(ctx)
                guard let row = tab.selectedRows?.first, let col = tab.currentColumn, case .cursor(let id) = grid.value(row: row, column: col) else {
                    throw CommandError.notAvailable(L10n.tr("Bieżąca komórka nie zawiera kursora"))
                }
                guard let doc = SQLCommands.sqlDocument(ctx.workspace) else { return .ok }
                let s = grid.session
                let child = ResultGridModel(columns: await s.columns(of: id), resultSet: id, session: s, sql: grid.sql, format: grid.format)
                await child.fetchMore(ctx.workspace.settings.recordsPerPage.initialRows)
                let t = ResultTab(title: "\(grid.columns[col].name) #\(row + 1)", statementRange: tab.statementRange, grid: child)
                doc.results.insert(t, at: 0)
                doc.activeResultID = t.id
                return CommandResult(message: L10n.tr("Wierszy: \(child.rowCount)"))
            },
            // MARK: Filtr kolumn (PD-GRID-011)
            command("grid.columnFilter", L10n.tr("Filtr kolumn…"),
                    params: [CommandParameter("names", .string, L10n.tr("Fragmenty nazw (po przecinku albo w liniach)")),
                             CommandParameter("types", .string, L10n.tr("Typy: text, number, date, lob, other")),
                             CommandParameter("mandatory", .boolean, L10n.tr("Tylko obowiązkowe (NOT NULL)")),
                             CommandParameter("keys", .string, L10n.tr("Klucze: primary, unique, foreign"))],
                    summary: L10n.tr("Pokazuje tylko kolumny pasujące do nazw, typów, obowiązkowości i kluczy; lista nazw może być wklejona."),
                    feature: "PD-GRID-011", validate: hasGrid) { ctx in
                let (tab, grid) = try grid(ctx)
                let a = ctx.arguments
                guard a.string("names") != nil || a.string("types") != nil || a.bool("mandatory") != nil || a.string("keys") != nil else {
                    ctx.ui?.showColumnFilter(tab)
                    return .ok
                }
                func set<T: RawRepresentable>(_ k: String, _: T.Type) -> Set<T> where T.RawValue == String {
                    Set((a.string(k) ?? "").split(separator: ",").compactMap { T(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) })
                }
                let f = ColumnFilter(names: ColumnFilter.names(from: a.string("names") ?? ""), types: set("types", ColumnFilter.TypeGroup.self),
                                     mandatoryOnly: a.bool("mandatory") ?? false, keys: set("keys", ColumnFilter.KeyKind.self))
                var keyInfo: [String: Set<ColumnFilter.KeyKind>] = [:], mandatory: Set<String> = []
                if !f.keys.isEmpty || f.mandatoryOnly {
                    for (i, info) in try await dictionary(tab, grid, ws: ctx.workspace) {
                        keyInfo[grid.columns[i].name.uppercased()] = info.keys
                        if !info.nullable { mandatory.insert(grid.columns[i].name.uppercased()) }
                    }
                }
                let visible = f.visible(grid.columns, keyInfo: keyInfo, mandatory: mandatory)
                tab.columnFilter = f.isEmpty ? nil : f
                tab.hiddenColumns = Set(grid.columns.indices).subtracting(visible)
                if let text = a.string("names"), !text.isEmpty {
                    let h = [text] + ctx.workspace.settings.columnFilterHistory.filter { $0 != text }
                    ctx.workspace.settings.columnFilterHistory = Array(h.prefix(10))
                }
                return CommandResult(message: L10n.tr("Widoczne kolumny: \(visible.count) z \(grid.columns.count)"),
                                     value: .array(visible.sorted().map { .string(grid.columns[$0].name) }))
            },
            command("grid.clearColumnFilter", L10n.tr("Pokaż wszystkie kolumny"),
                    summary: L10n.tr("Wyłącza filtr kolumn siatki."), feature: "PD-GRID-011", validate: hasGrid) { ctx in
                let (tab, _) = try grid(ctx)
                tab.columnFilter = nil
                tab.hiddenColumns = []
                return .ok
            },
            // MARK: Wyrównanie (PD-GRID-012)
            command("grid.align", L10n.tr("Wyrównaj kolumny"),
                    params: [CommandParameter("mode", .string, L10n.tr("header, content albo both (domyślnie)"))],
                    summary: L10n.tr("Ustawia szerokości kolumn według nagłówków, treści albo obu."), feature: "PD-GRID-012", validate: hasGrid) { ctx in
                let (tab, grid) = try grid(ctx)
                let raw = ctx.arguments.string("mode") ?? "both"
                guard let mode = GridAlignMode(rawValue: raw) else { throw CommandError.invalidArgument("mode", raw) }
                tab.columnWidths = GridAlign.widths(grid, mode: mode)
                return .ok
            },
            command("sql.toggleEditor", L10n.tr("Ukryj edytor"),
                    summary: L10n.tr("Ukrywa albo pokazuje edytor okna SQL — wyniki zajmują całe okno."), feature: "PD-GRID-012",
                    validate: { $0.activeDocument?.kind == .sql }) { ctx in
                guard let doc = ctx.workspace.activeDocument, doc.kind == .sql else { throw CommandError.notAvailable(L10n.tr("Brak okna SQL")) }
                doc.editorHidden.toggle()
                return CommandResult(message: doc.editorHidden ? L10n.tr("Edytor ukryty") : L10n.tr("Edytor widoczny"))
            },
            command("grid.rowHeight", L10n.tr("Wysokość wierszy…"),
                    params: [CommandParameter("lines", .string, L10n.tr("Linie na wiersz 1–10 albo auto (wg treści)"))],
                    summary: L10n.tr("Ustawia wysokość wierszy siatki w liniach tekstu (wieloliniowe wartości zawijane) albo wg treści."),
                    feature: "PD-GRID-012", validate: hasGrid) { ctx in
                let (tab, grid) = try grid(ctx)
                var raw = ctx.arguments.string("lines")
                if raw == nil, ctx.invoker == .user, let ui = ctx.ui {
                    raw = await ui.chooseValue(L10n.tr("Wysokość wierszy"), values: ["auto"] + (1...10).map(String.init))
                    if raw == nil { throw CommandError.cancelledByUser }
                }
                let value = raw ?? "auto"
                if value == "auto" { tab.rowLines = GridAlign.rowLines(grid) } else {
                    guard let n = Int(value), (1...10).contains(n) else { throw CommandError.invalidArgument("lines", value) }
                    tab.rowLines = n
                }
                return CommandResult(message: L10n.tr("Linii na wiersz: \(tab.rowLines)"), value: .int(Int64(tab.rowLines)))
            },
            command("grid.saveAlignTemplate", L10n.tr("Zapisz wyrównanie dla zapytania"),
                    summary: L10n.tr("Zapamiętuje kolejność i szerokości kolumn dla tego zapytania; stosowane przy kolejnych wykonaniach."),
                    feature: "PD-GRID-012", validate: hasGrid) { ctx in
                let (tab, grid) = try grid(ctx)
                ctx.workspace.settings.alignTemplates[GridAlign.key(for: grid.sql)] = GridAlign.template(grid, tab: tab)
                return .ok
            },
            command("grid.removeAlignTemplate", L10n.tr("Usuń wyrównanie zapytania"),
                    summary: L10n.tr("Usuwa zapisany szablon wyrównania tego zapytania."), feature: "PD-GRID-012", validate: hasGrid) { ctx in
                let (tab, grid) = try grid(ctx)
                ctx.workspace.settings.alignTemplates[GridAlign.key(for: grid.sql)] = nil
                tab.columnWidths = nil
                return .ok
            },
            // MARK: Słownik w siatce (PD-GRID-022)
            command("grid.columnInfo", L10n.tr("Informacje o kolumnie"),
                    summary: L10n.tr("Typ, NOT NULL, klucze i komentarz bieżącej kolumny ze słownika (pasek stanu)."),
                    feature: "PD-GRID-022", validate: hasGrid) { ctx in
                let (tab, grid) = try grid(ctx)
                let c = try columnIndex(ctx, tab, grid)
                let info = try await dictionary(tab, grid, ws: ctx.workspace)[c]
                let line = grid.columns[c].name + ": " + (info?.statusLine ?? grid.columns[c].typeName + (grid.columns[c].nullable ? "" : " NOT NULL"))
                SQLCommands.sqlDocument(ctx.workspace)?.statusText = line
                return CommandResult(message: line, value: .object(["column": .string(grid.columns[c].name), "info": .string(line),
                                                                    "values": .array((info?.values ?? []).map { .string($0) })]))
            },
            command("grid.valueList", L10n.tr("Lista wartości…"),
                    summary: L10n.tr("Wartość bieżącej komórki z listy: CHECK … IN (…) albo klucz obcy do małej tabeli (tryb edycji)."),
                    feature: "PD-GRID-022", validate: { ws in GridCommands.activeGrid(ws)?.1.edit.isEditing ?? false }) { ctx in
                let (tab, grid) = try grid(ctx)
                guard let (rows, col) = currentCells(tab, grid) else { throw CommandError.notAvailable(L10n.tr("Wybierz komórkę")) }
                let values = try await dictionary(tab, grid, ws: ctx.workspace)[col]?.values ?? []
                guard !values.isEmpty else { throw CommandError.notAvailable(L10n.tr("Kolumna \(grid.columns[col].name) nie ma listy wartości")) }
                let chosen: String?
                if let v = ctx.arguments.string("value") { chosen = v } else { chosen = await ctx.ui?.chooseValue(grid.columns[col].name, values: values) }
                guard let chosen else { throw CommandError.cancelledByUser }
                for r in rows { try grid.setText(chosen, row: r, column: col) }
                return .ok
            },
            // MARK: Sumy (PD-GRID-024)
            command("grid.totals", L10n.tr("Sumy kolumny…"),
                    params: [CommandParameter("column", .string, L10n.tr("Kolumna (domyślnie bieżąca)")),
                             CommandParameter("functions", .string, L10n.tr("sum, count, avg, min, max (po przecinku; puste — wyłącz)"))],
                    summary: L10n.tr("Pokazuje pod siatką sumę, liczbę, średnią, minimum lub maksimum kolumny; ustawienie zostaje po ponownym wykonaniu."),
                    feature: "PD-GRID-024", validate: hasGrid) { ctx in
                let (tab, grid) = try grid(ctx)
                let c = try columnIndex(ctx, tab, grid)
                let raw = ctx.arguments.string("functions") ?? (grid.columns[c].type.isNumeric ? "sum,avg,min,max" : "count")
                let aggs = raw.split(separator: ",").compactMap { ColumnAggregate(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
                tab.totals[c] = aggs.isEmpty ? nil : aggs
                SQLCommands.sqlDocument(ctx.workspace)?.columnTotals[grid.columns[c].name.uppercased()] = aggs.isEmpty ? nil : aggs
                let values = ColumnTotals.compute(grid, column: c, aggs)
                return CommandResult(message: ColumnTotals.summary(grid, totals: [c: aggs]),
                                     value: .object(Dictionary(uniqueKeysWithValues: values.map { ($0.0.rawValue, JSONValue.string($0.1)) })))
            },
            command("grid.clearTotals", L10n.tr("Wyłącz sumy"),
                    summary: L10n.tr("Usuwa wszystkie sumy kolumn tego okna."), feature: "PD-GRID-024", validate: hasGrid) { ctx in
                let (tab, _) = try grid(ctx)
                tab.totals = [:]
                SQLCommands.sqlDocument(ctx.workspace)?.columnTotals = [:]
                return .ok
            },
            // MARK: Czcionka siatki (PD-GRID-025)
            command("grid.fontLarger", L10n.tr("Większa czcionka siatki"), .view, submenu: L10n.tr("Siatka"), effect: .settings,
                    summary: L10n.tr("Powiększa czcionkę siatki wyników."), feature: "PD-GRID-025") { ctx in
                ctx.workspace.settings.gridFontSize = min(32, ctx.workspace.settings.gridFontSize + 1)
                return .ok
            },
            command("grid.fontSmaller", L10n.tr("Mniejsza czcionka siatki"), .view, submenu: L10n.tr("Siatka"), effect: .settings,
                    summary: L10n.tr("Pomniejsza czcionkę siatki wyników."), feature: "PD-GRID-025") { ctx in
                ctx.workspace.settings.gridFontSize = max(8, ctx.workspace.settings.gridFontSize - 1)
                return .ok
            },
            command("grid.fontReset", L10n.tr("Domyślna czcionka siatki"), .view, submenu: L10n.tr("Siatka"), effect: .settings,
                    summary: L10n.tr("Przywraca domyślny rozmiar czcionki siatki."), feature: "PD-GRID-025") { ctx in
                ctx.workspace.settings.gridFontSize = 12
                return .ok
            },
            // MARK: Wielkość liter w siatce (PD-GRID-026)
            command("grid.upperCase", L10n.tr("Wielkie litery w komórkach"), .edit, effect: .modifiesEditor,
                    summary: L10n.tr("Zamienia tekst zaznaczonych komórek bieżącej kolumny na wielkie litery (tryb edycji)."),
                    feature: "PD-GRID-026", validate: { ws in GridCommands.activeGrid(ws)?.1.edit.isEditing ?? false }) { ctx in
                try changeCase(ctx, upper: true)
            },
            command("grid.lowerCase", L10n.tr("Małe litery w komórkach"), .edit, effect: .modifiesEditor,
                    summary: L10n.tr("Zamienia tekst zaznaczonych komórek bieżącej kolumny na małe litery (tryb edycji)."),
                    feature: "PD-GRID-026", validate: { ws in GridCommands.activeGrid(ws)?.1.edit.isEditing ?? false }) { ctx in
                try changeCase(ctx, upper: false)
            },
            // MARK: Numer wiersza w kopiowaniu (PD-GRID-027)
            command("grid.toggleRowNumbers", L10n.tr("Numer wiersza w kopiowaniu i eksporcie"), .view, submenu: L10n.tr("Siatka"),
                    effect: .settings, summary: L10n.tr("Włącza albo wyłącza kolumnę z numerem wiersza przy kopiowaniu i eksporcie siatki."),
                    feature: "PD-GRID-027") { ctx in
                ctx.workspace.settings.rowNumbersInCopyExport.toggle()
                return CommandResult(value: .bool(ctx.workspace.settings.rowNumbersInCopyExport))
            },
            // MARK: Odświeżanie (PD-SQLW-006, PD-VAR-008)
            command("sql.refreshResult", L10n.tr("Odśwież wynik"), mac: ["cmd+shift+r"],
                    summary: L10n.tr("Wykonuje ponownie polecenie bieżącej karty z zapamiętanymi wartościami zmiennych."),
                    feature: "PD-SQLW-006", validate: hasGrid) { ctx in
                guard let doc = SQLCommands.sqlDocument(ctx.workspace) else { return .ok }
                let (tab, _) = try grid(ctx)
                try await SQLExecutor.rerun(tab, in: doc, ws: ctx.workspace)
                return CommandResult(message: doc.statusText)
            },
            command("sql.autoRefresh", L10n.tr("Automatyczne odświeżanie…"),
                    params: [CommandParameter("seconds", .integer, L10n.tr("Okres w sekundach (0 — wyłącz)"))],
                    summary: L10n.tr("Odświeża wyniki okna co podaną liczbę sekund, bez pytania o zmienne."), feature: "PD-SQLW-006",
                    validate: hasDoc) { ctx in
                guard let doc = SQLCommands.sqlDocument(ctx.workspace) else { return .ok }
                var seconds = ctx.arguments.int("seconds").map(Int.init)
                if seconds == nil, let ui = ctx.ui {
                    guard let t = await ui.askText(L10n.tr("Automatyczne odświeżanie"), message: L10n.tr("Okres w sekundach (0 — wyłącz)"),
                                                   defaultValue: String(doc.autoRefreshSeconds ?? 10)) else { throw CommandError.cancelledByUser }
                    guard let n = Int(t.trimmingCharacters(in: .whitespaces)), n >= 0 else { throw CommandError.invalidArgument("seconds", t) }
                    seconds = n
                }
                SQLExecutor.setAutoRefresh(doc, seconds: seconds, ws: ctx.workspace)
                return CommandResult(message: doc.autoRefreshSeconds.map { L10n.tr("Odświeżanie co \($0) s") } ?? L10n.tr("Odświeżanie wyłączone"))
            },
            // MARK: Przypinanie (PD-SQLW-017)
            command("sql.pinResult", L10n.tr("Przypnij wynik"),
                    summary: L10n.tr("Przypina albo odpina bieżącą kartę wyniku — przypięta nie znika przy kolejnym wykonaniu (także Shift+klik karty)."),
                    feature: "PD-SQLW-017", validate: { GridCommands.activeTab($0) != nil }) { ctx in
                guard let tab = GridCommands.activeTab(ctx.workspace) else { return .ok }
                tab.pinned.toggle()
                return CommandResult(value: .bool(tab.pinned))
            },
            command("sql.pinAllResults", L10n.tr("Przypnij wszystkie wyniki"),
                    summary: L10n.tr("Przypina wszystkie karty wyników okna."), feature: "PD-SQLW-017", validate: hasDoc) { ctx in
                SQLCommands.sqlDocument(ctx.workspace)?.results.forEach { $0.pinned = true }
                return .ok
            },
            command("sql.clearResults", L10n.tr("Wyczyść karty wyników"),
                    params: [CommandParameter("all", .boolean, L10n.tr("Także przypięte"))],
                    summary: L10n.tr("Zamyka karty wyników okna (domyślnie bez przypiętych)."), feature: "PD-SQLW-017", validate: hasDoc) { ctx in
                guard let doc = SQLCommands.sqlDocument(ctx.workspace) else { return .ok }
                let all = ctx.arguments.bool("all") ?? false
                for r in doc.results where all || !r.pinned { await r.grid?.close() }
                doc.results.removeAll { all || !$0.pinned }
                if !doc.results.contains(where: { $0.id == doc.activeResultID }) { doc.activeResultID = doc.results.first?.id }
                return .ok
            },
            // MARK: Eksport bezpośredni (PD-SQLW-018)
            command("sql.exportQuery", L10n.tr("Eksportuj zapytanie do pliku…"),
                    params: [CommandParameter("format", .string, L10n.tr("csv, tsv, html, xml, sql, xlsx")),
                             CommandParameter("file", .string, L10n.tr("Plik (puste — wybór; „clipboard” — schowek)"))],
                    effect: .modifiesDatabase,
                    summary: L10n.tr("Wykonuje polecenie pod kursorem i zapisuje cały wynik prosto do pliku albo schowka, bez siatki."),
                    feature: "PD-SQLW-018", validate: hasDoc) { ctx in
                try await directExport(ctx)
            },
            // MARK: Query By Example (PD-SQLW-022)
            command("grid.queryByExample", L10n.tr("Query By Example…"),
                    params: [CommandParameter("criteria", .object, L10n.tr("Kolumna → kryterium (wartość, %, > < <> , in (…), between … and …, null)"))],
                    mac: ["cmd+shift+e"],
                    summary: L10n.tr("Zawęża wynik kryteriami wpisanymi pod nazwami kolumn i wykonuje zapytanie ponownie."),
                    feature: "PD-SQLW-022", validate: { ws in GridCommands.activeTab(ws)?.statementText != nil }) { ctx in
                guard let doc = SQLCommands.sqlDocument(ctx.workspace) else { return .ok }
                let (tab, grid) = try grid(ctx)
                guard case .object(let o)? = ctx.arguments.values["criteria"] else {
                    ctx.ui?.showQueryByExample(tab)
                    return .ok
                }
                var criteria: [Int: String] = [:]
                for (name, v) in o {
                    guard let i = grid.columns.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                        throw CommandError.invalidArgument("criteria", name)
                    }
                    if case .string(let s) = v, !s.trimmingCharacters(in: .whitespaces).isEmpty { criteria[i] = s }
                }
                // Sprawdzenie kryteriów przed wykonaniem (komunikat wskazuje kolumnę).
                _ = try QueryByExample.apply(sql: "select 1 from dual", criteria: criteria.map { (grid.columns[$0.key], $0.value) },
                                             options: SQLExecutor.qbeOptions(ctx.workspace))
                tab.qbeCriteria = criteria
                try await SQLExecutor.rerun(tab, in: doc, ws: ctx.workspace)
                return CommandResult(message: doc.statusText, value: .string(tab.grid?.sql ?? ""))
            },
            command("grid.clearQueryByExample", L10n.tr("Wyczyść Query By Example"),
                    summary: L10n.tr("Usuwa kryteria Query By Example i wykonuje zapytanie ponownie."), feature: "PD-SQLW-022",
                    validate: { ws in !(GridCommands.activeTab(ws)?.qbeCriteria.isEmpty ?? true) }) { ctx in
                guard let doc = SQLCommands.sqlDocument(ctx.workspace) else { return .ok }
                let (tab, _) = try grid(ctx)
                tab.qbeCriteria = [:]
                try await SQLExecutor.rerun(tab, in: doc, ws: ctx.workspace)
                return .ok
            },
            // MARK: Wklejenie jako nowe SQL Window (PD-SQLW-025)
            command("file.pasteAsSQLWindow", L10n.tr("Wklej jako nowe SQL Window"), .file, submenu: nil,
                    summary: L10n.tr("Tworzy SQL Window z tekstem ze schowka (także wklejenie na pusty obszar okien)."),
                    feature: "PD-SQLW-025") { ctx in
                guard let text = ctx.ui?.clipboardText(), !text.isEmpty else { throw CommandError.notAvailable(L10n.tr("Schowek nie zawiera tekstu")) }
                let doc = ctx.workspace.newDocument(.sql, text: text)
                doc.isModified = true
                return .ok
            },
        ]
    }

    static func changeCase(_ ctx: CommandContext, upper: Bool) throws -> CommandResult {
        let (tab, grid) = try grid(ctx)
        guard let (rows, col) = currentCells(tab, grid) else { throw CommandError.notAvailable(L10n.tr("Wybierz komórki")) }
        guard grid.isEditable(column: col) else { throw CommandError.notAvailable(L10n.tr("Kolumna \(grid.columns[col].name) nie jest edytowalna")) }
        var changed = 0
        for r in rows {
            guard case .text(let s) = grid.value(row: r, column: col) else { continue }
            let n = upper ? s.uppercased() : s.lowercased()
            if n != s { try grid.setText(n, row: r, column: col); changed += 1 }
        }
        return CommandResult(message: L10n.tr("Zmienione komórki: \(changed)"))
    }

    static func directExport(_ ctx: CommandContext) async throws -> CommandResult {
        let ws = ctx.workspace
        guard let doc = SQLCommands.sqlDocument(ws) else { return .ok }
        let raw = ctx.arguments.string("format") ?? "csv"
        guard let format = ExportFormat(rawValue: raw), format != .expressionList else { throw CommandError.invalidArgument("format", raw) }
        guard let s = SQLExecutor.statements(text: doc.text, selection: doc.selectedRange, scope: .currentStatement, autoSelect: true).first else {
            throw CommandError.notAvailable(L10n.tr("Brak polecenia do wykonania"))
        }
        try await ws.guardModification([s.text], connectionID: ws.effectiveConnection(of: doc))
        var values = doc.variableValues
        if doc.substitutionEnabled {
            let requests = SQLExecutor.variableRequests([s], remembered: doc.variableValues)
            if !requests.isEmpty {
                guard let answers = await ws.ui?.askVariables(requests, document: doc) else { throw CommandError.cancelledByUser }
                values.merge(answers) { $1 }
                doc.variableValues = values
            }
        }
        let prepared = doc.substitutionEnabled ? Variables.prepare(s.text, values: values) : Variables.Prepared(sql: s.text, binds: [])
        let session = try await ws.session(for: doc)
        doc.isExecuting = true
        defer { doc.isExecuting = false }
        let r = try await session.execute(prepared.sql, binds: SQLExecutor.bindVariables(prepared),
                                          options: ExecuteOptions(autoCommit: ws.settings.autoCommitSQL, lobLimit: 64 << 20))
        guard let rs = r.resultSet else { throw CommandError.notAvailable(L10n.tr("Polecenie nie zwróciło wyniku")) }
        var rows: [[OracleValue]] = []
        while true {
            let batch = try await session.fetch(rs.id, maxRows: 10_000)
            rows.append(contentsOf: batch.rows)
            if !batch.hasMore { break }
        }
        await session.closeResultSet(rs.id)
        let data = ExportData(title: SQLExecutor.tabTitle(for: s), columns: rs.columns, rows: rows,
                              tableName: ResultExporter.tableName(fromQuery: prepared.sql), sql: prepared.sql)
        var o = ExportOptions()
        o.format = ws.settings.valueFormat
        let file = ctx.arguments.string("file")
        if file == "clipboard" {
            ws.ui?.copyToClipboard(ResultExporter.text(format, data, options: o), html: nil)
            return CommandResult(message: L10n.tr("Skopiowano wierszy: \(rows.count)"))
        }
        let url: URL
        if let file, !file.isEmpty {
            url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        } else {
            guard let u = await ws.ui?.chooseSaveURL(suggestedName: data.title, fileExtension: format.fileExtension) else { throw CommandError.cancelledByUser }
            url = u
        }
        let bytes = format == .xlsx ? ResultExporter.xlsx([data], options: o) : Data(ResultExporter.text(format, data, options: o).utf8)
        try bytes.write(to: url, options: .atomic)
        doc.statusText = L10n.tr("Zapisano wierszy: \(rows.count) do \(url.lastPathComponent)")
        return CommandResult(message: doc.statusText, value: .int(Int64(rows.count)))
    }
}
