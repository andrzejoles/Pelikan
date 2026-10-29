import AppKit
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
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = c.descriptor.title.replacingOccurrences(of: "…", with: "")
        item.paletteLabel = c.descriptor.title
        item.toolTip = c.descriptor.summary
        item.image = NSImage(systemSymbolName: ToolbarModel.symbol(for: command), accessibilityDescription: c.descriptor.title)
        item.target = self
        item.action = #selector(runCommand(_:))
        return item
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

    /// Okno dostosowania paska (komenda `view.customizeToolbar`).
    func customize() {
        toolbar?.runCustomizationPalette(nil)
    }
}
