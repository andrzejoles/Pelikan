import Foundation

/// Punkt i prostokąt diagramu (współrzędne w jednostkach przy zoomie 100 %).
public struct DiagramPoint: Sendable, Codable, Hashable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public struct DiagramRect: Sendable, Codable, Hashable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var center: DiagramPoint { DiagramPoint(x + width / 2, y + height / 2) }
    public func contains(_ p: DiagramPoint) -> Bool { p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height }
    public func intersects(_ r: DiagramRect) -> Bool { x < r.x + r.width && r.x < x + width && y < r.y + r.height && r.y < y + height }
}

/// Element diagramu: obiekt bazy (z kolumnami dla tabel i widoków) albo notatka (PD-DIAG-001/002).
public struct DiagramItem: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable { case object, note }
    public var id = UUID()
    public var kind: Kind
    public var owner = ""
    public var name = ""
    public var type = ""
    public var text = ""
    public var columns: [SchemaColumn] = []
    public var showColumns = true
    public var frame: DiagramRect
    public var color: RGBColor?

    public var title: String { kind == .note ? text : "\(owner.lowercased()).\(name.lowercased())" }
    public var objectKey: String { "\(owner).\(name)" }

    public init(kind: Kind, frame: DiagramRect) { self.kind = kind; self.frame = frame }
}

/// Zakończenie linii.
public enum LineEnd: String, Sendable, Codable, CaseIterable { case none, arrow, crowFoot, dot }

/// Linia: klucz obcy (child → parent), zależność (Reference link) albo dodana ręcznie; łamana przez punkty pośrednie.
public struct DiagramLink: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable { case foreignKey, reference, manual }
    public var id = UUID()
    public var kind: Kind
    public var from: UUID
    public var to: UUID
    public var label = ""
    public var bends: [DiagramPoint] = []
    public var startEnd: LineEnd = .none
    public var endEnd: LineEnd = .arrow
    public var color: RGBColor?

    public init(kind: Kind, from: UUID, to: UUID) { self.kind = kind; self.from = from; self.to = to }
}

/// Grupa: ramka z tytułem pod elementami.
public struct DiagramGroup: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var title: String
    public var frame: DiagramRect
    public var color: RGBColor?
    public init(title: String, frame: DiagramRect) { self.title = title; self.frame = frame }
}

/// Diagram (UG 11, PD-DIAG-001..003): elementy, linie, grupy, siatka 8 px i zoom 10–200 %; zapis jako JSON (.pdd).
public struct Diagram: Sendable, Codable, Hashable {
    public static let grid = 8.0
    public static let zoomRange = 0.1...2.0

    public var version = 1
    public var items: [DiagramItem] = []
    public var links: [DiagramLink] = []
    public var groups: [DiagramGroup] = []
    public var zoom = 1.0
    public var showGrid = true
    public var snapToGrid = true

    public init() {}

    public static func snap(_ v: Double) -> Double { (v / grid).rounded() * grid }

    public func item(_ id: UUID) -> DiagramItem? { items.first { $0.id == id } }

    public func item(owner: String, name: String) -> DiagramItem? {
        items.first { $0.kind == .object && $0.owner == owner && $0.name == name }
    }

    /// Wysokość ramki obiektu z kolumnami (nagłówek + wiersz na kolumnę).
    public static func objectSize(columns: Int, showColumns: Bool) -> (Double, Double) {
        (200, showColumns && columns > 0 ? 24 + Double(columns) * 16 + 6 : 32)
    }

    /// Wolne miejsce dla nowego elementu: kolejne pola siatki 240×(wysokość) od lewej, bez nakładania.
    public func freeFrame(width: Double, height: Double, near: DiagramPoint? = nil) -> DiagramRect {
        let start = near ?? DiagramPoint(Self.grid * 2, Self.grid * 2)
        var y = Self.snap(start.y)
        while true {
            var x = Self.snap(start.x)
            for _ in 0..<8 {
                let r = DiagramRect(x: x, y: y, width: width, height: height)
                let padded = DiagramRect(x: r.x - 16, y: r.y - 16, width: r.width + 32, height: r.height + 32)
                if !items.contains(where: { $0.frame.intersects(padded) }) { return r }
                x += 240
            }
            y += 120
        }
    }

