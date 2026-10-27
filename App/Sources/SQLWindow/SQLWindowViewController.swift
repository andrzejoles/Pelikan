import AppKit
import PelikanWorkspace

/// SQL Window (UG 7): edytor u góry, wyniki na dole (karty wyników + Output), pasek okna (pozycja kursora,
/// przycisk `&`, stan). Polecenia wykonuje `SQLExecutor` przez komendy rejestru (F8, Ctrl+F8…).
final class SQLWindowViewController: NSViewController, NSSplitViewDelegate, DocumentContentController {
    private let document: Document
    private let workspace: Workspace
    private let split = NSSplitView()
    private var editor: CodeEditorView!
    private let resultsArea = NSView()
    private let tabBar = NSStackView()
    private let resultContainer = NSView()
    private let caretLabel = NSTextField(labelWithString: "1:1")
    private let substitutionButton = NSButton(title: "&", target: nil, action: nil)
    private let executingIndicator = NSProgressIndicator()
    private var tokens: [ObservationToken] = []
    private var gridViews: [UUID: NSView] = [:]
    /// Widok karty Output z pokazanymi liniami i czcionką — dopisywanie zamiast przebudowy (APP2-20).
    private var outputCache: (view: NSView, lines: [String], font: NSFont)?
    private var showingOutput = false
    private var showingStatistics = false
    private var resultsCollapsed = true

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

