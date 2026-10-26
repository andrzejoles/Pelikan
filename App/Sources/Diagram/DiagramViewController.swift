import AppKit
import PelikanWorkspace

/// Okno diagramu (UG 11, PD-DIAG-001..003): pasek narzędzi i płótno z obiektami, liniami, grupami i notatkami.
final class DiagramViewController: NSViewController {
    let document: PelikanWorkspace.Document
    let workspace: Workspace
    private(set) var canvas: DiagramCanvas!
    private let zoomPopup = NSPopUpButton()
    private var tokens: [ObservationToken] = []

    var preferredFirstResponder: NSView { canvas }

    init(document: PelikanWorkspace.Document, workspace: Workspace) {
        self.document = document
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        canvas = DiagramCanvas(document: document, workspace: workspace)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = canvas
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        func button(_ title: String, _ symbol: String, _ command: CommandID) -> NSButton {
            let b = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(), target: nil, action: nil)
            b.bezelStyle = .texturedRounded
            b.imagePosition = .imageLeading
            b.toolTip = workspace.registry.command(command)?.descriptor.summary
            b.target = self
            b.action = #selector(run(_:))
            b.identifier = NSUserInterfaceItemIdentifier(command.rawValue)
            return b
        }
        for p in [10, 25, 50, 75, 100, 150, 200] { zoomPopup.addItem(withTitle: "\(p) %"); zoomPopup.lastItem?.tag = p }
        zoomPopup.target = self
        zoomPopup.action = #selector(zoomChanged)
        let export = NSPopUpButton(frame: .zero, pullsDown: true)
        export.addItem(withTitle: L10n.tr("Eksport"))
        for (t, f) in [("PNG…", "png"), ("PDF…", "pdf")] {
            export.addItem(withTitle: t)
            export.lastItem?.representedObject = f
            export.lastItem?.target = self
            export.lastItem?.action = #selector(exportItem(_:))
        }
        export.addItem(withTitle: L10n.tr("Kopiuj jako obraz"))
        export.lastItem?.target = self
        export.lastItem?.action = #selector(copyImage)
        export.addItem(withTitle: L10n.tr("Drukuj…"))
        export.lastItem?.target = self
        export.lastItem?.action = #selector(printDiagram)
        let bar = NSStackView(views: [
            button(L10n.tr("Dodaj"), "plus.rectangle", "diagram.addObject"),
            button(L10n.tr("Powiązane"), "point.3.connected.trianglepath.dotted", "diagram.addRelated"),
            button(L10n.tr("Zależności"), "arrow.triangle.branch", "diagram.addReferences"),
            button(L10n.tr("Notatka"), "note.text", "diagram.addNote"),
            button(L10n.tr("Grupa"), "rectangle.dashed", "diagram.addGroup"),
            button(L10n.tr("Kolumny"), "list.bullet.rectangle", "diagram.showColumns"),
            button(L10n.tr("Siatka"), "grid", "diagram.toggleGrid"),
            button(L10n.tr("Aktualizuj z bazy"), "arrow.clockwise", "diagram.updateFromDB"),
            zoomPopup, export,
        ])
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        // Wąskie okno: przyciski, które się nie mieszczą, są chowane od końca listy — zoom i eksport zostają.
        bar.setClippingResistancePriority(.defaultLow, for: .horizontal)
        for (i, v) in bar.arrangedSubviews.enumerated() {
            bar.setVisibilityPriority(v === zoomPopup || v === export ? .mustHold : NSStackView.VisibilityPriority(rawValue: Float(900 - i * 10)), for: v)
        }
        // Pasek u góry, płótno wypełnia resztę (w pionowym NSStackView widok przewijany bez wysokości własnej się zapadał).
        let root = NSView()
        for v in [bar, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        bar.setHuggingPriority(.required, for: .vertical)
        view = root
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            _ = self.document.diagram
            _ = self.document.diagramSelection
            self.canvas.refresh()
            self.zoomPopup.selectItem(withTag: Int((self.document.diagram.zoom * 100).rounded()))
        })
    }

    @objc private func run(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        workspace.activate(document.id)
        workspace.perform(CommandID(rawValue: id))
    }

    @objc private func zoomChanged() {
        document.diagram.setZoom(Double(zoomPopup.selectedTag()) / 100)
    }

    @objc private func exportItem(_ item: NSMenuItem) {
        DiagramOutput.export(document, format: item.representedObject as? String ?? "png", workspace: workspace)
    }

    @objc private func copyImage() { DiagramOutput.copy(document) }
    @objc private func printDiagram() { DiagramOutput.print(document) }
}

