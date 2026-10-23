import Foundation
import PelikanDB
import PelikanSQL

/// Zapytanie standardowe dla tabel i widoków (UG 7.14, PD-SQLW-013): `[owner]`, `[table]`, `[columns]` w tekście.
public struct StandardQuery: Sendable, Codable, Hashable, Identifiable {
    public var name: String
    public var sql: String
    public var id: String { name }
    public init(name: String, sql: String) { self.name = name; self.sql = sql }

    public static var standard: [StandardQuery] {
        [
            StandardQuery(name: L10n.tr("Wszystkie kolumny wymienione"), sql: "select [columns]\n  from [owner].[table] t"),
            StandardQuery(name: L10n.tr("Liczba wierszy"), sql: "select count(*) from [owner].[table]"),
            StandardQuery(name: L10n.tr("Ostatnio zmienione (ORA_ROWSCN)"), sql: "select t.*, scn_to_timestamp(ora_rowscn) zmieniono\n  from [owner].[table] t\n order by ora_rowscn desc\n fetch first 100 rows only"),
        ]
    }

    /// Tekst zapytania dla obiektu (kolumny z kwalifikatorem `t.`).
    public func text(owner: String, table: String, columns: [String]) -> String {
        let cols = columns.isEmpty ? "t.*" : columns.map { "t." + ResultExporter.identifier($0) }.joined(separator: ",\n       ")
        return sql.replacingOccurrences(of: "[owner]", with: ResultExporter.identifier(owner))
            .replacingOccurrences(of: "[table]", with: ResultExporter.identifier(table))
            .replacingOccurrences(of: "[columns]", with: cols)
    }

    /// Zapytanie standardowe z SQL siatki: nazwa tabeli (z kwalifikatorem albo bez) zastąpiona `[owner].[table]`.
    public static func from(sql: String, owner: String?, table: String, name: String) -> StandardQuery {
        var t = sql
        for pattern in [owner.map { "\($0).\(table)" }, owner.map { "\"\($0)\".\"\(table)\"" }, table].compactMap({ $0 }) {
            if let r = t.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: pattern))\b"#, options: [.regularExpression, .caseInsensitive]) {
                t.replaceSubrange(r, with: "[owner].[table]")
                break
            }
        }
        return StandardQuery(name: name, sql: t)
    }
}

/// Zapytanie powiązane kluczem obcym (UG 7.4, PD-SQLW-019).
public struct LinkedQuery: Sendable, Hashable, Identifiable {
    public enum Direction: String, Sendable, Hashable { case parent, child }
    public var direction: Direction
    public var constraint: String
    public var owner: String
    public var table: String
    /// Pary (kolumna w tabeli bieżącej, kolumna w tabeli powiązanej).
    public var columns: [(String, String)]
    public var id: String { "\(direction.rawValue):\(constraint)" }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    public var title: String {
        direction == .parent ? L10n.tr("Nadrzędna: \(owner).\(table)") : L10n.tr("Podrzędna: \(owner).\(table)")
    }

    /// Zapytanie dla wiersza: wartości kolumn klucza jako literały (bez okna zmiennych).
    public func sql(values: [String: OracleValue]) -> String {
        let conditions = columns.map { here, there -> String in
            let v = values[here.uppercased()] ?? .null
            if case .null = v { return "t.\(ResultExporter.identifier(there)) is null" }
            return "t.\(ResultExporter.identifier(there)) = \(ResultExporter.literal(v))"
        }
        return "select t.*, t.rowid\n  from \(ResultExporter.identifier(owner)).\(ResultExporter.identifier(table)) t\n where " + conditions.joined(separator: "\n   and ")
    }
}

