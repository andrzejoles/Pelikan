import AppKit
import PelikanSQL
import PelikanWorkspace

/// Edytor kodu SQL/PL/SQL (ADR 0003): NSTextView na TextKit 2, podświetlanie przyrostowe, numery linii,
/// pasek pozycji `linia:kolumna [długość]` (NF15), wiązanie z `Document` (tekst, zaznaczenie, błąd).
final class CodeEditorView: NSView, NSTextViewDelegate {
    let textView: CodeTextView
    let scrollView = NSScrollView()
    private let ruler: LineNumberRulerView
    private let highlighter = SyntaxHighlighter()
    private let document: Document
    private var font: NSFont
    private var updatingFromModel = false
    private var tokens: [ObservationToken] = []
    private let folding = FoldingContentDelegate()
    private var regions: [FoldRegion] = []
    private var regionsWork: DispatchWorkItem?
    private lazy var completion = CompletionPopup(textView: textView)
    private var assistWork: DispatchWorkItem?
    private var pairGeneration = 0
    private var pairRanges: [NSTextRange] = []
    private var analysisWork: DispatchWorkItem?
    private var analyzedText: String?
    private var diagnostics: [EditorDiagnostic] = []
    var onCaretChange: ((String) -> Void)?

    init(document: Document, fontSize: CGFloat = 13, secondary: Bool = false) {
        self.document = document
        let ws0 = (NSApp.delegate as? AppDelegate)?.workspace
        ligatures = ws0?.settings.editorLigatures ?? true
        font = Self.makeFont(name: ws0?.settings.editorFontName ?? "SF Mono", size: fontSize, ligatures: ligatures)
        textView = CodeTextView(usingTextLayoutManager: true)
        ruler = LineNumberRulerView(textView: textView, highlighter: highlighter)
        isSecondary = secondary
        super.init(frame: .zero)
        configure()
        if let ws = (NSApp.delegate as? AppDelegate)?.workspace {
            textView.keywordCase = ws.settings.keywordCase
            textView.highlightCurrentLine = ws.settings.highlightCurrentLine
            textView.indentUnit = ws.settings.useTabCharacter ? "\t" : String(repeating: " ", count: ws.settings.tabSize)
        }
        load(document.text)
        // Wcięcia i zawijanie wierszy z Preferencji na żywo (PD-EDIT-004).
        tokens.append(trackChanges { [weak self] in
            guard let self, let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
            self.textView.indentMode = ws.settings.indentMode
            self.textView.rightMarginColumn = ws.settings.rightMarginColumn
            self.textView.showSpecialCharacters = ws.settings.showSpecialCharacters
            self.ruler.interval = ws.settings.lineNumberInterval
            self.ruler.needsDisplay = true
            self.textView.backspaceUnindents = ws.settings.backspaceUnindents
            self.textView.indentUnit = ws.settings.useTabCharacter ? "\t" : String(repeating: " ", count: ws.settings.tabSize)
            self.setWordWrap(ws.settings.wordWrap)
        })
        // Status linii względem stanu z otwarcia/zapisu (PD-EDIT-003).
        tokens.append(trackChanges { [weak self] in
            guard let self, let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
            _ = self.document.baselineText
            self.lineStatusEnabled = ws.settings.showLineStatus
            self.scheduleLineStatus(delay: 0)
        })
        // Tło w kolorze połączenia (wskaźniki połączeń, PD-CONN-005) — delikatny odcień, tekst pozostaje czytelny.
        tokens.append(trackChanges { [weak self] in
            guard let self, let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
            _ = self.document.connectionID
            if ws.settings.colorWindowBackground, let c = ws.indicatorColor(for: self.document) {
                self.textView.backgroundColor = NSColor.textBackgroundColor.blended(withFraction: 0.08, of: NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)) ?? .textBackgroundColor
            } else {
                self.textView.backgroundColor = .textBackgroundColor
            }
        })
        tokens.append(trackChanges { [weak self] in self?.syncFromModel() })
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            _ = self.document.foldedStarts
            self.applyFolds()
        })
        // Podkreślenia analizy kodu (DG-RES-001, DG-INSP-001) z modelu.
        tokens.append(trackChanges { [weak self] in
            guard let self, let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
            let list = ws.settings.liveCodeAnalysis ? ws.diagnostics[self.document.id] ?? [] : []
            self.showDiagnostics(list)
        })
        scheduleAnalysis(delay: 0.5)
        // Okno w trakcie wykonania jest tylko do odczytu (jak we wzorcu); inne okna działają równolegle.
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            self.textView.isEditable = !self.document.isExecuting && !self.document.isReadOnly
        })
        // Rozmiar czcionki i ligatury z Preferencji na żywo (PD-EDIT-021).
        tokens.append(trackChanges { [weak self] in
            guard let self, let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
            let size = CGFloat(ws.settings.editorFontSize), lig = ws.settings.editorLigatures
            if size != self.font.pointSize || lig != self.ligatures { self.ligatures = lig; self.setFontSize(size) }
        })
        // Znaczniki kolorów (PD-EDIT-012) i zakładki na marginesie (PD-EDIT-011).
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            self.showColorMarks(self.document.colorMarks)
            _ = self.document.bookmarks
            self.ruler.needsDisplay = true
        })
        // Dodatkowe kursory z modelu (PD-EDIT-023).
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            let extra = self.document.additionalSelections
            self.applyAdditionalSelections(extra)
        })
        // Drugi widok tego samego tekstu (PD-EDIT-014).
        if !isSecondary {
            tokens.append(trackChanges { [weak self] in
                guard let self else { return }
                self.setSplit(self.document.splitEditor)
            })
        }
        textView.hoverText = { [weak self] offset in
            guard let self else { return nil }
            if let d = self.diagnostics.first(where: { $0.range.lowerBound <= offset && offset < max($0.range.upperBound, $0.range.lowerBound + 1) }) { return d.message }
            return DeclarationHover.text(at: offset, in: self.textView.string)
        }
        ruler.bookmarkLines = { [weak self] in
            guard let self else { return [:] }
            var out: [Int: Int] = [:]
            for b in self.document.bookmarks { out[self.highlighter.line(containing: b.offset)] = b.number }
            return out
        }
    }

    /// Drugi edytor tego samego dokumentu (podział, PD-EDIT-014) — bez własnego podziału.
    private(set) var isSecondary = false
    private var secondary: CodeEditorView?
    private weak var peer: CodeEditorView?
    private let pane = NSView()
    private var splitView: NSSplitView?
    private var ligatures = true
    private var colorMarkRanges: [NSTextRange] = []
    private var lineStatusEnabled = true
    private var lineStatusWork: DispatchWorkItem?
    private var wordWrap = false

    convenience init(secondaryOf primary: CodeEditorView, document: Document, fontSize: CGFloat) {
        self.init(document: document, fontSize: fontSize, secondary: true)
        peer = primary
    }

    private func setSplit(_ on: Bool) {
        if on, secondary == nil {
            let s = CodeEditorView(secondaryOf: self, document: document, fontSize: font.pointSize)
            secondary = s
            peer = s
            let split = NSSplitView()
            split.isVertical = false
            split.dividerStyle = .thin
            split.translatesAutoresizingMaskIntoConstraints = false
            pane.removeFromSuperview()
            pane.translatesAutoresizingMaskIntoConstraints = true
            split.addArrangedSubview(pane)
            split.addArrangedSubview(s)
            addSubview(split)
            NSLayoutConstraint.activate([split.topAnchor.constraint(equalTo: topAnchor), split.bottomAnchor.constraint(equalTo: bottomAnchor),
                                         split.leadingAnchor.constraint(equalTo: leadingAnchor), split.trailingAnchor.constraint(equalTo: trailingAnchor)])
            splitView = split
            layoutSubtreeIfNeeded()
            split.setPosition(split.bounds.height / 2, ofDividerAt: 0)
        } else if !on, let split = splitView {
            secondary?.removeFromSuperview()
            secondary = nil
            peer = nil
            pane.removeFromSuperview()
            split.removeFromSuperview()
            splitView = nil
            embedPane()
        }
    }

    private func embedPane() {
        pane.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pane)
        NSLayoutConstraint.activate([pane.topAnchor.constraint(equalTo: topAnchor), pane.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     pane.leadingAnchor.constraint(equalTo: leadingAnchor), pane.trailingAnchor.constraint(equalTo: trailingAnchor)])
    }

    static let colorMarkPalette: [NSColor] = [.systemYellow, .systemGreen, .systemBlue, .systemPink, .systemOrange, .systemPurple]

    private func showColorMarks(_ marks: [ColorMark]) {
        guard let tlm = textView.textLayoutManager, let content = tlm.textContentManager else { return }
        for r in colorMarkRanges { tlm.removeRenderingAttribute(.backgroundColor, for: r) }
        let len = (textView.string as NSString).length
        colorMarkRanges = []
        for m in marks where m.range.upperBound <= len {
            guard let a = content.location(content.documentRange.location, offsetBy: m.range.lowerBound),
                  let b = content.location(a, offsetBy: m.range.count), let r = NSTextRange(location: a, end: b) else { continue }
            let color = Self.colorMarkPalette[max(0, min(Self.colorMarkPalette.count - 1, m.color - 1))].withAlphaComponent(0.3)
            tlm.addRenderingAttribute(.backgroundColor, value: color, for: r)
            colorMarkRanges.append(r)
        }
    }

    /// Zaznaczenia z modelu → zaznaczenia widoku (pierwsze — główne).
    private func applyAdditionalSelections(_ extra: [Range<Int>]) {
        let len = (textView.string as NSString).length
        let main = document.selectedRange
        let all = ([main] + extra).map { NSRange(location: min($0.lowerBound, len), length: max(0, min($0.upperBound, len) - min($0.lowerBound, len))) }
        let current = textView.selectedRanges.map(\.rangeValue)
        guard all != current, !updatingFromModel else { return }
        updatingFromModel = true
        textView.selectedRanges = all.map { NSValue(range: $0) }
        updatingFromModel = false
        textView.needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = font
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        // Bez zawijania wierszy; TextKit 2 nie rysuje tekstu przy nieskończonej szerokości kontenera — duża, skończona.
        textView.textContainer?.size = NSSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = [.font: font, .foregroundColor: SyntaxTheme.plain]
        textView.delegate = self
        // Delegatem NSTextStorage w TextKit 2 jest NSTextContentStorage — nie podmieniamy go, tylko słuchamy powiadomień.
        NotificationCenter.default.addObserver(self, selector: #selector(storageDidProcessEditing(_:)),
                                               name: NSTextStorage.didProcessEditingNotification, object: textView.textStorage)
        textView.setAccessibilityLabel(document.fullTitle)
        textView.textContentStorage?.delegate = folding
        configureCompletion()
        ruler.foldState = { [weak self] line in
            guard let self, let r = self.regions.first(where: { $0.startLine == line }) else { return nil }
            return self.document.foldedStarts.contains(r.start)
        }
        // Podgląd zwiniętego obszaru pod znacznikiem „⋯” (PD-EDIT-013).
        textView.foldPreview = { [weak self] start in
            guard let self, let r = self.regions.first(where: { $0.start == start }) else { return nil }
            return CodeFolding.preview(r, in: self.textView.string)
        }
        ruler.breakpointLines = { [weak self] in
            guard let self, let ws = (NSApp.delegate as? AppDelegate)?.workspace, [.test, .program].contains(self.document.kind) else { return [] }
            return Set(ws.breakpointLines(in: self.document).map { $0 - 1 })
        }
        ruler.coverageLines = { [weak self] in
            guard let self, self.document.kind == .program, let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return ([], [], []) }
            let c = ws.coverageDetail(in: self.document)
            return (Set(c.covered.map { $0 - 1 }), Set(c.uncovered.map { $0 - 1 }), Set(c.partial.map { $0 - 1 }))
        }
        if [.test, .program].contains(document.kind) {
            ruler.onBreakpointClick = { [weak self] line in
                guard let self, let ws = (NSApp.delegate as? AppDelegate)?.workspace,
                      let bp = ws.breakpointAt(document: self.document, line: line + 1) else { return }
                ws.toggleBreakpoint(bp)
                self.ruler.needsDisplay = true
            }
        }
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            self.textView.executionLine = self.document.executionLine
            if let ws = (NSApp.delegate as? AppDelegate)?.workspace { _ = ws.breakpoints; _ = ws.lastUtplsqlRun?.coverage }
            self.ruler.needsDisplay = true
        })
        ruler.onFoldClick = { [weak self] line in
            guard let self, let r = self.regions.first(where: { $0.startLine == line }) else { return }
            if self.document.foldedStarts.contains(r.start) { self.document.foldedStarts.remove(r.start) } else {
                self.document.foldedStarts.insert(r.start)
                let caret = self.document.selectedRange.lowerBound
                if r.hidden.contains(caret) { self.document.selectedRange = r.start..<r.start }
            }
        }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        // Okno ma treść pod paskiem tytułu — bez automatycznych wcięć edytor nie wchodzi pod pasek kart.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        // Margines numerów linii jako osobny widok obok (NSRulerView w TextKit 2 zasłaniał tekst).
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        ruler.translatesAutoresizingMaskIntoConstraints = false
        // Margines i tekst w panelu — przy podziale (PD-EDIT-014) panel trafia do NSSplitView obok drugiego widoku.
        pane.addSubview(ruler)
        pane.addSubview(scrollView)
        NSLayoutConstraint.activate([
            ruler.topAnchor.constraint(equalTo: pane.topAnchor),
            ruler.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            ruler.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            ruler.widthAnchor.constraint(equalToConstant: 44),
            scrollView.topAnchor.constraint(equalTo: pane.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: ruler.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])
        embedPane()
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ruler.needsDisplay = true }
        }
    }

    override func layout() {
        super.layout()
        // Widok tekstu co najmniej tak duży jak obszar przewijania (inaczej zerowa szerokość = niewidoczny tekst).
        let size = scrollView.contentSize
        textView.minSize = NSSize(width: size.width, height: size.height)
        // Zawijanie: szerokość widoku tekstu równa obszarowi przewijania (także przy zwężeniu okna).
        if wordWrap, textView.frame.width != size.width {
            textView.setFrameSize(NSSize(width: size.width, height: max(textView.frame.height, size.height)))
        }
        if textView.frame.width < size.width || textView.frame.height < size.height {
            textView.setFrameSize(NSSize(width: max(textView.frame.width, size.width), height: max(textView.frame.height, size.height)))
        }
    }

    private func load(_ text: String) {
        updatingFromModel = true
        textView.string = text
        if let storage = textView.textStorage { highlighter.highlightAll(storage, font: font) }
        // Zaznaczenie z modelu (np. otwarcie obiektu na linii), a nie koniec wczytanego tekstu.
        let len = (text as NSString).length
        let sel = document.selectedRange
        let r = NSRange(location: min(sel.lowerBound, len), length: max(0, min(sel.upperBound, len) - min(sel.lowerBound, len)))
        textView.setSelectedRange(r)
        updatingFromModel = false
        DispatchQueue.main.async { [weak self] in self?.textView.scrollRangeToVisible(r) }
        ruler.needsDisplay = true
        scheduleRegions(delay: 0)
    }

    // MARK: Code Assistant (UG 25.4)

    static let showCompletionNotification = Notification.Name("PelikanShowCompletion")

    private func configureCompletion() {
        completion.requery = { [weak self] in
            guard let self, let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return nil }
            return await ws.completion(for: self.document, text: self.textView.string, offset: self.textView.selectedRange().location)
        }
        textView.keyInterceptor = { [weak self] event in self?.completion.handle(event) ?? false }
        textView.onMouseDown = { [weak self] in self?.completion.close() }
        NotificationCenter.default.addObserver(self, selector: #selector(showCompletion(_:)), name: Self.showCompletionNotification, object: document)
    }

    @objc private func showCompletion(_ note: Notification) {
        guard let r = note.userInfo?["result"] as? CompletionResult, window?.isKeyWindow == true, window?.firstResponder === textView else { return }
        completion.show(r)
    }

    /// Po wpisaniu kropki — automatyczna aktywacja z opóźnieniem (UG 23.14), gdy kursor nie zmienił się w międzyczasie.
    private func scheduleAutomaticAssist() {
        assistWork?.cancel()
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace, ws.settings.codeAssistantAutomatic else { return }
        let caret = textView.selectedRange().location
        guard caret > 0, (textView.string as NSString).character(at: caret - 1) == 0x2E else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.textView.selectedRange().location == caret, !self.completion.isVisible else { return }
            ws.perform("edit.codeAssistant")
        }
        assistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, ws.settings.codeAssistantDelay)), execute: work)
    }

    // MARK: Pary nawiasów i bloków (UG 23.12)

    /// Podświetlenie pary przy kursorze (nawiasy, BEGIN/IF/LOOP/CASE ↔ END) — liczone w tle, bez zmiany tekstu.
    private func updatePairs() {
        pairGeneration += 1
        let generation = pairGeneration
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return showPairs([]) }
        let text = textView.string
        Task.detached(priority: .utility) {
            let pairs = PairMatcher.pairs(text, offset: sel.location)
            await MainActor.run { [weak self] in
                guard let self, self.pairGeneration == generation, self.textView.string == text else { return }
                self.showPairs(pairs)
            }
        }
    }

    private func showPairs(_ ranges: [Range<Int>]) {
        guard let tlm = textView.textLayoutManager, let content = tlm.textContentManager else { return }
        for r in pairRanges { tlm.removeRenderingAttribute(.backgroundColor, for: r) }
        pairRanges = ranges.compactMap { r in
            guard let a = content.location(content.documentRange.location, offsetBy: r.lowerBound),
                  let b = content.location(a, offsetBy: r.count) else { return nil }
            return NSTextRange(location: a, end: b)
        }
        let color = NSColor.findHighlightColor.withAlphaComponent(0.35)
        for r in pairRanges { tlm.addRenderingAttribute(.backgroundColor, value: color, for: r) }
    }

    // MARK: Analiza kodu w czasie pisania (DG-RES-001, DG-INSP-001)

    /// Analiza z opóźnieniem po zmianie tekstu (inspekcje lokalnie, nazwy ze słownika otwartego połączenia).
    private func scheduleAnalysis(delay: Double = 0.8) {
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace, ws.settings.liveCodeAnalysis,
              [.sql, .program, .test].contains(document.kind), document.text != analyzedText else { return }
        analysisWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.analyzedText = self.document.text
            Task { @MainActor in await ws.analyzeCode(self.document) }
        }
        analysisWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Podkreślenie falowane (kropkowane): błąd — czerwone, ostrzeżenie — pomarańczowe; atrybuty renderowania, bez zmiany tekstu.
    private func showDiagnostics(_ list: [EditorDiagnostic]) {
        diagnostics = list
        guard let tlm = textView.textLayoutManager, let content = tlm.textContentManager else { return }
        tlm.removeRenderingAttribute(.underlineStyle, for: content.documentRange)
        tlm.removeRenderingAttribute(.underlineColor, for: content.documentRange)
        let len = (textView.string as NSString).length
        for d in list where d.range.upperBound <= len && !d.range.isEmpty {
            guard let a = content.location(content.documentRange.location, offsetBy: d.range.lowerBound),
                  let b = content.location(a, offsetBy: d.range.count), let r = NSTextRange(location: a, end: b) else { continue }
            tlm.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue, for: r)
            tlm.addRenderingAttribute(.underlineColor, value: d.severity == .error ? NSColor.systemRed : NSColor.systemOrange, for: r)
        }
        updateDiagnosticTip()
    }

    /// Komunikat problemu pod kursorem: podpowiedź edytora i pasek stanu okna.
    private func updateDiagnosticTip() {
        let caret = textView.selectedRange().location
        let d = diagnostics.first { $0.range.lowerBound <= caret && caret <= $0.range.upperBound }
        // Podpowiedź pod myszą (problem albo deklaracja) daje `hoverText`; tu — pasek stanu okna.
        if let d, document.statusText != d.message { document.statusText = d.message }
    }

    // MARK: Zwijanie kodu (UG 25.17)

    /// Obszary zwijania przeliczane z opóźnieniem po zmianie tekstu (znaczniki ± w marginesie).
    private func scheduleRegions(delay: Double = 0.3) {
        scheduleLineStatus()
        regionsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Analiza w tle (pakiet 50 000 linii); wynik tylko dla niezmienionego tekstu.
            let text = self.textView.string
            Task.detached(priority: .userInitiated) {
                let r = CodeFolding.regions(text)
                await MainActor.run { [weak self] in
                    guard let self, self.textView.string == text else { return }
                    self.regions = r
                    self.applyFolds()
                    self.ruler.needsDisplay = true
                }
            }
        }
        regionsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Status linii (zmienione, nowe) liczony w tle z opóźnieniem po zmianie tekstu.
    private func scheduleLineStatus(delay: Double = 0.5) {
        lineStatusWork?.cancel()
        guard lineStatusEnabled else {
            if !ruler.lineStatus.isEmpty { ruler.lineStatus = [:]; ruler.needsDisplay = true }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.textView.string, baseline = self.document.baselineText
            Task.detached(priority: .utility) {
                let status = TextDiff.lineStatus(baseline: baseline, current: text)
                await MainActor.run { [weak self] in
                    guard let self, self.textView.string == text else { return }
                    self.ruler.lineStatus = status
                    self.ruler.needsDisplay = true
                }
            }
        }
        lineStatusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Zawijanie wierszy do szerokości okna (PD-EDIT-004); bez zawijania — duża, skończona szerokość kontenera.
    private func setWordWrap(_ on: Bool) {
        guard on != wordWrap, let container = textView.textContainer else { return }
        wordWrap = on
        textView.isHorizontallyResizable = !on
        scrollView.hasHorizontalScroller = !on
        container.widthTracksTextView = on
        if on {
            let width = scrollView.contentSize.width
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
            container.size = NSSize(width: width - 2 * textView.textContainerInset.width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            container.size = NSSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)
        }
        if let tlm = textView.textLayoutManager {
            tlm.invalidateLayout(for: tlm.documentRange)
            tlm.textViewportLayoutController.layoutViewport()
        }
        textView.needsDisplay = true
        ruler.needsDisplay = true
    }

    private func applyFolds() {
        let folded = document.foldedStarts
        let hidden = CodeFolding.hiddenRanges(regions, folded: folded)
        guard hidden != folding.hidden else { return }
        folding.hidden = hidden
        // Znacznik „⋯” tylko przy zwinięciach widocznych (nie wewnątrz innego zwiniętego obszaru).
        textView.foldedLines = regions.filter { r in folded.contains(r.start) && !hidden.contains { $0.contains(r.start) } }.map(\.start)
        if let tlm = textView.textLayoutManager {
            tlm.invalidateLayout(for: tlm.documentRange)
            tlm.textViewportLayoutController.layoutViewport()
        }
        textView.needsDisplay = true
        ruler.needsDisplay = true
    }

    /// Zaznaczenie w ukrytym tekście (przejście do deklaracji, wyszukiwanie, błąd) rozwija obejmujące zwinięcia.
    private func revealSelection(_ offset: Int) {
        guard folding.hidden.contains(where: { $0.contains(offset) }) else { return }
        let containing = regions.filter { document.foldedStarts.contains($0.start) && $0.hidden.contains(offset) }.map(\.start)
        DispatchQueue.main.async { [weak self] in self?.document.foldedStarts.subtract(containing) }
    }

    /// Zmiany modelu z zewnątrz (komendy edycji, historia okna, agent `replace_range`, błąd do zaznaczenia).
    /// Tekst nakładany jako minimalna zamiana przez NSTextView — z rejestracją cofania i podświetlaniem przyrostowym.
    private func syncFromModel() {
        let text = document.text
        let selection = document.selectedRange
        let error = document.errorRange
        if text != textView.string {
            applyExternal(text)
            scheduleAnalysis()
        }
        let len = (textView.string as NSString).length
        let current = textView.selectedRange()
        let wanted = NSRange(location: min(selection.lowerBound, len), length: max(0, min(selection.upperBound, len) - min(selection.lowerBound, len)))
        // Przy podziale edytora zaznaczenie z modelu stosuje tylko widok, w którym nie pisze się właśnie w drugim.
        let peerActive = peer.map { $0.window?.firstResponder === $0.textView } ?? false
        if !updatingFromModel, current != wanted, !peerActive, document.additionalSelections.isEmpty {
            revealSelection(wanted.location)
            textView.setSelectedRange(wanted)
            textView.scrollRangeToVisible(wanted)
        }
        if let error {
            let r = NSRange(location: min(error.lowerBound, len), length: 0)
            textView.setSelectedRange(r)
            textView.scrollRangeToVisible(r)
            // Zaznacz słowo z błędem (NF15: podkreślenie całego słowa).
            let word = textView.selectionRange(forProposedRange: r, granularity: .selectByWord)
            if word.length > 0 { textView.showFindIndicator(for: word) }
        }
    }

    private func applyExternal(_ text: String) {
        let old = textView.string as NSString
        let new = text as NSString
        // Wspólny początek i koniec — zamieniamy tylko środek.
        var prefix = 0
        let minLen = min(old.length, new.length)
        while prefix < minLen, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < minLen - prefix, old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        let range = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        updatingFromModel = true
        defer { updatingFromModel = false }
        if old.length == 0 || range.length == old.length && old.length > 200_000 {
            load(text)
            return
        }
        if textView.shouldChangeText(in: range, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
        }
        if let storage = textView.textStorage {
            highlighter.highlight(storage, editedRange: NSRange(location: prefix, length: (replacement as NSString).length),
                                  delta: (replacement as NSString).length - range.length, font: font)
        }
        ruler.needsDisplay = true
        scheduleRegions()
    }

    // MARK: Podświetlanie przyrostowe (po każdej edycji magazynu tekstu)

    @objc private func storageDidProcessEditing(_ note: Notification) {
        guard let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters), !updatingFromModel else { return }
        let editedRange = storage.editedRange
        let delta = storage.changeInLength
        // Atrybuty zmieniamy po zakończeniu przetwarzania edycji (nie w trakcie).
        DispatchQueue.main.async { [weak self] in
            guard let self, let storage = self.textView.textStorage else { return }
            let len = storage.length
            let r = NSRange(location: min(editedRange.location, len), length: min(editedRange.length, max(0, len - min(editedRange.location, len))))
            self.highlighter.highlight(storage, editedRange: r, delta: delta, font: self.font)
            self.ruler.needsDisplay = true
            self.scheduleRegions()
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !updatingFromModel else { return }
        updatingFromModel = true
        document.text = textView.string
        document.errorRange = nil
        updatingFromModel = false
        if completion.isVisible { completion.textChanged() } else { scheduleAutomaticAssist() }
        scheduleAnalysis()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !updatingFromModel else { return }
        let r = textView.selectedRange()
        document.selectedRange = r.location..<(r.location + r.length)
        // Zaznaczenie kolumnowe (Option+przeciąganie) i dodatkowe kursory → model (PD-EDIT-007, PD-EDIT-023).
        let extra = textView.selectedRanges.dropFirst().map { $0.rangeValue }.map { $0.location..<($0.location + $0.length) }
        if document.additionalSelections != Array(extra) {
            updatingFromModel = true
            document.additionalSelections = Array(extra)
            updatingFromModel = false
        }
        // Po edycji początki linii przelicza podświetlanie w następnym obiegu pętli — pozycję liczymy po nim.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let r = self.textView.selectedRange()
            let line = self.highlighter.line(containing: r.location)
            let col = r.location - (line < self.highlighter.lineStarts.count ? self.highlighter.lineStarts[line] : 0)
            self.onCaretChange?(r.length > 0 ? "\(line + 1):\(col + 1) [\(r.length)]" : "\(line + 1):\(col + 1)")
            self.ruler.needsDisplay = true
            self.updatePairs()
            self.updateDiagnosticTip()
        }
    }

    func setFontSize(_ size: CGFloat) {
        let name = (NSApp.delegate as? AppDelegate)?.workspace.settings.editorFontName ?? font.familyName ?? "SF Mono"
        font = Self.makeFont(name: name, size: size, ligatures: ligatures)
        textView.font = font
        textView.typingAttributes[.font] = font
        if let storage = textView.textStorage { highlighter.highlightAll(storage, font: font) }
        ruler.needsDisplay = true
    }

    /// Czcionka edytora; bez ligatur — wyłączone ligatury typowe i kontekstowe alternatywy (PD-EDIT-021).
    static func makeFont(name: String, size: CGFloat, ligatures: Bool) -> NSFont {
        let base = NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        guard !ligatures else { return base }
        let off: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector],
            [.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector],
        ]
        return NSFont(descriptor: base.fontDescriptor.addingAttributes([.featureSettings: off]), size: size) ?? base
    }
}

