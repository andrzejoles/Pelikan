import AppKit
import PelikanWorkspace

/// Pasek narzędzi okna głównego (PD-UI-006): komendy z rejestru (`ToolbarModel`), dostosowanie standardowe macOS
/// z zapamiętaniem układu i grupa „Szybki dostęp” z listą komend z Preferencji.
@MainActor
final class MainToolbarController: NSObject, NSToolbarDelegate, NSToolbarItemValidation {
    static let quickAccess = NSToolbarItem.Identifier(ToolbarModel.quickAccessItem)
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
        ToolbarModel.paletteCommands.map(identifier) + [Self.quickAccess, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
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
        workspace.isEnabled(CommandID(rawValue: command(of: item)))
    }

    /// Okno dostosowania paska (komenda `view.customizeToolbar`).
    func customize() {
        toolbar?.runCustomizationPalette(nil)
    }
}
