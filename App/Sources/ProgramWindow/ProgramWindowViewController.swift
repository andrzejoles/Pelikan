import AppKit
import PelikanSQL
import PelikanWorkspace

/// Program Window (UG 4): karty jednostek (specyfikacja, ciało…) nad edytorem — edytor pokazuje tylko jednostkę
/// wybranej karty (D192), edytor kodu,
/// lista błędów i ostrzeżeń kompilacji (klik = przejście do linii), wskaźniki: niebieski — zmieniony niezapisany,
/// żółty — zmieniony nieskompilowany (UG 4.3). F8 kompiluje wszystkie jednostki.
final class ProgramWindowViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, DocumentContentController {
    private let document: Document
    private let workspace: Workspace
    private var editor: CodeEditorView!
    private let unitBar = NSStackView()
    private let messages = NSTableView()
    private let messagesScroll = NSScrollView()
    private let split = NSSplitView()
    private let caretLabel = NSTextField(labelWithString: "1:1")
    private let hierarchyLabel = NSTextField(labelWithString: "")
    private let contents = CodeContentsView()
    private let outerSplit = NSSplitView()
    private var outlineNodes: [OutlineNode] = []
    private let modifiedDot = NSTextField(labelWithString: "●")
    private let staleDot = NSTextField(labelWithString: "●")
    private let executing = NSProgressIndicator()
    private var tokens: [ObservationToken] = []
    private var units: [ProgramUnit] = []
    private var tabs: [ProgramUnitTab] = []
    private var unitButtons: [NSButton] = []
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
        editor.onCaretChange = { [weak self] s in
            self?.caretLabel.stringValue = s
            self?.caretMoved()
        }
        // Karta jednostki widoczna w edytorze — wyróżniona na pasku kart.
        editor.onShownTabChange = { [weak self] _ in self?.updateUnitButtons() }
        // Code Contents: klik albo Enter — kursor na nazwie elementu i fokus w edytorze; strzałki w drzewie — kursor
        // idzie za zaznaczeniem, fokus zostaje w drzewie. Element innej jednostki przełącza kartę (D192).
        contents.onSelect = { [weak self] n, focus in
            guard let self else { return }
            self.workspace.recordJump()
            self.document.selectedRange = n.nameOffset..<(n.nameOffset + (n.name as NSString).length)
            if focus { self.view.window?.makeFirstResponder(self.editor.textView) }
        }
        hierarchyLabel.textColor = .secondaryLabelColor
        hierarchyLabel.lineBreakMode = .byTruncatingHead
        hierarchyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hierarchyLabel.setAccessibilityLabel(L10n.tr("Hierarchia kodu"))
        hierarchyLabel.toolTip = L10n.tr("Kliknij, aby zaznaczyć albo przejść do elementu ścieżki")
        hierarchyLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(hierarchyClicked)))
        unitBar.spacing = 2
        unitBar.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

        for (i, (title, id)) in [(L10n.tr("Typ"), "sev"), (L10n.tr("Jednostka"), "unit"), (L10n.tr("Linia"), "line"), (L10n.tr("Komunikat"), "text")].enumerated() {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title
            c.width = [60, 180, 60, 600][i]
            messages.addTableColumn(c)
        }
        messages.usesAlternatingRowBackgroundColors = true
        messages.rowSizeStyle = .custom
        messages.dataSource = self
        messages.delegate = self
        messages.target = self
        messages.action = #selector(messageClicked)
        messages.setAccessibilityLabel(L10n.tr("Błędy kompilacji"))
        messagesScroll.documentView = messages
        messagesScroll.hasVerticalScroller = true

        caretLabel.textColor = .secondaryLabelColor
        modifiedDot.textColor = .systemBlue
        modifiedDot.toolTip = L10n.tr("Zmieniony, niezapisany")
        staleDot.textColor = .systemYellow
        staleDot.toolTip = L10n.tr("Zmieniony, nieskompilowany")
        executing.style = .spinning
        executing.controlSize = .small
        executing.isDisplayedWhenStopped = false
        let windowBar = NSStackView(views: [modifiedDot, staleDot, caretLabel, hierarchyLabel, NSView(), executing])
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
            barContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
            { let c = barContainer.heightAnchor.constraint(equalTo: unitBar.heightAnchor); c.priority = .defaultHigh; return c }(),
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
        // Code Contents po lewej stronie edytora (UG 25.15).
        outerSplit.isVertical = true
        outerSplit.dividerStyle = .thin
        outerSplit.addArrangedSubview(contents)
        outerSplit.addArrangedSubview(split)
        contents.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        outerSplit.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        outerSplit.setHoldingPriority(NSLayoutConstraint.Priority(240), forSubviewAt: 1)
        view = outerSplit
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            self.contents.isHidden = !self.workspace.settings.showCodeContents
            self.contents.order = self.workspace.settings.codeContentsOrder
            self.outerSplit.adjustSubviews()
        })
        tokens.append(trackChanges { [weak self] in self?.refreshUnits() })
        tokens.append(trackChanges { [weak self] in self?.refreshMessages() })
        tokens.append(trackChanges { [weak self] in self?.refreshIndicators() })
        tokens.append(trackChanges { [weak self] in self?.applyInterfaceFont() })
    }

    /// Czcionka interfejsu z Preferencji (D178): pasek okna, karty jednostek i lista komunikatów — także po zmianie.
    private func applyInterfaceFont() {
        let small = InterfaceFonts.shared.small
        hierarchyLabel.font = small
        caretLabel.font = .monospacedDigitSystemFont(ofSize: small.pointSize, weight: .regular)
        for case let b as NSButton in unitBar.arrangedSubviews { b.font = small }
        updateUnitButtons()
        messages.rowHeight = AppFonts.rowHeight(for: small)
        messages.reloadData()
    }

    private var didPositionContents = false

    override func viewDidAppear() {
        super.viewDidAppear()
        // Szerokość początkowa panelu Code Contents — po pierwszym układzie okna (wcześniej podział dzieli po połowie).
        guard !didPositionContents else { return }
        didPositionContents = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.outerSplit.layoutSubtreeIfNeeded()
            self.outerSplit.setPosition(220, ofDividerAt: 0)
        }
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
        // Zarys i jednostki liczone w tle (pakiet 50 000 linii bez przestojów przy pisaniu).
        Task.detached(priority: .userInitiated) {
            let outline = PLSQLOutline.parse(text)
            let units = ProgramCompiler.units(in: text)
            let tabs = ProgramUnitTabs.tabs(units, in: text)
            await MainActor.run { [weak self] in
                guard let self, self.document.text == text else { return }
                // Wynik z tła także dla marginesu i komend (bez ponownego podziału na głównym wątku, R4-01).
                self.document.cacheProgramUnits(units, forText: text)
                self.tabs = tabs
                self.editor.unitTabs = tabs
                self.apply(outline: outline, units: units)
            }
        }
    }

    private func apply(outline: [OutlineNode], units u: [ProgramUnit]) {
        outlineNodes = outline
        contents.update(outlineNodes)
        caretMoved()
        let signature = u.map(\.id).map { $0.components(separatedBy: "@")[0] }.joined(separator: "|")
        units = u
        guard signature != lastUnitSignature else { return }
        lastUnitSignature = signature
        unitBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        unitButtons = []
        for (index, unit) in u.enumerated() {
            // Klik karty — komenda rejestru (makra, skróty i agent widzą to samo przejście, D192).
            let b = ClosureButton(title: unit.tabTitle) { [weak self] in self?.select(index) }
            b.bezelStyle = .accessoryBar
            b.setButtonType(.pushOnPushOff)
            b.font = InterfaceFonts.shared.small
            unitButtons.append(b)
            b.toolTip = "\(unit.type.rawValue) \(unit.owner.map { "\($0)." } ?? "")\(unit.name)"
            // Menu karty: usunięcie jednostki z okna (PD-PROG-001).
            let menu = NSMenu()
            let spec = unit.name + ([.packageBody, .typeBody].contains(unit.type) ? " body" : "")
            menu.addItem(ClosureMenuItem(title: L10n.tr("Usuń jednostkę")) { [weak self] in
                self?.workspace.perform("prog.removeUnit", CommandArguments(["unit": .string(spec)]))
            })
            b.menu = menu
            unitBar.addArrangedSubview(b)
        }
        // „+” — nowa jednostka z szablonu jednostek programów (PD-PROG-001).
        let add = ClosureButton(title: "+") { [weak self] in self?.showAddUnitMenu() }
        add.bezelStyle = .accessoryBarAction
        add.font = InterfaceFonts.shared.small
        add.setAccessibilityLabel(L10n.tr("Dodaj jednostkę"))
        add.toolTip = L10n.tr("Dodaj jednostkę")
        addButton = add
        unitBar.addArrangedSubview(add)
        updateUnitButtons()
    }

    /// Karta aktywna wyraźnie zaznaczona (wciśnięta, pogrubiona); okno z jedną jednostką — bez wyróżnienia.
    private func updateUnitButtons() {
        let shown = editor.shownTab
        for (i, b) in unitButtons.enumerated() {
            let on = shown == i
            b.state = on ? .on : .off
            b.font = on ? NSFontManager.shared.convert(InterfaceFonts.shared.small, toHaveTrait: .boldFontMask) : InterfaceFonts.shared.small
            b.setAccessibilityValue(on ? L10n.tr("karta aktywna") : nil)
        }
        contents.activeRange = shown.flatMap { tabs.indices.contains($0) ? tabs[$0].segment : nil }
    }

    private weak var addButton: NSButton?

    /// Menu „+”: szablony folderu jednostek programów (procedura, funkcja, pakiet, typ, wyzwalacz, Java, MLE).
    private func showAddUnitMenu() {
        guard let add = addButton else { return }
        let menu = NSMenu()
        for t in workspace.templates.all where t.folder == TemplateLibrary.programFolder {
            menu.addItem(ClosureMenuItem(title: t.name) { [weak self] in
                self?.workspace.perform("prog.addUnit", CommandArguments(["template": .string(t.id)]))
            })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: add.bounds.height + 2), in: add)
    }

    /// Menu ścieżki Code Hierarchy (PD-CA-011): dla każdego poziomu — zaznacz cały element albo przejdź do nazwy.
    @objc private func hierarchyClicked() {
        let path = PLSQLOutline.path(at: document.selectedRange.lowerBound, in: outlineNodes)
        guard !path.isEmpty else { return }
        let menu = NSMenu()
        for (level, node) in path.enumerated() {
            let item = NSMenuItem(title: String(repeating: "  ", count: level) + node.name, action: nil, keyEquivalent: "")
            item.submenu = NSMenu()
            item.submenu?.addItem(ClosureMenuItem(title: L10n.tr("Zaznacz")) { [weak self] in
                self?.workspace.perform("codeHierarchy.select", CommandArguments(["level": .int(Int64(level))]))
            })
            item.submenu?.addItem(ClosureMenuItem(title: L10n.tr("Przejdź")) { [weak self] in
                self?.workspace.perform("codeHierarchy.goto", CommandArguments(["level": .int(Int64(level))]))
                if let tv = self?.editor.textView { self?.view.window?.makeFirstResponder(tv) }
            })
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: hierarchyLabel.bounds.height + 2), in: hierarchyLabel)
    }

    /// Code Hierarchy (UG 25.16): ścieżka od jednostki do podprogramu/bloku pod kursorem; Code Contents śledzi kursor.
    private func caretMoved() {
        let o = document.selectedRange.lowerBound
        hierarchyLabel.stringValue = PLSQLOutline.path(at: o, in: outlineNodes).map(\.name).joined(separator: " › ")
        if !contents.isHidden { contents.track(offset: o) }
    }

    /// Klik karty: okno z kartami — `prog.selectUnit`; jedna jednostka — kursor na jej początku (jak dotąd).
    private func select(_ index: Int) {
        updateUnitButtons()
        if tabs.count > 1 {
            workspace.perform("prog.selectUnit", CommandArguments(["unit": .int(Int64(index + 1))]))
        } else if units.indices.contains(index) {
            let o = units[index].range.lowerBound
            document.selectedRange = o..<o
        }
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
        tf.font = InterfaceFonts.shared.small
        tf.lineBreakMode = .byTruncatingTail
        switch tableColumn?.identifier.rawValue {
        case "sev":
            tf.stringValue = m.severity == .error ? L10n.tr("Błąd") : m.severity == .warning ? L10n.tr("Ostrzeżenie") : L10n.tr("Podpowiedź")
            tf.textColor = m.severity == .error ? .systemRed : m.severity == .warning ? .systemOrange : .secondaryLabelColor
        case "unit": tf.stringValue = m.unit
        case "line": tf.stringValue = "\(unitLine(m.line)):\(m.column)"
        default: tf.stringValue = m.text; tf.toolTip = m.text
        }
        return tf
    }

    /// Linia komunikatu na liście: w oknie z kartami — linia jednostki (jak ALL_ERRORS), inaczej linia dokumentu.
    private func unitLine(_ documentLine: Int) -> Int {
        guard tabs.count > 1 else { return documentLine }
        let text = document.text
        let o = TextEditing.offset(ofLine: documentLine, in: text)
        guard let i = ProgramUnitTabs.index(of: o, in: tabs) else { return documentLine }
        let first = TextEditing.line(containing: tabs[i].sourceOffset, in: text)
        return ProgramUnitTabs.unitLine(documentLine: documentLine - 1, sourceLine: first) ?? documentLine
    }

    @objc private func messageClicked() {
        let row = messages.clickedRow
        guard row >= 0, row < shownMessages.count else { return }
        let m = shownMessages[row]
        let o = ProgramCompiler.offset(line: m.line, column: m.column, in: document.text)
        workspace.recordJump()
        document.selectedRange = o..<o
        view.window?.makeFirstResponder(editor.textView)
    }
}
