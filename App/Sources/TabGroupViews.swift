import AppKit
import PelikanWorkspace

/// Wysokości karty i kapsułki z czcionek interfejsu (D178): wiersz tytułu i wiersz połączenia/szczegółu.
@MainActor
enum TabMetrics {
    static func line(_ f: NSFont) -> CGFloat { ceil(f.ascender - f.descender + f.leading) }

    static var fonts: InterfaceFonts { InterfaceFonts.shared }
    /// Tytuł karty (o 1 pt mniejszy), nazwa kapsułki (o 2 pt), drugi wiersz karty i kapsułki (o 3 pt).
    static func font(by delta: Double, weight: FontWeightChoice? = nil) -> NSFont {
        AppFonts.font(family: fonts.family, size: AppFonts.reduced(fonts.size, by: delta), weight: weight ?? fonts.weight)
    }

    /// Karta: odstęp 3 pt, wiersz tytułu (najmniej przycisk zamknięcia 14 pt), wiersz połączenia, 5 pt na podkreślenie.
    static var tabHeight: CGFloat { 3 + max(14, line(font(by: 1, weight: .semibold))) + line(font(by: 3)) + 5 }
    /// Pasek kart: karta i odstępy 3 pt nad i pod nią.
    static var tabBarHeight: CGFloat { tabHeight + 6 }
    /// Kapsułka: 2 pt, nazwa, szczegół (wiersze zachodzą o 1 pt), 3 pt.
    static var capsuleHeight: CGFloat { 2 + line(font(by: 2, weight: .semibold)) - 1 + line(font(by: 3)) + 3 }
}

/// Kolory palety połączeń i grup kart (D200) jako kolory dynamiczne: jasny i ciemny wygląd, „Zwiększ kontrast”.
enum TabPaletteColors {
    static func color(_ index: Int, _ shade: TabColorPalette.Shade) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = TabColorPalette.color(index, shade: shade, dark: appearance.isDark,
                                          increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        }
    }

    /// Znacznik typu okna na karcie — wariant koloru typu o kontraście AA na tle palety (`TabColorPalette.markerColor`).
    static func marker(_ kind: DocumentKind) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = TabColorPalette.markerColor(kind, dark: appearance.isDark)
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        }
    }

    /// Kółko w kolorze palety (menu grup, Lista okien); nil — szare (okna bez połączenia).
    static func swatch(_ index: Int?, size: CGFloat = 10) -> NSImage {
        let color = index.map { color($0, .accent) } ?? .tertiaryLabelColor
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: size * 0.3, yRadius: size * 0.3).fill()
            return true
        }
        return image
    }
}

/// Menu wszystkich grup kart (pionowa lista: kolor, nazwa, liczba okien) — „»” kapsułek, mała kapsułka paska kart
/// w pełnym ekranie i menu kapsułki.
@MainActor
enum TabGroupMenu {
    static func make(_ workspace: Workspace, groups: [TabGroup], current: String?, target: AnyObject, action: Selector,
                     allAction: Selector?) -> NSMenu {
        let menu = NSMenu()
        for g in groups {
            let item = NSMenuItem(title: g.name + " — " + g.caption, action: action, keyEquivalent: "")
            item.image = TabPaletteColors.swatch(g.colorIndex, size: 12)
            item.representedObject = g.id
            item.target = target
            item.state = g.id == current && !workspace.tabGroupState.showAll ? .on : .off
            item.setAccessibilityLabel(g.name + ", " + g.caption)
            menu.addItem(item)
        }
        if let allAction {
            menu.addItem(.separator())
            let all = NSMenuItem(title: L10n.tr("Karty wszystkich grup"), action: allAction, keyEquivalent: "")
            all.target = target
            all.state = workspace.tabGroupState.showAll ? .on : .off
            menu.addItem(all)
        }
        return menu
    }
}

/// Kapsułka grupy kart (D200): dwa wiersze — nazwa oraz szczegół i liczba okien; tło w kolorze grupy, bieżąca grupa
/// wyróżniona mocniejszym tłem, obwódką i pogrubioną nazwą. Kliknięcie — pokazuje grupę; menu — grupy ręczne
/// (zmień nazwę, rozgrupuj) i lista wszystkich grup.
final class TabGroupCapsule: NSView {
    let group: TabGroup
    private let isCurrent: Bool
    private let onSelect: () -> Void
    private let name = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    static let maxWidth: CGFloat = 190

