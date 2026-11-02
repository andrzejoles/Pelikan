import AppKit
import PelikanWorkspace

/// Pasek ikon bezpośrednio nad wynikiem zapytania (D207): wszystkie czynności dotyczące wyniku z rejestru komend,
/// w grupach karty „Wynik” wstążki (`ResultBarModel`) rozdzielonych kreską. Same ikony — opis, podsumowanie i skrót
/// w podpowiedzi; listy rozwijane (▾) jak na wstążce. Gdy pasek się nie mieści, końcowe elementy trafiają do menu „»”
/// (z podziałem na grupy). Dostępność przycisków — jak w menu (`Workspace.isEnabled`); stan przełączników — z rejestru
/// komend (`Workspace.toggleState`, np. panel wartości), z modelu siatki paska (`localState`, edycja danych) albo od
/// widoku siatki (`setState`, widok rekordu). Po prawej — licznik wierszy.
final class ResultCommandBar: NSView {
    private enum Element {
        case command(String, NSButton)
        case menu(title: String, commands: [String], NSButton)
        case separator(NSBox)

        var view: NSView {
            switch self {
            case .command(_, let b), .menu(_, _, let b): b
            case .separator(let box): box
            }
        }
    }

    private let workspace: Workspace
    private let trailing: NSView
    private var elements: [Element] = []
    private let overflowButton = NSButton(title: "", target: nil, action: nil)
    /// Śledzenie dostępności komend — tylko gdy pasek jest w oknie (siatki kart wyników w pamięci podręcznej okna
    /// SQL poza oknem nie przeliczają komend przy każdej zmianie).
    private var tracking: ObservationToken?
    private var visibleCount = 0
    /// Stan przełącznika z modelu siatki tego paska (pierwszeństwo przed `toggleState`, który dotyczy aktywnej siatki);
    /// odczyt śledzony jak dostępność.
    var localState: [String: () -> Bool] = [:]
    /// Przyciski-przełączniki (typ przycisku ustawiony przy pierwszym stanie).
    private var toggles: Set<String> = []
    /// Czynności z zachowaniem widoku siatki (np. wstawienie rekordu z edycją pierwszej komórki) zamiast samej komendy.
    var actions: [String: () -> Void] = [:]
    /// Menu zamiast komendy bez argumentów (eksport i kopiowanie w wybranym formacie).
    var menus: [String: () -> NSMenu] = [:]
    /// Symbol przełącznika w stanie włączonym (kłódka otwarta przy edycji).
    var onSymbols: [String: String] = [:]

    static let height: CGFloat = 26
    private static let buttonWidth: CGFloat = 26
    private static let menuWidth: CGFloat = 36
    private static let separatorWidth: CGFloat = 9

