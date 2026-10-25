import Foundation
import Observation
import PelikanDB
import PelikanSQL

/// Typ obiektu bazy w Object Browserze (UG 21.1): folder, typ w ALL_OBJECTS, minimalna wersja serwera.
public enum DBObjectType: String, Sendable, Codable, CaseIterable, Hashable {
    case function = "FUNCTION", procedure = "PROCEDURE", package = "PACKAGE", packageBody = "PACKAGE BODY"
    case type = "TYPE", typeBody = "TYPE BODY", trigger = "TRIGGER", javaSource = "JAVA SOURCE", library = "LIBRARY"
    case table = "TABLE", view = "VIEW", materializedView = "MATERIALIZED VIEW", sequence = "SEQUENCE", synonym = "SYNONYM"
    case index = "INDEX", databaseLink = "DATABASE LINK", queue = "QUEUE", job = "JOB"
    case mleModule = "MLE MODULE", mleEnvironment = "MLE ENVIRONMENT", domain = "DOMAIN", property = "PROPERTY GRAPH"
    /// Adnotacje 23ai (ALL_ANNOTATIONS, nie są obiektami ALL_OBJECTS) i asercje SQL 23.26 (ALL_ASSERTIONS).
    case annotation = "ANNOTATION", assertion = "ASSERTION"
    case user = "USER", role = "ROLE", profile = "PROFILE", directory = "DIRECTORY"

    /// Nazwa folderu w drzewie.
    public var folderName: String {
        switch self {
        case .function: L10n.tr("Funkcje")
        case .procedure: L10n.tr("Procedury")
        case .package: L10n.tr("Pakiety")
        case .packageBody: L10n.tr("Ciała pakietów")
        case .type: L10n.tr("Typy")
        case .typeBody: L10n.tr("Ciała typów")
        case .trigger: L10n.tr("Wyzwalacze")
        case .javaSource: L10n.tr("Źródła Java")
        case .library: L10n.tr("Biblioteki")
        case .table: L10n.tr("Tabele")
        case .view: L10n.tr("Widoki")
        case .materializedView: L10n.tr("Widoki zmaterializowane")
        case .sequence: L10n.tr("Sekwencje")
        case .synonym: L10n.tr("Synonimy")
        case .index: L10n.tr("Indeksy")
        case .databaseLink: L10n.tr("Łącza bazy danych")
        case .queue: L10n.tr("Kolejki")
        case .job: L10n.tr("Zadania (Scheduler)")
        case .mleModule: L10n.tr("Moduły MLE")
        case .mleEnvironment: L10n.tr("Środowiska MLE")
        case .domain: L10n.tr("Domeny")
        case .property: L10n.tr("Grafy właściwości")
        case .annotation: L10n.tr("Adnotacje")
        case .assertion: L10n.tr("Asercje")
        case .user: L10n.tr("Użytkownicy")
        case .role: L10n.tr("Role")
        case .profile: L10n.tr("Profile")
        case .directory: L10n.tr("Katalogi")
        }
    }

    /// Kolejność folderów jak we wzorcu (programy, potem dane, potem obiekty globalne).
    public static let browserOrder: [DBObjectType] = [
        .function, .procedure, .package, .packageBody, .type, .typeBody, .trigger, .javaSource, .library, .mleModule,
        .mleEnvironment, .table, .view, .materializedView, .sequence, .synonym, .index, .domain, .annotation, .assertion, .property, .databaseLink,
        .queue, .job, .directory, .user, .role, .profile,
    ]

    /// Minimalna wersja główna serwera (MLE i domeny — 23ai).
    public var minimumServerMajor: Int {
        switch self {
        case .mleModule, .mleEnvironment, .domain, .property, .annotation, .assertion: 23
        default: 0
        }
    }

    /// Obiekty globalne (nie należą do schematu).
    public var isGlobal: Bool { [.user, .role, .profile, .directory].contains(self) }

