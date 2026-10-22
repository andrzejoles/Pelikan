import AppKit
import PelikanWorkspace

/// Lista okien (UG 32): tytuł z typem, status (zmieniony / transakcja), klik aktywuje, środkowy klik zamyka.
final class WindowListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let workspace: Workspace
    private let table = NSTableView()
    private var documents: [Document] = []

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("title"))
        column.title = L10n.tr("Okna")
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.setAccessibilityLabel(L10n.tr("Lista okien"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        view = scroll
        trackChanges { [weak self] in self?.reload() }
    }

    private func reload() {
        documents = workspace.documents
        // Odczyt właściwości rejestruje śledzenie zmian tytułu i stanu.
        _ = documents.map { ($0.title, $0.isModified, $0.transactionOpen) }
        table.reloadData()
        if let i = documents.firstIndex(where: { $0.id == workspace.activeDocumentID }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { documents.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let doc = documents[row]
        let cell = tableView.makeView(withIdentifier: .init("cell"), owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = .init("cell")
            let image = NSImageView()
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            c.imageView = image
            c.textField = text
            for v in [image, text] {
                v.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(v)
            }
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 14),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        let symbol = doc.transactionOpen ? "circle.fill" : (doc.isModified ? "pencil.circle" : "doc.text")
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = doc.transactionOpen ? .systemGreen : DocumentTabButton.color(for: doc.kind)
        cell.textField?.stringValue = doc.fullTitle
        return cell
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < documents.count else { return }
        workspace.activate(documents[row].id)
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        if event.buttonNumber == 2, row >= 0, row < documents.count { workspace.close(documents[row].id) }
    }
}