    init(workspace: Workspace, trailing: NSView) {
        self.workspace = workspace
        self.trailing = trailing
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(L10n.tr("Czynności wyniku"))
        build()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            tracking?.cancel()
            tracking = nil
        } else if tracking == nil {
            tracking = trackChanges { [weak self] in self?.refreshEnabled() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        for (i, group) in ResultBarModel.groups.enumerated() {
            if i > 0 {
                let box = NSBox()
                box.boxType = .separator
                elements.append(.separator(box))
            }
            for item in group.items {
                switch item {
                case .large(let id, _), .small(let id, _):
                    guard let d = workspace.registry.command(CommandID(rawValue: id))?.descriptor else { continue }
                    let b = iconButton(CommandSymbols.symbol(for: id) ?? "circle.dashed", tooltip: tooltip(for: d), label: d.title)
                    b.identifier = NSUserInterfaceItemIdentifier(id)
                    b.target = self
                    b.action = #selector(commandPressed(_:))
                    elements.append(.command(id, b))
                case .menu(let title, let symbol, let commands, _):
                    let b = iconButton(symbol, tooltip: title, label: title)
                    b.image = Self.menuImage(symbol, label: title)
                    b.target = self
                    b.action = #selector(menuPressed(_:))
                    elements.append(.menu(title: title, commands: commands, b))
                }
            }
        }
        for e in elements { addSubview(e.view) }
        overflowButton.title = "»"
        overflowButton.bezelStyle = .accessoryBarAction
        overflowButton.showsBorderOnlyWhileMouseInside = true
        overflowButton.toolTip = L10n.tr("Pozostałe czynności wyniku")
        overflowButton.setAccessibilityLabel(L10n.tr("Pozostałe czynności wyniku"))
        overflowButton.target = self
        overflowButton.action = #selector(overflowPressed(_:))
        addSubview(overflowButton)
        addSubview(trailing)
    }

    private func iconButton(_ symbol: String, tooltip: String, label: String) -> NSButton {
        let b = NSButton(title: "", target: nil, action: nil)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        b.imagePosition = .imageOnly
        b.bezelStyle = .accessoryBarAction
        b.showsBorderOnlyWhileMouseInside = true
        b.toolTip = tooltip
        b.setAccessibilityLabel(label)
        return b
    }

    /// Symbol listy rozwijanej z małą strzałką w dół po prawej (jeden obraz-szablon — kolor jak w innych ikonach).
    private static func menuImage(_ symbol: String, label: String) -> NSImage? {
        guard let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: label),
              let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 7, weight: .semibold)) else { return nil }
        let size = NSSize(width: icon.size.width + chevron.size.width + 2, height: max(icon.size.height, chevron.size.height))
        let image = NSImage(size: size, flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: (size.height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            chevron.draw(in: NSRect(x: icon.size.width + 2, y: (size.height - chevron.size.height) / 2 - 2,
                                    width: chevron.size.width, height: chevron.size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = label
        return image
    }

    private func tooltip(for d: CommandDescriptor) -> String {
        var s = d.title.replacingOccurrences(of: "…", with: "") + "\n" + d.summary
        if let chord = workspace.keymap.chords(for: d.id).first { s += "\n" + L10n.tr("Skrót: \(chord.displayString)") }
        return s
    }

    // MARK: Stan

    private func refreshEnabled() {
        for case .command(let id, let b) in elements {
            let on = workspace.isEnabled(CommandID(rawValue: id))
            if b.isEnabled != on { b.isEnabled = on }
            // Stan komendy-przełącznika z rejestru (edycja danych, panel wartości).
            if let state = localState[id]?() ?? workspace.toggleState(CommandID(rawValue: id)) { setState(id, on: state) }
        }
    }

    /// Przełącznik włączony albo wyłączony (przycisk wyróżniony, symbol stanu włączonego): ze stanu komendy
    /// (`toggleState`) albo — stan samego widoku siatki (widok rekordu) — od widoku.
    func setState(_ id: String, on: Bool) {
        for case .command(id, let b) in elements {
            if toggles.insert(id).inserted { b.setButtonType(.pushOnPushOff) } else if (b.state == .on) == on { continue }
            b.state = on ? .on : .off
            guard let d = workspace.registry.command(CommandID(rawValue: id))?.descriptor else { continue }
            let symbol = on ? onSymbols[id] ?? CommandSymbols.symbol(for: id) : CommandSymbols.symbol(for: id)
            b.image = NSImage(systemSymbolName: symbol ?? "circle.dashed", accessibilityDescription: d.title)
        }
    }

    // MARK: Układ i przepełnienie

    private func width(of e: Element) -> CGFloat {
        switch e {
        case .command: Self.buttonWidth
        case .menu: Self.menuWidth
        case .separator: Self.separatorWidth
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    override func layout() {
        super.layout()
        let h = bounds.height
        let count = trailing.fittingSize
        let trailingWidth = min(count.width, max(0, bounds.width / 3))
        trailing.frame = NSRect(x: bounds.width - trailingWidth - 6, y: (h - count.height) / 2, width: trailingWidth, height: count.height)
        let available = Double(max(0, bounds.width - trailingWidth - 16))
        let widths = elements.map { Double(width(of: $0)) }
        visibleCount = ResultBarModel.fit(widths: widths, available: available - 4, overflowWidth: Double(Self.buttonWidth)) { i in
            if case .separator = self.elements[i] { true } else { false }
        }
        var x: CGFloat = 4
        for (i, e) in elements.enumerated() {
            let w = width(of: e)
            let shown = i < visibleCount
            e.view.isHidden = !shown
            guard shown else { continue }
            switch e {
            case .separator(let box): box.frame = NSRect(x: x + 4, y: (h - 14) / 2, width: 1, height: 14)
            default: e.view.frame = NSRect(x: x, y: (h - 22) / 2, width: w, height: 22)
            }
            x += w
        }
        overflowButton.isHidden = visibleCount >= elements.count
        overflowButton.frame = NSRect(x: x, y: (h - 22) / 2, width: Self.buttonWidth, height: 22)
    }

    // MARK: Akcje

    @objc private func commandPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        // Przełącznik zmienia stan sam po kliknięciu — stan przywraca model (`setState`) po wykonaniu komendy.
        if toggles.contains(id) { sender.state = sender.state == .on ? .off : .on }
        if let menu = menu(for: id) {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
        } else {
            run(id)
        }
    }

    @objc private func menuPressed(_ sender: NSButton) {
        guard case .menu(_, let commands, _)? = elements.first(where: { $0.view === sender }) else { return }
        commandMenu(commands).popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    /// Elementy niemieszczące się na pasku — w grupach, listy rozwijane jako podmenu.
    @objc private func overflowPressed(_ sender: NSButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for e in elements.dropFirst(visibleCount) {
            switch e {
            case .separator:
                if menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }
            case .command(let id, _):
                guard let item = commandItem(id) else { continue }
                if let sub = self.menu(for: id) { item.submenu = sub; item.action = nil }
                menu.addItem(item)
            case .menu(let title, let commands, _):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = commandMenu(commands)
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    private func menu(for id: String) -> NSMenu? {
        if let make = menus[id] { return make() }
        let format: (ExportFormat) -> String
        switch id {
        case "grid.export": format = { L10n.tr("Eksportuj jako \($0.displayName)…") }
        case "grid.copyAs": format = { $0.displayName }
        default: return nil
        }
        // Formaty z parametru komendy — te same co w wyborze ze wstążki i dla agenta.
        let formats = workspace.registry.command(CommandID(rawValue: id))?.descriptor.parameters
            .first { $0.name == "format" }?.allowedValues?.compactMap(ExportFormat.init(rawValue:)) ?? []
        guard !formats.isEmpty else { return nil }
        let menu = NSMenu()
        for f in formats {
            let item = menu.addItem(withTitle: format(f), action: #selector(formatChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [id, f.rawValue]
        }
        return menu
    }

    @objc private func formatChosen(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        workspace.perform(CommandID(rawValue: pair[0]), CommandArguments(["format": .string(pair[1])]))
    }

    private func commandMenu(_ commands: [String]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for raw in RibbonModel.expand(commands, in: workspace.registry) {
            if raw == RibbonModel.separator { menu.addItem(.separator()); continue }
            if let item = commandItem(raw) { menu.addItem(item) }
        }
        return menu
    }

    /// Stan przełącznika ustawiony przez widok siatki (`setState`, np. widok rekordu) — z przycisku.
    private func viewState(_ id: String) -> Bool? {
        guard toggles.contains(id) else { return nil }
        for case .command(id, let b) in elements { return b.state == .on }
        return nil
    }

    private func commandItem(_ raw: String) -> NSMenuItem? {
        guard let d = workspace.registry.command(CommandID(rawValue: raw))?.descriptor else { return nil }
        let item = NSMenuItem(title: d.title, action: #selector(menuCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = raw
        item.toolTip = d.summary
        item.isEnabled = workspace.isEnabled(d.id)
        // Stan przełącznika także w menu „»” i listach (jak na przycisku).
        if let on = localState[raw]?() ?? workspace.toggleState(d.id) ?? viewState(raw) { item.state = on ? .on : .off }
        if let symbol = CommandSymbols.symbol(for: raw) { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        if let chord = workspace.keymap.chords(for: d.id).first(where: { MenuBuilder.keyEquivalent(for: $0) != nil }),
           let (key, mask) = MenuBuilder.keyEquivalent(for: chord) {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = mask
        }
        return item
    }

    @objc private func menuCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        run(raw)
    }

    private func run(_ id: String) {
        if let action = actions[id] { action() } else { workspace.perform(CommandID(rawValue: id)) }
    }
}