/// NSTextView z dodatkami edytora kodu: wcięcie zaznaczenia Tab/Shift+Tab (UG 25.1), auto-wcięcie po Enter.
final class CodeTextView: NSTextView {
    var indentUnit = "  "
    /// Tryb wcięcia po Enter i Backspace usuwający jednostkę wcięcia (UG 23.12, PD-EDIT-004).
    var indentMode: IndentMode = .automatic
    var backspaceUnindents = true
    /// Tekst podglądu zwiniętego obszaru (klucz — początek struktury) i miejsca znaczników „⋯” (PD-EDIT-013).
    var foldPreview: ((Int) -> String?)?
    /// Pionowy margines w kolumnie (0 — bez) i znaki specjalne: spacje, tabulacje, końce linii (PD-EDIT-003).
    var rightMarginColumn = 0 { didSet { if rightMarginColumn != oldValue { needsDisplay = true } } }
    var showSpecialCharacters = false { didSet { if showSpecialCharacters != oldValue { needsDisplay = true } } }
    private var foldBoxes: [(rect: NSRect, start: Int)] = []
    var keywordCase: KeywordCase = .unchanged
    var highlightCurrentLine = true
    /// Linia debugera (od 1) — wyróżniona tłem (UG 5.10).
    var executionLine: Int? { didSet { if executionLine != oldValue { needsDisplay = true } } }
    static let executionLineColor = NSColor.systemGreen.withAlphaComponent(0.22)
    /// Początki zwiniętych struktur — za ich linią rysowany jest znacznik „⋯”.
    var foldedLines: [Int] = [] { didSet { needsDisplay = true } }
    static let currentLineColor = NSColor(name: nil) { $0.isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(srgbRed: 0.95, green: 0.97, blue: 1, alpha: 1) }