public enum GridTools {
    /// Tabela źródłowa wyniku: z celu edycji (ROWID) albo pierwszej tabeli klauzuli FROM.
    @MainActor
    public static func sourceTable(of grid: ResultGridModel, defaultOwner: String) -> (owner: String, table: String)? {
        if let t = grid.edit.target { return ((t.owner ?? defaultOwner).uppercased(), t.table.uppercased()) }
        let ctx = CompletionContext.analyze(grid.sql, offset: min(7, (grid.sql as NSString).length))
        guard let t = ctx.tables.first(where: { $0.subquery == nil }) else { return nil }
        return ((t.owner ?? defaultOwner).uppercased(), t.name.uppercased())
    }

    /// Klucze obce: tabele nadrzędne (FK tej tabeli) i podrzędne (FK wskazujące na jej PK/UK).
    public static func linkedQueries(owner: String, table: String, in s: any DatabaseSession) async throws -> [LinkedQuery] {
        let (_, rows) = try await s.queryAll("""
            select 'parent' dir, c.constraint_name, r.owner, r.table_name, cc.column_name here, rc.column_name there, cc.position
              from all_constraints c
              join all_constraints r on r.owner = c.r_owner and r.constraint_name = c.r_constraint_name
              join all_cons_columns cc on cc.owner = c.owner and cc.constraint_name = c.constraint_name
              join all_cons_columns rc on rc.owner = r.owner and rc.constraint_name = r.constraint_name and rc.position = cc.position
             where c.constraint_type = 'R' and c.owner = :o and c.table_name = :t
            union all
            select 'child', c.constraint_name, c.owner, c.table_name, rc.column_name, cc.column_name, cc.position
              from all_constraints c
              join all_constraints r on r.owner = c.r_owner and r.constraint_name = c.r_constraint_name
              join all_cons_columns cc on cc.owner = c.owner and cc.constraint_name = c.constraint_name
              join all_cons_columns rc on rc.owner = r.owner and rc.constraint_name = r.constraint_name and rc.position = cc.position
             where c.constraint_type = 'R' and r.owner = :o and r.table_name = :t
             order by 1, 2, 7
            """, binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "t", value: .text(table))], limit: 5000)
        var out: [LinkedQuery] = []
        for r in rows {
            let dir = LinkedQuery.Direction(rawValue: r[0].displayText ?? "") ?? .child
            let name = r[1].displayText ?? ""
            let pair = (r[4].displayText ?? "", r[5].displayText ?? "")
            if let i = out.firstIndex(where: { $0.direction == dir && $0.constraint == name }) {
                out[i].columns.append(pair)
            } else {
                out.append(LinkedQuery(direction: dir, constraint: name, owner: r[2].displayText ?? "", table: r[3].displayText ?? "", columns: [pair]))
            }
        }
        return out
    }

    /// Wartości wiersza siatki po nazwie kolumny (wielkie litery).
    @MainActor
    public static func rowValues(_ grid: ResultGridModel, viewRow: Int) -> [String: OracleValue] {
        var v: [String: OracleValue] = [:]
        for (i, c) in grid.columns.enumerated() { v[c.name.uppercased()] = grid.value(row: grid.dataRow(viewRow), column: i) }
        return v
    }

    // MARK: Porównanie rekordów (UG 7.8, PD-SQLW-020)

    /// Kolumna porównania: wartości w kolejnych rekordach i czy są identyczne.
    public struct ColumnComparison: Sendable, Hashable, Identifiable {
        public var column: String
        public var values: [String]
        public var identical: Bool
        public var id: String { column }
    }

    @MainActor
    public static func compareRecords(_ grid: ResultGridModel, viewRows: [Int], ignoreCase: Bool) -> [ColumnComparison] {
        grid.columns.indices.map { c in
            let values = viewRows.map { grid.text(row: grid.dataRow($0), column: c) }
            let normalized = Set(values.map { ignoreCase ? $0.lowercased() : $0 })
            return ColumnComparison(column: grid.columns[c].name, values: values, identical: normalized.count <= 1)
        }
    }

    // MARK: Porównanie wyników (UG 7.9, PD-SQLW-021)

    public struct ResultDifference: Sendable, Equatable {
        /// Komórki różne (wiersz, nazwa kolumny) — kolumny dopasowane po nazwie.
        public var cells: Set<CellRef>
        public var rowsOnlyLeft: Int
        public var rowsOnlyRight: Int
        public var columnsOnlyLeft: [String]
        public var columnsOnlyRight: [String]
        public var identical: Bool { cells.isEmpty && rowsOnlyLeft == 0 && rowsOnlyRight == 0 && columnsOnlyLeft.isEmpty && columnsOnlyRight.isEmpty }

        public struct CellRef: Sendable, Hashable {
            public var row: Int
            public var column: String
            public init(row: Int, column: String) { self.row = row; self.column = column }
        }
    }

    @MainActor
    public static func compareResults(_ left: ResultGridModel, _ right: ResultGridModel, ignoreCase: Bool = false) -> ResultDifference {
        let ln = left.columns.map { $0.name.uppercased() }, rn = right.columns.map { $0.name.uppercased() }
        let common = ln.filter { rn.contains($0) }
        var cells = Set<ResultDifference.CellRef>()
        let n = min(left.rowCount, right.rowCount)
        for r in 0..<n {
            for name in common {
                var a = left.text(row: left.dataRow(r), column: ln.firstIndex(of: name)!)
                var b = right.text(row: right.dataRow(r), column: rn.firstIndex(of: name)!)
                if ignoreCase { a = a.lowercased(); b = b.lowercased() }
                if a != b { cells.insert(.init(row: r, column: name)) }
            }
        }
        return ResultDifference(cells: cells, rowsOnlyLeft: max(0, left.rowCount - n), rowsOnlyRight: max(0, right.rowCount - n),
                                columnsOnlyLeft: ln.filter { !rn.contains($0) }, columnsOnlyRight: rn.filter { !ln.contains($0) })
    }

    // MARK: Kolumna do plików (UG 7.2, PD-GRID-016)

    /// Nazwa pliku z szablonu: `[KOLUMNA]` → wartość kolumny wiersza (bez znaków niedozwolonych w nazwach plików),
    /// `[#]` → numer wiersza.
    public static func fileName(_ template: String, values: [String: String], index: Int) -> String {
        var out = template.replacingOccurrences(of: "[#]", with: String(index))
        let re = try! NSRegularExpression(pattern: #"\[([^\]]+)\]"#)
        let ns = out as NSString
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
            let key = ns.substring(with: m.range(at: 1)).uppercased()
            out = (out as NSString).replacingCharacters(in: m.range, with: values[key] ?? "")
        }
        let bad = CharacterSet(charactersIn: "/\\:\0").union(.newlines).union(.controlCharacters)
        let cleaned = String(out.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) })
        return cleaned.hasPrefix(".") ? "_" + cleaned.dropFirst() : cleaned
    }

    /// Zapis wartości kolumny każdego wiersza do osobnego pliku; zwraca liczbę plików. Wartości LOB pobrane w całości
    /// (siatka może trzymać skrócone — wtedy plik ma tylko pobraną część, raportowane w `truncated`).
    @MainActor
    public static func columnToFiles(_ grid: ResultGridModel, column: Int, viewRows: [Int], directory: URL, template: String) throws -> (files: Int, truncated: Int) {
        var files = 0, truncated = 0
        for (i, r) in viewRows.enumerated() {
            let row = grid.dataRow(r)
            var values: [String: String] = [:]
            for (c, col) in grid.columns.enumerated() { values[col.name.uppercased()] = grid.text(row: row, column: c) }
            let name = fileName(template, values: values, index: i + 1)
            guard !name.isEmpty else { continue }
            let data: Data
            switch grid.value(row: row, column: column) {
            case .null: continue
            case .lob(let l):
                if l.truncated { truncated += 1 }
                data = l.bytes ?? Data((l.text ?? "").utf8)
            case .raw(let d): data = d
            default: data = Data(grid.text(row: row, column: column).utf8)
            }
            try data.write(to: directory.appendingPathComponent(name))
            files += 1
        }
        return (files, truncated)
    }
}