    /// Kod PL/SQL (źródło w ALL_SOURCE, kompilacja, Program Window).
    public var isProgram: Bool { [.function, .procedure, .package, .packageBody, .type, .typeBody, .trigger, .javaSource, .mleModule].contains(self) }

    /// Dane (Query data / Edit data).
    public var hasData: Bool { [.table, .view, .materializedView, .synonym].contains(self) }
}

/// Obiekt bazy.
public struct DBObject: Sendable, Hashable, Identifiable {
    public var owner: String
    public var name: String
    public var type: DBObjectType
    public var status: String
    public var created: OracleTimestamp?
    public var lastDDL: OracleTimestamp?

    public var id: String { "\(owner).\(name).\(type.rawValue)" }
    public var isValid: Bool { status.uppercased() != "INVALID" }

    /// Nazwa do SQL (z właścicielem; identyfikatory niestandardowe w cudzysłowie).
    public var qualifiedName: String { "\(ResultExporter.identifier(owner)).\(ResultExporter.identifier(name))" }

    public init(owner: String, name: String, type: DBObjectType, status: String = "VALID", created: OracleTimestamp? = nil, lastDDL: OracleTimestamp? = nil) {
        self.owner = owner; self.name = name; self.type = type; self.status = status; self.created = created; self.lastDDL = lastDDL
    }
}

/// Element obiektu w drzewie (kolumna, indeks, więz, wyzwalacz, podprogram pakietu, zależność).
public struct DBObjectChild: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case column, index, constraint, trigger, subprogram, attribute, dependency, referencedBy, partition
        /// Użycie adnotacji (obiekt / kolumna z wartością — PD-OB-002).
        case usage
    }
    public var kind: Kind
    public var name: String
    public var detail: String
    public var object: DBObject?
    public var id: String { "\(kind.rawValue):\(name):\(detail)" }
}

/// Filtr Object Browsera (UG 21.1): nazwy z `%`, wiele po przecinku; Status=, Source= (tekst w źródle PL/SQL).
public struct ObjectFilter: Sendable, Hashable {
    public var text = ""
    /// Filtr nazwany (PD-OB-007): warunek WHERE i ORDER BY na widoku obiektów (alias `o`), `:browser_user` — bieżący
    /// użytkownik przeglądarki, `&browser_filter` — tekst z pola filtra.
    public var named: BrowserFilter?

    public init(_ text: String = "", named: BrowserFilter? = nil) { self.text = text; self.named = named }

    struct Parsed {
        var names: [String] = []
        var status: String?
        var source: String?
        var createdAfter: String?
        var modifiedAfter: String?
    }

    func parsed() -> Parsed {
        var p = Parsed()
        for raw in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !raw.isEmpty {
            let lower = raw.lowercased()
            func value() -> String { String(raw[raw.index(after: raw.firstIndex(of: "=")!)...]).trimmingCharacters(in: .whitespaces) }
            if lower.hasPrefix("status=") { p.status = value().uppercased() }
            else if lower.hasPrefix("source=") { p.source = value() }
            else if lower.hasPrefix("name=") { p.names.append(value().uppercased()) }
            else if lower.hasPrefix("createdafter=") { p.createdAfter = value() }
            else if lower.hasPrefix("modifiedafter=") { p.modifiedAfter = value() }
            else { p.names.append(raw.uppercased()) }
        }
        return p
    }

