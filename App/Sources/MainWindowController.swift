import AppKit
import PelikanWorkspace

/// Okno główne w układzie PL/SQL Developer (ADR 0005): lewa kolumna narzędzi, obszar dokumentów z kartami, pasek stanu.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let windowID = NSUserInterfaceItemIdentifier("PelikanMainWindow")
    private(set) lazy var documentArea = DocumentAreaViewController(workspace: workspace)
    private let workspace: Workspace
    private let split = NSSplitViewController()
    private(set) lazy var sidebarController = SidebarViewController(workspace: workspace)
    private(set) var toolbarController: MainToolbarController?
    private(set) lazy var ribbon = RibbonController(workspace: workspace)
    /// Panele narzędzi (PD-UI-003, D183): prawy obok obszaru dokumentów, dolny pod nim — w zagnieżdżonych podziałach,
    /// żeby zapamiętany układ kolumn okna (lewa kolumna, panel agenta) się nie zmienił.
    private(set) lazy var rightDock = ToolDockViewController(placement: .right, workspace: workspace)
    private(set) lazy var bottomDock = ToolDockViewController(placement: .bottom, workspace: workspace)
    private let workArea = DockSplitViewController(placement: .right)
    private let centerArea = DockSplitViewController(placement: .bottom)
    private var rightDockItem: NSSplitViewItem!
    private var bottomDockItem: NSSplitViewItem!

    init(workspace: Workspace) {
        self.workspace = workspace
        let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan"

        window.titlebarSeparatorStyle = .line
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.identifier = Self.windowID
        super.init(window: window)
        window.delegate = self

        // Zwykły panel zamiast paska bocznego (D180): pasek boczny macOS 26+ leży w „płynnym szkle” (NSGlassEffectView),
        // przez które tekst całego panelu był na monitorach bez Retina rysowany kanciasto w aktywnym oknie.
        let sidebar = NSSplitViewItem(viewController: sidebarController)
        sidebar.holdingPriority = .defaultLow + 10
        sidebar.minimumThickness = 220
        sidebar.maximumThickness = 420
        sidebar.canCollapse = true
        centerArea.splitView.isVertical = false
        let documents = NSSplitViewItem(viewController: documentArea)
        documents.minimumThickness = 200
        bottomDockItem = DockSplitViewController.dockItem(bottomDock, minimum: 120)
        centerArea.addSplitViewItem(documents)
        centerArea.addSplitViewItem(bottomDockItem)
        let center = NSSplitViewItem(viewController: centerArea)
        center.minimumThickness = 480
        rightDockItem = DockSplitViewController.dockItem(rightDock, minimum: 240)
        workArea.addSplitViewItem(center)
        workArea.addSplitViewItem(rightDockItem)
        let content = NSSplitViewItem(viewController: workArea)
        content.minimumThickness = 480
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(content)
        split.splitView.autosaveName = "PelikanMainSplit"
        window.contentViewController = split
        // contentViewController dopasowuje okno do minimalnego rozmiaru treści — rozmiar startowy ustawiamy po nim,
        // a zapamiętaną ramkę (autosave) przywracamy na końcu.
        window.contentMinSize = NSSize(width: 820, height: 520)
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        window.setFrameUsingName("PelikanMainWindow")
        window.setFrameAutosaveName("PelikanMainWindow")

        let toolbar = NSToolbar(identifier: "PelikanMainToolbar")
        toolbar.displayMode = .iconOnly
        toolbarController = MainToolbarController(workspace: workspace, toolbar: toolbar)
        window.toolbar = toolbar
        window.addTitlebarAccessoryViewController(ribbon)
        window.onFirstResponderChange = { [weak self] in self?.autoHideDocks() }
        window.toolsWithoutFocus = { [weak self] in
            guard let self else { return [] }
            let responder = self.window?.firstResponder
            return [self.rightDock, self.bottomDock].compactMap { $0.isViewLoaded ? $0.unfocusedContent(responder: responder) : nil }
        }
        trackChanges { [weak self] in
            guard let self else { return }
            // Tytuł z połączeniem i worksetem, podtytuł z oknem i jego połączeniem (PD-UI-009).
            let appName = Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan"
            self.window?.title = workspace.windowTitle(appName: appName)
            self.window?.subtitle = workspace.windowSubtitle()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Zamknięcie okna głównego kończy aplikację drogą `applicationShouldTerminate` (pytania o zapis i transakcje).
    /// Okno zostaje, gdy użytkownik anuluje — inaczej przy innym otwartym oknie (Preferencje, narzędzie w osobnym oknie)
    /// aplikacja działałaby dalej bez okna głównego i bez sposobu na jego przywrócenie.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    // MARK: Prawa kolumna — panel agenta (ADR 0005)

    private var agentItem: NSSplitViewItem?

    /// Dodaje panel agenta jako prawą, zwijaną kolumnę (domyślnie zwiniętą).
    func installAgentPane(_ view: NSView) {
        guard agentItem == nil else { return }
        let vc = NSViewController()
        vc.view = view
        let item = NSSplitViewItem(viewController: vc)
        item.minimumThickness = 380
        item.canCollapse = true
        item.isCollapsed = true
        item.holdingPriority = .defaultLow + 10
        split.addSplitViewItem(item)
        agentItem = item
    }

    var isAgentPaneVisible: Bool { agentItem.map { !$0.isCollapsed } ?? false }

    // MARK: Układ okna (PD-WSET-002)

    var layout: WindowLayout? {
        guard let w = window else { return nil }
        let sidebar = split.splitViewItems.first
        return WindowLayout(frame: NSStringFromRect(w.frame), sidebarWidth: Double(sidebar?.viewController.view.frame.width ?? 260),
                            sidebarPane: sidebarController.selectedPane, agentPaneVisible: isAgentPaneVisible)
    }

    func apply(_ l: WindowLayout) {
        let f = NSRectFromString(l.frame)
        if f.width >= 400, f.height >= 300, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(f) }) { window?.setFrame(f, display: true) }
        split.splitViewItems.first?.isCollapsed = false
        split.splitView.setPosition(CGFloat(l.sidebarWidth), ofDividerAt: 0)
        sidebarController.select(pane: l.sidebarPane)
        if agentItem != nil { setAgentPane(visible: l.agentPaneVisible) }
    }

    func setAgentPane(visible: Bool) {
        agentItem?.animator().isCollapsed = !visible
    }

    // MARK: Panele narzędzi (PD-UI-003)

    func dock(_ placement: ToolPlacement) -> ToolDockViewController { placement == .bottom ? bottomDock : rightDock }

    func isDockVisible(_ placement: ToolPlacement) -> Bool {
        !(placement == .bottom ? bottomDockItem : rightDockItem).isCollapsed
    }

    /// Pokazuje albo chowa panel; przy pokazaniu przywraca zapamiętany rozmiar i poszerza panel do minimalnego rozmiaru
    /// narzędzia `fitting` (najwyżej do 60% obszaru, dalej zawartość się przewija).
    func setDock(_ placement: ToolPlacement, visible: Bool, fitting item: ToolItem? = nil) {
        guard placement != .floating else { return }
        let area = placement == .bottom ? centerArea : workArea
        let item = item.map { placement == .bottom ? $0.minimumSize.height : $0.minimumSize.width }
        let dockItem = placement == .bottom ? bottomDockItem! : rightDockItem!
        defer { ToolDockManager.shared.noteChange() }
        if !visible {
            dockItem.isCollapsed = true
            return
        }
        let wasCollapsed = dockItem.isCollapsed
        dockItem.isCollapsed = false
        area.view.layoutSubtreeIfNeeded()
        let current = area.dockSize
        var size = wasCollapsed ? area.savedSize : current
        if let item { size = max(size, item + 16) }
        if wasCollapsed || size > current + 1 { area.setDockSize(size) }
    }

    /// Autoukrywanie (Preferencje › Panele narzędzi): fokus w edytorze okna chowa panele z narzędziami.
    private func autoHideDocks() {
        guard workspace.settings.toolDock.autoHide, let responder = window?.firstResponder as? NSView,
              responder.isDescendant(of: documentArea.view) else { return }
        for p in [ToolPlacement.right, .bottom] where isDockVisible(p) { setDock(p, visible: false) }
    }

    /// Fokus po arkuszu (pytanie o tekst, zmienne, logowanie): gdy przed arkuszem był w narzędziu panelu albo w lewej
    /// kolumnie, tam zostaje — przeniesienie do edytora zwijałoby przy autoukrywaniu panel, w którym użytkownik pracuje.
    /// W pozostałych przypadkach — edytor aktywnego okna.
    func restoreFocus(after previous: NSResponder?) {
        var view = previous as? NSView
        if let text = view as? NSTextView, text.isFieldEditor { view = text.delegate as? NSView }
        if let view, let window, view.window === window, !view.isDescendant(of: documentArea.view) {
            if window.firstResponder !== previous { window.makeFirstResponder(view) }
            return
        }
        documentArea.focusActiveDocument()
    }
}