    /// Podświetlenie linii z kursorem (UG 23.12 „Highlight current line”).
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if rightMarginColumn > 0, let font {
            let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
            let x = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5) + CGFloat(rightMarginColumn) * advance
            NSColor.separatorColor.setFill()
            NSRect(x: x, y: rect.minY, width: 1, height: rect.height).fill()
        }
        if let line = executionLine, let tlm = textLayoutManager, let content = tlm.textContentManager {
            let ns = string as NSString
            var offset = 0, current = 1
            while current < line, offset < ns.length {
                let r = ns.lineRange(for: NSRange(location: offset, length: 0))
                offset = r.location + r.length
                current += 1
            }
            if let loc = content.location(content.documentRange.location, offsetBy: min(offset, ns.length)),
               let f = tlm.textLayoutFragment(for: loc)?.layoutFragmentFrame {
                // Na wierzchu podświetlenia bieżącej linii (rysowanego niżej).
                let rect = NSRect(x: 0, y: f.minY + textContainerInset.height, width: bounds.width, height: f.height)
                defer {
                    Self.executionLineColor.setFill()
                    rect.fill()
                    NSColor.systemGreen.setFill()
                    NSRect(x: 0, y: rect.minY, width: 3, height: rect.height).fill()
                }
                drawCurrentLine()
                return
            }
        }
        drawCurrentLine()
    }

    private func drawCurrentLine() {
        guard highlightCurrentLine, selectedRange().length == 0, let tlm = textLayoutManager, let content = tlm.textContentManager,
              let loc = content.location(content.documentRange.location, offsetBy: selectedRange().location) else { return }
        var frame = tlm.textLayoutFragment(for: loc)?.layoutFragmentFrame ?? .zero
        if frame == .zero || selectedRange().location == (string as NSString).length && string.hasSuffix("\n") {
            let h = (font?.ascender ?? 12) - (font?.descender ?? -3) + (font?.leading ?? 0)
            frame = NSRect(x: 0, y: frame == .zero ? 0 : frame.maxY, width: bounds.width, height: h)
        }
        Self.currentLineColor.setFill()
        NSRect(x: 0, y: frame.minY + textContainerInset.height, width: bounds.width, height: frame.height).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawExtraCarets()
        drawSpecialCharacters(in: dirtyRect)
        if foldedLines.isEmpty { foldBoxes = [] }
        guard !foldedLines.isEmpty, let tlm = textLayoutManager, let content = tlm.textContentManager else { return }
        var boxes: [(rect: NSRect, start: Int)] = []
        defer { foldBoxes = boxes }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: max(9, (font?.pointSize ?? 13) - 2)),
                                                    .foregroundColor: NSColor.secondaryLabelColor]
        let mark = NSAttributedString(string: "⋯", attributes: attrs)
        for start in foldedLines {
            guard let loc = content.location(content.documentRange.location, offsetBy: start),
                  let fragment = tlm.textLayoutFragment(for: loc) else { continue }
            let f = fragment.layoutFragmentFrame
            let width = fragment.textLineFragments.first?.typographicBounds.width ?? 0
            let box = NSRect(x: f.minX + width + textContainerInset.width + 6, y: f.minY + textContainerInset.height + 2,
                             width: mark.size().width + 10, height: max(10, f.height - 4))
            boxes.append((box, start))
            guard box.intersects(dirtyRect) else { continue }
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            mark.draw(at: NSPoint(x: box.minX + 5, y: box.midY - mark.size().height / 2))
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if highlightCurrentLine { needsDisplay = true }
    }

    /// Wielkość liter słowa kluczowego po jego zakończeniu (spacja, nowa linia, znak przestankowy), poza literałami i komentarzami.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        // Pisanie w wielu miejscach naraz: zaznaczenie kolumnowe albo dodatkowe kursory (PD-EDIT-007, PD-EDIT-023).
        if selectedRanges.count > 1, replacementRange.location == NSNotFound {
            applyMulti { MultiCursor.insert(text, in: $0, ranges: $1) }
            (NSApp.delegate as? AppDelegate)?.workspace.recordTyping(text)
            return
        }
        if keywordCase != .unchanged, let ch = text.unicodeScalars.first, !CharacterSet.alphanumerics.contains(ch), ch != "_", ch != "$", ch != "#" {
            applyKeywordCase()
        }
        super.insertText(string, replacementRange: replacementRange)
        applyAutoReplace(after: text)
        (NSApp.delegate as? AppDelegate)?.workspace.recordTyping(text)
    }

    /// Backspace w nagrywanym makrze (PD-EDIT-015); przy wielu kursorach — w każdym.
    override func deleteBackward(_ sender: Any?) {
        if selectedRanges.count > 1 {
            applyMulti { MultiCursor.deleteBackward(in: $0, ranges: $1) }
        } else if backspaceUnindents, selectedRange().length == 0, let n = unindentLength() {
            // Backspace w wiodących spacjach usuwa całą jednostkę wcięcia (PD-EDIT-004).
            let r = NSRange(location: selectedRange().location - n, length: n)
            if shouldChangeText(in: r, replacementString: "") {
                replaceCharacters(in: r, with: "")
                didChangeText()
            }
        } else {
            super.deleteBackward(sender)
        }
        (NSApp.delegate as? AppDelegate)?.workspace.recordDeleteBackward()
    }

    /// Zmiana tekstu we wszystkich zaznaczeniach jedną operacją cofania; zaznaczenia po zmianie z funkcji.
    private func applyMulti(_ edit: (String, [Range<Int>]) -> (text: String, ranges: [Range<Int>])) {
        let ranges = selectedRanges.map(\.rangeValue).map { $0.location..<($0.location + $0.length) }
        let result = edit(string, ranges)
        let change = EditorShift.Change(old: string, new: result.text)
        let range = NSRange(location: change.prefix, length: change.oldEnd - change.prefix)
        let replacement = (result.text as NSString).substring(with: NSRange(location: change.prefix, length: change.oldEnd - change.prefix + change.delta))
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
        selectedRanges = result.ranges.map { NSValue(range: NSRange(location: $0.lowerBound, length: $0.count)) }
    }

    /// AutoReplace (PD-EDIT-017): skrót przed wpisanym znakiem kończącym zastąpiony tekstem z Preferencji.
    private func applyAutoReplace(after typed: String) {
        guard typed.count == 1, selectedRange().length == 0, let ws = (NSApp.delegate as? AppDelegate)?.workspace,
              let r = AutoReplace.apply(ws.settings.autoReplace, text: string, caret: selectedRange().location) else { return }
        let range = NSRange(location: r.range.lowerBound, length: r.range.count)
        guard shouldChangeText(in: range, replacementString: r.replacement) else { return }
        replaceCharacters(in: range, with: r.replacement)
        didChangeText()
        setSelectedRange(NSRange(location: r.caret, length: 0))
    }

    // MARK: Podpowiedź pod myszą (PD-CA-008)

    /// Tekst podpowiedzi dla pozycji w tekście: problem analizy albo deklaracja identyfikatora.
    var hoverText: ((Int) -> String?)?
    private var tooltipTag: NSView.ToolTipTag?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let tooltipTag { removeToolTip(tooltipTag) }
        tooltipTag = addToolTip(bounds, owner: self, userData: nil)
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        // Podgląd zwiniętego kodu pod znacznikiem „⋯”.
        if let box = foldBoxes.first(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }), let preview = foldPreview?(box.start) {
            return preview
        }
        let i = characterIndexForInsertion(at: point)
        return hoverText?(i) ?? ""
    }

    // MARK: Zakładki Ctrl+K n / Ctrl+Q n (PD-EDIT-011, profil PL/SQL Developer)

    private var bookmarkPrefix: Character?

    private func handleBookmarkKeys(_ event: NSEvent) -> Bool {
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace, ws.settings.shortcutProfile == .plsqlDeveloper else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if let prefix = bookmarkPrefix {
            bookmarkPrefix = nil
            if let ch = event.charactersIgnoringModifiers?.first, let n = ch.wholeNumberValue {
                ws.perform(prefix == "k" ? "edit.toggleBookmark" : "edit.gotoBookmark", CommandArguments(["number": .int(Int64(n))]))
                return true
            }
            return false
        }
        if mods == .control, let ch = event.charactersIgnoringModifiers?.lowercased().first, ch == "k" || ch == "q" {
            bookmarkPrefix = ch
            return true
        }
        return false
    }

    /// Znaki specjalne (UG 23.12 „Show special characters”): kropka dla spacji, strzałka dla tabulacji, ¶ na końcu linii.
    private func drawSpecialCharacters(in dirtyRect: NSRect) {
        guard showSpecialCharacters, let tlm = textLayoutManager, let content = tlm.textContentManager else { return }
        let ns = string as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                                    .foregroundColor: NSColor.tertiaryLabelColor]
        let start = tlm.textViewportLayoutController.viewportRange?.location ?? tlm.documentRange.location
        tlm.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let f = fragment.layoutFragmentFrame
            if f.minY + self.textContainerInset.height > dirtyRect.maxY { return false }
            if f.maxY + self.textContainerInset.height < dirtyRect.minY { return true }
            let base = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                let r = line.characterRange
                for k in r.location..<(r.location + r.length) {
                    let i = base + k
                    guard i < ns.length else { break }
                    guard let mark = LineNumbering.specialMark(ns.character(at: i)) else { continue }
                    let p = line.locationForCharacter(at: k)
                    let origin = NSPoint(x: f.minX + line.typographicBounds.minX + p.x + self.textContainerInset.width,
                                         y: f.minY + line.typographicBounds.minY + self.textContainerInset.height)
                    (mark as NSString).draw(at: origin, withAttributes: attrs)
                }
            }
            return true
        }
    }

    /// Dodatkowe kursory (zaznaczenia zerowej długości poza pierwszym) — NSTextView rysuje tylko jeden.
    private func drawExtraCarets() {
        guard selectedRanges.count > 1, let tlm = textLayoutManager, let content = tlm.textContentManager else { return }
        NSColor.textColor.setFill()
        for r in selectedRanges.dropFirst().map(\.rangeValue) where r.length == 0 {
            guard let loc = content.location(content.documentRange.location, offsetBy: r.location) else { continue }
            var rect: CGRect?
            tlm.enumerateTextSegments(in: NSTextRange(location: loc), type: .selection, options: []) { _, frame, _, _ in
                rect = frame
                return false
            }
            if let f = rect {
                NSRect(x: f.minX + textContainerInset.width, y: f.minY + textContainerInset.height, width: 1.5, height: max(f.height, font?.pointSize ?? 13)).fill()
            }
        }
    }

    /// Kopiowanie i wycinanie trafia do historii schowka (PD-EDIT-024).
    override func copy(_ sender: Any?) {
        recordSelectionInClipboardHistory()
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        recordSelectionInClipboardHistory()
        super.cut(sender)
    }

    private func recordSelectionInClipboardHistory() {
        let r = selectedRange()
        guard r.length > 0 else { return }
        (NSApp.delegate as? AppDelegate)?.workspace.recordClipboard((string as NSString).substring(with: r))
    }

    private func applyKeywordCase() {
        let ns = self.string as NSString
        let caret = selectedRange().location
        guard selectedRange().length == 0, caret > 0 else { return }
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let line = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        guard let last = Lexer(line).tokenize().last, last.kind == .keyword, last.start + last.length == (line as NSString).length else { return }
        let word = (line as NSString).substring(with: NSRange(location: last.start, length: last.length))
        let cased: String = switch keywordCase {
        case .upper: word.uppercased()
        case .lower: word.lowercased()
        case .initCap: word.prefix(1).uppercased() + word.dropFirst().lowercased()
        case .unchanged: word
        }
        guard cased != word else { return }
        let r = NSRange(location: lineStart + last.start, length: last.length)
        if shouldChangeText(in: r, replacementString: cased) {
            replaceCharacters(in: r, with: cased)
            didChangeText()
        }
    }

    /// Klawisze przechwytywane przez listę podpowiedzi (↑↓, Enter, Tab, Esc), zanim trafią do edytora.
    var keyInterceptor: ((NSEvent) -> Bool)?
    var onMouseDown: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if keyInterceptor?(event) == true { return }
        if handleBookmarkKeys(event) { return }
        // Esc przy wielu kursorach — zostaje jeden (jak w edytorach z wieloma kursorami).
        if event.keyCode == 53, selectedRanges.count > 1 {
            setSelectedRange(selectedRanges[0].rangeValue)
            return
        }
        super.keyDown(with: event)
    }

    /// Cmd+klik na identyfikatorze — przejście do deklaracji (UG 25.19 nawigacja hiperłączami); Option+klik —
    /// dodatkowy kursor (PD-EDIT-023), Option+przeciąganie — zaznaczenie kolumnowe (NSTextView, PD-EDIT-007).
    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option, event.clickCount == 1 {
            let before = selectedRanges
            super.mouseDown(with: event)
            let after = selectedRanges
            if after.count == 1, after[0].rangeValue.length == 0 {
                let merged = MultiCursor.sorted(before.map(\.rangeValue).map { $0.location..<($0.location + $0.length) } + [after[0].rangeValue.location..<after[0].rangeValue.location])
                selectedRanges = merged.map { NSValue(range: NSRange(location: $0.lowerBound, length: $0.count)) }
                needsDisplay = true
            }
            return
        }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return super.mouseDown(with: event) }
        let i = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        setSelectedRange(NSRange(location: i, length: 0))
        ws.perform("edit.gotoDeclaration")
    }

    /// Menu kontekstowe: na nazwie obiektu — działania jak w Object Browserze (UG 25.9), potem menu edycji.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return menu }
        let i = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard let word = EditorObjectMenu.objectName(at: i, in: string) else { return menu }
        if selectedRange().length == 0 { setSelectedRange(NSRange(location: i, length: 0)) }
        var items: [NSMenuItem] = []
        let header = NSMenuItem(title: L10n.tr("Obiekt „\(word)”"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        items.append(header)
        for (id, title) in EditorObjectMenu.actions {
            let item = ClosureMenuItem(title: title) { ws.perform(id, CommandArguments(["object": .string(word)])) }
            items.append(item)
        }
        items.append(ClosureMenuItem(title: L10n.tr("Przejdź do deklaracji")) { ws.perform("edit.gotoDeclaration") })
        items.append(.separator())
        for (k, item) in items.enumerated() { menu.insertItem(item, at: k) }
        return menu
    }

    /// Upuszczone pliki skryptów otwierają się w oknach (zamiast wstawiania ścieżki do tekstu).
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Szablon z okna szablonów: wstawienie w miejscu upuszczenia (formularz zmiennych, PD-TPL-002).
        if let data = sender.draggingPasteboard.data(forType: TemplatePane.pasteboardType), let ws = (NSApp.delegate as? AppDelegate)?.workspace {
            let id = String(decoding: data, as: UTF8.self)
            let i = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            setSelectedRange(NSRange(location: i, length: 0))
            window?.makeFirstResponder(self)
            ws.perform("edit.insertTemplate", CommandArguments(["template": .string(id)]))
            return true
        }
        // Obiekt z Object Browsera upuszczony z klawiszem Option: wygenerowany kod zamiast nazwy (SD-GEN-001).
        if NSEvent.modifierFlags.contains(.option),
           let raw = sender.draggingPasteboard.string(forType: ObjectBrowserViewController.objectPasteboardType),
           let ws = (NSApp.delegate as? AppDelegate)?.workspace {
            let parts = raw.components(separatedBy: "\u{1}")
            if parts.count == 3, let type = DBObjectType(rawValue: parts[2]) {
                let kind: CodeGenerator.Kind? = [.table, .view, .materializedView, .synonym].contains(type) ? .select
                    : [.procedure, .function].contains(type) ? .call : nil
                if let kind {
                    let i = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
                    setSelectedRange(NSRange(location: i, length: 0))
                    window?.makeFirstResponder(self)
                    ws.perform("ob.generateCode", CommandArguments(["object": .string("\"\(parts[0])\".\"\(parts[1])\""), "type": .string(parts[2]),
                                                                    "kind": .string(kind.rawValue)]))
                    return true
                }
            }
        }
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            NSApp.delegate.flatMap { $0 as? AppDelegate }?.application(NSApp, open: urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    /// Liczba spacji do usunięcia Backspace w wiodących odstępach linii albo nil.
    private func unindentLength() -> Int? {
        let ns = string as NSString
        let caret = selectedRange().location
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        return SmartIndent.backspaceUnindent(lineBeforeCaret: ns.substring(with: NSRange(location: lineStart, length: caret - lineStart)), unit: indentUnit)
    }

    override func insertNewline(_ sender: Any?) {
        // Wcięcie nowej linii wg trybu (UG 23.12 None / Automatic / Smart, PD-EDIT-004).
        var ns = string as NSString
        let caret = selectedRange().location
        var lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        if indentMode == .smart, selectedRange().length == 0 {
            // Smart: END/ELSE/ELSIF/EXCEPTION wyrównane do poziomu struktury przed przejściem do nowej linii.
            let line = ns.substring(with: NSRange(location: lineRange.location, length: caret - lineRange.location))
            var previous: String?
            var p = lineRange.location
            while p > 0 {
                let r = ns.lineRange(for: NSRange(location: p - 1, length: 0))
                let s = ns.substring(with: r).trimmingCharacters(in: .newlines)
                if !s.trimmingCharacters(in: .whitespaces).isEmpty { previous = s; break }
                p = r.location
            }
            if let fixed = SmartIndent.reindentClosingLine(line, previous: previous, unit: indentUnit) {
                let r = NSRange(location: lineRange.location, length: caret - lineRange.location)
                if shouldChangeText(in: r, replacementString: fixed) {
                    replaceCharacters(in: r, with: fixed)
                    didChangeText()
                    setSelectedRange(NSRange(location: lineRange.location + (fixed as NSString).length, length: 0))
                }
                ns = string as NSString
                lineRange = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
            }
        }
        let before = ns.substring(with: NSRange(location: lineRange.location, length: selectedRange().location - lineRange.location))
        let indent = SmartIndent.newlineIndent(lineBeforeCaret: before, mode: indentMode, unit: indentUnit)
        super.insertNewline(sender)
        if !indent.isEmpty { insertText(indent, replacementRange: selectedRange()) }
    }

    override func insertTab(_ sender: Any?) {
        if selectedRange().length > 0 { shiftSelection(by: 1) } else { insertText(indentUnit, replacementRange: selectedRange()) }
    }

    override func insertBacktab(_ sender: Any?) { shiftSelection(by: -1) }

    private func shiftSelection(by direction: Int) {
        let ns = string as NSString
        let lines = ns.lineRange(for: selectedRange())
        var text = ns.substring(with: lines)
        let parts = text.components(separatedBy: "\n")
        let changed = parts.enumerated().map { i, l -> String in
            if i == parts.count - 1 && l.isEmpty { return l }
            if direction > 0 { return indentUnit + l }
            if l.hasPrefix(indentUnit) { return String(l.dropFirst(indentUnit.count)) }
            if l.hasPrefix("\t") { return String(l.dropFirst()) }
            return String(l.drop { $0 == " " })
        }
        text = changed.joined(separator: "\n")
        if shouldChangeText(in: lines, replacementString: text) {
            replaceCharacters(in: lines, with: text)
            didChangeText()
            setSelectedRange(NSRange(location: lines.location, length: (text as NSString).length))
        }
    }
}

/// Margines z numerami linii (UG 23.12 „Display line numbers”); bieżąca linia wyróżniona. Rysuje tylko linie
/// widoczne w obszarze przewijania (fragmenty układu TextKit 2 z zakresu viewportu).
final class LineNumberRulerView: NSView {
    private weak var textView: NSTextView?
    private let highlighter: SyntaxHighlighter
    /// Stan znacznika zwijania linii: nil — brak obszaru, true — zwinięty, false — rozwinięty.
    var foldState: ((Int) -> Bool?)?
    var onFoldClick: ((Int) -> Void)?
    /// Linie (od 0) z punktami przerwania i przełączenie kliknięciem w numer linii (UG 5.10).
    var breakpointLines: (() -> Set<Int>)?
    /// Pokrycie utPLSQL: linie (od 0) pokryte i niepokryte (UT-COV-002).
    var coverageLines: (() -> (covered: Set<Int>, uncovered: Set<Int>, partial: Set<Int>))?
    var onBreakpointClick: ((Int) -> Void)?
    /// Zakładki: linia (od 0) → numer 0–9 (PD-EDIT-011).
    var bookmarkLines: (() -> [Int: Int])?
    /// Status linii (od 0) względem stanu z otwarcia/zapisu: zmieniona — pomarańczowy, nowa — zielony pasek (PD-EDIT-003).
    var lineStatus: [Int: LineChange] = [:]
    /// Numer co n-tą linię (pierwsza i bieżąca zawsze).
    var interval = 1
    /// Linie widocznych fragmentów (y w układzie marginesu) — do trafienia kliknięciem.
    private var drawnLines: [(line: Int, minY: CGFloat, maxY: CGFloat)] = []

    init(textView: NSTextView, highlighter: SyntaxHighlighter) {
        self.textView = textView
        self.highlighter = highlighter
        super.init(frame: .zero)
        setAccessibilityElement(false)
        clipsToBounds = true      // tło marginesu nie może zamalować widoków nad edytorem
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = drawnLines.first(where: { p.y >= $0.minY && p.y < $0.maxY }) else { return super.mouseDown(with: event) }
        if p.x < 14, foldState?(hit.line) != nil { onFoldClick?(hit.line); return }
        if let onBreakpointClick { onBreakpointClick(hit.line); return }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let area = dirtyRect.intersection(bounds)
        NSColor.textBackgroundColor.setFill()
        area.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: area.minY, width: 1, height: area.height).fill()
        guard let tv = textView, let tlm = tv.textLayoutManager, let content = tlm.textContentManager else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, (tv.font?.pointSize ?? 13) - 2), weight: .regular)
        let caretLine = highlighter.line(containing: tv.selectedRange().location)
        let visible = tv.visibleRect
        let inset = tv.textContainerInset.height
        let lineHeight = tv.font.map { $0.ascender - $0.descender + $0.leading } ?? 16
        func label(_ line: Int, y: CGFloat, height: CGFloat) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: line == caretLine ? NSColor.labelColor : NSColor.tertiaryLabelColor]
            if let s = lineStatus[line] {
                (s == .added ? NSColor.systemGreen : NSColor.systemOrange).withAlphaComponent(0.85).setFill()
                NSRect(x: 0, y: y, width: 2.5, height: height).fill()
            }
            // Pokrycie: pasek przy prawej krawędzi marginesu.
            if cov.covered.contains(line) || cov.uncovered.contains(line) {
                // Zielony — pokryta, żółty — częściowo (nie wszystkie bloki), czerwony — niepokryta (UT-COV-002).
                (cov.partial.contains(line) ? NSColor.systemYellow : cov.covered.contains(line) ? NSColor.systemGreen : NSColor.systemRed)
                    .withAlphaComponent(0.8).setFill()
                NSRect(x: bounds.width - 5, y: y, width: 3, height: height).fill()
            }
            if bps.contains(line) {
                // Punkt przerwania: czerwone kółko pod numerem linii.
                let d = min(height, lineHeight) - 2
                NSColor.systemRed.withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: bounds.width - 8 - d - 10, y: y + 1, width: d, height: d)).fill()
            }
            if let n = marks[line] {
                // Zakładka: numer w zaokrąglonym znaczniku przy lewej krawędzi (obok znacznika zwijania).
                let badge = NSAttributedString(string: "\(n)", attributes: [.font: NSFont.boldSystemFont(ofSize: max(8, font.pointSize - 2)), .foregroundColor: NSColor.white])
                let h = min(height, lineHeight) - 2
                let box = NSRect(x: 13, y: y + 1, width: max(10, badge.size().width + 4), height: h)
                NSColor.systemBlue.setFill()
                NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
                badge.draw(at: NSPoint(x: box.midX - badge.size().width / 2, y: box.midY - badge.size().height / 2))
            }
            if LineNumbering.shows(line: line, caretLine: caretLine, interval: interval) {
                let s = NSAttributedString(string: "\(line + 1)", attributes: attrs)
                let size = s.size()
                s.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + (min(height, lineHeight) - size.height) / 2))
            } else if (line + 1) % max(1, interval / 2) == 0 {
                // Kreska między numerami (jak w edytorach z interwałem numeracji).
                NSColor.quaternaryLabelColor.setFill()
                NSRect(x: bounds.width - 14, y: y + min(height, lineHeight) / 2, width: 6, height: 1).fill()
            }
            drawnLines.append((line, y, y + height))
            if let folded = foldState?(line) {
                let marker = NSAttributedString(string: folded ? "▸" : "▾", attributes: [.font: font, .foregroundColor: folded ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor])
                marker.draw(at: NSPoint(x: 3, y: y + (min(height, lineHeight) - marker.size().height) / 2))
            }
        }
        drawnLines.removeAll(keepingCapacity: true)
        let bps = breakpointLines?() ?? []
        let marks = bookmarkLines?() ?? [:]
        let cov = coverageLines?() ?? (covered: Set<Int>(), uncovered: Set<Int>(), partial: Set<Int>())
        if content.documentRange.isEmpty {
            label(0, y: inset - visible.minY, height: lineHeight)
            return
        }
        let start = tlm.textViewportLayoutController.viewportRange?.location ?? tlm.documentRange.location
        var lastFrame = NSRect.zero
        tlm.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.maxY < visible.minY - 50 { return true }
            if frame.minY > visible.maxY + 50 { return false }
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            label(self.highlighter.line(containing: offset), y: frame.minY + inset - visible.minY, height: frame.height)
            lastFrame = frame
            return true
        }
        // Pusta ostatnia linia po końcowym znaku nowej linii nie ma własnego fragmentu.
        if tv.string.hasSuffix("\n"), lastFrame.maxY < visible.maxY {
            label(highlighter.lineStarts.count - 1, y: lastFrame.maxY + inset - visible.minY, height: lineHeight)
        }
    }
}
