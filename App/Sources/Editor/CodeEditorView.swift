import AppKit
import PelikanWorkspace

/// Edytor kodu SQL/PL/SQL (ADR 0003): NSTextView na TextKit 2, podświetlanie przyrostowe, numery linii,
/// pasek pozycji `linia:kolumna [długość]` (NF15), wiązanie z `Document` (tekst, zaznaczenie, błąd).
final class CodeEditorView: NSView, NSTextViewDelegate, NSTextStorageDelegate {
    let textView: CodeTextView
    let scrollView = NSScrollView()
    private let ruler: LineNumberRulerView
    private let highlighter = SyntaxHighlighter()
    private let document: Document
    private var font: NSFont
    private var updatingFromModel = false
    private var tokens: [ObservationToken] = []
    var onCaretChange: ((String) -> Void)?

    init(document: Document, fontSize: CGFloat = 13) {
        self.document = document
        font = NSFont(name: "SF Mono", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView = CodeTextView(usingTextLayoutManager: true)
        ruler = LineNumberRulerView(textView: textView, highlighter: highlighter)
        super.init(frame: .zero)
        configure()
        load(document.text)
        tokens.append(trackChanges { [weak self] in self?.syncFromModel() })
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
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = [.font: font, .foregroundColor: SyntaxTheme.plain]
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.setAccessibilityLabel(document.fullTitle)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func load(_ text: String) {
        updatingFromModel = true
        textView.string = text
        if let storage = textView.textStorage { highlighter.highlightAll(storage, font: font) }
        updatingFromModel = false
        ruler.needsDisplay = true
    }

    /// Zmiany modelu z zewnątrz (historia okna, agent `replace_range`, błąd do zaznaczenia).
    private func syncFromModel() {
        let text = document.text
        let error = document.errorRange
        if text != textView.string {
            load(text)
            textView.setSelectedRange(NSRange(location: min(document.selectedRange.lowerBound, (text as NSString).length), length: 0))
        }
        if let error {
            let len = (textView.string as NSString).length
            let r = NSRange(location: min(error.lowerBound, len), length: 0)
            textView.setSelectedRange(r)
            textView.scrollRangeToVisible(r)
            // Zaznacz słowo z błędem (NF15: podkreślenie całego słowa).
            let word = textView.selectionRange(forProposedRange: r, granularity: .selectByWord)
            if word.length > 0 { textView.showFindIndicator(for: word) }
        }
    }

    // MARK: NSTextStorageDelegate — podświetlanie przyrostowe

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !updatingFromModel else { return }
        // Atrybuty zmieniamy po zakończeniu przetwarzania edycji (nie wewnątrz delegata).
        DispatchQueue.main.async { [weak self] in
            guard let self, let storage = self.textView.textStorage else { return }
            let len = storage.length
            let r = NSRange(location: min(editedRange.location, len), length: min(editedRange.length, max(0, len - min(editedRange.location, len))))
            self.highlighter.highlight(storage, editedRange: r, delta: delta, font: self.font)
            self.ruler.needsDisplay = true
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !updatingFromModel else { return }
        updatingFromModel = true
        document.text = textView.string
        document.errorRange = nil
        updatingFromModel = false
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let r = textView.selectedRange()
        document.selectedRange = r.location..<(r.location + r.length)
        let line = highlighter.line(containing: r.location)
        let col = r.location - (line < highlighter.lineStarts.count ? highlighter.lineStarts[line] : 0)
        onCaretChange?(r.length > 0 ? "\(line + 1):\(col + 1) [\(r.length)]" : "\(line + 1):\(col + 1)")
        ruler.needsDisplay = true
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

/// Margines z numerami linii (UG 23.12 „Display line numbers”); bieżąca linia wyróżniona.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let highlighter: SyntaxHighlighter

    init(textView: NSTextView, highlighter: SyntaxHighlighter) {
        self.textView = textView
        self.highlighter = highlighter
        super.init(scrollView: nil, orientation: .verticalRuler)
        ruleThickness = 44
        clientView = textView
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let tlm = tv.textLayoutManager, let content = tlm.textContentManager else { return }
        NSColor.windowBackgroundColor.setFill()
        rect.fill()
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, (tv.font?.pointSize ?? 13) - 2), weight: .regular)
        let caretLine = highlighter.line(containing: tv.selectedRange().location)
        let visible = tv.visibleRect
        let origin = convert(NSPoint.zero, from: tv)
        let inset = tv.textContainerInset.height
        // Od początku widocznego zakresu (viewport), bez wymuszania układu całego dokumentu — O(widoczne linie).
        let start = tlm.textViewportLayoutController.viewportRange?.location ?? tlm.documentRange.location
        tlm.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.maxY < visible.minY - 50 { return true }
            if frame.minY > visible.maxY + 50 { return false }
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let line = self.highlighter.line(containing: offset)
            let isCaret = line == caretLine
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: isCaret ? NSColor.labelColor : NSColor.tertiaryLabelColor]
            let s = NSAttributedString(string: "\(line + 1)", attributes: attrs)
            let size = s.size()
            let y = frame.minY + inset + origin.y + (frame.height > 0 ? min(frame.height, (tv.font?.boundingRectForFont.height ?? size.height)) - size.height : 0) / 2
            s.draw(at: NSPoint(x: self.ruleThickness - size.width - 6, y: y))
            return true
        }
        let border = NSRect(x: ruleThickness - 1, y: rect.minY, width: 1, height: rect.height)
        NSColor.separatorColor.setFill()
        border.fill()
    }
}
