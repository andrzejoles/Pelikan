import Foundation
import PelikanDB
import PelikanSQL

/// Diagram ER z bazy (DB-DIAG-001): tabele schematu z kolumnami, linie kluczy obcych i automatyczny układ warstwowy
/// (tabele nadrzędne po lewej, podrzędne w kolejnych kolumnach); eksport obrazu — eksport diagramu (PNG/SVG/PDF).
public enum ERDiagram {
    public static let columnGap = 80.0
    public static let rowGap = 32.0

    /// Diagram z tabel (nazwy w schemacie `owner`) z liniami kluczy obcych między nimi.
    public static func build(owner: String, tables: [String], source: any SchemaMetadataSource, showColumns: Bool = true) async throws -> Diagram {
        var d = Diagram()
        let columns = try await source.columns(owner: owner, tables: tables)
        d.addObjectsForLayout(owner: owner, names: tables, type: "TABLE", columns: columns, showColumns: showColumns)
        d.addForeignKeyLinks(try await source.foreignKeys(owner: owner, childTables: tables))
        layout(&d)
        return d
    }

    /// Poziom tabeli: 0 dla tabel bez rodziców na diagramie, inaczej 1 + poziom najgłębszego rodzica (cykle przerwane).
    public static func levels(_ d: Diagram) -> [UUID: Int] {
        var parents: [UUID: Set<UUID>] = [:]
        for l in d.links where l.kind == .foreignKey && l.from != l.to { parents[l.from, default: []].insert(l.to) }
        var level: [UUID: Int] = [:]
        func visit(_ id: UUID, _ path: Set<UUID>) -> Int {
            if let v = level[id] { return v }
            var v = 0
            for p in parents[id] ?? [] where !path.contains(p) { v = max(v, visit(p, path.union([id])) + 1) }
            level[id] = v
            return v
        }
        for it in d.items where it.kind == .object { _ = visit(it.id, []) }
        return level
    }

    /// Układ warstwowy: kolumna na poziom, w kolumnie tabele posortowane po nazwie (kolejność rodziców najpierw);
    /// bardzo wysokie kolumny dzielone, żeby obraz nie był wąskim paskiem.
    public static func layout(_ d: inout Diagram) {
        let level = levels(d)
        let objects = d.items.filter { $0.kind == .object }
        guard !objects.isEmpty else { return }
        let maxLevel = level.values.max() ?? 0
        let totalHeight = objects.map { $0.frame.height + rowGap }.reduce(0, +)
        // Wysokość kolumny ~ proporcje 4:3 obrazu przy liczbie poziomów.
        let target = max(600, (totalHeight * 240 * 3 / 4).squareRoot())
        let index = Dictionary(d.items.indices.map { (d.items[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
        var x = Diagram.grid * 2
        for lv in 0...maxLevel {
            let column = objects.filter { (level[$0.id] ?? 0) == lv }.sorted { $0.name < $1.name }
            guard !column.isEmpty else { continue }
            var y = Diagram.grid * 2
            var widest = 0.0
            for it in column {
                if y > Diagram.grid * 2, y + it.frame.height > target {
                    x += widest + columnGap
                    y = Diagram.grid * 2
                    widest = 0
                }
                if let i = index[it.id] {
                    d.items[i].frame.x = Diagram.snap(x)
                    d.items[i].frame.y = Diagram.snap(y)
                }
                y += it.frame.height + rowGap
                widest = max(widest, it.frame.width)
            }
            x += widest + columnGap
        }
        for i in d.links.indices { d.links[i].bends = [] }
    }
}

extension Workspace {
    /// Nowe okno diagramu ER ze schematu (wszystkie tabele albo pasujące do maski LIKE).
    @discardableResult
    public func openERDiagram(owner: String, pattern: String = "%", connection: UUID?) async throws -> Document {
        guard let conn = connection ?? sessions.mainConnectionID else { throw CommandError.notConnected }
        let s = try await sessions.session(SessionKey(connectionID: conn, purpose: .tool("diagram")))
        let (_, rows) = try await s.queryAll("""
            select table_name from all_tables where owner = :o and table_name like :p escape '\\'
               and nested = 'NO' and table_name not like 'BIN$%' order by table_name
            """, binds: [BindVariable(name: "o", value: .text(owner.uppercased())), BindVariable(name: "p", value: .text(pattern.uppercased()))], limit: 2000)
        let tables = rows.compactMap { $0.first?.displayText }
        guard !tables.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak tabel pasujących do „\(pattern)” w schemacie \(owner)")) }
        let doc = newDocument(.diagram)
        doc.connectionID = conn
        doc.diagram = try await ERDiagram.build(owner: owner.uppercased(), tables: tables, source: SessionSchemaMetadata(session: s), showColumns: tables.count <= 60)
        doc.customTitle = L10n.tr("Diagram ER \(owner.uppercased())")
        doc.isModified = true
        return doc
    }
}
