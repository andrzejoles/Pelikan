import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Siatka wyników (ADR 0004): NSTableView z wirtualizacją wierszy, kolumna numeru wiersza, NULL na kolorowym tle
/// (UG 7.2), liczby do prawej, dociąganie porcjami przy zbliżeniu do końca, sortowanie klikiem nagłówka (Shift —
/// klucz dodatkowy), przenoszenie kolumn, pasek siatki (strony, kopiowanie, eksport, widok pojedynczego rekordu).
final class ResultGridView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let tab: ResultTab
    private let grid: ResultGridModel
    private let workspace: Workspace
    private let table = GridTableView()
    private let scroll = NSScrollView()
    private let record = SingleRecordView()
    private let bar = NSStackView()
    private let recordButton = NSButton()
    private let editButton = NSButton()
    private var editControls: [NSView] = []
    private var lastEditing = false
    private var lastFocus: Int?
    private let countLabel = NSTextField(labelWithString: "")
    private var tokens: [ObservationToken] = []
    private var lastRowCount = 0
    private var lastSort: [ResultGridModel.SortKey] = []
    private var lastFilter: String?
    private var valuePanel: NSView?
    private var scrollTrailing: NSLayoutConstraint?
    private var panelWidth: NSLayoutConstraint?
    static let nullColor = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.30, green: 0.28, blue: 0.12, alpha: 1) : NSColor(srgbRed: 1.0, green: 0.98, blue: 0.80, alpha: 1) }
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    init(tab: ResultTab, grid: ResultGridModel, workspace: Workspace) {
        self.tab = tab
        self.grid = grid
        self.workspace = workspace
        super.init(frame: .zero)
        configure()
        tokens.append(trackChanges { [weak self] in self?.modelChanged() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = 20
        table.intercellSpacing = NSSize(width: 6, height: 1)
        table.gridStyleMask = [.solidVerticalGridLineMask]
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.copyHandler = { [weak self] withHeader in self?.copy(withHeader: withHeader) }
        table.target = self
        table.action = #selector(cellClicked)
        table.doubleAction = #selector(cellDoubleClicked)
        let rowNo = NSTableColumn(identifier: .init("#"))
        rowNo.title = ""
        rowNo.width = 50
        rowNo.minWidth = 30
        table.addTableColumn(rowNo)
        for (i, c) in grid.columns.enumerated() {
            let col = NSTableColumn(identifier: .init("c\(i)"))
            col.title = c.name
            col.headerToolTip = "\(c.name) — \(c.typeName)\(c.nullable ? "" : " NOT NULL")"
            col.width = Self.initialWidth(c)
            col.minWidth = 24
            if c.type.isNumeric { col.headerCell.alignment = .right }
            table.addTableColumn(col)
        }
        table.setAccessibilityLabel(L10n.tr("Siatka wyników"))
        table.menu = contextMenu()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(columnsMoved), name: NSTableView.columnDidMoveNotification, object: table)

        // Pasek siatki (UG 7.1: Next Page, Last Page; UG 7.2: Single Record View, Export, Copy to Excel).
        func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
            b.bezelStyle = .accessoryBarAction
            b.isBordered = false
            b.toolTip = tip
            return b
        }
        recordButton.image = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: L10n.tr("Widok pojedynczego rekordu"))
        recordButton.bezelStyle = .accessoryBarAction
        recordButton.setButtonType(.pushOnPushOff)
        recordButton.isBordered = false
        recordButton.toolTip = L10n.tr("Widok pojedynczego rekordu")
        recordButton.target = self
        recordButton.action = #selector(toggleRecord)
        let export = NSPopUpButton(frame: .zero, pullsDown: true)
        export.isBordered = false
        export.addItem(withTitle: "")
        export.item(at: 0)?.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: L10n.tr("Eksport"))
        for f in ExportFormat.allCases where f != .expressionList {
            let item = export.menu!.addItem(withTitle: L10n.tr("Eksportuj jako \(f.displayName)…"), action: #selector(exportAs(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = f.rawValue
        }
        export.toolTip = L10n.tr("Eksportuj zaznaczenie albo cały pobrany wynik")
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        // Edycja (UG 7.6): kłódka Edit data, Wstaw, Usuń, Zatwierdź zmiany (z menu: kopiuj SQL zmian, anuluj).
        editButton.image = NSImage(systemSymbolName: "lock", accessibilityDescription: L10n.tr("Edytuj dane"))
        editButton.bezelStyle = .accessoryBarAction
        editButton.setButtonType(.pushOnPushOff)
        editButton.isBordered = false
        editButton.toolTip = L10n.tr("Edytuj dane (wymaga ROWID w zapytaniu)")
        editButton.target = self
        editButton.action = #selector(toggleEdit)
        editButton.isEnabled = grid.rowidColumn != nil
        let post = NSPopUpButton(frame: .zero, pullsDown: true)
        post.isBordered = false
        post.addItem(withTitle: "")
        post.item(at: 0)?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: L10n.tr("Zatwierdź zmiany"))
        for (title, id) in [(L10n.tr("Zatwierdź zmiany (Post)"), "grid.post"), (L10n.tr("Kopiuj SQL zmian"), "grid.copyChangesSQL"),
                            (L10n.tr("Anuluj zmiany"), "grid.cancelChanges")] {
            let item = post.menu!.addItem(withTitle: title, action: #selector(contextCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
        }
        post.toolTip = L10n.tr("Zatwierdź zmiany w bazie (bez COMMIT)")
        editControls = [button("plus", L10n.tr("Wstaw rekord"), #selector(insertRecord)),
                        button("minus", L10n.tr("Usuń rekord"), #selector(deleteRecord)), post]
        editControls.forEach { $0.isHidden = true }
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([separator.widthAnchor.constraint(equalToConstant: 1), separator.heightAnchor.constraint(equalToConstant: 14)])
        for v in [button("chevron.down", L10n.tr("Następna strona"), #selector(nextPage)),
                  button("chevron.down.2", L10n.tr("Ostatnia strona (pobierz wszystkie)"), #selector(lastPage)),
                  recordButton, export, button("tablecells", L10n.tr("Kopiuj do Excela"), #selector(copyToExcel)),
                  separator, editButton] + editControls + [countLabel] as [NSView] {
            bar.addArrangedSubview(v)
        }
        bar.spacing = 4
        bar.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 6)
        record.isHidden = true
        record.onMove = { [weak self] delta in self?.moveRecord(delta) }
        for v in [bar, scroll, record] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            { let c = bar.heightAnchor.constraint(equalToConstant: 24); c.priority = .defaultHigh; return c }(),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            record.topAnchor.constraint(equalTo: bar.bottomAnchor),
            record.leadingAnchor.constraint(equalTo: leadingAnchor),
            record.trailingAnchor.constraint(equalTo: trailingAnchor),
            record.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        // Panel wartości bieżącej komórki po prawej (DB-PANEL-001), widoczny przełącznikiem z menu Widok.
        let panel = NSHostingView(rootView: CellValuePanelView(tab: tab, grid: grid))
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        let trailing = scroll.trailingAnchor.constraint(equalTo: panel.leadingAnchor)
        let width = panel.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: bar.bottomAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailing, width,
        ])
        valuePanel = panel
        scrollTrailing = trailing
        panelWidth = width
        panel.isHidden = true
    }

    static func initialWidth(_ c: ColumnInfo) -> CGFloat {
        let chars: Int
        switch c.type {
        case .number, .binaryDouble, .binaryFloat, .binaryInteger:
            // NUMBER bez precyzji (wyrażenia, level) — szerokość jak dla 10 cyfr.
            chars = min(max(c.precision > 0 ? Int(c.precision) + 2 : 10, c.name.count), 18)
        case .date: chars = 19
        case .timestamp, .timestampTZ, .timestampLTZ: chars = 26
        case .varchar2, .nvarchar2, .char, .nchar: chars = min(max(Int(c.size), c.name.count), 40)
        default: chars = max(c.name.count, 10)
        }
        return CGFloat(chars) * 7.6 + 14
    }

    private func modelChanged() {
        let showPanel = workspace.valuePanelVisible
        if valuePanel?.isHidden == showPanel {
            valuePanel?.isHidden = !showPanel
            panelWidth?.constant = showPanel ? 300 : 0
        }
        let filterText = grid.filter?.text
        if filterText != lastFilter {
            lastFilter = filterText
            lastRowCount = grid.rowCount
            table.deselectAll(nil)
            table.reloadData()
        }
        let count = grid.rowCount
        let more = grid.hasMore
        let sort = grid.sortKeys
        let edit = grid.edit
        let focus = tab.focusedColumn
        countLabel.stringValue = (more ? L10n.tr("\(count) wierszy (więcej…)") : L10n.tr("\(count) wierszy"))
            + (filterText.map { L10n.tr("  ·  filtr: \($0) (z \(grid.fetchedRowCount))") } ?? "")
            + (edit.hasChanges ? "  ·  " + (grid.pendingSummary.isEmpty ? L10n.tr("zmiany do zatwierdzenia") : grid.pendingSummary.text) : "")
        if edit.isEditing != lastEditing {
            lastEditing = edit.isEditing
            editButton.state = edit.isEditing ? .on : .off
            editButton.image = NSImage(systemSymbolName: edit.isEditing ? "lock.open" : "lock", accessibilityDescription: L10n.tr("Edytuj dane"))
            editControls.forEach { $0.isHidden = !edit.isEditing }
            table.reloadData()
        } else if edit.isEditing {
            // Stan komórek (zmienione, wstawione, usunięte) — przerysowanie widocznych wierszy.
            table.reloadData(forRowIndexes: IndexSet(integersIn: table.rows(in: scroll.contentView.bounds).toRange() ?? 0..<0),
                             columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        }
        if let r = tab.revealRow {
            tab.revealRow = nil
            if r < table.numberOfRows {
                table.selectRowIndexes([r], byExtendingSelection: false)
                table.scrollRowToVisible(r)
            }
        }
        if focus != lastFocus {
            lastFocus = focus
            if let f = focus { focusCell(column: f) }
        }
        if sort != lastSort {
            lastSort = sort
            updateSortIndicators()
            table.reloadData()
            lastRowCount = count
        } else if count != lastRowCount {
            if count > lastRowCount, lastRowCount > 0, sort.isEmpty {
                table.insertRows(at: IndexSet(integersIn: lastRowCount..<count), withAnimation: [])
            } else {
                table.reloadData()
            }
            lastRowCount = count
        }
        if let rowNo = table.tableColumns.first { rowNo.width = max(36, CGFloat(String(count).count) * 8 + 14) }
        if !record.isHidden { showRecord() }
    }

    private func updateSortIndicators() {
        for col in table.tableColumns {
            guard col.identifier.rawValue != "#", let i = Int(col.identifier.rawValue.dropFirst()) else { continue }
            if let k = grid.sortKeys.firstIndex(where: { $0.column == i }) {
                let key = grid.sortKeys[k]
                table.setIndicatorImage(NSImage(named: key.ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"), in: col)
                col.title = grid.sortKeys.count > 1 ? "\(grid.columns[i].name) \(k + 1)" : grid.columns[i].name
            } else {
                table.setIndicatorImage(nil, in: col)
                col.title = grid.columns[i].name
            }
        }
    }

    /// Dociąganie przy zbliżeniu do końca (płynne przewijanie milionów wierszy — PD-GRID-001).
    @objc private func scrolled() {
        let visible = table.rows(in: scroll.contentView.bounds)
        if grid.hasMore, !grid.isFetching, visible.location + visible.length > grid.rowCount - 200 {
            Task { await grid.fetchMore(1000) }
        }
    }

    @objc private func columnsMoved() { tab.columnOrder = visibleColumns() }

    private func dataColumn(atTableColumn c: Int) -> Int? {
        guard c >= 0, c < table.tableColumns.count, table.tableColumns[c].identifier.rawValue != "#" else { return nil }
        return Int(table.tableColumns[c].identifier.rawValue.dropFirst())
    }

    @objc private func cellClicked() {
        if let c = dataColumn(atTableColumn: table.clickedColumn) { tab.currentColumn = c }
    }

    /// Podwójne kliknięcie: komórka LOB/LONG/RAW albo długi tekst → Large Data Editor (UG 7.2: przycisk komórki).
    @objc private func cellDoubleClicked() {
        guard table.clickedRow >= 0, let c = dataColumn(atTableColumn: table.clickedColumn) else { return }
        tab.currentColumn = c
        let type = grid.columns[c].type
        let large = type.isLOB || [.long, .longRaw, .raw, .json, .xmltype].contains(type) || grid.text(row: table.clickedRow, column: c).count > 20
        if large, !grid.isEditable(column: c) || type.isLOB { workspace.perform("grid.largeData") }
    }

    private func visibleColumns() -> [Int] {
        table.tableColumns.compactMap { c in c.identifier.rawValue == "#" ? nil : Int(c.identifier.rawValue.dropFirst()) }
    }

    // MARK: Źródło danych

    func numberOfRows(in tableView: NSTableView) -> Int { grid.rowCount }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let cell = tableView.makeView(withIdentifier: .init("cell"), owner: nil) as? GridCell ?? GridCell(font: font)
        if id == "#" {
            // Znacznik zmiany oczekującej w nagłówku wiersza (DG-GRID-001): + wstawiony, ~ zmieniony, − usunięty.
            let state = grid.edit.isEditing ? grid.rowEditState(row: row) : .normal
            let mark = switch state { case .inserted: "+ "; case .modified: "~ "; case .deleted: "− "; case .normal: "" }
            cell.configure(text: mark + String(row + 1), alignRight: true, isNull: false, secondary: state == .normal, rowMarker: state)
            return cell
        }
        guard let i = Int(id.dropFirst()) else { return nil }
        let v = grid.value(row: row, column: i)
        cell.configure(text: grid.text(row: row, column: i), alignRight: grid.columns[i].type.isNumeric, isNull: v.isNull, secondary: false,
                       state: grid.edit.isEditing ? grid.pendingCellState(row: row, column: i) : .normal,
                       overflow: grid.edit.isEditing && grid.isOverflow(row: row, column: i),
                       editable: grid.isEditable(column: i))
        cell.textField?.delegate = self
        return cell
    }

    /// Koniec edycji komórki: wartość do modelu (konwersja typu), błąd — komunikat i przywrócenie.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let row = table.row(for: field), col = table.column(for: field)
        guard row >= 0, col >= 0, let i = Int(table.tableColumns[col].identifier.rawValue.dropFirst()) else { return }
        let text = field.stringValue
        if text == grid.text(row: row, column: i) { return }
        do {
            try grid.setText(text, row: row, column: i)
        } catch {
            workspace.ui?.showError(error.localizedDescription)
            field.stringValue = grid.text(row: row, column: i)
        }
    }

    /// Klik nagłówka: rosnąco → malejąco → bez sortowania; Shift — sortowanie wtórne (UG 7.2).
    func tableView(_ tableView: NSTableView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
        guard tableColumn.identifier.rawValue != "#", let i = Int(tableColumn.identifier.rawValue.dropFirst()) else { return }
        grid.toggleSort(column: i, add: NSEvent.modifierFlags.contains(.shift))
    }

    /// Komórka z błędem po zatwierdzaniu zmian (NF12): zaznacz wiersz, przewiń do kolumny, rozpocznij edycję.
    private func focusCell(column: Int) {
        guard let row = tab.selectedRows?.first, row < grid.rowCount,
              let colIndex = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "c\(column)" }) else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        table.scrollColumnToVisible(colIndex)
        if grid.isEditable(column: column) { table.editColumn(colIndex, row: row, with: nil, select: true) }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let rows = Array(table.selectedRowIndexes)
        tab.selectedRows = rows.isEmpty ? nil : rows
        if !record.isHidden { showRecord() }
    }

    // MARK: Pasek siatki

    @objc private func nextPage() { workspace.perform("grid.nextPage") }
    @objc private func toggleEdit() { workspace.perform("grid.edit") }
    @objc private func insertRecord() {
        workspace.perform("grid.insertRecord")
        DispatchQueue.main.async { [weak self] in
            guard let self, let row = self.tab.selectedRows?.first, row < self.grid.rowCount else { return }
            self.table.selectRowIndexes([row], byExtendingSelection: false)
            self.table.scrollRowToVisible(row)
            if let first = self.grid.edit.target?.editableColumns.min(),
               let c = self.table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "c\(first)" }) {
                self.table.editColumn(c, row: row, with: nil, select: true)
            }
        }
    }
    @objc private func deleteRecord() { workspace.perform("grid.deleteRecord") }
    @objc private func lastPage() { workspace.perform("grid.lastPage") }
    @objc private func copyToExcel() { workspace.perform("grid.copyToExcel") }

    @objc private func exportAs(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        workspace.perform("grid.export", CommandArguments(["format": .string(raw)]))
    }

    @objc private func toggleRecord() {
        record.isHidden = recordButton.state == .off
        scroll.isHidden = !record.isHidden
        if !record.isHidden {
            if table.selectedRow < 0, grid.rowCount > 0 { table.selectRowIndexes([0], byExtendingSelection: false) }
            showRecord()
        }
    }

    private func moveRecord(_ delta: Int) {
        let r = max(0, min(grid.rowCount - 1, max(0, table.selectedRow) + delta))
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
        if delta > 0, r >= grid.rowCount - 2, grid.hasMore { Task { await grid.fetchMore(100) } }
    }

    private func showRecord() {
        let row = max(0, table.selectedRow)
        guard row < grid.rowCount else { record.show(row: 0, of: 0, fields: []); return }
        let fields = visibleColumns().map { i in
            SingleRecordView.Field(name: grid.columns[i].name, value: grid.text(row: row, column: i),
                                   type: grid.columns[i].typeName, isNull: grid.value(row: row, column: i).isNull)
        }
        record.show(row: row, of: grid.rowCount, fields: fields)
    }

    // MARK: Kopiowanie (UG 7.2: Copy, Copy with Header, Copy Header, Copy as Expression List)

    private func copy(withHeader: Bool) {
        if withHeader {
            workspace.perform("grid.copyWithHeader")
        } else {
            workspace.perform("grid.copy")
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, id) in [(L10n.tr("Kopiuj"), "grid.copy"), (L10n.tr("Kopiuj z nagłówkiem"), "grid.copyWithHeader"),
                            (L10n.tr("Kopiuj nagłówek"), "grid.copyHeader"), (L10n.tr("Kopiuj jako listę wyrażeń"), "grid.copyExpressionList")] {
            let item = menu.addItem(withTitle: title, action: #selector(contextCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
        }
        let copyAs = NSMenu()
        for f in [ExportFormat.csv, .html, .xml, .sql] {
            let item = copyAs.addItem(withTitle: f.displayName, action: #selector(copyAsFormat(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = f.rawValue
        }
        let copyAsItem = menu.addItem(withTitle: L10n.tr("Kopiuj jako"), action: nil, keyEquivalent: "")
        copyAsItem.submenu = copyAs
        menu.addItem(.separator())
        for (title, id) in [(L10n.tr("Large Data Editor…"), "grid.largeData"), (L10n.tr("Eksportuj wynik…"), "grid.export"),
                            (L10n.tr("Kopiuj do Excela"), "grid.copyToExcel"), (L10n.tr("Kolumna do plików…"), "grid.columnToFiles"),
                            (L10n.tr("Zapytania powiązane…"), "grid.linkedQueries"), (L10n.tr("Porównaj rekordy"), "grid.compareRecords"),
                            (L10n.tr("Porównaj wyniki"), "grid.compareResults"), (L10n.tr("Zapisz jako zapytanie standardowe…"), "grid.saveAsStandardQuery")] {
            let item = menu.addItem(withTitle: title, action: #selector(contextCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
        }
        menu.addItem(.separator())
        for (title, id, exclude) in [(L10n.tr("Filtruj: tylko ta wartość"), "grid.filterByValue", false),
                                     (L10n.tr("Filtruj: bez tej wartości"), "grid.filterByValue", true)] {
            let item = menu.addItem(withTitle: title, action: #selector(filterByValue(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = exclude
            _ = id
        }
        for (title, id) in [(L10n.tr("Filtr wyrażeniem…"), "grid.filterExpression"), (L10n.tr("Wyczyść filtr"), "grid.clearFilter"),
                            (L10n.tr("Grupuj według kolumny"), "grid.groupBy"), (L10n.tr("Panel wartości"), "grid.valuePanel")] {
            let item = menu.addItem(withTitle: title, action: #selector(cellCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
        }
        let gen = NSMenu()
        for k in RowSQLGenerator.Kind.allCases {
            let item = gen.addItem(withTitle: k.rawValue.uppercased(), action: #selector(generateSQL(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = k.rawValue
        }
        menu.addItem(withTitle: L10n.tr("Generuj SQL z wierszy"), action: nil, keyEquivalent: "").submenu = gen
        return menu
    }

    /// Komórka spod kursora menu jako bieżąca (prawy klik nie zmienia zaznaczenia tabeli).
    private func adoptClickedCell() {
        if let c = dataColumn(atTableColumn: table.clickedColumn) { tab.currentColumn = c }
        if table.clickedRow >= 0, !(tab.selectedRows ?? []).contains(table.clickedRow) {
            table.selectRowIndexes([table.clickedRow], byExtendingSelection: false)
            tab.selectedRows = [table.clickedRow]
        }
    }

    @objc private func filterByValue(_ sender: NSMenuItem) {
        adoptClickedCell()
        workspace.perform("grid.filterByValue", CommandArguments(["exclude": .bool(sender.representedObject as? Bool ?? false)]))
    }

    @objc private func cellCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        adoptClickedCell()
        workspace.perform(CommandID(rawValue: id))
    }

    @objc private func generateSQL(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? String else { return }
        workspace.perform("grid.generateSQL", CommandArguments(["kind": .string(kind)]))
    }

    @objc private func contextCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        workspace.perform(CommandID(rawValue: id))
    }

    @objc private func copyAsFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        workspace.perform("grid.copyAs", CommandArguments(["format": .string(raw)]))
    }
}

/// Tabela siatki z obsługą Cmd+C / Cmd+Shift+C.
final class GridTableView: NSTableView {
    var copyHandler: ((Bool) -> Void)?

    @objc func copy(_ sender: Any?) { copyHandler?(false) }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains([.command, .shift]), event.charactersIgnoringModifiers?.lowercased() == "c" {
            copyHandler?(true)
            return
        }
        super.keyDown(with: event)
    }
}

/// Lekka komórka siatki (jeden NSTextField, bez autolayoutu w każdym wierszu).
final class GridCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    init(font: NSFont) {
        super.init(frame: .zero)
        identifier = .init("cell")
        label.font = font
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.autoresizingMask = [.width, .height]
        addSubview(label)
        textField = label
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 2, dy: 1)
    }

    static let modifiedColor = NSColor.systemBlue
    static let insertedBackground = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.12, green: 0.28, blue: 0.16, alpha: 1) : NSColor(srgbRed: 0.88, green: 0.97, blue: 0.88, alpha: 1) }
    static let modifiedBackground = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.12, green: 0.20, blue: 0.32, alpha: 1) : NSColor(srgbRed: 0.88, green: 0.93, blue: 1.0, alpha: 1) }
    static let deletedBackground = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.32, green: 0.12, blue: 0.12, alpha: 1) : NSColor(srgbRed: 1.0, green: 0.90, blue: 0.90, alpha: 1) }

    func configure(text: String, alignRight: Bool, isNull: Bool, secondary: Bool,
                   state: CellEditState = .normal, overflow: Bool = false, editable: Bool = false, rowMarker: CellEditState = .normal) {
        // Wielowierszowy tekst w jednej linii komórki (pełna treść — widok rekordu, Large Data Editor).
        let shown = editable ? text : (text.count > 500 ? String(text.prefix(500)) + "…" : text.replacingOccurrences(of: "\n", with: " ⏎ "))
        label.isEditable = editable && state != .deleted
        label.isSelectable = label.isEditable
        label.alignment = alignRight ? .right : .left
        let color: NSColor = overflow ? .systemRed : state == .modified ? Self.modifiedColor : secondary ? .tertiaryLabelColor : .labelColor
        if state == .deleted {
            label.attributedStringValue = NSAttributedString(string: shown, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.systemRed, .font: label.font!])
        } else {
            label.stringValue = shown
            label.textColor = color
        }
        let marker: NSColor? = switch rowMarker {
        case .inserted: Self.insertedBackground
        case .modified: Self.modifiedBackground
        case .deleted: Self.deletedBackground
        case .normal: nil
        }
        layer?.backgroundColor = marker?.cgColor ?? (state == .inserted ? Self.insertedBackground.cgColor : state == .modified ? Self.modifiedBackground.cgColor
            : isNull ? ResultGridView.nullColor.cgColor : nil)
    }
}

