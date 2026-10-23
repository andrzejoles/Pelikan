import AppKit
import PelikanSQL
import PelikanWorkspace

/// Code Contents (UG 25.15): drzewo struktury kodu — jednostki, podprogramy, deklaracje; śledzi kursor (zaznacza
/// element zawierający pozycję), klik przenosi do nazwy elementu.
final class CodeContentsView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
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
    var onSelect: ((OutlineNode) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let c = NSTableColumn(identifier: .init("name"))
        c.resizingMask = .autoresizingMask
        outline.addTableColumn(c)
        outline.outlineTableColumn = c
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.style = .sourceList
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.setAccessibilityLabel(L10n.tr("Zawartość kodu"))
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
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
        roots = nodes.map(Item.init)
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
        label.font = .systemFont(ofSize: 11)
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
        switch k {
        case .package, .packageBody: "shippingbox"
        case .type, .typeBody, .typeDeclaration: "t.square"
        case .procedure: "p.square"
        case .function: "f.square"
        case .trigger: "bolt"
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