/// Okno główne zgłaszające zmianę fokusu (autoukrywanie paneli narzędzi) i ograniczające skróty narzędzi w panelach.
private final class MainWindow: NSWindow {
    var onFirstResponderChange: (() -> Void)?
    var toolsWithoutFocus: (() -> [NSView])?

    /// Skróty narzędzia w panelu (przycisk domyślny — Enter, Anuluj — Esc, `keyboardShortcut` SwiftUI, klawisze
    /// przycisków AppKit) działają tylko z fokusem w tym narzędziu: Enter w drzewie obiektów czy siatce nie może wykonać
    /// czynności narzędzia z panelu, a skrót narzędzia nie może przejąć skrótu menu. SwiftUI obsługuje skróty poza
    /// hierarchią widoków i pomija tylko widoki ukryte — narzędzia bez fokusu są ukrywane na czas obsługi zdarzenia
    /// (bez rysowania; ukrycie nie wywołuje onDisappear). Zwykłe pisanie (bez ⌘/⌃/⌥, poza Enter i Esc) nie może być
    /// skrótem narzędzia — wtedy bez ukrywania, żeby każdy znak w edytorze nie unieważniał układu narzędzi w panelach.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard Self.mayBeToolShortcut(event) else { return super.performKeyEquivalent(with: event) }
        let hidden = (toolsWithoutFocus?() ?? []).filter { !$0.isHidden }
        hidden.forEach { $0.isHidden = true }
        defer { hidden.forEach { $0.isHidden = false } }
        return super.performKeyEquivalent(with: event)
    }

    /// Skróty narzędzi to przycisk domyślny (Enter), Anuluj (Esc) i skróty z modyfikatorem.
    private static func mayBeToolShortcut(_ event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return true }
        return ["\r", "\u{3}", "\u{1b}"].contains(event.charactersIgnoringModifiers ?? "")
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let changed = super.makeFirstResponder(responder)
        if changed { onFirstResponderChange?() }
        return changed
    }
}

