import AppKit
import PelikanWorkspace

/// Wstążka okna głównego (PD-UI-012, D171): karty z grupami komend pod paskiem narzędzi, karty kontekstowe aktywnego
/// okna i pole „Szukaj czynności”. Układ kart i grup — `RibbonModel`, wyszukiwanie — `CommandSearch`.
@MainActor
final class RibbonController: NSTitlebarAccessoryViewController, NSSearchFieldDelegate {
    static let stripHeight: CGFloat = 30
    static let contentHeight: CGFloat = 104

    private let workspace: Workspace
    private let tabStack = NSStackView()
    private let groupStack = NSStackView()
    private let scroll = NSScrollView()
    private let search = NSSearchField()
    private let collapseButton = NSButton()
    private lazy var results = RibbonSearchResults(workspace: workspace) { [weak self] id in self?.run(id) }
    private var selection = RibbonSelection()
    private var selectedTab = "start"
    private var activeKind: DocumentKind?
    private var visibleTabs: [RibbonTab] = []
    private var buttons: [RibbonButton] = []
    private var tokens: [ObservationToken] = []
    private var updateObserver: (any NSObjectProtocol)?

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .bottom
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: Self.stripHeight + Self.contentHeight))
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.toolbar)
        root.setAccessibilityLabel(L10n.tr("Wstążka"))

        tabStack.orientation = .horizontal
        tabStack.spacing = 2
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        search.placeholderString = L10n.tr("Szukaj czynności…")
        search.toolTip = L10n.tr("Wpisz, co chcesz zrobić — np. „plan”, „eksport”, „compile”; Enter wykonuje pierwszą pozycję")
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.controlSize = .small
        search.translatesAutoresizingMaskIntoConstraints = false

        collapseButton.bezelStyle = .accessoryBarAction
        collapseButton.isBordered = false
        collapseButton.target = self
        collapseButton.action = #selector(toggleCollapsed)
        collapseButton.translatesAutoresizingMaskIntoConstraints = false

        groupStack.orientation = .horizontal
        groupStack.alignment = .top
        groupStack.spacing = 0
        groupStack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 0, right: 8)
        groupStack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(groupStack)
        scroll.documentView = document
        scroll.drawsBackground = false
        // Bez paska przewijania: przy pokazywanych paskach (Ustawienia systemowe) zasłaniałby podpisy grup; szeroką
        // kartę przewija gest albo kółko z Shift.
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false

        for v in [tabStack, search, collapseButton, line, scroll] as [NSView] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            tabStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            tabStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 3),
            tabStack.heightAnchor.constraint(equalToConstant: Self.stripHeight - 6),
            tabStack.trailingAnchor.constraint(lessThanOrEqualTo: search.leadingAnchor, constant: -12),
            collapseButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            collapseButton.centerYAnchor.constraint(equalTo: tabStack.centerYAnchor),
            search.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -6),
            search.centerYAnchor.constraint(equalTo: tabStack.centerYAnchor),
            search.widthAnchor.constraint(equalToConstant: 230),
            line.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.stripHeight),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: Self.contentHeight - 1),
            groupStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            groupStack.topAnchor.constraint(equalTo: document.topAnchor),
            groupStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            groupStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            document.heightAnchor.constraint(equalToConstant: Self.contentHeight - 1),
        ])
        view = root

        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            let kind = self.workspace.activeDocument?.kind
            if kind != self.activeKind || self.visibleTabs.isEmpty { self.show(kind: kind) }
        })
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            self.applyVisibility(shown: self.workspace.settings.showRibbon, collapsed: self.workspace.settings.ribbonCollapsed)
        })
        tokens.append(trackChanges { [weak self] in self?.refreshEnabled() })
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard updateObserver == nil, let window = view.window else { return }
        // Dostępność komend zależy też od stanu spoza modelu (zaznaczenie w edytorze, pierwszy responder) — jak pasek
        // narzędzi, wstążka sprawdza ją po każdym zdarzeniu okna.
        updateObserver = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEnabled() }
        }
    }

    // MARK: Karty

    private func show(kind: DocumentKind?) {
        activeKind = kind
        visibleTabs = RibbonModel.visibleTabs(for: kind)
        selectedTab = selection.tab(for: kind, visible: visibleTabs.map(\.id)) ?? "start"
        rebuildTabs()
        rebuildGroups()
    }

    private func rebuildTabs() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tab in visibleTabs {
            let color = tab.context.first.map(DocumentTabButton.color(for:))
            let b = RibbonTabButton(title: tab.title, selected: tab.id == selectedTab, color: color)
            b.onSelect = { [weak self] in self?.select(tab: tab.id) }
            b.onDoubleClick = { [weak self] in self?.toggleCollapsed() }
            if tab.isContextual {
                b.toolTip = L10n.tr("Karta kontekstowa: \(activeKind?.displayName ?? tab.title)")
            }
            tabStack.addArrangedSubview(b)
        }
    }

    private func select(tab id: String) {
        selection.select(id, for: activeKind)
        if workspace.settings.ribbonCollapsed { workspace.settings.ribbonCollapsed = false }
        guard id != selectedTab else { return }
        selectedTab = id
        rebuildTabs()
        rebuildGroups()
    }

    private func rebuildGroups() {
        groupStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = []
        guard let tab = visibleTabs.first(where: { $0.id == selectedTab }) else { return }
        for (i, group) in tab.groups.enumerated() {
            if i > 0 {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.heightAnchor.constraint(equalToConstant: Self.contentHeight - 14).isActive = true
                groupStack.addArrangedSubview(sep)
            }
            groupStack.addArrangedSubview(groupView(group))
        }
        refreshEnabled()
        scroll.contentView.scroll(to: .zero)
    }

    private func groupView(_ group: RibbonGroup) -> NSView {
        let items = NSStackView()
        items.orientation = .horizontal
        items.alignment = .top
        items.spacing = 2
        var column: NSStackView?
        func flushColumn() { column = nil }
        for item in group.items {
            switch item {
            case .large(let id, let label):
                flushColumn()
                if let b = commandButton(id, label: label, style: .large) { items.addArrangedSubview(b) }
            case .small(let id, let label):
                guard let b = commandButton(id, label: label, style: .small) else { continue }
                add(b, to: &column, in: items)
            case .menu(let title, let symbol, let commands, let large):
                let b = RibbonButton(style: large ? .large : .small, title: title, symbol: symbol, dropdown: true)
                b.toolTip = title
                b.onPress = { [weak self] sender in self?.popUp(commands, from: sender) }
                if large { flushColumn(); items.addArrangedSubview(b) } else { add(b, to: &column, in: items) }
            }
        }
        let title = NSTextField(labelWithString: group.title)
        title.font = .systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        let stack = NSStackView(views: [items, title])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Rząd przycisków o stałej wysokości (duży przycisk) — podpisy wszystkich grup w jednej linii.
        items.translatesAutoresizingMaskIntoConstraints = false
        items.heightAnchor.constraint(equalToConstant: RibbonButton.largeHeight).isActive = true
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel(group.title)
        return stack
    }

    /// Małe przyciski układane po trzy w kolumnie.
    private func add(_ b: RibbonButton, to column: inout NSStackView?, in items: NSStackView) {
        if column == nil || column!.arrangedSubviews.count == 3 {
            let c = NSStackView()
            c.orientation = .vertical
            c.alignment = .leading
            c.spacing = 1
            items.addArrangedSubview(c)
            column = c
        }
        column!.addArrangedSubview(b)
    }

    private func commandButton(_ id: String, label: String?, style: RibbonButton.Style) -> RibbonButton? {
        guard let d = workspace.registry.command(CommandID(rawValue: id))?.descriptor else { return nil }
        let title = label ?? d.title.replacingOccurrences(of: "…", with: "")
        let b = RibbonButton(style: style, title: title, symbol: CommandSymbols.symbol(for: id) ?? "circle.dashed", dropdown: false)
        b.commandID = d.id
        b.toolTip = tooltip(for: d)
        b.onPress = { [weak self] _ in self?.run(d.id) }
        b.contextMenuProvider = { [weak self] in self?.contextMenu(for: d.id) }
        buttons.append(b)
        return b
    }

    private func tooltip(for d: CommandDescriptor) -> String {
        var s = d.title + "\n" + d.summary
        if let chord = workspace.keymap.chords(for: d.id).first { s += "\n" + L10n.tr("Skrót: \(chord.displayString)") }
        return s
    }

    private func refreshEnabled() {
        for b in buttons {
            guard let id = b.commandID else { continue }
            let on = workspace.isEnabled(id)
            if b.isEnabled != on { b.isEnabled = on }
        }
    }

    // MARK: Listy rozwijane i menu kontekstowe

    private func popUp(_ commands: [String], from button: RibbonButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for raw in RibbonModel.expand(commands, in: workspace.registry) {
            if raw == RibbonModel.separator { menu.addItem(.separator()); continue }
            guard let d = workspace.registry.command(CommandID(rawValue: raw))?.descriptor else { continue }
            let item = NSMenuItem(title: d.title, action: #selector(menuCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = raw
            item.toolTip = d.summary
            item.isEnabled = workspace.isEnabled(d.id)
            if let symbol = CommandSymbols.symbol(for: raw) {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            if let chord = workspace.keymap.chords(for: d.id).first(where: { MenuBuilder.keyEquivalent(for: $0) != nil }),
               let (key, mask) = MenuBuilder.keyEquivalent(for: chord) {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = mask
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @objc private func menuCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        run(CommandID(rawValue: raw))
    }

    private func contextMenu(for id: CommandID) -> NSMenu {
        let menu = NSMenu()
        let inQuickAccess = workspace.settings.quickAccessCommands.contains(id.rawValue)
        let qa = menu.addItem(withTitle: inQuickAccess ? L10n.tr("Usuń z paska szybkiego dostępu") : L10n.tr("Dodaj do paska szybkiego dostępu"),
                              action: #selector(toggleQuickAccess(_:)), keyEquivalent: "")
        qa.target = self
        qa.representedObject = id.rawValue
        menu.addItem(.separator())
        let collapse = menu.addItem(withTitle: L10n.tr("Zwiń wstążkę"), action: #selector(toggleCollapsed), keyEquivalent: "")
        collapse.target = self
        return menu
    }

    @objc private func toggleQuickAccess(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let inQuickAccess = workspace.settings.quickAccessCommands.contains(raw)
        workspace.perform(inQuickAccess ? "view.removeFromQuickAccess" : "view.addToQuickAccess", CommandArguments(["command": .string(raw)]))
    }

    private func run(_ id: CommandID) {
        workspace.perform(id)
    }

    // MARK: Zwijanie i widoczność

    @objc private func toggleCollapsed() {
        workspace.settings.ribbonCollapsed.toggle()
    }

    private func applyVisibility(shown: Bool, collapsed: Bool) {
        isHidden = !shown
        scroll.isHidden = collapsed
        let symbol = collapsed ? "chevron.down" : "chevron.up"
        collapseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        collapseButton.toolTip = collapsed ? L10n.tr("Rozwiń wstążkę") : L10n.tr("Zwiń wstążkę do kart")
        collapseButton.setAccessibilityLabel(collapseButton.toolTip)
        let height = Self.stripHeight + (collapsed ? 0 : Self.contentHeight)
        if view.frame.height != height { view.setFrameSize(NSSize(width: view.frame.width, height: height)) }
    }

    // MARK: Szukaj czynności

    func focusSearch() {
        view.window?.makeFirstResponder(search)
    }

    func controlTextDidChange(_ obj: Notification) {
        results.update(query: search.stringValue, below: search)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        results.close()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): results.move(1); return true
        case #selector(NSResponder.moveUp(_:)): results.move(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            guard let id = results.selected else { return true }
            finishSearch()
            run(id)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finishSearch()
            return true
        default: return false
        }
    }

    private func finishSearch() {
        results.close()
        search.stringValue = ""
        view.window?.makeFirstResponder(nil)
        (view.window?.windowController as? MainWindowController)?.documentArea.focusActiveDocument()
    }
}

/// Widok z osią Y w dół (zawartość przewijana od lewej górnej krawędzi).
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Przyciski

/// Karta wstążki: tytuł, wyróżnienie wybranej, kolor rodzaju okna dla kart kontekstowych.
final class RibbonTabButton: NSView {
    var onSelect: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    private let label: NSTextField

    init(title: String, selected: Bool, color: NSColor?) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        label.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        label.textColor = color ?? (selected ? .labelColor : .secondaryLabelColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        if selected {
            layer?.backgroundColor = (color ?? .controlAccentColor).withAlphaComponent(0.16).cgColor
        } else if let color {
            layer?.borderWidth = 1
            layer?.borderColor = color.withAlphaComponent(0.5).cgColor
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        setAccessibilityValue(selected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { onSelect?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }
}

/// Przycisk wstążki: duży (ikona nad podpisem w dwóch liniach) albo mały (ikona obok podpisu); podświetlenie pod
/// kursorem, lista rozwijana oznaczona strzałką.
final class RibbonButton: NSControl {
    enum Style { case large, small }
    static let largeHeight: CGFloat = 76

    var commandID: CommandID?
    var onPress: ((RibbonButton) -> Void)?
    var contextMenuProvider: (() -> NSMenu?)?
    private let style: Style
    private let imageView = NSImageView()
    private let label: NSTextField
    private var hovering = false { didSet { updateBackground() } }
    private var pressed = false { didSet { updateBackground() } }

    init(style: Style, title: String, symbol: String, dropdown: Bool) {
        self.style = style
        let text = dropdown ? title + " ▾" : title
        label = style == .large ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        let config = NSImage.SymbolConfiguration(pointSize: style == .large ? 22 : 13, weight: .regular)
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        addSubview(label)
        switch style {
        case .large:
            label.alignment = .center
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byWordWrapping
            label.preferredMaxLayoutWidth = 84
            NSLayoutConstraint.activate([
                widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
                widthAnchor.constraint(lessThanOrEqualToConstant: 92),
                heightAnchor.constraint(equalToConstant: Self.largeHeight),
                imageView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.heightAnchor.constraint(equalToConstant: 28),
                label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 3),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            ])
        case .small:
            label.lineBreakMode = .byTruncatingTail
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 22),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualToConstant: 170),
            ])
        }
        setAccessibilityElement(true)
        setAccessibilityRole(dropdown ? .popUpButton : .button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isEnabled: Bool {
        didSet {
            imageView.contentTintColor = isEnabled ? .labelColor : .tertiaryLabelColor
            label.textColor = isEnabled ? .labelColor : .tertiaryLabelColor
            if !isEnabled { hovering = false }
        }
    }

    private func updateBackground() {
        let alpha: CGFloat = pressed ? 0.22 : hovering ? 0.12 : 0
        layer?.backgroundColor = alpha == 0 ? nil : NSColor.labelColor.withAlphaComponent(alpha).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { hovering = true } }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        // Śledzenie do puszczenia przycisku: klik liczy się, gdy kursor jest nadal nad przyciskiem.
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            if next.type == .leftMouseUp {
                pressed = false
                if inside { onPress?(self) }
                return
            }
            pressed = inside
        }
        pressed = false
    }

    override func menu(for event: NSEvent) -> NSMenu? { contextMenuProvider?() }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?(self)
        return true
    }
}

