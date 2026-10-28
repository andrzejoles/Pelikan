import AppKit
import PelikanDB
import PelikanWorkspace

/// Lista połączeń (UG 19.1): foldery użytkownika (połączenia jawne i z reguł), folder „Ostatnie”, pod połączeniem okna
/// z jego sesjami. Ikona klucza: hasło nieznane / znane / połączone. Połączenie główne pogrubione. Dwuklik = Połącz jako
/// główne. Foldery i połączenia alfabetycznie (kolejność z `ConnectionStore`); połączenie przeciągnięte na folder albo
/// na wolne miejsce listy (poziom główny) jest przenoszone komendą `connection.moveToFolder`.
final class ConnectionListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    static let connectionPasteboardType = NSPasteboard.PasteboardType("local.pelikan.connection")
    private let workspace: Workspace
    private let outline = NSOutlineView()
    private var roots: [Node] = []
    /// Korzenie już pokazane — nowe (np. pierwszy raz „Ostatnie”) są rozwijane, znane zachowują stan użytkownika.
    private var seenRoots = Set<String>()

    final class Node {
        enum Kind { case folder(ConnectionFolder), recent, connection(ConnectionDefinition), window(Document) }
        let kind: Kind
        var children: [Node] = []
        /// Ścieżka identyfikatorów od korzenia (to samo połączenie bywa w folderze i w „Ostatnich”).
        var key = ""
        init(_ kind: Kind) { self.kind = kind }

        var localKey: String {
            switch kind {
            case .folder(let f): "f:" + f.id.uuidString
            case .recent: "recent"
            case .connection(let c): "c:" + c.id.uuidString
            case .window(let d): "w:" + d.id.description
            }
        }

        var connectionID: UUID? {
            if case .connection(let c) = kind { return c.id }
            return nil
        }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        // Drzewo z wyraźnym wcięciem poziomów (styl listy paska bocznego macOS prawie nie wcina dzieci).
        outline.style = .plain
        outline.indentationPerLevel = 16
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.setAccessibilityLabel(L10n.tr("Lista połączeń"))
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        outline.registerForDraggedTypes([Self.connectionPasteboardType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: L10n.tr("Nowe połączenie"))!,
                           target: self, action: #selector(newConnection))
        let folder = NSButton(image: NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: L10n.tr("Nowy folder"))!,
                              target: self, action: #selector(newFolder))
        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: L10n.tr("Odśwież"))!,
                               target: self, action: #selector(reloadTree))
        for b in [add, folder, refresh] {
            b.isBordered = false
            b.toolTip = b.image?.accessibilityDescription
        }
        let bar = NSStackView(views: [add, folder, NSView(), refresh])
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        let root = NSView()
        for v in [bar, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 26),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        trackChanges { [weak self] in self?.reloadTree() }
    }

    @objc func reloadTree() {
        outline.rowHeight = AppFonts.rowHeight(for: InterfaceFonts.shared.bold)
        let store = workspace.connections
        // Odczyty rejestrują śledzenie zmian (lista, sesje, okna, połączenie główne).
        _ = (store.connections, store.folders, workspace.sessions.mainConnectionID, workspace.sessions.openSessionCount,
             workspace.documents.map(\.connectionID))
        func folderNode(_ f: ConnectionFolder) -> Node {
            let n = Node(.folder(f))
            n.children = store.subfolders(of: f.id).map(folderNode) + store.connections(in: f.id).map(connectionNode)
            return n
        }
        var r: [Node] = store.subfolders(of: nil).map(folderNode)
        r += store.connections(in: nil).map(connectionNode)
        let recent = store.recent()
        if !recent.isEmpty {
            let n = Node(.recent)
            n.children = recent.map(connectionNode)
            r.append(n)
        }
        func assignKeys(_ nodes: [Node], _ prefix: String) {
            for n in nodes { n.key = prefix + "/" + n.localKey; assignKeys(n.children, n.key) }
        }
        assignKeys(r, "")
        // Nowe węzły przy każdej zmianie okien i sesji — rozwinięcie i zaznaczenie przenoszone po ścieżce (R4-11).
        var expanded = Set<String>()
        func collect(_ nodes: [Node]) {
            for n in nodes where outline.isItemExpanded(n) { expanded.insert(n.key); collect(n.children) }
        }
        collect(roots)
        let selected = Set(outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? Node)?.key })
        roots = r
        outline.reloadData()
        func restore(_ nodes: [Node], root: Bool) {
            for n in nodes where expanded.contains(n.key) || (root && !seenRoots.contains(n.key)) {
                outline.expandItem(n)
                restore(n.children, root: false)
            }
        }
        restore(roots, root: true)
        seenRoots.formUnion(roots.map(\.key))
        if !selected.isEmpty {
            let rows = (0..<outline.numberOfRows).filter { (outline.item(atRow: $0) as? Node).map { selected.contains($0.key) } ?? false }
            outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
        }
    }

    private func connectionNode(_ c: ConnectionDefinition) -> Node {
        let n = Node(.connection(c))
        n.children = workspace.documents.filter { workspace.effectiveConnection(of: $0) == c.id && workspace.sessions
            .existingSession(workspace.sessions.key(forDocument: $0.id, connection: c.id)) != nil }.map { Node(.window($0)) }
        return n
    }

    // MARK: Źródło danych

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Node)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let cell = NSTableCellView()
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.font = InterfaceFonts.shared.body
        cell.imageView = image
        cell.textField = text
        for v in [image, text] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        switch node.kind {
        case .folder(let f):
            image.image = NSImage(systemSymbolName: f.hasRule ? "folder.badge.gearshape" : "folder", accessibilityDescription: nil)
            image.contentTintColor = f.color.map(NSColor.init(rgb:)) ?? .secondaryLabelColor
            text.stringValue = f.name
        case .recent:
            image.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            image.contentTintColor = .secondaryLabelColor
            text.stringValue = L10n.tr("Ostatnie")
        case .connection(let c):
            let status = workspace.sessions.status(of: c.id)
            let symbol: String
            switch status {
            case .connected: symbol = "key.fill"
            case .passwordKnown: symbol = "key"
            case .passwordUnknown: symbol = "key.slash"
            }
            image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image.contentTintColor = c.effectiveColor.map(NSColor.init(rgb:)) ?? (status == .passwordUnknown ? .secondaryLabelColor : .labelColor)
            var title = c.displayName
            if let s = c.currentSchema, !s.isEmpty { title += " [\(s)]" }
            if c.environment != .other { title += "  ·  \(c.environment.shortName)" }
            text.stringValue = title
            let isMain = workspace.sessions.mainConnectionID == c.id
            text.font = isMain ? InterfaceFonts.shared.bold : InterfaceFonts.shared.body
            cell.toolTip = c.connectionString
            cell.setAccessibilityLabel((isMain ? L10n.tr("Połączenie główne: ") : "") + c.displayName)
        case .window(let d):
            image.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            image.contentTintColor = DocumentTabButton.color(for: d.kind)
            text.stringValue = d.fullTitle
        }
        return cell
    }

    // MARK: Akcje

    private var clickedNode: Node? {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        return row >= 0 ? outline.item(atRow: row) as? Node : nil
    }

    @objc private func doubleClicked() {
        guard let node = clickedNode else { return }
        switch node.kind {
        case .connection(let c): workspace.perform("connection.connectAsMain", CommandArguments(["connection": .string(c.id.uuidString)]))
        case .window(let d): workspace.activate(d.id)
        default: break
        }
    }

    @objc private func newConnection() { workspace.perform("connection.new") }

    @objc private func newFolder() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Nowy folder")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.tr("Utwórz"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        var args: [String: JSONValue] = ["name": .string(field.stringValue)]
        if let node = clickedNode, case .folder(let f) = node.kind { args["parent"] = .string(f.id.uuidString) }
        workspace.perform("connection.newFolder", CommandArguments(args))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = clickedNode else {
            menu.addItem(item(L10n.tr("Nowe połączenie…"), "connection.new", nil))
            return
        }
        switch node.kind {
        case .connection(let c):
            let arg = c.id.uuidString
            menu.addItem(item(L10n.tr("Połącz jako główne"), "connection.connectAsMain", arg))
            menu.addItem(item(L10n.tr("Połącz"), "connection.connect", arg))
            menu.addItem(item(L10n.tr("Rozłącz"), "connection.disconnect", arg))
            menu.addItem(.separator())
            let open = NSMenuItem(title: L10n.tr("Nowe okno"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, kind) in [(L10n.tr("Okno SQL"), "sql"), (L10n.tr("Okno programu"), "program"), (L10n.tr("Okno testu"), "test"), (L10n.tr("Okno poleceń"), "command")] {
                let i = item(title, "connection.openWindow", arg)
                i.representedObject = ["connection.openWindow", arg, kind]
                sub.addItem(i)
            }
            open.submenu = sub
            menu.addItem(open)
            menu.addItem(item(L10n.tr("Pokaż okna połączenia"), "connection.showWindows", arg))
            menu.addItem(item(L10n.tr("Połącz ponownie okna połączenia"), "connection.reconnectWindows", arg))
            menu.addItem(item(L10n.tr("Zamknij okna połączenia"), "connection.closeWindows", arg))
            menu.addItem(item(L10n.tr("Ustaw bieżący schemat…"), "connection.setCurrentSchema", arg))
            menu.addItem(.separator())
            menu.addItem(item(L10n.tr("Edytuj…"), "connection.edit", arg))
            menu.addItem(item(L10n.tr("Kopiuj pod inną nazwą…"), "connection.duplicate", arg))
            menu.addItem(moveMenu(c))
            menu.addItem(item(L10n.tr("Usuń…"), "connection.delete", arg))
        case .folder, .recent:
            menu.addItem(item(L10n.tr("Nowe połączenie…"), "connection.new", nil))
        case .window(let d):
            let activate = NSMenuItem(title: L10n.tr("Aktywuj"), action: #selector(activateWindow(_:)), keyEquivalent: "")
            activate.target = self
            activate.representedObject = d
            menu.addItem(activate)
        }
    }

    /// Podmenu „Przenieś do folderu” — to samo co przeciągnięcie, dostępne z klawiatury i VoiceOver.
    private func moveMenu(_ c: ConnectionDefinition) -> NSMenuItem {
        let move = NSMenuItem(title: L10n.tr("Przenieś do folderu"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let store = workspace.connections
        func add(_ title: String, _ folder: UUID?, depth: Int) {
            let i = NSMenuItem(title: title, action: #selector(moveToFolder(_:)), keyEquivalent: "")
            i.target = self
            i.indentationLevel = depth
            i.representedObject = [c.id.uuidString, folder?.uuidString ?? ""]
            i.state = c.folderID == folder ? .on : .off
            sub.addItem(i)
        }
        add(L10n.tr("Poziom główny listy"), nil, depth: 0)
        func addFolders(_ parent: UUID?, depth: Int) {
            for f in store.subfolders(of: parent) {
                add(f.name, f.id, depth: depth)
                addFolders(f.id, depth: depth + 1)
            }
        }
        addFolders(nil, depth: 0)
        move.submenu = sub
        return move
    }

    @objc private func moveToFolder(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        move(connection: pair[0], to: pair[1].isEmpty ? nil : pair[1])
    }

    private func move(connection: String, to folder: String?) {
        var args: [String: PelikanWorkspace.JSONValue] = ["connection": .string(connection)]
        if let folder { args["folder"] = .string(folder) }
        workspace.perform("connection.moveToFolder", CommandArguments(args))
    }

    // MARK: Przeciąganie połączeń między folderami

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? Node, let id = node.connectionID else { return nil }
        let p = NSPasteboardItem()
        p.setString(id.uuidString, forType: Self.connectionPasteboardType)
        return p
    }

    /// Folder docelowy upuszczenia: folder pod kursorem, folder połączenia pod kursorem albo poziom główny (wolne
    /// miejsce, połączenie na poziomie głównym; okno — jak jego połączenie). „Ostatnie” nie jest celem. `nil` w wyniku —
    /// upuszczenie odrzucone.
    private func dropFolder(for item: Any?) -> UUID?? {
        guard let node = item as? Node else { return .some(nil) }
        switch node.kind {
        case .folder(let f): return .some(f.id)
        case .connection:
            guard let parent = outline.parent(forItem: node) as? Node else { return .some(nil) }
            if case .folder(let f) = parent.kind { return .some(f.id) }
            return nil
        case .window:
            // Wiersz okna pod połączeniem — jak upuszczenie na to połączenie (tak samo jak między wiersze okien).
            return dropFolder(for: outline.parent(forItem: node))
        case .recent: return nil
        }
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard let s = info.draggingPasteboard.string(forType: Self.connectionPasteboardType), let id = UUID(uuidString: s),
              let def = workspace.connections.connection(id), let target = dropFolder(for: item) else { return [] }
        // Podświetlenie całego folderu docelowego (kolejność w folderze jest alfabetyczna — bez wstawiania między wiersze).
        let folderNode = target.flatMap { t in allNodes(roots).first { if case .folder(let f) = $0.kind { f.id == t } else { false } } }
        outlineView.setDropItem(folderNode, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return def.folderID == target ? [] : .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let s = info.draggingPasteboard.string(forType: Self.connectionPasteboardType), let target = dropFolder(for: item) else { return false }
        move(connection: s, to: target?.uuidString)
        return true
    }

    private func allNodes(_ nodes: [Node]) -> [Node] { nodes.flatMap { [$0] + allNodes($0.children) } }

    private func item(_ title: String, _ command: String, _ connection: String?) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = [command, connection ?? ""]
        return i
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count >= 2 else { return }
        var values: [String: PelikanWorkspace.JSONValue] = pair[1].isEmpty ? [:] : ["connection": .string(pair[1])]
        if pair.count > 2 { values["kind"] = .string(pair[2]) }
        let args = CommandArguments(values)
        workspace.perform(CommandID(rawValue: pair[0]), args)
    }

    @objc private func activateWindow(_ sender: NSMenuItem) {
        if let d = sender.representedObject as? Document { workspace.activate(d.id) }
    }
}

extension NSColor {
    convenience init(rgb: PelikanWorkspace.RGBColor) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}
