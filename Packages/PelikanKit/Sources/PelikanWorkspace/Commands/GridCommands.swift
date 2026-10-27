import Foundation
import PelikanDB

/// Komendy siatki wyników (UG 7.1, 7.2): strony, eksport, kopiowanie.
public enum GridCommands {
    @MainActor
    static func activeTab(_ ws: Workspace) -> ResultTab? {
        guard let doc = SQLCommands.sqlDocument(ws) else { return nil }
        return doc.results.first { $0.id == doc.activeResultID } ?? doc.results.first
    }

    @MainActor
    static func activeGrid(_ ws: Workspace) -> (ResultTab, ResultGridModel)? {
        guard let tab = activeTab(ws), let grid = tab.grid else { return nil }
        return (tab, grid)
    }

    /// Zmiany siatki do zatwierdzenia — także wartość wpisywana w otwartym edytorze komórki (trafi do modelu po
    /// `commitPendingEdits`).
    @MainActor
    static func hasPendingChanges(_ ws: Workspace) -> Bool {
        activeGrid(ws).map { $0.1.edit.hasChanges || $0.1.cellEditorOpen } ?? false
    }

    /// Zaznaczenie (albo wszystkie pobrane wiersze) w kolejności widoku.
    @MainActor
    static func selection(_ ws: Workspace) -> ExportData? {
        guard let (tab, grid) = activeGrid(ws) else { return nil }
        let rows = tab.selectedRows.flatMap { $0.isEmpty ? nil : $0 }
        // Kolumny ukryte filtrem kolumn nie trafiają do kopii ani eksportu (PD-GRID-011).
        var columns = (tab.columnOrder ?? Array(grid.columns.indices)).filter { !tab.hiddenColumns.contains($0) }
        // Blok komórek (PD-GRID-007): tylko kolumny bloku, w kolejności widocznej.
        if let block = tab.selectedColumns, !block.isEmpty { columns = columns.filter { block.contains($0) } }
        var data = grid.exportData(rows: rows, columns: columns, title: tab.title)
        if ws.settings.rowNumbersInCopyExport { data = withRowNumbers(data, viewRows: rows ?? Array(0..<grid.rowCount)) }
        return data
    }

    /// Numer wiersza (widoku, od 1) jako pierwsza kolumna kopii i eksportu (PD-GRID-027).
    static func withRowNumbers(_ d: ExportData, viewRows: [Int]) -> ExportData {
        var out = d
        out.columns.insert(ColumnInfo(name: "#", type: .number, typeName: "NUMBER"), at: 0)
        out.rows = zip(d.rows, viewRows).map { [OracleValue.number(String($1 + 1))] + $0 }
        return out
    }