/// Płótno diagramu: rysowanie, zaznaczanie, przeciąganie (z dociąganiem do siatki), prostokąt zaznaczenia, zoom gestem,
/// upuszczanie obiektów z Object Browsera, menu kontekstowe.
final class DiagramCanvas: NSView {
    let document: PelikanWorkspace.Document
    weak var workspace: Workspace?
    /// Rysowanie bez zaznaczenia i tła siatki (eksport, druk).
    var plain = false
    private var dragStart: NSPoint?
    private var dragOffset = CGSize.zero
    private var rubber: NSRect?
    private var bendDrag: (link: UUID, index: Int)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(document: PelikanWorkspace.Document, workspace: Workspace?) {
        self.document = document
        self.workspace = workspace
        super.init(frame: NSRect(x: 0, y: 0, width: 1600, height: 1200))
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var diagram: Diagram { document.diagram }
    var zoom: CGFloat { plain ? 1 : CGFloat(diagram.zoom) }

    func refresh() {
        let b = diagram.bounds
        let w = max(CGFloat(b.x + b.width + 400) * zoom, superview?.bounds.width ?? 800)
        let h = max(CGFloat(b.y + b.height + 400) * zoom, superview?.bounds.height ?? 600)
        if frame.size != NSSize(width: w, height: h) { setFrameSize(NSSize(width: w, height: h)) }
        needsDisplay = true
    }

    func model(_ p: NSPoint) -> DiagramPoint { DiagramPoint(Double(p.x / zoom), Double(p.y / zoom)) }

    static func color(_ c: PelikanWorkspace.RGBColor?, default d: NSColor) -> NSColor {
        c.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } ?? d
    }

    func rect(_ r: DiagramRect, moving: Bool = false) -> NSRect {
        var n = NSRect(x: r.x, y: r.y, width: r.width, height: r.height)
        if moving { n = n.offsetBy(dx: dragOffset.width / zoom, dy: dragOffset.height / zoom) }
        return n
    }

