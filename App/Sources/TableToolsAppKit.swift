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
final class AppKitTableTools: NSObject, NSMenuDelegate {
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
    }

    var columns: [(id: String, title: String)] {
        table.tableColumns.filter { !$0.isHidden }.map { ($0.identifier.rawValue, $0.title) }
    }

    var contents: TableContents {
        TableContents(title: TableActions.title(title()), columns: columns, rowCount: table.numberOfRows, cell: cell,
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
    func reloaded() { model.revision += 1 }

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
        let header = TableActions.copyHeader
        let row = table.clickedRow
        let colIndex = table.clickedColumn
        let column = colIndex >= 0 && colIndex < table.tableColumns.count ? table.tableColumns[colIndex] : nil
        let rows: [Int] = row < 0 ? c.selectedRows : (table.selectedRowIndexes.contains(row) ? c.selectedRows : [row])
        // Raporty SQL z wiersza z kolumną SQL_ID/hash (D217).
        if let r = rows.first, let t = SQLIdentity.target(columns: c.columns.map(\.title), values: c.columns.map { c.cell(r, $0.id) }) {
            let target = SQLReportTarget(target: t, origin: L10n.tr("wiersz tabeli"))
            menu.addItem(BlockMenuItem(L10n.tr("Raporty dla \(target.label)…")) { SQLReportLauncher.open(target) })
            menu.addItem(.separator())
        }
        if row >= 0, let column {
            let id = column.identifier.rawValue
            menu.addItem(BlockMenuItem(L10n.tr("Kopiuj komórkę")) { TableActions.put(c.cell(row, id)) })
        }
        if !rows.isEmpty {
            menu.addItem(BlockMenuItem(rows.count == 1 ? L10n.tr("Kopiuj wiersz") : L10n.tr("Kopiuj zaznaczone wiersze (\(rows.count))")) {
                TableActions.copy(c.data(rows: rows), header: header)
            })
        }
        if let column {
            let id = column.identifier.rawValue
            menu.addItem(BlockMenuItem(L10n.tr("Kopiuj kolumnę „\(column.title)”")) {
                TableActions.copy(c.data(rows: c.all, columns: [id]), header: header)
            })
            let marked = model.state.markedColumns.contains(id)
            menu.addItem(BlockMenuItem(L10n.tr("Zaznacz kolumnę „\(column.title)” do kopii"), state: marked) { [model] in
                model.state.markedColumns.removeAll { $0 == id }
                if !marked { model.state.markedColumns.append(id) }
            })
        }
        let marked = model.state.markedColumns
        menu.addItem(BlockMenuItem(L10n.tr("Kopiuj zaznaczone kolumny (\(marked.count))"), enabled: !marked.isEmpty) {
            TableActions.copy(c.data(rows: c.all, columns: marked), header: header)
        })
        menu.addItem(BlockMenuItem(L10n.tr("Kopiuj całą tabelę")) { TableActions.copy(c.data(rows: c.all), header: header) })
        menu.addItem(BlockMenuItem(L10n.tr("Kopiuj nagłówki")) { TableActions.put(c.columns.map(\.title).joined(separator: "\t")) })
        menu.addItem(BlockMenuItem(L10n.tr("Kopiuj z nagłówkiem"), state: header) { TableActions.copyHeader = !header })
        if row >= 0, let column {
            let id = column.identifier.rawValue
            let value = c.cell(row, id)
            menu.addItem(.separator())
            menu.addItem(BlockMenuItem(L10n.tr("Filtruj „\(column.title)”: tylko ta wartość")) { [model] in
                model.state.filter.columns[id] = TableValueFilterMenu.condition(value, exclude: false)
            })
            menu.addItem(BlockMenuItem(L10n.tr("Filtruj „\(column.title)”: bez tej wartości")) { [model] in
                model.state.filter.columns[id] = TableValueFilterMenu.condition(value, exclude: true)
            })
        }
        if model.state.filter.isActive {
            menu.addItem(BlockMenuItem(L10n.tr("Wyczyść filtr")) { [model] in model.state.filter = TableFilter() })
        }
        menu.addItem(.separator())
        let export = NSMenuItem(title: L10n.tr("Eksportuj"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for f in TableExport.formats {
            sub.addItem(BlockMenuItem(f.displayName + "…") { TableActions.export(f, c.data(rows: c.all)) })
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
        return TableToolsBar(contents: tools.contents, state: Binding(get: { model.state }, set: { model.state = $0 }), total: tools.total())
            .padding(.horizontal, 4)
    }
}
