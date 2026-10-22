import AppKit
import PelikanWorkspace

/// Okno główne w układzie PL/SQL Developer (ADR 0005): lewa kolumna narzędzi, obszar dokumentów z kartami, pasek stanu.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private(set) lazy var documentArea = DocumentAreaViewController(workspace: workspace)
    private let workspace: Workspace
    private let split = NSSplitViewController()

    init(workspace: Workspace) {
        self.workspace = workspace
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan"

        window.titlebarSeparatorStyle = .line
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self

        let sidebar = NSSplitViewItem(sidebarWithViewController: SidebarViewController(workspace: workspace))
        sidebar.minimumThickness = 220
        sidebar.maximumThickness = 420
        sidebar.canCollapse = true
        let content = NSSplitViewItem(viewController: documentArea)
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
        window.toolbar = toolbar
        trackChanges { [weak self] in
            guard let self else { return }
            let doc = workspace.activeDocument
            self.window?.subtitle = doc?.fullTitle ?? ""
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Lewa kolumna

/// Lewa kolumna narzędzi: Lista połączeń (Etap 1), Przeglądarka obiektów (Etap 2), Lista okien.
final class SidebarViewController: NSViewController {
    private let workspace: Workspace
    private let selector = NSSegmentedControl(labels: [L10n.tr("Połączenia"), L10n.tr("Obiekty"), L10n.tr("Okna")],
                                              trackingMode: .selectOne, target: nil, action: nil)
    private let container = NSView()
    private lazy var panes: [NSViewController] = [
        ConnectionListViewController(workspace: workspace),
        PlaceholderPaneController(text: L10n.tr("Przeglądarka obiektów — Etap 2")),
        WindowListViewController(workspace: workspace),
    ]

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        selector.target = self
        selector.action = #selector(selectPane(_:))
        selector.selectedSegment = 0
        selector.segmentDistribution = .fillEqually
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

final class PlaceholderPaneController: NSViewController {
    private let text: String
    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
    }
}

// MARK: - Obszar dokumentów

/// Pasek kart dokumentów (SDI wzorca) + widok aktywnego dokumentu + pasek stanu.
final class DocumentAreaViewController: NSViewController {
    private let workspace: Workspace
    private let tabBar = NSStackView()
    private let container = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var controllers: [DocumentID: NSViewController] = [:]
    private var installedID: DocumentID?

    /// Fokus do edytora aktywnego okna (np. po zamknięciu arkusza logowania albo zmiennych).
    func focusActiveDocument() {
        guard let id = installedID, let vc = controllers[id] else { return }
        let responder = (vc as? SQLWindowViewController)?.preferredFirstResponder ?? (vc as? CommandWindowViewController)?.preferredFirstResponder
            ?? (vc as? DocumentViewController)?.preferredFirstResponder
        view.window?.makeFirstResponder(responder)
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        tabBar.orientation = .horizontal
        tabBar.spacing = 2
        tabBar.alignment = .centerY
        tabBar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        let tabScroll = NSScrollView()
        tabScroll.documentView = tabBar
        tabScroll.hasHorizontalScroller = false
        tabScroll.drawsBackground = false
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        let status = NSView()
        status.addSubview(statusLabel)
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
            statusLabel.leadingAnchor.constraint(equalTo: status.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: status.trailingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: status.centerYAnchor),
        ])
        view = root
        trackChanges { [weak self] in self?.refresh() }
    }

    private func refresh() {
        let docs = workspace.documents
        let active = workspace.activeDocumentID
        // Karty.
        tabBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for doc in docs {
            let tab = DocumentTabButton(document: doc, isActive: doc.id == active) { [weak self] in
                self?.workspace.activate(doc.id)
            } onClose: { [weak self] in
                self?.workspace.close(doc.id)
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
        if workspace.activeDocument?.id != installedID { container.subviews.forEach { $0.removeFromSuperview() } }
        if let doc = workspace.activeDocument {
            let vc = controllers[doc.id] ?? {
                let c: NSViewController = switch doc.kind {
                case .sql: SQLWindowViewController(document: doc, workspace: workspace)
                case .command: CommandWindowViewController(document: doc, workspace: workspace)
                default: DocumentViewController(document: doc, workspace: workspace)
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
            statusLabel.stringValue = [connectionDescription(for: doc), doc.transactionOpen ? L10n.tr("● transakcja otwarta") : nil, doc.isExecuting ? nil : doc.resultSummary,
                                       doc.isExecuting ? L10n.tr("Wykonywanie…") : doc.statusText?.components(separatedBy: "\n").first].compactMap { $0 }.joined(separator: "   ·   ")
        } else {
            installedID = nil
            statusLabel.stringValue = L10n.tr("Brak otwartych okien — Plik › Nowy")
        }
    }
}

extension DocumentAreaViewController {
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
        let marker = NSTextField(labelWithString: document.kind.shortName)
        marker.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        marker.textColor = Self.color(for: document.kind)
        let title = NSTextField(labelWithString: (document.isModified ? "● " : "") + document.title)
        title.font = .systemFont(ofSize: 12, weight: isActive ? .semibold : .regular)
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
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(document.fullTitle)
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

// MARK: - Dokument (okna inne niż SQL — edytor kodu; pełne okna w kolejnych etapach)

/// Widok dokumentu innego niż SQL Window: edytor kodu powiązany z `Document`.
final class DocumentViewController: NSViewController {
    private let document: Document
    private let workspace: Workspace
    private var editor: CodeEditorView!

    var preferredFirstResponder: NSView { editor.textView }

    init(document: Document, workspace: Workspace) {
        self.document = document
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        editor = CodeEditorView(document: document, fontSize: CGFloat(workspace.settings.editorFontSize))
        view = editor
    }
}