/// Podział z panelem narzędzi jako drugim elementem; rozmiar panelu zapamiętany między uruchomieniami.
final class DockSplitViewController: NSSplitViewController {
    let placement: ToolPlacement
    private var defaultsKey: String { "Pelikan.toolDock." + placement.rawValue }

    init(placement: ToolPlacement) {
        self.placement = placement
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func dockItem(_ vc: NSViewController, minimum: CGFloat) -> NSSplitViewItem {
        let item = NSSplitViewItem(viewController: vc)
        item.minimumThickness = minimum
        item.canCollapse = true
        item.isCollapsed = true
        item.holdingPriority = .defaultLow + 10
        return item
    }

    private var total: CGFloat { splitView.isVertical ? splitView.bounds.width : splitView.bounds.height }

    var dockSize: CGFloat {
        guard let v = splitViewItems.last?.viewController.view else { return 0 }
        return splitView.isVertical ? v.frame.width : v.frame.height
    }

    var savedSize: CGFloat {
        let saved = UserDefaults.standard.double(forKey: defaultsKey)
        return saved > 0 ? saved : (placement == .bottom ? 280 : 440)
    }

    func setDockSize(_ size: CGFloat) {
        let s = min(size, total * 0.6)
        splitView.setPosition(total - s - splitView.dividerThickness, ofDividerAt: 0)
    }

    private var wasCollapsed = true

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard let dock = splitViewItems.last else { return }
        // Zwinięcie przeciągnięciem podziału — pasek stanu pokazuje przycisk panelu.
        if dock.isCollapsed != wasCollapsed {
            wasCollapsed = dock.isCollapsed
            ToolDockManager.shared.noteChange()
        }
        guard !dock.isCollapsed, dockSize > 0 else { return }
        UserDefaults.standard.set(Double(dockSize), forKey: defaultsKey)
    }
}

