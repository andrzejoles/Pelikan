import AppKit
import PelikanSQL
import PelikanWorkspace

/// Command Window (UG 8): karta Dialog (wyjście i linia poleceń jak SQL*Plus, historia linii strzałkami) i karta
/// Editor (skrypt z podświetlaniem; F8 wykonuje i przełącza na Dialog). Pasek opcji SET (dwuklik przełącza — UG 8.1).
final class CommandWindowViewController: NSViewController, NSTextFieldDelegate {
    private let document: Document
    private let workspace: Workspace
    private let engine: SQLPlusEngine
    private let tabs = NSSegmentedControl()
    private let content = NSView()
    private let consoleScroll = NSTextView.scrollableTextView()
    private var console: NSTextView { consoleScroll.documentView as! NSTextView }
    private let input = HistoryTextField()
    private let promptLabel = NSTextField(labelWithString: "SQL>")
    private let dialogPane = NSView()
    private var editor: CodeEditorView!
    private let optionsBar = NSStackView()
    private var optionButtons: [String: NSButton] = [:]
    private let executingIndicator = NSProgressIndicator()
    private var tokens: [ObservationToken] = []
    private var renderedLines = 0
    private var renderedFirstID: UUID?
    private var pending: [String] = []
    /// Polecenia wpisane w trakcie wykonywania — kolejka jak w SQL*Plus (type-ahead).
    private var queue: [String] = []
    private var wasExecuting = false
    private var historyIndex: Int?

    var preferredFirstResponder: NSView { tabs.selectedSegment == 0 ? input : editor.textView }

    init(document: Document, workspace: Workspace) {
        self.document = document
        self.workspace = workspace
        engine = workspace.sqlplusEngine(for: document)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        tabs.segmentCount = 2
        tabs.setLabel(L10n.tr("Dialog"), forSegment: 0)
        tabs.setLabel(L10n.tr("Edytor"), forSegment: 1)
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)

