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
    var onCaretChange: ((String) -> Void)?

    init(document: Document, fontSize: CGFloat = 13) {
        self.document = document
        font = NSFont(name: "SF Mono", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView = CodeTextView(usingTextLayoutManager: true)
        ruler = LineNumberRulerView(textView: textView, highlighter: highlighter)
        super.init(frame: .zero)
        configure()
        if let ws = (NSApp.delegate as? AppDelegate)?.workspace {
            textView.keywordCase = ws.settings.keywordCase
            textView.highlightCurrentLine = ws.settings.highlightCurrentLine
            textView.indentUnit = ws.settings.useTabCharacter ? "\t" : String(repeating: " ", count: ws.settings.tabSize)
        }
        load(document.text)
        tokens.append(trackChanges { [weak self] in self?.syncFromModel() })
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            _ = self.document.foldedStarts
            self.applyFolds()
        })
        // Okno w trakcie wykonania jest tylko do odczytu (jak we wzorcu); inne okna działają równolegle.
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            self.textView.isEditable = !self.document.isExecuting
        })
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
        addSubview(ruler)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            ruler.topAnchor.constraint(equalTo: topAnchor),
            ruler.leadingAnchor.constraint(equalTo: leadingAnchor),
            ruler.bottomAnchor.constraint(equalTo: bottomAnchor),
            ruler.widthAnchor.constraint(equalToConstant: 44),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: ruler.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
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
            let m = ws.metadata(for: ws.effectiveConnection(of: self.document))
            return await CodeAssistant.complete(text: self.textView.string, offset: self.textView.selectedRange().location, metadata: m)
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

    // MARK: Zwijanie kodu (UG 25.17)

    /// Obszary zwijania przeliczane z opóźnieniem po zmianie tekstu (znaczniki ± w marginesie).
    private func scheduleRegions(delay: Double = 0.3) {
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
        }
        let len = (textView.string as NSString).length
        let current = textView.selectedRange()
        let wanted = NSRange(location: min(selection.lowerBound, len), length: max(0, min(selection.upperBound, len) - min(selection.lowerBound, len)))
        if !updatingFromModel, current != wanted {
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
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !updatingFromModel else { return }
        let r = textView.selectedRange()
        document.selectedRange = r.location..<(r.location + r.length)
        // Po edycji początki linii przelicza podświetlanie w następnym obiegu pętli — pozycję liczymy po nim.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let r = self.textView.selectedRange()
            let line = self.highlighter.line(containing: r.location)
            let col = r.location - (line < self.highlighter.lineStarts.count ? self.highlighter.lineStarts[line] : 0)
            self.onCaretChange?(r.length > 0 ? "\(line + 1):\(col + 1) [\(r.length)]" : "\(line + 1):\(col + 1)")
            self.ruler.needsDisplay = true
            self.updatePairs()
        }
    }

    func setFontSize(_ size: CGFloat) {
        font = NSFont(name: font.fontName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        textView.font = font
        if let storage = textView.textStorage { highlighter.highlightAll(storage, font: font) }
    }
}

/// NSTextView z dodatkami edytora kodu: wcięcie zaznaczenia Tab/Shift+Tab (UG 25.1), auto-wcięcie po Enter.
final class CodeTextView: NSTextView {
    var indentUnit = "  "
    var keywordCase: KeywordCase = .unchanged
    var highlightCurrentLine = true
    /// Początki zwiniętych struktur — za ich linią rysowany jest znacznik „⋯”.
    var foldedLines: [Int] = [] { didSet { needsDisplay = true } }
    static let currentLineColor = NSColor(name: nil) { $0.isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(srgbRed: 0.95, green: 0.97, blue: 1, alpha: 1) }

    /// Podświetlenie linii z kursorem (UG 23.12 „Highlight current line”).
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
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
        guard !foldedLines.isEmpty, let tlm = textLayoutManager, let content = tlm.textContentManager else { return }
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
        if keywordCase != .unchanged, let ch = text.unicodeScalars.first, !CharacterSet.alphanumerics.contains(ch), ch != "_", ch != "$", ch != "#" {
            applyKeywordCase()
        }
        super.insertText(string, replacementRange: replacementRange)
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
        super.keyDown(with: event)
    }

    /// Cmd+klik na identyfikatorze — przejście do deklaracji (UG 25.19 nawigacja hiperłączami).
    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
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
        guard let word = TextEditing.identifier(at: i, in: string), !Keywords.isKeyword(word) || word.contains(".") else { return menu }
        if selectedRange().length == 0 { setSelectedRange(NSRange(location: i, length: 0)) }
        var items: [NSMenuItem] = []
        let header = NSMenuItem(title: L10n.tr("Obiekt „\(word)”"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        items.append(header)
        let actions: [(String, String)] = [("ob.queryData", L10n.tr("Pokaż dane")), ("ob.editData", L10n.tr("Edytuj dane")),
                                           ("ob.describe", L10n.tr("Opis")), ("ob.edit", L10n.tr("Edytuj")), ("ob.ddl", L10n.tr("DDL")),
                                           ("ob.properties", L10n.tr("Właściwości")), ("ob.recompile", L10n.tr("Rekompiluj")),
                                           ("ob.compare", L10n.tr("Porównaj z aktywnym oknem"))]
        for (id, title) in actions {
            let item = ClosureMenuItem(title: title) { ws.perform(CommandID(rawValue: id), CommandArguments(["object": .string(word)])) }
            items.append(item)
        }
        items.append(ClosureMenuItem(title: L10n.tr("Przejdź do deklaracji")) { ws.perform("edit.gotoDeclaration") })
        items.append(.separator())
        for (k, item) in items.enumerated() { menu.insertItem(item, at: k) }
        return menu
    }

    /// Upuszczone pliki skryptów otwierają się w oknach (zamiast wstawiania ścieżki do tekstu).
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            NSApp.delegate.flatMap { $0 as? AppDelegate }?.application(NSApp, open: urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func insertNewline(_ sender: Any?) {
        // Automatyczne wcięcie jak poprzednia linia (UG 23.12 „Automatic”).
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = ns.substring(with: lineRange)
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
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
        guard let hit = drawnLines.first(where: { p.y >= $0.minY && p.y < $0.maxY }), foldState?(hit.line) != nil else {
            return super.mouseDown(with: event)
        }
        onFoldClick?(hit.line)
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
            let s = NSAttributedString(string: "\(line + 1)", attributes: attrs)
            let size = s.size()
            s.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + (min(height, lineHeight) - size.height) / 2))
            drawnLines.append((line, y, y + height))
            if let folded = foldState?(line) {
                let marker = NSAttributedString(string: folded ? "▸" : "▾", attributes: [.font: font, .foregroundColor: folded ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor])
                marker.draw(at: NSPoint(x: 3, y: y + (min(height, lineHeight) - marker.size().height) / 2))
            }
        }
        drawnLines.removeAll(keepingCapacity: true)
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