// MARK: - Wyniki wyszukiwania

/// Lista wyników „Szukaj czynności” pod polem wyszukiwania: ikona, tytuł, miejsce na wstążce lub w menu, skrót.
/// Pole zachowuje fokus (strzałki, Enter i Esc obsługuje `RibbonController`); kliknięcie wiersza wykonuje komendę.
@MainActor
final class RibbonSearchResults: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let workspace: Workspace
    private let onChoose: (CommandID) -> Void
    private let popover = NSPopover()
    private let table = NSTableView()
    private var items: [CommandDescriptor] = []
    /// Nazwy komend w innym języku (angielskie tytuły przy interfejsie po polsku) — liczone raz.
    private lazy var alternates: [CommandID: [String]] = {
        var out: [CommandID: [String]] = [:]
        for d in workspace.registry.descriptors {
            let names = [L10n.translation(of: d.title, language: "en"), d.submenu.flatMap { L10n.translation(of: $0, language: "en") }].compactMap { $0 }
            if !names.isEmpty { out[d.id] = names }
        }
        return out
    }()

    init(workspace: Workspace, onChoose: @escaping (CommandID) -> Void) {
        self.workspace = workspace
        self.onChoose = onChoose
        super.init()
        let column = NSTableColumn(identifier: .init("command"))
        column.width = 440
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 34
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.refusesFirstResponder = true
        table.setAccessibilityLabel(L10n.tr("Znalezione czynności"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let vc = NSViewController()
        vc.view = scroll
        popover.contentViewController = vc
        popover.behavior = .applicationDefined
        popover.animates = false
    }

    var selected: CommandID? {
        let row = table.selectedRow
        return items.indices.contains(row) ? items[row].id : items.first?.id
    }

    func update(query: String, below field: NSView) {
        let candidates = workspace.registry.descriptors.filter { $0.inMenu && !$0.id.rawValue.hasPrefix("agent.") }
        items = CommandSearch.search(query, in: candidates, limit: 12) { [alternates] in alternates[$0.id] ?? [] }.map(\.descriptor)
        guard !items.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty else { close(); return }
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        let height = CGFloat(max(1, min(items.count, 12))) * (table.rowHeight + table.intercellSpacing.height) + 8
        popover.contentSize = NSSize(width: 460, height: height)
        if !popover.isShown { popover.show(relativeTo: field.bounds, of: field, preferredEdge: .maxY) }
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        let row = max(0, min(items.count - 1, table.selectedRow + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    @objc private func clicked() {
        let row = table.clickedRow
        guard items.indices.contains(row) else { return }
        close()
        onChoose(items[row].id)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { max(items.count, 1) }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else {
            let empty = NSTextField(labelWithString: L10n.tr("Nic nie znaleziono — spróbuj innego słowa"))
            empty.textColor = .secondaryLabelColor
            return empty
        }
        let d = items[row]
        let enabled = workspace.isEnabled(d.id)
        let icon = NSImageView(image: NSImage(systemSymbolName: CommandSymbols.symbol(for: d.id.rawValue) ?? "command", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = enabled ? .labelColor : .tertiaryLabelColor
        let title = NSTextField(labelWithString: d.title)
        title.textColor = enabled ? .labelColor : .tertiaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        let place: String
        if let (tab, group) = RibbonModel.location(of: d.id.rawValue) {
            place = L10n.tr("Wstążka › \(tab.title) › \(group.title)")
        } else {
            place = L10n.tr("Menu \(d.category.displayName)") + (d.submenu.map { " › " + $0 } ?? "")
        }
        let detail = NSTextField(labelWithString: enabled ? place : place + " · " + L10n.tr("teraz niedostępne"))
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let texts = NSStackView(views: [title, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 0
        let key = NSTextField(labelWithString: workspace.keymap.chords(for: d.id).first?.displayString ?? "")
        key.textColor = .secondaryLabelColor
        key.setContentCompressionResistancePriority(.required, for: .horizontal)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [icon, texts, key])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 8)
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return row
    }
}