        console.isEditable = false
        console.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        console.textContainerInset = NSSize(width: 6, height: 6)
        console.setAccessibilityLabel(L10n.tr("Wyjście Command Window"))
        promptLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        input.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        input.placeholderString = L10n.tr("Polecenie SQL*Plus, SQL albo PL/SQL (blok kończy „/”)")
        input.delegate = self
        input.target = self
        input.action = #selector(submitLine)
        input.onHistory = { [weak self] delta in self?.moveHistory(delta) }
        input.setAccessibilityLabel(L10n.tr("Linia poleceń"))
        let inputRow = NSStackView(views: [promptLabel, input])
        inputRow.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        for v in [consoleScroll, inputRow] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            dialogPane.addSubview(v)
        }
        NSLayoutConstraint.activate([
            consoleScroll.topAnchor.constraint(equalTo: dialogPane.topAnchor),
            consoleScroll.leadingAnchor.constraint(equalTo: dialogPane.leadingAnchor),
            consoleScroll.trailingAnchor.constraint(equalTo: dialogPane.trailingAnchor),
            inputRow.topAnchor.constraint(equalTo: consoleScroll.bottomAnchor),
            inputRow.leadingAnchor.constraint(equalTo: dialogPane.leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: dialogPane.trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: dialogPane.bottomAnchor),
        ])
        editor = CodeEditorView(document: document, fontSize: CGFloat(workspace.settings.editorFontSize))

        // Pasek opcji (UG 8.1): kliknięcie przełącza SET … ON/OFF.
        for (key, title) in [("ECHO", "Echo"), ("FEEDBACK", "Feedback"), ("VERIFY", "Verify"), ("HEADING", "Heading"),
                             ("TIMING", "Timing"), ("SERVEROUTPUT", "Output"), ("TERMOUT", "Termout")] {
            let b = ClosureButton(title: title) { [weak self] in self?.toggle(key) }
            b.bezelStyle = .accessoryBarAction
            b.setButtonType(.pushOnPushOff)
            b.font = .systemFont(ofSize: 11)
            b.toolTip = L10n.tr("SET \(key) ON/OFF")
            optionButtons[key] = b
            optionsBar.addArrangedSubview(b)
        }
        executingIndicator.style = .spinning
        executingIndicator.controlSize = .small
        executingIndicator.isDisplayedWhenStopped = false
        optionsBar.addArrangedSubview(NSView())
        optionsBar.addArrangedSubview(executingIndicator)
        optionsBar.spacing = 2
        optionsBar.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 8)

        let top = NSStackView(views: [tabs, NSView()])
        top.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        let root = NSView()
        for v in [top, content, optionsBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: top.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            optionsBar.topAnchor.constraint(equalTo: content.bottomAnchor),
            optionsBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            optionsBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            optionsBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            { let c = optionsBar.heightAnchor.constraint(equalToConstant: 24); c.priority = .defaultHigh; return c }(),
        ])
        view = root
        tabChanged()
        tokens.append(trackChanges { [weak self] in self?.renderConsole() })
        tokens.append(trackChanges { [weak self] in self?.refreshOptions() })
    }

    @objc private func tabChanged() {
        content.subviews.forEach { $0.removeFromSuperview() }
        let v: NSView = tabs.selectedSegment == 0 ? dialogPane : editor
        v.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: content.topAnchor), v.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: content.leadingAnchor), v.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        view.window?.makeFirstResponder(preferredFirstResponder)
    }

    // MARK: Konsola

    private func attributes(_ kind: ConsoleLine.Kind) -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: kind == .prompt ? .semibold : .regular)
        let color: NSColor = switch kind {
        case .error: .systemRed
        case .echo: .secondaryLabelColor
        case .info: .systemTeal
        case .prompt: .labelColor
        case .output: .labelColor
        }
        return [.font: font, .foregroundColor: color]
    }

    /// Dopisywanie nowych linii (CLEAR SCREEN albo przycięcie bufora — pełne przerysowanie).
    private func renderConsole() {
        let lines = document.console
        let executing = document.isExecuting
        if executing { executingIndicator.startAnimation(nil) } else { executingIndicator.stopAnimation(nil) }
        if executing, tabs.selectedSegment == 1 { DispatchQueue.main.async { [weak self] in self?.showDialog() } }
        if wasExecuting, !executing, !queue.isEmpty {
            let next = queue.removeFirst()
            DispatchQueue.main.async { [weak self] in self?.execute(next) }
        }
        wasExecuting = executing
        promptLabel.stringValue = pending.isEmpty ? engine.state.sqlPrompt.trimmingCharacters(in: .whitespaces) : String(format: "%3d", pending.count + 1)
        guard let storage = console.textStorage else { return }
        if lines.count < renderedLines || lines.first?.id != renderedFirstID {
            storage.setAttributedString(NSAttributedString())
            renderedLines = 0
        }
        renderedFirstID = lines.first?.id
        guard renderedLines < lines.count else { return }
        let add = NSMutableAttributedString()
        for l in lines[renderedLines...] { add.append(NSAttributedString(string: l.text + "\n", attributes: attributes(l.kind))) }
        storage.append(add)
        renderedLines = lines.count
        console.scrollToEndOfDocument(nil)
    }

    private func refreshOptions() {
        let s = engine.state
        let values: [String: Bool] = ["ECHO": s.echo, "FEEDBACK": s.feedback > 0, "VERIFY": s.verify, "HEADING": s.heading,
                                      "TIMING": s.timing, "SERVEROUTPUT": s.serverOutput, "TERMOUT": s.termOut]
        for (k, v) in values { optionButtons[k]?.state = v ? .on : .off }
    }

    private func toggle(_ key: String) {
        let s = engine.state
        let on: Bool = switch key {
        case "ECHO": s.echo
        case "FEEDBACK": s.feedback > 0
        case "VERIFY": s.verify
        case "HEADING": s.heading
        case "TIMING": s.timing
        case "SERVEROUTPUT": s.serverOutput
        default: s.termOut
        }
        Task { await engine.run("set \(key.lowercased()) \(on ? "off" : "on")") }
    }

    // MARK: Linia poleceń

    /// Enter: polecenie SQL*Plus wykonuje się od razu; SQL po „;”, PL/SQL po linii „/” (jak SQL*Plus).
    @objc private func submitLine() {
        let line = input.stringValue
        input.stringValue = ""
        historyIndex = nil
        pending.append(line)
        let text = pending.joined(separator: "\n")
        // Echo wpisanej linii: pierwsza z promptem, kolejne z numerem (jak SQL*Plus).
        let prefix = pending.count == 1 ? engine.state.sqlPrompt : String(format: "%3d  ", pending.count)
        document.console.append(ConsoleLine(prefix + line, .prompt))
        guard SQLPlusEngine.isComplete(text) else {
            renderConsole()
            return
        }
        pending = []
        if document.isExecuting { queue.append(text) } else { execute(text) }
    }

    private func execute(_ text: String) {
        workspace.perform("cmd.executeLine", CommandArguments(["line": .string(text), "echo": .bool(false)]))
    }

    private func moveHistory(_ delta: Int) {
        let h = document.commandLineHistory
        guard !h.isEmpty else { return }
        var i = historyIndex ?? h.count
        i = max(0, min(h.count, i + delta))
        historyIndex = i
        input.stringValue = i < h.count ? h[i] : ""
        input.currentEditor()?.moveToEndOfDocument(nil)
    }

    /// F8 w karcie Editor wykonuje skrypt i przełącza na Dialog (UG 8.2).
    func showDialog() {
        tabs.selectedSegment = 0
        tabChanged()
    }
}

/// Pole linii poleceń ze strzałkami w górę/dół (historia).
final class HistoryTextField: NSTextField {
    var onHistory: ((Int) -> Void)?

    override func textShouldEndEditing(_ textObject: NSText) -> Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool { super.performKeyEquivalent(with: event) }

    override func keyUp(with event: NSEvent) { super.keyUp(with: event) }
}

extension CommandWindowViewController {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveHistory(-1); return true
        case #selector(NSResponder.moveDown(_:)): moveHistory(1); return true
        default: return false
        }
    }
}