// MARK: - Lewa kolumna

/// Lewa kolumna narzędzi: połączenia, przeglądarka obiektów, lista okien, szablony i pliki.
final class SidebarViewController: NSViewController {
    private let workspace: Workspace
    private let selector = NSSegmentedControl(labels: [L10n.tr("Połączenia"), L10n.tr("Obiekty"), L10n.tr("Okna"), L10n.tr("Szablony"), L10n.tr("Pliki")],
                                              trackingMode: .selectOne, target: nil, action: nil)
    private let container = NSView()
    private lazy var panes: [NSViewController] = [
        ConnectionListViewController(workspace: workspace),
        ObjectBrowserViewController(workspace: workspace),
        WindowListViewController(workspace: workspace),
        TemplatePaneController(workspace: workspace),
        FileBrowserPaneController(workspace: workspace),
    ]
    static let objectBrowserPane = 1
    static let fileBrowserPane = 4

    /// Wybrana karta lewej kolumny (układ okna, PD-WSET-002).
    var selectedPane: Int { selector.selectedSegment }

    func select(pane index: Int) {
        guard panes.indices.contains(index) else { return }
        _ = view
        selector.selectedSegment = index
        show(pane: index)
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = SolidBackgroundView(material: .sidebar)
        selector.target = self
        selector.action = #selector(selectPane(_:))
        selector.selectedSegment = 0
        selector.segmentDistribution = .fillEqually
        selector.controlSize = .small
        selector.font = InterfaceFonts.shared.small
        selector.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(selector)
        root.addSubview(container)
        NSLayoutConstraint.activate([
            selector.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 8),
            selector.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            selector.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: selector.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        show(pane: 0)
        trackChanges { [weak self] in self?.selector.font = InterfaceFonts.shared.small }
    }

    @objc private func selectPane(_ sender: NSSegmentedControl) { show(pane: sender.selectedSegment) }

    private func show(pane index: Int) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let vc = panes[index]
        if vc.parent == nil { addChild(vc) }
        vc.view.frame = container.bounds
        vc.view.autoresizingMask = [.width, .height]
        container.addSubview(vc.view)
    }
}

// MARK: - Obszar dokumentów

/// Widok obszaru dokumentów przyjmujący upuszczone pliki (MAC-FILE-001).
final class FileDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    /// Wklejenie tekstu na pusty obszar okien tworzy SQL Window (PD-SQLW-025).
    var onPaste: (() -> Void)?
    /// Obiekt z Object Browsera upuszczony poza edytorem (PD-OB-010): właściciel, nazwa, typ, połączenie gałęzi.
    var onObjectDrop: ((BrowserObjectDrag) -> Void)?

    override var acceptsFirstResponder: Bool { onPaste != nil }
    @objc func paste(_ sender: Any?) { onPaste?() }
    override func mouseDown(with event: NSEvent) {
        if onPaste != nil { window?.makeFirstResponder(self) }
        super.mouseDown(with: event)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, ObjectBrowserViewController.objectPasteboardType])
    }

    private func object(_ info: any NSDraggingInfo) -> BrowserObjectDrag? {
        info.draggingPasteboard.string(forType: ObjectBrowserViewController.objectPasteboardType).flatMap(BrowserObjectDrag.init)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func urls(_ info: any NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { urls(sender).isEmpty && object(sender) == nil ? [] : .copy }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let o = object(sender) {
            onObjectDrop?(o)
            return true
        }
        let u = urls(sender)
        guard !u.isEmpty else { return false }
        onDrop?(u)
        return true
    }
}

