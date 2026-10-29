import Foundation
import PelikanDB
import PelikanSQL

/// Obiekt bazy w projekcie (schemat, nazwa, typ).
public struct ProjectObject: Sendable, Codable, Hashable {
    public var owner: String
    public var name: String
    public var type: DBObjectType
    public init(_ o: DBObject) { owner = o.owner; name = o.name; type = o.type }
    public var dbObject: DBObject { DBObject(owner: owner, name: name, type: type) }
}

/// Element projektu (UG 14): plik (ścieżka względna wobec pliku projektu), obiekt bazy albo notatka; opcjonalna grupa.
public struct ProjectItem: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable { case file, object, note }
    public var id = UUID()
    public var kind: Kind
    public var path: String?
    public var object: ProjectObject?
    public var note: String?
    public var group: String?

    public static func file(_ path: String, group: String? = nil) -> ProjectItem { ProjectItem(kind: .file, path: path, group: group) }
    public static func object(_ o: DBObject, group: String? = nil) -> ProjectItem { ProjectItem(kind: .object, object: ProjectObject(o), group: group) }
    public static func note(_ text: String, group: String? = nil) -> ProjectItem { ProjectItem(kind: .note, note: text, group: group) }

    public var title: String {
        switch kind {
        case .file: (path.map { ($0 as NSString).lastPathComponent }) ?? ""
        case .object: object.map { "\($0.type.rawValue) \($0.dbObject.qualifiedName)" } ?? ""
        case .note: String((note ?? "").prefix(60))
        }
    }
}

/// Opcje projektu (UG 14.2): połączenie (alias), zatrzymanie po pierwszym błędzie, formatowanie przy budowaniu.
public struct ProjectOptions: Sendable, Codable, Hashable {
    public var connection: String?
    public var haltOnFirstError = true
    public var beautifyOnBuild = false
    /// Kodowanie plików projektu bez BOM (np. „ISO-8859-2” dla źródeł Pro*C); nil — wykrywanie przy otwarciu.
    public var encoding: String?
    public init() {}

    /// Kodowanie z `encoding` (nil — brak albo nieznana nazwa).
    public var preferredEncoding: String.Encoding? { encoding.flatMap(TextFileCodec.encoding(named:)) }
}

/// Okno pulpitu projektu (plik względny i rodzaj okna).
public struct ProjectWindow: Sendable, Codable, Hashable {
    public var path: String
    public var kind: DocumentKind
}

/// Projekt (plik `.prj`, JSON).
public struct Project: Sendable, Codable, Hashable {
    public var format = "pelikan-project"
    public var version = 1
    public var name: String
    public var items: [ProjectItem] = []
    public var options = ProjectOptions()
    public var desktop: [ProjectWindow] = []
    /// Ostatnie udane zbudowanie elementu (Make pomija pliki niezmienione od tej chwili).
    public var lastBuild: [UUID: Date] = [:]
    public init(name: String) { self.name = name }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> Project {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let p = try d.decode(Project.self, from: data)
        guard p.format == "pelikan-project" else { throw CommandError.notAvailable(L10n.tr("To nie jest plik projektu Pelikana")) }
        return p
    }

    public var groups: [String] { Array(Set(items.compactMap(\.group))).sorted() }
}

/// Wynik budowania elementu.
public struct ProjectBuildResult: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable { case compiled, skipped, failed }
    public var id: UUID
    public var title: String
    public var status: Status
    public var messages: [String]
}

/// Trafienie wyszukiwania w projekcie.
public struct ProjectMatch: Sendable, Hashable, Identifiable {
    public var id: String { "\(item):\(line)" }
    public var item: UUID
    public var title: String
    public var line: Int
    public var text: String
}

/// Stan Git projektu (PD-VCS-001): gałąź, ahead/behind i stan każdego pliku projektu.
public struct ProjectGitStatus: Sendable, Hashable {
    public var branch: String?
    public var ahead: Int
    public var behind: Int
    public var items: [UUID: GitFileState]
}