    /// Dodaje obiekt bazy (gdy go nie ma) i zwraca jego identyfikator.
    @discardableResult
    public mutating func addObject(owner: String, name: String, type: String, columns: [SchemaColumn], at point: DiagramPoint? = nil) -> UUID {
        if let existing = item(owner: owner, name: name) { return existing.id }
        let (w, h) = Self.objectSize(columns: columns.count, showColumns: true)
        var it = DiagramItem(kind: .object, frame: freeFrame(width: w, height: h, near: point))
        it.owner = owner; it.name = name; it.type = type; it.columns = columns
        items.append(it)
        return it.id
    }

    @discardableResult
    public mutating func addNote(_ text: String, at point: DiagramPoint? = nil) -> UUID {
        var it = DiagramItem(kind: .note, frame: freeFrame(width: 160, height: 64, near: point))
        it.text = text
        it.color = RGBColor(red: 1, green: 0.97, blue: 0.75)
        items.append(it)
        return it.id
    }

    /// Grupa obejmująca wskazane elementy (z marginesem).
    @discardableResult
    public mutating func addGroup(_ title: String, around ids: Set<UUID>) -> UUID? {
        let frames = items.filter { ids.contains($0.id) }.map(\.frame)
        guard !frames.isEmpty else { return nil }
        let minX = frames.map(\.x).min()! - 16, minY = frames.map(\.y).min()! - 32
        let maxX = frames.map { $0.x + $0.width }.max()! + 16, maxY = frames.map { $0.y + $0.height }.max()! + 16
        let g = DiagramGroup(title: title, frame: DiagramRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        groups.append(g)
        return g.id
    }

    /// Linie kluczy obcych między obiektami, które są na diagramie (bez powtórzeń).
    public mutating func addForeignKeyLinks(_ fks: [ForeignKey]) {
        for fk in fks {
            guard let c = item(owner: fk.childOwner, name: fk.childTable), let p = item(owner: fk.parentOwner, name: fk.parentTable) else { continue }
            if links.contains(where: { $0.kind == .foreignKey && $0.label == fk.name && $0.from == c.id }) { continue }
            var l = DiagramLink(kind: .foreignKey, from: c.id, to: p.id)
            l.label = fk.name
            l.startEnd = .crowFoot
            l.endEnd = .none
            links.append(l)
        }
    }

    /// Linia zależności (Reference link): obiekt `from` korzysta z `to`.
    public mutating func addReferenceLink(from: UUID, to: UUID) {
        guard from != to, !links.contains(where: { $0.kind == .reference && $0.from == from && $0.to == to }) else { return }
        var l = DiagramLink(kind: .reference, from: from, to: to)
        l.endEnd = .arrow
        links.append(l)
    }

    /// Usuwa elementy wraz z ich liniami.
    public mutating func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        links.removeAll { ids.contains($0.id) || ids.contains($0.from) || ids.contains($0.to) }
        groups.removeAll { ids.contains($0.id) }
    }

    /// Przesuwa elementy (z dociąganiem do siatki, gdy włączone).
    public mutating func move(_ ids: Set<UUID>, dx: Double, dy: Double) {
        for i in items.indices where ids.contains(items[i].id) {
            items[i].frame.x = snapToGrid ? Self.snap(items[i].frame.x + dx) : items[i].frame.x + dx
            items[i].frame.y = snapToGrid ? Self.snap(items[i].frame.y + dy) : items[i].frame.y + dy
        }
        for i in groups.indices where ids.contains(groups[i].id) {
            groups[i].frame.x += dx
            groups[i].frame.y += dy
        }
    }

    public mutating func setZoom(_ z: Double) { zoom = min(max(z, Self.zoomRange.lowerBound), Self.zoomRange.upperBound) }

    public mutating func setShowColumns(_ show: Bool, for ids: Set<UUID>) {
        for i in items.indices where ids.contains(items[i].id) && items[i].kind == .object {
            items[i].showColumns = show
            let (_, h) = Self.objectSize(columns: items[i].columns.count, showColumns: show)
            items[i].frame.height = h
        }
    }

    /// Odświeżenie kolumn z bazy (Update from DB); obiekty, których już nie ma, zwracane do zgłoszenia.
    public mutating func update(columns: [String: [SchemaColumn]]) -> [String] {
        var missing: [String] = []
        for i in items.indices where items[i].kind == .object {
            guard let cols = columns[items[i].objectKey] else { missing.append(items[i].title); continue }
            items[i].columns = cols
            let (_, h) = Self.objectSize(columns: cols.count, showColumns: items[i].showColumns)
            items[i].frame.height = h
        }
        return missing
    }