    init(group: TabGroup, isCurrent: Bool, onSelect: @escaping () -> Void) {
        self.group = group
        self.isCurrent = isCurrent
        self.onSelect = onSelect
        super.init(frame: .zero)
        let fonts = InterfaceFonts.shared
        name.stringValue = group.name
        name.font = TabMetrics.font(by: 2, weight: isCurrent ? .semibold : fonts.weight)
        caption.stringValue = group.caption
        caption.font = TabMetrics.font(by: 3)
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        // Kolor z przezroczystością zamiast semantycznego: pasek narzędzi nieaktywnego okna szarzy kolor etykiet, a oba
        // wiersze kapsułki mają zostać czytelne na kolorowym tle.
        name.textColor = NSColor.labelColor.withAlphaComponent(increased ? 1 : 0.95)
        caption.textColor = NSColor.labelColor.withAlphaComponent(increased ? 1 : DocumentTabButton.captionAlpha)
        for l in [name, caption] {
            l.lineBreakMode = .byTruncatingTail
            l.translatesAutoresizingMaskIntoConstraints = false
            l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(l)
        }
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            caption.topAnchor.constraint(equalTo: name.bottomAnchor, constant: -1),
        ])
        toolTip = group.name + " — " + group.caption
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(group.name)
        setAccessibilityHelp(L10n.tr("Grupa kart: \(group.caption)"))
        setAccessibilityValue(NSNumber(value: isCurrent ? 1 : 0))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Szerokość potrzebna na dłuższy z wierszy (najwyżej `maxWidth`).
    var preferredWidth: CGFloat {
        min(Self.maxWidth, max(name.intrinsicContentSize.width, caption.intrinsicContentSize.width) + 20)
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        if let i = group.colorIndex {
            TabPaletteColors.color(i, isCurrent ? .activeBackground : .inactiveBackground).setFill()
        } else {
            (isCurrent ? NSColor.labelColor.withAlphaComponent(0.12) : NSColor.labelColor.withAlphaComponent(0.05)).setFill()
        }
        shape.fill()
        if isCurrent {
            (group.colorIndex.map { TabPaletteColors.color($0, .accent) } ?? .secondaryLabelColor).setStroke()
            shape.lineWidth = 2
            shape.stroke()
        } else {
            NSColor.separatorColor.setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) { onSelect() }
}

