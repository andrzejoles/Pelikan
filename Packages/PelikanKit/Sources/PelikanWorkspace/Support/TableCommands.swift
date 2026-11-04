import Foundation
import PelikanLog

/// Wiersze i kolumny tabeli okna do kopii i eksportu (D214): tekst komórek w kolejności widoku (po filtrze i sortowaniu).
@MainActor
public struct TableContents {
    public let title: String
    public let columns: [(id: String, title: String)]
    /// Liczba wierszy widoku; `cell(wiersz, kolumna)` — tekst komórki.
    public let rowCount: Int
    public let cell: (Int, String) -> String
    /// Indeksy wierszy widoku zaznaczonych w tabeli.
    public let selectedRows: [Int]

    public init(title: String, columns: [(id: String, title: String)], rowCount: Int, cell: @escaping (Int, String) -> String, selectedRows: [Int]) {
        self.title = title
        self.columns = columns
        self.rowCount = rowCount
        self.cell = cell
        self.selectedRows = selectedRows
    }

    public func data(rows: [Int], columns ids: [String]? = nil) -> ExportData {
        let cols = ids.map { set in columns.filter { set.contains($0.id) } } ?? columns
        return TableExport.data(title: title, columns: cols.map(\.title), rows: rows.map { r in cols.map { cell(r, $0.id) } })
    }

    public var all: [Int] { Array(0..<rowCount) }
}

/// Tabela narzędzia, na której działają komendy `table.*` (D214): cel wywołania z menu i paska tabeli
/// (`CommandContext.target`) albo tabela z fokusem (`UIServices.focusedTable()` — paleta, skrót, makro).
@MainActor
public protocol TableHandle: AnyObject {
    var contents: TableContents { get }
    var filter: TableFilter { get set }
    /// Kolumny zaznaczone do kopii (identyfikatory, w kolejności zaznaczania).
    var markedColumns: [String] { get set }
    /// Tabela nadal istnieje (migawka z menu po zamknięciu okna — nie).
    var isAvailable: Bool { get }
}

extension TableHandle {
    public var isAvailable: Bool { true }
}

extension TableExport {
    /// Kopiowanie tabel z nagłówkiem kolumn (ustawienie zapamiętane między uruchomieniami).
    @MainActor public static var copyHeader: Bool {
        get { UserDefaults.standard.object(forKey: "tableCopyHeader") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tableCopyHeader") }
    }

    /// Warunek filtra „tylko ta wartość” / „bez tej wartości” dla tekstu komórki.
    public static func condition(_ value: String, exclude: Bool) -> String {
        if value.isEmpty { return exclude ? "is not null" : "is null" }
        // W cudzysłowach, gdy tekst ma apostrof albo białe znaki na brzegach (spacja, tabulator, nowa linia, twarda spacja) —
        // parser filtra je obcina, a warunek ma trafić w tę samą komórkę.
        // Przecinek („1,234” — separator tysięcy albo dziesiętny): porównanie tekstu komórki, nie liczby z niejednoznacznego
        // zapisu.
        let edges = value.trimmingCharacters(in: .whitespacesAndNewlines) != value
        let v = value.contains("'") || value.contains(",") || edges ? "'" + value.replacingOccurrences(of: "'", with: "''") + "'" : value
        return (exclude ? "<> " : "= ") + v
    }
}

/// Komendy tabel okien narzędzi (D214): kopiowanie komórki, wierszy, kolumn i całej tabeli, eksport, filtr wartością.
/// Menu i pasek tabel wywołują te komendy; są też w menu Edycja › Tabela, palecie i skrótach (makra nagrywają te, które
/// zmieniają stan tabeli — filtr, kolumny do kopii; kopie jak w siatce nie). Agent: Brak — dotyczą okna z fokusem.
@MainActor
enum TableCommands {
    static let submenu = L10n.tr("Tabela")

    static let rowsParam = CommandParameter("rows", .string, L10n.tr("Numery wierszy widoku od 1, po przecinku (domyślnie zaznaczone)"))
    static let columnParam = CommandParameter("column", .string, L10n.tr("Kolumna: identyfikator, tytuł albo #numer (bez argumentu — wybór z listy)"))

