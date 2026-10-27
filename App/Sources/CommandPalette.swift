import AppKit
import PelikanWorkspace

/// Paleta komend (PD-UI-007): wyszukiwanie po nazwie, identyfikatorze i kategorii; Enter wykonuje, Esc zamyka.
final class CommandPalette: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let workspace: Workspace
    private let panel: NSPanel
    private let search = NSSearchField()
    private let table = NSTableView()
    private var items: [CommandDescriptor] = []
    /// Nazwy komend w innym języku — jak w „Szukaj czynności” (liczone raz).
    private lazy var alternates = CommandSearch.alternateTitles(workspace.registry.descriptors)

    init(workspace: Workspace) {
        self.workspace = workspace
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                        styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.delegate = self

        search.placeholderString = L10n.tr("Wpisz nazwę komendy…")
        search.delegate = self
        search.sendsSearchStringImmediately = true
        for (id, title, width) in [("title", L10n.tr("Komenda"), 330.0), ("menu", L10n.tr("Menu"), 110.0), ("key", L10n.tr("Skrót"), 90.0)] {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title
            c.width = width
            table.addTableColumn(c)
        }
        table.headerView = nil
        table.setAccessibilityLabel(L10n.tr("Komendy"))
        table.rowSizeStyle = .custom
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(runSelected)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let stack = NSStackView(views: [search, scroll])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 12, bottom: 12, right: 12)
        panel.contentView = stack
    }

    func show(relativeTo window: NSWindow?) {
        search.stringValue = ""
        filter()
        if let frame = window?.frame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 80))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    private func filter() {
        // Kandydaci, kolejność i dopasowanie jak w „Szukaj czynności” na wstążce (bez komend pomocniczych i agenta, bez
        // polskich znaków, słowa kluczowe, angielskie nazwy — PD-UI-012, R4-12).
        let all = CommandSearch.userCommands(workspace.registry.descriptors)
        items = search.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? all
            : CommandSearch.search(search.stringValue, in: all, limit: all.count) { [alternates] in alternates[$0.id] ?? [] }.map(\.descriptor)
        table.rowHeight = AppFonts.rowHeight(for: InterfaceFonts.shared.body)
        table.reloadData()
        if let first = CommandSearch.firstAvailable(items, isEnabled: { workspace.isEnabled($0) }) {
            table.selectRowIndexes(IndexSet(integer: first), byExtendingSelection: false)
            table.scrollRowToVisible(first)
        }
    }

    func controlTextDidChange(_ obj: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
        case #selector(NSResponder.insertNewline(_:)): runSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)): panel.orderOut(nil); return true
        default: return false
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let row = max(0, min(items.count - 1, table.selectedRow + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func runSelected() {
        let row = table.selectedRow
        guard row >= 0, row < items.count else { return }
        // Niedostępnej teraz komendy nie wykonuje (jak „Szukaj czynności”).
        guard workspace.isEnabled(items[row].id) else { NSSound.beep(); return }
        panel.orderOut(nil)
        workspace.perform(items[row].id)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let d = items[row]
        let enabled = workspace.isEnabled(d.id)
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "menu": text = d.category.displayName
        case "key": text = workspace.keymap.chords(for: d.id).first?.displayString ?? ""
        default: text = d.submenu.map { "\($0) › \(d.title)" } ?? d.title
        }
        let label = NSTextField(labelWithString: text)
        label.font = tableColumn?.identifier.rawValue == "title" ? InterfaceFonts.shared.body : InterfaceFonts.shared.small
        label.textColor = enabled ? (tableColumn?.identifier.rawValue == "title" ? .labelColor : .secondaryLabelColor) : .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func windowDidResignKey(_ notification: Notification) { panel.orderOut(nil) }
}