/// Kapsułki grup kart na pasku tytułu (element paska narzędzi, D200). Mieszczą się — wszystkie; nie mieszczą się —
/// ostatnia kapsułka „»” z pionową listą wszystkich grup (bieżąca grupa zawsze widoczna). Jedna grupa — pusto.
final class TabGroupBar: NSView {
    private let workspace: Workspace
    private var capsules: [TabGroupCapsule] = []
    private let overflow = NSButton(title: "»", target: nil, action: nil)
    private var groups: [TabGroup] = []
    private var currentID: String?
    private var widthConstraint: NSLayoutConstraint!
    private var maxConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    /// Wysokość kapsułki z czcionek interfejsu (odczytana przy przebudowie).
    private var capsuleHeight: CGFloat = 32
    /// Zmiana liczby grup (pokazanie albo ukrycie elementu paska).
    var onGroupCountChange: ((Int) -> Void)?
    /// Po przebudowie kapsułek (menu elementu w przepełnieniu paska).
    var onReload: (() -> Void)?

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 34))
        translatesAutoresizingMaskIntoConstraints = false
        overflow.bezelStyle = .accessoryBarAction
        overflow.isBordered = true
        overflow.target = self
        overflow.action = #selector(showOverflow(_:))
        overflow.toolTip = L10n.tr("Wszystkie grupy kart")
        overflow.setAccessibilityLabel(L10n.tr("Wszystkie grupy kart"))
        addSubview(overflow)
        widthConstraint = widthAnchor.constraint(equalToConstant: 10)
        widthConstraint.priority = .defaultLow
        maxConstraint = widthAnchor.constraint(lessThanOrEqualToConstant: 10)
        heightConstraint = heightAnchor.constraint(equalToConstant: TabMetrics.capsuleHeight + 2)
        NSLayoutConstraint.activate([
            widthConstraint, maxConstraint, heightConstraint,
            widthAnchor.constraint(greaterThanOrEqualToConstant: 1),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(L10n.tr("Grupy kart"))
        trackChanges { [weak self] in self?.reload() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func reload() {
        _ = InterfaceFonts.shared.size
        capsuleHeight = TabMetrics.capsuleHeight
        heightConstraint.constant = capsuleHeight + 2
        let groups = workspace.tabGroups
        let current = workspace.tabGroupState.showAll ? nil : workspace.activeDocumentID.flatMap { id in groups.first { $0.documents.contains(id) }?.id }
        let changedCount = groups.count != self.groups.count
        self.groups = groups
        currentID = current
        capsules.forEach { $0.removeFromSuperview() }
        capsules = groups.count > 1 ? groups.map { g in
            let c = TabGroupCapsule(group: g, isCurrent: g.id == current) { [weak self] in self?.select(g.id) }
            c.menu = capsuleMenu(g)
            return c
        } : []
        capsules.forEach { addSubview($0) }
        let total = capsules.reduce(0) { $0 + $1.preferredWidth + 6 } + 4
        widthConstraint.constant = groups.count > 1 ? total : 1
        maxConstraint.constant = groups.count > 1 ? total : 1
        if changedCount { onGroupCountChange?(groups.count) }
        onReload?()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = capsuleHeight
        let y = (bounds.height - h) / 2
        let overflowWidth: CGFloat = 28
        let fit = TabCapsuleLayout.fit(widths: capsules.map { Double($0.preferredWidth) }, available: Double(bounds.width),
                                       spacing: 6, overflowWidth: Double(overflowWidth),
                                       current: capsules.firstIndex { $0.group.id == currentID })
        var x: CGFloat = 2
        for (i, c) in capsules.enumerated() {
            guard fit.visible.contains(i) else { c.isHidden = true; continue }
            c.isHidden = false
            c.frame = NSRect(x: x, y: y, width: CGFloat(fit.widths[i]), height: h)
            x += CGFloat(fit.widths[i]) + 6
        }
        overflow.isHidden = !fit.overflow
        overflow.frame = NSRect(x: x, y: y + (h - 24) / 2, width: overflowWidth, height: 24)
    }

    /// Lista wszystkich grup (menu „»” i element paska w menu przepełnienia).
    func groupsMenu() -> NSMenu {
        TabGroupMenu.make(workspace, groups: groups, current: currentID, target: self, action: #selector(chooseGroup(_:)),
                          allAction: #selector(toggleAll))
    }

    private func select(_ id: String) {
        workspace.perform("window.showGroup", CommandArguments(["group": .string(id)]))
    }

    @objc private func showOverflow(_ sender: NSButton) {
        let menu = groupsMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func chooseGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        select(id)
    }

    @objc func toggleAll() { workspace.perform("window.allTabs") }

    /// Menu kapsułki: grupa ręczna — Zmień nazwę…, Rozgrupuj; zawsze — karty wszystkich grup.
    private func capsuleMenu(_ g: TabGroup) -> NSMenu {
        let menu = NSMenu()
        if g.kind == .manual {
            for (title, command) in [(L10n.tr("Zmień nazwę…"), "window.renameGroup"), (L10n.tr("Rozgrupuj"), "window.ungroup")] {
                let item = menu.addItem(withTitle: title, action: #selector(groupCommand(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [command, g.id]
            }
            menu.addItem(.separator())
        }
        let all = menu.addItem(withTitle: L10n.tr("Karty wszystkich grup"), action: #selector(toggleAll), keyEquivalent: "")
        all.target = self
        all.state = workspace.tabGroupState.showAll ? .on : .off
        return menu
    }

    @objc private func groupCommand(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        workspace.perform(CommandID(rawValue: pair[0]), CommandArguments(["group": .string(pair[1])]))
    }
}
