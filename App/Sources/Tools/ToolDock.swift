import AppKit
import PelikanWorkspace
import SwiftUI

// MARK: - Cykl życia narzędzia w SwiftUI

/// Koniec życia narzędzia: zamknięcie karty panelu albo okna (PD-UI-003, D183). Przeniesienie narzędzia między panelem
/// a oknem wyjmuje widok z jednego okna i wkłada do drugiego — SwiftUI wywołuje wtedy onDisappear/onAppear i przerywa
/// `.task`. Czynności „przy zamknięciu” (przerwanie wyszukiwania, zatrzymanie monitora) rejestrują się tutaj.
@MainActor
final class ToolLifetime {
    private var handlers: [UUID: () -> Void] = [:]
    private var ended = false
    /// Zawartość narzędzia (ustawiana przy otwarciu) — do sprawdzenia, czy narzędzie widać.
    weak var content: NSView?

    /// Narzędzie widać: karta wybrana w rozwiniętym panelu (karty i zwinięty panel chowają widoki) albo okno
    /// niezminimalizowane. Pętle auto-odświeżania (Sesje, Instance Viewer, wykres) nie odpytują wtedy bazy na próżno.
    var isVisible: Bool {
        guard let content else { return true }
        guard let window = content.window else { return false }
        return window.isVisible && !window.isMiniaturized && !content.isHiddenOrHasHiddenAncestor
    }

    func register(_ id: UUID, _ handler: @escaping () -> Void) {
        if !ended { handlers[id] = handler }
    }

    func end() {
        guard !ended else { return }
        ended = true
        let all = handlers.values
        handlers = [:]
        all.forEach { $0() }
    }
}

extension EnvironmentValues {
    @Entry var toolLifetime: ToolLifetime? = nil
}

private struct OnToolClose: ViewModifier {
    @Environment(\.toolLifetime) private var lifetime
    @State private var id = UUID()
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { lifetime?.register(id, action) }
            // Widok poza narzędziem (bez cyklu życia) — jak dotąd przy zniknięciu.
            .onDisappear { if lifetime == nil { action() } }
    }
}

private struct ToolTask<ID: Equatable>: ViewModifier {
    let id: ID
    let action: @MainActor () async -> Void
    @State private var completed: ID?

    func body(content: Content) -> some View {
        content.task(id: id) {
            guard completed != id else { return }
            await action()
            if !Task.isCancelled { completed = id }
        }
    }
}

private struct OnFirstAppear: ViewModifier {
    @State private var done = false
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            guard !done else { return }
            done = true
            action()
        }
    }
}

extension View {
    /// Czynność przy zamknięciu narzędzia (nie przy przeniesieniu między panelem a oknem).
    func onToolClose(perform action: @escaping () -> Void) -> some View { modifier(OnToolClose(action: action)) }

    /// `.task(id:)` wykonywane raz dla wartości `id`: ponowne pojawienie się po przeniesieniu narzędzia nie wczytuje
    /// danych od nowa ani nie nadpisuje pól wypełnionych przez użytkownika; przerwane zadanie wykona się ponownie.
    func toolTask<ID: Equatable>(id: ID, _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(ToolTask(id: id, action: action))
    }

    /// `onAppear` tylko za pierwszym razem (stan początkowy pól narzędzia).
    func onFirstAppear(perform action: @escaping () -> Void) -> some View { modifier(OnFirstAppear(action: action)) }
}

// MARK: - Narzędzie

/// Otwarte narzędzie: zawartość (widok SwiftUI albo AppKit) i jej bieżące miejsce — panel okna głównego albo okno.
@MainActor
final class ToolItem {
    let key: String
    let title: String
    let size: NSSize
    let content: NSView
    let lifetime: ToolLifetime
    /// Kontroler AppKit narzędzia (trzymany, dopóki narzędzie jest otwarte).
    let owner: AnyObject?
    fileprivate(set) var placement: ToolPlacement = .floating
    fileprivate var placed = false
    fileprivate var window: ToolFloatingWindowController?

