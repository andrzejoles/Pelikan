import AppKit
import PelikanWorkspace

/// Lista podpowiedzi Code Assistant (UG 25.4): panel podrzędny pod kursorem, ↑/↓ wybór, Enter/Tab wstawia,
/// Esc zamyka; pisanie dalej zawęża listę (ponowne zapytanie o podpowiedzi przy każdej zmianie tekstu).
@MainActor
final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private weak var textView: NSTextView?
    private let panel: NSPanel
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var result: CompletionResult?
    /// Ponowne pobranie podpowiedzi dla bieżącego tekstu i kursora (wynik nil — zamknięcie).
    var requery: (() async -> CompletionResult?)?
    /// Numer zapytania — odpowiedź dla starszego prefiksu (wolniejsza) nie nadpisze nowszej ani nie otworzy zamkniętej listy.
    private var generation = 0
    private var resignObserver: (any NSObjectProtocol)?

    var isVisible: Bool { panel.isVisible }

    init(textView: NSTextView) {
        self.textView = textView
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        super.init()
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        let c = NSTableColumn(identifier: .init("item"))
        c.resizingMask = .autoresizingMask
        table.addTableColumn(c)
        table.headerView = nil
        table.rowSizeStyle = .small
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(accept)
        table.setAccessibilityLabel(L10n.tr("Podpowiedzi kodu"))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.frame = background.bounds
        scroll.autoresizingMask = [.width, .height]
        background.addSubview(scroll)
        panel.contentView = background
    }

    func show(_ r: CompletionResult) {
        guard let tv = textView, let window = tv.window else { return }
        result = r
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)
        let rowHeight = table.numberOfRows > 0 ? table.rect(ofRow: 0).height : table.rowHeight + table.intercellSpacing.height
        let height = min(CGFloat(r.items.count), 10) * rowHeight + 10
        // Pozycja: pod początkiem zastępowanego fragmentu.
        let anchor = tv.firstRect(forCharacterRange: NSRange(location: r.replaceRange.lowerBound, length: 0), actualRange: nil)
        var frame = NSRect(x: anchor.minX - 4, y: anchor.minY - height - 2, width: 380, height: height)
        if let screen = window.screen?.visibleFrame, frame.minY < screen.minY { frame.origin.y = anchor.maxY + 2 }
        // Lista w granicach okna edytora.
        if frame.maxX > window.frame.maxX - 8 { frame.origin.x = max(window.frame.minX + 8, window.frame.maxX - 8 - frame.width) }
        panel.setFrame(frame, display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        // Inne okno aplikacji albo inna aplikacja — lista znika (klawisze trafiałyby już gdzie indziej, R4-13).
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
    }

    func close() {
        generation += 1
        if let o = resignObserver {
            NotificationCenter.default.removeObserver(o)
            resignObserver = nil
        }
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        result = nil
    }

    /// Klawisze obsługiwane przez otwartą listę; zwraca true, gdy zdarzenie zostało zużyte.
    func handle(_ event: NSEvent) -> Bool {
        guard panel.isVisible, let r = result else { return false }
        switch event.keyCode {
        case 125: move(1, count: r.items.count); return true          // ↓
        case 126: move(-1, count: r.items.count); return true         // ↑
        case 121: move(10, count: r.items.count); return true         // PageDown
        case 116: move(-10, count: r.items.count); return true        // PageUp
        case 36, 76, 48: accept(); return true                        // Enter, Enter (num), Tab
        case 53: close(); return true                                 // Esc
        case 123, 124: close(); return false                          // ← → zamykają i przesuwają kursor
        default: return false
        }
    }

    /// Po zmianie tekstu przy otwartej liście — nowe zapytanie (zawężenie albo zamknięcie).
    func textChanged() {
        guard panel.isVisible, let requery else { return }
        generation += 1
        let current = generation
        Task { @MainActor in
            let r = await requery()
            guard current == self.generation else { return }
            if let r { self.show(r) } else { self.close() }
        }
    }

    private func move(_ delta: Int, count: Int) {
        let row = max(0, min(count - 1, table.selectedRow + delta))
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func accept() {
        guard let tv = textView, let r = result, table.selectedRow >= 0, table.selectedRow < r.items.count else { return close() }
        let item = r.items[table.selectedRow]
        // Zastępujemy od początku prefiksu do końca słowa pod kursorem.
        let caret = tv.selectedRange().location
        let range = NSRange(location: r.replaceRange.lowerBound, length: max(caret, r.replaceRange.upperBound) - r.replaceRange.lowerBound)
        close()
        if tv.shouldChangeText(in: range, replacementString: item.insertText) {
            tv.textStorage?.replaceCharacters(in: range, with: item.insertText)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location + (item.insertText as NSString).length, length: 0))
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { result?.items.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = result?.items[row] else { return nil }
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: Self.symbol(item.kind), accessibilityDescription: item.kind.rawValue) ?? NSImage())
        icon.contentTintColor = Self.tint(item.kind)
        let label = NSTextField(labelWithString: item.insertText)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: item.detail)
        detail.font = InterfaceFonts.shared.small
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [icon, label, detail] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14), icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            detail.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), detail.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    static func symbol(_ k: CompletionItem.Kind) -> String {
        switch k {
        case .column, .field: "c.square"
        case .table: "tablecells"
        case .view: "eye"
        case .synonym: "arrow.triangle.turn.up.right.diamond"
        case .package: "shippingbox"
        case .procedure: "p.square"
        case .function: "f.square"
        case .sequence: "number"
        case .type, .localType: "t.square"
        case .trigger: "bolt"
        case .schema: "person"
        case .variable, .parameter, .constant: "v.square"
        case .cursor: "list.bullet.rectangle"
        case .exception: "exclamationmark.triangle"
        case .alias: "a.square"
        case .keyword: "textformat"
        case .pseudoColumn: "sparkle"
        case .databaseLink: "link"
        case .object: "cube"
        }
    }

    static func tint(_ k: CompletionItem.Kind) -> NSColor {
        switch k {
        case .column, .field, .pseudoColumn: .systemTeal
        case .table, .view, .synonym: .systemGreen
        case .package, .type, .localType: .systemOrange
        case .procedure, .function, .trigger: .systemBlue
        case .keyword: .systemPurple
        default: .secondaryLabelColor
        }
    }
}