    // MARK: Rysowanie

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)
        let sel = plain ? [] : document.diagramSelection
        if diagram.showGrid, !plain {
            NSColor.separatorColor.withAlphaComponent(0.25).setFill()
            let visible = NSRect(x: dirtyRect.minX / zoom, y: dirtyRect.minY / zoom, width: dirtyRect.width / zoom, height: dirtyRect.height / zoom)
            let g = CGFloat(Diagram.grid) * (zoom < 0.5 ? 4 : 1)
            var x = floor(visible.minX / g) * g
            while x < visible.maxX {
                var y = floor(visible.minY / g) * g
                while y < visible.maxY { NSRect(x: x, y: y, width: 1 / zoom, height: 1 / zoom).fill(); y += g }
                x += g
            }
        }
        for g in diagram.groups {
            let r = rect(g.frame, moving: sel.contains(g.id))
            Self.color(g.color, default: .systemGray).withAlphaComponent(0.08).setFill()
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            path.fill()
            (sel.contains(g.id) ? NSColor.controlAccentColor : NSColor.systemGray).setStroke()
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
            (g.title as NSString).draw(at: NSPoint(x: r.minX + 6, y: r.minY + 4),
                                       withAttributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        }
        for l in diagram.links { drawLink(l, selection: sel) }
        for it in diagram.items { drawItem(it, selected: sel.contains(it.id), moving: sel.contains(it.id)) }
        ctx.restoreGState()
        if let r = rubber {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            r.fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: r).stroke()
        }
    }

    func drawItem(_ it: DiagramItem, selected: Bool, moving: Bool) {
        let r = rect(it.frame, moving: moving)
        let border: NSColor = selected ? .controlAccentColor : .separatorColor
        if it.kind == .note {
            Self.color(it.color, default: .systemYellow.withAlphaComponent(0.25)).setFill()
            r.fill()
            border.setStroke()
            NSBezierPath(rect: r).stroke()
            (it.text as NSString).draw(in: r.insetBy(dx: 6, dy: 4), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
            return
        }
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        let header = NSRect(x: r.minX, y: r.minY, width: r.width, height: 22)
        Self.color(it.color, default: it.type == "TABLE" ? .systemBlue : .systemPurple).withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: header, xRadius: 4, yRadius: 4).fill()
        border.setStroke()
        path.lineWidth = selected ? 2 : 1
        path.stroke()
        let title = it.type == "TABLE" ? it.name.lowercased() : "\(it.name.lowercased())  (\(it.type.lowercased()))"
        (title as NSString).draw(in: header.insetBy(dx: 6, dy: 3), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        guard it.showColumns else { return }
        var y = r.minY + 26
        for c in it.columns {
            let name = (c.primaryKey ? "🔑 " : "") + c.name.lowercased()
            (name as NSString).draw(at: NSPoint(x: r.minX + 6, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
            let t = c.type.lowercased() + (c.nullable ? "" : " ●")
            let size = (t as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)])
            (t as NSString).draw(at: NSPoint(x: r.maxX - size.width - 6, y: y + 1),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
            y += 16
        }
    }

    /// Punkt na krawędzi prostokąta w kierunku punktu `toward`.
    static func edge(_ r: NSRect, toward p: NSPoint) -> NSPoint {
        let c = NSPoint(x: r.midX, y: r.midY)
        let dx = p.x - c.x, dy = p.y - c.y
        guard dx != 0 || dy != 0 else { return c }
        let sx = dx == 0 ? .infinity : (r.width / 2) / abs(dx)
        let sy = dy == 0 ? .infinity : (r.height / 2) / abs(dy)
        let s = min(sx, sy)
        return NSPoint(x: c.x + dx * s, y: c.y + dy * s)
    }

    func linkPoints(_ l: DiagramLink, selection: Set<UUID>) -> [NSPoint]? {
        guard let a = diagram.item(l.from), let b = diagram.item(l.to) else { return nil }
        let ra = rect(a.frame, moving: selection.contains(a.id)), rb = rect(b.frame, moving: selection.contains(b.id))
        let bends = l.bends.map { NSPoint(x: $0.x, y: $0.y) }
        let start = Self.edge(ra, toward: bends.first ?? NSPoint(x: rb.midX, y: rb.midY))
        let end = Self.edge(rb, toward: bends.last ?? NSPoint(x: ra.midX, y: ra.midY))
        return [start] + bends + [end]
    }

    func drawLink(_ l: DiagramLink, selection: Set<UUID>) {
        guard let pts = linkPoints(l, selection: selection), pts.count >= 2 else { return }
        let color = Self.color(l.color, default: l.kind == .reference ? .systemOrange : .secondaryLabelColor)
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.line(to: p) }
        path.lineWidth = selection.contains(l.id) ? 2.5 : 1.2
        if l.kind == .reference { path.setLineDash([5, 3], count: 2, phase: 0) }
        path.stroke()
        drawEnd(l.startEnd, at: pts[0], from: pts[1], color: color)
        drawEnd(l.endEnd, at: pts[pts.count - 1], from: pts[pts.count - 2], color: color)
        // Zaznaczona linia: uchwyty punktów łamania (przeciąganie, Option+klik usuwa; dwuklik na linii dodaje).
        if selection.contains(l.id) {
            NSColor.controlAccentColor.setFill()
            for b in pts.dropFirst().dropLast() { NSRect(x: b.x - 3.5, y: b.y - 3.5, width: 7, height: 7).fill() }
        }
        if !l.label.isEmpty {
            let mid = NSPoint(x: (pts[0].x + pts[pts.count - 1].x) / 2, y: (pts[0].y + pts[pts.count - 1].y) / 2)
            (l.label.lowercased() as NSString).draw(at: NSPoint(x: mid.x + 4, y: mid.y - 12),
                                                   withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor])
        }
    }

    func drawEnd(_ e: LineEnd, at p: NSPoint, from q: NSPoint, color: NSColor) {
        let angle = atan2(p.y - q.y, p.x - q.x)
        func pt(_ len: CGFloat, _ a: CGFloat) -> NSPoint { NSPoint(x: p.x - len * cos(angle + a), y: p.y - len * sin(angle + a)) }
        let path = NSBezierPath()
        switch e {
        case .none: return
        case .arrow:
            path.move(to: pt(10, 0.4)); path.line(to: p); path.line(to: pt(10, -0.4))
        case .crowFoot:
            // „Kurza stopka” przy tabeli podrzędnej: trzy linie z punktu na linii do krawędzi.
            let base = pt(12, 0)
            let px = -sin(angle), py = cos(angle)
            path.move(to: base); path.line(to: NSPoint(x: p.x + 7 * px, y: p.y + 7 * py))
            path.move(to: base); path.line(to: p)
            path.move(to: base); path.line(to: NSPoint(x: p.x - 7 * px, y: p.y - 7 * py))
        case .dot:
            NSBezierPath(ovalIn: NSRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)).fill()
            return
        }
        color.setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }

    // MARK: Interakcja

    func hit(_ p: DiagramPoint) -> UUID? {
        if let it = diagram.items.last(where: { $0.frame.contains(p) }) { return it.id }
        if let g = diagram.groups.last(where: { DiagramRect(x: $0.frame.x, y: $0.frame.y, width: $0.frame.width, height: 22).contains(p) }) { return g.id }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        workspace?.activate(document.id)
        let p = convert(event.locationInWindow, from: nil)
        let m = model(p)
        if event.clickCount == 2, let id = hit(m), let it = diagram.item(id), it.kind == .note {
            Task { @MainActor in
                guard let text = await workspace?.ui?.askText(L10n.tr("Notatka"), message: L10n.tr("Tekst notatki"), defaultValue: it.text) else { return }
                if let i = document.diagram.items.firstIndex(where: { $0.id == id }) {
                    document.diagram.items[i].text = text
                    document.isModified = true
                }
            }
            return
        }
        // Punkty łamania linii (PD-DIAG-002): przeciąganie, Option+klik usuwa, dwuklik na linii dodaje.
        let tolerance = 6 / Double(zoom)
        if let b = diagram.bend(at: m, tolerance: tolerance) {
            if event.modifierFlags.contains(.option) {
                document.diagram.removeBend(link: b.link, index: b.index)
                document.isModified = true
            } else {
                document.diagramSelection = [b.link]
                bendDrag = b
            }
            return
        }
        if hit(m) == nil, let l = diagram.link(at: m, tolerance: tolerance) {
            if event.clickCount == 2, let b = document.diagram.insertBend(at: m, tolerance: tolerance) {
                document.isModified = true
                bendDrag = b
            }
            document.diagramSelection = [l.link]
            return
        }
        if let id = hit(m) {
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command) {
                if document.diagramSelection.contains(id) { document.diagramSelection.remove(id) } else { document.diagramSelection.insert(id) }
            } else if !document.diagramSelection.contains(id) {
                document.diagramSelection = [id]
            }
            dragStart = p
        } else {
            if !event.modifierFlags.contains(.shift) { document.diagramSelection = [] }
            rubber = NSRect(origin: p, size: .zero)
            dragStart = p
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let b = bendDrag {
            document.diagram.moveBend(link: b.link, index: b.index, to: model(convert(event.locationInWindow, from: nil)))
            document.isModified = true
            needsDisplay = true
            return
        }
        guard let s = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        if rubber != nil {
            rubber = NSRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        } else {
            dragOffset = CGSize(width: p.x - s.x, height: p.y - s.y)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragOffset = .zero; rubber = nil; bendDrag = nil; needsDisplay = true }
        if let r = rubber {
            let mr = DiagramRect(x: Double(r.minX / zoom), y: Double(r.minY / zoom), width: Double(r.width / zoom), height: Double(r.height / zoom))
            document.diagramSelection.formUnion(diagram.items.filter { $0.frame.intersects(mr) }.map(\.id))
            return
        }
        guard dragOffset != .zero else { return }
        let dx = Double(dragOffset.width / zoom), dy = Double(dragOffset.height / zoom)
        document.diagram.move(document.diagramSelection, dx: dx, dy: dy)
        document.isModified = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { workspace?.perform("diagram.delete") } else { super.keyDown(with: event) }
    }

    override func magnify(with event: NSEvent) {
        document.diagram.setZoom(document.diagram.zoom * (1 + Double(event.magnification)))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        if let id = hit(model(p)), !document.diagramSelection.contains(id) { document.diagramSelection = [id] }
        let menu = NSMenu()
        for id in ["diagram.addRelated", "diagram.addReferences", "diagram.showColumns", "diagram.addGroup", "diagram.addNote", "diagram.delete"] as [CommandID] {
            guard let c = workspace?.registry.command(id) else { continue }
            let item = NSMenuItem(title: c.descriptor.title, action: #selector(menuCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let colors = NSMenuItem(title: L10n.tr("Kolor"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, c) in [(L10n.tr("Domyślny"), nil), (L10n.tr("Niebieski"), PelikanWorkspace.RGBColor(red: 0.3, green: 0.5, blue: 0.95)),
                          (L10n.tr("Zielony"), PelikanWorkspace.RGBColor(red: 0.3, green: 0.75, blue: 0.4)), (L10n.tr("Pomarańczowy"), PelikanWorkspace.RGBColor(red: 0.95, green: 0.6, blue: 0.2)),
                          (L10n.tr("Czerwony"), PelikanWorkspace.RGBColor(red: 0.9, green: 0.3, blue: 0.3))] as [(String, PelikanWorkspace.RGBColor?)] {
            let item = ClosureMenuItem(title: name) { [weak self] in self?.setColor(c) }
            sub.addItem(item)
        }
        colors.submenu = sub
        menu.addItem(colors)
        return menu
    }

    @objc private func menuCommand(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        workspace?.perform(CommandID(rawValue: id))
    }

    private func setColor(_ c: PelikanWorkspace.RGBColor?) {
        let sel = document.diagramSelection
        for i in document.diagram.items.indices where sel.contains(document.diagram.items[i].id) { document.diagram.items[i].color = c }
        for i in document.diagram.links.indices where sel.contains(document.diagram.links[i].id) { document.diagram.links[i].color = c }
        for i in document.diagram.groups.indices where sel.contains(document.diagram.groups[i].id) { document.diagram.groups[i].color = c }
        document.isModified = true
    }

    // MARK: Upuszczanie z Object Browsera (nazwa obiektu jako tekst)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let name = sender.draggingPasteboard.string(forType: .string), let ws = workspace else { return false }
        let at = model(convert(sender.draggingLocation, from: nil))
        let doc = document
        Task { @MainActor in
            do {
                let source = try await ws.schemaSource(for: doc)
                // Przeciąganie z Object Browsera zaznacza obiekt — ten ma właściciela i typ; inaczej nazwa ze słownika.
                let selected = ws.selectedObject.flatMap { $0.name.lowercased() == name.lowercased() ? $0 : nil }
                var found = selected
                if found == nil { found = try await source.resolve(name) }
                guard let o = found else { return }
                var d = doc.diagram
                let id = try await DiagramEditor.add(o, to: &d, at: at, source: source)
                doc.diagram = d
                doc.diagramSelection = [id]
                doc.isModified = true
            } catch { ws.ui?.showError(error.localizedDescription) }
        }
        return true
    }
}