    init(key: String, title: String, size: NSSize, content: NSView, lifetime: ToolLifetime, owner: AnyObject?) {
        self.key = key
        self.title = title
        self.size = size
        self.content = content
        self.lifetime = lifetime
        self.owner = owner
        lifetime.content = content
    }

    /// Najmniejszy rozmiar zawartości (minimalna ramka widoku SwiftUI, ograniczenia AppKit) — w panelu, po wstawieniu.
    var minimumSize: NSSize { content.fittingSize }

    /// Rozmiar wg zawartości w panelu (tylko minimum — panel przewija mniejszą zawartość) albo w oknie (rozmiar okna
    /// z treści, jak dotąd). W panelu bez obszarów bezpiecznych okna: zawartość nie leży pod paskiem tytułu.
    fileprivate func prepare(docked: Bool) {
        content.removeFromSuperview()
        if let hosting = content as? NSHostingView<AnyView> {
            hosting.sizingOptions = docked ? [.minSize] : .standardBounds
            hosting.safeAreaRegions = docked ? [] : .all
        }
        content.translatesAutoresizingMaskIntoConstraints = !docked
    }
}

// MARK: - Menedżer

/// Narzędzia w panelach okna głównego i w osobnych oknach (PD-UI-003, D183): jedno narzędzie danego klucza; miejsce
/// nowego narzędzia z ustawień (domyślnie panel po prawej), przenoszenie komendami `view.dockTool…`/`view.floatTool`.
@MainActor
@Observable
final class ToolDockManager {
    static let shared = ToolDockManager()
    static let pasteboardType = NSPasteboard.PasteboardType("local.pelikan.tool")

    @ObservationIgnored var workspace: Workspace?
    @ObservationIgnored weak var mainWindow: MainWindowController?
    /// Punkt ekranu dla okna narzędzia odłączonego przeciągnięciem karty poza panel.
    @ObservationIgnored var nextFloatOrigin: NSPoint?
    @ObservationIgnored private var items: [String: ToolItem] = [:]
    @ObservationIgnored private var lastActive: String?
    /// Zmiana zawartości albo widoczności paneli (pasek stanu pokazuje przyciski zwiniętych paneli).
    private(set) var revision = 0

    private init() {}

    var openKeys: [String] { items.keys.sorted() }

    func item(_ key: String) -> ToolItem? { items[key] }

    /// Liczba narzędzi w panelu (odczyt śledzony — do odświeżania paska stanu).
    func count(in placement: ToolPlacement) -> Int {
        _ = revision
        return items.values.filter { $0.placed && $0.placement == placement }.count
    }

    func noteChange() { revision += 1 }

    /// Przywołuje otwarte narzędzie; false — narzędzia o tym kluczu nie ma.
    @discardableResult
    func reveal(key: String) -> Bool {
        guard let item = items[key] else { return false }
        reveal(item)
        return true
    }

    func show(key: String, title: String, size: NSSize, content: NSView, lifetime: ToolLifetime = ToolLifetime(), owner: AnyObject? = nil) {
        if reveal(key: key) { return }
        let item = ToolItem(key: key, title: title, size: size, content: content, lifetime: lifetime, owner: owner)
        items[key] = item
        move(item, to: workspace?.settings.toolDock.placement(for: key) ?? .right)
        reveal(item)
    }

    func close(key: String) {
        guard let item = items.removeValue(forKey: key) else { return }
        detach(item)
        if lastActive == key { lastActive = nil }
        item.lifetime.end()
        noteChange()
    }

    /// Przenosi narzędzie; zwraca jego klucz (nil — brak narzędzia).
    @discardableResult
    func place(_ key: String?, at placement: ToolPlacement) -> String? {
        guard let key = key ?? currentKey(), let item = items[key] else { return nil }
        move(item, to: placement)
        reveal(item)
        return key
    }

    /// Narzędzie, którego dotyczą komendy bez argumentu: okno narzędzia na wierzchu, karta panelu z fokusem,
    /// ostatnio używane.
    func currentKey() -> String? {
        if let c = NSApp.keyWindow?.windowController as? ToolFloatingWindowController, items[c.item.key] === c.item { return c.item.key }
        if let key = focusedDockedKey() { return key }
        if let key = lastActive, items[key] != nil { return key }
        return nil
    }

