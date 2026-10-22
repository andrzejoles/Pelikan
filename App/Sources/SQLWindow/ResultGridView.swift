import AppKit
import PelikanDB
import PelikanWorkspace

/// Siatka wyników (ADR 0004): NSTableView z wirtualizacją wierszy, kolumna numeru wiersza, NULL na kolorowym tle
/// (UG 7.2), liczby do prawej, dociąganie porcjami przy zbliżeniu do końca, kopiowanie (Cmd+C — z nagłówkiem: Cmd+Shift+C).
final class ResultGridView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let grid: ResultGridModel
    private let table = GridTableView()
    private let scroll = NSScrollView()
    private var token: ObservationToken?
    private var lastRowCount = 0
    static let nullColor = NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.30, green: 0.28, blue: 0.12, alpha: 1) : NSColor(srgbRed: 1.0, green: 0.98, blue: 0.80, alpha: 1) }
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    init(grid: ResultGridModel) {
        self.grid = grid
        super.init(frame: .zero)
        configure()
        token = trackChanges { [weak self] in self?.modelChanged() }
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
        table.copyHandler = { [weak self] withHeader in self?.copySelection(withHeader: withHeader) }
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
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
        scroll.contentView.postsBoundsChangedNotifications = true
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
        let count = grid.rowCount
        _ = grid.hasMore
        guard count != lastRowCount else { return }
        if count > lastRowCount, lastRowCount > 0 {
            table.insertRows(at: IndexSet(integersIn: lastRowCount..<count), withAnimation: [])
        } else {
            table.reloadData()
        }
        lastRowCount = count
        if let rowNo = table.tableColumns.first { rowNo.width = max(36, CGFloat(String(count).count) * 8 + 14) }
    }

    /// Dociąganie przy zbliżeniu do końca (płynne przewijanie milionów wierszy — PD-GRID-001).
    @objc private func scrolled() {
        let visible = table.rows(in: scroll.contentView.bounds)
        if grid.hasMore, !grid.isFetching, visible.location + visible.length > grid.rowCount - 200 {
            Task { await grid.fetchMore(1000) }
        }
    }

    // MARK: Źródło danych

    func numberOfRows(in tableView: NSTableView) -> Int { grid.rowCount }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let cell = tableView.makeView(withIdentifier: .init("cell"), owner: nil) as? GridCell ?? GridCell(font: font)
        if id == "#" {
            cell.configure(text: String(row + 1), alignRight: true, isNull: false, secondary: true)
            return cell
        }
        guard let i = Int(id.dropFirst()) else { return nil }
        let v = grid.value(row: row, column: i)
        cell.configure(text: grid.text(row: row, column: i), alignRight: grid.columns[i].type.isNumeric, isNull: v.isNull, secondary: false)
        return cell
    }

    // MARK: Kopiowanie (UG 7.2: Copy, Copy with Header)

    private func copySelection(withHeader: Bool) {
        let rows = table.selectedRowIndexes.isEmpty ? IndexSet(integersIn: 0..<grid.rowCount) : table.selectedRowIndexes
        let cols = table.tableColumns.compactMap { c -> Int? in c.identifier.rawValue == "#" ? nil : Int(c.identifier.rawValue.dropFirst()) }
        var lines: [String] = []
        if withHeader { lines.append(cols.map { grid.columns[$0].name }.joined(separator: "\t")) }
        for r in rows { lines.append(cols.map { grid.text(row: r, column: $0) }.joined(separator: "\t")) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
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
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 2, dy: 1)
    }

    func configure(text: String, alignRight: Bool, isNull: Bool, secondary: Bool) {
        label.stringValue = text
        label.alignment = alignRight ? .right : .left
        label.textColor = secondary ? .tertiaryLabelColor : .labelColor
        layer?.backgroundColor = isNull ? ResultGridView.nullColor.cgColor : nil
    }
}