    /// Prostokąt obejmujący całą zawartość (eksport obrazu, druk).
    public var bounds: DiagramRect {
        let frames = items.map(\.frame) + groups.map(\.frame)
        guard !frames.isEmpty else { return DiagramRect(x: 0, y: 0, width: 400, height: 300) }
        let minX = frames.map(\.x).min()!, minY = frames.map(\.y).min()!
        let maxX = frames.map { $0.x + $0.width }.max()!, maxY = frames.map { $0.y + $0.height }.max()!
        return DiagramRect(x: minX - 16, y: minY - 16, width: maxX - minX + 32, height: maxY - minY + 32)
    }

    // MARK: Plik

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> Diagram {
        try JSONDecoder().decode(Diagram.self, from: data)
    }
}

/// Punkty łamania linii (PD-DIAG-002): geometria w układzie diagramu, trafienie i edycja.
extension Diagram {
    /// Punkt na krawędzi prostokąta w kierunku `toward` (początek i koniec linii).
    static func edge(_ r: DiagramRect, toward p: DiagramPoint) -> DiagramPoint {
        let c = r.center
        let dx = p.x - c.x, dy = p.y - c.y
        guard dx != 0 || dy != 0 else { return c }
        let sx = dx == 0 ? Double.infinity : (r.width / 2) / abs(dx)
        let sy = dy == 0 ? Double.infinity : (r.height / 2) / abs(dy)
        let s = min(sx, sy)
        return DiagramPoint(c.x + dx * s, c.y + dy * s)
    }

    /// Łamana linii: krawędź elementu źródłowego, punkty łamania, krawędź elementu docelowego.
    public func polyline(_ l: DiagramLink) -> [DiagramPoint]? {
        guard let a = item(l.from), let b = item(l.to) else { return nil }
        let start = Self.edge(a.frame, toward: l.bends.first ?? b.frame.center)
        let end = Self.edge(b.frame, toward: l.bends.last ?? a.frame.center)
        return [start] + l.bends + [end]
    }

    static func distance(_ p: DiagramPoint, toSegment a: DiagramPoint, _ b: DiagramPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = dx * dx + dy * dy
        let t = len == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len))
        let px = a.x + t * dx - p.x, py = a.y + t * dy - p.y
        return (px * px + py * py).squareRoot()
    }

    /// Punkt łamania pod `p` (w promieniu `tolerance`).
    public func bend(at p: DiagramPoint, tolerance: Double = 6) -> (link: UUID, index: Int)? {
        for l in links.reversed() {
            if let i = l.bends.firstIndex(where: { abs($0.x - p.x) <= tolerance && abs($0.y - p.y) <= tolerance }) { return (l.id, i) }
        }
        return nil
    }

    /// Linia pod `p` i numer odcinka (0 — od elementu źródłowego do pierwszego punktu łamania).
    public func link(at p: DiagramPoint, tolerance: Double = 5) -> (link: UUID, segment: Int)? {
        for l in links.reversed() {
            guard let pts = polyline(l) else { continue }
            for i in 0..<(pts.count - 1) where Self.distance(p, toSegment: pts[i], pts[i + 1]) <= tolerance { return (l.id, i) }
        }
        return nil
    }

    /// Wstawia punkt łamania w odcinku linii pod `p` (z dociąganiem do siatki); zwraca jego numer.
    @discardableResult
    public mutating func insertBend(at p: DiagramPoint, tolerance: Double = 5) -> (link: UUID, index: Int)? {
        guard let hit = link(at: p, tolerance: tolerance), let i = links.firstIndex(where: { $0.id == hit.link }) else { return nil }
        links[i].bends.insert(DiagramPoint(Self.snap(p.x), Self.snap(p.y)), at: hit.segment)
        return (hit.link, hit.segment)
    }

    public mutating func moveBend(link id: UUID, index: Int, to p: DiagramPoint) {
        guard let i = links.firstIndex(where: { $0.id == id }), links[i].bends.indices.contains(index) else { return }
        links[i].bends[index] = DiagramPoint(Self.snap(p.x), Self.snap(p.y))
    }

    public mutating func removeBend(link id: UUID, index: Int) {
        guard let i = links.firstIndex(where: { $0.id == id }), links[i].bends.indices.contains(index) else { return }
        links[i].bends.remove(at: index)
    }
}
