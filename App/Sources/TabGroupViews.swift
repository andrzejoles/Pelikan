import AppKit
import PelikanWorkspace

/// Kolory palety połączeń i grup kart (D200) jako kolory dynamiczne: jasny i ciemny wygląd, „Zwiększ kontrast”.
enum TabPaletteColors {
    static func color(_ index: Int, _ shade: TabColorPalette.Shade) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = TabColorPalette.color(index, shade: shade, dark: appearance.isDark,
                                          increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
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
    static let height: CGFloat = 32

    init(group: TabGroup, isCurrent: Bool, onSelect: @escaping () -> Void) {
        self.group = group
        self.isCurrent = isCurrent
        self.onSelect = onSelect
        super.init(frame: .zero)
        let fonts = InterfaceFonts.shared
        name.stringValue = group.name
        name.font = AppFonts.font(family: fonts.family, size: AppFonts.reduced(fonts.size, by: 2), weight: isCurrent ? .semibold : fonts.weight)
        caption.stringValue = group.caption
        caption.font = AppFonts.font(family: fonts.family, size: AppFonts.reduced(fonts.size, by: 3), weight: fonts.weight)
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
    /// Zmiana liczby grup (pokazanie albo ukrycie elementu paska).
    var onGroupCountChange: ((Int) -> Void)?

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: TabGroupCapsule.height))
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
        NSLayoutConstraint.activate([
            widthConstraint, maxConstraint,
            widthAnchor.constraint(greaterThanOrEqualToConstant: 1),
            heightAnchor.constraint(equalToConstant: TabGroupCapsule.height + 2),
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
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = TabGroupCapsule.height
        let y = (bounds.height - h) / 2
        let overflowWidth: CGFloat = 28
        var widths = capsules.map(\.preferredWidth)
        let all = widths.reduce(0) { $0 + $1 + 6 }
        var visible = Array(capsules.indices)
        if all > bounds.width + 0.5 {
            // Tyle kapsułek, ile się mieści obok „»”; bieżąca zawsze widoczna (zamiast ostatniej mieszczącej się).
            var used: CGFloat = overflowWidth
            visible = []
            for i in capsules.indices where used + widths[i] + 6 <= bounds.width {
                visible.append(i)
                used += widths[i] + 6
            }
            if let cur = capsules.firstIndex(where: { $0.group.id == currentID }), !visible.contains(cur) {
                if !visible.isEmpty { visible.removeLast() }
                visible.append(cur)
                widths[cur] = min(widths[cur], max(60, bounds.width - overflowWidth - 6))
            }
        }
        var x: CGFloat = 2
        for (i, c) in capsules.enumerated() {
            guard visible.contains(i) else { c.isHidden = true; continue }
            c.isHidden = false
            c.frame = NSRect(x: x, y: y, width: widths[i], height: h)
            x += widths[i] + 6
        }
        overflow.isHidden = visible.count == capsules.count
        overflow.frame = NSRect(x: x, y: y + (h - 24) / 2, width: overflowWidth, height: 24)
    }

    private func select(_ id: String) {
        workspace.perform("window.showGroup", CommandArguments(["group": .string(id)]))
    }

    @objc private func showOverflow(_ sender: NSButton) {
        let menu = TabGroupMenu.make(workspace, groups: groups, current: currentID, target: self, action: #selector(chooseGroup(_:)),
                                     allAction: #selector(toggleAll))
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
