import Foundation
import PelikanDB
import PelikanSQL

/// Widoki dualności JSON-relacyjnej (Oracle 23ai+, SD-DV-001): lista, generator DDL z tabeli głównej i tabel
/// podrzędnych (klucze obce), dokumenty i struktura (JSON_DATAGUIDE).
public enum DualityViews {
    public struct View: Sendable, Hashable, Identifiable {
        public var owner: String
        public var name: String
        public var rootTable: String
        public var allowInsert: Bool
        public var allowUpdate: Bool
        public var allowDelete: Bool
        public var id: String { "\(owner).\(name)" }
    }

    static func yes(_ v: OracleValue) -> Bool { ["YES", "TRUE"].contains((v.displayText ?? "").uppercased()) }

    public static func list(owner: String, in s: any DatabaseSession) async throws -> [View] {
        let (_, rows) = try await s.queryAll("""
            select view_owner, view_name, root_table_name, allow_insert, allow_update, allow_delete
              from all_json_duality_views where view_owner = :o order by view_name
            """, binds: [BindVariable(name: "o", value: .text(owner))], limit: 10_000)
        return rows.map {
            View(owner: $0[0].displayText ?? "", name: $0[1].displayText ?? "", rootTable: $0[2].displayText ?? "",
                 allowInsert: yes($0[3]), allowUpdate: yes($0[4]), allowDelete: yes($0[5]))
        }
    }

    /// DDL widoku dla tabeli głównej: kolumny jako pola (`_id` = klucz główny), tabele podrzędne (FK do klucza głównego)
    /// jako tablice zagnieżdżonych obiektów; operacje insert/update/delete na wszystkich poziomach.
    public static func generateDDL(view: String, owner: String, rootTable: String, children: [String] = [], in s: any DatabaseSession) async throws -> String {
        func columns(_ table: String) async throws -> [String] {
            let (_, rows) = try await s.queryAll("select column_name from all_tab_columns where owner = :o and table_name = :t order by column_id",
                                                 binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "t", value: .text(table))], limit: 2000)
            return rows.compactMap { $0.first?.displayText }
        }
        let pk = try await s.scalar("""
            select cc.column_name from all_constraints c join all_cons_columns cc on cc.owner = c.owner and cc.constraint_name = c.constraint_name
             where c.owner = :o and c.table_name = :t and c.constraint_type = 'P' and cc.position = 1
            """, binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "t", value: .text(rootTable))])
        guard let pk else { throw CommandError.notAvailable(L10n.tr("Tabela \(rootTable) nie ma klucza głównego — wymagany w widoku dualności")) }
        func field(_ c: String) -> String { c.lowercased().replacingOccurrences(of: "\"", with: "") }
        var lines = ["'_id' : r.\(ResultExporter.identifier(pk))"]
        for c in try await columns(rootTable) where c != pk { lines.append("'\(field(c))' : r.\(ResultExporter.identifier(c))") }
        for child in children {
            let fk = try await s.scalar("""
                select cc.column_name from all_constraints c join all_cons_columns cc on cc.owner = c.owner and cc.constraint_name = c.constraint_name
                  join all_constraints p on p.owner = c.r_owner and p.constraint_name = c.r_constraint_name
                 where c.owner = :o and c.table_name = :c and c.constraint_type = 'R' and p.table_name = :t and cc.position = 1
                """, binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "c", value: .text(child)), BindVariable(name: "t", value: .text(rootTable))])
            guard let fk else { continue }
            let cols = try await columns(child).filter { $0 != fk }.map { c in "'\(field(c))' : c.\(ResultExporter.identifier(c))" }
            lines.append("'\(field(child))' : [select json {\(cols.joined(separator: ", "))} from \(ResultExporter.identifier(owner)).\(ResultExporter.identifier(child)) c with insert update delete where c.\(ResultExporter.identifier(fk)) = r.\(ResultExporter.identifier(pk))]")
        }
        return """
            create or replace json relational duality view \(ResultExporter.identifier(owner)).\(ResultExporter.identifier(view.uppercased())) as
            select json {
              \(lines.joined(separator: ",\n  "))
            }
            from \(ResultExporter.identifier(owner)).\(ResultExporter.identifier(rootTable)) r with insert update delete
            """
    }

    /// Dokumenty widoku (JSON tekstowo).
    public static func documents(_ v: View, limit: Int = 100, in s: any DatabaseSession) async throws -> [String] {
        let (_, rows) = try await s.queryAll("select json_serialize(data pretty) from \(ResultExporter.identifier(v.owner)).\(ResultExporter.identifier(v.name)) fetch first \(max(1, limit)) rows only",
                                             limit: limit)
        return rows.map { r in
            if case .lob(let l)? = r.first { return l.text ?? "" }
            return r.first?.displayText ?? ""
        }
    }

    /// Struktura dokumentów (JSON_DATAGUIDE): ścieżki i typy.
    public static func dataGuide(_ v: View, in s: any DatabaseSession) async throws -> [(path: String, type: String)] {
        let (_, rows) = try await s.queryAll("""
            select jt.path, jt.type from (select json_dataguide(data) g from \(ResultExporter.identifier(v.owner)).\(ResultExporter.identifier(v.name))) d,
                   json_table(d.g, '$[*]' columns (path varchar2(400) path '$."o:path"', type varchar2(40) path '$.type')) jt order by jt.path
            """, limit: 10_000)
        return rows.map { ($0[0].displayText ?? "", $0[1].displayText ?? "") }
    }
}

