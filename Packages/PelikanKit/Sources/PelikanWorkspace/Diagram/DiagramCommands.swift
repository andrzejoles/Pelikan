import Foundation
import PelikanDB
import PelikanSQL

/// Operacje diagramu korzystające ze słownika bazy (PD-DIAG-001, PD-DIAG-003).
public enum DiagramEditor {
    static let tableTypes: Set<String> = ["TABLE", "VIEW", "MATERIALIZED VIEW"]

    /// Dodaje obiekt (tabela/widok z kolumnami) i linie kluczy obcych do obiektów już obecnych.
    @discardableResult
    public static func add(_ o: DBObject, to d: inout Diagram, at point: DiagramPoint? = nil, source: any SchemaMetadataSource) async throws -> UUID {
        if let existing = d.item(owner: o.owner, name: o.name) { return existing.id }
        let isTable = tableTypes.contains(o.type.rawValue)
        let cols = isTable ? try await source.columns(owner: o.owner, name: o.name) : []
        let id = d.addObject(owner: o.owner, name: o.name, type: o.type.rawValue, columns: cols, at: point)
        if o.type == .table { d.addForeignKeyLinks(try await source.foreignKeys(owner: o.owner, table: o.name)) }
        return id
    }

    /// Tabele powiązane kluczami obcymi z zaznaczonymi (nadrzędne i podrzędne) wraz z liniami.
    public static func addRelated(_ ids: Set<UUID>, to d: inout Diagram, source: any SchemaMetadataSource) async throws {
        for it in d.items where ids.contains(it.id) && it.kind == .object && it.type == "TABLE" {
            let fks = try await source.foreignKeys(owner: it.owner, table: it.name)
            for fk in fks {
                let child = fk.childOwner == it.owner && fk.childTable == it.name
                let other = child ? (fk.parentOwner, fk.parentTable) : (fk.childOwner, fk.childTable)
                if d.item(owner: other.0, name: other.1) == nil {
                    let near = DiagramPoint(it.frame.x + it.frame.width + 40, it.frame.y)
                    d.addObject(owner: other.0, name: other.1, type: "TABLE", columns: try await source.columns(owner: other.0, name: other.1), at: near)
                }
            }
            d.addForeignKeyLinks(fks)
        }
    }

    /// Obiekty, od których zaznaczone zależą (Reference links).
    public static func addReferences(_ ids: Set<UUID>, to d: inout Diagram, source: any SchemaMetadataSource) async throws {
        for it in d.items where ids.contains(it.id) && it.kind == .object {
            for r in try await source.references(owner: it.owner, name: it.name) {
                let target: UUID
                if let existing = d.item(owner: r.owner, name: r.name) {
                    target = existing.id
                } else {
                    let cols = tableTypes.contains(r.type.rawValue) ? try await source.columns(owner: r.owner, name: r.name) : []
                    target = d.addObject(owner: r.owner, name: r.name, type: r.type.rawValue, columns: cols,
                                         at: DiagramPoint(it.frame.x, it.frame.y + it.frame.height + 40))
                }
                d.addReferenceLink(from: it.id, to: target)
            }
        }
    }

    /// Update from DB: kolumny i nowe klucze obce; zwraca obiekty, których w bazie już nie ma.
    public static func update(_ d: inout Diagram, source: any SchemaMetadataSource) async throws -> [String] {
        var columns: [String: [SchemaColumn]] = [:]
        var fks: [ForeignKey] = []
        for it in d.items where it.kind == .object {
            guard try await source.resolve("\"\(it.owner)\".\"\(it.name)\"") != nil else { continue }
            columns[it.objectKey] = tableTypes.contains(it.type) ? try await source.columns(owner: it.owner, name: it.name) : []
            if it.type == "TABLE" { fks += try await source.foreignKeys(owner: it.owner, table: it.name) }
        }
        let missing = d.update(columns: columns)
        d.addForeignKeyLinks(fks)
        return missing
    }
}

extension Workspace {
    /// Aktywne okno diagramu albo nowe.
    func diagramDocument(createIfNeeded: Bool) -> Document? {
        if let d = activeDocument, d.kind == .diagram { return d }
        return createIfNeeded ? newDocument(.diagram) : nil
    }

    /// Źródło metadanych dla okna (połączenie okna albo główne).
    public func schemaSource(for doc: Document?) async throws -> any SchemaMetadataSource {
        guard let m = metadata(for: doc.flatMap { effectiveConnection(of: $0) }) else { throw CommandError.notConnected }
        return try await m.schemaSource()
    }

    /// Źródło metadanych połączenia (Query Builder).
    public func schemaSource(connection: UUID?) async throws -> any SchemaMetadataSource {
        guard let m = metadata(for: connection) else { throw CommandError.notConnected }
        return try await m.schemaSource()
    }
}

