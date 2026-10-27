import AppKit
import PelikanSQL
import PelikanWorkspace

/// Code Contents (UG 25.15): drzewo struktury kodu — jednostki, podprogramy, deklaracje; śledzi kursor (zaznacza
/// element zawierający pozycję), klik przenosi do nazwy elementu; sortowanie i menu elementu (PD-CA-010).
final class CodeContentsView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    /// Węzeł drzewa (NSOutlineView wymaga obiektów o stałej tożsamości).
    final class Item {
        let node: OutlineNode
        let children: [Item]
        init(_ node: OutlineNode) {
            self.node = node
            // Parametry pokazywane w nazwie podprogramu, nie jako osobne węzły.
            children = node.children.filter { $0.kind != .parameter }.map(Item.init)
        }
    }

    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var roots: [Item] = []
    private var selecting = false
    private var rawNodes: [OutlineNode] = []
    var onSelect: ((OutlineNode) -> Void)?
    /// Kolejność elementów (Preferencje › Edytor, menu panelu).
    var order: CodeContents.Order = .source {
        didSet { if order != oldValue { update(rawNodes) } }
    }

    private var fontToken: ObservationToken?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let c = NSTableColumn(identifier: .init("name"))
        c.resizingMask = .autoresizingMask
        outline.addTableColumn(c)
        outline.outlineTableColumn = c
        outline.headerView = nil
        // Wysokość wiersza z czcionki interfejsu (przy stylu innym niż `.custom` AppKit ignoruje `rowHeight`).
        outline.rowSizeStyle = .custom
        // Drzewo z wyraźnym wcięciem poziomów (styl listy paska bocznego macOS prawie nie wcina dzieci).
        outline.style = .plain
        outline.indentationPerLevel = 16
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.setAccessibilityLabel(L10n.tr("Zawartość kodu"))
        outline.menu = NSMenu()
        outline.menu?.delegate = self
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        fontToken = trackChanges { [weak self] in
            guard let self else { return }
            let font = InterfaceFonts.shared.small
            outline.rowHeight = AppFonts.rowHeight(for: font)
            // Bez `reloadData` — zachowuje rozwinięcie i zaznaczenie.
            for row in 0..<outline.numberOfRows {
                (outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView)?.textField?.font = font
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Nowy zarys; zachowuje rozwinięcie węzłów o tej samej ścieżce nazw.
    func update(_ nodes: [OutlineNode]) {
        var expanded = Set<String>()
        func collect(_ items: [Item], _ prefix: String) {
            for i in items where outline.isItemExpanded(i) {
                let key = prefix + "/" + i.node.name
                expanded.insert(key)
                collect(i.children, key)
            }
        }
        let first = roots.isEmpty
        collect(roots, "")
        rawNodes = nodes
        roots = CodeContents.sorted(nodes, order: order).map(Item.init)
        outline.reloadData()
        func restore(_ items: [Item], _ prefix: String, depth: Int) {
            for i in items {
                let key = prefix + "/" + i.node.name
                if expanded.contains(key) || (first && depth == 0) { outline.expandItem(i); restore(i.children, key, depth: depth + 1) }
            }
        }
        restore(roots, "", depth: 0)
    }

    /// Śledzenie kursora: zaznacza najgłębszy element zawierający pozycję.
    func track(offset: Int) {
        var level = roots
        var target: Item?
        while let i = level.first(where: { $0.node.range.contains(offset) || $0.node.range.upperBound == offset }) {
            target = i
            if !i.node.isContainer { break }
            if i.children.contains(where: { $0.node.range.contains(offset) }) { outline.expandItem(i) }
            level = i.children
        }
        guard let target else { outline.deselectAll(nil); return }
        let row = outline.row(forItem: target)
        guard row >= 0, outline.selectedRow != row else { return }
        selecting = true
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        selecting = false
    }

    // MARK: Menu elementu (PD-CA-010)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
        if let item = outline.item(atRow: outline.clickedRow) as? Item {
            let n = item.node
            let args = CommandArguments(["offset": .int(Int64(n.nameOffset))])
            menu.addItem(ClosureMenuItem(title: L10n.tr("Przejdź")) { [weak self] in self?.onSelect?(n) })
            menu.addItem(ClosureMenuItem(title: L10n.tr("Zaznacz")) { ws.perform("codeContents.select", args) })
            menu.addItem(ClosureMenuItem(title: L10n.tr("Kopiuj")) { ws.perform("codeContents.copy", args) })
            menu.addItem(ClosureMenuItem(title: L10n.tr("Wytnij")) { ws.perform("codeContents.cut", args) })
            if [.procedure, .function].contains(n.kind) {
                menu.addItem(ClosureMenuItem(title: L10n.tr("Testuj")) { ws.perform("codeContents.test", args) })
            }
            menu.addItem(.separator())
        }
        let sort = NSMenuItem(title: L10n.tr("Sortuj"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (o, title) in [(CodeContents.Order.source, L10n.tr("Jak w źródle")), (.name, L10n.tr("Alfabetycznie")), (.kind, L10n.tr("Według rodzaju"))] {
            let i = ClosureMenuItem(title: title) { ws.perform("codeContents.sort", CommandArguments(["order": .string(o.rawValue)])) }
            i.state = order == o ? .on : .off
            sub.addItem(i)
        }
        sort.submenu = sub
        menu.addItem(sort)
    }

    @objc private func clicked() {
        guard let i = outline.item(atRow: outline.clickedRow) as? Item else { return }
        onSelect?(i.node)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Item)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Item)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Item)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = (item as? Item)?.node else { return nil }
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: Self.symbol(n.kind), accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = Self.tint(n.kind)
        let label = NSTextField(labelWithString: Self.title(n))
        label.font = InterfaceFonts.shared.small
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = Self.title(n)
        for v in [icon, label] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14), icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
        ])
        cell.textField = label
        return cell
    }

    /// Tekst węzła: nazwa, parametry podprogramu, typ zwracany albo typ deklaracji.
    static func title(_ n: OutlineNode) -> String {
        switch n.kind {
        case .procedure, .function:
            let params = n.children.filter { $0.kind == .parameter }.map(\.name)
            var s = n.name + (params.isEmpty ? "" : "(" + params.joined(separator: ", ") + ")")
            if !n.detail.isEmpty { s += " return " + n.detail }
            return s
        case .package: return n.name + " (" + L10n.tr("specyfikacja") + ")"
        case .packageBody, .typeBody: return n.name + " (" + L10n.tr("ciało") + ")"
        case .block: return n.name
        default: return n.detail.isEmpty ? n.name : n.name + " " + n.detail
        }
    }

    static func symbol(_ k: OutlineNode.Kind) -> String {
        // Rodzaje będące obiektami bazy — ikony jak w Object Browserze i podpowiedziach.
        switch k {
        case .package, .packageBody: ObjectSymbols.symbol(for: .package)
        case .type, .typeBody, .typeDeclaration: ObjectSymbols.symbol(for: .type)
        case .procedure: ObjectSymbols.symbol(for: .procedure)
        case .function: ObjectSymbols.symbol(for: .function)
        case .trigger: ObjectSymbols.symbol(for: .trigger)
        case .block, .declareSection, .beginSection, .exceptionSection: "curlybraces"
        case .cursor: "list.bullet.rectangle"
        case .exception: "exclamationmark.triangle"
        case .constant: "c.square"
        case .variable, .parameter: "v.square"
        }
    }

    static func tint(_ k: OutlineNode.Kind) -> NSColor {
        switch k {
        case .package, .packageBody, .type, .typeBody: .systemOrange
        case .procedure, .function, .trigger: .systemBlue
        case .exception: .systemRed
        default: .secondaryLabelColor
        }
    }
}
