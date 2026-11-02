import AppKit
import PelikanWorkspace

/// Pasek kart z przewijaniem przy przepełnieniu (D201): przyciski ‹ › po bokach tylko wtedy, gdy karty się nie mieszczą
/// (wyłączone na końcach), przewijanie o kilka kart z animacją, kółko myszy (pionowy obrót przewija poziomo) i gest
/// gładzika; aktywna karta zawsze przewijana do widoku. Na początku opcjonalnie mała kapsułka bieżącej grupy (pełny
/// ekran albo pasek narzędzi bez kapsułek grup, D200).
final class TabStripView: NSView {
    let stack = NSStackView()
    private let strip: OverflowScrollStrip
    /// Mała kapsułka bieżącej grupy (menu wszystkich grup); ukryta, gdy kapsułki są na pasku narzędzi.
    let groupPill = NSButton(title: "", target: nil, action: nil)
    private var pillLeading: NSLayoutConstraint!
    private var pillHidden: NSLayoutConstraint!

    override init(frame: NSRect) {
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        strip = OverflowScrollStrip(document: stack, leftLabel: L10n.tr("Przewiń karty w lewo"),
                                    rightLabel: L10n.tr("Przewiń karty w prawo"))
        super.init(frame: frame)
        strip.translatesAutoresizingMaskIntoConstraints = false
        groupPill.bezelStyle = .accessoryBarAction
        groupPill.isHidden = true
        groupPill.translatesAutoresizingMaskIntoConstraints = false
        groupPill.setContentHuggingPriority(.required, for: .horizontal)
        groupPill.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(groupPill)
        addSubview(strip)
        pillLeading = groupPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0)
        pillHidden = groupPill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            pillLeading, pillHidden,
            groupPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            strip.leadingAnchor.constraint(equalTo: groupPill.trailingAnchor),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.heightAnchor.constraint(equalTo: strip.scroll.contentView.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Bez kapsułki — zerowa szerokość (pasek kart od lewej krawędzi jak dotąd).
    func setGroupPillVisible(_ visible: Bool) {
        groupPill.isHidden = !visible
        pillHidden.isActive = !visible
        pillLeading.constant = visible ? 6 : 0
        needsLayout = true
    }

    /// Aktywna karta w widoku (po przełączeniu okna albo grupy) — po układzie paska.
    func reveal(_ view: NSView) { strip.reveal(view) }
}

/// Poziomy pas przewijany przy przepełnieniu — pasek kart (D201), pasek kart wstążki i zawartość karty wstążki (D206):
/// przyciski ‹ › po bokach tylko wtedy, gdy treść się nie mieści (obszar treści zwęża się o nie), wyłączone na końcach;
/// krok z animacją 0,2 s (bez animacji przy „Ogranicz ruch”); bez przepełnienia przewijanie idzie dalej. Obliczenia
/// w `TabStripScrolling` (pakiet, testy).
final class OverflowScrollStrip: NSView {
    let scroll: TabScrollView
    private let left = NSButton(image: NSImage(), target: nil, action: nil)
    private let right = NSButton(image: NSImage(), target: nil, action: nil)
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private var boundsObserver: (any NSObjectProtocol)?
    /// Granice elementów (grup wstążki) w treści — krok przycisku do granicy grupy (`pageTarget`); bez nich zwykły krok.
    var pageItems: (() -> [ClosedRange<Double>])?
    private(set) var overflowShown = false
    private static let inset: CGFloat = 24