    /// Warunek SQL i zmienne wiązane dla widoku obiektów (alias `o`).
    func whereClause(binds: inout [BindVariable]) -> String {
        let p = parsed()
        var parts: [String] = []
        if !p.names.isEmpty {
            let ors = p.names.enumerated().map { i, n -> String in
                binds.append(BindVariable(name: "fn\(i)", value: .text(n.contains("%") || n.contains("_") ? n : n + "%")))
                return "o.object_name like :fn\(i)"
            }
            parts.append("(" + ors.joined(separator: " or ") + ")")
        }
        if let s = p.status { binds.append(BindVariable(name: "fst", value: .text(s))); parts.append("o.status = :fst") }
        if let c = p.createdAfter { binds.append(BindVariable(name: "fca", value: .text(c))); parts.append("o.created > to_date(:fca, 'YYYY-MM-DD')") }
        if let m = p.modifiedAfter { binds.append(BindVariable(name: "fma", value: .text(m))); parts.append("o.last_ddl_time > to_date(:fma, 'YYYY-MM-DD')") }
        if let src = p.source {
            binds.append(BindVariable(name: "fsrc", value: .text("%" + src.uppercased() + "%")))
            parts.append("exists (select 1 from all_source s where s.owner = o.owner and s.name = o.object_name and s.type = o.object_type and upper(s.text) like :fsrc)")
        }
        return parts.joined(separator: " and ")
    }
}

/// Metadane słownika danych dla połączenia (UG 21): zapytania przez sesję główną połączenia, cache w pamięci,
/// widoki DBA_ gdy użytkownik ma do nich prawo i włączona preferencja, foldery zależne od wersji serwera.
@MainActor
@Observable
public final class MetadataProvider {
    public let connectionID: UUID
    @ObservationIgnored let workspace: Workspace
    @ObservationIgnored private var cache: [String: [DBObject]] = [:]
    @ObservationIgnored private var childCache: [String: [DBObjectChild]] = [:]
    @ObservationIgnored private var dbaViews: Bool?
    @ObservationIgnored private var features: DictionaryFeatures?
    /// Pamięć podręczna Code Assistant: nazwy obiektów schematu, rozwiązane nazwy (synonimy), linki.
    @ObservationIgnored var nameCache: [String: [(name: String, type: String)]] = [:]
    @ObservationIgnored var resolveCache: [String: DBObject?] = [:]
    @ObservationIgnored var linkCache: [String]?
    public private(set) var recent: [DBObject] = []
    /// Zmienia się po odświeżeniu (widoki przeładowują drzewo).
    public private(set) var generation = 0

    init(workspace: Workspace, connectionID: UUID) {
        self.workspace = workspace
        self.connectionID = connectionID
    }

    func session() async throws -> any DatabaseSession {
        try await workspace.sessions.session(SessionKey(connectionID: connectionID, purpose: .main))
    }

    public func refresh() {
        cache.removeAll()
        childCache.removeAll()
        nameCache.removeAll()
        resolveCache.removeAll()
        linkCache = nil
        features = nil
        generation += 1
        // Słownik analizy nazw w czasie pisania (po DDL Object Browsera, edytorów obiektów, odświeżeniu).
        workspace.resetNameResolutionCache(connectionID)
    }

    public func refresh(_ object: DBObject) {
        childCache = childCache.filter { !$0.key.hasPrefix(object.id) }
        cache = cache.filter { !$0.key.contains("|\(object.type.rawValue)|") }
        generation += 1
    }

    /// Prefiks widoków słownika: DBA_ (gdy dostępne i włączone w preferencjach) albo ALL_.
    func dictionaryPrefix() async throws -> String {
        if let d = dbaViews { return d ? "dba" : "all" }
        var d = false
        if workspace.settings.useDBAViews {
            let s = try await session()
            d = (try? await s.scalar("select count(*) from session_privs where privilege in ('SELECT ANY DICTIONARY', 'SELECT_CATALOG_ROLE')")).flatMap(Int.init) ?? 0 > 0
            if !d { d = (try? await s.scalar("select count(*) from session_roles where role = 'SELECT_CATALOG_ROLE'")).flatMap(Int.init) ?? 0 > 0 }
        }
        dbaViews = d
        return d ? "dba" : "all"
    }

    /// Schemat bieżący sesji (<CURRENT USER>).
    public func currentSchema() async throws -> String {
        try await session().info.currentSchema
    }