/// Kontroler zawartości okna dokumentu (SQL, program, test, polecenia, plan, diagram, raport, notatnik).
@MainActor
protocol DocumentContentController: NSViewController {
    /// Widok, który dostaje fokus po aktywacji okna albo zamknięciu arkusza.
    var preferredFirstResponder: NSView { get }
}

/// Pasek kart dokumentów (SDI wzorca) + widok aktywnego dokumentu + pasek stanu.
final class DocumentAreaViewController: NSViewController {
    private let workspace: Workspace
    private let tabBar = NSStackView()
    private let container = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    /// Połączenie okna na pasku stanu — kliknięcie: wybór połączenia okna (UG 20.2, PD-CONN-019).
    private let connectionButton = NSButton(title: "", target: nil, action: nil)
    /// Gałąź i stan Git pliku aktywnego okna (PD-VCS-001).
    private let gitLabel = NSTextField(labelWithString: "")
    /// Przyciski zwiniętych paneli narzędzi z liczbą narzędzi (D183).
    private let dockButtons = NSStackView()
    private var gitKey: String?
    private var controllers: [DocumentID: NSViewController] = [:]
    private var installedID: DocumentID?

    /// Fokus do edytora aktywnego okna (np. po zamknięciu arkusza logowania albo zmiennych) — każdy rodzaj okna,
    /// także notatnik (wspólny protokół zamiast łańcucha rzutowań, R4-20).
    func focusActiveDocument() {
        guard let id = installedID, let vc = controllers[id] else { return }
        view.window?.makeFirstResponder((vc as? any DocumentContentController)?.preferredFirstResponder)
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = FileDropView()
        root.onDrop = { [weak self] urls in
            guard let self else { return }
            for u in urls {
                do { try self.workspace.openFile(u) } catch { self.workspace.ui?.showError(error.localizedDescription) }
            }
        }
        root.onObjectDrop = { [weak self] drag in
            self?.workspace.perform("ob.dropOnWorkspace", drag.arguments())
        }
        root.onPaste = { [weak self] in
            guard let self, self.workspace.documents.isEmpty else { return }
            self.workspace.perform("file.pasteAsSQLWindow")
        }
        tabBar.orientation = .horizontal
        tabBar.spacing = 2
        tabBar.alignment = .centerY
        tabBar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        let tabScroll = NSScrollView()
        tabScroll.documentView = tabBar
        tabScroll.hasHorizontalScroller = false
        tabScroll.drawsBackground = false
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = InterfaceFonts.shared.small
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        let status = NSView()
        status.addSubview(statusLabel)
        connectionButton.isBordered = false
        connectionButton.font = InterfaceFonts.shared.small
        connectionButton.contentTintColor = .labelColor
        connectionButton.target = self
        connectionButton.action = #selector(chooseConnection(_:))
        connectionButton.toolTip = L10n.tr("Połączenie okna — kliknij, aby zmienić")
        connectionButton.translatesAutoresizingMaskIntoConstraints = false
        connectionButton.setContentHuggingPriority(.required, for: .horizontal)
        connectionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        status.addSubview(connectionButton)
        gitLabel.font = InterfaceFonts.shared.small
        gitLabel.textColor = .secondaryLabelColor
        gitLabel.translatesAutoresizingMaskIntoConstraints = false
        gitLabel.setContentHuggingPriority(.required, for: .horizontal)
        gitLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        status.addSubview(gitLabel)
        dockButtons.spacing = 6
        dockButtons.translatesAutoresizingMaskIntoConstraints = false
        dockButtons.setContentHuggingPriority(.required, for: .horizontal)
        status.addSubview(dockButtons)
        let separator = NSBox()
        separator.boxType = .separator
        let topSeparator = NSBox()
        topSeparator.boxType = .separator

        for v in [tabScroll, topSeparator, container, separator, status, statusLabel] { v.translatesAutoresizingMaskIntoConstraints = false }
        for v in [tabScroll, topSeparator, container, separator, status] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            tabScroll.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            tabScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            { let c = tabScroll.heightAnchor.constraint(equalToConstant: 32); c.priority = .defaultHigh; return c }(),
            tabBar.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor),
            tabBar.heightAnchor.constraint(equalTo: tabScroll.contentView.heightAnchor),
            topSeparator.topAnchor.constraint(equalTo: tabScroll.bottomAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: container.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.topAnchor.constraint(equalTo: separator.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 24),
            connectionButton.leadingAnchor.constraint(equalTo: status.leadingAnchor, constant: 8),
            connectionButton.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: connectionButton.trailingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: gitLabel.leadingAnchor, constant: -10),
            gitLabel.trailingAnchor.constraint(equalTo: dockButtons.leadingAnchor, constant: -8),
            dockButtons.trailingAnchor.constraint(equalTo: status.trailingAnchor, constant: -10),
            dockButtons.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            gitLabel.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: status.centerYAnchor),
        ])
        view = root
        trackChanges { [weak self] in self?.refresh() }
        trackChanges { [weak self] in self?.refreshDockButtons() }
    }

    /// Zwinięty panel z narzędziami: przycisk z liczbą narzędzi, który go pokazuje.
    private func refreshDockButtons() {
        let manager = ToolDockManager.shared
        let font = InterfaceFonts.shared.small
        dockButtons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (placement, symbol, command) in [(ToolPlacement.bottom, "rectangle.bottomthird.inset.filled", "view.toolDockBottom"),
                                             (.right, "sidebar.right", "view.toolDockRight")] {
            let count = manager.count(in: placement)
            guard count > 0, manager.mainWindow?.isDockVisible(placement) == false else { continue }
            let tip = placement == .right ? L10n.tr("Pokaż panel po prawej (narzędzia: \(count))")
                                          : L10n.tr("Pokaż panel na dole (narzędzia: \(count))")
            let b = NSButton(title: String(count), image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                             target: self, action: #selector(showDock(_:)))
            b.isBordered = false
            b.font = font
            b.imagePosition = .imageLeading
            b.toolTip = tip
            b.setAccessibilityLabel(tip)
            b.identifier = NSUserInterfaceItemIdentifier(command)
            dockButtons.addArrangedSubview(b)
        }
    }

    @objc private func showDock(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        workspace.perform(CommandID(rawValue: id))
    }

    private func refresh() {
        // Czcionka interfejsu z Preferencji (D178) — odczyt w śledzonym odświeżeniu: zmiana od razu przebudowuje karty.
        let fonts = InterfaceFonts.shared
        for l in [statusLabel, gitLabel] { l.font = fonts.small }
        connectionButton.font = fonts.small
        let docs = workspace.documents
        let active = workspace.activeDocumentID
        // Karty.
        tabBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for doc in docs {
            let tab = DocumentTabButton(document: doc, isActive: doc.id == active) { [weak self] in
                self?.workspace.activate(doc.id)
            } onClose: { [weak self] in
                self?.workspace.perform("file.closeWindow", CommandArguments(["document": .string(doc.id.description)]))
            }
            tab.menu = tabMenu(for: doc)
            // Kolor połączenia (wskaźniki, PD-CONN-005) jako obramowanie karty.
            if let c = workspace.indicatorColor(for: doc) {
                tab.layer?.borderWidth = 1.5
                tab.layer?.borderColor = NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 0.9).cgColor
            }
            tabBar.addArrangedSubview(tab)
        }
        // Widoki dokumentów (zachowywane dla otwartych okien).
        let alive = Set(docs.map(\.id))
        for (id, vc) in controllers where !alive.contains(id) {
            vc.view.removeFromSuperview()
            vc.removeFromParent()
            controllers[id] = nil
        }
        container.clipsToBounds = true
        if workspace.activeDocument?.id != installedID { container.subviews.forEach { $0.removeFromSuperview() } }
        if let doc = workspace.activeDocument {
            let vc = controllers[doc.id] ?? {
                let c: NSViewController = switch doc.kind {
                case .sql: SQLWindowViewController(document: doc, workspace: workspace)
                case .command: CommandWindowViewController(document: doc, workspace: workspace)
                case .program: ProgramWindowViewController(document: doc, workspace: workspace)
                case .test: TestWindowViewController(document: doc, workspace: workspace)
                case .diagram: DiagramViewController(document: doc, workspace: workspace)
                case .explainPlan: ExplainPlanViewController(document: doc, workspace: workspace)
                case .report: ReportWindowViewController(document: doc, workspace: workspace)
                case .notebook: NotebookViewController(document: doc, workspace: workspace)
                }
                addChild(c)
                controllers[doc.id] = c
                return c
            }()
            if installedID != doc.id {
                vc.view.frame = container.bounds
                vc.view.autoresizingMask = [.width, .height]
                container.addSubview(vc.view)
                installedID = doc.id
                focusActiveDocument()
            }
            connectionButton.title = connectionDescription(for: doc) + " ▾"
            connectionButton.contentTintColor = workspace.indicatorColor(for: doc).map { NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } ?? .labelColor
            connectionButton.isHidden = false
            statusLabel.stringValue = [doc.transactionOpen ? L10n.tr("● transakcja otwarta") : nil, workspace.coverageStatus(in: doc),
                                       doc.isExecuting ? nil : doc.resultSummary,
                                       doc.isExecuting ? L10n.tr("Wykonywanie…") : doc.statusText?.components(separatedBy: "\n").first].compactMap { $0 }.joined(separator: "   ·   ")
            // Plik karty widocznej (okno pary) z pamięci kart — bez dzielenia tekstu przy każdym znaku (R4-01).
            refreshGit(file: doc.shownFileURL, modified: doc.isModified)
        } else {
            installedID = nil
            refreshGit(file: nil, modified: false)
            connectionButton.isHidden = true
            statusLabel.stringValue = L10n.tr("Brak otwartych okien — Plik › Nowy")
        }
    }
}