    @MainActor
    static func requireSelection(_ ctx: CommandContext) throws -> ExportData {
        guard let d = selection(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak siatki wyników")) }
        return d
    }

    @MainActor
    static func copy(_ ctx: CommandContext, _ format: ExportFormat, header: Bool) throws -> CommandResult {
        let d = try requireSelection(ctx)
        var o = ExportOptions()
        o.includeHeader = header
        o.format = ctx.workspace.settings.valueFormat
        let text = ResultExporter.text(format, d, options: o)
        let html = format == .tsv ? ResultExporter.text(.html, d, options: o) : nil
        ctx.workspace.ui?.copyToClipboard(text, html: html)
        return CommandResult(message: L10n.tr("Skopiowano wierszy: \(d.rows.count)"))
    }

    static func formatArgument(_ ctx: CommandContext) throws -> ExportFormat {
        guard let raw = ctx.arguments.string("format") else { throw CommandError.missingArgument("format") }
        guard let f = ExportFormat(rawValue: raw) else { throw CommandError.invalidArgument("format", raw) }
        return f
    }

    @MainActor
    public static var all: [Command] {
        let hasGrid: @MainActor (Workspace) -> Bool = { activeGrid($0) != nil }
        return [
            Command(CommandDescriptor(id: "grid.nextPage", title: L10n.tr("Następna strona"), category: .session, submenu: L10n.tr("Wynik"),
                                      pd: [], mac: ["cmd+pagedown"], agent: .none, effect: .none,
                                      summary: L10n.tr("Pobiera kolejną stronę wierszy wyniku."), feature: "PD-SQLW-004"),
                    validate: { ws in activeGrid(ws).map { $0.1.hasMore && !$0.1.isFetching } ?? false }) { ctx in
                guard let (_, grid) = activeGrid(ctx.workspace) else { return .ok }
                let page: Int
                switch ctx.workspace.settings.recordsPerPage {
                case .fixed(let n): page = max(1, n)
                default: page = 100
                }
                await grid.fetchMore(page)
                return .ok
            },
            Command(CommandDescriptor(id: "grid.lastPage", title: L10n.tr("Ostatnia strona (pobierz wszystkie)"), category: .session,
                                      submenu: L10n.tr("Wynik"), pd: [], mac: ["cmd+shift+pagedown"], agent: .none, effect: .none,
                                      summary: L10n.tr("Pobiera wszystkie pozostałe wiersze wyniku."), feature: "PD-SQLW-004"),
                    validate: { ws in activeGrid(ws).map { $0.1.hasMore && !$0.1.isFetching } ?? false }) { ctx in
                guard let (_, grid) = activeGrid(ctx.workspace) else { return .ok }
                await grid.fetchAll()
                return CommandResult(message: L10n.tr("Wierszy: \(grid.rowCount)"))
            },
            Command(CommandDescriptor(id: "grid.copy", title: L10n.tr("Kopiuj"), category: .edit, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Kopiuje zaznaczone komórki (tekst z tabulatorami i HTML)."), inMenu: false,
                                      feature: "PD-GRID-015"),
                    validate: hasGrid) { ctx in try copy(ctx, .tsv, header: false) },
            Command(CommandDescriptor(id: "grid.copyWithHeader", title: L10n.tr("Kopiuj z nagłówkiem"), category: .edit, submenu: L10n.tr("Wynik"),
                                      pd: ["ctrl+shift+c"], mac: ["cmd+shift+c"], agent: .none, effect: .none,
                                      summary: L10n.tr("Kopiuje zaznaczone komórki z nagłówkami kolumn (tekst z tabulatorami i HTML)."),
                                      feature: "PD-GRID-015"),
                    validate: hasGrid) { ctx in try copy(ctx, .tsv, header: true) },
            Command(CommandDescriptor(id: "grid.copyHeader", title: L10n.tr("Kopiuj nagłówek"), category: .edit, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .none, summary: L10n.tr("Kopiuje nazwy zaznaczonych kolumn."), feature: "PD-GRID-015"),
                    validate: hasGrid) { ctx in
                let d = try requireSelection(ctx)
                ctx.workspace.ui?.copyToClipboard(d.columns.map(\.name).joined(separator: "\t"), html: nil)
                return .ok
            },
            Command(CommandDescriptor(id: "grid.copyExpressionList", title: L10n.tr("Kopiuj jako listę wyrażeń"), category: .edit,
                                      submenu: L10n.tr("Wynik"), agent: .none, effect: .none,
                                      summary: L10n.tr("Kopiuje zaznaczenie jako warunek „kolumna IN (…)”."), feature: "PD-GRID-015"),
                    validate: hasGrid) { ctx in try copy(ctx, .expressionList, header: false) },
            Command(CommandDescriptor(id: "grid.graph", title: L10n.tr("Wykres…"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Okno wykresu z bieżącej karty wyników: kategoria, serie, typ, styl, szablony, auto-odświeżanie, eksport."),
                                      feature: "PD-GRAPH-001"),
                    validate: hasGrid) { ctx in
                guard let doc = SQLCommands.sqlDocument(ctx.workspace), let (tab, _) = activeGrid(ctx.workspace) else { return .ok }
                ctx.ui?.showGraph(document: doc, tab: tab)
                return .ok
            },
            Command(CommandDescriptor(id: "grid.copyAs", title: L10n.tr("Kopiuj jako…"), category: .edit, submenu: L10n.tr("Wynik"),
                                      parameters: [CommandParameter("format", .string, required: true, L10n.tr("Format"), allowed: ["csv", "tsv", "html", "xml", "sql", "expressionList"])],
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Kopiuje zaznaczenie do schowka w wybranym formacie."), inMenu: false, feature: "PD-GRID-013"),
                    validate: hasGrid) { ctx in try copy(ctx, try formatArgument(ctx), header: true) },
            Command(CommandDescriptor(id: "grid.export", title: L10n.tr("Eksportuj wynik…"), category: .file,
                                      parameters: [CommandParameter("format", .string, L10n.tr("Format"), allowed: ["csv", "tsv", "html", "xml", "sql", "xlsx"])],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje zaznaczenie (albo cały pobrany wynik) do pliku."), feature: "PD-GRID-013"),
                    validate: hasGrid) { ctx in
                let format = (try? formatArgument(ctx)) ?? .csv
                let d = try requireSelection(ctx)
                var o = ExportOptions()
                o.format = ctx.workspace.settings.valueFormat
                let data = format == .xlsx ? ResultExporter.xlsx([d], options: o) : Data(ResultExporter.text(format, d, options: o).utf8)
                let ok = await ctx.workspace.ui?.saveFile(suggestedName: d.title, fileExtension: format.fileExtension, data: data) ?? false
                return CommandResult(message: ok ? L10n.tr("Zapisano wierszy: \(d.rows.count)") : nil)
            },
            Command(CommandDescriptor(id: "grid.copyToExcel", title: L10n.tr("Kopiuj do Excela"), category: .edit, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje wszystkie wyniki okna jako skoroszyt xlsx (arkusz na wynik, polecenie SQL na osobnym arkuszu)."),
                                      feature: "PD-GRID-014"),
                    validate: hasGrid) { ctx in
                guard let doc = SQLCommands.sqlDocument(ctx.workspace) else { return .ok }
                let sheets = doc.results.compactMap { tab in tab.grid?.exportData(columns: tab.columnOrder, title: tab.title) }
                var o = ExportOptions()
                o.format = ctx.workspace.settings.valueFormat
                let data = ResultExporter.xlsx(sheets, includeSQL: true, options: o)
                _ = await ctx.workspace.ui?.saveFile(suggestedName: doc.title, fileExtension: "xlsx", data: data)
                return .ok
            },
            Command(CommandDescriptor(id: "grid.largeData", title: L10n.tr("Large Data Editor…"), category: .edit, submenu: L10n.tr("Wynik"),
                                      mac: ["cmd+alt+l"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera bieżącą komórkę (LOB, LONG, RAW, długi tekst) w edytorze dużych danych."),
                                      feature: "PD-GRID-003"),
                    validate: { ws in activeGrid(ws).map { $0.0.selectedRows?.first != nil && $0.0.currentColumn != nil } ?? false }) { ctx in
                guard let (tab, grid) = activeGrid(ctx.workspace), let row = tab.selectedRows?.first, let col = tab.currentColumn else { return .ok }
                let model = LargeDataModel(grid: grid, row: row, column: col)
                ctx.workspace.ui?.showLargeDataEditor(model)
                try await model.loadFull()
                return .ok
            },
            // Edycja danych (UG 7.6).
            Command(CommandDescriptor(id: "grid.edit", title: L10n.tr("Edytuj dane"), category: .session, submenu: L10n.tr("Wynik"),
                                      mac: ["cmd+alt+e"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Włącza albo wyłącza edycję wyniku (wymaga ROWID w zapytaniu)."), feature: "PD-GRID-017"),
                    validate: { ws in activeGrid(ws).map { $0.1.rowidColumn != nil } ?? false }) { ctx in
                guard let (_, grid) = activeGrid(ctx.workspace) else { return .ok }
                if grid.edit.isEditing {
                    grid.endEditing()
                } else {
                    try await grid.beginEditing()
                }
                return .ok
            },
            Command(CommandDescriptor(id: "grid.insertRecord", title: L10n.tr("Wstaw rekord"), category: .session, submenu: L10n.tr("Wynik"),
                                      mac: ["cmd+alt+i"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Dodaje pusty wiersz do edytowanego wyniku."), feature: "PD-GRID-017"),
                    validate: { ws in activeGrid(ws)?.1.edit.isEditing ?? false }) { ctx in
                guard let (tab, grid) = activeGrid(ctx.workspace) else { return .ok }
                let row = try grid.insertRecord()
                tab.selectedRows = [row]
                return .ok
            },
            Command(CommandDescriptor(id: "grid.deleteRecord", title: L10n.tr("Usuń rekord"), category: .session, submenu: L10n.tr("Wynik"),
                                      mac: ["cmd+shift+backspace"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Oznacza zaznaczone wiersze do usunięcia (usunięcie przy zatwierdzaniu zmian)."), feature: "PD-GRID-017"),
                    validate: { ws in activeGrid(ws).map { $0.1.edit.isEditing && !($0.0.selectedRows ?? []).isEmpty } ?? false }) { ctx in
                guard let (tab, grid) = activeGrid(ctx.workspace) else { return .ok }
                try grid.deleteRecords(tab.selectedRows ?? [])
                return .ok
            },
            Command(CommandDescriptor(id: "grid.post", title: L10n.tr("Zatwierdź zmiany (Post)"), category: .session, submenu: L10n.tr("Wynik"),
                                      mac: ["cmd+alt+s"], agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Zapisuje zmiany siatki w bazie (UPDATE/INSERT/DELETE po ROWID) — bez COMMIT."), feature: "PD-GRID-017"),
                    validate: { ws in hasPendingChanges(ws) }) { ctx in
                ctx.workspace.ui?.commitPendingEdits()
                guard let (_, grid) = activeGrid(ctx.workspace), grid.edit.hasChanges, let doc = SQLCommands.sqlDocument(ctx.workspace) else { return .ok }
                try await ctx.workspace.guardModification(["update t set x = 1"], connectionID: ctx.workspace.effectiveConnection(of: doc))
                do {
                    let n = try await grid.postChanges()
                    doc.transactionOpen = true
                    return CommandResult(message: L10n.tr("Zapisano zmian: \(n) — transakcja otwarta"))
                } catch let e as GridEditError {
                    doc.transactionOpen = (try? await SessionUtilities.transactionOpen(grid.session)) ?? true
                    if case .postFailed(let row, let column, _) = e, let tab = activeTab(ctx.workspace) {
                        tab.selectedRows = [row]
                        tab.focusedColumn = column
                    }
                    throw CommandError.notAvailable(e.localizedDescription)
                }
            },
            Command(CommandDescriptor(id: "grid.cancelChanges", title: L10n.tr("Anuluj zmiany"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .uiState, summary: L10n.tr("Przywraca wartości sprzed edycji."), feature: "PD-GRID-017"),
                    validate: { ws in hasPendingChanges(ws) }) { ctx in
                ctx.workspace.ui?.commitPendingEdits()
                activeGrid(ctx.workspace)?.1.cancelChanges()
                return .ok
            },
            Command(CommandDescriptor(id: "grid.copyChangesSQL", title: L10n.tr("Kopiuj SQL zmian"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Kopiuje polecenia, które wykona Zatwierdź zmiany (podgląd przed zapisem)."), feature: "PD-GRID-020"),
                    validate: { ws in hasPendingChanges(ws) }) { ctx in
                ctx.workspace.ui?.commitPendingEdits()
                guard let (_, grid) = activeGrid(ctx.workspace), grid.edit.hasChanges else { return .ok }
                let sql = grid.changesSQL()
                ctx.workspace.ui?.copyToClipboard(sql, html: nil)
                return CommandResult(message: sql)
            },
        ]
    }
}
