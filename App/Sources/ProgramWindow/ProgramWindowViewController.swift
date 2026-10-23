import AppKit
import PelikanWorkspace

/// Program Window (UG 4): karty jednostek (specyfikacja, ciało…) nad edytorem — przejście do jednostki, edytor kodu,
/// lista błędów i ostrzeżeń kompilacji (klik = przejście do linii), wskaźniki: niebieski — zmieniony niezapisany,
/// żółty — zmieniony nieskompilowany (UG 4.3). F8 kompiluje wszystkie jednostki.
final class ProgramWindowViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let document: Document
    private let workspace: Workspace
    private var editor: CodeEditorView!
    private let unitBar = NSStackView()
    private let messages = NSTableView()
    private let messagesScroll = NSScrollView()
    private let split = NSSplitView()
    private let caretLabel = NSTextField(labelWithString: "1:1")
    private let modifiedDot = NSTextField(labelWithString: "●")
    private let staleDot = NSTextField(labelWithString: "●")
    private let executing = NSProgressIndicator()
    private var tokens: [ObservationToken] = []
    private var units: [ProgramUnit] = []
    private var shownMessages: [CompileMessage] = []
    private var lastUnitSignature = ""
    private var messagesVisible = false

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
        editor.onCaretChange = { [weak self] s in self?.caretLabel.stringValue = s }
        unitBar.spacing = 2
        unitBar.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

        for (i, (title, id)) in [(L10n.tr("Typ"), "sev"), (L10n.tr("Jednostka"), "unit"), (L10n.tr("Linia"), "line"), (L10n.tr("Komunikat"), "text")].enumerated() {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title
            c.width = [60, 180, 60, 600][i]
            messages.addTableColumn(c)
        }
        messages.usesAlternatingRowBackgroundColors = true
        messages.rowSizeStyle = .small
        messages.dataSource = self
        messages.delegate = self
        messages.target = self
        messages.action = #selector(messageClicked)
        messages.setAccessibilityLabel(L10n.tr("Błędy kompilacji"))
        messagesScroll.documentView = messages
        messagesScroll.hasVerticalScroller = true

        caretLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        caretLabel.textColor = .secondaryLabelColor
        modifiedDot.textColor = .systemBlue
        modifiedDot.toolTip = L10n.tr("Zmieniony, niezapisany")
        staleDot.textColor = .systemYellow
        staleDot.toolTip = L10n.tr("Zmieniony, nieskompilowany")
        executing.style = .spinning
        executing.controlSize = .small
        executing.isDisplayedWhenStopped = false
        let windowBar = NSStackView(views: [modifiedDot, staleDot, caretLabel, NSView(), executing])
        windowBar.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)

        let editorPane = NSView()
        let barContainer = NSView()
        unitBar.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(unitBar)
        for v in [barContainer, editor!, windowBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            editorPane.addSubview(v)
        }
        NSLayoutConstraint.activate([
            barContainer.topAnchor.constraint(equalTo: editorPane.topAnchor),
            barContainer.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
            barContainer.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
            barContainer.heightAnchor.constraint(equalToConstant: 26),
            unitBar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            unitBar.centerYAnchor.constraint(equalTo: barContainer.centerYAnchor),
            editor.topAnchor.constraint(equalTo: barContainer.bottomAnchor),
            editor.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
            windowBar.topAnchor.constraint(equalTo: editor.bottomAnchor),
            windowBar.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
            windowBar.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
            windowBar.bottomAnchor.constraint(equalTo: editorPane.bottomAnchor),
            { let c = windowBar.heightAnchor.constraint(equalToConstant: 22); c.priority = .defaultHigh; return c }(),
        ])
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(editorPane)
        split.addArrangedSubview(messagesScroll)
        messagesScroll.isHidden = true
        view = split
        tokens.append(trackChanges { [weak self] in self?.refreshUnits() })
        tokens.append(trackChanges { [weak self] in self?.refreshMessages() })
        tokens.append(trackChanges { [weak self] in self?.refreshIndicators() })
    }

    // MARK: Karty jednostek

    private var unitsWork: DispatchWorkItem?

    /// Lista jednostek przeliczana z opóźnieniem po zmianie tekstu (pakiet 50 000 linii — bez kosztu przy każdym znaku).
    private func refreshUnits() {
        let text = document.text
        unitsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recomputeUnits(text) }
        unitsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (units.isEmpty ? 0 : 0.4), execute: work)
    }

    private func recomputeUnits(_ text: String) {
        let u = ProgramCompiler.units(in: text)
        let signature = u.map(\.id).map { $0.components(separatedBy: "@")[0] }.joined(separator: "|")
        units = u
        guard signature != lastUnitSignature else { return }
        lastUnitSignature = signature
        unitBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for unit in u {
            let b = ClosureButton(title: unit.tabTitle) { [weak self] in self?.select(unit.id) }
            b.bezelStyle = .accessoryBarAction
            b.font = .systemFont(ofSize: 11)
            b.toolTip = "\(unit.type.rawValue) \(unit.owner.map { "\($0)." } ?? "")\(unit.name)"
            unitBar.addArrangedSubview(b)
        }
    }

    private func select(_ id: String) {
        guard let u = units.first(where: { $0.id.components(separatedBy: "@")[0] == id.components(separatedBy: "@")[0] }) else { return }
        document.selectedRange = u.range.lowerBound..<u.range.lowerBound
        view.window?.makeFirstResponder(editor.textView)
    }

    // MARK: Komunikaty kompilacji

    private func refreshMessages() {
        shownMessages = document.compileMessages
        messages.reloadData()
        let show = !shownMessages.isEmpty
        if show != messagesVisible {
            messagesVisible = show
            messagesScroll.isHidden = !show
            split.adjustSubviews()
            if show {
                let h = split.bounds.height
                DispatchQueue.main.async { [weak self] in self?.split.setPosition(max(120, h - 160), ofDividerAt: 0) }
            }
        }
    }

    private func refreshIndicators() {
        modifiedDot.isHidden = !document.isModified
        staleDot.isHidden = !document.isCompileStale
        if document.isExecuting { executing.startAnimation(nil) } else { executing.stopAnimation(nil) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shownMessages.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let m = shownMessages[row]
        let tf = NSTextField(labelWithString: "")
        tf.font = .systemFont(ofSize: 11)
        tf.lineBreakMode = .byTruncatingTail
        switch tableColumn?.identifier.rawValue {
        case "sev":
            tf.stringValue = m.severity == .error ? L10n.tr("Błąd") : m.severity == .warning ? L10n.tr("Ostrzeżenie") : L10n.tr("Podpowiedź")
            tf.textColor = m.severity == .error ? .systemRed : m.severity == .warning ? .systemOrange : .secondaryLabelColor
        case "unit": tf.stringValue = m.unit
        case "line": tf.stringValue = "\(m.line):\(m.column)"
        default: tf.stringValue = m.text; tf.toolTip = m.text
        }
        return tf
    }

    @objc private func messageClicked() {
        let row = messages.clickedRow
        guard row >= 0, row < shownMessages.count else { return }
        let m = shownMessages[row]
        let o = ProgramCompiler.offset(line: m.line, column: m.column, in: document.text)
        document.selectedRange = o..<o
        view.window?.makeFirstResponder(editor.textView)
    }
}
