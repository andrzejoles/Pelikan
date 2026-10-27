import Foundation
import PelikanSQL
import PelikanDB

/// Komendy obiektu Object Browsera (UG 21.1): dane, DDL, opis, właściwości, edycja, rekompilacja, usunięcie.
/// Obiekt wskazuje argument `object` (`WŁAŚCICIEL.NAZWA`) i `type` (typ z ALL_OBJECTS); bez nich — zaznaczenie
/// w Object Browserze (`Workspace.selectedObject`).
public enum ObjectCommands {
    /// Obiekt wskazany nazwą i typem — bez połączenia (komendy z własnym argumentem `connection`).
    static let objectNameParams = [
        CommandParameter("object", .string, L10n.tr("Obiekt: WŁAŚCICIEL.NAZWA (domyślnie zaznaczony w Object Browserze)")),
        CommandParameter("type", .string, L10n.tr("Typ obiektu jak w ALL_OBJECTS, np. TABLE, PACKAGE BODY")),
    ]
    /// Obiekt i jego połączenie (domyślnie gałąź zaznaczonego obiektu, przy nazwie — aktywne okno, potem główne; D185).
    static let objectParams = objectNameParams + [CommandContext.toolConnectionParam]

    @MainActor
    static func target(_ ctx: CommandContext, connectionArgument: Bool = true) async throws -> (DBObject, MetadataProvider) {
        guard let m = ctx.workspace.metadata(for: try ctx.objectConnection(connectionArgument: connectionArgument)) else { throw CommandError.notConnected }
        if let spec = ctx.arguments.string("object") {
            let type = ctx.arguments.string("type").flatMap { DBObjectType(rawValue: $0.uppercased()) }
            // `pakiet.element` z edytora — gdy nie ma obiektu o tej nazwie, obiektem jest pakiet (pierwszy człon).
            var found = try await m.find(spec, type: type)
            if found == nil, type == nil, let first = spec.split(separator: ".").first, spec.contains(".") {
                found = try await m.find(String(first))
            }
            guard let o = found else {
                throw CommandError.invalidArgument("object", L10n.tr("nie znaleziono \(spec)"))
            }
            return (o, m)
        }
        guard let o = ctx.workspace.selectedObject else { throw CommandError.missingArgument("object") }
        return (o, m)
    }

    @MainActor
    static func hasSelection(_ ws: Workspace) -> Bool { ws.selectedObject != nil && ws.objectBrowserConnection != nil }

    /// Nowe okno SQL z tekstem (opcjonalnie wykonanym) — na połączeniu obiektu.
    @MainActor
    static func sqlWindow(_ ws: Workspace, title: String, text: String, execute: Bool, connection: UUID? = nil) async throws -> Document {
        let doc = ws.newDocument(.sql, text: text)
        ws.bind(doc, to: connection)
        doc.customTitle = title
        doc.isModified = false
        doc.selectedRange = 0..<0
        if execute { _ = try await SQLExecutor.execute(doc, scope: .alternate, in: ws) }
        return doc
    }

    /// Polecenie (re)kompilacji obiektu.
    static func compileStatement(_ o: DBObject) -> String? {
        switch o.type {
        case .package: "ALTER PACKAGE \(o.qualifiedName) COMPILE"
        case .packageBody: "ALTER PACKAGE \(o.qualifiedName) COMPILE BODY"
        case .type: "ALTER TYPE \(o.qualifiedName) COMPILE"
        case .typeBody: "ALTER TYPE \(o.qualifiedName) COMPILE BODY"
        case .function, .procedure, .trigger, .view, .materializedView, .synonym, .library, .mleModule:
            "ALTER \(o.type.rawValue) \(o.qualifiedName) COMPILE"
        case .javaSource: "ALTER JAVA SOURCE \(o.qualifiedName) COMPILE"
        default: nil
        }
    }

