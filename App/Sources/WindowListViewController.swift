import AppKit
import PelikanWorkspace

/// Lista okien (UG 32): tytuł z typem, status (zmieniony / transakcja), kolor połączenia, klik aktywuje, środkowy klik
/// zamyka; menu: Wykonaj, Połącz ponownie, Zmień nazwę, Krótkie nazwy, Nowe, Sortuj, Zamknij (PD-UI-002). Przy kilku
/// grupach kart — drzewo według grup (D200): węzeł grupy z kolorem, nazwą i liczbą okien; klik pokazuje grupę.
final class WindowListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let workspace: Workspace
    private let table = NSOutlineView()
    /// Węzeł grupy (obiekt — NSOutlineView porównuje elementy po tożsamości).
    private final class GroupNode {
        let group: TabGroup
        var documents: [Document]
        init(group: TabGroup, documents: [Document]) { self.group = group; self.documents = documents }
    }
    private var groups: [GroupNode] = []
    /// Okna bez drzewa (jedna grupa).
    private var flat: [Document] = []
    private var collapsed: Set<String> = []

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("title"))
        column.title = L10n.tr("Okna")
        table.addTableColumn(column)
        table.outlineTableColumn = column
        table.headerView = nil
        table.style = .plain
        table.indentationPerLevel = 10
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.setAccessibilityLabel(L10n.tr("Lista okien"))
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false  // stan pozycji z `item(…, enabled:)` (np. Wykonaj w trakcie wykonania)
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        view = scroll
        trackChanges { [weak self] in self?.reload() }
    }

    private func reload() {
        table.rowHeight = AppFonts.rowHeight(for: InterfaceFonts.shared.body)
        let documents = workspace.windowListDocuments
        // Odczyt właściwości rejestruje śledzenie zmian tytułu, stanu i połączenia.
        _ = documents.map { ($0.title, $0.isModified, $0.transactionOpen, $0.connectionID, workspace.indicatorColor(for: $0)) }
        let tabGroups = workspace.tabGroups
        if tabGroups.count > 1 {
            // Okna w grupie w kolejności listy okien (sortowanie z menu).
            groups = tabGroups.map { g in
                let ids = Set(g.documents)
                return GroupNode(group: g, documents: documents.filter { ids.contains($0.id) })
            }
            flat = []
        } else {
            groups = []
            flat = documents
        }
        table.reloadData()
        for g in groups where !collapsed.contains(g.group.id) { table.expandItem(g) }
        if let doc = (groups.flatMap(\.documents) + flat).first(where: { $0.id == workspace.activeDocumentID }) {
            let row = table.row(forItem: doc)
            if row >= 0 { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let g = item as? GroupNode { return g.documents.count }
        return groups.isEmpty ? flat.count : groups.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let g = item as? GroupNode { return g.documents[index] }
        return groups.isEmpty ? flat[index] : groups[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is GroupNode }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let g = notification.userInfo?["NSObject"] as? GroupNode { collapsed.insert(g.group.id) }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let g = notification.userInfo?["NSObject"] as? GroupNode { collapsed.remove(g.group.id) }
    }

    private func cell(_ outlineView: NSOutlineView) -> NSTableCellView {
        outlineView.makeView(withIdentifier: .init("cell"), owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = .init("cell")
            let image = NSImageView()
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            c.imageView = image
            c.textField = text
            for v in [image, text] {
                v.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(v)
            }
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 14),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = cell(outlineView)
        if let g = item as? GroupNode {
            // Węzeł grupy: kolor grupy, nazwa, szczegół i liczba okien.
            cell.imageView?.image = TabPaletteColors.swatch(g.group.colorIndex, size: 11)
            cell.imageView?.contentTintColor = nil
            let title = NSMutableAttributedString(string: g.group.name, attributes: [.font: InterfaceFonts.shared.bold, .foregroundColor: NSColor.labelColor])
            title.append(NSAttributedString(string: "  " + g.group.caption,
                                            attributes: [.font: InterfaceFonts.shared.small, .foregroundColor: NSColor.secondaryLabelColor]))
            cell.textField?.attributedStringValue = title
            cell.setAccessibilityLabel(g.group.name + ", " + g.group.caption)
            return cell
        }
        guard let doc = item as? Document else { return nil }
        let symbol = doc.transactionOpen ? "circle.fill" : (doc.isModified ? "pencil.circle" : "doc.text")
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = doc.transactionOpen ? .systemGreen : DocumentTabButton.color(for: doc.kind)
        // Kolor palety połączenia (tło karty, D200) i kolor środowiska (wskaźnik, PD-CONN-005) przed tytułem.
        let title = NSMutableAttributedString()
        if let p = workspace.paletteIndex(for: doc) {
            let a = NSTextAttachment()
            a.image = TabPaletteColors.swatch(p, size: 9)
            title.append(NSAttributedString(attachment: a))
            title.append(NSAttributedString(string: " "))
        }
        if let c = workspace.indicatorColor(for: doc) {
            title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)]))
        }
        title.append(NSAttributedString(string: workspace.windowListTitle(doc), attributes: [.foregroundColor: NSColor.labelColor]))
        title.addAttribute(.font, value: InterfaceFonts.shared.body, range: NSRange(location: 0, length: title.length))
        cell.textField?.attributedStringValue = title
        cell.setAccessibilityLabel(nil)
        return cell
    }

    private var clickedDocument: Document? { table.item(atRow: table.clickedRow) as? Document }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let doc = clickedDocument
        func item(_ title: String, _ command: String, _ args: [String: JSONValue] = [:], enabled: Bool = true) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(performMenuCommand(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = (command, args) as (String, [String: JSONValue])
            i.isEnabled = enabled
            return i
        }
        if let g = table.item(atRow: table.clickedRow) as? GroupNode, g.group.kind == .manual {
            menu.addItem(item(L10n.tr("Zmień nazwę…"), "window.renameGroup", ["group": .string(g.group.id)]))
            menu.addItem(item(L10n.tr("Rozgrupuj"), "window.ungroup", ["group": .string(g.group.id)]))
            menu.addItem(.separator())
        }
        if let doc {
            let a: [String: JSONValue] = ["document": .string(doc.id.description)]
            menu.addItem(item(L10n.tr("Wykonaj"), "window.execute", a, enabled: !doc.isExecuting))
            menu.addItem(item(L10n.tr("Połącz ponownie"), "window.reconnect", a, enabled: !doc.transactionOpen && !doc.isExecuting))
            menu.addItem(item(L10n.tr("Zmień nazwę…"), "window.rename", a))
            menu.addItem(item(L10n.tr("Zamknij"), "file.closeWindow", a))
            if workspace.tabGroupState.assignments[doc.id] != nil {
                menu.addItem(item(L10n.tr("Usuń z grupy ręcznej"), "window.removeFromGroup", a))
            }
            menu.addItem(.separator())
        }
        let short = item(L10n.tr("Krótkie nazwy"), "window.listShortTitles")
        short.state = workspace.settings.windowListShortTitles ? .on : .off
        menu.addItem(short)
        let new = NSMenuItem(title: L10n.tr("Nowe"), action: nil, keyEquivalent: "")
        new.submenu = NSMenu()
        for (t, c) in [(L10n.tr("Okno SQL"), "file.new.sql"), (L10n.tr("Okno testu"), "file.new.test"),
                       (L10n.tr("Okno programu"), "file.new.program"), (L10n.tr("Konsola SQL*Plus"), "file.new.command")] {
            new.submenu?.addItem(item(t, c))
        }
        menu.addItem(new)
        let sort = NSMenuItem(title: L10n.tr("Sortuj"), action: nil, keyEquivalent: "")
        sort.submenu = NSMenu()
        for o in WindowListSort.allCases {
            let i = item(o.displayName, "window.listSort", ["order": .string(o.rawValue)])
            i.state = workspace.settings.windowListSort == o ? .on : .off
            sort.submenu?.addItem(i)
        }
        menu.addItem(sort)
    }

    @objc private func performMenuCommand(_ sender: NSMenuItem) {
        guard let (command, args) = sender.representedObject as? (String, [String: JSONValue]) else { return }
        workspace.perform(CommandID(rawValue: command), CommandArguments(args))
    }

    @objc private func rowClicked() {
        let item = table.item(atRow: table.clickedRow)
        if let doc = item as? Document {
            workspace.activate(doc.id)
        } else if let g = item as? GroupNode {
            workspace.perform("window.showGroup", CommandArguments(["group": .string(g.group.id)]))
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = table.convert(event.locationInWindow, from: nil)
        if event.buttonNumber == 2, let doc = table.item(atRow: table.row(at: point)) as? Document {
            workspace.perform("file.closeWindow", CommandArguments(["document": .string(doc.id.description)]))
        }
    }
}