/// Moduły i środowiska MLE (JavaScript, Oracle 23ai+, SD-MLE-001).
public enum MLE {
    public struct Module: Sendable, Hashable, Identifiable {
        public var owner: String
        public var name: String
        public var language: String
        public var version: String
        public var id: String { "\(owner).\(name)" }
    }

    public static func modules(owner: String, in s: any DatabaseSession) async throws -> [Module] {
        let (_, rows) = try await s.queryAll("select module_owner, module_name, language_name, nvl(version, ' ') from all_mle_modules where module_owner = :o order by module_name",
                                             binds: [BindVariable(name: "o", value: .text(owner))], limit: 10_000)
        return rows.map { Module(owner: $0[0].displayText ?? "", name: $0[1].displayText ?? "", language: $0[2].displayText ?? "", version: ($0[3].displayText ?? "").trimmingCharacters(in: .whitespaces)) }
    }

    public static func environments(owner: String, in s: any DatabaseSession) async throws -> [String] {
        let (_, rows) = try await s.queryAll("select env_name from all_mle_envs where env_owner = :o order by env_name", binds: [BindVariable(name: "o", value: .text(owner))], limit: 10_000)
        return rows.compactMap { $0.first?.displayText }
    }

    /// DDL modułu z kodu JavaScript (import pliku): nazwa z pliku, wersja opcjonalna.
    public static func createModuleDDL(name: String, source: String, version: String? = nil) -> String {
        let n = name.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
        return "create or replace mle module \(n) language javascript" + (version.map { " version '\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "") + " as\n" + source
    }

    /// Środowisko importujące moduły (`import … from "nazwa"`).
    public static func createEnvironmentDDL(name: String, imports: [(specifier: String, module: String)]) -> String {
        let n = name.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
        let list = imports.map { "'\($0.specifier.replacingOccurrences(of: "'", with: "''"))' module \($0.module.uppercased())" }.joined(separator: ", ")
        return "create or replace mle env \(n)" + (list.isEmpty ? "" : " imports (\(list))")
    }

    /// Kod źródłowy modułu (ALL_SOURCE, typ MLE MODULE).
    public static func source(owner: String, name: String, in s: any DatabaseSession) async throws -> String {
        let (_, rows) = try await s.queryAll("select text from all_source where owner = :o and name = :n and type = 'MLE MODULE' order by line",
                                             binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(name))], limit: 1_000_000)
        return rows.map { $0.first?.displayText ?? "" }.joined()
    }
}

/// Debugowanie modułów MLE po wykonaniu (DBMS_MLE.ENABLE_DEBUGGING, SD-MLE-001): punkty na liniach modułu z migawką
/// zmiennych lokalnych albo obserwacją wskazanych; kod wywołujący wykonywany w jednym bloku z gwarantowanym wyłączeniem.
public enum MLEDebugger {
    public struct Point: Sendable, Hashable {
        public var line: Int
        /// Puste — migawka wszystkich zmiennych lokalnych (snapshot); inaczej obserwacja tych nazw (watch).
        public var watch: [String]
        public init(line: Int, watch: [String] = []) { self.line = line; self.watch = watch }
    }

    public struct Hit: Sendable, Hashable {
        public var frame: String
        public var line: Int
        public var values: [String: String]
    }

