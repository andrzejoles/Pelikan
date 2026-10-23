import Foundation
import PelikanDB

/// Filtr nazwany Object Browsera (PD-OB-007): warunek na widoku obiektów (alias `o`), sortowanie, przypisanie do
/// użytkownika bazy i znacznik domyślnego.
public struct BrowserFilter: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var whereClause: String
    public var orderBy: String
    /// Użytkownik bazy (puste — wszyscy); filtr domyślny stosowany po zalogowaniu.
    public var forUser: String
    public var isDefault: Bool

    public init(name: String, whereClause: String, orderBy: String = "", forUser: String = "", isDefault: Bool = false) {
        self.name = name; self.whereClause = whereClause; self.orderBy = orderBy; self.forUser = forUser; self.isDefault = isDefault
    }

    /// Warunek z `&browser_filter` zastąpionym tekstem pola filtra (literał bez apostrofów).
    public func expandedWhere(filterText: String) -> String {
        whereClause.replacingOccurrences(of: "&browser_filter", with: filterText.replacingOccurrences(of: "'", with: "''"))
    }
}

/// Folder użytkownika Object Browsera (PD-OB-008): zapytanie (kolumny OWNER, OBJECT_NAME, OBJECT_TYPE) i/lub lista
/// obiektów, kolor, folder nadrzędny, widoczność według połączenia, ukrywanie właściciela.
public struct BrowserFolder: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var query: String
    public var objects: [ProjectObject]
    public var color: String?
    public var parentID: UUID?
    /// Wzorzec połączenia (`*`, `%`, `?`, `_` jak w zestawach preferencji; puste — wszystkie).
    public var connectionPattern: String
    public var suppressOwner: Bool

    public init(name: String, query: String = "", objects: [ProjectObject] = [], color: String? = nil, parentID: UUID? = nil,
                connectionPattern: String = "", suppressOwner: Bool = false) {
        self.name = name; self.query = query; self.objects = objects; self.color = color; self.parentID = parentID
        self.connectionPattern = connectionPattern; self.suppressOwner = suppressOwner
    }

    public func visible(for def: ConnectionDefinition?) -> Bool {
        connectionPattern.trimmingCharacters(in: .whitespaces).isEmpty
            || PreferenceSets.candidates(for: def).contains { PreferenceSets.matches(connectionPattern, $0) }
    }
}

/// Filtry i foldery Object Browsera w katalogu danych (`browser.json`).
public struct BrowserCustomization: Sendable, Codable, Hashable {
    public var filters: [BrowserFilter] = []
    public var folders: [BrowserFolder] = []
    public init() {}

    public static func load(from dir: URL?) -> BrowserCustomization {
        guard let u = dir?.appendingPathComponent("browser.json"), let d = try? Data(contentsOf: u),
              let c = try? JSONDecoder().decode(BrowserCustomization.self, from: d) else { return BrowserCustomization() }
        return c
    }

    public func save(to dir: URL?) throws {
        guard let dir else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: dir.appendingPathComponent("browser.json"), options: .atomic)
    }

    /// Filtr domyślny dla użytkownika bazy (najpierw przypisany do niego, potem ogólny).
    public func defaultFilter(user: String) -> BrowserFilter? {
        filters.first { $0.isDefault && $0.forUser.caseInsensitiveCompare(user) == .orderedSame }
            ?? filters.first { $0.isDefault && $0.forUser.isEmpty }
    }

    /// Filtry dostępne dla użytkownika bazy.
    public func filters(for user: String) -> [BrowserFilter] {
        filters.filter { $0.forUser.isEmpty || $0.forUser.caseInsensitiveCompare(user) == .orderedSame }
    }
}