/// Okna narzędzi siatki (aplikacja).
public enum GridToolRequest {
    case linkedQueries([LinkedQuery], values: [String: OracleValue], connection: UUID?)
    case compareRecords([GridTools.ColumnComparison])
    case compareResults(left: ResultTab, right: ResultTab)
    case columnToFiles(ResultTab)
    /// Grupowanie z licznikami (DB-GRID-001): karta, kolumna, wartości z liczbą wystąpień.
    case groupCounts(ResultTab, column: Int, counts: [GroupCount])
}

/// Komendy narzędzi siatki (PD-SQLW-013, 019, 020, 021, PD-GRID-016).
@MainActor
enum GridToolCommands {
    static func connection(_ ws: Workspace) -> UUID? {
        SQLCommands.sqlDocument(ws).flatMap { ws.effectiveConnection(of: $0) } ?? ws.sessions.mainConnectionID
    }

    static var all: [Command] {
        let hasGrid: @MainActor (Workspace) -> Bool = { GridCommands.activeGrid($0) != nil }
        return [
            Command(CommandDescriptor(id: "ob.standardQuery", title: L10n.tr("Zapytanie standardowe"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams + [CommandParameter("name", .string, required: true, L10n.tr("Nazwa zapytania standardowego"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno SQL z zapytaniem standardowym dla tabeli albo widoku i wykonuje je."),
                                      inMenu: false, feature: "PD-SQLW-013")) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                guard let q = ctx.workspace.settings.standardQueries.first(where: { $0.name == ctx.arguments.string("name") }) else {
                    throw CommandError.invalidArgument("name", ctx.arguments.string("name") ?? "")
                }
                let columns = try await m.columns(of: o).map(\.name)
                _ = try await ObjectCommands.sqlWindow(ctx.workspace, title: "\(o.name).sql", text: q.text(owner: o.owner, table: o.name, columns: columns), execute: true)
                return .ok
            },
            Command(CommandDescriptor(id: "grid.saveAsStandardQuery", title: L10n.tr("Zapisz jako zapytanie standardowe…"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Zapisuje zapytanie bieżącego wyniku jako zapytanie standardowe tabel i widoków (nazwa tabeli → [owner].[table])."),
                                      feature: "PD-SQLW-013"),
                    validate: hasGrid) { ctx in
                let ws = ctx.workspace
                guard let (_, grid) = GridCommands.activeGrid(ws) else { return .ok }
                let schema = ws.sessions.connectedSchema(connection(ws)) ?? ""
                guard let src = GridTools.sourceTable(of: grid, defaultOwner: schema) else { throw CommandError.notAvailable(L10n.tr("Nie rozpoznano tabeli zapytania")) }
                var name = ctx.arguments.string("name")
                if name == nil { name = await ctx.ui?.askText(L10n.tr("Zapytanie standardowe"), message: L10n.tr("Nazwa"), defaultValue: "") }
                guard let name, !name.isEmpty else { throw CommandError.cancelledByUser }
                ws.settings.standardQueries.removeAll { $0.name == name }
                ws.settings.standardQueries.append(StandardQuery.from(sql: grid.sql, owner: src.owner, table: src.table, name: name))
                return CommandResult(message: L10n.tr("Zapisano zapytanie standardowe „\(name)”"))
            },
            Command(CommandDescriptor(id: "grid.linkedQueries", title: L10n.tr("Zapytania powiązane…"), category: .session, submenu: L10n.tr("Wynik"),
                                      parameters: [CommandParameter("constraint", .string, L10n.tr("Nazwa klucza obcego (bez — wybór w oknie)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Tabele nadrzędne i podrzędne bieżącego wiersza z kluczy obcych; wybrana otwiera się w nowym oknie SQL z warunkiem na wartości wiersza."),
                                      feature: "PD-SQLW-019"),
                    validate: { ws in GridCommands.activeGrid(ws).map { $0.0.selectedRows?.first != nil } ?? false }) { ctx in
                let ws = ctx.workspace
                guard let (tab, grid) = GridCommands.activeGrid(ws), let row = tab.selectedRows?.first, let conn = connection(ws) else { return .ok }
                let schema = ws.sessions.connectedSchema(conn) ?? ""
                guard let src = GridTools.sourceTable(of: grid, defaultOwner: schema) else { throw CommandError.notAvailable(L10n.tr("Nie rozpoznano tabeli zapytania")) }
                let s = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("linked")))
                let links = try await GridTools.linkedQueries(owner: src.owner, table: src.table, in: s)
                guard !links.isEmpty else { throw CommandError.notAvailable(L10n.tr("Tabela \(src.table) nie ma powiązań kluczami obcymi")) }
                let values = GridTools.rowValues(grid, viewRow: row)
                if let c = ctx.arguments.string("constraint") {
                    guard let link = links.first(where: { $0.constraint.caseInsensitiveCompare(c) == .orderedSame }) else { throw CommandError.invalidArgument("constraint", c) }
                    let d = try await ObjectCommands.sqlWindow(ws, title: "\(link.table).sql", text: link.sql(values: values), execute: true)
                    d.connectionID = conn
                    return .ok
                }
                ctx.ui?.showGridTool(.linkedQueries(links, values: values, connection: conn))
                return .ok
            },
            Command(CommandDescriptor(id: "grid.compareRecords", title: L10n.tr("Porównaj rekordy"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Porównuje zaznaczone rekordy kolumna po kolumnie (identyczne / różne, opcjonalnie bez wielkości liter)."),
                                      feature: "PD-SQLW-020"),
                    validate: { ws in (GridCommands.activeGrid(ws)?.0.selectedRows?.count ?? 0) >= 2 }) { ctx in
                guard let (tab, grid) = GridCommands.activeGrid(ctx.workspace), let rows = tab.selectedRows, rows.count >= 2 else { return .ok }
                ctx.ui?.showGridTool(.compareRecords(GridTools.compareRecords(grid, viewRows: rows, ignoreCase: false)))
                return .ok
            },
            Command(CommandDescriptor(id: "grid.compareResults", title: L10n.tr("Porównaj wyniki"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Porównuje bieżącą kartę wyników z drugą kartą okna (przypiętą albo sąsiednią), z podświetleniem różnic."),
                                      feature: "PD-SQLW-021"),
                    validate: { ws in (SQLCommands.sqlDocument(ws)?.results.filter { $0.grid != nil }.count ?? 0) >= 2 }) { ctx in
                guard let doc = SQLCommands.sqlDocument(ctx.workspace), let active = GridCommands.activeTab(ctx.workspace) else { return .ok }
                let others = doc.results.filter { $0.grid != nil && $0.id != active.id }
                guard let other = others.first(where: \.pinned) ?? others.last else { return .ok }
                ctx.ui?.showGridTool(.compareResults(left: other, right: active))
                return .ok
            },
            Command(CommandDescriptor(id: "grid.columnToFiles", title: L10n.tr("Kolumna do plików…"), category: .file, submenu: L10n.tr("Eksport wyniku"),
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje wartość wybranej kolumny każdego wiersza do osobnego pliku; nazwy plików z szablonu z kolumnami wiersza."),
                                      feature: "PD-GRID-016"),
                    validate: hasGrid) { ctx in
                guard let tab = GridCommands.activeTab(ctx.workspace) else { return .ok }
                ctx.ui?.showGridTool(.columnToFiles(tab))
                return .ok
            },
        ]
    }
}