@MainActor
public enum ProjectEngine {
    /// Stan Git plików projektu (repozytorium wykrywane z katalogu projektu; poza repozytorium — nil).
    public nonisolated static func gitStatus(of project: Project, projectURL: URL) -> ProjectGitStatus? {
        guard let repo = GitRepository.discover(for: projectURL.deletingLastPathComponent()), let status = try? repo.status() else { return nil }
        var items: [UUID: GitFileState] = [:]
        for item in project.items where item.kind == .file {
            if let url = url(of: item, projectURL: projectURL), let s = status.state(of: url) { items[item.id] = s }
        }
        return ProjectGitStatus(branch: status.branch, ahead: status.ahead, behind: status.behind, items: items)
    }

    public nonisolated static func url(of item: ProjectItem, projectURL: URL) -> URL? {
        guard let p = item.path else { return nil }
        return p.hasPrefix("/") ? URL(fileURLWithPath: p) : projectURL.deletingLastPathComponent().appendingPathComponent(p)
    }

    /// Ścieżka względna wobec katalogu projektu (gdy plik jest w nim albo poniżej).
    public static func relativePath(_ url: URL, projectURL: URL) -> String {
        let base = projectURL.deletingLastPathComponent().standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    /// Połączenie projektu: z opcji projektu (alias agenta albo nazwa), bez niej — główne.
    public static func connection(_ project: Project, in ws: Workspace) throws -> ConnectionDefinition {
        if let alias = project.options.connection, let def = ws.connections.connections.first(where: { $0.agentAlias == alias || $0.displayName == alias }) {
            return def
        }
        guard let id = ws.sessions.mainConnectionID, let def = ws.connections.connection(id) else { throw CommandError.notConnected }
        return def
    }

    /// Build (wszystko) albo Make (tylko pliki zmienione od ostatniego budowania i obiekty niepoprawne) — UG 14.6.
    public static func build(_ project: inout Project, projectURL: URL, make: Bool, in ws: Workspace) async throws -> [ProjectBuildResult] {
        let def = try connection(project, in: ws)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        // Ostrzeżenia i parametry kompilatora z Preferencji — jak kompilacja okna programu (PD-PROG-013); błąd
        // parametru nie zatrzymuje budowania.
        for statement in ws.settings.compiler.statements(warnings: ws.settings.plsqlWarnings) {
            _ = try? await s.execute(statement)
        }
        var results: [ProjectBuildResult] = []
        for item in project.items where item.kind != .note {
            var statements: [String] = []
            var compiled: [DBObject] = []
            // Informacje bez wpływu na wynik (pominięte polecenia).
            var notes: [String] = []
            switch item.kind {
            case .file:
                guard let url = url(of: item, projectURL: projectURL) else { continue }
                let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
                if make, let last = project.lastBuild[item.id], modified <= last {
                    results.append(ProjectBuildResult(id: item.id, title: item.title, status: .skipped, messages: []))
                    continue
                }
                // Kodowanie projektu (D55), BOM i CRLF — jak przy otwieraniu pliku.
                var text = TextFileCodec.decode(try Data(contentsOf: url), preferred: project.options.preferredEncoding).text
                if project.options.beautifyOnBuild, let f = try? Beautifier.format(text, options: ws.settings.beautifier) { text = f }
                let units = ProgramCompiler.units(in: text)
                statements = units.map(\.text)
                // Build kompiluje jednostki programów; pozostałe polecenia pliku (CREATE TABLE, GRANT, SET…) nie są
                // wykonywane — informacja zamiast cichego pominięcia.
                let other = ScriptSplitter.split(text).count { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } - units.count
                if other > 0 { notes.append(L10n.tr("Pominięto poleceń innych niż jednostki programów: \(other) (budowanie kompiluje tylko jednostki PL/SQL).")) }
                let schema = s.info.currentSchema
                compiled = units.map { DBObject(owner: $0.owner ?? schema, name: $0.name, type: $0.type) }
            case .object:
                guard let o = item.object?.dbObject else { continue }
                if make, try await s.scalar("select status from all_objects where owner = :o and object_name = :n and object_type = :t",
                                            binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name)),
                                                    BindVariable(name: "t", value: .text(o.type.rawValue))]) == "VALID" {
                    results.append(ProjectBuildResult(id: item.id, title: item.title, status: .skipped, messages: []))
                    continue
                }
                let q = "\"\(o.owner)\".\"\(o.name)\""
                statements = [o.type == .packageBody ? "alter package \(q) compile body" : o.type == .typeBody ? "alter type \(q) compile body"
                              : "alter \(o.type.rawValue.lowercased()) \(q) compile"]
                compiled = [o]
            case .note:
                continue
            }
            try await ws.guardModification(statements, connectionID: def.id)
            var messages: [String] = []
            for st in statements {
                do { _ = try await s.execute(st) } catch { messages.append(error.localizedDescription) }
            }
            for o in compiled {
                let (_, rows) = try await s.queryAll("select line, position, text from all_errors where owner = :o and name = :n and type = :t and attribute = 'ERROR' order by sequence",
                                                     binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name)),
                                                             BindVariable(name: "t", value: .text(o.type.rawValue))], limit: 200)
                messages += rows.map { "\(o.name) \($0[0].displayText ?? ""):\($0[1].displayText ?? "") \(($0[2].displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines))" }
            }
            let ok = messages.isEmpty
            if ok { project.lastBuild[item.id] = Date() }
            results.append(ProjectBuildResult(id: item.id, title: item.title, status: ok ? .compiled : .failed, messages: messages + notes))
            if !ok, project.options.haltOnFirstError { break }
        }
        return results
    }

    /// Szukanie tekstu w plikach i źródłach obiektów projektu (bez wielkości liter) — UG 14.5.
    public static func find(_ text: String, in project: Project, projectURL: URL, ws: Workspace) async throws -> [ProjectMatch] {
        let needle = text.lowercased()
        guard !needle.isEmpty else { return [] }
        var out: [ProjectMatch] = []
        func scan(_ content: String, _ item: ProjectItem) {
            for (i, line) in content.components(separatedBy: "\n").enumerated() where line.lowercased().contains(needle) {
                out.append(ProjectMatch(item: item.id, title: item.title, line: i + 1, text: line.trimmingCharacters(in: .whitespaces)))
            }
        }
        for item in project.items {
            switch item.kind {
            case .file:
                if let url = url(of: item, projectURL: projectURL), let data = try? Data(contentsOf: url) {
                    scan(TextFileCodec.decode(data, preferred: project.options.preferredEncoding).text, item)
                }
            case .object:
                if let o = item.object?.dbObject, let m = ws.metadata(for: try connection(project, in: ws).id), let src = try? await m.source(of: o) { scan(src, item) }
            case .note:
                scan(item.note ?? "", item)
            }
        }
        return out
    }

    /// Pulpit: okna z plikami w katalogu projektu (zapis) i ich ponowne otwarcie.
    public static func captureDesktop(_ project: inout Project, projectURL: URL, ws: Workspace) {
        // Okno pary (D194): oba pliki — przy otwarciu drugi trafia do tego samego okna.
        project.desktop = ws.documents.flatMap { d in d.fileURLs.map { ProjectWindow(path: relativePath($0, projectURL: projectURL), kind: d.kind) } }
    }

    public static func restoreDesktop(_ project: Project, projectURL: URL, ws: Workspace) -> Int {
        var n = 0
        for w in project.desktop {
            let url = w.path.hasPrefix("/") ? URL(fileURLWithPath: w.path) : projectURL.deletingLastPathComponent().appendingPathComponent(w.path)
            if ws.documents.contains(where: { $0.fileURLs.contains(url.standardizedFileURL) }) { continue }
            if (try? ws.openFile(url, as: w.kind)) != nil { n += 1 }
        }
        return n
    }
}