/// Komendy diagramu i Query Buildera (PD-DIAG-001..003, PD-QB-001).
@MainActor
enum DiagramCommands {
    static func diagram(_ ws: Workspace) throws -> Document {
        guard let d = ws.activeDocument, d.kind == .diagram else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest diagramem")) }
        return d
    }

    static func isDiagram(_ ws: Workspace) -> Bool { ws.activeDocument?.kind == .diagram }

    static func edit(_ doc: Document, _ change: (inout Diagram) -> Void) {
        var d = doc.diagram
        change(&d)
        if d != doc.diagram {
            doc.diagram = d
            doc.isModified = true
        }
    }

    static func uiCommand(_ id: CommandID, _ title: String, summary: String, feature: String, params: [CommandParameter] = [],
                          effect: CommandEffect = .uiState,
                          _ body: @escaping @MainActor @Sendable (CommandContext, Document) async throws -> CommandResult) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: .tools, submenu: L10n.tr("Diagram"), parameters: params,
                                  agent: .none, effect: effect, summary: summary, feature: feature),
                validate: isDiagram) { ctx in try await body(ctx, try diagram(ctx.workspace)) }
    }

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "diagram.addObject", title: L10n.tr("Dodaj do diagramu"), category: .tools, submenu: L10n.tr("Diagram"),
                                      parameters: [CommandParameter("object", .string, L10n.tr("Obiekt: NAZWA albo SCHEMAT.NAZWA (domyślnie zaznaczony w Object Browserze)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Dodaje obiekt do aktywnego diagramu (albo nowego): tabele i widoki z kolumnami, linie kluczy obcych do obiektów na diagramie."),
                                      feature: "PD-DIAG-001"),
                    validate: { $0.selectedObject != nil || isDiagram($0) }) { ctx in
                let ws = ctx.workspace
                guard let doc = ws.diagramDocument(createIfNeeded: true) else { return .ok }
                let source = try await ws.schemaSource(for: doc)
                let object: DBObject
                if let name = ctx.arguments.string("object") {
                    guard let o = try await source.resolve(name) else { throw CommandError.notAvailable(L10n.tr("Nie znaleziono obiektu \(name)")) }
                    object = o
                } else if let o = ws.selectedObject {
                    object = o
                } else {
                    throw CommandError.missingArgument("object")
                }
                var d = doc.diagram
                let id = try await DiagramEditor.add(object, to: &d, source: source)
                edit(doc) { $0 = d }
                doc.diagramSelection = [id]
                return .ok
            },
            uiCommand("diagram.addRelated", L10n.tr("Dodaj powiązane tabele"),
                      summary: L10n.tr("Dodaje tabele powiązane kluczami obcymi z zaznaczonymi (nadrzędne i podrzędne) i linie relacji."),
                      feature: "PD-DIAG-001") { ctx, doc in
                var d = doc.diagram
                try await DiagramEditor.addRelated(doc.diagramSelection, to: &d, source: try await ctx.workspace.schemaSource(for: doc))
                edit(doc) { $0 = d }
                return .ok
            },
            uiCommand("diagram.addReferences", L10n.tr("Dodaj zależności"),
                      summary: L10n.tr("Dodaje obiekty, od których zaznaczone zależą (ALL_DEPENDENCIES), i linie referencji."),
                      feature: "PD-DIAG-001") { ctx, doc in
                var d = doc.diagram
                try await DiagramEditor.addReferences(doc.diagramSelection, to: &d, source: try await ctx.workspace.schemaSource(for: doc))
                edit(doc) { $0 = d }
                return .ok
            },
            uiCommand("diagram.showColumns", L10n.tr("Pokaż lub ukryj kolumny"),
                      summary: L10n.tr("Przełącza widoczność kolumn zaznaczonych obiektów."), feature: "PD-DIAG-001") { _, doc in
                let show = !(doc.diagram.items.first { doc.diagramSelection.contains($0.id) }?.showColumns ?? true)
                let selection = doc.diagramSelection
                edit(doc) { $0.setShowColumns(show, for: selection) }
                return .ok
            },
            uiCommand("diagram.addNote", L10n.tr("Dodaj notatkę"), summary: L10n.tr("Dodaje notatkę na diagramie."), feature: "PD-DIAG-002",
                      params: [CommandParameter("text", .string, L10n.tr("Tekst notatki"))]) { ctx, doc in
                var text = ctx.arguments.string("text") ?? ""
                if text.isEmpty, let ui = ctx.ui { text = await ui.askText(L10n.tr("Notatka"), message: L10n.tr("Tekst notatki"), defaultValue: "") ?? "" }
                guard !text.isEmpty else { return .ok }
                var id: UUID?
                edit(doc) { id = $0.addNote(text) }
                if let id { doc.diagramSelection = [id] }
                return .ok
            },
            uiCommand("diagram.addGroup", L10n.tr("Grupuj zaznaczone"), summary: L10n.tr("Obejmuje zaznaczone elementy ramką grupy z tytułem."),
                      feature: "PD-DIAG-002", params: [CommandParameter("title", .string, L10n.tr("Tytuł grupy"))]) { ctx, doc in
                var title = ctx.arguments.string("title") ?? ""
                if title.isEmpty, let ui = ctx.ui {
                    title = await ui.askText(L10n.tr("Grupa"), message: L10n.tr("Tytuł grupy"), defaultValue: L10n.tr("Grupa")) ?? ""
                }
                guard !title.isEmpty else { return .ok }
                let selection = doc.diagramSelection
                edit(doc) { _ = $0.addGroup(title, around: selection) }
                return .ok
            },
            uiCommand("diagram.delete", L10n.tr("Usuń z diagramu"), summary: L10n.tr("Usuwa zaznaczone elementy, linie i grupy z diagramu (nie z bazy)."),
                      feature: "PD-DIAG-002") { _, doc in
                let selection = doc.diagramSelection
                edit(doc) { $0.remove(selection) }
                doc.diagramSelection = []
                return .ok
            },
            uiCommand("diagram.zoom", L10n.tr("Powiększenie diagramu"), summary: L10n.tr("Ustawia powiększenie diagramu (10–200 %)."), feature: "PD-DIAG-002",
                      params: [CommandParameter("percent", .integer, required: true, L10n.tr("Powiększenie w procentach"))]) { ctx, doc in
                doc.diagram.setZoom(Double(ctx.arguments.int("percent") ?? 100) / 100)
                return .ok
            },
            uiCommand("diagram.toggleGrid", L10n.tr("Siatka diagramu"), summary: L10n.tr("Pokazuje lub ukrywa siatkę 8 px i dociąganie do niej."),
                      feature: "PD-DIAG-002") { _, doc in
                doc.diagram.showGrid.toggle()
                doc.diagram.snapToGrid = doc.diagram.showGrid
                return .ok
            },
            uiCommand("diagram.updateFromDB", L10n.tr("Aktualizuj z bazy"),
                      summary: L10n.tr("Odświeża kolumny i klucze obce obiektów diagramu ze słownika bazy; zgłasza obiekty, których już nie ma."),
                      feature: "PD-DIAG-003") { ctx, doc in
                var d = doc.diagram
                let missing = try await DiagramEditor.update(&d, source: try await ctx.workspace.schemaSource(for: doc))
                edit(doc) { $0 = d }
                return CommandResult(message: missing.isEmpty ? L10n.tr("Diagram zaktualizowany") : L10n.tr("Brak w bazie: \(missing.joined(separator: ", "))"))
            },
            uiCommand("diagram.export", L10n.tr("Eksportuj diagram jako obraz…"), summary: L10n.tr("Zapisuje diagram jako PNG albo PDF."), feature: "PD-DIAG-003",
                      params: [CommandParameter("format", .string, L10n.tr("Format"), allowed: ["png", "pdf"])], effect: .external) { ctx, doc in
                ctx.ui?.exportDiagram(doc, format: ctx.arguments.string("format") ?? "png")
                return .ok
            },
            uiCommand("diagram.copyImage", L10n.tr("Kopiuj diagram jako obraz"), summary: L10n.tr("Kopiuje obraz diagramu do schowka."),
                      feature: "PD-DIAG-003") { ctx, doc in
                ctx.ui?.copyDiagramImage(doc)
                return .ok
            },
            uiCommand("diagram.print", L10n.tr("Drukuj diagram…"), summary: L10n.tr("Drukuje diagram."), feature: "PD-DIAG-003", effect: .external) { ctx, doc in
                ctx.ui?.printDiagram(doc)
                return .ok
            },
            Command(CommandDescriptor(id: "tools.queryBuilder", title: L10n.tr("Query Builder…"), category: .tools,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Buduje SELECT z tabel, złączeń z kluczy obcych, pól, warunków i sortowania; wstawia zapytanie do edytora. Zaznaczony prosty SELECT otwiera do modyfikacji."),
                                      feature: "PD-QB-001"),
                    validate: { $0.sessions.mainConnectionID != nil || $0.activeDocument?.connectionID != nil }) { ctx in
                let ws = ctx.workspace
                var sql: String?
                if let d = ws.activeDocument, [.sql, .program, .test].contains(d.kind) {
                    let ns = d.text as NSString
                    let sel = d.selectedRange
                    if !sel.isEmpty, sel.upperBound <= ns.length { sql = ns.substring(with: NSRange(location: sel.lowerBound, length: sel.count)) }
                }
                ctx.ui?.showQueryBuilder(sql: sql, connectionID: ws.activeDocument.flatMap { ws.effectiveConnection(of: $0) } ?? ws.sessions.mainConnectionID)
                return .ok
            },
        ]
    }
}
