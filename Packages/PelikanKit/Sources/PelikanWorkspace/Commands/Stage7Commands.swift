import Foundation
import PelikanDB

/// Komendy Etapu 7 (siatka i edytor): filtr i grupowanie wyników, generowanie SQL z wierszy, generowanie kodu
/// z obiektu, panel wartości, snippety (DB-GRID-001/002, SD-GEN-001, DB-PANEL-001, SC-SNIP-001).
@MainActor
enum Stage7Commands {
    /// Wstawia tekst w miejscu kursora (zastępuje zaznaczenie) okna edytora; okno tylko do odczytu — błąd (PD-FILE-003).
    static func insert(_ text: String, into doc: Document) throws {
        try BuiltinCommands.checkWritable(doc)
        let ns = doc.text as NSString
        let sel = min(doc.selectedRange.lowerBound, ns.length)..<min(doc.selectedRange.upperBound, ns.length)
        doc.text = ns.replacingCharacters(in: NSRange(location: sel.lowerBound, length: sel.count), with: text)
        let end = sel.lowerBound + (text as NSString).length
        doc.selectedRange = end..<end
    }

    static func editor(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, [.sql, .program, .test, .command].contains(d.kind) else { return nil }
        return d
    }

    static var all: [Command] {
        let hasGrid: @MainActor (Workspace) -> Bool = { GridCommands.activeGrid($0) != nil }
        let hasCell: @MainActor (Workspace) -> Bool = { ws in
            GridCommands.activeGrid(ws).map { $0.0.selectedRows?.first != nil && $0.0.currentColumn != nil } ?? false
        }
        return [
            // MARK: Filtr i grupowanie (DB-GRID-001)
            Command(CommandDescriptor(id: "grid.filterByValue", title: L10n.tr("Filtruj według wartości komórki"), category: .session, submenu: L10n.tr("Wynik"),
                                      parameters: [CommandParameter("exclude", .boolean, L10n.tr("Wyklucz wartość (≠) zamiast pokazać tylko ją (=)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pokazuje tylko wiersze z wartością bieżącej komórki w jej kolumnie (albo wszystkie poza nią) — lokalnie, bez ponownego zapytania."),
                                      feature: "DB-GRID-001"),
                    validate: hasCell) { ctx in
                guard let (tab, grid) = GridCommands.activeGrid(ctx.workspace), let row = tab.selectedRows?.first, let col = tab.currentColumn else { return .ok }
                let f = GridFilter.value(column: grid.columns[col].name, value: grid.value(row: row, column: col), format: grid.format,
                                         exclude: ctx.arguments.bool("exclude") ?? false)
                grid.setFilter(f)
                tab.selectedRows = []
                return CommandResult(message: L10n.tr("Filtr: \(f.text) — wierszy: \(grid.rowCount)"))
            },
            Command(CommandDescriptor(id: "grid.filterExpression", title: L10n.tr("Filtr wyrażeniem…"), category: .session, submenu: L10n.tr("Wynik"),
                                      parameters: [CommandParameter("expression", .string, L10n.tr("Np. SAL > 1000 AND ENAME LIKE 'S%' OR COMM IS NULL"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Filtruje pobrane wiersze wyrażeniem na kolumnach (=, <>, <, >, LIKE, IS NULL, AND, OR)."),
                                      feature: "DB-GRID-001"),
                    validate: hasGrid) { ctx in
                guard let (tab, grid) = GridCommands.activeGrid(ctx.workspace) else { return .ok }
                var expr = ctx.arguments.string("expression")
                if expr == nil {
                    expr = await ctx.ui?.askText(L10n.tr("Filtr wyników"), message: L10n.tr("Wyrażenie na kolumnach, np. SAL > 1000 AND ENAME LIKE 'S%'"),
                                                 defaultValue: grid.filter?.text ?? "")
                }
                guard let e = expr?.trimmingCharacters(in: .whitespacesAndNewlines) else { throw CommandError.cancelledByUser }
                if e.isEmpty { grid.setFilter(nil); return .ok }
                grid.setFilter(try GridFilter.parse(e, columns: grid.columns.map(\.name)))
                tab.selectedRows = []
                return CommandResult(message: L10n.tr("Filtr: \(e) — wierszy: \(grid.rowCount)"))
            },
            Command(CommandDescriptor(id: "grid.clearFilter", title: L10n.tr("Wyczyść filtr"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .uiState, summary: L10n.tr("Pokazuje znów wszystkie pobrane wiersze."), feature: "DB-GRID-001"),
                    validate: { GridCommands.activeGrid($0)?.1.filter != nil }) { ctx in
                GridCommands.activeGrid(ctx.workspace)?.1.setFilter(nil)
                return .ok
            },
            Command(CommandDescriptor(id: "grid.groupBy", title: L10n.tr("Grupuj według kolumny"), category: .session, submenu: L10n.tr("Wynik"),
                                      parameters: [CommandParameter("column", .string, L10n.tr("Kolumna (domyślnie bieżąca)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Wartości kolumny w widocznych wierszach z liczbą wystąpień; wybór wartości filtruje siatkę."),
                                      feature: "DB-GRID-001"),
                    validate: hasGrid) { ctx in
                guard let (tab, grid) = GridCommands.activeGrid(ctx.workspace) else { return .ok }
                let col: Int
                if let name = ctx.arguments.string("column") {
                    guard let c = grid.columns.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                        throw CommandError.invalidArgument("column", name)
                    }
                    col = c
                } else {
                    guard let c = tab.currentColumn ?? (grid.columns.isEmpty ? nil : 0) else { return .ok }
                    col = c
                }
                let counts = grid.groupCounts(column: col)
                ctx.ui?.showGridTool(.groupCounts(tab, column: col, counts: counts.map { GroupCount(value: $0.value, isNull: $0.isNull, count: $0.count) }))
                return CommandResult(value: .array(counts.map { .object(["value": .string($0.value), "count": .int(Int64($0.count))]) }))
            },
            // MARK: Panel wartości (DB-PANEL-001)
            Command(CommandDescriptor(id: "grid.valuePanel", title: L10n.tr("Panel wartości"), category: .view,
                                      mac: ["cmd+alt+v"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pokazuje albo ukrywa panel obok siatki z wartością bieżącej komórki (tekst, JSON, XML, HTML, obraz, hex)."),
                                      feature: "DB-PANEL-001")) { ctx in
                ctx.workspace.valuePanelVisible.toggle()
                return .ok
            },
            // MARK: SQL z wierszy (DB-GRID-002)
            Command(CommandDescriptor(id: "grid.generateSQL", title: L10n.tr("Generuj SQL z wierszy…"), category: .session, submenu: L10n.tr("Wynik"),
                                      parameters: [CommandParameter("kind", .string, required: true, L10n.tr("Rodzaj polecenia"), allowed: RowSQLGenerator.Kind.allCases.map(\.rawValue))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("INSERT, UPDATE, DELETE albo MERGE dla zaznaczonych wierszy (klucz z klucza głównego tabeli albo ROWID) w nowym oknie SQL, bez wykonania."),
                                      feature: "DB-GRID-002"),
                    validate: hasGrid) { ctx in
                let ws = ctx.workspace
                guard let (tab, grid) = GridCommands.activeGrid(ws) else { return .ok }
                guard let kind = RowSQLGenerator.Kind(rawValue: ctx.arguments.string("kind") ?? "") else { throw CommandError.missingArgument("kind") }
                let conn = GridToolCommands.connection(ws)
                let schema = ws.sessions.connectedSchema(conn) ?? ""
                guard let src = GridTools.sourceTable(of: grid, defaultOwner: schema) else { throw CommandError.notAvailable(L10n.tr("Nie rozpoznano tabeli zapytania")) }
                var keys: [String] = []
                if kind != .insert, let conn {
                    let s = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("generate")))
                    keys = try await RowSQLGenerator.primaryKey(owner: src.owner, table: src.table, in: s)
                }
                let viewRows = tab.selectedRows.flatMap { $0.isEmpty ? nil : $0 } ?? Array(0..<grid.rowCount)
                let rows = viewRows.map { r in grid.columns.indices.map { grid.value(row: r, column: $0) } }
                let table = src.owner.caseInsensitiveCompare(schema) == .orderedSame ? ResultExporter.identifier(src.table)
                    : "\(ResultExporter.identifier(src.owner)).\(ResultExporter.identifier(src.table))"
                let sql = try RowSQLGenerator.statements(kind, table: table, columns: grid.columns, rows: rows, keyColumns: keys)
                let doc = ws.newDocument(.sql, text: sql)
                doc.connectionID = conn
                doc.isModified = false
                return CommandResult(message: L10n.tr("Poleceń: \(rows.count)"), value: .string(sql))
            },
            // MARK: Kod z obiektu (SD-GEN-001)
            Command(CommandDescriptor(id: "ob.generateCode", title: L10n.tr("Generuj kod…"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams + [
                                          CommandParameter("kind", .string, required: true, L10n.tr("Rodzaj kodu"), allowed: CodeGenerator.Kind.allCases.map(\.rawValue)),
                                          CommandParameter("member", .string, L10n.tr("Podprogram pakietu (wywołanie)")),
                                          CommandParameter("newWindow", .boolean, L10n.tr("W nowym oknie zamiast w miejscu kursora")),
                                          CommandParameter("returnOnly", .boolean, L10n.tr("Tylko zwróć kod (bez wstawiania)"))],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("SELECT/INSERT/UPDATE/DELETE z kolumnami tabeli, wywołanie procedury z parametrami albo fragment Java JDBC / Python — w miejscu kursora albo w nowym oknie."),
                                      feature: "SD-GEN-001")) { ctx in
                let ws = ctx.workspace
                guard let kind = CodeGenerator.Kind(rawValue: ctx.arguments.string("kind") ?? "") else { throw CommandError.missingArgument("kind") }
                let (o, m) = try await ObjectCommands.target(ctx)
                let code: String
                if kind == .call {
                    guard [.procedure, .function, .package, .packageBody].contains(o.type) else {
                        throw CommandError.notAvailable(L10n.tr("Wywołanie generuje się dla procedury, funkcji albo podprogramu pakietu"))
                    }
                    let member = ctx.arguments.string("member")
                    if o.type == .package || o.type == .packageBody, member == nil {
                        throw CommandError.missingArgument("member")
                    }
                    code = try await TestRunner.script(for: o, member: member, metadata: m).0
                } else {
                    guard [.table, .view, .materializedView, .synonym].contains(o.type) else {
                        throw CommandError.notAvailable(L10n.tr("Kod SQL generuje się dla tabeli albo widoku"))
                    }
                    let s = try await m.session()
                    let pk = o.type == .table ? (try? await RowSQLGenerator.primaryKey(owner: o.owner, table: o.name, in: s)) ?? [] : []
                    let cols = try await m.columns(of: o).filter { $0.kind == .column }.map {
                        CodeGenerator.Column(name: $0.name, type: $0.detail, isKey: pk.contains($0.name))
                    }
                    let alias = ws.connections.connection(m.connectionID)?.agentAlias ?? "ALIAS"
                    code = CodeGenerator.generate(kind, object: o, columns: cols, connectionAlias: alias)
                }
                if ctx.arguments.bool("returnOnly") == true { return CommandResult(value: .string(code)) }
                if ctx.arguments.bool("newWindow") != true, let doc = editor(ws) {
                    try insert(code, into: doc)
                } else {
                    let doc = ws.newDocument(.sql, text: code)
                    // Okno kodu obiektu innego połączenia jest do niego przypięte (D185).
                    ws.bind(doc, to: m.connectionID)
                    doc.isModified = false
                }
                return CommandResult(value: .string(code))
            },
            // MARK: Snippety (SC-SNIP-001)
            Command(CommandDescriptor(id: "view.snippets", title: L10n.tr("Snippety"), category: .view,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Biblioteka fragmentów kodu: wbudowane i własne; dwuklik albo przeciągnięcie wstawia do edytora."),
                                      feature: "SC-SNIP-001")) { ctx in
                ctx.ui?.showSnippets()
                return .ok
            },
            Command(CommandDescriptor(id: "edit.insertSnippet", title: L10n.tr("Wstaw snippet"), category: .edit,
                                      parameters: [CommandParameter("id", .string, required: true, L10n.tr("Identyfikator: kategoria/nazwa"))],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Wstawia fragment kodu z biblioteki w miejscu kursora aktywnego edytora."), inMenu: false,
                                      feature: "SC-SNIP-001"),
                    validate: { editor($0) != nil }) { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                guard let s = ctx.workspace.snippets.all.first(where: { $0.id == ctx.arguments.string("id") }) else {
                    throw CommandError.invalidArgument("id", ctx.arguments.string("id") ?? "")
                }
                try insert(s.text, into: doc)
                return .ok
            },
        ]
    }
}

/// Wartość i liczba wystąpień (grupowanie siatki).
public struct GroupCount: Sendable, Hashable, Identifiable {
    public var value: String
    public var isNull: Bool
    public var count: Int
    public var id: String { (isNull ? "\u{0}" : "") + value }
}
