import AppKit
import PelikanSQL
import PelikanWorkspace

/// Pasek narzędzi okna głównego (PD-UI-006): komendy z rejestru (`ToolbarModel`), dostosowanie standardowe macOS
/// z zapamiętaniem układu i grupa „Szybki dostęp” z listą komend z Preferencji.
@MainActor
final class MainToolbarController: NSObject, NSToolbarDelegate, NSToolbarItemValidation {
    static let quickAccess = NSToolbarItem.Identifier(ToolbarModel.quickAccessItem)
    static let tabGroups = NSToolbarItem.Identifier(ToolbarModel.tabGroupsItem)
    private let workspace: Workspace
    private weak var toolbar: NSToolbar?
    private var token: ObservationToken?
    private var formatToken: ObservationToken?
    /// Przełączniki formatowania przy Enter (pasek i szybki dostęp) — stan odświeżany przy zmianie ustawienia.
    private var formatButtons: [WeakButton] = []

    init(workspace: Workspace, toolbar: NSToolbar) {
        self.workspace = workspace
        self.toolbar = toolbar
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        token = trackChanges { [weak self] in
            guard let self else { return }
            _ = self.workspace.settings.quickAccessCommands
            self.refreshQuickAccess()
        }
        formatToken = trackChanges { [weak self] in
            guard let self else { return }
            _ = self.workspace.settings.beautifier.formatOnEnter
            _ = self.workspace.keymap
            self.refreshFormatButtons()
        }
    }

    private func identifier(_ s: String) -> NSToolbarItem.Identifier {
        s == ToolbarModel.flexibleSpaceItem ? .flexibleSpace : NSToolbarItem.Identifier(s)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ToolbarModel.defaultItems.map(identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ToolbarModel.paletteCommands.map(identifier) + [Self.tabGroups, Self.quickAccess, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == Self.tabGroups {
            // Kapsułki grup kart (D200): bez grup (jedna grupa) element ukryty — pasek jak dotąd.
            let item = NSToolbarItem(itemIdentifier: id)
            let bar = TabGroupBar(workspace: workspace)
            item.view = bar
            item.label = L10n.tr("Grupy kart")
            item.paletteLabel = L10n.tr("Grupy kart")
            item.visibilityPriority = .high
            item.autovalidates = false
            item.isHidden = workspace.tabGroups.count < 2
            bar.onGroupCountChange = { [weak item, weak self] count in
                item?.isHidden = count < 2
                self?.onTabGroupsChange?()
            }
            // Element w menu przepełnienia paska: „Grupy kart” z listą grup.
            let form = NSMenuItem(title: L10n.tr("Grupy kart"), action: nil, keyEquivalent: "")
            item.menuFormRepresentation = form
            bar.onReload = { [weak bar, weak form] in form?.submenu = bar?.groupsMenu() }
            form.submenu = bar.groupsMenu()
            return item
        }
        if id == Self.quickAccess {
            let group = NSToolbarItemGroup(itemIdentifier: id)
            group.label = L10n.tr("Szybki dostęp")
            group.paletteLabel = L10n.tr("Szybki dostęp")
            group.controlRepresentation = .expanded
            group.subitems = quickAccessItems()
            return group
        }
        return commandItem(id.rawValue, identifier: id)
    }

    private func commandItem(_ command: String, identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard let c = workspace.registry.command(CommandID(rawValue: command)) else { return nil }
        if command == ToolbarModel.formatOnEnterItem { return formatToggleItem(c.descriptor, identifier: identifier) }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = c.descriptor.title.replacingOccurrences(of: "…", with: "")
        item.paletteLabel = c.descriptor.title
        item.toolTip = c.descriptor.summary
        item.image = NSImage(systemSymbolName: ToolbarModel.symbol(for: command), accessibilityDescription: c.descriptor.title)
        item.target = self
        item.action = #selector(runCommand(_:))
        return item
    }

    /// Przełącznik formatowania przy Enter (D205): przycisk ze stanem (włączony — wciśnięty, wyłączony — przekreślona
    /// różdżka), podpowiedź ze stanem i skrótem, dla VoiceOver wartość „włączone/wyłączone”.
    private func formatToggleItem(_ d: CommandDescriptor, identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = L10n.tr("Formatowanie przy Enter")
        item.paletteLabel = L10n.tr("Formatowanie przy Enter")
        let button = NSButton(image: NSImage(), target: self, action: #selector(toggleFormatOnEnter(_:)))
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .toolbar
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(L10n.tr("Formatowanie przy Enter"))
        item.view = button
        item.autovalidates = false
        let form = NSMenuItem(title: L10n.tr("Formatowanie przy Enter"), action: #selector(toggleFormatOnEnter(_:)), keyEquivalent: "")
        form.target = self
        item.menuFormRepresentation = form
        formatButtons.removeAll { $0.button == nil }
        formatButtons.append(WeakButton(button: button, menuItem: form))
        refreshFormatButtons()
        return item
    }

    private func refreshFormatButtons() {
        let on = workspace.settings.beautifier.formatOnEnter
        let state = on ? L10n.tr("włączone") : L10n.tr("wyłączone")
        var tip = L10n.tr("Formatowanie przy Enter: \(state)") + "\n"
            + L10n.tr("Enter formatuje opuszczaną linię i wcina nową według reguł formatera; istniejący kod — tylko na żądanie (Formatuj kod).")
        if let chord = workspace.keymap.chords(for: CommandID(rawValue: ToolbarModel.formatOnEnterItem)).first {
            tip += "\n" + L10n.tr("Skrót: \(chord.displayString)")
        }
        let image = Self.formatImage(on: on)
        for ref in formatButtons {
            guard let b = ref.button else { continue }
            b.state = on ? .on : .off
            b.image = image
            b.toolTip = tip
            b.setAccessibilityValue(state)
            ref.menuItem?.state = on ? .on : .off
        }
    }

    /// Różdżka; wyłączone — przekreślona (symbol bez wariantu z kreską).
    static func formatImage(on: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let base = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return NSImage() }
        guard !on else { return base }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let slash = NSBezierPath()
            slash.lineWidth = 1.6
            slash.lineCapStyle = .round
            // Kreska w poprzek różdżki (ta biegnie od lewej u góry w prawo w dół).
            slash.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1))
            slash.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
            NSColor.black.setStroke()
            slash.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func toggleFormatOnEnter(_ sender: Any?) {
        workspace.perform(CommandID(rawValue: ToolbarModel.formatOnEnterItem))
    }

    private func quickAccessItems() -> [NSToolbarItem] {
        ToolbarModel.sanitized(workspace.settings.quickAccessCommands, in: workspace).compactMap {
            commandItem($0, identifier: NSToolbarItem.Identifier("qa." + $0))
        }
    }

    private func refreshQuickAccess() {
        guard let group = toolbar?.items.first(where: { $0.itemIdentifier == Self.quickAccess }) as? NSToolbarItemGroup else { return }
        group.subitems = quickAccessItems()
    }

    private func command(of item: NSToolbarItem) -> String {
        let raw = item.itemIdentifier.rawValue
        return raw.hasPrefix("qa.") ? String(raw.dropFirst(3)) : raw
    }

    @objc func runCommand(_ sender: NSToolbarItem) {
        workspace.perform(CommandID(rawValue: command(of: sender)))
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        // Kapsułki grup to nie komenda — zawsze dostępne (wyłączony element szarzałby nazwy grup).
        if item.itemIdentifier == Self.tabGroups { return true }
        return workspace.isEnabled(CommandID(rawValue: command(of: item)))
    }

    func toolbarWillAddItem(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onTabGroupsChange?() }
    }

    func toolbarDidRemoveItem(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onTabGroupsChange?() }
    }