/// Widok pojedynczego rekordu (UG 7.2 Single Record View): kolumna, wartość, typ; poprzedni / następny rekord.
final class SingleRecordView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    struct Field {
        let name: String
        let value: String
        let type: String
        let isNull: Bool
    }

    private var fields: [Field] = []
    private let table = NSTableView()
    private let label = NSTextField(labelWithString: "")
    var onMove: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (id, title, width) in [("name", L10n.tr("Kolumna"), 180.0), ("value", L10n.tr("Wartość"), 420.0), ("type", L10n.tr("Typ"), 160.0)] {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title
            c.width = width
            table.addTableColumn(c)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.style = .plain
        table.setAccessibilityLabel(L10n.tr("Rekord w pionie"))
        table.dataSource = self
        table.delegate = self
        table.usesAutomaticRowHeights = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let prev = ClosureButton(title: "◀︎", action: { [weak self] in self?.onMove?(-1) })
        let next = ClosureButton(title: "▶︎", action: { [weak self] in self?.onMove?(1) })
        prev.toolTip = L10n.tr("Poprzedni rekord")
        next.toolTip = L10n.tr("Następny rekord")
        for b in [prev, next] { b.bezelStyle = .accessoryBarAction }
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        let nav = NSStackView(views: [prev, next, label])
        nav.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        for v in [nav, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: topAnchor),
            nav.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.topAnchor.constraint(equalTo: nav.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(row: Int, of count: Int, fields: [Field]) {
        self.fields = fields
        label.stringValue = count == 0 ? "" : L10n.tr("Rekord \(row + 1) z \(count)")
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { fields.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let f = fields[row]
        let tf = NSTextField(wrappingLabelWithString: "")
        tf.isSelectable = true
        switch tableColumn?.identifier.rawValue {
        case "name":
            tf.stringValue = f.name
            tf.font = .boldSystemFont(ofSize: 12)
        case "value":
            tf.stringValue = f.value
            tf.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            if f.isNull {
                tf.drawsBackground = true
                tf.backgroundColor = ResultGridView.nullColor
            }
        default:
            tf.stringValue = f.type
            tf.textColor = .secondaryLabelColor
        }
        return tf
    }
}