extension DocumentAreaViewController {
    /// Stan Git pliku aktywnego okna — liczony w tle przy zmianie pliku albo po zapisie (zmiana `isModified`).
    func refreshGit(file: URL?, modified: Bool) {
        let key = file.map { "\($0.path)|\(modified)" }
        guard key != gitKey else { return }
        gitKey = key
        guard let file else { gitLabel.stringValue = ""; return }
        Task { [weak self] in
            let info = await Task.detached { () -> (String?, GitFileState?)? in
                guard let repo = GitRepository.discover(for: file), let s = try? repo.status() else { return nil }
                return (s.branch, s.state(of: file))
            }.value
            guard let self, self.gitKey == key else { return }
            if let (branch, state) = info {
                let mark = state.map { $0 == .unmodified ? "" : " · " + $0.displayName } ?? ""
                self.gitLabel.stringValue = "⎇ " + (branch ?? L10n.tr("(odłączony HEAD)")) + mark
                self.gitLabel.toolTip = L10n.tr("Git: gałąź i stan pliku")
            } else {
                self.gitLabel.stringValue = ""
            }
        }
    }

    /// Menu karty (PD-UI-004): zamknij, zamknij pozostałe / z lewej / z prawej.
    func tabMenu(for doc: Document) -> NSMenu {
        let menu = NSMenu()
        for (title, id) in [(L10n.tr("Zamknij"), "file.closeWindow"), (L10n.tr("Zamknij pozostałe"), "file.closeOthers"),
                            (L10n.tr("Zamknij z lewej"), "file.closeLeft"), (L10n.tr("Zamknij z prawej"), "file.closeRight")] {
            let item = menu.addItem(withTitle: title, action: #selector(tabMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [id, doc.id.description]
        }
        return menu
    }

    @objc func tabMenuAction(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        if pair[0] == "file.closeWindow" {
            workspace.perform("file.closeWindow", CommandArguments(["document": .string(pair[1])]))
        } else {
            if let d = workspace.documents.first(where: { $0.id.description == pair[1] }) { workspace.activate(d.id) }
            workspace.perform(CommandID(rawValue: pair[0]))
        }
    }

    @objc func chooseConnection(_ sender: NSButton) {
        guard let doc = workspace.activeDocument else { return }
        let menu = NSMenu()
        let mainName = workspace.sessions.mainConnectionID.flatMap { workspace.connections.connection($0)?.displayName } ?? L10n.tr("brak")
        let main = menu.addItem(withTitle: L10n.tr("Połączenie główne (\(mainName))"), action: #selector(selectConnection(_:)), keyEquivalent: "")
        main.representedObject = ""
        main.target = self
        main.state = doc.connectionID == nil ? .on : .off
        menu.addItem(.separator())
        for c in workspace.connections.connections.sorted(by: ConnectionStore.alphabetical) {
            let item = menu.addItem(withTitle: c.displayName + " (\(c.environment.shortName))", action: #selector(selectConnection(_:)), keyEquivalent: "")
            item.representedObject = c.id.uuidString
            item.target = self
            item.state = doc.connectionID == c.id ? .on : .off
        }
        menu.addItem(.separator())
        let pin = menu.addItem(withTitle: L10n.tr("Przypnij połączenie okna"), action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        pin.state = doc.connectionPinned ? .on : .off
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func selectConnection(_ sender: NSMenuItem) {
        workspace.perform("session.windowConnection", CommandArguments(["connection": .string(sender.representedObject as? String ?? "")]))
    }

    @objc func togglePin() {
        workspace.perform("session.pinWindowConnection")
    }

    /// Połączenie okna na pasku stanu (UG 20.2): opis, środowisko, przypięcie.
    func connectionDescription(for doc: Document) -> String {
        guard let id = workspace.effectiveConnection(of: doc), let c = workspace.connections.connection(id) else {
            return L10n.tr("Brak połączenia")
        }
        var s = c.displayName
        if c.environment != .other { s += " (\(c.environment.shortName))" }
        if doc.connectionPinned { s = "📌 " + s }
        if c.readOnly { s += " · " + L10n.tr("tylko odczyt") }
        return s
    }
}

/// Karta dokumentu: kolorowy znacznik typu (NF12), tytuł, przycisk zamknięcia; środkowy klik zamyka (NF15).
final class DocumentTabButton: NSView {
    private let onSelect: () -> Void
    private let onClose: () -> Void

    init(document: Document, isActive: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = isActive ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
        let fonts = InterfaceFonts.shared
        let marker = NSTextField(labelWithString: document.kind.shortName)
        marker.font = .monospacedSystemFont(ofSize: fonts.label.pointSize, weight: .bold)
        marker.textColor = Self.color(for: document.kind)
        let title = NSTextField(labelWithString: (document.isModified ? "● " : "") + document.title)
        title.font = AppFonts.font(family: fonts.family, size: AppFonts.reduced(fonts.size, by: 1), weight: isActive ? .semibold : fonts.weight)
        title.lineBreakMode = .byTruncatingMiddle
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L10n.tr("Zamknij"))!,
                             target: nil, action: nil)
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.target = self
        close.action = #selector(closeTapped)
        let stack = NSStackView(views: [marker, title, close])
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            close.widthAnchor.constraint(equalToConstant: 14),
        ])
        toolTip = document.fullTitle
        // Karta jako element dostępności (VoiceOver): przycisk wyboru z akcją „naciśnij” i akcją zamknięcia (R4-15).
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(document.fullTitle)
        setAccessibilityValue(NSNumber(value: isActive ? 1 : 0))
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: L10n.tr("Zamknij")) { [weak self] in
            self?.onClose()
            return true
        }])
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect()
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func color(for kind: DocumentKind) -> NSColor {
        switch kind {
        case .sql: .systemBlue
        case .program: .systemOrange
        case .test: .systemGreen
        case .command: .systemGray
        case .explainPlan: .systemPurple
        case .report: .systemTeal
        case .diagram: .systemPink
        case .notebook: .systemIndigo
        }
    }

    override func mouseDown(with event: NSEvent) { onSelect() }
    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { onClose() } }
    @objc private func closeTapped() { onClose() }
}