    static func handle(_ ctx: CommandContext) throws -> any TableHandle {
        // Tabela z menu (cel wywołania) — jej brak to błąd, nie zamiana na tabelę z fokusem.
        if let target = ctx.target {
            guard let h = target as? any TableHandle, h.isAvailable else { throw CommandError.notAvailable(L10n.tr("Tabeli z menu już nie ma (okno zamknięte)")) }
            return h
        }
        guard let h = ctx.ui?.focusedTable() else { throw CommandError.notAvailable(L10n.tr("Brak tabeli okna narzędzia z fokusem")) }
        return h
    }

    static func hasTable(_ ws: Workspace) -> Bool { ws.ui?.focusedTable() != nil }

    /// Wiersze z argumentu `rows` (numery od 1) albo zaznaczone.
    static func rows(_ ctx: CommandContext, _ c: TableContents) throws -> [Int] {
        guard let raw = ctx.arguments.string("rows") else { return c.selectedRows }
        guard !raw.isEmpty else { throw CommandError.invalidArgument("rows", raw) }
        return try raw.split(separator: ",").map { part in
            guard let n = Int(part.trimmingCharacters(in: .whitespaces)), n >= 1, n <= c.rowCount else { throw CommandError.invalidArgument("rows", raw) }
            return n - 1
        }
    }

    /// Wiersz z argumentu `row` (numer od 1) albo pierwszy zaznaczony.
    static func row(_ ctx: CommandContext, _ c: TableContents) throws -> Int {
        if let n = ctx.arguments.int("row") {
            guard n >= 1, n <= c.rowCount else { throw CommandError.invalidArgument("row", String(n)) }
            return Int(n) - 1
        }
        guard let r = c.selectedRows.first else { throw CommandError.notAvailable(L10n.tr("Zaznacz wiersz tabeli")) }
        return r
    }

    static let rowParam = CommandParameter("row", .integer, L10n.tr("Numer wiersza widoku od 1 (domyślnie pierwszy zaznaczony)"))

    /// Kolumna do makra: pozycja „#n” — tytuły (i identyfikatory z tytułów) zależą od języka interfejsu.
    static func columnArgument(_ id: String, _ c: TableContents) -> JSONValue {
        .string(c.columns.firstIndex { $0.id == id }.map { "#\($0 + 1)" } ?? id)
    }

    /// Kolumna z argumentu `column` (identyfikator albo tytuł, bez wielkości liter); bez argumentu — wybór z listy.
    static func column(_ ctx: CommandContext, _ c: TableContents) async throws -> String {
        // Pusty identyfikator to też kolumna (kolumny bez tytułu, np. ikona ważności) — brak argumentu ≠ "".
        if let raw = ctx.arguments.string("column") {
            // „#n” — n-ta kolumna (makra: niezależnie od języka tytułów).
            if raw.hasPrefix("#"), let n = Int(raw.dropFirst()), n >= 1, n <= c.columns.count { return c.columns[n - 1].id }
            guard let col = c.columns.first(where: { $0.id == raw })
                    ?? (raw.isEmpty ? nil : c.columns.first(where: { $0.title.caseInsensitiveCompare(raw) == .orderedSame }))
            else { throw CommandError.invalidArgument("column", raw) }
            return col.id
        }
        guard let id = try await ctx.choose(L10n.tr("Kolumna"), c.columns.map { (label: $0.title.isEmpty ? $0.id : $0.title, value: $0.id) }) else {
            throw CommandError.missingArgument("column")
        }
        return id
    }

    static func put(_ ctx: CommandContext, _ data: ExportData, header: Bool) -> CommandResult {
        let c = TableExport.clipboard(data, header: header)
        ctx.ui?.copyToClipboard(c.text, html: c.html)
        return CommandResult(message: L10n.tr("Skopiowano wierszy: \(data.rows.count)"))
    }

