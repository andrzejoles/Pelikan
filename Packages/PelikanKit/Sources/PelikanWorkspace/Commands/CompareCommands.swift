import Foundation
import PelikanDB
import PelikanSQL

/// Porównania (UG 4.5, UG 21.1 Compare, UG 26): okno programu z bazą lub plikiem, obiekt z oknem, dwa pliki, dwa teksty.
enum CompareCommands {
    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "prog.compareWithDatabase", title: L10n.tr("Porównaj ze źródłem w bazie"), category: .file, submenu: L10n.tr("Porównaj"),
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Porównuje jednostki okna programu ze źródłem tych obiektów w bazie (ALL_SOURCE)."), feature: "PD-PROG-008"),
                    validate: { ws in ws.activeDocument.map { $0.kind == .program && ws.effectiveConnection(of: $0) != nil } ?? false }) { ctx in
                guard let doc = ctx.workspace.activeDocument, doc.kind == .program else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest oknem programu")) }
                guard let m = ctx.workspace.metadata(for: ctx.workspace.effectiveConnection(of: doc)) else { throw CommandError.notConnected }
                let db = try await databaseText(of: doc.text, metadata: m)
                return show(ctx, left: db, right: doc.text, leftTitle: L10n.tr("Baza danych"), rightTitle: doc.title) {
                    (try await databaseText(of: doc.text, metadata: m), doc.text)
                }
            },
            Command(CommandDescriptor(id: "prog.compareWithFile", title: L10n.tr("Porównaj z plikiem…"), category: .file, submenu: L10n.tr("Porównaj"),
                                      parameters: [CommandParameter("file", .string, L10n.tr("Ścieżka pliku (bez — okno wyboru)"))],
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Porównuje tekst aktywnego okna z plikiem."), feature: "PD-PROG-008"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                guard let doc = BuiltinCommands.editable(ctx.workspace) else { return .ok }
                guard let url = try await file(ctx, "file") else { throw CommandError.cancelledByUser }
                return show(ctx, left: try read(url), right: doc.text, leftTitle: url.lastPathComponent, rightTitle: doc.title) {
                    (try read(url), doc.text)
                }
            },
            Command(CommandDescriptor(id: "ob.compare", title: L10n.tr("Porównaj z aktywnym oknem"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams, agent: .read, effect: .none,
                                      summary: L10n.tr("Porównuje źródło (albo DDL) obiektu bazy z tekstem aktywnego okna."), feature: "PD-OB-022"),
                    validate: { ws in ws.selectedObject != nil && BuiltinCommands.editable(ws) != nil }) { ctx in
                let (o, m) = try await ObjectCommands.target(ctx)
                guard let doc = BuiltinCommands.editable(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak aktywnego okna z tekstem")) }
                let text = try await objectText(o, metadata: m)
                return show(ctx, left: text, right: doc.text, leftTitle: "\(o.owner).\(o.name)", rightTitle: doc.title) {
                    (try await objectText(o, metadata: m), doc.text)
                }
            },
            Command(CommandDescriptor(id: "prog.compareWithConnection", title: L10n.tr("Porównaj z obiektami w innej bazie…"), category: .file,
                                      submenu: L10n.tr("Porównaj"),
                                      parameters: [CommandParameter("connection", .string, L10n.tr("Nazwa połączenia (bez — wybór z listy)")),
                                                   CommandParameter("schema", .string, L10n.tr("Schemat w tamtej bazie (domyślnie z nagłówków albo bieżący)"))],
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Porównuje jednostki okna programu ze źródłem obiektów o tych nazwach w bazie innego połączenia."),
                                      feature: "PD-PROG-008"),
                    validate: { ws in ws.activeDocument?.kind == .program && ws.connections.connections.count > 1 }) { ctx in
                guard let doc = ctx.workspace.activeDocument, doc.kind == .program else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest oknem programu")) }
                let (other, name) = try await otherConnection(ctx, excluding: ctx.workspace.effectiveConnection(of: doc))
                guard let m = ctx.workspace.metadata(for: other) else { throw CommandError.notConnected }
                let schema = ctx.arguments.string("schema")
                let db = try await databaseText(of: doc.text, metadata: m, schema: schema)
                return show(ctx, left: db, right: doc.text, leftTitle: name, rightTitle: doc.title) {
                    (try await databaseText(of: doc.text, metadata: m, schema: schema), doc.text)
                }
            },
            Command(CommandDescriptor(id: "ob.compareWithConnection", title: L10n.tr("Porównaj z obiektem w innej bazie…"), category: .tools,
                                      submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectNameParams + [
                                        CommandParameter("connection", .string, L10n.tr("Nazwa połączenia (bez — wybór z listy)")),
                                        CommandParameter("schema", .string, L10n.tr("Schemat w tamtej bazie (domyślnie ten sam)")),
                                      ],
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Porównuje źródło (albo DDL) obiektu z obiektem o tej samej nazwie w bazie innego połączenia."),
                                      feature: "PD-OB-022"),
                    validate: { ws in ws.selectedObject != nil && ws.connections.connections.count > 1 }) { ctx in
                // `connection` to tu druga baza — obiekt z gałęzi drzewa, okna albo połączenia głównego.
                let (o, m) = try await ObjectCommands.target(ctx, connectionArgument: false)
                let (other, name) = try await otherConnection(ctx, excluding: m.connectionID)
                guard let om = ctx.workspace.metadata(for: other) else { throw CommandError.notConnected }
                let owner = ctx.arguments.string("schema")?.uppercased() ?? o.owner
                let remote = DBObject(owner: owner, name: o.name, type: o.type)
                let load: @MainActor () async throws -> (String, String) = {
                    let r = (try? await objectText(remote, metadata: om)) ?? ""
                    return (try await objectText(o, metadata: m), r)
                }
                let (l, r) = try await load()
                return show(ctx, left: l, right: r, leftTitle: "\(o.owner).\(o.name)", rightTitle: "\(name): \(owner).\(o.name)", reload: load)
            },
            Command(CommandDescriptor(id: "tools.compareFiles", title: L10n.tr("Porównaj pliki…"), category: .tools,
                                      parameters: [CommandParameter("left", .string, L10n.tr("Pierwszy plik")), CommandParameter("right", .string, L10n.tr("Drugi plik"))],
                                      agent: .none, effect: .none, summary: L10n.tr("Porównuje dwa pliki w przeglądarce różnic."), feature: "PD-DIFF-001")) { ctx in
                guard let l = try await file(ctx, "left"), let r = try await file(ctx, "right") else { throw CommandError.cancelledByUser }
                return show(ctx, left: try read(l), right: try read(r), leftTitle: l.lastPathComponent, rightTitle: r.lastPathComponent) {
                    (try read(l), try read(r))
                }
            },
            Command(CommandDescriptor(id: "tools.compareTexts", title: L10n.tr("Porównaj teksty"), category: .tools,
                                      parameters: [
                                          CommandParameter("left", .string, required: true, L10n.tr("Tekst lewy")),
                                          CommandParameter("right", .string, required: true, L10n.tr("Tekst prawy")),
                                          CommandParameter("ignoreCase", .boolean, L10n.tr("Ignoruj wielkość liter")),
                                          CommandParameter("ignoreWhitespace", .boolean, L10n.tr("Ignoruj białe znaki")),
                                          CommandParameter("ignoreComments", .boolean, L10n.tr("Ignoruj komentarze")),
                                      ],
                                      agent: .read, effect: .none, summary: L10n.tr("Różnica dwóch tekstów w formacie unified."), inMenu: false,
                                      feature: "PD-DIFF-001")) { ctx in
                let o = DiffOptions(ignoreCase: ctx.arguments.bool("ignoreCase") ?? false, ignoreWhitespace: ctx.arguments.bool("ignoreWhitespace") ?? false,
                                    ignoreComments: ctx.arguments.bool("ignoreComments") ?? false)
                let u = TextDiff.unified(ctx.arguments.string("left") ?? "", ctx.arguments.string("right") ?? "", options: o)
                return CommandResult(message: u.isEmpty ? L10n.tr("Brak różnic") : u, value: .string(u))
            },
        ]
    }

    /// Źródło (z ciałem pakietu/typu) albo DDL obiektu do porównania.
    @MainActor
    static func objectText(_ o: DBObject, metadata m: MetadataProvider) async throws -> String {
        var text = o.type.isProgram ? try await m.source(of: o) + "\n/\n" : try await m.ddl(of: o)
        if o.type == .package || o.type == .type {
            let body = DBObject(owner: o.owner, name: o.name, type: o.type == .package ? .packageBody : .typeBody)
            if let b = try? await m.source(of: body) { text += "\n" + b + "\n/\n" }
        }
        return text
    }

    /// Użytkownik: przeglądarka różnic (z Reload — ponownym wczytaniem obu stron); agent: różnica unified w wyniku.
    @MainActor
    static func show(_ ctx: CommandContext, left: String, right: String, leftTitle: String, rightTitle: String,
                     reload: DiffReload? = nil) -> CommandResult {
        if ctx.invoker == .user {
            if let tool = ctx.workspace.settings.externalDiff, !tool.program.trimmingCharacters(in: .whitespaces).isEmpty {
                do {
                    try ctx.workspace.openExternalDiff(tool, left: left, right: right, leftTitle: leftTitle, rightTitle: rightTitle)
                } catch {
                    ctx.ui?.showError(error.localizedDescription)
                }
            } else {
                ctx.ui?.showDiff(left: left, right: right, leftTitle: leftTitle, rightTitle: rightTitle, reload: reload)
            }
        }
        let u = TextDiff.unified(left, right, leftName: leftTitle, rightName: rightTitle)
        return CommandResult(message: u.isEmpty ? L10n.tr("Brak różnic") : L10n.tr("Różnice: \(TextDiff.rows(left, right).filter { $0.kind != .same }.count) linii"),
                             value: .string(u))
    }

    /// Źródła w bazie dla jednostek tekstu okna programu, w tej samej kolejności (brak obiektu — pusty fragment).
    @MainActor
    static func databaseText(of text: String, metadata m: MetadataProvider, schema override: String? = nil) async throws -> String {
        let schema = try await m.currentSchema()
        var out: [String] = []
        for u in ProgramCompiler.units(in: text) {
            let o = DBObject(owner: override?.uppercased() ?? u.owner ?? schema, name: u.name, type: u.type)
            if let src = try? await m.source(of: o), !src.isEmpty { out.append(src + "\n/") }
        }
        // Układ jak przy otwarciu z bazy (ob.edit): jednostki rozdzielone pustą linią.
        return out.joined(separator: "\n\n") + "\n"
    }

    /// Drugie połączenie: z argumentu `connection` (nazwa) albo wybór z listy pozostałych połączeń.
    @MainActor
    static func otherConnection(_ ctx: CommandContext, excluding current: UUID?) async throws -> (UUID, String) {
        let ws = ctx.workspace
        if let n = ctx.arguments.string("connection") {
            guard let id = ws.connectionID(named: n) else { throw CommandError.invalidArgument("connection", L10n.tr("Nie ma połączenia „\(n)”")) }
            return (id, ws.connections.connection(id)?.displayName ?? n)
        }
        let others = ws.connections.connections.filter { $0.id != current }
        guard !others.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak innego połączenia do porównania")) }
        guard let ui = ctx.ui, let chosen = await ui.chooseValue(L10n.tr("Porównaj z połączeniem"), values: others.map(\.displayName)),
              let def = others.first(where: { $0.displayName == chosen }) else { throw CommandError.cancelledByUser }
        return (def.id, def.displayName)
    }

    @MainActor
    static func file(_ ctx: CommandContext, _ key: String) async throws -> URL? {
        if let p = ctx.arguments.string(key) { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        return await ctx.ui?.chooseFilesToOpen().first
    }

    static func read(_ url: URL) throws -> String { TextFileCodec.decode(try Data(contentsOf: url)).text }
}