    /// Kompilacja z informacją debugowania (PD-DBG-011): ALTER … COMPILE DEBUG [BODY] dla jednostek PL/SQL.
    static func debugCompileStatement(_ o: DBObject) -> String? {
        guard [.package, .packageBody, .type, .typeBody, .function, .procedure, .trigger].contains(o.type),
              let s = compileStatement(o) else { return nil }
        if s.hasSuffix(" COMPILE BODY") { return String(s.dropLast(" COMPILE BODY".count)) + " COMPILE DEBUG BODY" }
        return s + " DEBUG"
    }

    @MainActor
    public static var all: [Command] {
        [
            Command(CommandDescriptor(id: "ob.queryData", title: L10n.tr("Pokaż dane"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera okno SQL z zapytaniem o dane tabeli lub widoku i wykonuje je."), feature: "PD-OB-017"),
                    validate: { ws in ws.selectedObject.map { $0.type.hasData } ?? false }) { ctx in
                let (o, m) = try await target(ctx)
                m.touch(o)
                _ = try await sqlWindow(ctx.workspace, title: o.name, text: "select * from \(o.qualifiedName)", execute: true, connection: m.connectionID)
                return .ok
            },
            Command(CommandDescriptor(id: "ob.editData", title: L10n.tr("Edytuj dane"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera dane tabeli z ROWID w trybie edycji (UG 21.1 Edit data)."), feature: "PD-OB-017"),
                    validate: { ws in ws.selectedObject.map { $0.type == .table } ?? false }) { ctx in
                let (o, m) = try await target(ctx)
                m.touch(o)
                let doc = try await sqlWindow(ctx.workspace, title: o.name, text: "select t.*, t.rowid from \(o.qualifiedName) t", execute: true, connection: m.connectionID)
                if let grid = doc.results.first?.grid { try await grid.beginEditing() }
                return .ok
            },
            Command(CommandDescriptor(id: "ob.ddl", title: L10n.tr("DDL"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .read, effect: .none,
                                      summary: L10n.tr("Skrypt DDL obiektu (DBMS_METADATA) w nowym oknie SQL."), feature: "PD-OB-015"),
                    validate: hasSelection) { ctx in
                let (o, m) = try await target(ctx)
                let ddl = try await m.ddl(of: o)
                if !ctx.invoker.isAgent { _ = try await sqlWindow(ctx.workspace, title: "\(o.name).sql", text: ddl, execute: false, connection: m.connectionID) }
                return CommandResult(message: ddl)
            },
            Command(CommandDescriptor(id: "ob.describe", title: L10n.tr("Opis"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .read, effect: .none,
                                      summary: L10n.tr("Kolumny, parametry, elementy pakietu albo atrybuty typu (UG 21.1 Describe)."), feature: "PD-OB-013"),
                    validate: hasSelection) { ctx in
                let (o, m) = try await target(ctx)
                let items = try await m.children(of: o).filter { [.column, .subprogram, .attribute].contains($0.kind) }
                if !ctx.invoker.isAgent {
                    ctx.workspace.ui?.showObjectInfo(title: L10n.tr("Opis: \(o.qualifiedName)"),
                                                     columns: [L10n.tr("Nazwa"), L10n.tr("Typ / szczegóły")],
                                                     rows: items.map { [$0.name, $0.detail] })
                }
                return CommandResult(message: items.map { "\($0.name) \($0.detail)" }.joined(separator: "\n"),
                                     value: .array(items.map { .object(["name": .string($0.name), "detail": .string($0.detail), "kind": .string($0.kind.rawValue)]) }))
            },
            Command(CommandDescriptor(id: "ob.properties", title: L10n.tr("Właściwości"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .read, effect: .none,
                                      summary: L10n.tr("Właściwości obiektu ze słownika danych (UG 21.1 Properties)."), feature: "PD-OB-012"),
                    validate: hasSelection) { ctx in
                let (o, m) = try await target(ctx)
                let props = try await m.properties(of: o)
                if !ctx.invoker.isAgent {
                    ctx.workspace.ui?.showObjectInfo(title: L10n.tr("Właściwości: \(o.qualifiedName)"), columns: [L10n.tr("Właściwość"), L10n.tr("Wartość")],
                                                     rows: props.map { [$0.0, $0.1] })
                }
                return CommandResult(message: props.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
            },
            Command(CommandDescriptor(id: "ob.edit", title: L10n.tr("Edytuj"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .none, effect: .uiState,
                                      summary: L10n.tr("Otwiera program w oknie programu; tabelę, sekwencję, synonim, indeks, użytkownika i rolę w edytorze; pozostałe obiekty jako DDL."), feature: "PD-OB-014"),
                    validate: hasSelection) { ctx in
                let (picked, m) = try await target(ctx)
                m.touch(picked)
                // Ciało pakietu/typu otwierane razem ze specyfikacją — jedno okno, karta ciała aktywna. Bez źródła
                // specyfikacji (osierocone ciało, brak uprawnień do specyfikacji) — samo ciało, jak przed D181.
                var openBody = picked.type == .packageBody || picked.type == .typeBody
                var o = picked
                var specSource: String?
                if openBody {
                    let spec = DBObject(owner: picked.owner, name: picked.name, type: picked.type == .packageBody ? .package : .type)
                    specSource = try? await m.source(of: spec)
                    if specSource != nil { o = spec } else { openBody = false }
                }
                if o.type.isProgram {
                    // Specyfikacja i ciało pakietu/typu w jednym oknie (karty jednostek — Program Window).
                    var text: String
                    if let specSource { text = specSource } else { text = try await m.source(of: o) }
                    text += "\n/\n"
                    // Ciało jest dołączane tylko, gdy istnieje — typ bez metod, kolekcja i pakiet bez ciała mają jedną kartę.
                    if o.type == .package || o.type == .type {
                        let bodyType: DBObjectType = o.type == .package ? .packageBody : .typeBody
                        if let body = try? await m.source(of: DBObject(owner: o.owner, name: o.name, type: bodyType)) { text += "\n" + body + "\n/\n" }
                    }
                    if ctx.workspace.settings.beautifier.afterLoad, let f = try? Beautifier.format(text, options: ctx.workspace.settings.beautifier) {
                        text = f
                    }
                    let doc = ctx.workspace.newDocument(.program, text: text)
                    ctx.workspace.bind(doc, to: m.connectionID)
                    doc.customTitle = o.name.lowercased() + "." + Self.fileExtension(o.type)
                    doc.isModified = false
                    // Ciało wskazane w przeglądarce: kursor na początku drugiej jednostki (karta ciała); po formatowaniu
                    // granicą nadal jest „/” sam w linii.
                    var caret = 0
                    if openBody, let r = doc.text.range(of: "\n/\n") {
                        caret = doc.text.utf16.distance(from: doc.text.startIndex, to: r.upperBound)
                        while caret < (doc.text as NSString).length, (doc.text as NSString).character(at: caret) == 0x0A { caret += 1 }
                        if caret >= (doc.text as NSString).length { caret = 0 }
                    }
                    doc.selectedRange = caret..<caret
                    // Znaczniki czasu (PD-PROG-011): późniejsza zmiana obiektu w bazie przez kogoś innego jest wykrywana.
                    var objects = [o]
                    if o.type == .package { objects.append(DBObject(owner: o.owner, name: o.name, type: .packageBody)) }
                    if o.type == .type { objects.append(DBObject(owner: o.owner, name: o.name, type: .typeBody)) }
                    if let s = try? await m.session() { doc.objectTimestamps = (try? await ObjectAdmin.lastDDLTimes(objects, in: s)) ?? [:] }
                } else if let kind = Self.simpleEditorKind(o.type), ctx.invoker == .user, ctx.ui != nil {
                    // Sekwencja, synonim, indeks, użytkownik, rola: prosty edytor (UG 9.2–9.11).
                    let e = try await SimpleObjectEditor.load(kind, owner: o.owner, name: o.name, metadata: m)
                    ctx.ui?.showObjectEditor(e, connectionID: m.connectionID)
                } else if o.type == .table, ctx.invoker == .user, ctx.ui != nil {
                    // Tabela: edytor definicji (UG 9.1) zamiast DDL.
                    let d = try await TableDDL.load(owner: o.owner, name: o.name, metadata: m)
                    ctx.ui?.showTableEditor(d, original: d, connectionID: m.connectionID)
                } else {
                    let ddl = try await m.ddl(of: o)
                    _ = try await sqlWindow(ctx.workspace, title: "\(o.name).sql", text: ddl, execute: false, connection: m.connectionID)
                }
                return .ok
            },
            Command(CommandDescriptor(id: "ob.recompile", title: L10n.tr("Rekompiluj"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Kompiluje obiekt ponownie (ALTER … COMPILE) w sesji kompilacji."), feature: "PD-OB-009"),
                    validate: { ws in ws.selectedObject.flatMap { compileStatement($0) } != nil }) { ctx in
                let (o, m) = try await target(ctx)
                guard let sql = compileStatement(o) else { throw CommandError.notAvailable(L10n.tr("Tego obiektu nie da się kompilować")) }
                // Potwierdzanie rekompilacji (Preferencje › Object Browser, PD-OB-025).
                if ctx.workspace.settings.confirmRecompile, ctx.invoker == .user, let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Rekompilować \(o.name)?"), message: sql, buttons: [L10n.tr("Rekompiluj"), L10n.tr("Anuluj")]) == 0 else {
                        throw CommandError.cancelledByUser
                    }
                }
                try await ctx.workspace.guardModification([sql], connectionID: m.connectionID)
                let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: m.connectionID))
                // Błąd kompilacji przychodzi jako ostrzeżenie ORA-24344 (status niżej); brak uprawnień, blokada (ORA-04021)
                // itp. — wyjątkiem.
                _ = try await s.execute(sql)
                m.refresh(o)
                let status = try await s.scalar("select status from all_objects where owner = :o and object_name = :n and object_type = :t",
                                                binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name)),
                                                        BindVariable(name: "t", value: .text(o.type.rawValue))])
                return CommandResult(message: status == "VALID" ? L10n.tr("Skompilowano: \(o.qualifiedName)") : L10n.tr("\(o.qualifiedName) ma błędy kompilacji"),
                                     value: .string(status ?? ""))
            },
            Command(CommandDescriptor(id: "ob.addDebugInfo", title: L10n.tr("Dodaj informację debugowania"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Kompiluje jednostkę PL/SQL z informacją debugowania (ALTER … COMPILE DEBUG), także ciało pakietu/typu."),
                                      feature: "PD-DBG-011"),
                    validate: { ws in ws.selectedObject.flatMap { debugCompileStatement($0) } != nil }) { ctx in
                let (o, m) = try await target(ctx)
                var objs = [o]
                if o.type == .package { objs.append(DBObject(owner: o.owner, name: o.name, type: .packageBody)) }
                if o.type == .type { objs.append(DBObject(owner: o.owner, name: o.name, type: .typeBody)) }
                let sql = objs.compactMap(debugCompileStatement)
                guard !sql.isEmpty else { throw CommandError.notAvailable(L10n.tr("Ten obiekt nie jest jednostką PL/SQL")) }
                try await ctx.workspace.guardModification(sql, connectionID: m.connectionID)
                let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: m.connectionID))
                // Jednostka: błąd kompilacji to ostrzeżenie ORA-24344, inne błędy zgłaszane; ciało pakietu/typu — może nie istnieć.
                _ = try await s.execute(sql[0])
                for q in sql.dropFirst() { _ = try? await s.execute(q) }
                m.refresh(o)
                return CommandResult(message: L10n.tr("Dodano informację debugowania: \(o.qualifiedName)"))
            },
            Command(CommandDescriptor(id: "ob.drop", title: L10n.tr("Usuń obiekt…"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .approval, effect: .modifiesDatabase,
                                      summary: L10n.tr("Usuwa obiekt z bazy (DROP) po potwierdzeniu."), feature: "PD-OB-016"),
                    validate: { ws in ws.selectedObject.map { ![.user, .role, .profile].contains($0.type) } ?? false }) { ctx in
                let (o, m) = try await target(ctx)
                let sql = try MultiObjectCommands.dropStatement(o, cascadeConstraints: false)
                try await ctx.workspace.guardModification([sql], connectionID: m.connectionID)
                let choice = await ctx.ui?.ask(L10n.tr("Usunąć \(o.type.rawValue) \(o.qualifiedName)?"), message: L10n.tr("Tej operacji nie da się cofnąć (poza koszem dla tabel)."),
                                               buttons: [L10n.tr("Usuń"), L10n.tr("Anuluj")])
                guard choice == 0 else { throw CommandError.cancelledByUser }
                let s = try await ctx.workspace.sessions.session(ctx.workspace.sessions.compileKey(connection: m.connectionID))
                _ = try await s.execute(sql)
                if ctx.workspace.selectedObject == o { ctx.workspace.selectedObject = nil }
                m.refresh()
                return CommandResult(message: L10n.tr("Usunięto \(o.qualifiedName)"))
            },
            Command(CommandDescriptor(id: "ob.copyName", title: L10n.tr("Kopiuj nazwę"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: objectParams, agent: .none, effect: .none,
                                      summary: L10n.tr("Kopiuje nazwę obiektu (z właścicielem, gdy inny niż bieżący schemat)."), feature: "PD-OB-011"),
                    validate: hasSelection) { ctx in
                let (o, m) = try await target(ctx)
                let schema = (try? await m.currentSchema()) ?? ""
                let name = o.owner == schema ? ResultExporter.displayIdentifier(o.name) : ResultExporter.displayQualified(owner: o.owner, name: o.name)
                ctx.workspace.ui?.copyToClipboard(name, html: nil)
                return CommandResult(message: name)
            },
            Command(CommandDescriptor(id: "ob.refresh", title: L10n.tr("Odśwież Object Browser"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: [CommandContext.toolConnectionParam],
                                      agent: .full, effect: .uiState,
                                      summary: L10n.tr("Czyści pamięć podręczną słownika i przeładowuje drzewo (wszystkie otwarte połączenia albo wskazane)."),
                                      feature: "PD-OB-004"),
                    validate: { !$0.sessions.openConnections.isEmpty }) { ctx in
                if ctx.arguments.string("connection") != nil {
                    ctx.workspace.metadata(for: try ctx.toolConnection())?.refresh()
                } else {
                    ctx.workspace.refreshOpenMetadata()
                }
                return .ok
            },
        ]
    }

    static func simpleEditorKind(_ t: DBObjectType) -> SimpleObjectEditor.Kind? {
        switch t {
        case .sequence: .sequence
        case .synonym: .synonym
        case .index: .index
        case .user: .user
        case .role: .role
        case .library: .library
        case .directory: .directory
        case .job: .job
        case .queue: .queue
        case .profile: .profile
        case .databaseLink: .databaseLink
        default: nil
        }
    }

    static func fileExtension(_ t: DBObjectType) -> String {
        switch t {
        case .function: "fnc"
        case .procedure: "prc"
        case .package, .packageBody: "pck"
        case .type, .typeBody: "typ"
        case .trigger: "trg"
        case .javaSource: "jsp"
        case .mleModule: "mle"
        default: "sql"
        }
    }
}