    static func command(_ id: String, _ title: String, _ summary: String, parameters: [CommandParameter] = [], effect: CommandEffect = .none,
                        state: StateHandler? = nil, needsTable: Bool = true, run: @escaping CommandHandler) -> Command {
        Command(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .edit, submenu: submenu,
                                  parameters: parameters,
                                  agent: .none, effect: effect, summary: summary, feature: "PD-UI-015"),
                validate: needsTable ? hasTable : nil, state: state, run: run)
    }

    static var all: [Command] {
        [
            command("table.copyCell", L10n.tr("Kopiuj komórkę tabeli"), L10n.tr("Kopiuje tekst komórki wiersza (domyślnie pierwszego zaznaczonego) w kolumnie."),
                    parameters: [rowParam, columnParam]) { ctx in
                let c = try handle(ctx).contents
                let r = try row(ctx, c)
                let col = try await column(ctx, c)
                ctx.ui?.copyToClipboard(c.cell(r, col), html: nil)
                return .ok
            },
            command("table.copyRows", L10n.tr("Kopiuj wiersze tabeli"), L10n.tr("Kopiuje zaznaczone wiersze tabeli (tekst z tabulatorami i HTML)."),
                    parameters: [rowsParam]) { ctx in
                let c = try handle(ctx).contents
                let rows = try rows(ctx, c)
                guard !rows.isEmpty else { throw CommandError.notAvailable(L10n.tr("Zaznacz wiersze tabeli")) }
                return put(ctx, c.data(rows: rows), header: TableExport.copyHeader)
            },
            command("table.copyColumn", L10n.tr("Kopiuj kolumnę tabeli"), L10n.tr("Kopiuje całą kolumnę tabeli (wiersze widoku)."),
                    parameters: [columnParam]) { ctx in
                let c = try handle(ctx).contents
                return put(ctx, c.data(rows: c.all, columns: [try await column(ctx, c)]), header: TableExport.copyHeader)
            },
            command("table.markColumn", L10n.tr("Zaznacz kolumnę do kopii"), L10n.tr("Dodaje kolumnę do kolumn kopiowanych razem albo ją z nich usuwa."),
                    parameters: [columnParam, CommandParameter("marked", .boolean, L10n.tr("Zaznaczona (domyślnie — przełączenie)"))],
                    effect: .uiState) { ctx in
                let h = try handle(ctx)
                let c = h.contents
                let id = try await column(ctx, c)
                // `marked` — stan docelowy (makro odtwarza stan, nie przełączenie); bez niego — przełączenie.
                let mark = ctx.arguments.bool("marked") ?? !h.markedColumns.contains(id)
                h.markedColumns.removeAll { $0 == id }
                if mark { h.markedColumns.append(id) }
                return CommandResult(resolvedArguments: CommandArguments(["column": columnArgument(id, c), "marked": .bool(mark)]))
            },
            command("table.clearMarkedColumns", L10n.tr("Odznacz kolumny do kopii"), L10n.tr("Usuwa zaznaczenie wszystkich kolumn do kopii."),
                    effect: .uiState) { ctx in
                try handle(ctx).markedColumns = []
                return .ok
            },
            command("table.copyMarkedColumns", L10n.tr("Kopiuj zaznaczone kolumny tabeli"),
                    L10n.tr("Kopiuje kolumny zaznaczone do kopii: wszystkie wiersze widoku, zaznaczone albo podane wiersze."),
                    parameters: [rowsParam, CommandParameter("selected", .boolean, L10n.tr("Tylko zaznaczone wiersze (domyślnie wszystkie)"))]) { ctx in
                let h = try handle(ctx)
                let c = h.contents
                guard !h.markedColumns.isEmpty else { throw CommandError.notAvailable(L10n.tr("Zaznacz kolumny do kopii")) }
                let rows = ctx.arguments.string("rows") != nil || ctx.arguments.bool("selected") == true ? try rows(ctx, c) : c.all
                guard !rows.isEmpty else { throw CommandError.notAvailable(L10n.tr("Zaznacz wiersze tabeli")) }
                return put(ctx, c.data(rows: rows, columns: h.markedColumns), header: TableExport.copyHeader)
            },
            command("table.copyAll", L10n.tr("Kopiuj całą tabelę"), L10n.tr("Kopiuje wszystkie wiersze widoku tabeli (po filtrze, w kolejności sortowania).")) { ctx in
                let c = try handle(ctx).contents
                return put(ctx, c.data(rows: c.all), header: TableExport.copyHeader)
            },
            command("table.copyHeaders", L10n.tr("Kopiuj nagłówki tabeli"), L10n.tr("Kopiuje tytuły kolumn tabeli.")) { ctx in
                ctx.ui?.copyToClipboard(try handle(ctx).contents.columns.map(\.title).joined(separator: "\t"), html: nil)
                return .ok
            },
            command("table.toggleCopyHeader", L10n.tr("Kopiuj tabele z nagłówkiem"), L10n.tr("Włącza albo wyłącza nagłówki kolumn przy kopiowaniu z tabel."),
                    effect: .settings, state: { _ in TableExport.copyHeader }, needsTable: false) { _ in
                TableExport.copyHeader.toggle()
                return .ok
            },
            command("table.filterByValue", L10n.tr("Filtruj tabelę wartością"),
                    L10n.tr("Filtr kolumny: tylko wartość komórki wiersza (domyślnie pierwszego zaznaczonego) albo bez niej."),
                    parameters: [columnParam, rowParam, CommandParameter("value", .string, L10n.tr("Wartość (zamiast wiersza)")),
                                 CommandParameter("exclude", .boolean, L10n.tr("Bez tej wartości (domyślnie tylko ta wartość)"))],
                    effect: .uiState) { ctx in
                let h = try handle(ctx)
                let c = h.contents
                let col = try await column(ctx, c)
                // Wartość podana wprost (makro) albo z wiersza (menu, paleta).
                let value = try ctx.arguments.string("value") ?? c.cell(try row(ctx, c), col)
                h.filter.columns[col] = TableExport.condition(value, exclude: ctx.arguments.bool("exclude") ?? false)
                // Do makra wartość, nie numer wiersza — odtworzenie filtruje tą samą wartością w każdej tabeli i kolejności.
                return CommandResult(resolvedArguments: CommandArguments(["column": columnArgument(col, c), "value": .string(value)]))
            },
            command("table.clearFilter", L10n.tr("Wyczyść filtr tabeli"), L10n.tr("Usuwa szybki filtr i filtry kolumn tabeli."), effect: .uiState) { ctx in
                try handle(ctx).filter = TableFilter()
                return .ok
            },
            command("table.export", L10n.tr("Eksportuj tabelę…"),
                    L10n.tr("Zapisuje wszystkie wiersze widoku tabeli do pliku: tekst, CSV, Excel, JSON, XML, HTML albo TSV."),
                    parameters: [CommandParameter("format", .string, L10n.tr("Format (bez argumentu — wybór z listy)"), allowed: TableExport.formats.map(\.rawValue))],
                    effect: .external) { ctx in
                let table = try handle(ctx)
                let c = table.contents
                let format: ExportFormat
                if let raw = ctx.arguments.string("format") {
                    guard let f = TableExport.formats.first(where: { $0.rawValue == raw }) else { throw CommandError.invalidArgument("format", raw) }
                    format = f
                } else if let f = try await ctx.choose(L10n.tr("Format eksportu"), TableExport.formats.map { (label: $0.displayName, value: $0) }) {
                    format = f
                } else {
                    throw CommandError.missingArgument("format")
                }
                let data = c.data(rows: c.all)
                let name = c.title.isEmpty ? L10n.tr("Tabela") : c.title
                guard await ctx.ui?.saveFile(suggestedName: name, fileExtension: format.fileExtension, data: TableExport.file(format, data), table: table) == true
                else { return .ok }
                Log.tools.info("Eksport tabeli: \(format.rawValue, privacy: .public), wierszy \(data.rows.count, privacy: .public)")
                return CommandResult(message: L10n.tr("Zapisano wierszy: \(data.rows.count)"), resolvedArguments: ctx.arguments.string("format") == nil ? CommandArguments(["format": .string(format.rawValue)]) : nil)
            },
        ]
    }
}