    /// Specyfikacja debugowania (JSON) dla modułu `owner.module`.
    public static func spec(owner: String, module: String, points: [Point]) -> String {
        func q(_ s: String) -> String {
            s.unicodeScalars.map { c -> String in
                switch c { case "\"": "\\\""; case "\\": "\\\\"; default: c.value < 0x20 ? String(format: "\\u%04x", c.value) : String(c) }
            }.joined()
        }
        let name = q("\(owner.uppercased()).\(module.uppercased())")
        let dps = points.map { p -> String in
            let actions = p.watch.isEmpty ? #"{"type":"snapshot"}"# : p.watch.map { #"{"type":"watch","id":""# + q($0) + #""}"# }.joined(separator: ",")
            return #"{"at":{"name":""# + name + #"","line":"# + String(p.line) + #"},"actions":["# + actions + "]}"
        }
        return #"{"version":"1.0","debugpoints":["# + dps.joined(separator: ",") + "]}"
    }

    /// Wynik PARSE_DEBUG_OUTPUT: tablica (po wywołaniach) tablic trafień.
    public static func parse(_ json: String) -> [Hit] {
        guard let data = json.data(using: .utf8), let top = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        let flat = top.flatMap { ($0 as? [Any]) ?? [$0] }
        return flat.compactMap { item in
            guard let o = item as? [String: Any], let at = o["at"] as? [String: Any] else { return nil }
            var values: [String: String] = [:]
            for (k, v) in (o["values"] as? [String: Any]) ?? [:] {
                if let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .sortedKeys]) { values[k] = String(decoding: d, as: UTF8.self) }
            }
            return Hit(frame: at["frameName"] as? String ?? "", line: (at["line"] as? Int) ?? 0, values: values)
        }
    }

    /// Wykonuje `call` (instrukcje PL/SQL) z włączonym debugowaniem i zwraca trafienia punktów.
    public static func run(owner: String, module: String, points: [Point], call: String, in s: any DatabaseSession) async throws -> [Hit] {
        var body = call.trimmingCharacters(in: .whitespacesAndNewlines)
        while body.hasSuffix("/") { body.removeLast(); body = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !body.hasSuffix(";") { body += ";" }
        let block = """
            declare
              sink blob;
            begin
              dbms_lob.createtemporary(sink, true);
              dbms_mle.enable_debugging(json(:spec), sink);
              begin
                \(body)
              exception when others then
                dbms_mle.disable_debugging;
                raise;
              end;
              dbms_mle.disable_debugging;
              :out := json_serialize(dbms_mle.parse_debug_output(sink) returning clob);
            end;
            """
        let r = try await s.execute(block, binds: [BindVariable(name: "spec", type: .clob, value: .text(spec(owner: owner, module: module, points: points))),
                                                   BindVariable(name: "out", type: .clob, direction: .output)],
                                    options: ExecuteOptions(lobLimit: 50_000_000))
        guard case .lob(let l)? = r.outBinds["out"] else { return [] }
        return parse(l.text ?? "")
    }
}

/// Dane przestrzenne (SD-DATA-001): SDO_GEOMETRY jako WKT i prosty podgląd.
public enum Spatial {
    /// Kształt z WKT: listy pierścieni/linii (współrzędne x, y) i punkty.
    public struct Shape: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case point, line, polygon }
        public var kind: Kind
        public var parts: [[(Double, Double)]]
        public static func == (a: Shape, b: Shape) -> Bool {
            a.kind == b.kind && a.parts.count == b.parts.count && zip(a.parts, b.parts).allSatisfy { $0.count == $1.count && zip($0, $1).allSatisfy { $0 == $1 } }
        }
    }

    /// Parser WKT: POINT, LINESTRING, POLYGON, MULTIPOINT, MULTILINESTRING, MULTIPOLYGON, GEOMETRYCOLLECTION.
    public static func parse(_ wkt: String) -> [Shape] {
        let s = wkt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let paren = s.firstIndex(of: "(") else { return [] }
        let tag = s[..<paren].trimmingCharacters(in: .whitespaces).uppercased()
        let body = String(s[paren...])
        func coords(_ text: String) -> [(Double, Double)] {
            text.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").split(separator: ",").compactMap { pair in
                let n = pair.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
                return n.count >= 2 ? (n[0], n[1]) : nil
            }
        }
        /// Grupy na pierwszym poziomie nawiasów wewnątrz zewnętrznego nawiasu.
        func groups(_ text: String) -> [String] {
            var out: [String] = [], depth = 0, current = ""
            for ch in text.dropFirst().dropLast() {
                if ch == "(" { depth += 1 }
                if ch == ")" { depth -= 1 }
                if ch == ",", depth == 0 { out.append(current); current = ""; continue }
                current.append(ch)
            }
            if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }
            return out
        }
        switch tag {
        case "POINT": return [Shape(kind: .point, parts: [coords(body)])]
        case "LINESTRING": return [Shape(kind: .line, parts: [coords(body)])]
        case "POLYGON": return [Shape(kind: .polygon, parts: groups(body).map(coords))]
        case "MULTIPOINT": return [Shape(kind: .point, parts: [coords(body)])]
        case "MULTILINESTRING": return groups(body).map { Shape(kind: .line, parts: [coords($0)]) }
        case "MULTIPOLYGON": return groups(body).map { Shape(kind: .polygon, parts: groups($0.trimmingCharacters(in: .whitespaces)).map(coords)) }
        case "GEOMETRYCOLLECTION": return groups(body).flatMap { parse($0) }
        default: return []
        }
    }

    /// WKT kolumny SDO_GEOMETRY dla wyniku zapytania (zapytanie siatki owinięte SDO_UTIL.TO_WKTGEOMETRY).
    public static func wkt(query: String, column: String, limit: Int = 1000, in s: any DatabaseSession) async throws -> [String?] {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while q.hasSuffix(";") { q.removeLast() }
        let (_, rows) = try await s.queryAll("select sdo_util.to_wktgeometry(x.\(ResultExporter.identifier(column.uppercased()))) from (\(q)) x",
                                             limit: limit)
        return rows.map { r in
            if case .lob(let l)? = r.first { return l.text }
            return r.first?.displayText
        }
    }
}

