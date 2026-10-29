import AppKit
import PelikanSQL
import PelikanWorkspace

/// Code Contents (UG 25.15): drzewo struktury kodu — specyfikacja i ciało osobno, podprogramy (parametry i typ zwracany),
/// typy, kursory, zmienne, stałe, wyjątki, pragmy, podprogramy zagnieżdżone; elementy prywatne ciała pochylone
/// i przygaszone. Śledzi kursor (zaznacza element zawierający pozycję), klik albo Enter przenosi do nazwy elementu
/// (także na innej karcie jednostki — D192), strzałki w drzewie przesuwają kursor bez zmiany fokusu; filtr nazw nad
/// drzewem, sortowanie i menu elementu (PD-CA-010). Ten sam widok w oknie programu, SQL i testu (`CodeContentsPanel`,
/// D199) — w oknie SQL także polecenia SQL skryptu.
final class CodeContentsView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    /// Węzeł drzewa (NSOutlineView wymaga obiektów o stałej tożsamości).
    final class Item {
        let node: OutlineNode
        let children: [Item]
        init(_ node: OutlineNode) {
            self.node = node
            // Parametry pokazywane w nazwie podprogramu, nie jako osobne węzły.
            children = node.children.filter { $0.kind != .parameter }.map(Item.init)
        }
    }

    /// Drzewo z Enter jako „przejdź” (NSOutlineView sam nie wysyła akcji klawiszem).
    final class Tree: NSOutlineView {
        var onEnter: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76 { onEnter?(); return }
            super.keyDown(with: event)
        }
    }

    private let outline = Tree()
    private let scroll = NSScrollView()
    private let filterField = NSSearchField()
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private var noteHidden: NSLayoutConstraint!
    private var roots: [Item] = []
    private var selecting = false
    private var rawNodes: [OutlineNode] = []
    private var filter = ""
    /// Przejście do elementu; `focus` — fokus do edytora (klik, Enter), bez — zostaje w drzewie (strzałki).
    var onSelect: ((OutlineNode, _ focus: Bool) -> Void)?
    /// Odcinek karty jednostki widocznej w edytorze — jej korzeń pogrubiony (D192).
    var activeRange: Range<Int>? {
        didSet {
            guard activeRange != oldValue else { return }
            for r in roots { reloadRow(r) }
        }
    }
    /// Kolejność elementów (Ustawienia › Edytor, menu panelu).
    var order: CodeContents.Order = .source {
        didSet { if order != oldValue { update(rawNodes) } }
    }

    /// Dopisek nad drzewem (np. skrypt z poleceniami ponad limit); nil — bez dopisku.
    var note: String? {
        didSet {
            guard note != oldValue else { return }
            noteLabel.stringValue = note ?? ""
            noteLabel.isHidden = note == nil
            noteHidden.isActive = note == nil
        }
    }

    private var fontToken: ObservationToken?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let c = NSTableColumn(identifier: .init("name"))
        c.resizingMask = .autoresizingMask
        outline.addTableColumn(c)
        outline.outlineTableColumn = c
        outline.headerView = nil
        // Wysokość wiersza z czcionki interfejsu (przy stylu innym niż `.custom` AppKit ignoruje `rowHeight`).
        outline.rowSizeStyle = .custom
        // Drzewo z wyraźnym wcięciem poziomów (styl listy paska bocznego macOS prawie nie wcina dzieci).
        outline.style = .plain
        outline.indentationPerLevel = 16
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.onEnter = { [weak self] in self?.activateSelected() }
        outline.setAccessibilityLabel(L10n.tr("Zawartość kodu"))
        outline.menu = NSMenu()
        outline.menu?.delegate = self
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        filterField.placeholderString = L10n.tr("Filtr nazw")
        filterField.setAccessibilityLabel(L10n.tr("Filtr nazw zawartości kodu"))
        filterField.controlSize = .small
        filterField.sendsSearchStringImmediately = true
        filterField.delegate = self
        filterField.target = self
        filterField.action = #selector(filterChanged)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.isHidden = true
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        noteHidden = noteLabel.heightAnchor.constraint(equalToConstant: 0)
        noteHidden.isActive = true
        addSubview(filterField)
        addSubview(noteLabel)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            filterField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            filterField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            noteLabel.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 4),
            noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            noteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 4), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        fontToken = trackChanges { [weak self] in
            guard let self else { return }
            let font = InterfaceFonts.shared.small
            outline.rowHeight = AppFonts.rowHeight(for: font)
            filterField.font = font
            noteLabel.font = font
            // Bez `reloadData` — zachowuje rozwinięcie i zaznaczenie.
            for row in 0..<outline.numberOfRows {
                (outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView)?.textField?.font = font
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Nowy zarys; zachowuje rozwinięcie węzłów o tej samej ścieżce nazw.
    /// Klucz rozwinięcia: ścieżka rodzajów i nazw z numerem kolejnym wśród rodzeństwa o tym samym rodzaju i nazwie —
    /// specyfikacja i ciało o tej samej nazwie oraz kolejne bloki „BEGIN” mają osobny stan.
    private static func keys(_ prefix: String, _ items: [Item]) -> [String] {
        var seen: [String: Int] = [:]
        return items.map { i in
            let base = i.node.kind.rawValue + ":" + i.node.name
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return prefix + "/" + base + (n == 0 ? "" : "#\(n)")
        }
    }

    /// Bez rozwijania przy pierwszym pokazaniu, gdy korzeni jest więcej (skrypt z tysiącami poleceń).
    private static let autoExpandLimit = 200

    /// Rozwinięcie sprzed filtrowania — przywracane po wyczyszczeniu filtra (przy filtrze drzewo jest rozwinięte całe).
    private var expandedBeforeFilter: Set<String>?

    private func expandedKeys() -> Set<String> {
        var expanded = Set<String>()
        func collect(_ items: [Item], _ prefix: String) {
            for (i, key) in zip(items, Self.keys(prefix, items)) where !i.children.isEmpty && outline.isItemExpanded(i) {
                expanded.insert(key)
                collect(i.children, key)
            }
        }
        collect(roots, "")
        return expanded
    }

    func update(_ nodes: [OutlineNode], restoring saved: Set<String>? = nil) {
        let first = roots.isEmpty
        let expanded = saved ?? expandedKeys()
        rawNodes = nodes
        roots = CodeContents.sorted(CodeContents.filtered(nodes, matching: filter), order: order).map(Item.init)
        outline.reloadData()
        let expandRoots = first && roots.count <= Self.autoExpandLimit
        func restore(_ items: [Item], _ prefix: String, depth: Int) {
            for (i, key) in zip(items, Self.keys(prefix, items)) where !i.children.isEmpty {
                // Przy filtrze — wszystko rozwinięte (widać pasujące elementy).
                if expanded.contains(key) || (expandRoots && depth == 0) || !filter.isEmpty { outline.expandItem(i); restore(i.children, key, depth: depth + 1) }
            }
        }
        restore(roots, "", depth: 0)
    }

    private var filterWork: DispatchWorkItem?

    /// Filtr z opóźnieniem (pakiet z tysiącami elementów — bez przebudowy drzewa przy każdym znaku); przy bardzo
    /// wielu elementach (skrypt z tysiącami poleceń) — dłuższym.
    @objc private func filterChanged() {
        filterWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyFilter() }
        filterWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (rawNodes.count > 1000 ? 0.45 : 0.18), execute: work)
    }

    private func applyFilter() {
        let new = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        guard new != filter else { return }
        if filter.isEmpty { expandedBeforeFilter = expandedKeys() }
        filter = new
        if new.isEmpty {
            let saved = expandedBeforeFilter
            expandedBeforeFilter = nil
            update(rawNodes, restoring: saved ?? [])
        } else {
            update(rawNodes)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Strzałka w dół z pola filtru — do drzewa; Esc — czyści filtr.
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            filterWork?.perform()
            filterWork = nil
            window?.makeFirstResponder(outline)
            if outline.selectedRow < 0, outline.numberOfRows > 0 { outline.selectRowIndexes([0], byExtendingSelection: false) }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), !filterField.stringValue.isEmpty {
            filterField.stringValue = ""
            filterWork?.cancel()
            applyFilter()
            return true
        }
        return false
    }

    private func reloadRow(_ item: Item) {
        let row = outline.row(forItem: item)
        if row >= 0 { outline.reloadData(forRowIndexes: [row], columnIndexes: [0]) }
    }

    /// Śledzenie kursora: zaznacza najgłębszy element zawierający pozycję.
    func track(offset: Int) {
        var level = roots
        var target: Item?
        while let i = level.first(where: { $0.node.range.contains(offset) || $0.node.range.upperBound == offset }) {
            target = i
            if !i.node.isContainer { break }
            if i.children.contains(where: { $0.node.range.contains(offset) }) { outline.expandItem(i) }
            level = i.children
        }
        guard let target else { outline.deselectAll(nil); return }
        let row = outline.row(forItem: target)
        guard row >= 0, outline.selectedRow != row else { return }
        selecting = true
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        selecting = false
    }

    // MARK: Menu elementu (PD-CA-010)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
        if let item = outline.item(atRow: outline.clickedRow) as? Item {
            let n = item.node
            let args = CommandArguments(["offset": .int(Int64(n.nameOffset))])
            menu.addItem(ClosureMenuItem(title: L10n.tr("Przejdź")) { [weak self] in self?.onSelect?(n, true) })
            menu.addItem(ClosureMenuItem(title: L10n.tr("Zaznacz")) { ws.perform("codeContents.select", args) })
            menu.addItem(ClosureMenuItem(title: L10n.tr("Kopiuj")) { ws.perform("codeContents.copy", args) })
            menu.addItem(ClosureMenuItem(title: L10n.tr("Wytnij")) { ws.perform("codeContents.cut", args) })
            if [.procedure, .function].contains(n.kind) {
                menu.addItem(ClosureMenuItem(title: L10n.tr("Testuj")) { ws.perform("codeContents.test", args) })
            }
            menu.addItem(.separator())
        }
        let sort = NSMenuItem(title: L10n.tr("Sortuj"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (o, title) in [(CodeContents.Order.source, L10n.tr("Jak w źródle")), (.name, L10n.tr("Alfabetycznie")), (.kind, L10n.tr("Według rodzaju"))] {
            let i = ClosureMenuItem(title: title) { ws.perform("codeContents.sort", CommandArguments(["order": .string(o.rawValue)])) }
            i.state = order == o ? .on : .off
            sub.addItem(i)
        }
        sort.submenu = sub
        menu.addItem(sort)
        menu.addItem(ClosureMenuItem(title: L10n.tr("Rozwiń wszystko")) { [weak self] in self?.outline.expandItem(nil, expandChildren: true) })
        menu.addItem(ClosureMenuItem(title: L10n.tr("Zwiń wszystko")) { [weak self] in self?.outline.collapseItem(nil, collapseChildren: true) })
    }

    @objc private func clicked() {
        guard let i = outline.item(atRow: outline.clickedRow) as? Item else { return }
        onSelect?(i.node, true)
    }

    private func activateSelected() {
        guard let i = outline.item(atRow: outline.selectedRow) as? Item else { return }
        onSelect?(i.node, true)
    }

    /// Zaznaczenie zmienione klawiaturą w drzewie — kursor edytora idzie za nim (fokus zostaje w drzewie).
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !selecting, NSApp.currentEvent?.type == .keyDown, window?.firstResponder === outline,
              let i = outline.item(atRow: outline.selectedRow) as? Item else { return }
        onSelect?(i.node, false)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Item)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Item)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Item)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = (item as? Item)?.node else { return nil }
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: Self.symbol(n), accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = Self.tint(n.kind)
        let label = NSTextField(labelWithString: Self.title(n))
        var font = InterfaceFonts.shared.small
        // Prywatne elementy ciała — pochylone i przygaszone; korzeń widocznej karty — pogrubiony.
        if n.isPublic == false {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            label.textColor = .secondaryLabelColor
        }
        if let a = activeRange, outlineView.parent(forItem: item) == nil, a.contains(n.nameOffset) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        label.font = font
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = CodeContents.signature(of: n)
        label.setAccessibilityLabel(CodeContents.signature(of: n))
        for v in [icon, label] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14), icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
        ])
        cell.textField = label
        return cell
    }

    /// Tekst węzła: nazwa, parametry podprogramu, typ zwracany albo typ deklaracji.
    static func title(_ n: OutlineNode) -> String {
        switch n.kind {
        case .procedure, .function:
            let params = n.children.filter { $0.kind == .parameter }.map(\.name)
            var s = n.name + (params.isEmpty ? "" : "(" + params.joined(separator: ", ") + ")")
            if !n.detail.isEmpty { s += " return " + n.detail }
            return s
        case .package, .type: return n.name + " (" + L10n.tr("specyfikacja") + ")"
        case .packageBody, .typeBody: return n.name + " (" + L10n.tr("ciało") + ")"
        case .typeDeclaration:
            // Rodzaj typu krótko (szczegóły w podpowiedzi).
            return n.typeShape.isEmpty ? n.name : n.name + " " + n.typeShape.lowercased()
        case .cursor:
            let params = n.detail.hasPrefix("(") ? String(n.detail[..<(n.detail.firstIndex(of: ")").map { n.detail.index(after: $0) } ?? n.detail.endIndex)]) : ""
            return n.name + params
        case .pragma: return "pragma " + n.name.lowercased()
        case .block: return n.name
        // Polecenie SQL skryptu: szczegóły wieloliniowe (do ok. 1000 znaków w podpowiedzi) — w drzewie jedna linia.
        case .statement:
            let line = n.detail.prefix(200).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return line.isEmpty ? n.name : n.name + " " + line
        default: return n.detail.isEmpty ? n.name : n.name + " " + n.detail
        }
    }

    static func symbol(_ n: OutlineNode) -> String {
        // Deklaracje typów wg rodzaju: rekord, kolekcja, kursor referencyjny, podtyp.
        guard n.kind == .typeDeclaration else { return symbol(n.kind) }
        switch n.typeShape {
        case "RECORD": return "rectangle.split.3x1"
        case "TABLE", "VARRAY": return "tablecells"
        case "REF CURSOR": return "arrow.right.circle"
        case "SUBTYPE": return "t.square"
        default: return symbol(n.kind)
        }
    }

    static func symbol(_ k: OutlineNode.Kind) -> String {
        // Rodzaje będące obiektami bazy — ikony jak w Object Browserze i podpowiedziach.
        switch k {
        case .package, .packageBody: ObjectSymbols.symbol(for: .package)
        case .type, .typeBody, .typeDeclaration: ObjectSymbols.symbol(for: .type)
        case .procedure: ObjectSymbols.symbol(for: .procedure)
        case .function: ObjectSymbols.symbol(for: .function)
        case .trigger: ObjectSymbols.symbol(for: .trigger)
        case .block, .declareSection, .beginSection, .exceptionSection: "curlybraces"
        case .cursor: "list.bullet.rectangle"
        case .exception: "exclamationmark.triangle"
        case .constant: "c.square"
        case .variable, .parameter: "v.square"
        case .pragma: "p.square"
        case .statement: "text.alignleft"
        }
    }

    static func tint(_ k: OutlineNode.Kind) -> NSColor {
        switch k {
        case .package, .packageBody, .type, .typeBody: .systemOrange
        case .procedure, .function, .trigger: .systemBlue
        case .exception: .systemRed
        case .typeDeclaration, .cursor: .systemPurple
        case .statement: .systemGreen
        case .constant: .systemTeal
        default: .secondaryLabelColor
        }
    }
}