        // Pasek okna (dół edytora): pozycja, &, wykonywanie.
        caretLabel.textColor = .secondaryLabelColor
        substitutionButton.bezelStyle = .accessoryBarAction
        substitutionButton.target = self
        substitutionButton.action = #selector(toggleSubstitution)
        substitutionButton.toolTip = L10n.tr("Podstawianie zmiennych & i : (kliknij, aby wyłączyć)")
        executingIndicator.style = .spinning
        executingIndicator.controlSize = .small
        executingIndicator.isDisplayedWhenStopped = false
        let windowBar = NSStackView(views: [substitutionButton, caretLabel, NSView(), executingIndicator])
        windowBar.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 8)

        let editorPane = NSView()
        for v in [editor!, windowBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            editorPane.addSubview(v)
        }
        NSLayoutConstraint.activate([
            editor.topAnchor.constraint(equalTo: editorPane.topAnchor),
            editor.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
            windowBar.topAnchor.constraint(equalTo: editor.bottomAnchor),
            windowBar.leadingAnchor.constraint(equalTo: editorPane.leadingAnchor),
            windowBar.trailingAnchor.constraint(equalTo: editorPane.trailingAnchor),
            windowBar.bottomAnchor.constraint(equalTo: editorPane.bottomAnchor),
            { let c = windowBar.heightAnchor.constraint(equalToConstant: 22); c.priority = .defaultHigh; return c }(),
        ])

        // Obszar wyników: karty + zawartość.
        tabBar.orientation = .horizontal
        tabBar.spacing = 2
        tabBar.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        let tabScroll = NSScrollView()
        tabScroll.documentView = tabBar
        tabScroll.drawsBackground = false
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        for v in [tabScroll, resultContainer] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            resultsArea.addSubview(v)
        }
        NSLayoutConstraint.activate([
            tabScroll.topAnchor.constraint(equalTo: resultsArea.topAnchor),
            tabScroll.leadingAnchor.constraint(equalTo: resultsArea.leadingAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: resultsArea.trailingAnchor),
            { let c = tabScroll.heightAnchor.constraint(equalToConstant: 28); c.priority = .defaultHigh; return c }(),
            tabBar.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor),
            tabBar.heightAnchor.constraint(equalTo: tabScroll.contentView.heightAnchor),
            resultContainer.topAnchor.constraint(equalTo: tabScroll.bottomAnchor),
            resultContainer.leadingAnchor.constraint(equalTo: resultsArea.leadingAnchor),
            resultContainer.trailingAnchor.constraint(equalTo: resultsArea.trailingAnchor),
            resultContainer.bottomAnchor.constraint(equalTo: resultsArea.bottomAnchor),
        ])

        split.isVertical = false
        split.dividerStyle = .thin
        split.delegate = self
        split.addArrangedSubview(editorPane)
        split.addArrangedSubview(resultsArea)
        // Wyniki ukryte do pierwszego wykonania (ukryty widok NSSplitView = zwinięty, bez przesuwania dzielnika w layout).
        resultsArea.isHidden = true
        view = split
        tokens.append(trackChanges { [weak self] in self?.refreshResults() })
        tokens.append(trackChanges { [weak self] in self?.refreshState() })
    }

    private func refreshState() {
        // „Ukryj edytor” (PD-GRID-012): same wyniki w oknie.
        if let editorPane = split.arrangedSubviews.first, editorPane.isHidden != document.editorHidden {
            editorPane.isHidden = document.editorHidden
            split.adjustSubviews()
        }
        let executing = document.isExecuting
        if executing { executingIndicator.startAnimation(nil) } else { executingIndicator.stopAnimation(nil) }
        // Pasek okna czcionką interfejsu (D178) — także po zmianie w Preferencjach.
        let fonts = InterfaceFonts.shared
        caretLabel.font = .monospacedDigitSystemFont(ofSize: fonts.small.pointSize, weight: .regular)
        substitutionButton.contentTintColor = document.substitutionEnabled ? nil : .systemRed
        substitutionButton.attributedTitle = NSAttributedString(string: "&", attributes: [
            .foregroundColor: document.substitutionEnabled ? NSColor.labelColor : NSColor.systemRed,
            .font: AppFonts.font(family: fonts.family, size: AppFonts.reduced(fonts.size, by: 1), weight: .bold),
        ])
    }

    private func refreshResults() {
        let results = document.results
        let active = document.activeResultID
        let output = document.output
        _ = results.map { ($0.title, $0.message, $0.pinned, $0.grid) }
        // Pokaż obszar wyników po pierwszym wyniku albo wyjściu.
        if resultsCollapsed, !results.isEmpty || !output.isEmpty {
            resultsCollapsed = false
            resultsArea.isHidden = false
            split.adjustSubviews()
            let h = split.bounds.height
            DispatchQueue.main.async { [weak self] in self?.split.setPosition(max(120, h * 0.5), ofDividerAt: 0) }
        }
        tabBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for r in results {
            tabBar.addArrangedSubview(tabButton(title: (r.pinned ? "📌 " : "") + r.title,
                                                selected: !showingOutput && r.id == active, isError: r.grid == nil && r.message?.hasPrefix("ORA-") == true) { [weak self] in
                self?.showingOutput = false; self?.showingStatistics = false
                self?.document.activeResultID = r.id
                self?.select(r)
                // Shift+klik karty przypina albo odpina wynik (UG 7.10, PD-SQLW-017) — komendą rejestru.
                if NSEvent.modifierFlags.contains(.shift) { self?.workspace.perform("sql.pinResult") }
            })
        }
        tabBar.addArrangedSubview(tabButton(title: output.isEmpty ? L10n.tr("Output") : L10n.tr("Output (\(output.count))"),
                                            selected: (showingOutput || results.isEmpty) && !showingStatistics, isError: false) { [weak self] in
            self?.showingOutput = true
            self?.showingStatistics = false
            self?.refreshResults()
        })
        let stats = document.statistics
        if !stats.isEmpty {
            tabBar.addArrangedSubview(tabButton(title: L10n.tr("Statystyki"), selected: showingStatistics, isError: false) { [weak self] in
                self?.showingStatistics = true
                self?.refreshResults()
            })
        }
        let alive = Set(results.map(\.id))
        gridViews = gridViews.filter { alive.contains($0.key) }
        let shown: NSView?
        if showingStatistics, !stats.isEmpty {
            // Ostatnie wykonanie i suma okna, statystyki wybrane w Preferencjach (PD-OPT-004).
            let rows = Profiler.rows(last: stats, totals: document.statisticTotals, selected: workspace.settings.selectedStatistics)
            let width = max(rows.map(\.name.count).max() ?? 0, 10)
            let header = L10n.tr("Statystyka").padding(toLength: width, withPad: " ", startingAt: 0) + "  " + L10n.tr("Ostatnie") + "  " + L10n.tr("Suma")
            shown = textView(([header] + rows.map { $0.name.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + String(format: "%.0f", $0.last) + "  " + String(format: "%.0f", $0.total) })
                .joined(separator: "\n"), isError: false)
        } else if showingOutput || results.isEmpty {
            shown = outputView(output)
        } else if let r = results.first(where: { $0.id == active }) ?? results.first {
            shown = view(for: r)
        } else {
            shown = nil
        }
        // Widok już pokazany zostaje w kontenerze: przeniesienie zabierało fokus siatce (i edytowanej komórce)
        // i przewijało Output na początek.
        if let shown, shown.superview === resultContainer, resultContainer.subviews.count == 1 { return }
        resultContainer.subviews.forEach { $0.removeFromSuperview() }
        if let shown { install(shown) }
    }

    private func select(_ r: ResultTab) {
        // Wybór karty podświetla polecenie w edytorze (UG 7.1).
        let len = (editor.textView.string as NSString).length
        let range = NSRange(location: min(r.statementRange.lowerBound, len), length: max(0, min(r.statementRange.count, len - min(r.statementRange.lowerBound, len))))
        editor.textView.setSelectedRange(range)
        editor.textView.scrollRangeToVisible(range)
        refreshResults()
    }

    private func install(_ v: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        resultContainer.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: resultContainer.topAnchor),
            v.leadingAnchor.constraint(equalTo: resultContainer.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: resultContainer.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: resultContainer.bottomAnchor),
        ])
    }

    private func view(for r: ResultTab) -> NSView {
        // Odświeżenie karty (Refresh, QBE) podmienia model siatki — widok budowany od nowa.
        if let v = gridViews[r.id], r.grid == nil || (v as? ResultGridView)?.model === r.grid { return v }
        let v: NSView
        if let grid = r.grid {
            v = ResultGridView(tab: r, grid: grid, workspace: workspace)
        } else {
            v = textView(r.message ?? "", isError: r.message?.hasPrefix("ORA-") == true)
        }
        gridViews[r.id] = v
        return v
    }

    private func outputView(_ lines: [String]) -> NSView {
        // Wyjście tylko przybywa (albo jest czyszczone przed wykonaniem): nowe linie dopisywane do pokazanego widoku.
        let font = InterfaceFonts.shared.code
        if let c = outputCache, c.font == font, c.lines.isEmpty == lines.isEmpty, lines.starts(with: c.lines),
           let tv = (c.view as? NSScrollView)?.documentView as? NSTextView {
            if lines.count > c.lines.count {
                let added = "\n" + lines[c.lines.count...].joined(separator: "\n")
                tv.textStorage?.append(NSAttributedString(string: added, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
            }
            outputCache = (c.view, lines, font)
            return c.view
        }
        let v = textView(lines.isEmpty ? L10n.tr("Brak wyjścia DBMS_OUTPUT") : lines.joined(separator: "\n"), isError: false, placeholder: lines.isEmpty)
        outputCache = (v, lines, font)
        return v
    }

    private func textView(_ text: String, isError: Bool, placeholder: Bool = false) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.font = InterfaceFonts.shared.code
        tv.textColor = isError ? .systemRed : (placeholder ? .secondaryLabelColor : .labelColor)
        tv.string = text
        tv.textContainerInset = NSSize(width: 6, height: 6)
        return scroll
    }

    private func tabButton(title: String, selected: Bool, isError: Bool, action: @escaping () -> Void) -> NSView {
        let b = ClosureButton(title: title, action: action)
        b.bezelStyle = .accessoryBarAction
        b.setButtonType(.pushOnPushOff)
        b.state = selected ? .on : .off
        let fonts = InterfaceFonts.shared
        b.font = AppFonts.font(family: fonts.family, size: AppFonts.reduced(fonts.size, by: 2), weight: selected ? .semibold : fonts.weight)
        if isError {
            // Karta z błędem: czerwony tytuł z ikoną (UG 7.1 — wynik z błędem wyróżniony).
            b.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: L10n.tr("Błąd"))
            b.imagePosition = .imageLeading
            b.contentTintColor = .systemRed
            if !selected { b.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed, .font: b.font!]) }
        }
        return b
    }

    @objc private func toggleSubstitution() { workspace.perform("sql.toggleSubstitution") }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { 60 }
}

/// Przycisk z akcją w domknięciu.
final class ClosureButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(title: String, action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        handler = action
        target = self
        self.action = #selector(fire)
    }

    @objc private func fire() { handler?() }
}

/// Pozycja menu z akcją w domknięciu (obiekt akcji trzymany w `representedObject`).
final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

@MainActor
func ClosureMenuItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
    let a = MenuAction(action)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
    item.target = a
    item.representedObject = a
    return item
}
