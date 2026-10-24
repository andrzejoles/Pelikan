import AppKit
import PelikanDB
import PelikanWorkspace

/// Object Browser (UG 21): obiekty połączenia głównego w folderach typów, wybór użytkownika i filtr, elementy obiektu
/// (kolumny, indeksy, więzy, wyzwalacze, podprogramy, zależności), Ostatnie, menu kontekstowe z komend `ob.*`.
final class ObjectBrowserViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let workspace: Workspace
    private let outline = NSOutlineView()
    private let userPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let filterField = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private var roots: [Node] = []
    private var tokens: [ObservationToken] = []
    private var lastConnection: UUID?
    private var lastGeneration = -1
    private var owner: String?          // nil — wszyscy użytkownicy
    private var ownerMode = 0           // 0 bieżący, 1 wszyscy, 2 wybrany

    /// Węzeł drzewa (klasa — NSOutlineView porównuje elementy przez tożsamość).
    final class Node {
        enum Kind {
            case folder(DBObjectType)
            case recent
            case userFolder(BrowserFolder)
            case object(DBObject)
            case group(DBObjectChild.Kind, [DBObjectChild])
            case child(DBObjectChild)
            case message(String)
        }
        let kind: Kind
        var children: [Node]?
        var loading = false
        init(_ kind: Kind, children: [Node]? = nil) { self.kind = kind; self.children = children }

        var object: DBObject? {
            switch kind {
            case .object(let o): o
            case .child(let c): c.object
            default: nil
            }
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
        column.title = L10n.tr("Obiekty")
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.allowsMultipleSelection = true
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.setAccessibilityLabel(L10n.tr("Object Browser"))
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        userPopup.controlSize = .small
        userPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        userPopup.target = self
        userPopup.action = #selector(userChanged)
        filterField.controlSize = .small
        filterField.placeholderString = L10n.tr("Filtr: nazwa%, status=invalid, source=tekst")
        filterField.target = self
        filterField.action = #selector(filterChanged)
        filterField.sendsWholeSearchString = true
        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: L10n.tr("Odśwież"))!,
                               target: self, action: #selector(refreshAll))
        refresh.isBordered = false
        refresh.toolTip = L10n.tr("Odśwież Object Browser")
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        let root = NSView()
        for v in [userPopup, refresh, filterField, scroll, status] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            userPopup.topAnchor.constraint(equalTo: root.topAnchor),
            userPopup.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            refresh.centerYAnchor.constraint(equalTo: userPopup.centerYAnchor),
            refresh.leadingAnchor.constraint(equalTo: userPopup.trailingAnchor, constant: 4),
            refresh.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            refresh.widthAnchor.constraint(equalToConstant: 18),
            filterField.topAnchor.constraint(equalTo: userPopup.bottomAnchor, constant: 4),
            filterField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            filterField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 2),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            status.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -6),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
        ])
        userPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view = root
        tokens.append(trackChanges { [weak self] in self?.modelChanged() })
    }

    private func modelChanged() {
        let conn = workspace.sessions.mainConnectionID
        let generation = workspace.metadata()?.generation ?? 0
        _ = workspace.metadata()?.recent.count
        if conn != lastConnection {
            lastConnection = conn
            owner = nil
            ownerMode = 0
            lastGeneration = generation
            Task { await reloadAll(users: true) }
        } else if generation != lastGeneration {
            lastGeneration = generation
            Task { await reloadAll(users: false) }
        }
    }

    // MARK: Ładowanie

    private func reloadAll(users: Bool) async {
        guard let m = workspace.metadata() else {
            roots = [Node(.message(L10n.tr("Zaloguj się, aby przeglądać obiekty")))]
            userPopup.removeAllItems()
            outline.reloadData()
            return
        }
        do {
            let types = try await m.availableTypes()
            if users { try await loadUsers(m) }
            if ownerMode == 0 { owner = try await m.currentSchema() }
            // Filtr domyślny dla użytkownika (PD-OB-007) — przy pierwszym wczytaniu połączenia.
            if users, workspace.browserFilter == nil, let user = try? await m.currentSchema(),
               let f = workspace.browserCustomization.defaultFilter(user: user) { workspace.browserFilter = f }
            // Foldery użytkownika widoczne dla połączenia (PD-OB-008) i foldery typów wg preferencji (PD-OB-025).
            let def = workspace.sessions.mainConnectionID.flatMap { workspace.connections.connection($0) }
            let userFolders = workspace.browserCustomization.folders.filter { $0.parentID == nil && $0.visible(for: def) }
            roots = [Node(.recent)] + userFolders.map { Node(.userFolder($0)) } + workspace.browserFolderTypes(available: types).map { Node(.folder($0)) }
            outline.reloadData()
            status.stringValue = ""
        } catch {
            roots = [Node(.message(error.localizedDescription))]
            outline.reloadData()
        }
    }

    private func loadUsers(_ m: MetadataProvider) async throws {
        let current = try await m.currentSchema()
        let list = try await m.users()
        userPopup.removeAllItems()
        userPopup.addItem(withTitle: L10n.tr("<Bieżący użytkownik> \(current)"))
        userPopup.addItem(withTitle: L10n.tr("<Wszyscy użytkownicy>"))
        userPopup.menu?.addItem(.separator())
        for u in list { userPopup.addItem(withTitle: u) }
        userPopup.selectItem(at: 0)
    }

    private func load(_ node: Node) {
        guard node.children == nil, !node.loading, let m = workspace.metadata() else { return }
        node.loading = true
        let filter = ObjectFilter(filterField.stringValue, named: workspace.browserFilter)
        let owner = self.owner
        Task {
            defer { node.loading = false }
            do {
                switch node.kind {
                case .folder(let t):
                    let objects = try await m.objects(t, owner: t.isGlobal ? nil : owner, filter: filter)
                    node.children = objects.isEmpty ? [Node(.message(L10n.tr("(brak)")))] : objects.map { Node(.object($0)) }
                    status.stringValue = L10n.tr("\(t.folderName): \(objects.count)")
                case .recent:
                    node.children = m.recent.map { Node(.object($0)) }
                case .userFolder(let f):
                    let subfolders = workspace.browserCustomization.folders.filter { $0.parentID == f.id }.map { Node(.userFolder($0)) }
                    let objects = try await m.objects(in: f).map { Node(.object($0)) }
                    node.children = subfolders + objects
                    if node.children?.isEmpty == true { node.children = [Node(.message(L10n.tr("(brak)")))] }
                case .object(let o):
                    let items = try await m.children(of: o)
                    let order: [DBObjectChild.Kind] = [.column, .attribute, .subprogram, .index, .constraint, .trigger, .usage, .dependency, .referencedBy]
                    node.children = order.compactMap { k in
                        let list = items.filter { $0.kind == k }
                        return list.isEmpty ? nil : Node(.group(k, list), children: list.map { Node(.child($0)) })
                    }
                    if node.children?.isEmpty == true { node.children = [Node(.message(L10n.tr("(brak elementów)")))] }
                default:
                    node.children = []
                }
            } catch {
                node.children = [Node(.message(error.localizedDescription))]
            }
            outline.reloadItem(node, reloadChildren: true)
            if outline.isItemExpanded(node) == false { outline.expandItem(node) }
        }
    }

    @objc private func userChanged() {
        let i = userPopup.indexOfSelectedItem
        switch i {
        case 0: ownerMode = 0
        case 1: ownerMode = 1; owner = nil
        default: ownerMode = 2; owner = userPopup.titleOfSelectedItem
        }
        Task { await reloadAll(users: false) }
    }

    @objc private func filterChanged() { Task { await reloadAll(users: false) } }

    @objc private func refreshAll() { workspace.perform("ob.refresh") }

    // MARK: Źródło danych

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let n = item as? Node else { return roots.count }
        return n.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let n = item as? Node else { return roots[index] }
        return n.children![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let n = item as? Node else { return false }
        switch n.kind {
        case .folder, .recent, .group, .userFolder: return true
        case .object(let o): return !o.type.isGlobal
        default: return false
        }
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        if let n = notification.userInfo?["NSObject"] as? Node { load(n) }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? Node else { return nil }
        let cell = outlineView.makeView(withIdentifier: .init("cell"), owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = .init("cell")
            let image = NSImageView()
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            c.imageView = image
            c.textField = text
            for v in [image, text] {
                v.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(v)
            }
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: c.leadingAnchor),
                image.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
                text.trailingAnchor.constraint(equalTo: c.trailingAnchor),
                text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        var title = ""
        var symbol = "folder"
        var color: NSColor = .secondaryLabelColor
        var textColor: NSColor = .labelColor
        switch n.kind {
        case .folder(let t): title = t.folderName
        case .recent: title = L10n.tr("Ostatnie"); symbol = "clock"
        case .userFolder(let f):
            title = f.name
            symbol = "folder.fill"
            color = f.color.flatMap(Self.namedColor) ?? .systemBlue
        case .object(let o):
            title = ownerMode == 0 || o.type.isGlobal ? o.name : "\(o.owner).\(o.name)"
            symbol = Self.symbol(o.type)
            color = o.isValid ? Self.color(o.type) : .systemRed
            if !o.isValid { textColor = .systemRed }
        case .group(let k, let items): title = "\(Self.groupName(k)) (\(items.count))"; symbol = "folder"
        case .child(let c):
            title = c.detail.isEmpty ? c.name : "\(c.name)  \(c.detail)"
            symbol = Self.childSymbol(c.kind)
        case .message(let m): title = m; symbol = "info.circle"; textColor = .secondaryLabelColor
        }
        cell.textField?.stringValue = title
        // Własne kolory Object Browsera (PD-PREF-005): tekst zwykłych pozycji i tło listy.
        let colors = workspace.settings.browserColors
        if textColor == .labelColor, let c = colors.text { textColor = NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1) }
        let background = colors.background.map { NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
        if outline.backgroundColor != background ?? .clear {
            outline.backgroundColor = background ?? .clear
            outline.enclosingScrollView?.drawsBackground = background != nil
        }
        cell.textField?.textColor = textColor
        let size = workspace.settings.browserFontSize
        cell.textField?.font = .systemFont(ofSize: size > 0 ? size : NSFont.smallSystemFontSize + 1)
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = color
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        // Wiele obiektów (PD-OB-011): wszystkie zaznaczone obiekty; bieżący — kliknięty albo pierwszy.
        let objs = outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? Node)?.object }
        workspace.selectedObjects = objs
        let clicked = outline.clickedRow >= 0 ? (outline.item(atRow: outline.clickedRow) as? Node)?.object : nil
        workspace.selectedObject = clicked.flatMap { c in objs.contains(c) ? c : nil } ?? objs.first
            ?? (outline.item(atRow: outline.selectedRow) as? Node)?.object
    }

    /// Cmd+C: nazwy zaznaczonych obiektów po przecinku.
    @objc func copy(_ sender: Any?) {
        workspace.perform("ob.copyNames")
    }

    /// Typ schowka z obiektem (właściciel, nazwa, typ) — upuszczenie z Option generuje kod (SD-GEN-001).
    static let objectPasteboardType = NSPasteboard.PasteboardType("local.pelikan.dbobject")

    /// Przeciąganie obiektu do edytora wstawia nazwę (UG 21.1); z klawiszem Option — kod (SELECT albo wywołanie).
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let n = item as? Node else { return nil }
        switch n.kind {
        case .object(let o):
            let p = NSPasteboardItem()
            p.setString(o.name.lowercased(), forType: .string)
            p.setString([o.owner, o.name, o.type.rawValue].joined(separator: "\u{1}"), forType: Self.objectPasteboardType)
            return p
        case .child(let c): return c.name.lowercased() as NSString
        case .group(_, let items):
            // Folder elementów (np. Kolumny) → nazwy po przecinku (UG 21.1).
            return BrowserDrop.namesList(items.map(\.name)) as NSString
        case .folder, .userFolder:
            let names = (n.children ?? []).compactMap(\.object).map(\.name)
            return names.isEmpty ? nil : BrowserDrop.namesList(names) as NSString
        default: return nil
        }
    }

    @objc private func doubleClicked() {
        guard let n = outline.item(atRow: outline.clickedRow) as? Node else { return }
        if let o = n.object, o.type.isProgram || workspace.settings.browserDoubleClick[o.type.rawValue] != nil {
            // Akcja dwukliku według typu z Preferencji (PD-OB-025); domyślnie Edytuj dla programów.
            workspace.selectedObject = o
            workspace.perform(workspace.browserDoubleClickCommand(for: o.type))
        } else if outline.isExpandable(n) {
            outline.isItemExpanded(n) ? outline.collapseItem(n) : outline.expandItem(n)
        }
    }

    // MARK: Menu kontekstowe

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outline.clickedRow
        // Kliknięcie w zaznaczenie wielu obiektów: menu akcji wspólnych (PD-OB-011).
        if row >= 0, outline.selectedRowIndexes.contains(row), workspace.selectedObjects.count > 1 {
            for id in ["ob.copyNames", "ob.ddlSelected", "-", "ob.recompileSelected", "ob.dropSelected"] {
                if id == "-" { menu.addItem(.separator()); continue }
                guard let c = workspace.registry.command(CommandID(rawValue: id)) else { continue }
                let item = menu.addItem(withTitle: c.descriptor.title, action: #selector(runCommand(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
            }
            return
        }
        if row >= 0, let n = outline.item(atRow: row) as? Node {
            workspace.selectedObject = n.object
            outline.selectRowIndexes([row], byExtendingSelection: false)
            // Kolumna albo więz tabeli: zmiana nazwy elementu (PD-OB-016).
            if case .child(let c) = n.kind, [.column, .constraint].contains(c.kind), let table = parentObject(of: n), table.type == .table {
                let item = ClosureMenuItem(title: L10n.tr("Zmień nazwę elementu…")) { [weak self] in
                    self?.workspace.perform("ob.renameChild", CommandArguments(["object": .string("\"\(table.owner)\".\"\(table.name)\""), "type": "TABLE",
                                                                                "kind": .string(c.kind.rawValue), "name": .string(c.name)]))
                }
                menu.addItem(item)
                if n.object == nil { return }
                menu.addItem(.separator())
            }
        }
        guard workspace.selectedObject != nil else {
            menu.addItem(withTitle: L10n.tr("Odśwież"), action: #selector(refreshAll), keyEquivalent: "").target = self
            return
        }
        // Pozycje niedostępne dla typu obiektu (np. Włącz/Wyłącz poza wyzwalaczami i tabelami) są pomijane, nie wyszarzane.
        let optional: Set<String> = ["ob.enable", "ob.disable", "ob.ccflags", "ob.test", "ob.standardTest", "ob.addSourceToEditor", "ob.rename",
                                     "ob.duplicate", "ob.utplsqlRun", "ob.addDebugInfo", "ob.refreshMV", "ob.testLink", "ob.runJob",
                                     "ob.startQueue", "ob.stopQueue", "ob.compare"]
        for id in ["ob.queryData", "ob.editData", "-", "ob.edit", "ob.ddl", "ob.describe", "ob.properties", "-", "ob.test", "ob.standardTest",
                   "ob.utplsqlRun", "ob.addSourceToEditor", "-", "ob.recompile", "ob.addDebugInfo", "ob.refreshMV", "ob.testLink", "ob.runJob",
                   "ob.startQueue", "ob.stopQueue", "ob.enable", "ob.disable", "ob.ccflags", "ob.rename", "ob.duplicate", "ob.drop",
                   "-", "ob.compare", "ob.compareWithConnection", "ob.addToFolder", "-", "ob.copyName", "ob.refresh"] {
            if optional.contains(id), !workspace.isEnabled(CommandID(rawValue: id)) { continue }
            if id == "ob.copyName", let o = workspace.selectedObject, let gen = generateCodeMenu(o) { menu.addItem(gen) }
            if id == "-" { menu.addItem(.separator()); continue }
            guard let c = workspace.registry.command(CommandID(rawValue: id)) else { continue }
            let item = menu.addItem(withTitle: c.descriptor.title, action: #selector(runCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.isEnabled = workspace.isEnabled(CommandID(rawValue: id))
            // Zapytania standardowe tabel i widoków (UG 7.14) zaraz po „Pokaż dane”.
            if id == "ob.queryData", let o = workspace.selectedObject, [.table, .view, .materializedView].contains(o.type) {
                let sub = NSMenu()
                for q in workspace.settings.standardQueries {
                    let si = sub.addItem(withTitle: q.name, action: #selector(runStandardQuery(_:)), keyEquivalent: "")
                    si.target = self
                    si.representedObject = q.name
                }
                menu.addItem(withTitle: L10n.tr("Zapytania standardowe"), action: nil, keyEquivalent: "").submenu = sub
            }
        }
    }

    /// Generowanie kodu z obiektu (SD-GEN-001): SQL dla tabel i widoków, wywołanie dla procedur i funkcji.
    private func generateCodeMenu(_ o: DBObject) -> NSMenuItem? {
        let kinds: [CodeGenerator.Kind]
        switch o.type {
        case .table, .view, .materializedView, .synonym: kinds = CodeGenerator.Kind.allCases.filter { $0 != .call }
        case .procedure, .function: kinds = [.call]
        default: return nil
        }
        let sub = NSMenu()
        for k in kinds {
            let item = sub.addItem(withTitle: k.displayName, action: #selector(generateCode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = k.rawValue
        }
        let item = NSMenuItem(title: L10n.tr("Generuj kod"), action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }

    @objc private func generateCode(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? String, let o = workspace.selectedObject else { return }
        workspace.perform("ob.generateCode", CommandArguments(["object": .string("\"\(o.owner)\".\"\(o.name)\""), "type": .string(o.type.rawValue),
                                                              "kind": .string(kind)]))
    }

    @objc private func runStandardQuery(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let o = workspace.selectedObject else { return }
        workspace.perform("ob.standardQuery", CommandArguments(["object": .string("\"\(o.owner)\".\"\(o.name)\""), "type": .string(o.type.rawValue), "name": .string(name)]))
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        workspace.perform(CommandID(rawValue: id))
    }

    /// Obiekt nadrzędny elementu drzewa (element → grupa → obiekt).
    private func parentObject(of node: Node) -> DBObject? {
        var item: Any? = outline.parent(forItem: node)
        while let n = item as? Node {
            if case .object(let o) = n.kind { return o }
            item = outline.parent(forItem: n)
        }
        return nil
    }

    // MARK: Wygląd

    static func namedColor(_ name: String) -> NSColor? {
        ["red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow, "green": .systemGreen, "blue": .systemBlue,
         "purple": .systemPurple, "gray": .systemGray][name.lowercased()]
    }

    static func symbol(_ t: DBObjectType) -> String {
        switch t {
        case .table: "tablecells"
        case .view, .materializedView: "eye"
        case .sequence: "number"
        case .synonym: "arrowshape.turn.up.right"
        case .package, .packageBody: "shippingbox"
        case .function: "function"
        case .procedure: "gearshape"
        case .type, .typeBody: "cube"
        case .trigger: "bolt"
        case .index: "list.number"
        case .user: "person"
        case .role: "person.2"
        case .databaseLink: "link"
        case .mleModule, .mleEnvironment: "curlybraces"
        case .domain: "checkmark.seal"
        case .annotation: "tag"
        case .assertion: "checkmark.shield"
        default: "doc"
        }
    }

    static func color(_ t: DBObjectType) -> NSColor {
        switch t {
        case .table, .view, .materializedView: .systemBlue
        case .package, .packageBody, .function, .procedure, .type, .typeBody: .systemOrange
        case .trigger: .systemYellow
        case .mleModule, .mleEnvironment: .systemPurple
        default: .secondaryLabelColor
        }
    }

    static func groupName(_ k: DBObjectChild.Kind) -> String {
        switch k {
        case .column: L10n.tr("Kolumny")
        case .index: L10n.tr("Indeksy")
        case .constraint: L10n.tr("Więzy")
        case .trigger: L10n.tr("Wyzwalacze")
        case .subprogram: L10n.tr("Podprogramy")
        case .attribute: L10n.tr("Atrybuty")
        case .dependency: L10n.tr("Zależy od")
        case .referencedBy: L10n.tr("Używany przez")
        case .partition: L10n.tr("Partycje")
        case .usage: L10n.tr("Użycie")
        }
    }

    static func childSymbol(_ k: DBObjectChild.Kind) -> String {
        switch k {
        case .column, .attribute: "minus"
        case .index: "list.number"
        case .constraint: "key"
        case .trigger: "bolt"
        case .subprogram: "function"
        case .dependency: "arrow.right"
        case .referencedBy: "arrow.left"
        case .partition: "square.split.2x1"
        case .usage: "tag"
        }
    }
}

/// Okno informacji o obiekcie (Opis, Właściwości): tabela, kopiowanie zaznaczenia, niemodalne.
final class ObjectInfoWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let rows: [[String]]
    private let table = NSTableView()
    private static var open: [ObjectInfoWindowController] = []

    static func show(title: String, columns: [String], rows: [[String]]) {
        let c = ObjectInfoWindowController(title: title, columns: columns, rows: rows)
        open.append(c)
        c.showWindow(nil)
    }

    init(title: String, columns: [String], rows: [[String]]) {
        self.rows = rows
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420), styleMask: [.titled, .closable, .resizable, .utilityWindow],
                         backing: .buffered, defer: false)
        w.title = title
        super.init(window: w)
        table.setAccessibilityLabel(title)
        for (i, name) in columns.enumerated() {
            let c = NSTableColumn(identifier: .init("c\(i)"))
            c.title = name
            c.width = i == 0 ? 200 : 320
            table.addTableColumn(c)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        w.contentView = scroll
        w.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { Self.open.removeAll { $0 === self } }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue, let i = Int(id.dropFirst()) else { return nil }
        let tf = NSTextField(labelWithString: i < rows[row].count ? rows[row][i] : "")
        tf.isSelectable = true
        tf.font = i == 0 ? .systemFont(ofSize: 12, weight: .medium) : .monospacedSystemFont(ofSize: 12, weight: .regular)
        tf.lineBreakMode = .byTruncatingTail
        return tf
    }

    @objc func copy(_ sender: Any?) {
        let sel = table.selectedRowIndexes.isEmpty ? IndexSet(integersIn: 0..<rows.count) : table.selectedRowIndexes
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sel.map { rows[$0].joined(separator: "\t") }.joined(separator: "\n"), forType: .string)
    }
}
