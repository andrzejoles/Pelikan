import AppKit
import PelikanWorkspace
import SwiftUI

/// Stan narzędzi tabeli AppKit obserwowany przez pasek nad tabelą (D214).
@MainActor @Observable
final class TableToolsModel {
    var state = TableToolsState() {
        didSet { if state.filter != oldValue.filter { onFilterChange?() } }
    }
    /// Zmienia się po każdym przeładowaniu wierszy — pasek odświeża liczbę wierszy.
    var revision = 0
    /// Przeładowania wierszy (nie zmiany zaznaczenia) — menu wykrywa przesunięcie wierszy po otwarciu.
    @ObservationIgnored var reloads = 0
    @ObservationIgnored var onFilterChange: (() -> Void)?
}

/// Akcja pozycji menu w domknięciu (cel pozycji, trzymany w `representedObject`).
final class TableMenuAction: NSObject {
    private let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func run() { block() }
}

/// Pozycja menu z akcją w domknięciu.
@MainActor
func BlockMenuItem(_ title: String, state: Bool = false, enabled: Bool = true, _ block: @escaping () -> Void) -> NSMenuItem {
    let action = TableMenuAction(block)
    let item = NSMenuItem(title: title, action: #selector(TableMenuAction.run), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    item.state = state ? .on : .off
    item.isEnabled = enabled
    return item
}

/// Kopiowanie, eksport i filtr wartości kolumn dla tabel AppKit (D214) — te same czynności co w tabelach SwiftUI:
/// menu kontekstowe (komórka, wiersze, kolumna, zaznaczone kolumny, cała tabela, filtr wartością, eksport)
/// i pasek nad tabelą (szybki filtr, filtr kolumn, liczba wierszy, Kopiuj, Eksportuj).
@MainActor
final class AppKitTableTools: NSObject, NSMenuDelegate, FocusTable {
    var window: NSWindow? { table.window }

    /// Migawka w chwili wyboru pozycji menu: tekst wierszy, których dotyczy czynność (zaznaczone i spod kursora) —
    /// komenda startuje później (zadanie), a tabela może się w tym czasie przeładować.
    func snapshot() -> (contents: TableContents, indexes: ([AnyHashable]) -> [Int]) {
        let c = contents
        var wanted = Set(c.selectedRows)
        if table.clickedRow >= 0 { wanted.insert(table.clickedRow) }
        let cells = Dictionary(uniqueKeysWithValues: wanted.filter { $0 < c.rowCount }.map { r in
            (r, Dictionary(c.columns.map { ($0.id, c.cell(r, $0.id)) }, uniquingKeysWith: { a, _ in a }))
        })
        let frozen = TableContents(title: c.title, columns: c.columns, rowCount: c.rowCount,
                                   cell: { r, id in cells[r]?[id] ?? "" }, selectedRows: c.selectedRows)
        let count = c.rowCount
        // Identyfikatory wierszy tabel AppKit to ich indeksy.
        return (frozen, { ids in ids.compactMap { $0 as? Int }.filter { $0 < count } })
    }

    var filter: TableFilter {
        get { model.state.filter }
        set { model.state.filter = newValue }
    }
    var markedColumns: [String] {
        get { model.state.markedColumns }
        set { model.state.markedColumns = newValue }
    }
    @objc private func selectionChanged(_ note: Notification) { model.revision += 1 }

    /// Komendy z palety i skrótu: tekst wszystkich wierszy przepisany na starcie komendy (komenda czeka na wybór kolumny,
    /// a tabela może się w tym czasie przeładować) — raz na komendę, nie przy każdym otwarciu menu.
    var stableContents: TableContents {
        let c = contents
        let cells = (0..<c.rowCount).map { r in c.columns.map { c.cell(r, $0.id) } }
        let index = Dictionary(c.columns.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return TableContents(title: c.title, columns: c.columns, rowCount: c.rowCount,
                             cell: { r, id in r < cells.count ? index[id].map { cells[r][$0] } ?? "" : "" }, selectedRows: c.selectedRows)
    }

    var hasSQLColumn: Bool { columns.contains { SQLIdentity.columnKind($0.title) != nil || SQLIdentity.columnKind($0.id) != nil } }

    /// Zapytanie z pierwszego zaznaczonego wiersza (kolumna SQL_ID albo hash).
    var sqlTarget: SQLReportTarget? { contents.selectedRows.first.flatMap { sqlTarget(row: $0, in: contents) } }

    /// Zapytanie z wiersza widoku — menu wiersza i skrót (jedna reguła).
    func sqlTarget(row r: Int, in c: TableContents) -> SQLReportTarget? {
        SQLReportTarget.fromTableRow(columns: c.columns, values: c.columns.map { c.cell(r, $0.id) }, connection: nil, origin: L10n.tr("wiersz tabeli"))
    }

    let table: NSTableView
    let model = TableToolsModel()
    private let title: () -> String
    /// Liczba wszystkich wierszy (przed filtrem).
    let total: () -> Int
    /// Tekst komórki wiersza widoku (po filtrze i sortowaniu) w kolumnie o identyfikatorze.
    private let cell: (Int, String) -> String
    private var baseItems: [NSMenuItem] = []

    init(table: NSTableView, title: @escaping () -> String, total: @escaping () -> Int, cell: @escaping (Int, String) -> String,
         onFilterChange: @escaping () -> Void) {
        self.table = table
        self.title = title
        self.total = total
        self.cell = cell
        super.init()
        model.onFilterChange = onFilterChange
        let menu = NSMenu()
        if let old = table.menu {
            baseItems = old.items
            old.removeAllItems()
        }
        menu.delegate = self
        table.menu = menu
        TableFocus.register(table, self)
        // Pasek nad tabelą (liczba i pozycje „zaznaczone”) po każdej zmianie zaznaczenia; obserwator z selektorem
        // wyrejestrowuje się sam przy zwolnieniu obiektu.
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: NSTableView.selectionDidChangeNotification, object: table)
    }

    var columns: [(id: String, title: String)] {
        table.tableColumns.filter { !$0.isHidden }.map { ($0.identifier.rawValue, $0.title) }
    }

    var contents: TableContents {
        TableContents(title: TableActions.title(title(), window: table.window), columns: columns, rowCount: table.numberOfRows, cell: cell,
                      selectedRows: Array(table.selectedRowIndexes))
    }

    /// Elementy spełniające filtr (tekst i klucz komórki po identyfikatorze kolumny).
    func filter<T>(_ items: [T], _ value: (T, String) -> (text: String, key: SortKey)) -> [T] {
        let f = model.state.filter.compiled()
        guard !f.isEmpty else { return items }
        let ids = columns.map(\.id)
        return items.filter { item in f.matches(all: ids) { value(item, $0) } }
    }

    /// Po przeładowaniu tabeli — liczba wierszy na pasku.
    func reloaded() {
        model.revision += 1
        model.reloads += 1
    }

    /// Pasek narzędzi nad widokiem przewijania tabeli.
    func wrap(_ scroll: NSView) -> NSView {
        let bar = NSHostingView(rootView: AppKitTableBar(tools: self).interfaceFont())
        let stack = NSStackView(views: [bar, scroll])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        bar.setContentHuggingPriority(.required, for: .vertical)
        for v in [bar, scroll] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        bar.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 0).isActive = true
        return stack
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in baseItems { menu.addItem(item) }
        if !baseItems.isEmpty { menu.addItem(.separator()) }
        let c = contents
        let header = TableExport.copyHeader
        let row = table.clickedRow
        let colIndex = table.clickedColumn
        let column = colIndex >= 0 && colIndex < table.tableColumns.count ? table.tableColumns[colIndex] : nil
        let rows: [Int] = row < 0 ? c.selectedRows : (table.selectedRowIndexes.contains(row) ? c.selectedRows : [row])
        // Czynności bez wierszy — na tej tabeli (cel wywołania); czynności na wierszach — na migawce z chwili wyboru
        // pozycji, o ile tabela nie przeładowała się od otwarcia menu. Menu nie zmienia zaznaczenia (zaznaczenie bywa
        // nawigacją, np. wybór pliku dziennika).
        func item(_ title: String, state: Bool = false, enabled: Bool = true, _ id: String, _ args: [String: JSONValue] = [:]) -> NSMenuItem {
            BlockMenuItem(title, state: state, enabled: enabled) { [weak self] in
                guard let self else { return }
                TableActions.perform(self, id, args)
            }
        }
        // Przeładowanie tabeli po otwarciu menu przesuwa wiersze (zaznaczenie i numery to indeksy) — komunikat zamiast
        // czynności na innych wierszach.
        let reloadsAtOpen = model.reloads
        func rowItem(_ title: String, _ id: String, _ args: [String: JSONValue]) -> NSMenuItem {
            BlockMenuItem(title) { [weak self] in
                guard let self else { return }
                guard self.model.reloads == reloadsAtOpen else {
                    (NSApp.delegate as? AppDelegate)?.showError(L10n.tr("Wierszy z menu nie ma już w tabeli (odświeżona)"))
                    return
                }
                // Migawka teraz, synchronicznie z wyborem pozycji — komenda (zadanie) działa na tych wierszach.
                TableActions.performOnRows(FrozenTable(self), id) { _ in args }
            }
        }
        // Raporty SQL z wiersza z kolumną SQL_ID/hash (D217).
        if let r = rows.first, let target = sqlTarget(row: r, in: c) {
            menu.addItem(BlockMenuItem(L10n.tr("Raporty dla \(target.label)…")) { SQLReportLauncher.open(target) })
            menu.addItem(.separator())
        }
        if row >= 0, let column {
            menu.addItem(rowItem(L10n.tr("Kopiuj komórkę"), "table.copyCell", ["row": .int(Int64(row + 1)), "column": .string(column.identifier.rawValue)]))
        }
        if !rows.isEmpty {
            // Wiersz spod kursora poza zaznaczeniem — tylko on; inaczej zaznaczenie.
            let args: [String: JSONValue] = row >= 0 && !table.selectedRowIndexes.contains(row) ? ["rows": .string(String(row + 1))] : [:]
            menu.addItem(rowItem(rows.count == 1 ? L10n.tr("Kopiuj wiersz") : L10n.tr("Kopiuj zaznaczone wiersze (\(rows.count))"), "table.copyRows", args))
        }
        if let column {
            let id = column.identifier.rawValue
            menu.addItem(item(L10n.tr("Kopiuj kolumnę „\(column.title)”"), "table.copyColumn", ["column": .string(id)]))
            menu.addItem(item(L10n.tr("Zaznacz kolumnę „\(column.title)” do kopii"), state: markedColumns.contains(id), "table.markColumn", ["column": .string(id)]))
        }
        let marked = markedColumns
        menu.addItem(item(L10n.tr("Kopiuj zaznaczone kolumny (\(marked.count))"), enabled: !marked.isEmpty, "table.copyMarkedColumns"))
        menu.addItem(item(L10n.tr("Kopiuj całą tabelę"), "table.copyAll"))
        menu.addItem(item(L10n.tr("Kopiuj nagłówki"), "table.copyHeaders"))
        menu.addItem(item(L10n.tr("Kopiuj z nagłówkiem"), state: header, "table.toggleCopyHeader"))
        if row >= 0, let column {
            let id = column.identifier.rawValue
            menu.addItem(.separator())
            menu.addItem(rowItem(L10n.tr("Filtruj „\(column.title)”: tylko ta wartość"), "table.filterByValue",
                                 ["row": .int(Int64(row + 1)), "column": .string(id), "exclude": .bool(false)]))
            menu.addItem(rowItem(L10n.tr("Filtruj „\(column.title)”: bez tej wartości"), "table.filterByValue",
                                 ["row": .int(Int64(row + 1)), "column": .string(id), "exclude": .bool(true)]))
        }
        if model.state.filter.isActive {
            menu.addItem(item(L10n.tr("Wyczyść filtr"), "table.clearFilter"))
        }
        menu.addItem(.separator())
        let export = NSMenuItem(title: L10n.tr("Eksportuj"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for f in TableExport.formats {
            sub.addItem(item(f.displayName + "…", "table.export", ["format": .string(f.rawValue)]))
        }
        export.submenu = sub
        menu.addItem(export)
    }
}

/// Pasek narzędzi tabeli AppKit (ten sam co nad tabelami SwiftUI).
struct AppKitTableBar: View {
    let tools: AppKitTableTools

    var body: some View {
        let model = tools.model
        _ = model.revision
        return TableToolsBar(contents: tools.contents, handle: tools, state: Binding(get: { model.state }, set: { model.state = $0 }), total: tools.total())
            .padding(.horizontal, 4)
    }
}
