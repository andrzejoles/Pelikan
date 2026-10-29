import AppKit
import PelikanWorkspace

/// Pasek kart z przewijaniem przy przepełnieniu (D201): przyciski ‹ › po bokach tylko wtedy, gdy karty się nie mieszczą
/// (wyłączone na końcach), przewijanie o kilka kart z animacją, kółko myszy (pionowy obrót przewija poziomo) i gest
/// gładzika; aktywna karta zawsze przewijana do widoku. Na początku opcjonalnie mała kapsułka bieżącej grupy (pełny
/// ekran albo pasek narzędzi bez kapsułek grup, D200).
final class TabStripView: NSView {
    let stack = NSStackView()
    private let scroll = TabScrollView()
    private let left = NSButton(image: NSImage(), target: nil, action: nil)
    private let right = NSButton(image: NSImage(), target: nil, action: nil)
    /// Mała kapsułka bieżącej grupy (menu wszystkich grup); ukryta, gdy kapsułki są na pasku narzędzi.
    let groupPill = NSButton(title: "", target: nil, action: nil)
    private var boundsObserver: (any NSObjectProtocol)?
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private var pillLeading: NSLayoutConstraint!
    private var pillHidden: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.onScroll = { [weak self] in self?.updateButtons() }
        for (b, symbol, label, sel) in [(left, "chevron.left", L10n.tr("Przewiń karty w lewo"), #selector(scrollLeft)),
                                        (right, "chevron.right", L10n.tr("Przewiń karty w prawo"), #selector(scrollRight))] {
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
        groupPill.bezelStyle = .accessoryBarAction
        groupPill.isHidden = true
        groupPill.translatesAutoresizingMaskIntoConstraints = false
        groupPill.setContentHuggingPriority(.required, for: .horizontal)
        groupPill.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(groupPill)
        addSubview(scroll)
        leading = scroll.leadingAnchor.constraint(equalTo: groupPill.trailingAnchor)
        trailing = scroll.trailingAnchor.constraint(equalTo: trailingAnchor)
        pillLeading = groupPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0)
        pillHidden = groupPill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            pillLeading, pillHidden,
            groupPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.leadingAnchor.constraint(equalTo: groupPill.trailingAnchor, constant: 2),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.widthAnchor.constraint(equalToConstant: 20),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.widthAnchor.constraint(equalToConstant: 20),
            leading, trailing,
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
        ])
        scroll.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateButtons() }
        }
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

    private var offset: Double { Double(scroll.contentView.bounds.origin.x) }
    private var content: Double { Double(stack.fittingSize.width) }
    private var visible: Double { Double(scroll.contentView.bounds.width) }

    override func layout() {
        super.layout()
        updateButtons()
    }

    /// Przyciski tylko przy przepełnieniu; obszar kart zwęża się o ich szerokość.
    private func updateButtons() {
        let overflow = TabStripScrolling.overflows(content: content, visible: visible + (left.isHidden ? 0 : 48))
        left.isHidden = !overflow
        right.isHidden = !overflow
        leading.constant = overflow ? 24 : 0
        trailing.constant = overflow ? -24 : 0
        left.isEnabled = TabStripScrolling.canScroll(offset: offset, content: content, visible: visible, forward: false)
        right.isEnabled = TabStripScrolling.canScroll(offset: offset, content: content, visible: visible, forward: true)
    }

    @objc private func scrollLeft() { animate(to: TabStripScrolling.target(offset: offset, content: content, visible: visible, forward: false)) }
    @objc private func scrollRight() { animate(to: TabStripScrolling.target(offset: offset, content: content, visible: visible, forward: true)) }

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

    /// Aktywna karta w widoku (po przełączeniu okna albo grupy) — po układzie paska.
    func reveal(_ view: NSView) {
        layoutSubtreeIfNeeded()
        let f = view.convert(view.bounds, to: stack)
        let x = TabStripScrolling.reveal(offset: offset, content: content, visible: visible, minX: Double(f.minX), maxX: Double(f.maxX))
        guard abs(x - offset) > 0.5 else { return }
        scroll.contentView.setBoundsOrigin(NSPoint(x: x, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        updateButtons()
    }
}

/// Przewijanie paska kart kółkiem myszy: obrót pionowy przewija poziomo (pasek nie ma przewijania pionowego), gest
/// poziomy gładzika — jak zwykle.
final class TabScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let doc = documentView else {
            super.scrollWheel(with: event)
            onScroll?()
            return
        }
        let delta = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 12)
        let x = TabStripScrolling.wheel(offset: Double(contentView.bounds.origin.x), delta: delta,
                                        content: Double(doc.fittingSize.width), visible: Double(contentView.bounds.width))
        contentView.setBoundsOrigin(NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
        onScroll?()
    }
}