    /// `mapsPreciseVertical` — gest pionowy gładzika też przewija poziomo (pasek kart); bez tego poziomo przewija tylko
    /// obrót kółka myszy, a gest gładzika działa jak w zwykłym widoku przewijanym (zawartość wstążki).
    init(document: NSView, leftLabel: String, rightLabel: String, mapsPreciseVertical: Bool = true) {
        scroll = TabScrollView()
        scroll.mapsPreciseVertical = mapsPreciseVertical
        super.init(frame: .zero)
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.onScroll = { [weak self] in self?.updateButtons() }
        for (b, symbol, label, sel) in [(left, "chevron.left", leftLabel, #selector(scrollLeft)),
                                        (right, "chevron.right", rightLabel, #selector(scrollRight))] {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            b.isBordered = false
            b.target = self
            b.action = sel
            b.toolTip = label
            b.setAccessibilityLabel(label)
            b.isHidden = true
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
        }
        addSubview(scroll)
        leading = scroll.leadingAnchor.constraint(equalTo: leadingAnchor)
        trailing = scroll.trailingAnchor.constraint(equalTo: trailingAnchor)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.widthAnchor.constraint(equalToConstant: 20),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.widthAnchor.constraint(equalToConstant: 20),
            leading, trailing,
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
        scroll.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateButtons() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var offset: Double { Double(scroll.contentView.bounds.origin.x) }
    private var content: Double { Double(scroll.documentView?.frame.width ?? 0) }
    private var visible: Double { Double(scroll.contentView.bounds.width) }

    override func layout() {
        super.layout()
        updateButtons()
    }

    /// Przyciski tylko przy przepełnieniu (szerokość treści wobec całego pasa, bez miejsca na przyciski); stan
    /// przycisków (koniec pasa) — od razu. Zmiana ograniczeń poza `layout()` (następny obieg pętli) — zmiana w trakcie
    /// układu wywołałaby kolejny układ w tym samym przebiegu.
    private func updateButtons() {
        let full = visible + (overflowShown ? 2 * Self.inset : 0)
        let overflow = TabStripScrolling.overflows(content: content, visible: full)
        if overflow != overflowShown {
            DispatchQueue.main.async { [weak self] in self?.setOverflow(overflow) }
        }
        left.isEnabled = TabStripScrolling.canScroll(offset: offset, content: content, visible: visible, forward: false)
        right.isEnabled = TabStripScrolling.canScroll(offset: offset, content: content, visible: visible, forward: true)
    }

    private func setOverflow(_ overflow: Bool) {
        guard overflow != overflowShown else { return }
        overflowShown = overflow
        left.isHidden = !overflow
        right.isHidden = !overflow
        leading.constant = overflow ? Self.inset : 0
        trailing.constant = overflow ? -Self.inset : 0
        scroll.overflows = overflow
        if !overflow { scrollToStart() }
    }

    @objc private func scrollLeft() { animate(to: pageTarget(forward: false)) }
    @objc private func scrollRight() { animate(to: pageTarget(forward: true)) }

    private func pageTarget(forward: Bool) -> Double {
        guard let items = pageItems?() else {
            return TabStripScrolling.target(offset: offset, content: content, visible: visible, forward: forward)
        }
        return TabStripScrolling.pageTarget(offset: offset, content: content, visible: visible, forward: forward, items: items)
    }

    private func animate(to x: Double) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            scroll.contentView.animator().setBoundsOrigin(NSPoint(x: x, y: 0))
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scroll.reflectScrolledClipView(self.scroll.contentView)
                self.updateButtons()
            }
        }
    }

    /// Początek treści (zmiana karty wstążki, koniec przepełnienia) — bez animacji.
    func scrollToStart() {
        scroll.contentView.setBoundsOrigin(.zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        updateButtons()
    }

    /// Element w widoku (aktywna karta) — po układzie pasa.
    func reveal(_ view: NSView) {
        guard let document = scroll.documentView else { return }
        layoutSubtreeIfNeeded()
        let f = view.convert(view.bounds, to: document)
        let x = TabStripScrolling.reveal(offset: offset, content: content, visible: visible, minX: Double(f.minX), maxX: Double(f.maxX))
        guard abs(x - offset) > 0.5 else { return }
        scroll.contentView.setBoundsOrigin(NSPoint(x: x, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        updateButtons()
    }
}

/// Przewijanie pasa kółkiem myszy i gładzikiem przy przepełnieniu: obrót kółka (a z `mapsPreciseVertical` także
/// pionowy gest gładzika) przewija poziomo, ruch poziomy — jak zwykle. Bez przepełnienia zdarzenie idzie dalej (np. do
/// przewijanego widoku pod spodem).
final class TabScrollView: NSScrollView {
    var onScroll: (() -> Void)?
    var overflows = false
    var mapsPreciseVertical = true

    override func scrollWheel(with event: NSEvent) {
        guard overflows, let doc = documentView else {
            nextResponder?.scrollWheel(with: event)
            return
        }
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              mapsPreciseVertical || !event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            onScroll?()
            return
        }
        let delta = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 12)
        let x = TabStripScrolling.wheel(offset: Double(contentView.bounds.origin.x), delta: delta,
                                        content: Double(doc.frame.width), visible: Double(contentView.bounds.width))
        contentView.setBoundsOrigin(NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
        onScroll?()
    }
}