/// Komendy projektu (menu Projekt).
@MainActor
enum ProjectCommands {
    static func current(_ ws: Workspace) throws -> (Project, URL) {
        guard let p = ws.project, let url = ws.projectURL else { throw CommandError.notAvailable(L10n.tr("Brak otwartego projektu")) }
        return (p, url)
    }

    static func save(_ ws: Workspace) throws {
        let (p, url) = try current(ws)
        try p.encoded().write(to: url, options: .atomic)
    }

    /// Zmiana projektu z zapisem pliku projektu.
    static func mutate(_ ws: Workspace, _ change: (inout Project, URL) throws -> Void) throws {
        var (p, url) = try current(ws)
        try change(&p, url)
        ws.project = p
        try save(ws)
    }

    /// Element z argumentu `item` (identyfikator elementu projektu).
    static func itemIndex(_ ctx: CommandContext, in p: Project) throws -> Int {
        guard let raw = ctx.arguments.string("item") else { throw CommandError.missingArgument("item") }
        guard let id = UUID(uuidString: raw), let i = p.items.firstIndex(where: { $0.id == id }) else {
            throw CommandError.invalidArgument("item", raw)
        }
        return i
    }

    static let itemParameter = CommandParameter("item", .string, required: true, L10n.tr("Identyfikator elementu projektu"))