/// Eksport obrazu, schowek i druk diagramu (PD-DIAG-003) — rysowanie bez zaznaczenia i siatki, w skali 100 %.
@MainActor
enum DiagramOutput {
    static func offscreen(_ doc: PelikanWorkspace.Document) -> (DiagramCanvas, NSRect) {
        let c = DiagramCanvas(document: doc, workspace: nil)
        c.plain = true
        let b = doc.diagram.bounds
        c.setFrameSize(NSSize(width: b.x + b.width + 16, height: b.y + b.height + 16))
        return (c, NSRect(x: b.x, y: b.y, width: b.width, height: b.height))
    }

    static func png(_ doc: PelikanWorkspace.Document) -> Data? {
        let (c, r) = offscreen(doc)
        guard let rep = c.bitmapImageRepForCachingDisplay(in: r) else { return nil }
        c.cacheDisplay(in: r, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    static func pdf(_ doc: PelikanWorkspace.Document) -> Data {
        let (c, r) = offscreen(doc)
        return c.dataWithPDF(inside: r)
    }

    static func export(_ doc: PelikanWorkspace.Document, format: String, workspace: Workspace) {
        let data = format == "pdf" ? pdf(doc) : png(doc)
        guard let data else { return }
        Task { _ = await workspace.ui?.saveFile(suggestedName: doc.title, fileExtension: format == "pdf" ? "pdf" : "png", data: data) }
    }

    static func copy(_ doc: PelikanWorkspace.Document) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = png(doc) { pb.setData(data, forType: .png) }
        pb.setData(pdf(doc), forType: .pdf)
    }

    static func print(_ doc: PelikanWorkspace.Document) {
        let (c, _) = offscreen(doc)
        // Kopia — paginacja diagramu nie może zmieniać wspólnych ustawień druku aplikacji.
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        NSPrintOperation(view: c, printInfo: info).run()
    }
}