    /// Możliwości słownika serwera (wersja, widoki 23ai/26ai — PD-OB-026), pamiętane do odświeżenia.
    public func dictionaryFeatures() async throws -> DictionaryFeatures {
        if let features { return features }
        let f = await DictionaryQuery.features(in: try await session())
        features = f
        return f
    }

    /// Foldery dostępne na serwerze (wersja i obecne widoki słownika).
    public func availableTypes() async throws -> [DBObjectType] {
        try await dictionaryFeatures().availableTypes
    }

    /// Użytkownicy (wybór schematu w Object Browserze).
    public func users() async throws -> [String] {
        let (_, rows) = try await session().queryAll("select username from all_users order by username", limit: 100_000)
        return rows.compactMap { $0.first?.displayText }
    }

    /// Obiekty typu dla właściciela (nil — wszyscy użytkownicy) z filtrem.
    public func objects(_ type: DBObjectType, owner: String?, filter: ObjectFilter = ObjectFilter()) async throws -> [DBObject] {
        let key = "\(owner ?? "*")|\(type.rawValue)|\(filter.text)|\(filter.named?.id.uuidString ?? "")|\(filter.named?.whereClause ?? "")"
        if let c = cache[key] { return c }
        let s = try await session()
        let px = try await dictionaryPrefix()
        var binds: [BindVariable] = []
        var sql: String
        switch type {
        case .user:
            sql = "select username, username, 'VALID', created, created from all_users o where 1 = 1"
            sql = applyNameFilter(sql, column: "username", filter: filter, binds: &binds) + " order by 1"
        case .role:
            sql = px == "dba" ? "select role, role, 'VALID', null, null from dba_roles o where 1 = 1" : "select role, role, 'VALID', null, null from session_roles o where 1 = 1"
            sql = applyNameFilter(sql, column: "role", filter: filter, binds: &binds) + " order by 1"
        case .profile:
            sql = px == "dba" ? "select distinct profile, profile, 'VALID', null, null from dba_profiles o where 1 = 1"
                : "select profile, profile, 'VALID', null, null from user_users o where 1 = 1"
            sql = applyNameFilter(sql, column: "profile", filter: filter, binds: &binds) + " order by 1"
        case .directory:
            sql = "select owner, directory_name, 'VALID', null, null from all_directories o where 1 = 1"
            sql = applyNameFilter(sql, column: "directory_name", filter: filter, binds: &binds) + " order by 2"
        case .annotation, .assertion:
            // Adnotacje (23ai) i asercje (23.26) nie mają wierszy w ALL_OBJECTS (asercja: typ UNDEFINED) — PD-OB-002.
            let (column, ownerColumn) = type == .annotation ? ("annotation_name", "annotation_owner") : ("assertion_name", "owner")
            sql = type == .annotation
                ? "select distinct annotation_owner, annotation_name, 'VALID', null, null from all_annotations o where 1 = 1"
                : "select owner, assertion_name, case when invalid = 'YES' then 'INVALID' else 'VALID' end, null, null from all_assertions o where 1 = 1"
            if let owner {
                binds.append(BindVariable(name: "own", value: .text(owner)))
                sql += " and \(ownerColumn) = :own"
            }
            sql = applyNameFilter(sql, column: column, filter: filter, binds: &binds) + " order by 2, 1"
        default:
            sql = "select o.owner, o.object_name, o.status, o.created, o.last_ddl_time from \(px)_objects o where o.object_type = :t"
            binds.append(BindVariable(name: "t", value: .text(type.rawValue)))
            // Kolejki i zadania mają osobne typy; obiekty pomocnicze (BIN$ w koszu) pomijamy.
            sql += " and o.object_name not like 'BIN$%'"
            if type == .table { sql += " and o.secondary = 'N'" }
            if let owner {
                binds.append(BindVariable(name: "own", value: .text(owner)))
                sql += " and o.owner = :own"
            }
            // Filtr nazwany: z polem filtra jako &browser_filter tekst pola nie filtruje już nazw (wzorzec).
            let usesFilterText = filter.named?.whereClause.contains("&browser_filter") == true
            let w = usesFilterText ? "" : filter.whereClause(binds: &binds)
            if !w.isEmpty { sql += " and " + w }
            if let named = filter.named, !named.whereClause.trimmingCharacters(in: .whitespaces).isEmpty {
                sql += " and (" + named.expandedWhere(filterText: filter.text) + ")"
                if named.whereClause.contains(":browser_user") {
                    binds.append(BindVariable(name: "browser_user", value: .text(try await currentSchema())))
                }
            }
            let order = filter.named?.orderBy.trimmingCharacters(in: .whitespaces) ?? ""
            sql += order.isEmpty ? " order by o.object_name, o.owner" : " order by " + order
        }
        let (_, rows) = try await s.queryAll(sql, binds: binds, limit: 1_000_000)
        let list = rows.map { r -> DBObject in
            DBObject(owner: r[0].displayText ?? "", name: r[1].displayText ?? "", type: type, status: r[2].displayText ?? "VALID",
                     created: Self.timestamp(r[3]), lastDDL: Self.timestamp(r[4]))
        }
        cache[key] = list
        return list
    }

