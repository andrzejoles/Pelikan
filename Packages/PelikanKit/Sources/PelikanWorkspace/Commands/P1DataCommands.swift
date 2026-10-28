import Foundation
import PelikanDB
import PelikanSQL

/// Komendy domykające wiersze P1 danych: układ liczb, kalendarz daty, blok komórek, rekord z komentarzami kolumn
/// (siatka), a także Object Browser i edytor tabeli (rozszerzenia w osobnych plikach).
@MainActor
enum P1DataCommands {
    static var all: [Command] { grid + P1BrowserCommands.all }

    static func command(_ id: CommandID, _ title: String, _ category: CommandCategory = .session, submenu: String? = GridStage8Commands.resultMenu,
                        params: [CommandParameter] = [], agent: AgentAccess = .none, effect: CommandEffect = .uiState,
                        summary: String, feature: String, validate: (@MainActor @Sendable (Workspace) -> Bool)? = nil,
                        _ run: @escaping CommandHandler) -> Command {
        GridStage8Commands.command(id, title, category, submenu: submenu, params: params, agent: agent, effect: effect,
                                   summary: summary, feature: feature, validate: validate, run)
    }

    static var grid: [Command] {
        let hasGrid: @MainActor @Sendable (Workspace) -> Bool = { GridCommands.activeGrid($0) != nil }
        return [
            // MARK: Układ liczb (PD-GRID-004)
            command("grid.numberLayout", L10n.tr("Układ liczb w siatce"), .view, submenu: L10n.tr("Siatka"),
                    params: [CommandParameter("layout", .string, L10n.tr("right, left, formatted albo thousands (bez argumentu — wybór z listy)"))],
                    effect: .settings,
                    summary: L10n.tr("Wyrównanie i format liczb w siatce: do prawej, do lewej, z separatorem regionalnym, z separatorem tysięcy."),
                    feature: "PD-GRID-004") { ctx in
                var raw = ctx.arguments.string("layout")
                if raw == nil {
                    raw = try await ctx.choose(L10n.tr("Układ liczb w siatce"), NumberLayout.allCases.map { (label: $0.displayName, value: $0.rawValue) })
                }
                guard let raw else { throw CommandError.missingArgument("layout") }
                guard let layout = NumberLayout(rawValue: raw) else { throw CommandError.invalidArgument("layout", raw) }
                ctx.workspace.settings.gridNumberLayout = layout
                return CommandResult(message: layout.displayName, value: .string(layout.rawValue))
            },
            // MARK: Large Data Editor — Auto Format (PD-LDE-001)
            command("grid.largeDataAutoFormat", L10n.tr("Auto Format w Large Data Editor"), .view, submenu: L10n.tr("Siatka"),
                    effect: .settings,
                    summary: L10n.tr("Włącza albo wyłącza automatyczne formatowanie JSON i XML po otwarciu Large Data Editor."),
                    feature: "PD-LDE-001") { ctx in
                ctx.workspace.settings.largeDataAutoFormat.toggle()
                return CommandResult(value: .bool(ctx.workspace.settings.largeDataAutoFormat))
            },
            // MARK: Kalendarz przy edycji daty (PD-GRID-005)
            command("grid.chooseDate", L10n.tr("Kalendarz…"), .edit,
                    params: [CommandParameter("value", .string, L10n.tr("Data YYYY-MM-DD [HH24:MI:SS] zamiast okna kalendarza"))],
                    effect: .modifiesEditor,
                    summary: L10n.tr("Wybór daty z kalendarza do zaznaczonych komórek kolumny DATE / TIMESTAMP (tryb edycji)."),
                    feature: "PD-GRID-005", validate: { ws in
                        guard let (tab, grid) = GridCommands.activeGrid(ws), grid.edit.isEditing, let c = tab.currentColumn else { return false }
                        return grid.isDateColumn(c) && grid.isEditable(column: c)
                    }) { ctx in
                let (tab, grid) = try GridStage8Commands.grid(ctx)
                guard let (rows, col) = GridStage8Commands.currentCells(tab, grid), grid.isDateColumn(col) else {
                    throw CommandError.notAvailable(L10n.tr("Wybierz komórkę z datą"))
                }
                let withTime = grid.columns[col].type != .date || ctx.workspace.settings.dateFormat.uppercased().contains("HH")
                let chosen: OracleTimestamp
                var keepTime = false
                if let raw = ctx.arguments.string("value") {
                    guard let t = OracleTimestamp.parse(raw, mask: "YYYY-MM-DD HH24:MI:SS") else { throw CommandError.invalidArgument("value", raw) }
                    chosen = t
                    keepTime = !raw.contains(":")
                } else {
                    guard let t = await ctx.ui?.chooseDate(grid.columns[col].name, initial: grid.timestamp(row: rows[0], column: col),
                                                           withTime: withTime) else { throw CommandError.cancelledByUser }
                    chosen = t
                    keepTime = !withTime
                }
                for r in rows { try grid.setDate(chosen, row: r, column: col, keepTime: keepTime) }
                return CommandResult(message: grid.text(row: rows[0], column: col))
            },
            // MARK: Blok komórek (PD-GRID-007)
            command("grid.selectBlock", L10n.tr("Zaznacz blok komórek"), .edit,
                    params: [CommandParameter("fromRow", .integer, required: true, L10n.tr("Pierwszy wiersz (od 1)")),
                             CommandParameter("toRow", .integer, required: true, L10n.tr("Ostatni wiersz (od 1)")),
                             CommandParameter("fromColumn", .string, required: true, L10n.tr("Pierwsza kolumna (nazwa)")),
                             CommandParameter("toColumn", .string, L10n.tr("Ostatnia kolumna (nazwa); brak — jedna kolumna"))],
                    summary: L10n.tr("Zaznacza prostokątny blok komórek; kopiowanie i eksport obejmują tylko jego kolumny."),
                    feature: "PD-GRID-007", validate: hasGrid) { ctx in
                let (tab, grid) = try GridStage8Commands.grid(ctx)
                func column(_ key: String) throws -> Int? {
                    guard let name = ctx.arguments.string(key) else { return nil }
                    guard let i = grid.columns.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                        throw CommandError.invalidArgument(key, name)
                    }
                    return i
                }
                guard let from = try column("fromColumn") else { throw CommandError.missingArgument("fromColumn") }
                let to = try column("toColumn") ?? from
                // Pusta siatka: zakres 1...0 zatrzymałby aplikację.
                guard let r1 = ctx.arguments.int("fromRow"), let r2 = ctx.arguments.int("toRow"), grid.rowCount > 0,
                      (1...grid.rowCount).contains(Int(r1)), (1...grid.rowCount).contains(Int(r2)) else {
                    throw CommandError.invalidArgument("fromRow", "1…\(grid.rowCount)")
                }
                let order = (tab.columnOrder ?? Array(grid.columns.indices)).filter { !tab.hiddenColumns.contains($0) }
                tab.selectedRows = GridBlock.rows(from: Int(r1) - 1, to: Int(r2) - 1)
                tab.selectedColumns = GridBlock.columns(from: from, to: to, order: order)
                tab.currentColumn = from
                return CommandResult(value: .object(["rows": .int(Int64(tab.selectedRows?.count ?? 0)),
                                                     "columns": .array((tab.selectedColumns ?? []).map { .string(grid.columns[$0].name) })]))
            },
            command("grid.selectColumn", L10n.tr("Zaznacz kolumnę"), .edit,
                    params: [CommandParameter("column", .string, L10n.tr("Nazwa kolumny; brak — bieżąca"))],
                    summary: L10n.tr("Zaznacza całą kolumnę (wszystkie pobrane wiersze) jako blok komórek."),
                    feature: "PD-GRID-007", validate: hasGrid) { ctx in
                let (tab, grid) = try GridStage8Commands.grid(ctx)
                let c = try GridStage8Commands.columnIndex(ctx, tab, grid)
                tab.selectedRows = grid.rowCount == 0 ? nil : Array(0..<grid.rowCount)
                tab.selectedColumns = [c]
                tab.currentColumn = c
                return .ok
            },
            // MARK: Rekord z komentarzami kolumn (PD-GRID-010)
            command("grid.toggleRecordView", L10n.tr("Widok pojedynczego rekordu"),
                    summary: L10n.tr("Przełącza wynik między tabelą a widokiem pojedynczego rekordu (kolumny, wartości, typy i komentarze kolumn)."),
                    feature: "PD-GRID-010", validate: hasGrid) { ctx in
                let (tab, _) = try GridStage8Commands.grid(ctx)
                tab.showsRecord.toggle()
                return .ok
            },
            // Dane rekordu bez zmiany widoku (agent, skrypty; komentarze kolumn dla widoku rekordu) — poza menu i wstążką.
            Command(CommandDescriptor(id: "grid.recordView", title: L10n.tr("Rekord z komentarzami kolumn"), category: .session,
                                      submenu: GridStage8Commands.resultMenu,
                                      parameters: [CommandParameter("row", .integer, L10n.tr("Wiersz (od 1); brak — zaznaczony"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Kolumny, wartości, typy i komentarze kolumn (ze słownika) jednego rekordu — widok pojedynczego rekordu."),
                                      inMenu: false, feature: "PD-GRID-010"), validate: hasGrid) { ctx in
                let (tab, grid) = try GridStage8Commands.grid(ctx)
                let row = ctx.arguments.int("row").map { Int($0) - 1 } ?? tab.selectedRows?.first ?? 0
                guard row >= 0, row < grid.rowCount else { throw CommandError.invalidArgument("row", String(row + 1)) }
                // Słownik tabeli wyniku (komentarze); brak tabeli albo sesji — pola bez komentarzy.
                _ = try? await GridStage8Commands.dictionary(tab, grid, ws: ctx.workspace)
                let cols = (tab.columnOrder ?? Array(grid.columns.indices)).filter { !tab.hiddenColumns.contains($0) }
                let fields = tab.recordFields(row: row, columns: cols)
                return CommandResult(value: .array(fields.map {
                    .object(["column": .string($0.name), "value": $0.isNull ? .null : .string($0.value), "type": .string($0.type),
                             "comment": .string($0.comment)])
                }))
            },
        ]
    }
}