    /// Zmiana widoczności kapsułek grup (mała kapsułka na pasku kart, gdy pasek narzędzi ich nie pokazuje).
    var onTabGroupsChange: (() -> Void)?

    /// Czy kapsułki grup są na widocznym pasku narzędzi (nie: pasek ukryty, element usunięty, pełny ekran).
    func showsTabGroups(fullScreen: Bool) -> Bool {
        guard let toolbar, toolbar.isVisible, !fullScreen else { return false }
        // Element w menu przepełnienia paska (wąskie okno) nie pokazuje kapsułek — wtedy mała kapsułka na pasku kart.
        return (toolbar.visibleItems ?? []).contains { $0.itemIdentifier == Self.tabGroups && !$0.isHidden }
    }

    /// Element grup dodany raz do zapamiętanego układu paska (układ sprzed wersji z grupami go nie ma); usunięty potem
    /// przez użytkownika w dostosowaniu paska — zostaje usunięty.
    func ensureTabGroupsItem() {
        let key = "Pelikan.toolbar.tabGroupsAdded"
        guard let toolbar, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !toolbar.items.contains(where: { $0.itemIdentifier == Self.tabGroups }) {
            toolbar.insertItem(withItemIdentifier: Self.tabGroups, at: 0)
        }
    }

    /// Przełącznik formatowania przy Enter dodany raz do zapamiętanego układu paska (sprzed D205) — przed logowaniem
    /// albo na końcu; usunięty potem przez użytkownika — zostaje usunięty.
    func ensureFormatOnEnterItem() {
        let key = "Pelikan.toolbar.formatOnEnterAdded"
        let id = NSToolbarItem.Identifier(ToolbarModel.formatOnEnterItem)
        guard let toolbar, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !toolbar.items.contains(where: { $0.itemIdentifier == id }) else { return }
        let logon = toolbar.items.firstIndex { $0.itemIdentifier.rawValue == "session.logon" }
        toolbar.insertItem(withItemIdentifier: id, at: logon ?? toolbar.items.count)
    }

    /// Okno dostosowania paska (komenda `view.customizeToolbar`).
    func customize() {
        toolbar?.runCustomizationPalette(nil)
    }
}

/// Słabe odwołanie do przełącznika na pasku (element usunięty z paska znika z listy).
private struct WeakButton {
    weak var button: NSButton?
    weak var menuItem: NSMenuItem?
}
