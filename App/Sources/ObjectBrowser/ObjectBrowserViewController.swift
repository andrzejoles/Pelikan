import AppKit
import PelikanDB
import PelikanWorkspace

/// Object Browser (UG 21, PD-OB-001, D185): jak w DBeaverze — na najwyższym poziomie otwarte połączenia (główne
/// pierwsze i wyróżnione), pod każdym foldery typów, Ostatnie i foldery użytkownika; elementy obiektu (kolumny, indeksy,
/// więzy, wyzwalacze, podprogramy, zależności), menu kontekstowe z komend `ob.*` na połączeniu gałęzi. Rozłączone
/// połączenie znika z drzewa. Wybór użytkownika dotyczy połączenia zaznaczonej gałęzi, filtr — wszystkich.
final class ObjectBrowserViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let workspace: Workspace
    private let outline = NSOutlineView()
    private let userPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let filterField = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private var roots: [Node] = []
    private var tokens: [ObservationToken] = []
    /// Stan gałęzi połączeń (użytkownik, lista użytkowników, generacja metadanych) — trwa, dopóki połączenie jest otwarte.
    private var branches: [UUID: Branch] = [:]
    private var lastMain: UUID?
    /// Zawartość listy użytkowników (gałąź, bieżący, lista) — pozycje przebudowywane tylko po jej zmianie.
    private var popupSignature: (branch: ObjectIdentifier, current: String, list: [String])?
    /// Zaznaczenie ustawiane przy przywracaniu stanu gałęzi (nie jest wyborem użytkownika).
    private var restoringSelection = false

    /// Węzeł drzewa (klasa — NSOutlineView porównuje elementy przez tożsamość). `connection` — połączenie gałęzi.
    final class Node {
        enum Kind {
            case connection
            case folder(DBObjectType)
            case recent
            case userFolder(BrowserFolder)
            /// Folder DBA albo DBMS na końcu gałęzi (obiekty z przedrostkiem, do których użytkownik ma uprawnienia).
            case systemFolder(SystemObjectFolder)
            case object(DBObject)
            case group(DBObjectChild.Kind, [DBObjectChild])
            case child(DBObjectChild)
            case message(String)
        }
        let kind: Kind
        let connection: UUID
        var children: [Node]?
        var loading = false
        init(_ kind: Kind, connection: UUID, children: [Node]? = nil) { self.kind = kind; self.connection = connection; self.children = children }

        var object: DBObject? {
            switch kind {
            case .object(let o): o
            case .child(let c): c.object
            default: nil
            }
        }
    }

    /// Gałąź połączenia: węzeł, wybór użytkownika i stan wczytania (osobno dla każdego połączenia).
    final class Branch {
        let node: Node
        var owner: String?          // schemat bieżący (tryb 0) albo wybrany (3)
        var ownerMode = 0           // 0 bieżący, 1 dostępne, 2 wszyscy, 3 wybrany (D187)

        /// Zakres folderów gałęzi (D187).
        var scope: ObjectScope {
            switch ownerMode {
            case 0: owner.map(ObjectScope.mine) ?? .accessible
            case 1: .accessible
            case 2: .all
            default: owner.map(ObjectScope.user) ?? .all
            }
        }
        var users: (current: String, list: [String])?
        var generation = -1
        var recent: [DBObject] = []
        /// Numer przeładowania: wynik starszego (np. wolniejszej bazy) nie nadpisuje gałęzi ani listy użytkowników (R4-21).
        var reloadGeneration = 0
        /// Lista użytkowników do wczytania — także gdy przeładowanie z nią zastąpi nowsze bez niej.
        var usersPending = false
        /// Przeładowania zlecone, a niezakończone — rozwinięcie gałęzi nie zleca wtedy kolejnego.
        var reloadsInFlight = 0
        /// Ścieżki rozwiniętych węzłów i zaznaczone obiekty (id) sprzed przebudowy gałęzi — przywracane, gdy foldery
        /// wczytają się od nowa (po kompilacji, Zastosuj, Odśwież); każda pozycja jednorazowo.
        var restoreExpanded: Set<String> = []
        var restoreSelection: Set<String> = []
        init(_ connection: UUID) { node = Node(.connection, connection: connection) }
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
        // Drzewo z wyraźnym wcięciem poziomów (styl listy paska bocznego macOS prawie nie wcina dzieci).
        outline.style = .plain
        outline.indentationPerLevel = 16
        // Wysokość wiersza z czcionki drzewa (przy stylu innym niż `.custom` AppKit ignoruje `rowHeight`).
        outline.rowSizeStyle = .custom
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.allowsMultipleSelection = true
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.setAccessibilityLabel(L10n.tr("Przeglądarka obiektów"))
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        userPopup.controlSize = .small
        userPopup.font = InterfaceFonts.shared.small
        userPopup.target = self
        userPopup.action = #selector(userChanged)
        userPopup.toolTip = L10n.tr("Użytkownik w gałęzi zaznaczonego połączenia")
        filterField.controlSize = .small
        filterField.placeholderString = L10n.tr("Filtr: część nazwy, NAZWA%, status=invalid, source=tekst")
        filterField.target = self
        filterField.action = #selector(filterChanged)
        filterField.sendsWholeSearchString = true
        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: L10n.tr("Odśwież"))!,
                               target: self, action: #selector(refreshAll))
        refresh.isBordered = false
        refresh.toolTip = L10n.tr("Odśwież Przeglądarkę obiektów")
        status.font = InterfaceFonts.shared.small
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
        // Czcionka Object Browsera albo interfejsu z Preferencji (D178): wysokość wierszy i ponowne narysowanie drzewa.
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            let font = self.browserFont
            self.outline.rowHeight = AppFonts.rowHeight(for: font)
            self.outline.reloadData()
        })
    }

    /// Czcionka drzewa: własna z Preferencji › Edytor albo czcionka interfejsu o 1 pt mniejsza.
    var browserFont: NSFont {
        let s = workspace.settings, ui = InterfaceFonts.shared
        return AppFonts.font(family: s.browserFontName.isEmpty ? ui.family : s.browserFontName,
                             size: s.browserFontSize > 0 ? s.browserFontSize : AppFonts.reduced(ui.size, by: 1), weight: s.browserFontWeight)
    }

    /// Otwarte połączenia w kolejności drzewa: alfabetycznie, jak na liście połączeń (główne wyróżnia ★ i pogrubienie).
    private var orderedConnections: [UUID] {
        // Bez połączeń, których definicji już nie ma (np. tymczasowe okna poleceń po DISCONNECT).
        workspace.sessions.openConnections.compactMap { workspace.connections.connection($0) }
            .sorted(by: ConnectionStore.alphabetical).map(\.id)
    }

    private func modelChanged() {
        let ids = orderedConnections
        let main = workspace.sessions.mainConnectionID
        // Odczyt śledzony: generacja i Ostatnie każdego otwartego połączenia.
        let state = ids.map { id in (id, workspace.metadata(for: id)?.generation ?? 0, workspace.metadata(for: id)?.recent ?? []) }
        _ = workspace.connections.connections.count   // zmiana nazwy albo koloru połączenia — przerysowanie gałęzi
        // Drzewo przebudowywane po bieżącym obiegu pętli: pierwsze wywołanie przychodzi z loadView, zanim widok ma
        // szerokość — reloadData i rozwinięcie wtedy zostawiały kolumnę wąską (obcięte nazwy).
        Task { @MainActor [weak self] in self?.apply(ids: ids, main: main, state: state) }
    }

    private func apply(ids: [UUID], main: UUID?, state: [(UUID, Int, [DBObject])]) {
        // Sama zmiana „Ostatnich” (otwarcie obiektu) — przeładowany niżej tylko ten folder, bez całego drzewa.
        let onlyRecent = state.allSatisfy { id, generation, _ in branches[id]?.generation == generation }
            && state.contains { id, _, recent in branches[id]?.recent != recent }
        if ids != roots.map(\.connection) || main != lastMain {
            rebuildRoots(ids, main: main)
        } else if !onlyRecent {
            outline.reloadData()
        }
        for (id, generation, recent) in state {
            guard let b = branches[id] else { continue }
            if b.generation != generation {
                let first = b.generation < 0
                b.generation = generation
                startReload(b, users: first)
            } else if recent != b.recent, let node = b.node.children?.first(where: { if case .recent = $0.kind { true } else { false } }),
                      node.children != nil {
                // Folder „Ostatnie” już wczytany — `touch` nie zmienia generacji, więc lista odświeżana tutaj.
                node.children = recent.map { Node(.object($0), connection: id) }
                outline.reloadItem(node, reloadChildren: true)
            }
            b.recent = recent
        }
        if roots.isEmpty { status.stringValue = L10n.tr("Zaloguj się, aby przeglądać obiekty") }
        refreshUserPopup()
    }

    /// Gałęzie otwartych połączeń; istniejące zachowują stan i rozwinięcie, nowe połączenie główne jest rozwinięte.
    private func rebuildRoots(_ ids: [UUID], main: UUID?) {
        let expanded = Set(roots.filter { outline.isItemExpanded($0) }.map(\.connection))
        for id in branches.keys where !ids.contains(id) { branches[id] = nil }
        let newMain = main != lastMain
        lastMain = main
        roots = ids.map { id in
            if let b = branches[id] { return b.node }
            let b = Branch(id)
            if workspace.settings.browserShowAccessible { b.ownerMode = 1 }
            branches[id] = b
            return b.node
        }
        if let selected = workspace.selectedObjectConnection, !ids.contains(selected) {
            workspace.selectedObject = nil
            workspace.selectedObjects = []
            workspace.selectedObjectConnection = nil
        }
        outline.reloadData()
        for node in roots where expanded.contains(node.connection) || (newMain && node.connection == main) || roots.count == 1 {
            outline.expandItem(node)
        }
    }

    // MARK: Ładowanie

    /// Gałąź połączenia zaznaczonego wiersza (bez zaznaczenia — połączenie główne).
    private var currentBranch: Branch? {
        let row = outline.selectedRow
        if row >= 0, let n = outline.item(atRow: row) as? Node, let b = branches[n.connection] { return b }
        return workspace.sessions.mainConnectionID.flatMap { branches[$0] } ?? roots.first.flatMap { branches[$0.connection] }
    }

    /// Przeładowanie gałęzi w tle, liczone w `reloadsInFlight` od chwili zlecenia.
    private func startReload(_ b: Branch, users: Bool) {
        b.reloadsInFlight += 1
        Task {
            await reload(b, users: users)
            b.reloadsInFlight -= 1
        }
    }

    private func reload(_ b: Branch, users: Bool) async {
        b.reloadGeneration += 1
        let generation = b.reloadGeneration
        if users { b.usersPending = true }
        func current() -> Bool { generation == b.reloadGeneration && branches[b.node.connection] === b }
        let id = b.node.connection
        guard let m = workspace.metadata(for: id) else { return }
        let withUsers = b.usersPending
        do {
            let types = try await m.availableTypes()
            let userList = withUsers ? try await (m.currentSchema(), m.users()) : nil
            let schema = b.ownerMode == 0 ? try await m.currentSchema() : nil
            guard current() else { return }
            if let userList { b.users = (userList.0, userList.1) }
            b.usersPending = false
            if let schema { b.owner = schema }
            // Filtr domyślny dla użytkownika (PD-OB-007) — przy pierwszym wczytaniu połączenia głównego (filtr dotyczy
            // wszystkich gałęzi, więc nie bierze go użytkownik innego połączenia).
            if withUsers, id == workspace.sessions.mainConnectionID, workspace.browserFilter == nil, let user = try? await m.currentSchema(),
               let f = workspace.browserCustomization.defaultFilter(user: user) { workspace.browserFilter = f }
            guard current() else { return }
            // Foldery użytkownika widoczne dla połączenia (PD-OB-008) i foldery typów wg preferencji (PD-OB-025).
            let def = workspace.connections.connection(id)
            let userFolders = workspace.browserCustomization.folders.filter { $0.parentID == nil && $0.visible(for: def) }
            rememberState(b)
            b.node.children = [Node(.recent, connection: id)] + userFolders.map { Node(.userFolder($0), connection: id) }
                + workspace.browserFolderTypes(available: types).map { Node(.folder($0), connection: id) }
                + SystemObjectFolder.allCases.map { Node(.systemFolder($0), connection: id) }
            outline.reloadItem(b.node, reloadChildren: true)
            if outline.isItemExpanded(b.node) { restoreState(b.node, path: Self.rootKey, b) }
            refreshUserPopup()
            status.stringValue = ""
        } catch {
            guard current() else { return }
            b.node.children = [Node(.message(error.localizedDescription), connection: id)]
            outline.reloadItem(b.node, reloadChildren: true)
        }
    }

    // MARK: Stan gałęzi po przebudowie (rozwinięcie, zaznaczenie)

    static let rootKey = "c"

    /// Klucz węzła w ścieżce rozwinięcia; nil — węzeł bez dzieci.
    static func key(_ n: Node) -> String? {
        switch n.kind {
        case .connection: rootKey
        case .folder(let t): "f:" + t.rawValue
        case .recent: "r"
        case .userFolder(let f): "u:" + f.id.uuidString
        case .systemFolder(let f): "s:" + f.rawValue
        case .object(let o): "o:" + o.id
        case .group(let k, _): "g:" + k.rawValue
        default: nil
        }
    }

    /// Ścieżka węzła od gałęzi połączenia (nil — węzeł spoza bieżącego drzewa, np. z poprzedniego wczytania).
    private func path(_ n: Node) -> String? {
        var parts: [String] = []
        var item: Node? = n
        while let i = item {
            guard let k = Self.key(i) else { return nil }
            parts.append(k)
            item = outline.parent(forItem: i) as? Node
            if item == nil, !roots.contains(where: { $0 === i }) { return nil }
        }
        return parts.reversed().joined(separator: "/")
    }

    /// Zapamiętuje rozwinięte węzły i zaznaczone obiekty gałęzi przed zastąpieniem jej folderów nowymi węzłami.
    private func rememberState(_ b: Branch) {
        guard outline.isItemExpanded(b.node) else { b.restoreExpanded = []; b.restoreSelection = []; return }
        func collect(_ n: Node, _ prefix: String) {
            for c in n.children ?? [] where outline.isItemExpanded(c) {
                guard let k = Self.key(c) else { continue }
                b.restoreExpanded.insert(prefix + "/" + k)
                collect(c, prefix + "/" + k)
            }
        }
        collect(b.node, Self.rootKey)
        for row in outline.selectedRowIndexes {
            if let n = outline.item(atRow: row) as? Node, n.connection == b.node.connection, case .object(let o) = n.kind { b.restoreSelection.insert(o.id) }
        }
    }

    /// Rozwija ponownie zapamiętane węzły pod `node` (niewczytane — po wczytaniu w `load`) i zaznacza zapamiętane obiekty.
    private func restoreState(_ node: Node, path prefix: String, _ b: Branch) {
        guard !b.restoreExpanded.isEmpty || !b.restoreSelection.isEmpty else { return }
        for c in node.children ?? [] {
            guard let k = Self.key(c), b.restoreExpanded.remove(prefix + "/" + k) != nil else { continue }
            outline.expandItem(c)
            if c.children != nil { restoreState(c, path: prefix + "/" + k, b) }
        }
        var rows = IndexSet()
        for c in node.children ?? [] {
            guard case .object(let o) = c.kind, b.restoreSelection.contains(o.id) else { continue }
            let row = outline.row(forItem: c)
            if row >= 0 { rows.insert(row); b.restoreSelection.remove(o.id) }
        }
        guard !rows.isEmpty else { return }
        restoringSelection = true
        outline.selectRowIndexes(rows, byExtendingSelection: true)
        restoringSelection = false
    }

    /// Lista użytkowników gałęzi zaznaczonego połączenia; pozycje (tysiące schematów) przebudowywane tylko po zmianie
    /// gałęzi albo listy, przy zmianie zaznaczenia — sam wybór pozycji.
    private func refreshUserPopup() {
        guard let b = currentBranch, let users = b.users else {
            popupSignature = nil
            userPopup.removeAllItems()
            userPopup.isEnabled = false
            return
        }
        userPopup.isEnabled = true
        if popupSignature?.branch != ObjectIdentifier(b) || popupSignature?.current != users.current || popupSignature?.list != users.list {
            userPopup.removeAllItems()
            userPopup.addItem(withTitle: L10n.tr("<Bieżący użytkownik> \(users.current)"))
            userPopup.addItem(withTitle: L10n.tr("<Dostępne obiekty>"))
            userPopup.addItem(withTitle: L10n.tr("<Wszyscy użytkownicy>"))
            userPopup.menu?.addItem(.separator())
            for u in users.list { userPopup.addItem(withTitle: u) }
            popupSignature = (ObjectIdentifier(b), users.current, users.list)
        }
        switch b.ownerMode {
        case 0, 1, 2: userPopup.selectItem(at: b.ownerMode)
        default: userPopup.selectItem(withTitle: b.owner ?? "")
        }
    }

    private func load(_ node: Node) {
        guard node.children == nil, !node.loading, let m = workspace.metadata(for: node.connection) else { return }
        let id = node.connection
        if case .connection = node.kind {
            // Pierwsze wczytanie (generacja jeszcze nieustalona) zleca `apply`; trwające przeładowanie — bez drugiego.
            if let b = branches[id], b.generation >= 0, b.reloadsInFlight == 0 { startReload(b, users: b.users == nil) }
            return
        }
        node.loading = true
        let filter = ObjectFilter(filterField.stringValue, named: workspace.browserFilter, contains: workspace.settings.browserFilterContains)
        let scope = branches[id]?.scope ?? .accessible
        Task {
            defer { node.loading = false }
            do {
                switch node.kind {
                case .folder(let t):
                    let objects = try await m.objects(t, scope: scope, filter: filter)
                    node.children = objects.isEmpty ? [Node(.message(L10n.tr("(brak)")), connection: id)] : objects.map { Node(.object($0), connection: id) }
                    status.stringValue = L10n.tr("\(t.folderName): \(objects.count)")
                case .recent:
                    node.children = m.recent.map { Node(.object($0), connection: id) }
                case .systemFolder(let f):
                    let objects = try await m.systemObjects(f, filter: filter)
                    node.children = objects.isEmpty ? [Node(.message(L10n.tr("(brak)")), connection: id)] : objects.map { Node(.object($0), connection: id) }
                    status.stringValue = L10n.tr("\(f.rawValue): \(objects.count)")
                case .userFolder(let f):
                    let subfolders = workspace.browserCustomization.folders.filter { $0.parentID == f.id }.map { Node(.userFolder($0), connection: id) }
                    let objects = try await m.objects(in: f).map { Node(.object($0), connection: id) }
                    node.children = subfolders + objects
                    if node.children?.isEmpty == true { node.children = [Node(.message(L10n.tr("(brak)")), connection: id)] }
                case .object(let o):
                    let items = try await m.children(of: o)
                    let order: [DBObjectChild.Kind] = [.column, .attribute, .subprogram, .index, .constraint, .trigger, .usage, .dependency, .referencedBy]
                    node.children = order.compactMap { k in
                        let list = items.filter { $0.kind == k }
                        return list.isEmpty ? nil : Node(.group(k, list), connection: id, children: list.map { Node(.child($0), connection: id) })
                    }
                    if node.children?.isEmpty == true { node.children = [Node(.message(L10n.tr("(brak elementów)")), connection: id)] }
                default:
                    node.children = []
                }
            } catch {
                node.children = [Node(.message(error.localizedDescription), connection: id)]
            }
            outline.reloadItem(node, reloadChildren: true)
            if outline.isItemExpanded(node) == false { outline.expandItem(node) }
            if let b = branches[id], let p = path(node) { restoreState(node, path: p, b) }
        }
    }

    @objc private func userChanged() {
        guard let b = currentBranch else { return }
        let i = userPopup.indexOfSelectedItem
        switch i {
        case 0: b.ownerMode = 0
        case 1: b.ownerMode = 1; b.owner = nil
        case 2: b.ownerMode = 2; b.owner = nil
        default: b.ownerMode = 3; b.owner = userPopup.titleOfSelectedItem
        }
        startReload(b, users: false)
    }

    @objc private func filterChanged() {
        for b in branches.values { startReload(b, users: false) }
    }

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
        case .connection, .folder, .recent, .group, .userFolder, .systemFolder: return true
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
        var font = browserFont
        // Bez właściciela obiekty własnego schematu w każdym trybie (D187; publiczne łącza i synonimy, obiekty innych
        // schematów — z właścicielem).
        let ownSchema = branches[n.connection].flatMap { $0.users?.current ?? ($0.ownerMode == 0 ? $0.owner : nil) }
        switch n.kind {
        case .connection:
            // Połączenie główne wyróżnione: gwiazdka, pogrubienie, dopisek; kolor połączenia albo środowiska.
            let def = workspace.connections.connection(n.connection)
            let isMain = n.connection == workspace.sessions.mainConnectionID
            title = (def?.displayName ?? "?") + (def.map { $0.environment != .other ? " (\($0.environment.shortName))" : "" } ?? "")
            if isMain { title = "★ " + title + " — " + L10n.tr("główne") }
            symbol = "cylinder.split.1x2"
            color = workspace.indicatorColor(forConnection: n.connection).map { NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } ?? .systemGray
            font = AppFonts.font(family: font.familyName ?? "", size: font.pointSize, weight: isMain ? .bold : .semibold)
            cell.setAccessibilityLabel(isMain ? L10n.tr("Połączenie główne: \(def?.displayName ?? "")") : L10n.tr("Połączenie: \(def?.displayName ?? "")"))
        case .folder(let t): title = t.folderName
        case .recent: title = L10n.tr("Ostatnie"); symbol = "clock"
        case .systemFolder(let f):
            title = f.rawValue
            symbol = "folder.badge.gearshape"
            color = .systemTeal
        case .userFolder(let f):
            title = f.name
            symbol = "folder.fill"
            color = f.color.flatMap(Self.namedColor) ?? .systemBlue
        case .object(let o):
            // W folderach DBA i DBMS bez „SYS.” przy każdej pozycji (inni właściciele, np. XDB — z nazwą schematu).
            let inSystemFolder = (outline.parent(forItem: n) as? Node).map { if case .systemFolder = $0.kind { true } else { false } } ?? false
            title = o.type.isGlobal || o.owner == ownSchema || (inSystemFolder && o.owner == "SYS") ? o.name : "\(o.owner).\(o.name)"
            symbol = ObjectSymbols.symbol(for: o.type)
            color = o.isValid ? Self.color(o.type) : .systemRed
            if !o.isValid { textColor = .systemRed }
        case .group(let k, let items): title = "\(Self.groupName(k)) (\(items.count))"; symbol = "folder"
        case .child(let c):
            title = c.detail.isEmpty ? c.name : "\(c.name)  \(c.detail)"
            symbol = Self.childSymbol(c.kind)
        case .message(let m): title = m; symbol = "info.circle"; textColor = .secondaryLabelColor
        }
        if case .connection = n.kind {} else { cell.setAccessibilityLabel(nil) }
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
        cell.textField?.font = font
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = color
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        // Wybór użytkownika kończy przywracanie zaznaczenia sprzed przebudowy gałęzi.
        if !restoringSelection, !outline.selectedRowIndexes.isEmpty { for b in branches.values { b.restoreSelection = [] } }
        // Wiele obiektów (PD-OB-011): zaznaczone obiekty połączenia bieżącego wiersza (kliknięty albo pierwszy) — komendy
        // działają na jednym połączeniu.
        let rows = outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? Node }
        let clickedNode = outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as? Node : nil
        let anchor = clickedNode.flatMap { c in rows.contains { $0 === c } ? c : nil } ?? rows.first
        let connection = anchor?.connection
        let objs = rows.filter { $0.connection == connection }.compactMap(\.object)
        workspace.selectedObjectConnection = connection
        workspace.selectedObjects = objs
        workspace.selectedObject = anchor?.object.flatMap { c in objs.contains(c) ? c : nil } ?? objs.first
        refreshUserPopup()
    }

    /// Argumenty komendy dla obiektu z drzewa: nazwa, typ i połączenie gałęzi.
    private func objectArguments(_ o: DBObject, connection: UUID?, _ extra: [String: JSONValue] = [:]) -> CommandArguments {
        var a: [String: JSONValue] = ["object": .string("\"\(o.owner)\".\"\(o.name)\""), "type": .string(o.type.rawValue)]
        if let connection { a["connection"] = .string(connection.uuidString) }
        for (k, v) in extra { a[k] = v }
        return CommandArguments(a)
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
            p.setString(BrowserObjectDrag(object: o, connection: n.connection).pasteboardString, forType: Self.objectPasteboardType)
            return p
        case .child(let c): return c.name.lowercased() as NSString
        case .group(_, let items):
            // Folder elementów (np. Kolumny) → nazwy po przecinku (UG 21.1).
            return BrowserDrop.namesList(items.map(\.name)) as NSString
        case .folder, .userFolder, .systemFolder:
            let names = (n.children ?? []).compactMap(\.object).map(\.name)
            return names.isEmpty ? nil : BrowserDrop.namesList(names) as NSString
        default: return nil
        }
    }

    @objc private func doubleClicked() {
        guard let n = outline.item(atRow: outline.clickedRow) as? Node else { return }
        if let o = n.object, o.type.isProgram || workspace.settings.browserDoubleClick[o.type.rawValue] != nil {
            // Akcja dwukliku według typu z Preferencji (PD-OB-025); domyślnie Edytuj dla programów — na połączeniu gałęzi.
            workspace.perform(workspace.browserDoubleClickCommand(for: o.type), objectArguments(o, connection: n.connection))
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
            outline.selectRowIndexes([row], byExtendingSelection: false)
            workspace.selectedObjectConnection = n.connection
            workspace.selectedObject = n.object
            workspace.selectedObjects = n.object.map { [$0] } ?? []
            if case .connection = n.kind {
                connectionMenu(menu, n.connection)
                return
            }
            // Kolumna albo więz tabeli: zmiana nazwy elementu (PD-OB-016).
            if case .child(let c) = n.kind, [.column, .constraint].contains(c.kind), let table = parentObject(of: n), table.type == .table {
                let item = ClosureMenuItem(title: L10n.tr("Zmień nazwę elementu…")) { [weak self] in
                    guard let self else { return }
                    self.workspace.perform("ob.renameChild", self.objectArguments(table, connection: n.connection,
                                                                                  ["kind": .string(c.kind.rawValue), "name": .string(c.name)]))
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
        workspace.perform("ob.generateCode", objectArguments(o, connection: workspace.selectedObjectConnection, ["kind": .string(kind)]))
    }

    @objc private func runStandardQuery(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let o = workspace.selectedObject else { return }
        workspace.perform("ob.standardQuery", objectArguments(o, connection: workspace.selectedObjectConnection, ["name": .string(name)]))
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        workspace.perform(CommandID(rawValue: id))
    }

    /// Menu gałęzi połączenia: główne, nowe okno, odświeżenie, rozłączenie, edycja definicji.
    private func connectionMenu(_ menu: NSMenu, _ id: UUID) {
        let arg = CommandArguments(["connection": .string(id.uuidString)])
        var entries: [(String, CommandID)] = []
        if id != workspace.sessions.mainConnectionID { entries.append((L10n.tr("Ustaw jako połączenie główne"), "connection.connectAsMain")) }
        entries += [(L10n.tr("Nowe okno SQL na tym połączeniu"), "connection.openWindow"), (L10n.tr("Odśwież"), "ob.refresh"),
                    (L10n.tr("Edytuj połączenie…"), "connection.edit"), (L10n.tr("Rozłącz"), "connection.disconnect")]
        for (title, command) in entries {
            if command == "connection.edit" || command == "connection.disconnect" { menu.addItem(.separator()) }
            menu.addItem(ClosureMenuItem(title: title) { [weak self] in self?.workspace.perform(command, arg) })
        }
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

/// Informacje o obiekcie (Opis, Właściwości): tabela, kopiowanie zaznaczenia; narzędzie w panelu albo oknie (D183).
final class ObjectInfoViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let rows: [[String]]
    private let table = NSTableView()

    static func show(title: String, columns: [String], rows: [[String]]) {
        let c = ObjectInfoViewController(title: title, columns: columns, rows: rows)
        ToolDockManager.shared.show(key: "objectInfo-" + UUID().uuidString, title: title, size: NSSize(width: 560, height: 420),
                                    content: c.view, owner: c)
    }

    init(title: String, columns: [String], rows: [[String]]) {
        self.rows = rows
        super.init(nibName: nil, bundle: nil)
        table.setAccessibilityLabel(title)
        for (i, name) in columns.enumerated() {
            let c = NSTableColumn(identifier: .init("c\(i)"))
            c.title = name
            c.width = i == 0 ? 200 : 320
            table.addTableColumn(c)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        // Wysokość wiersza z czcionki interfejsu i kodu (D178).
        table.rowSizeStyle = .custom
        table.rowHeight = max(AppFonts.rowHeight(for: InterfaceFonts.shared.body), AppFonts.rowHeight(for: InterfaceFonts.shared.code)) - 4
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        view = scroll
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue, let i = Int(id.dropFirst()) else { return nil }
        let tf = NSTextField(labelWithString: i < rows[row].count ? rows[row][i] : "")
        tf.isSelectable = true
        let fonts = InterfaceFonts.shared
        tf.font = i == 0 ? AppFonts.font(family: fonts.family, size: fonts.size, weight: .medium) : fonts.code
        tf.lineBreakMode = .byTruncatingTail
        return tf
    }

    @objc func copy(_ sender: Any?) {
        let sel = table.selectedRowIndexes.isEmpty ? IndexSet(integersIn: 0..<rows.count) : table.selectedRowIndexes
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sel.map { rows[$0].joined(separator: "\t") }.joined(separator: "\n"), forType: .string)
    }
}

/// Obiekt przeciągany z Object Browsera (schowek `objectPasteboardType`): właściciel, nazwa, typ i połączenie gałęzi
/// (D185; starszy format bez połączenia — trzy części).
struct BrowserObjectDrag {
    let owner: String
    let name: String
    let type: String
    let connection: String?

    init(object o: DBObject, connection: UUID) {
        owner = o.owner; name = o.name; type = o.type.rawValue; self.connection = connection.uuidString
    }

    init?(_ raw: String) {
        let p = raw.components(separatedBy: "\u{1}")
        guard p.count == 3 || p.count == 4 else { return nil }
        owner = p[0]; name = p[1]; type = p[2]; connection = p.count == 4 ? p[3] : nil
    }

    var pasteboardString: String { ([owner, name, type] + (connection.map { [$0] } ?? [])).joined(separator: "\u{1}") }

    /// Argumenty komendy obiektu (`object`, `type`, `connection`) z dodatkowymi.
    func arguments(_ extra: [String: JSONValue] = [:]) -> CommandArguments {
        var a: [String: JSONValue] = ["object": .string("\"\(owner)\".\"\(name)\""), "type": .string(type)]
        if let connection { a["connection"] = .string(connection) }
        for (k, v) in extra { a[k] = v }
        return CommandArguments(a)
    }
}
