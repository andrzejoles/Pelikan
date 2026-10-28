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
    /// Licznik zmian znaków w magazynie tekstu — wyniki analiz w tle przyjmowane tylko dla niezmienionego tekstu,
    /// bez porównywania całych łańcuchów (`textView.string` kopiuje cały dokument).
    private var textEdits = 0
    /// Wersja tekstu dokumentu (`textRevision`) zgodna z widokiem — `syncFromModel` przy samej zmianie zaznaczenia
    /// nie porównuje całego tekstu.
    private var syncedRevision = -1
    private var pairRanges: [NSTextRange] = []
    /// Wystąpienia nazwy pod kursorem i polecenia transakcyjne (PD-EDIT-018, PD-PROG-015) — osobne kolory.
    private var occurrenceRanges: [NSTextRange] = []
    private var transactionRanges: [NSTextRange] = []
    private var analysisWork: DispatchWorkItem?
    private var analyzedText: String?
    private var diagnostics: [EditorDiagnostic] = []
    var onCaretChange: ((String) -> Void)?
    /// Krój i grubość czcionki, z którymi zbudowano `font` (zmiana w Preferencjach — przebudowa).
    private var fontKey = ""

    // MARK: Karty jednostek okna programu (D192)

    /// Odcinki jednostek (okno programu z co najmniej dwiema jednostkami): edytor pokazuje tylko odcinek karty z kursorem,
    /// resztę tekstu ukrywa tym samym mechanizmem co zwijanie (`FoldingContentDelegate`). Ustawia okno programu po
    /// analizie w tle; przy pisaniu edytor sam przesuwa granice.
    var unitTabs: [ProgramUnitTab] {
        get { tabs }
        set {
            tabs = newValue
            secondary?.unitTabs = newValue
            let before = shownTab
            showTab(containing: textView.selectedRange().location, force: true)
            // Karta zmieniona po analizie w tle (okno otwarte na linii, debuger, usunięcie jednostki) — `showTab`
            // przewinął na początek karty, a `syncFromModel` nie przewinie (zaznaczenie już ustawione): do kursora.
            if shownTab != before {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.scrollToSelection(self.textView.selectedRange())
                }
            }
        }
    }
    private var tabs: [ProgramUnitTab] = []
    /// Karta, której odcinek jest widoczny (nil — okno bez kart).
    private(set) var shownTab: Int?
    /// Zmiana karty widocznej (pasek kart okna programu, Code Contents).
    var onShownTabChange: ((Int?) -> Void)?
    /// Ukryte zakresy zwinięć (bez odcinków innych kart).
    private var foldHidden: [Range<Int>] = []
    /// Zaznaczenie z modelu (komenda, nawigacja) — może przejść na inną kartę; zaznaczenie z klawiatury i myszy
    /// zostaje na karcie widocznej.
    private var applyingModelSelection = false
    /// Widok ma dodatkowe kursory z modelu (do zdjęcia, gdy model je wyczyści).
    private var appliedExtraSelections = false

    init(document: Document, fontSize: CGFloat = 13, secondary: Bool = false) {
        self.document = document
        let ws0 = (NSApp.delegate as? AppDelegate)?.workspace
        ligatures = ws0?.settings.editorLigatures ?? true
        font = Self.makeFont(name: ws0?.settings.editorFontName ?? "SF Mono", size: fontSize, weight: ws0?.settings.editorFontWeight ?? .regular,
                             ligatures: ligatures)
        fontKey = ws0.map { $0.settings.editorFontName + "|" + $0.settings.editorFontWeight.rawValue } ?? ""
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
            // Własne kolory edytora (PD-PREF-005) — tło jako baza odcienia połączenia.
            let colors = ws.settings.editorColors
            let base = colors.background.map { NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } ?? .textBackgroundColor
            SyntaxTheme.customPlain = colors.text.map { NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
            self.textView.insertionPointColor = SyntaxTheme.customPlain ?? .textColor
            if ws.settings.colorWindowBackground, let c = ws.indicatorColor(for: self.document) {
                self.textView.backgroundColor = base.blended(withFraction: 0.08, of: NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)) ?? base
            } else {
                self.textView.backgroundColor = base
            }
            self.textView.needsDisplay = true
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
            let key = ws.settings.editorFontName + "|" + ws.settings.editorFontWeight.rawValue
            if size != self.font.pointSize || lig != self.ligatures || key != self.fontKey {
                self.ligatures = lig
                self.fontKey = key
                self.setFontSize(size)
            }
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
            // Zatrzymany debuger: wartość zmiennej pod myszą (PD-DBG-005).
            if [.test, .program].contains(self.document.kind), let ws = (NSApp.delegate as? AppDelegate)?.workspace,
               let word = DebugHover.word(in: self.textView.string, at: offset), let v = ws.debugHoverText(word) {
                return v
            }
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
    private var colorMarkRanges: [(range: NSTextRange, color: NSColor)] = []
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
            s.unitTabs = unitTabs
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
        for r in colorMarkRanges { tlm.removeRenderingAttribute(.backgroundColor, for: r.range) }
        let len = textView.textLength
        colorMarkRanges = []
        for m in marks where m.range.upperBound <= len {
            guard let a = content.location(content.documentRange.location, offsetBy: m.range.lowerBound),
                  let b = content.location(a, offsetBy: m.range.count), let r = NSTextRange(location: a, end: b) else { continue }
            let color = Self.colorMarkPalette[max(0, min(Self.colorMarkPalette.count - 1, m.color - 1))].withAlphaComponent(0.3)
            colorMarkRanges.append((r, color))
        }
        applyBackgrounds()
    }

    /// Zaznaczenia z modelu → zaznaczenia widoku (pierwsze — główne).
    private func applyAdditionalSelections(_ extra: [Range<Int>]) {
        // Bez dodatkowych kursorów zaznaczenie główne stosuje tylko `syncFromModel` (przewinięcie, zwinięcia, karta
        // jednostki). Wcześniej ten obserwator — także śledzący `selectedRange` — wyprzedzał go i ustawiał zaznaczenie
        // widoku bez przewinięcia, a `syncFromModel` widział je już ustawione i nie przewijał: przejścia z kart, Code
        // Contents, Idź do linii zostawiały widok w miejscu (D192).
        guard !extra.isEmpty || appliedExtraSelections else { return }
        appliedExtraSelections = !extra.isEmpty
        let len = textView.textLength
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
        NotificationCenter.default.addObserver(self, selector: #selector(storageWillProcessEditing(_:)),
                                               name: NSTextStorage.willProcessEditingNotification, object: textView.textStorage)
        textView.setAccessibilityLabel(document.fullTitle)
        textView.textContentStorage?.delegate = folding
        configureCompletion()
        // Numery linii karty jednostki jak w ALL_SOURCE/ALL_ERRORS (linia 1 = linia słowa typu, D189/D192).
        ruler.displayNumber = { [weak self] line in
            guard let self else { return line + 1 }
            return self.displayLine(line)
        }
        ruler.showsLastLine = { [weak self] in
            guard let self, let t = self.shownTab else { return true }
            return t == self.unitTabs.count - 1
        }
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
        ruler.unappliedBreakpointLines = { [weak self] in
            guard let self, self.document.kind == .program, let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return [] }
            return Set(ws.breakpointLines(in: self.document, onlyUnapplied: true).map { $0 - 1 })
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
        textView.lineStart = { [weak self] line in
            guard let starts = self?.highlighter.lineStarts, line >= 0, line < starts.count else { return nil }
            return starts[line]
        }
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            self.textView.executionLine = self.document.executionLine
            if let ws = (NSApp.delegate as? AppDelegate)?.workspace { _ = ws.breakpoints; _ = ws.unappliedBreakpoints; _ = ws.lastUtplsqlRun?.coverage }
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
            ruler.widthAnchor.constraint(equalToConstant: 50),
            scrollView.topAnchor.constraint(equalTo: pane.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: ruler.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])
        embedPane()
        scrollView.contentView.postsBoundsChangedNotifications = true
        // Obserwator z selektorem — wyrejestrowany sam przy zwolnieniu widoku (blokowy zostawał w NotificationCenter).
        NotificationCenter.default.addObserver(self, selector: #selector(contentBoundsDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @objc private func contentBoundsDidChange(_ note: Notification) {
        ruler.needsDisplay = true
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
        syncedRevision = document.textRevision
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
        textView.onFocusLost = { [weak self] in self?.completion.close() }
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
        guard caret > 0, caret <= textView.textLength, textView.textStorage?.mutableString.character(at: caret - 1) == 0x2E else { return }
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
        let text = textView.string, edits = textEdits
        let ws = (NSApp.delegate as? AppDelegate)?.workspace
        let occurrencesOn = ws?.settings.highlightOccurrences ?? true
        let transactionsOn = ws?.settings.highlightTransactions ?? true
        Task.detached(priority: .utility) {
            let selection = sel.location..<(sel.location + sel.length)
            // Pary (nawiasy, bloki, INSERT ↔ VALUES) tylko przy kursorze; wystąpienia także dla zaznaczonego słowa.
            let pairs = sel.length == 0 ? PairMatcher.pairs(text, offset: sel.location) + PairMatcher.insertValuesPair(text, offset: sel.location) : []
            let occurrences = occurrencesOn ? PairMatcher.occurrences(text, selection: selection) : []
            let transactions = transactionsOn ? PairMatcher.transactionStatements(text) : []
            await MainActor.run { [weak self] in
                guard let self, self.pairGeneration == generation, self.textEdits == edits else { return }
                self.pairRanges = self.show(pairs, replacing: self.pairRanges)
                self.occurrenceRanges = self.show(occurrences, replacing: self.occurrenceRanges)
                self.transactionRanges = self.show(transactions, replacing: self.transactionRanges)
                self.applyBackgrounds()
            }
        }
    }

    /// Zakresy tła warstwy (atrybut renderowania — bez zmiany tekstu): usuwa tło starych, zwraca nowe — tło nakłada
    /// `applyBackgrounds`.
    private func show(_ ranges: [Range<Int>], replacing old: [NSTextRange]) -> [NSTextRange] {
        guard let tlm = textView.textLayoutManager, let content = tlm.textContentManager else { return [] }
        for r in old { tlm.removeRenderingAttribute(.backgroundColor, for: r) }
        let new = ranges.compactMap { r -> NSTextRange? in
            guard let a = content.location(content.documentRange.location, offsetBy: r.lowerBound),
                  let b = content.location(a, offsetBy: r.count) else { return nil }
            return NSTextRange(location: a, end: b)
        }
        return new
    }

    /// Wszystkie warstwy tła (znaczniki kolorów, polecenia transakcyjne, wystąpienia nazwy, pary) używają tego samego
    /// atrybutu `.backgroundColor` — usunięcie jednej wycina tło pozostałych w tych miejscach. Dlatego po każdej zmianie
    /// warstwy nakładane są wszystkie, od spodu (R4-08).
    private func applyBackgrounds() {
        guard let tlm = textView.textLayoutManager else { return }
        for m in colorMarkRanges { tlm.addRenderingAttribute(.backgroundColor, value: m.color, for: m.range) }
        for (ranges, color) in [(transactionRanges, NSColor.systemOrange.withAlphaComponent(0.18)),
                                (occurrenceRanges, NSColor.systemYellow.withAlphaComponent(0.22)),
                                (pairRanges, NSColor.findHighlightColor.withAlphaComponent(0.35))] {
            for r in ranges { tlm.addRenderingAttribute(.backgroundColor, value: color, for: r) }
        }
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
        // Atrybuty magazynu tekstu, nie renderowania: TextKit 2 nie rysuje podkreślenia z atrybutów renderowania
        // (podkreślenia były niewidoczne — wykryte zrzutem w tle). Zmiana atrybutów nie zmienia tekstu ani historii cofania;
        // kolorowanie składni nadpisuje edytowaną linię, a analiza po zmianie nakłada podkreślenia ponownie.
        guard let storage = textView.textStorage else { return }
        let len = storage.length
        storage.beginEditing()
        storage.removeAttribute(.underlineStyle, range: NSRange(location: 0, length: len))
        storage.removeAttribute(.underlineColor, range: NSRange(location: 0, length: len))
        for d in list where d.range.upperBound <= len && !d.range.isEmpty {
            let r = NSRange(location: d.range.lowerBound, length: d.range.count)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue, range: r)
            storage.addAttribute(.underlineColor, value: d.severity == .error ? NSColor.systemRed : NSColor.systemOrange, range: r)
        }
        storage.endEditing()
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
            let text = self.textView.string, edits = self.textEdits
            Task.detached(priority: .userInitiated) {
                let r = CodeFolding.regions(text)
                await MainActor.run { [weak self] in
                    guard let self, self.textEdits == edits else { return }
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
            let text = self.textView.string, baseline = self.document.baselineText, edits = self.textEdits
            Task.detached(priority: .utility) {
                let status = TextDiff.lineStatus(baseline: baseline, current: text)
                await MainActor.run { [weak self] in
                    guard let self, self.textEdits == edits else { return }
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
        foldHidden = hidden
        // Znacznik „⋯” tylko przy zwinięciach widocznych (nie wewnątrz innego zwiniętego obszaru).
        textView.foldedLines = regions.filter { r in folded.contains(r.start) && !hidden.contains { $0.contains(r.start) } }.map(\.start)
        updateHidden()
    }

    /// Ukryte akapity: zwinięcia i odcinki kart innych niż widoczna (posortowane, rozłączne). Zmiana — ponowny układ.
    private func updateHidden(invalidate: Bool = true) {
        let combined = Self.merged(foldHidden + unitHidden())
        guard combined != folding.hidden else { return }
        folding.hidden = combined
        guard invalidate else { return }
        // Ponowny układ potrafi zgłosić zmianę zaznaczenia ze starym zaznaczeniem widoku — bez zapisu do modelu
        // (inaczej nadpisałoby właśnie ustawione zaznaczenie z komendy i skok „nic nie robił”).
        let wasUpdating = updatingFromModel
        updatingFromModel = true
        defer { updatingFromModel = wasUpdating }
        if let tlm = textView.textLayoutManager {
            tlm.invalidateLayout(for: tlm.documentRange)
            tlm.textViewportLayoutController.layoutViewport()
        }
        textView.needsDisplay = true
        ruler.needsDisplay = true
        scheduleViewportRefresh()
    }

    private var viewportRefreshScheduled = false

    /// Drugi układ obszaru widoku po bieżącym obiegu pętli: widok tekstu zmienia wysokość dopiero po układzie, a fragmenty
    /// poza poprzednią wysokością (dolne linie po zmianie karty, po dopisaniu tekstu z komendy) zostawały puste — numery
    /// w marginesie były, tekstu nie — do kliknięcia albo przewinięcia.
    private func scheduleViewportRefresh() {
        guard !viewportRefreshScheduled else { return }
        viewportRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewportRefreshScheduled = false
            // Układ potrafi zgłosić zmianę zaznaczenia ze starym zaznaczeniem widoku — bez zapisu do modelu (jak w updateHidden).
            let wasUpdating = self.updatingFromModel
            self.updatingFromModel = true
            defer { self.updatingFromModel = wasUpdating }
            self.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
            self.textView.needsDisplay = true
            self.ruler.needsDisplay = true
        }
    }

    private func unitHidden() -> [Range<Int>] {
        guard let t = shownTab, unitTabs.indices.contains(t) else { return [] }
        let seg = unitTabs[t].segment, len = textView.textLength
        var out: [Range<Int>] = []
        if seg.lowerBound > 0 { out.append(0..<min(seg.lowerBound, len)) }
        if seg.upperBound < len { out.append(seg.upperBound..<len) }
        return out
    }

    static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for r in ranges.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, r.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// Karta odcinka z pozycją (okno z kartami).
    private func tab(containing offset: Int) -> Int? {
        unitTabs.count > 1 ? ProgramUnitTabs.index(of: offset, in: unitTabs) : nil
    }

    /// Pokazuje kartę odcinka z pozycją (przejście w inne miejsce tekstu przełącza kartę samo).
    private func showTab(containing offset: Int, force: Bool = false) {
        let t = tab(containing: offset)
        guard t != shownTab || force else { return }
        let changed = t != shownTab
        shownTab = t
        // Nowa karta od początku (stare przesunięcie dotyczyło innego odcinka); cel przewija potem `scrollToSelection`.
        if changed { scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: 0)) }
        updateHidden()
        if changed {
            ruler.needsDisplay = true
            onShownTabChange?(t)
        }
    }

    /// Karty policzone od razu (zmiana obejmująca granicę kart: Zamień wszystko, formatowanie całości, Przywróć,
    /// cofnięcie takich zmian) — przesunięte granice nie odpowiadałyby jednostkom do analizy w tle.
    private func recomputeTabsNow() {
        guard document.kind == .program else { return }
        let text = textView.string
        unitTabs = ProgramUnitTabs.tabs(ProgramCompiler.units(in: text), in: text)
    }

    /// Najdalsza pozycja kursora na widocznej karcie i jej początek.
    private func visibleBounds() -> (lower: Int, upper: Int)? {
        guard let t = shownTab, unitTabs.indices.contains(t), let ns = textView.textStorage?.mutableString else { return nil }
        let tab = unitTabs[t]
        return (min(tab.segment.lowerBound, ns.length), ProgramUnitTabs.caretLimit(tab, isLast: t == unitTabs.count - 1, in: ns))
    }

    /// Numer linii w marginesie i na pasku: na karcie jednostki — linia jednostki (Oracle), przed słowem typu — nil.
    func displayLine(_ line: Int) -> Int? {
        guard let t = shownTab, unitTabs.indices.contains(t) else { return line + 1 }
        return ProgramUnitTabs.unitLine(documentLine: line, sourceLine: highlighter.line(containing: unitTabs[t].sourceOffset))
    }

    /// Przewinięcie do zaznaczenia po zmianie karty albo skoku. TextKit 2 układa tylko widoczny fragment, a położenie
    /// reszty szacuje — po zmianie ukrytych akapitów (inna karta) szacunek bywa daleki od celu i `scrollRangeToVisible`
    /// trafia obok. Po przewinięciu układ widocznego obszaru poprawia szacunek; gdy cel nadal jest poza widokiem —
    /// przewinięcie do jego (już dokładniejszej) ramki, kilka razy. Bez układu całego tekstu od początku karty (pakiet
    /// 50 000 linii — sekundy). Cel w jednej trzeciej wysokości widoku, nie przy krawędzi.
    private func scrollToSelection(_ r: NSRange) {
        textView.scrollRangeToVisible(r)
        guard let tlm = textView.textLayoutManager, let content = tlm.textContentManager,
              let b = content.location(content.documentRange.location, offsetBy: r.location) else { return }
        for _ in 0..<4 {
            tlm.textViewportLayoutController.layoutViewport()
            tlm.ensureLayout(for: NSTextRange(location: b))
            guard let f = tlm.textLayoutFragment(for: b)?.layoutFragmentFrame else { return }
            let rect = NSRect(x: 0, y: f.minY + textView.textContainerInset.height, width: 1, height: f.height)
            let visible = scrollView.contentView.bounds
            if rect.minY >= visible.minY, rect.maxY <= visible.maxY { break }
            scrollView.contentView.scroll(to: NSPoint(x: visible.minX, y: max(0, rect.minY - visible.height / 3)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        textView.scrollRangeToVisible(r)
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
        // Sama zmiana zaznaczenia nie zmienia wersji tekstu — bez porównania całego dokumentu.
        // Przewinięcie do kursora po zmianie tekstu z modelu tylko, gdy kursor był widoczny albo zmiana go obejmuje —
        // edycja agenta w innym miejscu, Zamień wszystko czy formatowanie nie odrywają od czytanego fragmentu.
        var followCaret = false
        if document.textRevision != syncedRevision, text != textView.string {
            let caret = textView.selectedRange().location
            let wasVisible = isVisible(caret)
            let changed = applyExternal(text)
            scheduleAnalysis()
            followCaret = wasVisible || (caret >= changed.location && caret <= NSMaxRange(changed))
        } else {
            syncedRevision = document.textRevision
        }
        let len = textView.textLength
        let current = textView.selectedRange()
        let wanted = NSRange(location: min(selection.lowerBound, len), length: max(0, min(selection.upperBound, len) - min(selection.lowerBound, len)))
        // Przy podziale edytora zaznaczenie z modelu stosuje tylko widok, w którym nie pisze się właśnie w drugim.
        let peerActive = peer.map { $0.window?.firstResponder === $0.textView } ?? false
        if !updatingFromModel, current != wanted, !peerActive, document.additionalSelections.isEmpty {
            revealSelection(wanted.location)
            showTab(containing: wanted.location)
            applyingModelSelection = true
            textView.setSelectedRange(wanted)
            applyingModelSelection = false
            scrollToSelection(wanted)
            selectionDidChange()
        } else if followCaret, current == wanted {
            // Zmiana tekstu z komendy (np. Powiel linię): widok sam przesunął kursor tam, gdzie chce model — bez
            // zmiany zaznaczenia nie było przewinięcia do kursora ani odświeżenia pozycji na pasku.
            DispatchQueue.main.async { [weak self] in
                self?.scrollToSelection(wanted)
                self?.scheduleViewportRefresh()
            }
            selectionDidChange()
        }
        if let error {
            let r = NSRange(location: min(error.lowerBound, len), length: 0)
            showTab(containing: r.location)
            applyingModelSelection = true
            textView.setSelectedRange(r)
            applyingModelSelection = false
            scrollToSelection(r)
            // Zaznacz słowo z błędem (NF15: podkreślenie całego słowa).
            let word = textView.selectionRange(forProposedRange: r, granularity: .selectByWord)
            if word.length > 0 { textView.showFindIndicator(for: word) }
            // Błąd zaznaczany raz: bez wyczyszczenia każda zmiana zaznaczenia (klik, strzałka) uruchamiałaby to
            // śledzenie ponownie i kursor wracałby na błąd. Ponowne wykonanie albo kompilacja ustawia go od nowa.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.document.errorRange == error else { return }
                self.document.errorRange = nil
            }
        }
    }

    /// Zwraca zakres zmienionego fragmentu w starym tekście.
    @discardableResult
    private func applyExternal(_ text: String) -> NSRange {
        let old = textView.string as NSString
        let new = text as NSString
        // Wspólny początek i koniec — zamieniamy tylko środek.
        var prefix = 0
        let minLen = min(old.length, new.length)
        while prefix < minLen, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < minLen - prefix, old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        var range = NSRange(location: prefix, length: old.length - prefix - suffix)
        var replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        // Czyste wstawienie wypadające na granicy kart, gdy można je przesunąć o znak w lewo (tekst kończy się tym samym
        // znakiem co ten przed granicą — zwykle „\n”): np. Powiel linię w ostatniej linii karty wstawia kopię na końcu
        // tej karty, a najmniejsza różnica wskazuje początek następnej (tekst na granicy należy do karty późniejszej).
        let rep = replacement as NSString
        if range.length == 0, range.location > 0,
           ProgramUnitTabs.appliesBeforeBoundary(tabs, shownTab: shownTab, location: range.location, inserted: replacement,
                                                 characterBefore: old.character(at: range.location - 1),
                                                 selectionAfter: document.selectedRange.lowerBound) {
            replacement = old.substring(with: NSRange(location: range.location - 1, length: 1)) + rep.substring(to: rep.length - 1)
            range.location -= 1
        }
        updatingFromModel = true
        defer { updatingFromModel = false }
        // Także wstawienie do pustego okna i pełna zamiana dużego tekstu idą przez shouldChangeText — jedna operacja
        // cofania; `textView.string =` nie rejestrowało cofania, a na stosie zostawały zakresy starego tekstu.
        let whole = range.length == old.length && old.length > 200_000
        // Model jest źródłem prawdy: zmiana z modelu trafia do widoku także w oknie chwilowo nieedytowalnym (wykonanie,
        // tylko do odczytu) — inaczej widok pokazywałby stary tekst, a ⌘S zapisał niewidoczny (R4-06).
        let editable = textView.isEditable
        textView.isEditable = true
        defer { textView.isEditable = editable }
        if textView.shouldChangeText(in: range, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            syncedRevision = document.textRevision
        }
        if let storage = textView.textStorage {
            if whole {
                highlighter.highlightAll(storage, font: font)
            } else {
                highlighter.highlight(storage, editedRange: NSRange(location: range.location, length: (replacement as NSString).length),
                                      delta: (replacement as NSString).length - range.length, font: font)
            }
        }
        ruler.needsDisplay = true
        scheduleRegions()
        return NSRange(location: prefix, length: old.length - prefix - suffix)
    }

    /// Czy pozycja jest w widocznym obszarze edytora (przed zmianą tekstu — czy przewijać potem do kursora).
    private func isVisible(_ offset: Int) -> Bool {
        guard let tlm = textView.textLayoutManager, let content = tlm.textContentManager,
              let loc = content.location(content.documentRange.location, offsetBy: min(offset, textView.textLength)),
              let f = tlm.textLayoutFragment(for: loc)?.layoutFragmentFrame else { return false }
        let line = f.offsetBy(dx: 0, dy: textView.textContainerInset.height)
        return line.maxY > textView.visibleRect.minY && line.minY < textView.visibleRect.maxY
    }

    // MARK: Podświetlanie przyrostowe (po każdej edycji magazynu tekstu)

    /// Zmiana obejmująca granicę kart wykryta przed przetworzeniem edycji (karty liczone potem od razu).
    private var pendingSpansBoundary = false

    /// Granice kart i ukryte zakresy przesuwane przed przetworzeniem edycji: magazyn treści tworzy akapity zmienionego
    /// fragmentu w trakcie przetwarzania i może wtedy pytać delegata, czy je pokazać — zakresy mają już odpowiadać
    /// nowemu tekstowi. Bez ponownego układu całości.
    @objc private func storageWillProcessEditing(_ note: Notification) {
        guard let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters),
              !unitTabs.isEmpty || !foldHidden.isEmpty else { return }
        let editedRange = storage.editedRange
        let delta = storage.changeInLength
        let edited = editedRange.location..<(editedRange.location + editedRange.length)
        let oldEnd = edited.upperBound - delta
        // Zmiana obejmująca granicę kart (w starym tekście granica wewnątrz zastąpionego fragmentu).
        pendingSpansBoundary = tabs.dropFirst().contains { $0.segment.lowerBound > edited.lowerBound && $0.segment.lowerBound < oldEnd }
        if !tabs.isEmpty { tabs = ProgramUnitTabs.shift(tabs, edited: edited, delta: delta) }
        // Wstawienie na początku ukrytego zakresu jest przed nim (widoczne), na jego końcu — za nim.
        let pure = oldEnd == edited.lowerBound
        func moveLower(_ o: Int) -> Int { o < edited.lowerBound ? o : o >= oldEnd ? o + delta : edited.upperBound }
        func moveUpper(_ o: Int) -> Int { o < edited.lowerBound || (pure && o == edited.lowerBound) ? o : o >= oldEnd ? o + delta : edited.upperBound }
        foldHidden = Self.merged(foldHidden.map { moveLower($0.lowerBound)..<max(moveLower($0.lowerBound), moveUpper($0.upperBound)) })
        updateHidden(invalidate: false)
    }

    @objc private func storageDidProcessEditing(_ note: Notification) {
        guard let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
        textEdits &+= 1
        let editedRange = storage.editedRange
        let delta = storage.changeInLength
        // Obszary zwijania przesuwane od razu, tak jak klucze zwinięć w modelu (`Document.text`) — do przeliczenia
        // w tle `applyFolds` dopasowuje przesunięte klucze do przesuniętych obszarów, bez rozwijania i zwijania.
        if !regions.isEmpty {
            regions = CodeFolding.shift(regions, edited: editedRange.location..<(editedRange.location + editedRange.length), delta: delta)
        }
        if pendingSpansBoundary {
            pendingSpansBoundary = false
            DispatchQueue.main.async { [weak self] in self?.recomputeTabsNow() }
        }
        guard !updatingFromModel else { return }
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
        syncedRevision = document.textRevision
        document.errorRange = nil
        updatingFromModel = false
        if completion.isVisible { completion.textChanged() } else { scheduleAutomaticAssist() }
        scheduleAnalysis()
    }

    /// Kursor i zaznaczenie z klawiatury i myszy zostają na karcie widocznej (strzałki, ⌘A, ⇧⌘↓ nie wchodzą w ukryty
    /// tekst innych jednostek); zaznaczenie z modelu, cofanie i ponawianie — bez ograniczenia (przełączają kartę).
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue],
                  toCharacterRanges newSelectedCharRanges: [NSValue]) -> [NSValue] {
        guard !updatingFromModel, !applyingModelSelection, let b = visibleBounds(),
              !(textView.undoManager?.isUndoing ?? false), !(textView.undoManager?.isRedoing ?? false) else { return newSelectedCharRanges }
        let clamped = newSelectedCharRanges.map { v in
            let r = v.rangeValue
            let lo = min(max(r.location, b.lower), b.upper)
            let hi = min(max(r.location + r.length, b.lower), b.upper)
            return NSValue(range: NSRange(location: lo, length: hi - lo))
        }
        // Przycięte ruchem kursora z klawiatury (⌘↓, ⇧⌘↓): widok przewijał do ukrytego końca tekstu — przewinięcie do
        // kursora. ⌘A i przeciąganie myszą — bez przewijania.
        let proposed = newSelectedCharRanges.first?.rangeValue
        let selectAll = proposed.map { $0.location == 0 && $0.length == textView.textStorage?.length } ?? false
        if clamped != newSelectedCharRanges, NSApp.currentEvent?.type == .keyDown, !selectAll, let first = clamped.first?.rangeValue {
            DispatchQueue.main.async { [weak self] in self?.scrollToSelection(NSRange(location: first.location + first.length, length: 0)) }
        }
        return clamped
    }

    /// Edycja z klawiatury tylko w widocznej karcie — także usunięcie znaku nowej linii oddzielającego następną kartę.
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard !updatingFromModel, let b = visibleBounds(),
              !(textView.undoManager?.isUndoing ?? false), !(textView.undoManager?.isRedoing ?? false) else { return true }
        return affectedCharRange.location >= b.lower && affectedCharRange.location + affectedCharRange.length <= b.upper
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !updatingFromModel else { return }
        let r = textView.selectedRange()
        // Cofanie zmiany w innej jednostce — karta tej jednostki.
        if !applyingModelSelection, tab(containing: r.location) != shownTab {
            showTab(containing: r.location)
            DispatchQueue.main.async { [weak self] in self?.scrollToSelection(r) }
        }
        document.selectedRange = r.location..<(r.location + r.length)
        // Zaznaczenie kolumnowe (Option+przeciąganie) i dodatkowe kursory → model (PD-EDIT-007, PD-EDIT-023).
        let extra = textView.selectedRanges.dropFirst().map { $0.rangeValue }.map { $0.location..<($0.location + $0.length) }
        if document.additionalSelections != Array(extra) {
            updatingFromModel = true
            document.additionalSelections = Array(extra)
            updatingFromModel = false
        }
        selectionDidChange()
    }

    /// Pozycja na pasku, margines, pary i wystąpienia po zmianie kursora — także ustawionego z modelu (Idź do linii,
    /// nawigacja po błędach), gdy `textViewDidChangeSelection` jest pomijane. Po edycji początki linii przelicza
    /// podświetlanie w następnym obiegu pętli — pozycję liczymy po nim.
    private func selectionDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let r = self.textView.selectedRange()
            let line = self.highlighter.line(containing: r.location)
            let start = min(r.location, line < self.highlighter.lineStarts.count ? self.highlighter.lineStarts[line] : 0)
            // Kolumna i długość w znakach (jak kolumny Oracle), nie w jednostkach UTF-16 — emoji liczone raz.
            let ns: NSString = self.textView.textStorage?.mutableString ?? ""
            let col = TextEditing.characterCount(ns, range: NSRange(location: start, length: r.location - start))
            let length = TextEditing.characterCount(ns, range: r)
            let shown = self.displayLine(line).map(String.init) ?? "–"
            self.onCaretChange?(r.length > 0 ? "\(shown):\(col + 1) [\(length)]" : "\(shown):\(col + 1)")
            self.ruler.needsDisplay = true
            self.updatePairs()
            self.updateDiagnosticTip()
        }
    }

    func setFontSize(_ size: CGFloat) {
        let settings = (NSApp.delegate as? AppDelegate)?.workspace.settings
        font = Self.makeFont(name: settings?.editorFontName ?? font.familyName ?? "SF Mono", size: size, weight: settings?.editorFontWeight ?? .regular,
                             ligatures: ligatures)
        textView.font = font
        textView.typingAttributes[.font] = font
        if let storage = textView.textStorage { highlighter.highlightAll(storage, font: font) }
        ruler.needsDisplay = true
    }

    /// Czcionka edytora; bez ligatur — wyłączone ligatury typowe i kontekstowe alternatywy (PD-EDIT-021).
    static func makeFont(name: String, size: CGFloat, weight: FontWeightChoice = .regular, ligatures: Bool) -> NSFont {
        // „SF Mono” to systemowa czcionka o stałej szerokości (bez osobnej instalacji); inne kroje — z grubością (D178).
        let base = AppFonts.font(family: name == "SF Mono" ? "" : name, size: Double(size), weight: weight, monospaced: true)
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
    /// Początek linii (od 0) z tablicy podświetlania — linia debugera bez przechodzenia tekstu od początku przy
    /// każdym rysowaniu; nil — za końcem tekstu.
    var lineStart: ((Int) -> Int?)?
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
            let length = textLength
            var offset = 0
            if let lineStart {
                offset = lineStart(line - 1) ?? length
            } else if let ns = textStorage?.mutableString {
                var current = 1
                while current < line, offset < ns.length {
                    let r = ns.lineRange(for: NSRange(location: offset, length: 0))
                    offset = r.location + r.length
                    current += 1
                }
            }
            if let loc = content.location(content.documentRange.location, offsetBy: min(offset, length)),
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
        let fragment = tlm.textLayoutFragment(for: loc)
        var frame = fragment?.layoutFragmentFrame ?? .zero
        if frame == .zero || selectedRange().location == textLength && endsWithNewline {
            let h = (font?.ascender ?? 12) - (font?.descender ?? -3) + (font?.leading ?? 0)
            frame = NSRect(x: 0, y: fragment.map(trailingEmptyLineY) ?? 0, width: bounds.width, height: h)
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
        let ns: NSString = textStorage?.mutableString ?? ""
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
    /// Edytor traci fokus albo znika z okna (inna karta, siatka) — zamknięcie listy podpowiedzi (R4-13).
    var onFocusLost: (() -> Void)?

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusLost?() }
        return resigned
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { onFocusLost?() }
        super.viewWillMove(toWindow: newWindow)
    }

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
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // Szablon z okna szablonów: wstawienie w miejscu upuszczenia (formularz zmiennych, PD-TPL-002).
        if let data = sender.draggingPasteboard.data(forType: TemplatePane.pasteboardType), let ws = (NSApp.delegate as? AppDelegate)?.workspace {
            let id = String(decoding: data, as: UTF8.self)
            let i = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            setSelectedRange(NSRange(location: i, length: 0))
            window?.makeFirstResponder(self)
            ws.perform("edit.insertTemplate", CommandArguments(["template": .string(id)]))
            return true
        }
        // Obiekt z Object Browsera (PD-OB-010): z klawiszem Control albo przy preferencji „Pytaj” — menu (nazwa, kolumny,
        // SELECT/INSERT/UPDATE/DELETE, wywołanie, DDL); inna preferencja niż „Nazwa” — tekst wg preferencji.
        if !NSEvent.modifierFlags.contains(.option),
           let raw = sender.draggingPasteboard.string(forType: ObjectBrowserViewController.objectPasteboardType),
           let ws = (NSApp.delegate as? AppDelegate)?.workspace {
            let preferred = ws.settings.browserDropAction
            if let drag = BrowserObjectDrag(raw), let type = DBObjectType(rawValue: drag.type),
               NSEvent.modifierFlags.contains(.control) || preferred != .name {
                let point = convert(sender.draggingLocation, from: nil)
                let i = characterIndexForInsertion(at: point)
                setSelectedRange(NSRange(location: i, length: 0))
                window?.makeFirstResponder(self)
                // Obiekt z połączenia gałęzi drzewa (kolumny, DDL), nie z połączenia okna (D185).
                let args: (BrowserDropAction) -> CommandArguments = { a in drag.arguments(["action": .string(a.rawValue)]) }
                if NSEvent.modifierFlags.contains(.control) || preferred == .ask {
                    let menu = NSMenu()
                    for a in BrowserDropAction.actions(for: type) {
                        menu.addItem(ClosureMenuItem(title: a.displayName) { ws.perform("ob.dropText", args(a)) })
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        menu.popUp(positioning: nil, at: point, in: self)
                    }
                } else {
                    ws.perform("ob.dropText", args(preferred))
                }
                return true
            }
        }
        // Obiekt z Object Browsera upuszczony z klawiszem Option: wygenerowany kod zamiast nazwy (SD-GEN-001).
        if NSEvent.modifierFlags.contains(.option),
           let raw = sender.draggingPasteboard.string(forType: ObjectBrowserViewController.objectPasteboardType),
           let ws = (NSApp.delegate as? AppDelegate)?.workspace {
            if let drag = BrowserObjectDrag(raw), let type = DBObjectType(rawValue: drag.type) {
                let kind: CodeGenerator.Kind? = [.table, .view, .materializedView, .synonym].contains(type) ? .select
                    : [.procedure, .function].contains(type) ? .call : nil
                if let kind {
                    let i = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
                    setSelectedRange(NSRange(location: i, length: 0))
                    window?.makeFirstResponder(self)
                    ws.perform("ob.generateCode", drag.arguments(["kind": .string(kind.rawValue)]))
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
    var unappliedBreakpointLines: (() -> Set<Int>)?
    /// Pokrycie utPLSQL: linie (od 0) pokryte i niepokryte (UT-COV-002).
    var coverageLines: (() -> (covered: Set<Int>, uncovered: Set<Int>, partial: Set<Int>))?
    var onBreakpointClick: ((Int) -> Void)?
    /// Zakładki: linia (od 0) → numer 0–9 (PD-EDIT-011).
    var bookmarkLines: (() -> [Int: Int])?
    /// Status linii (od 0) względem stanu z otwarcia/zapisu: zmieniona — pomarańczowy, nowa — zielony pasek (PD-EDIT-003).
    var lineStatus: [Int: LineChange] = [:]
    /// Numer co n-tą linię (pierwsza i bieżąca zawsze).
    var interval = 1
    /// Numer pokazywany przy linii dokumentu (od 0); nil — bez numeru (karta jednostki: linie przed słowem typu).
    var displayNumber: ((Int) -> Int?)?
    /// Czy ostatnia, pusta linia dokumentu jest widoczna (karta jednostki inna niż ostatnia — nie).
    var showsLastLine: (() -> Bool)?
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
        if p.x < 16, foldState?(hit.line) != nil { onFoldClick?(hit.line); return }
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
                // Punkt przerwania: czerwone kółko pod numerem linii; niezastosowany — pusty okrąg (PD-DBG-007).
                let d = min(height, lineHeight) - 2
                let oval = NSBezierPath(ovalIn: NSRect(x: bounds.width - 8 - d - 10, y: y + 1, width: d, height: d))
                if unappliedLines.contains(line) {
                    NSColor.systemRed.withAlphaComponent(0.85).setStroke()
                    oval.lineWidth = 1.5
                    oval.stroke()
                } else {
                    NSColor.systemRed.withAlphaComponent(0.85).setFill()
                    oval.fill()
                }
            }
            if let n = marks[line] {
                // Zakładka: numer w zaokrąglonym znaczniku przy lewej krawędzi (obok znacznika zwijania).
                let badge = NSAttributedString(string: "\(n)", attributes: [.font: NSFont.boldSystemFont(ofSize: max(8, font.pointSize - 2)), .foregroundColor: NSColor.white])
                let h = min(height, lineHeight) - 2
                let box = NSRect(x: 16, y: y + 1, width: max(10, badge.size().width + 4), height: h)
                NSColor.systemBlue.setFill()
                NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
                badge.draw(at: NSPoint(x: box.midX - badge.size().width / 2, y: box.midY - badge.size().height / 2))
            }
            let number: Int? = displayNumber.map { $0(line) } ?? (line + 1)
            if number == nil {
                // Linia przed nagłówkiem jednostki — bez numeru.
            } else if let number, LineNumbering.shows(line: number - 1, caretLine: line == caretLine ? number - 1 : -1, interval: interval) {
                let s = NSAttributedString(string: "\(number)", attributes: attrs)
                let size = s.size()
                s.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + (min(height, lineHeight) - size.height) / 2))
            } else if let number, number % max(1, interval / 2) == 0 {
                // Kreska między numerami (jak w edytorach z interwałem numeracji).
                NSColor.quaternaryLabelColor.setFill()
                NSRect(x: bounds.width - 14, y: y + min(height, lineHeight) / 2, width: 6, height: 1).fill()
            }
            drawnLines.append((line, y, y + height))
            if let folded = foldState?(line) {
                // Znacznik zwijania: symbol strzałki wielkości tekstu linii (zwinięty — kolor akcentu), dobrze widoczny.
                let side = min(12, max(9, min(height, lineHeight) - 3))
                let color: NSColor = folded ? .controlAccentColor : .secondaryLabelColor
                let config = NSImage.SymbolConfiguration(pointSize: side, weight: .bold).applying(.init(paletteColors: [color]))
                if let image = NSImage(systemSymbolName: folded ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let size = image.size
                    image.draw(in: NSRect(x: 2 + (12 - size.width) / 2, y: y + (min(height, lineHeight) - size.height) / 2, width: size.width, height: size.height),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
        }
        drawnLines.removeAll(keepingCapacity: true)
        let bps = breakpointLines?() ?? []
        let unappliedLines = unappliedBreakpointLines?() ?? []
        let marks = bookmarkLines?() ?? [:]
        let cov = coverageLines?() ?? (covered: Set<Int>(), uncovered: Set<Int>(), partial: Set<Int>())
        if content.documentRange.isEmpty {
            label(0, y: inset - visible.minY, height: lineHeight)
            return
        }
        let start = tlm.textViewportLayoutController.viewportRange?.location ?? tlm.documentRange.location
        var lastFrame = NSRect.zero
        var lastFragment: NSTextLayoutFragment?
        tlm.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.maxY < visible.minY - 50 { return true }
            if frame.minY > visible.maxY + 50 { return false }
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            label(self.highlighter.line(containing: offset), y: frame.minY + inset - visible.minY, height: frame.height)
            lastFrame = frame
            lastFragment = fragment
            return true
        }
        // Pusta ostatnia linia po końcowym znaku nowej linii nie ma własnego fragmentu.
        if tv.endsWithNewline, lastFrame.maxY < visible.maxY, showsLastLine?() ?? true {
            let y = lastFragment.map(trailingEmptyLineY) ?? lastFrame.maxY
            label(highlighter.lineStarts.count - 1, y: y + inset - visible.minY, height: lineHeight)
        }
    }
}

/// Górna krawędź pustej linii po końcowym „\n”. TextKit 2 dokłada ją do ostatniego fragmentu jako pusty fragment linii
/// (wtedy leży wewnątrz ramki fragmentu); bez niego — pod fragmentem.
@MainActor
private func trailingEmptyLineY(_ fragment: NSTextLayoutFragment) -> CGFloat {
    let frame = fragment.layoutFragmentFrame
    if fragment.textLineFragments.count > 1, let extra = fragment.textLineFragments.last, extra.characterRange.length == 0 {
        return frame.minY + extra.typographicBounds.minY
    }
    return frame.maxY
}

fileprivate extension NSTextView {
    /// Długość i ostatni znak z magazynu tekstu — `string` kopiuje cały dokument przy każdym odczycie.
    var textLength: Int { textStorage?.length ?? 0 }
    var endsWithNewline: Bool {
        guard let s = textStorage, s.length > 0 else { return false }
        return s.mutableString.character(at: s.length - 1) == 0x0A
    }
}