/// Komendy widoków dualności, MLE i podglądu przestrzennego.
@MainActor
public enum Oracle23Commands {
    /// Sesja narzędzia dla połączenia aktywnego okna i bieżący schemat.
    public static func session(_ ws: Workspace) async throws -> (session: any DatabaseSession, owner: String) {
        guard let conn = ws.activeDocument.flatMap({ ws.effectiveConnection(of: $0) }) ?? ws.sessions.mainConnectionID else { throw CommandError.notConnected }
        let s = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("oracle23")))
        let owner = try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? ""
        return (s, owner)
    }

    static var all: [Command] {
        let connected: @MainActor (Workspace) -> Bool = { $0.sessions.mainConnectionID != nil }
        return [
            Command(CommandDescriptor(id: "tools.dualityViews", title: L10n.tr("Widoki dualności JSON"), category: .tools,
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Lista widoków dualności JSON-relacyjnej schematu: dokumenty, struktura (Data Guide) i generator DDL z tabeli głównej i tabel podrzędnych."),
                                      feature: "SD-DV-001"), validate: connected) { ctx in
                ctx.ui?.showDualityViews()
                return .ok
            },
            Command(CommandDescriptor(id: "tools.dualityViewDDL", title: L10n.tr("Nowy widok dualności…"), category: .tools,
                                      parameters: [CommandParameter("name", .string, required: true, L10n.tr("Nazwa widoku")),
                                                   CommandParameter("root", .string, required: true, L10n.tr("Tabela główna")),
                                                   CommandParameter("children", .string, L10n.tr("Tabele podrzędne (po przecinku)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Generuje DDL widoku dualności do nowego okna SQL (nie wykonuje go)."), feature: "SD-DV-001"),
                    validate: connected) { ctx in
                let (s, owner) = try await session(ctx.workspace)
                let children = (ctx.arguments.string("children") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
                let ddl = try await DualityViews.generateDDL(view: ctx.arguments.string("name") ?? "", owner: owner,
                                                             rootTable: (ctx.arguments.string("root") ?? "").uppercased(), children: children, in: s)
                ctx.workspace.newDocument(.sql, text: ddl + "\n/\n")
                return CommandResult(value: .string(ddl))
            },
            Command(CommandDescriptor(id: "tools.mleModules", title: L10n.tr("Moduły i środowiska MLE"), category: .tools,
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Moduły JavaScript (MLE) i środowiska schematu: źródło, import pliku .js jako modułu, nowe środowisko."),
                                      feature: "SD-MLE-001"), validate: connected) { ctx in
                ctx.ui?.showMLEModules()
                return .ok
            },
            Command(CommandDescriptor(id: "tools.importMLEModule", title: L10n.tr("Importuj moduł JavaScript…"), category: .tools,
                                      parameters: [CommandParameter("file", .string, required: true, L10n.tr("Plik .js / .mjs")),
                                                   CommandParameter("name", .string, L10n.tr("Nazwa modułu (domyślnie z nazwy pliku)")),
                                                   CommandParameter("version", .string, L10n.tr("Wersja"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Tworzy z pliku JavaScript DDL modułu MLE w nowym oknie programu (kompilacja jak innych obiektów)."),
                                      feature: "SD-MLE-001")) { ctx in
                guard let path = ctx.arguments.string("file") else { throw CommandError.invalidArgument("file", "") }
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let source = TextFileCodec.decode(try Data(contentsOf: url)).text
                let ddl = MLE.createModuleDDL(name: ctx.arguments.string("name") ?? url.deletingPathExtension().lastPathComponent,
                                              source: source, version: ctx.arguments.string("version"))
                ctx.workspace.newDocument(.program, text: ddl + (ddl.hasSuffix("\n") ? "" : "\n") + "/\n")
                return CommandResult(value: .string(ddl))
            },
            Command(CommandDescriptor(id: "tools.debugMLE", title: L10n.tr("Debuguj moduł MLE po wykonaniu…"), category: .tools,
                                      parameters: [CommandParameter("module", .string, required: true, L10n.tr("Moduł")),
                                                   CommandParameter("lines", .string, required: true, L10n.tr("Linie punktów (po przecinku)")),
                                                   CommandParameter("watch", .string, L10n.tr("Obserwowane zmienne (po przecinku; puste — wszystkie lokalne)")),
                                                   CommandParameter("call", .sql, required: true, L10n.tr("Instrukcje PL/SQL wywołujące kod modułu"))],
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Wykonuje podane instrukcje z punktami debugowania DBMS_MLE i pokazuje wartości zmiennych w punktach."),
                                      feature: "SD-MLE-001"), validate: connected) { ctx in
                let (s, owner) = try await session(ctx.workspace)
                func list(_ k: String) -> [String] {
                    (ctx.arguments.string(k) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                let watch = list("watch")
                let points = list("lines").compactMap(Int.init).map { MLEDebugger.Point(line: $0, watch: watch) }
                guard !points.isEmpty else { throw CommandError.invalidArgument("lines", ctx.arguments.string("lines") ?? "") }
                let hits = try await MLEDebugger.run(owner: owner, module: ctx.arguments.string("module") ?? "", points: points,
                                                     call: ctx.arguments.string("call") ?? "", in: s)
                let text = hits.isEmpty ? L10n.tr("Żaden punkt nie został osiągnięty.")
                    : hits.enumerated().map { i, h in "#\(i + 1)  \(h.frame)  " + L10n.tr("linia \(h.line)") + "\n" + h.values.keys.sorted().map { "    \($0) = \(h.values[$0] ?? "")" }.joined(separator: "\n") }.joined(separator: "\n\n")
                ctx.ui?.showHTMLReport(title: L10n.tr("Debugowanie MLE"), html: PackCommands.html("MLE", text))
                return CommandResult(value: .array(hits.map { h in .object(["frame": .string(h.frame), "line": .int(Int64(h.line)),
                                                                            "values": .object(h.values.mapValues { .string($0) })]) }))
            },
            Command(CommandDescriptor(id: "grid.spatialPreview", title: L10n.tr("Podgląd przestrzenny"), category: .view,
                                      parameters: [CommandParameter("column", .string, L10n.tr("Kolumna SDO_GEOMETRY (domyślnie bieżąca)"))],
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Rysuje geometrie SDO_GEOMETRY kolumny wyniku (WKT przez SDO_UTIL) i pokazuje je jako tekst WKT."),
                                      feature: "SD-DATA-001"),
                    validate: { GridCommands.activeGrid($0) != nil }) { ctx in
                guard let (tab, grid) = GridCommands.activeGrid(ctx.workspace) else { return .ok }
                let name = ctx.arguments.string("column") ?? tab.currentColumn.map { grid.columns[$0].name }
                    ?? grid.columns.first(where: { $0.typeName.uppercased().contains("SDO_GEOMETRY") })?.name
                guard let name else { throw CommandError.notAvailable(L10n.tr("Wybierz kolumnę z geometrią")) }
                let (s, _) = try await session(ctx.workspace)
                let wkt = try await Spatial.wkt(query: grid.sql, column: name, in: s).compactMap { $0 }
                ctx.ui?.showSpatialPreview(title: name, wkt: wkt)
                return CommandResult(value: .array(wkt.map { .string($0) }))
            },
        ]
    }
}