    /// Opcje projektu zmieniane komendą `project.setOption`.
    static let options = ["connection", "haltOnFirstError", "beautifyOnBuild"]

    /// Czynności na elementach i opcjach projektu (okno projektu, PD-PROJ-001/002) — każda zapisuje plik projektu.
    static var itemCommands: [Command] {
        let hasProject: @MainActor (Workspace) -> Bool = { $0.project != nil }
        return [
            Command(CommandDescriptor(id: "project.addFiles", title: L10n.tr("Dodaj pliki do projektu…"), category: .project,
                                      parameters: [CommandParameter("files", .string, L10n.tr("Ścieżki plików (lista); bez — wybór plików"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Dodaje pliki do projektu (ścieżki względne wobec pliku projektu); pliki już obecne są pomijane."),
                                      feature: "PD-PROJ-001"),
                    validate: hasProject) { ctx in
                _ = try current(ctx.workspace)
                var files = (ctx.arguments.strings("files") ?? []).map { URL(fileURLWithPath: $0) }
                if ctx.arguments.strings("files") == nil { files = await ctx.ui?.chooseFilesToOpen() ?? [] }
                guard !files.isEmpty else { return .ok }
                var added = 0
                try mutate(ctx.workspace) { p, url in
                    for f in files {
                        let rel = ProjectEngine.relativePath(f, projectURL: url)
                        if !p.items.contains(where: { $0.path == rel }) { p.items.append(.file(rel)); added += 1 }
                    }
                }
                return CommandResult(message: L10n.tr("Dodano plików: \(added)"))
            },
            Command(CommandDescriptor(id: "project.addNote", title: L10n.tr("Dodaj notatkę do projektu"), category: .project,
                                      parameters: [CommandParameter("text", .string, L10n.tr("Tekst notatki"))],
                                      agent: .none, effect: .external, summary: L10n.tr("Dodaje do projektu element-notatkę."), feature: "PD-PROJ-001"),
                    validate: hasProject) { ctx in
                let note = ProjectItem.note(ctx.arguments.string("text") ?? L10n.tr("Notatka"))
                try mutate(ctx.workspace) { p, _ in p.items.append(note) }
                return CommandResult(value: .string(note.id.uuidString))
            },
            Command(CommandDescriptor(id: "project.removeItem", title: L10n.tr("Usuń element z projektu"), category: .project,
                                      parameters: [itemParameter], agent: .none, effect: .external,
                                      summary: L10n.tr("Usuwa element z projektu (plik na dysku i obiekt w bazie zostają)."), inMenu: false,
                                      feature: "PD-PROJ-001"),
                    validate: hasProject) { ctx in
                try mutate(ctx.workspace) { p, _ in
                    let i = try itemIndex(ctx, in: p)
                    p.items.remove(at: i)
                }
                return .ok
            },
            Command(CommandDescriptor(id: "project.setItemGroup", title: L10n.tr("Grupa elementu projektu"), category: .project,
                                      parameters: [itemParameter, CommandParameter("group", .string, L10n.tr("Nazwa grupy (pusta — bez grupy)"))],
                                      agent: .none, effect: .external, summary: L10n.tr("Przenosi element projektu do grupy."), inMenu: false,
                                      feature: "PD-PROJ-001"),
                    validate: hasProject) { ctx in
                let group = ctx.arguments.string("group").flatMap { $0.isEmpty ? nil : $0 }
                try mutate(ctx.workspace) { p, _ in
                    let i = try itemIndex(ctx, in: p)
                    p.items[i].group = group
                }
                return .ok
            },
            Command(CommandDescriptor(id: "project.setNote", title: L10n.tr("Tekst notatki projektu"), category: .project,
                                      parameters: [itemParameter, CommandParameter("text", .string, required: true, L10n.tr("Tekst notatki"))],
                                      agent: .none, effect: .external, summary: L10n.tr("Zmienia tekst elementu-notatki projektu."), inMenu: false,
                                      feature: "PD-PROJ-001"),
                    validate: hasProject) { ctx in
                guard let text = ctx.arguments.string("text") else { throw CommandError.missingArgument("text") }
                try mutate(ctx.workspace) { p, _ in
                    let i = try itemIndex(ctx, in: p)
                    guard p.items[i].kind == .note else { throw CommandError.invalidArgument("item", p.items[i].id.uuidString) }
                    p.items[i].note = text
                }
                return .ok
            },
            Command(CommandDescriptor(id: "project.setOption", title: L10n.tr("Opcja projektu"), category: .project,
                                      parameters: [CommandParameter("option", .string, required: true, L10n.tr("Opcja"), allowed: options),
                                                   CommandParameter("value", .string, required: true,
                                                                    L10n.tr("Wartość: nazwa połączenia (pusta — główne) albo true/false"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zmienia opcję projektu: połączenie budowania, zatrzymanie po pierwszym błędzie, formatowanie przy budowaniu."),
                                      inMenu: false, feature: "PD-PROJ-002"),
                    validate: hasProject) { ctx in
                guard let option = ctx.arguments.string("option") else { throw CommandError.missingArgument("option") }
                guard let value = ctx.arguments.values["value"] else { throw CommandError.missingArgument("value") }
                let flag = value.boolValue ?? (value.stringValue.map { ["true", "1", "yes", "tak"].contains($0.lowercased()) })
                try mutate(ctx.workspace) { p, _ in
                    switch option {
                    case "connection": p.options.connection = value.stringValue.flatMap { $0.isEmpty ? nil : $0 }
                    case "haltOnFirstError": p.options.haltOnFirstError = flag ?? p.options.haltOnFirstError
                    case "beautifyOnBuild": p.options.beautifyOnBuild = flag ?? p.options.beautifyOnBuild
                    default: throw CommandError.invalidArgument("option", option)
                    }
                }
                return .ok
            },
        ]
    }

    static var all: [Command] {
        let hasProject: @MainActor (Workspace) -> Bool = { $0.project != nil }
        return [
            Command(CommandDescriptor(id: "project.show", title: L10n.tr("Elementy projektu"), category: .project,
                                      agent: .none, effect: .uiState, summary: L10n.tr("Okno projektu: elementy, grupy, budowanie, wyszukiwanie, pulpit."),
                                      feature: "PD-PROJ-001")) { ctx in
                ctx.ui?.showProject()
                return .ok
            },
            Command(CommandDescriptor(id: "project.new", title: L10n.tr("Nowy projekt…"), category: .project,
                                      parameters: [CommandParameter("file", .string, L10n.tr("Plik projektu (.prj; bez argumentu — okno zapisu)"))],
                                      agent: .none, effect: .external, summary: L10n.tr("Tworzy nowy plik projektu i otwiera go."), feature: "PD-PROJ-001")) { ctx in
                var url = ctx.arguments.string("file").map { URL(fileURLWithPath: $0) }
                if url == nil, let ui = ctx.askingUI {
                    guard let u = await ui.chooseSaveURL(suggestedName: L10n.tr("Projekt"), fileExtension: "prj") else { throw CommandError.cancelledByUser }
                    url = u
                }
                guard let url else { throw CommandError.missingArgument("file") }
                ctx.workspace.project = Project(name: url.deletingPathExtension().lastPathComponent)
                ctx.workspace.projectURL = url
                try save(ctx.workspace)
                return .ok
            },
            Command(CommandDescriptor(id: "project.open", title: L10n.tr("Otwórz projekt…"), category: .project,
                                      parameters: [CommandParameter("file", .string, L10n.tr("Plik projektu (.prj; bez argumentu — wybór pliku)"))],
                                      agent: .none, effect: .uiState, summary: L10n.tr("Otwiera projekt z pliku."), feature: "PD-PROJ-001")) { ctx in
                var url = ctx.arguments.string("file").map { URL(fileURLWithPath: $0) }
                if url == nil, let ui = ctx.askingUI {
                    guard let u = await ui.chooseFile(L10n.tr("Otwórz projekt"), extensions: ["prj"]) else { throw CommandError.cancelledByUser }
                    url = u
                }
                guard let url else { throw CommandError.missingArgument("file") }
                ctx.workspace.project = try Project.decode(Data(contentsOf: url))
                ctx.workspace.projectURL = url
                return CommandResult().resolving(ctx.arguments.string("file") == nil ? ["file": .string(url.path)] : [:])
            },
            Command(CommandDescriptor(id: "project.close", title: L10n.tr("Zamknij projekt"), category: .project,
                                      agent: .none, effect: .uiState, summary: L10n.tr("Zapisuje i zamyka projekt."), feature: "PD-PROJ-001"),
                    validate: hasProject) { ctx in
                try? save(ctx.workspace)
                ctx.workspace.project = nil
                ctx.workspace.projectURL = nil
                return .ok
            },
            Command(CommandDescriptor(id: "project.addActiveFile", title: L10n.tr("Dodaj plik okna do projektu"), category: .project,
                                      agent: .none, effect: .external, summary: L10n.tr("Dodaje plik aktywnego okna do projektu."), feature: "PD-PROJ-001"),
                    validate: { $0.project != nil && $0.activeDocument?.fileURL != nil }) { ctx in
                guard case (var p, let url)? = try? current(ctx.workspace), let d = ctx.workspace.activeDocument, d.fileURL != nil else { return .ok }
                // Okno pary (D194): oba pliki.
                for f in d.fileURLs {
                    let rel = ProjectEngine.relativePath(f, projectURL: url)
                    if !p.items.contains(where: { $0.path == rel }) { p.items.append(.file(rel)) }
                }
                ctx.workspace.project = p
                try save(ctx.workspace)
                return .ok
            },
            Command(CommandDescriptor(id: "project.addSelectedObject", title: L10n.tr("Dodaj obiekt do projektu"), category: .project,
                                      agent: .none, effect: .external, summary: L10n.tr("Dodaje obiekt zaznaczony w przeglądarce obiektów do projektu."), feature: "PD-PROJ-001"),
                    validate: { $0.project != nil && $0.selectedObject != nil }) { ctx in
                guard var (p, _) = try? current(ctx.workspace), let o = ctx.workspace.selectedObject else { return .ok }
                if !p.items.contains(where: { $0.object == ProjectObject(o) }) { p.items.append(.object(o)) }
                ctx.workspace.project = p
                try save(ctx.workspace)
                return .ok
            },
            Command(CommandDescriptor(id: "project.build", title: L10n.tr("Buduj projekt"), category: .project,
                                      agent: .none, effect: .modifiesDatabase, summary: L10n.tr("Kompiluje wszystkie pliki i obiekty projektu w kolejności elementów."),
                                      feature: "PD-PROJ-002"),
                    validate: hasProject) { ctx in try await build(ctx, make: false) },
            Command(CommandDescriptor(id: "project.make", title: L10n.tr("Make projektu"), category: .project,
                                      agent: .none, effect: .modifiesDatabase, summary: L10n.tr("Kompiluje tylko pliki zmienione od ostatniego budowania i obiekty niepoprawne."),
                                      feature: "PD-PROJ-002"),
                    validate: hasProject) { ctx in try await build(ctx, make: true) },
            Command(CommandDescriptor(id: "project.saveDesktop", title: L10n.tr("Zapisz pulpit projektu"), category: .project,
                                      agent: .none, effect: .external, summary: L10n.tr("Zapamiętuje w projekcie otwarte okna z plikami."), feature: "PD-PROJ-003"),
                    validate: hasProject) { ctx in
                guard case (var p, let url)? = try? current(ctx.workspace) else { return .ok }
                ProjectEngine.captureDesktop(&p, projectURL: url, ws: ctx.workspace)
                ctx.workspace.project = p
                try save(ctx.workspace)
                return CommandResult(message: L10n.tr("Okna pulpitu: \(p.desktop.count)"))
            },
            Command(CommandDescriptor(id: "project.openDesktop", title: L10n.tr("Otwórz pulpit projektu"), category: .project,
                                      agent: .none, effect: .uiState, summary: L10n.tr("Otwiera okna zapisane w pulpicie projektu."), feature: "PD-PROJ-003"),
                    validate: hasProject) { ctx in
                let (p, url) = try current(ctx.workspace)
                return CommandResult(message: L10n.tr("Otwarto okien: \(ProjectEngine.restoreDesktop(p, projectURL: url, ws: ctx.workspace))"))
            },
            Command(CommandDescriptor(id: "project.find", title: L10n.tr("Szukaj w projekcie…"), category: .project,
                                      parameters: [CommandParameter("text", .string, required: true, L10n.tr("Szukany tekst"))],
                                      agent: .none, effect: .none, summary: L10n.tr("Szuka tekstu w plikach, źródłach obiektów i notatkach projektu."), feature: "PD-PROJ-003"),
                    validate: hasProject) { ctx in
                let (p, url) = try current(ctx.workspace)
                let matches = try await ProjectEngine.find(ctx.arguments.string("text") ?? "", in: p, projectURL: url, ws: ctx.workspace)
                return CommandResult(message: L10n.tr("Trafienia: \(matches.count)"),
                                     value: .array(matches.map { .object(["item": .string($0.title), "line": .int(Int64($0.line)), "text": .string($0.text)]) }))
            },
        ] + itemCommands
    }

    static func build(_ ctx: CommandContext, make: Bool) async throws -> CommandResult {
        guard case (var p, let url)? = try? current(ctx.workspace) else { return .ok }
        let results = try await ProjectEngine.build(&p, projectURL: url, make: make, in: ctx.workspace)
        ctx.workspace.project = p
        ctx.workspace.projectBuildResults = results
        try? save(ctx.workspace)
        let failed = results.filter { $0.status == .failed }.count
        return CommandResult(message: L10n.tr("Skompilowano: \(results.filter { $0.status == .compiled }.count), pominięto: \(results.filter { $0.status == .skipped }.count), błędy: \(failed)"),
                             value: .array(results.map { .object(["item": .string($0.title), "status": .string($0.status.rawValue)]) }))
    }
}