extension MetadataProvider {
    /// Obiekty folderu użytkownika: lista i wynik zapytania (kolumny OWNER, OBJECT_NAME, OBJECT_TYPE).
    public func objects(in folder: BrowserFolder) async throws -> [DBObject] {
        var out = folder.objects.map(\.dbObject)
        let q = folder.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            var sql = q
            while sql.hasSuffix(";") { sql.removeLast() }
            let (_, rows) = try await session().queryAll(sql, limit: 100_000)
            for r in rows where r.count >= 3 {
                guard let t = r[2].displayText.flatMap({ DBObjectType(rawValue: $0.uppercased()) }) else { continue }
                out.append(DBObject(owner: r[0].displayText ?? "", name: r[1].displayText ?? "", type: t))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }
}

extension Workspace {
    /// Foldery typów Object Browsera wg preferencji: wybrane w podanej kolejności (pozostałe ukryte); puste — wszystkie.
    public func browserFolderTypes(available: [DBObjectType]) -> [DBObjectType] {
        let chosen = settings.browserFolders.compactMap(DBObjectType.init(rawValue:)).filter(available.contains)
        return chosen.isEmpty ? available : chosen
    }

    /// Komenda dwukliku na obiekcie (preferencja per typ; domyślnie Edytuj dla programów, Pokaż dane dla tabel i widoków).
    public func browserDoubleClickCommand(for type: DBObjectType) -> CommandID {
        if let c = settings.browserDoubleClick[type.rawValue], ["ob.edit", "ob.queryData", "ob.describe", "ob.ddl", "ob.editData"].contains(c) {
            return CommandID(rawValue: c)
        }
        return type.hasData && !type.isProgram ? "ob.queryData" : "ob.edit"
    }
}

/// Komendy filtrów nazwanych i folderów użytkownika (PD-OB-007, PD-OB-008).
@MainActor
enum BrowserCommands {
    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "ob.applyFilter", title: L10n.tr("Filtr nazwany…"), category: .tools, submenu: L10n.tr("Object Browser"),
                                      parameters: [CommandParameter("name", .string, L10n.tr("Nazwa filtra (puste — bez filtra)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Stosuje w Object Browserze filtr nazwany (WHERE/ORDER BY na widoku obiektów)."), feature: "PD-OB-007")) { ctx in
                let ws = ctx.workspace
                var name = ctx.arguments.string("name")
                if name == nil, let ui = ctx.ui, !ws.browserCustomization.filters.isEmpty {
                    let options = Array(ws.browserCustomization.filters.prefix(7).map(\.name)) + [L10n.tr("Bez filtra")]
                    guard let i = await ui.ask(L10n.tr("Filtr nazwany"), message: L10n.tr("Wybierz filtr Object Browsera."), buttons: options) else {
                        throw CommandError.cancelledByUser
                    }
                    name = i < options.count - 1 ? options[i] : ""
                }
                guard let name, !name.isEmpty else { ws.browserFilter = nil; ws.metadata()?.refresh(); return .ok }
                guard let f = ws.browserCustomization.filters.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw CommandError.invalidArgument("name", name)
                }
                ws.browserFilter = f
                ws.metadata()?.refresh()
                return CommandResult(message: f.name)
            },
            Command(CommandDescriptor(id: "ob.addToFolder", title: L10n.tr("Dodaj do folderu…"), category: .tools, submenu: L10n.tr("Obiekt"),
                                      parameters: ObjectCommands.objectParams + [CommandParameter("folder", .string, L10n.tr("Folder użytkownika (nowy, gdy nie istnieje)"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Dodaje zaznaczony obiekt do folderu użytkownika Object Browsera."), feature: "PD-OB-008"),
                    validate: ObjectCommands.hasSelection) { ctx in
                let ws = ctx.workspace
                let (o, _) = try await ObjectCommands.target(ctx)
                var name = ctx.arguments.string("folder")
                if name == nil { name = await ctx.ui?.askText(L10n.tr("Dodaj do folderu"), message: L10n.tr("Folder użytkownika"), defaultValue: ws.browserCustomization.folders.first?.name ?? "") }
                guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError.cancelledByUser }
                var c = ws.browserCustomization
                if let i = c.folders.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    if !c.folders[i].objects.contains(where: { $0.dbObject.id == o.id }) { c.folders[i].objects.append(ProjectObject(o)) }
                } else {
                    c.folders.append(BrowserFolder(name: name, objects: [ProjectObject(o)]))
                }
                try ws.saveBrowserCustomization(c)
                return CommandResult(message: name)
            },
        ]
    }
}
