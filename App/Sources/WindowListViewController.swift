import AppKit
import PelikanWorkspace

/// Lista okien (UG 32): tytuł z typem, status (zmieniony / transakcja), kolor połączenia, klik aktywuje, środkowy klik
/// zamyka; menu: Wykonaj, Połącz ponownie, Zmień nazwę, Krótkie nazwy, Nowe, Sortuj, Zamknij (PD-UI-002).
final class WindowListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let workspace: Workspace
    private let table = NSTableView()
    private var documents: [Document] = []

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
        table.headerView = nil
        table.style = .plain
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
        documents = workspace.windowListDocuments
        // Odczyt właściwości rejestruje śledzenie zmian tytułu, stanu i połączenia.
        _ = documents.map { ($0.title, $0.isModified, $0.transactionOpen, $0.connectionID, workspace.indicatorColor(for: $0)) }
        table.reloadData()
        if let i = documents.firstIndex(where: { $0.id == workspace.activeDocumentID }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { documents.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let doc = documents[row]
        let cell = tableView.makeView(withIdentifier: .init("cell"), owner: self) as? NSTableCellView ?? {
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
        let symbol = doc.transactionOpen ? "circle.fill" : (doc.isModified ? "pencil.circle" : "doc.text")
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = doc.transactionOpen ? .systemGreen : DocumentTabButton.color(for: doc.kind)
        // Kolor połączenia (wskaźnik, PD-CONN-005) jako kropka przed tytułem.
        let title = NSMutableAttributedString()
        if let c = workspace.indicatorColor(for: doc) {
            title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)]))
        }
        title.append(NSAttributedString(string: workspace.windowListTitle(doc), attributes: [.foregroundColor: NSColor.labelColor]))
        title.addAttribute(.font, value: InterfaceFonts.shared.body, range: NSRange(location: 0, length: title.length))
        cell.textField?.attributedStringValue = title
        return cell
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        let doc = row >= 0 && row < documents.count ? documents[row] : nil
        func item(_ title: String, _ command: String, _ args: [String: JSONValue] = [:], enabled: Bool = true) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(performMenuCommand(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = (command, args) as (String, [String: JSONValue])
            i.isEnabled = enabled
            return i
        }
        if let doc {
            let a: [String: JSONValue] = ["document": .string(doc.id.description)]
            menu.addItem(item(L10n.tr("Wykonaj"), "window.execute", a, enabled: !doc.isExecuting))
            menu.addItem(item(L10n.tr("Połącz ponownie"), "window.reconnect", a, enabled: !doc.transactionOpen && !doc.isExecuting))
            menu.addItem(item(L10n.tr("Zmień nazwę…"), "window.rename", a))
            menu.addItem(item(L10n.tr("Zamknij"), "file.closeWindow", a))
            menu.addItem(.separator())
        }
        let short = item(L10n.tr("Krótkie nazwy"), "window.listShortTitles")
        short.state = workspace.settings.windowListShortTitles ? .on : .off
        menu.addItem(short)
        let new = NSMenuItem(title: L10n.tr("Nowe"), action: nil, keyEquivalent: "")
        new.submenu = NSMenu()
        for (t, c) in [(L10n.tr("Okno SQL"), "file.new.sql"), (L10n.tr("Okno testu"), "file.new.test"),
                       (L10n.tr("Okno programu"), "file.new.program"), (L10n.tr("Okno poleceń"), "file.new.command")] {
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
        let row = table.clickedRow
        guard row >= 0, row < documents.count else { return }
        workspace.activate(documents[row].id)
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        if event.buttonNumber == 2, row >= 0, row < documents.count {
            workspace.perform("file.closeWindow", CommandArguments(["document": .string(documents[row].id.description)]))
        }
    }
}