    func applyNameFilter(_ sql: String, column: String, filter: ObjectFilter, binds: inout [BindVariable]) -> String {
        let names = filter.parsed().names
        guard !names.isEmpty else { return sql }
        let ors = names.enumerated().map { i, n -> String in
            binds.append(BindVariable(name: "fn\(i)", value: .text(n.contains("%") ? n : n + "%")))
            return "\(column) like :fn\(i)"
        }
        return sql + " and (" + ors.joined(separator: " or ") + ")"
    }

    static func timestamp(_ v: OracleValue) -> OracleTimestamp? {
        if case .timestamp(let t, _) = v { return t }
        return nil
    }

    /// Elementy obiektu (UG 21.1 podfoldery): kolumny, indeksy, więzy, wyzwalacze, podprogramy, zależności.
    public func children(of o: DBObject) async throws -> [DBObjectChild] {
        let key = o.id
        if let c = childCache[key] { return c }
        let s = try await session()
        let b = [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name))]
        var out: [DBObjectChild] = []
        func q(_ sql: String, _ make: ([OracleValue]) -> DBObjectChild) async throws {
            let (_, rows) = try await s.queryAll(sql, binds: b, limit: 100_000)
            out += rows.map(make)
        }
        switch o.type {
        case .table, .view, .materializedView:
            try await q("""
                select c.column_name, c.data_type || case when c.data_type in ('VARCHAR2','NVARCHAR2','CHAR','NCHAR','RAW') then '(' || c.char_length || ')'
                    when c.data_type = 'NUMBER' and c.data_precision is not null then '(' || c.data_precision || nvl2(nullif(c.data_scale, 0), ',' || c.data_scale, '') || ')' end
                    || case when c.nullable = 'N' then ' NOT NULL' end
                from all_tab_columns c where c.owner = :o and c.table_name = :n order by c.column_id
                """) { DBObjectChild(kind: .column, name: $0[0].displayText ?? "", detail: $0[1].displayText ?? "") }
            if o.type != .view {
                try await q("select index_name, uniqueness || ' ' || index_type from all_indexes where table_owner = :o and table_name = :n order by index_name") {
                    DBObjectChild(kind: .index, name: $0[0].displayText ?? "", detail: $0[1].displayText ?? "",
                                  object: DBObject(owner: o.owner, name: $0[0].displayText ?? "", type: .index))
                }
            }
            try await q("""
                select constraint_name, decode(constraint_type, 'P', 'PRIMARY KEY', 'U', 'UNIQUE', 'R', 'FOREIGN KEY', 'C', 'CHECK', constraint_type) || ' ' || status
                from all_constraints where owner = :o and table_name = :n and constraint_type in ('P', 'U', 'R', 'C')
                  and not (constraint_type = 'C' and constraint_name like 'SYS_C%')
                order by decode(constraint_type, 'P', 1, 'U', 2, 'R', 3, 4), constraint_name
                """) { DBObjectChild(kind: .constraint, name: $0[0].displayText ?? "", detail: $0[1].displayText ?? "") }
            try await q("select trigger_name, triggering_event || ' ' || status, owner from all_triggers where table_owner = :o and table_name = :n order by trigger_name") {
                DBObjectChild(kind: .trigger, name: $0[0].displayText ?? "", detail: $0[1].displayText ?? "",
                              object: DBObject(owner: $0[2].displayText ?? o.owner, name: $0[0].displayText ?? "", type: .trigger))
            }
        case .package, .type:
            try await q("""
                select procedure_name, case when overload is not null then '#' || overload end
                from all_procedures where owner = :o and object_name = :n and procedure_name is not null order by subprogram_id
                """) { DBObjectChild(kind: .subprogram, name: $0[0].displayText ?? "", detail: $0[1].displayText ?? "") }
            if o.type == .type {
                try await q("select attr_name, attr_type_name from all_type_attrs where owner = :o and type_name = :n order by attr_no") {
                    DBObjectChild(kind: .attribute, name: $0[0].displayText ?? "", detail: $0[1].displayText ?? "")
                }
            }
        case .annotation:
            // Użycie adnotacji: obiekt (i kolumna) z wartością.
            try await q("""
                select object_type || ' ' || object_name || nvl2(column_name, '.' || column_name, ''), annotation_value, object_type, object_name
                from all_annotations_usage where annotation_owner = :o and annotation_name = :n order by object_type, object_name, column_name
                """) { r in
                DBObjectChild(kind: .usage, name: r[0].displayText ?? "", detail: r[1].displayText ?? "",
                              object: (r[2].displayText).flatMap(DBObjectType.init(rawValue:)).map { DBObject(owner: o.owner, name: r[3].displayText ?? "", type: $0) })
            }
        default: break
        }
        if o.type != .user, o.type != .role, o.type != .annotation {
            try await q("""
                select referenced_owner || '.' || referenced_name, referenced_type, referenced_owner, referenced_name from all_dependencies
                where owner = :o and name = :n and referenced_owner not in ('SYS', 'PUBLIC') order by 1
                """) { r in
                DBObjectChild(kind: .dependency, name: r[0].displayText ?? "", detail: r[1].displayText ?? "",
                              object: (r[1].displayText).flatMap(DBObjectType.init(rawValue:)).map { DBObject(owner: r[2].displayText ?? "", name: r[3].displayText ?? "", type: $0) })
            }
            try await q("""
                select owner || '.' || name, type, owner, name from all_dependencies
                where referenced_owner = :o and referenced_name = :n order by 1
                """) { r in
                DBObjectChild(kind: .referencedBy, name: r[0].displayText ?? "", detail: r[1].displayText ?? "",
                              object: (r[1].displayText).flatMap(DBObjectType.init(rawValue:)).map { DBObject(owner: r[2].displayText ?? "", name: r[3].displayText ?? "", type: $0) })
            }
        }
        childCache[key] = out
        return out
    }

    /// Źródło PL/SQL (ALL_SOURCE) jako skrypt `CREATE OR REPLACE` (bez końcowego `/`).
    public func source(of o: DBObject) async throws -> String {
        try await Self.source(of: o, in: session())
    }

    /// Źródło programu w podanej sesji (także sesji agenta).
    public nonisolated static func source(of o: DBObject, in s: any DatabaseSession) async throws -> String {
        let (_, rows) = try await s.queryAll("select text, sys_context('userenv', 'current_schema') from all_source where owner = :o and name = :n and type = :t order by line",
                                             binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name)),
                                                     BindVariable(name: "t", value: .text(o.type.rawValue))], limit: 2_000_000)
        guard !rows.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak źródła \(o.type.rawValue) \(o.qualifiedName) (brak uprawnień albo obiekt zawinięty)")) }
        var text = rows.map { $0.first?.displayText ?? "" }.joined()
        if text.hasSuffix("\n") { text.removeLast() }
        // Moduł MLE: ALL_SOURCE zawiera sam kod JavaScript — nagłówek CREATE MLE MODULE z wersją (PD-PROG-014).
        if o.type == .mleModule {
            let version = try? await s.scalar("select version from all_mle_modules where module_owner = :o and module_name = :n",
                                               binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name))])
            return MLE.createModuleDDL(name: o.name, source: text, version: version ?? nil)
        }
        // Pierwsza linia z ALL_SOURCE zaczyna się od typu ("PACKAGE emp_api AS") — dodajemy CREATE OR REPLACE, a dla
        // obiektu z innego schematu także właściciela (bez niego kompilacja utworzyłaby kopię w schemacie sesji).
        let created = "CREATE OR REPLACE " + text
        let current = rows.first.flatMap { $0.count > 1 ? $0[1].displayText : nil }
        return current.map { $0 == o.owner } ?? true ? created : ProgramCompiler.withOwner(created, owner: o.owner)
    }

    /// DDL obiektu przez DBMS_METADATA (UG 23.2): zakończenie `;`/`/`, bez atrybutów składowania.
    public func ddl(of o: DBObject) async throws -> String {
        try await Self.ddl(of: o, in: session())
    }

    /// DDL obiektu w podanej sesji (także sesji agenta).
    public nonisolated static func ddl(of o: DBObject, in s: any DatabaseSession) async throws -> String {
        // DBMS_METADATA nie obsługuje asercji ani adnotacji (ORA-31600) — DDL ze słownika (PD-OB-002).
        if o.type == .assertion || o.type == .annotation { return try await Oracle23Dictionary.ddl(of: o, in: s) }
        let metaType: String = switch o.type {
        case .packageBody: "PACKAGE_BODY"
        case .typeBody: "TYPE_BODY"
        case .materializedView: "MATERIALIZED_VIEW"
        case .databaseLink: "DB_LINK"
        case .javaSource: "JAVA_SOURCE"
        case .mleModule: "MLE_MODULE"
        case .domain: "SQL_DOMAIN"
        default: o.type.rawValue.replacingOccurrences(of: " ", with: "_")
        }
        let r = try await s.execute("""
            declare h number; begin
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', true);
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES', false); exception when others then null; end;
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE', false); exception when others then null; end;
              :ddl := dbms_metadata.get_ddl(:t, :n, :o);
            end;
            """, binds: [BindVariable(name: "ddl", type: .clob, direction: .output), BindVariable(name: "t", value: .text(metaType)),
                         BindVariable(name: "n", value: .text(o.name)), BindVariable(name: "o", value: .text(o.owner))])
        guard case .lob(let l)? = r.outBinds["ddl"], let text = l.text else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Właściwości (UG 21.1 Properties): wiersz ALL_OBJECTS + widok typu (tabela, sekwencja, synonim…).
    public func properties(of o: DBObject) async throws -> [(String, String)] {
        let s = try await session()
        let b = [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name))]
        var out: [(String, String)] = []
        // Warianty zapasowe dla starszych serwerów (kolumny 12c — PD-OB-026).
        func add(_ sql: String, _ binds: [BindVariable], fallback: [String] = []) async throws {
            let (cols, rows) = try await DictionaryQuery.queryAll([sql] + fallback, binds: binds, limit: 1, in: s)
            guard let r = rows.first else { return }
            for (i, c) in cols.enumerated() where !r[i].isNull { out.append((c.name, r[i].format(workspace.settings.valueFormat))) }
        }
        if !o.type.isGlobal, o.type != .annotation, o.type != .assertion {
            try await add("select object_type, status, created, last_ddl_time, timestamp, temporary, generated, secondary, editionable from all_objects where owner = :o and object_name = :n and object_type = :t",
                          b + [BindVariable(name: "t", value: .text(o.type.rawValue))],
                          fallback: ["select object_type, status, created, last_ddl_time, timestamp, temporary, generated, secondary from all_objects where owner = :o and object_name = :n and object_type = :t"])
        }
        switch o.type {
        case .table: try await add("select tablespace_name, num_rows, last_analyzed, partitioned, temporary, iot_type, logging, compression from all_tables where owner = :o and table_name = :n", b)
        case .sequence: try await add("select min_value, max_value, increment_by, cycle_flag, order_flag, cache_size, last_number from all_sequences where sequence_owner = :o and sequence_name = :n", b)
        case .synonym: try await add("select table_owner, table_name, db_link from all_synonyms where owner = :o and synonym_name = :n", b)
        case .view: try await add("select text_length, read_only from all_views where owner = :o and view_name = :n", b)
        case .user: try await add("select user_id, created, common, oracle_maintained, default_collation from all_users where username = :n", [b[1]],
                                  fallback: ["select user_id, created, common, oracle_maintained from all_users where username = :n",
                                             "select user_id, created from all_users where username = :n"])
        case .assertion: try await add("select status, deferrable, deferred, validated, invalid from all_assertions where owner = :o and assertion_name = :n", b)
        default: break
        }
        if o.type == .table || o.type == .view {
            try await add("select comments from all_tab_comments where owner = :o and table_name = :n", b)
        }
        return out
    }

    /// Ostatnio używane obiekty (UG 21.1 Recent objects).
    public func touch(_ o: DBObject) {
        recent.removeAll { $0.id == o.id }
        recent.insert(o, at: 0)
        let limit = max(1, workspace.settings.browserRecentLimit)
        if recent.count > limit { recent.removeLast(recent.count - limit) }
    }

    /// Znalezienie obiektu po nazwie (`OWNER.NAME` albo `NAME`, synonimy publiczne pomijane).
    public func find(_ spec: String, type: DBObjectType? = nil) async throws -> DBObject? {
        let parts = spec.split(separator: ".").map { $0.hasPrefix("\"") ? String($0.dropFirst().dropLast()) : String($0).uppercased() }
        let name = parts.last ?? spec.uppercased()
        let s = try await session()
        let owner = parts.count >= 2 ? parts[0] : s.info.currentSchema
        var binds = [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(name))]
        var sql = "select object_type, status from all_objects where owner = :o and object_name = :n"
        if let type { sql += " and object_type = :t"; binds.append(BindVariable(name: "t", value: .text(type.rawValue))) }
        sql += " order by decode(object_type, 'PACKAGE BODY', 2, 'TYPE BODY', 2, 1)"
        let (_, rows) = try await s.queryAll(sql, binds: binds, limit: 10)
        guard let r = rows.first(where: { DBObjectType(rawValue: $0[0].displayText ?? "") != nil }),
              let t = DBObjectType(rawValue: r[0].displayText ?? "") else { return nil }
        return DBObject(owner: owner, name: name, type: t, status: r[1].displayText ?? "VALID")
    }
}

extension Workspace {
    /// Metadane połączenia głównego (Object Browser).
    public func metadata(for connectionID: UUID? = nil) -> MetadataProvider? {
        guard let id = connectionID ?? sessions.mainConnectionID else { return nil }
        if let m = metadataProviders[id] { return m }
        let m = MetadataProvider(workspace: self, connectionID: id)
        metadataProviders[id] = m
        return m
    }
}