    /// Karta panelu, w której jest fokus okna głównego (⌘W zamyka wtedy narzędzie, nie okno dokumentu).
    func focusedDockedKey() -> String? {
        guard let main = mainWindow, main.window?.isKeyWindow == true, let responder = main.window?.firstResponder as? NSView else { return nil }
        for p in [ToolPlacement.right, .bottom] {
            let dock = main.dock(p)
            if dock.isViewLoaded, responder.isDescendant(of: dock.view) { return dock.selectedKey }
        }
        return nil
    }

    func noteActive(_ key: String) { lastActive = key }

    func toggle(_ placement: ToolPlacement) {
        guard placement != .floating, let main = mainWindow else { return }
        main.setDock(placement, visible: !main.isDockVisible(placement))
    }

    /// Okno narzędzia zamknięte przez użytkownika.
    fileprivate func floatingWindowClosed(_ item: ToolItem) {
        guard items[item.key] === item else { return }
        item.window = nil
        item.placed = false
        close(key: item.key)
    }

    private func move(_ item: ToolItem, to requested: ToolPlacement) {
        // Bez okna głównego (np. zamknięte) narzędzie otwiera się w oknie.
        let placement: ToolPlacement = mainWindow == nil ? .floating : requested
        if item.placed, item.placement == placement { return }
        detach(item)
        item.placement = placement
        switch placement {
        case .floating:
            item.window = ToolFloatingWindowController(item: item, origin: nextFloatOrigin, dockable: mainWindow != nil)
            nextFloatOrigin = nil
        case .right, .bottom:
            mainWindow?.dock(placement).add(item)
        }
        item.placed = true
        noteChange()
    }

    private func detach(_ item: ToolItem) {
        guard item.placed else { return }
        item.placed = false
        switch item.placement {
        case .floating:
            item.window?.detach()
            item.window = nil
        case .right, .bottom:
            guard let main = mainWindow else { return }
            let dock = main.dock(item.placement)
            dock.remove(item)
            if dock.items.isEmpty { main.setDock(item.placement, visible: false) }
        }
    }

    private func reveal(_ item: ToolItem) {
        lastActive = item.key
        switch item.placement {
        case .floating:
            item.window?.showWindow(nil)
        case .right, .bottom:
            guard let main = mainWindow else { return }
            main.dock(item.placement).select(item)
            main.setDock(item.placement, visible: true, fitting: item)
            main.window?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Panel

/// Panel narzędzi okna głównego (prawy albo dolny): karty narzędzi, przyciski odłączenia, przeniesienia i ukrycia;
/// upuszczenie karty z drugiego panelu dokuje narzędzie tutaj.
@MainActor
final class ToolDockViewController: NSViewController {
    let placement: ToolPlacement
    private let workspace: Workspace
    private(set) var items: [ToolItem] = []
    private(set) var selectedKey: String?
    private let tabs = NSStackView()
    private let container = NSView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private var wrappers: [String: NSScrollView] = [:]
    private var buttons: [NSButton] = []

    init(placement: ToolPlacement, workspace: Workspace) {
        self.placement = placement
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = ToolDropView()
        root.onDrop = { [weak self] key in
            guard let self else { return }
            self.workspace.perform(self.placement == .right ? "view.dockToolRight" : "view.dockToolBottom", CommandArguments(["tool": .string(key)]))
        }
        let background = SolidBackgroundView(material: .sidebar)
        tabs.orientation = .horizontal
        tabs.spacing = 2
        tabs.alignment = .centerY
        tabs.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        let tabScroll = NSScrollView()
        tabScroll.documentView = tabs
        tabScroll.hasHorizontalScroller = false
        tabScroll.drawsBackground = false
        let other: (String, CommandID, String) = placement == .right
            ? ("dock.arrow.down.rectangle", "view.dockToolBottom", L10n.tr("Przenieś narzędzie na dół"))
            : ("rectangle.righthalf.inset.filled", "view.dockToolRight", L10n.tr("Przenieś narzędzie w prawo"))
        buttons = [
            button("macwindow.on.rectangle", L10n.tr("Odłącz narzędzie do osobnego okna"), "view.floatTool"),
            button(other.0, other.2, other.1),
            button(placement == .right ? "chevron.right" : "chevron.down", L10n.tr("Ukryj panel"),
                   placement == .right ? "view.toolDockRight" : "view.toolDockBottom", withTool: false),
        ]
        let buttonStack = NSStackView(views: buttons)
        buttonStack.spacing = 2
        let separator = NSBox()
        separator.boxType = .separator
        emptyLabel.stringValue = L10n.tr("Brak narzędzi w panelu. Przeciągnij tu kartę narzędzia albo wybierz Widok › Panele narzędzi.")
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        for v in [background, tabScroll, buttonStack, separator, container, emptyLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: root.topAnchor),
            background.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabScroll.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            tabScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: buttonStack.leadingAnchor, constant: -4),
            { let c = tabScroll.heightAnchor.constraint(equalToConstant: 30); c.priority = .defaultHigh; return c }(),
            tabs.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor),
            tabs.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor),
            tabs.heightAnchor.constraint(equalTo: tabScroll.contentView.heightAnchor),
            buttonStack.centerYAnchor.constraint(equalTo: tabScroll.centerYAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            separator.topAnchor.constraint(equalTo: tabScroll.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: separator.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.group)
        root.setAccessibilityLabel(placement == .right ? L10n.tr("Panel narzędzi po prawej") : L10n.tr("Panel narzędzi na dole"))
        view = root
        trackChanges { [weak self] in
            _ = InterfaceFonts.shared.small
            self?.rebuildTabs()
        }
    }

    private func button(_ symbol: String, _ tip: String, _ command: CommandID, withTool: Bool = true) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: nil, action: nil)
        b.isBordered = false
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.target = self
        b.action = #selector(buttonAction(_:))
        b.identifier = NSUserInterfaceItemIdentifier(command.rawValue + (withTool ? "|tool" : ""))
        return b
    }

    @objc private func buttonAction(_ sender: NSButton) {
        let parts = (sender.identifier?.rawValue ?? "").split(separator: "|").map(String.init)
        guard let id = parts.first else { return }
        var args: [String: JSONValue] = [:]
        if parts.count > 1 {
            guard let key = selectedKey else { return }
            args["tool"] = .string(key)
        }
        workspace.perform(CommandID(rawValue: id), CommandArguments(args))
    }

    func add(_ item: ToolItem) {
        _ = view
        item.prepare(docked: true)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(item.content)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.isHidden = true
        container.addSubview(scroll)
        let clip = scroll.contentView
        // Zawartość wypełnia panel, a gdy panel jest mniejszy od minimalnego rozmiaru narzędzia — przewija się.
        // Priorytet wypełnienia niższy niż trzymanie rozmiaru elementów podziału okna: inaczej minimum narzędzia
        // rozpychałoby panel.
        let fillWidth = document.widthAnchor.constraint(equalTo: clip.widthAnchor)
        fillWidth.priority = NSLayoutConstraint.Priority(200)
        let fillHeight = document.heightAnchor.constraint(equalTo: clip.heightAnchor)
        fillHeight.priority = NSLayoutConstraint.Priority(200)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.widthAnchor.constraint(greaterThanOrEqualTo: clip.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: clip.heightAnchor),
            fillWidth, fillHeight,
            item.content.topAnchor.constraint(equalTo: document.topAnchor),
            item.content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            item.content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            item.content.trailingAnchor.constraint(equalTo: document.trailingAnchor),
        ])
        wrappers[item.key] = scroll
        items.append(item)
        select(item)
    }

    func remove(_ item: ToolItem) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        item.content.removeFromSuperview()
        wrappers.removeValue(forKey: item.key)?.removeFromSuperview()
        if selectedKey == item.key {
            selectedKey = nil
            if !items.isEmpty { select(items[min(index, items.count - 1)]) }
        }
        rebuildTabs()
    }

    /// Widoczne narzędzie panelu, jeśli fokus okna jest poza nim (jego skróty nie powinny wtedy działać).
    func unfocusedContent(responder: NSResponder?) -> NSView? {
        guard let key = selectedKey, let wrapper = wrappers[key], !wrapper.isHidden else { return nil }
        if let view = responder as? NSView, view.isDescendant(of: wrapper) { return nil }
        return wrapper
    }

    func select(_ item: ToolItem) {
        selectedKey = item.key
        for (key, w) in wrappers { w.isHidden = key != item.key }
        ToolDockManager.shared.noteActive(item.key)
        rebuildTabs()
    }

    private func rebuildTabs() {
        guard isViewLoaded else { return }
        emptyLabel.isHidden = !items.isEmpty
        for b in buttons.prefix(2) { b.isEnabled = selectedKey != nil }
        tabs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let tab = ToolTabView(item: item, selected: item.key == selectedKey)
            tab.onSelect = { [weak self, weak item] in if let self, let item { self.select(item) } }
            tab.onClose = { [weak self] key in self?.workspace.perform("view.closeTool", CommandArguments(["tool": .string(key)])) }
            tab.menu = tabMenu(for: item.key)
            tabs.addArrangedSubview(tab)
        }
    }

    /// Menu karty: przeniesienie do drugiego panelu albo okna, zamknięcie (komendy z argumentem narzędzia).
    private func tabMenu(for key: String) -> NSMenu {
        let menu = NSMenu()
        var entries: [(String, CommandID)] = []
        if placement != .right { entries.append((L10n.tr("Zadokuj po prawej"), "view.dockToolRight")) }
        if placement != .bottom { entries.append((L10n.tr("Zadokuj na dole"), "view.dockToolBottom")) }
        entries.append((L10n.tr("Odłącz do osobnego okna"), "view.floatTool"))
        for (title, id) in entries {
            let item = menu.addItem(withTitle: title, action: #selector(menuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [id.rawValue, key]
        }
        menu.addItem(.separator())
        let close = menu.addItem(withTitle: L10n.tr("Zamknij"), action: #selector(menuAction(_:)), keyEquivalent: "")
        close.target = self
        close.representedObject = ["view.closeTool", key]
        return menu
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        workspace.perform(CommandID(rawValue: pair[0]), CommandArguments(["tool": .string(pair[1])]))
    }
}

/// Dokument przewijanej zawartości narzędzia — od góry, jak okno.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Korzeń panelu przyjmujący upuszczone karty narzędzi.
private final class ToolDropView: NSView {
    var onDrop: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([ToolDockManager.pasteboardType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: ToolDockManager.pasteboardType) == nil ? [] : .move
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let key = sender.draggingPasteboard.string(forType: ToolDockManager.pasteboardType) else { return false }
        onDrop?(key)
        return true
    }
}

/// Karta narzędzia: tytuł i przycisk zamknięcia; środkowy klik zamyka; przeciągnięcie do drugiego panelu dokuje tam
/// narzędzie, a upuszczenie poza panelami odłącza je do okna w miejscu upuszczenia.
private final class ToolTabView: NSView, NSDraggingSource {
    var onSelect: (() -> Void)?
    var onClose: ((String) -> Void)?
    private let key: String
    private var downPoint: NSPoint?

    init(item: ToolItem, selected: Bool) {
        key = item.key
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
        let fonts = InterfaceFonts.shared
        let title = NSTextField(labelWithString: item.title)
        title.font = AppFonts.font(family: fonts.family, size: AppFonts.reduced(fonts.size, by: 1), weight: selected ? .semibold : fonts.weight)
        title.lineBreakMode = .byTruncatingMiddle
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: L10n.tr("Zamknij")) ?? NSImage(),
                             target: nil, action: nil)
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.target = self
        close.action = #selector(closeTapped)
        let stack = NSStackView(views: [title, close])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            close.widthAnchor.constraint(equalToConstant: 14),
        ])
        toolTip = item.title
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(item.title)
        setAccessibilityValue(NSNumber(value: selected ? 1 : 0))
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: L10n.tr("Zamknij")) { [weak self] in
            guard let self else { return false }
            self.onClose?(self.key)
            return true
        }])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }

    override func mouseDown(with event: NSEvent) { downPoint = event.locationInWindow }

    override func mouseUp(with event: NSEvent) {
        if downPoint != nil { onSelect?() }
        downPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        downPoint = nil
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(key, forType: ToolDockManager.pasteboardType)
        let dragging = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = bitmapImageRepForCachingDisplay(in: bounds).map { rep -> NSImage in
            cacheDisplay(in: bounds, to: rep)
            let i = NSImage(size: bounds.size)
            i.addRepresentation(rep)
            return i
        }
        dragging.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { onClose?(key) } }

    @objc private func closeTapped() { onClose?(key) }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Upuszczona poza panelami: osobne okno w miejscu upuszczenia. Przeciąganie przerwane klawiszem Esc też kończy
        // się bez operacji — wtedy narzędzie zostaje na miejscu.
        guard operation == [], let workspace = ToolDockManager.shared.workspace else { return }
        if let event = NSApp.currentEvent, event.type == .keyDown, event.keyCode == 53 { return }
        ToolDockManager.shared.nextFloatOrigin = screenPoint
        workspace.perform("view.floatTool", CommandArguments(["tool": .string(key)]))
    }
}

// MARK: - Okno narzędzia

/// Osobne okno narzędzia; przycisk na pasku tytułu dokuje je w panelu okna głównego.
@MainActor
final class ToolFloatingWindowController: NSWindowController, NSWindowDelegate {
    let item: ToolItem
    private var detaching = false

    init(item: ToolItem, origin: NSPoint?, dockable: Bool) {
        self.item = item
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: item.size), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = item.title
        item.prepare(docked: false)
        w.contentView = item.content
        w.center()
        // Okna z kluczem jednorazowym (UUID, id dokumentu) bez zapamiętanej ramki — każde zostawiałoby wpis w UserDefaults.
        if ToolDockSettings.kind(of: item.key) == item.key { w.setFrameAutosaveName("Pelikan.\(item.key)") }
        if let origin { w.setFrameTopLeftPoint(origin) }
        super.init(window: w)
        w.delegate = self
        if dockable {
            let tip = L10n.tr("Zadokuj w oknie głównym")
            let b = NSButton(image: NSImage(systemSymbolName: "rectangle.righthalf.inset.filled", accessibilityDescription: tip) ?? NSImage(),
                             target: self, action: #selector(dockMenu(_:)))
            b.isBordered = false
            b.toolTip = tip
            b.frame = NSRect(x: 2, y: 0, width: 28, height: 22)
            // Widok dodatku paska tytułu w kontenerze o stałej ramce: AppKit nie pozwala przesuwać samego widoku
            // dodatku, a przycisk z układem ograniczeń był przesuwany (wyjątek „changing the view's origin”).
            let holder = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 22))
            holder.addSubview(b)
            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = holder
            accessory.layoutAttribute = .trailing
            w.addTitlebarAccessoryViewController(accessory)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func dockMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for (title, id) in [(L10n.tr("Zadokuj po prawej"), "view.dockToolRight"), (L10n.tr("Zadokuj na dole"), "view.dockToolBottom")] {
            let i = menu.addItem(withTitle: title, action: #selector(dock(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = id
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func dock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ToolDockManager.shared.workspace?.perform(CommandID(rawValue: id), CommandArguments(["tool": .string(item.key)]))
    }

    /// Oddaje zawartość (do panelu) i zamyka okno bez kończenia życia narzędzia.
    func detach() {
        detaching = true
        window?.contentView = NSView()
        close()
    }

    func windowWillClose(_ notification: Notification) {
        if !detaching { ToolDockManager.shared.floatingWindowClosed(item) }
    }

    func windowDidBecomeKey(_ notification: Notification) { ToolDockManager.shared.noteActive(item.key) }
}
