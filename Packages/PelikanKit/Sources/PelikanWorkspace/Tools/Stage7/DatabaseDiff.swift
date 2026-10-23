import Foundation
import PelikanDB
import PelikanSQL

/// Kolumna tabeli do porównania struktury (Database Diff).
public struct TableColumnDefinition: Sendable, Hashable, Codable {
    public var name: String
    public var type: String
    public var nullable: Bool
    public var defaultValue: String?
    public init(name: String, type: String, nullable: Bool = true, defaultValue: String? = nil) {
        self.name = name; self.type = type; self.nullable = nullable; self.defaultValue = defaultValue
    }
}

/// Database Diff (SD-DIFF-001): porównanie schematów (także dwóch połączeń) z typami obiektów do wyboru;
/// różniące się tabele wyrównywane przez ALTER TABLE ADD/MODIFY zamiast komentarza.
public enum DatabaseDiff {
    public struct Options: Sendable, Hashable, Codable {
        public var compare = CompareOptions()
        /// Typy obiektów (puste — wszystkie).
        public var types: Set<String> = []
        /// Kolumny tylko w celu: polecenie DROP COLUMN (inaczej komentarz).
        public var dropColumns = false
        public init() {}
    }

    static let columnsSQL = """
        select column_name, data_type || case
                 when data_type in ('VARCHAR2', 'NVARCHAR2', 'CHAR', 'NCHAR') then '(' || char_length || decode(char_used, 'C', ' CHAR', '') || ')'
                 when data_type = 'RAW' then '(' || data_length || ')'
                 when data_type = 'NUMBER' and data_precision is not null then '(' || data_precision || nvl2(nullif(data_scale, 0), ',' || data_scale, '') || ')'
                 when data_type = 'NUMBER' and data_scale = 0 then '(*,0)'
               end typ, nullable, data_default
          from all_tab_columns where owner = :o and table_name = :t order by column_id
        """

    public static func columns(owner: String, table: String, in s: any DatabaseSession) async throws -> [TableColumnDefinition] {
        let (_, rows) = try await s.queryAll(columnsSQL, binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "t", value: .text(table))], limit: 2000)
        return rows.compactMap { r in
            guard let n = r[0].displayText, let t = r[1].displayText else { return nil }
            let d = r[3].displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return TableColumnDefinition(name: n, type: t, nullable: r[2].displayText != "N", defaultValue: d?.isEmpty == false ? d : nil)
        }
    }

    /// Polecenia ALTER TABLE wyrównujące kolumny celu do źródła (czysta funkcja).
    public static func alterTable(_ table: String, source: [TableColumnDefinition], target: [TableColumnDefinition], dropColumns: Bool) -> [String] {
        let t = ResultExporter.identifier(table)
        let byName = Dictionary(target.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String] = []
        for c in source {
            let col = ResultExporter.identifier(c.name)
            guard let d = byName[c.name] else {
                out.append("alter table \(t) add (\(col) \(c.type.lowercased())" + (c.defaultValue.map { " default \($0)" } ?? "") + (c.nullable ? "" : " not null") + ");")
                continue
            }
            var parts: [String] = []
            if d.type != c.type { parts.append(c.type.lowercased()) }
            if (d.defaultValue ?? "") != (c.defaultValue ?? "") { parts.append("default " + (c.defaultValue ?? "null")) }
            if d.nullable != c.nullable { parts.append(c.nullable ? "null" : "not null") }
            if !parts.isEmpty { out.append("alter table \(t) modify (\(col) \(parts.joined(separator: " ")));") }
        }
        let names = Set(source.map(\.name))
        for d in target where !names.contains(d.name) {
            let st = "alter table \(t) drop column \(ResultExporter.identifier(d.name));"
            out.append(dropColumns ? st : "-- " + st)
        }
        return out
    }

    /// Porównanie schematów: różnice obiektów; dla różnych tabel skrypt ALTER (gdy różnią się tylko kolumny).
    public static func run(sourceOwner: String, source: any DatabaseSession, targetOwner: String, target: any DatabaseSession,
                           options: Options, progress: (@MainActor (Int, Int) -> Void)? = nil) async throws -> [ObjectDifference] {
        let objects = try await ObjectExport.objects(owner: sourceOwner, in: source).filter { options.types.isEmpty || options.types.contains($0.type.rawValue) }
        let total = objects.count
        var diffs = try await ObjectCompare.compare(objects, source: source, targetOwner: targetOwner, target: target, options: options.compare) { n in
            progress?(n, total)
        }
        for i in diffs.indices where diffs[i].type == .table && diffs[i].status == .different {
            let sc = try await columns(owner: sourceOwner, table: diffs[i].name, in: source)
            let tc = try await columns(owner: targetOwner, table: diffs[i].name, in: target)
            let alters = alterTable(diffs[i].name, source: sc, target: tc, dropColumns: options.dropColumns)
            if !alters.isEmpty { diffs[i].sync = alters.joined(separator: "\n") }
        }
        return diffs
    }

    /// Koszyk z różnic: obiekty do wdrożenia (tylko w źródle i różne) — do dalszej edycji i skryptu wdrożenia.
    public static func cart(from diffs: [ObjectDifference], sourceOwner: String, name: String = L10n.tr("Różnice")) -> DeploymentCart {
        var c = DeploymentCart(name: name)
        for d in diffs where d.status != .onlyTarget {
            var item = CartItem(owner: sourceOwner, name: d.name, type: d.type.rawValue)
            item.syncScript = d.status == .different ? d.sync : nil
            c.items.append(item)
        }
        return c
    }
}

/// Element koszyka: obiekt z DDL i opcjonalnie danymi (filtr WHERE); `syncScript` — gotowy skrypt z Diff zamiast DDL.
public struct CartItem: Sendable, Hashable, Codable, Identifiable {
    public var id = UUID()
    public var owner: String
    public var name: String
    public var type: String
    public var includeDDL = true
    public var includeData = false
    public var whereClause = ""
    public var syncScript: String?
    public init(owner: String, name: String, type: String) { self.owner = owner; self.name = name; self.type = type }
    public var object: DBObject? { DBObjectType(rawValue: type).map { DBObject(owner: owner, name: name, type: $0) } }
}

/// Koszyk (Cart, SD-DIFF-001): pakiet zmian zapisywany jako JSON (`.cart`) i wdrażany jako skrypt.
public struct DeploymentCart: Sendable, Hashable, Codable {
    public var format = "pelikan-cart"
    public var name: String
    public var items: [CartItem] = []
    /// Nazwa schematu w DDL (domyślnie bez — skrypt wykonywany w schemacie docelowym).
    public var includeOwner = false
    public var includeGrants = false
    public init(name: String) { self.name = name }

    public mutating func add(_ o: DBObject) {
        guard !items.contains(where: { $0.owner == o.owner && $0.name == o.name && $0.type == o.type.rawValue }) else { return }
        items.append(CartItem(owner: o.owner, name: o.name, type: o.type.rawValue))
    }

    public mutating func remove(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) } }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> DeploymentCart {
        let c = try JSONDecoder().decode(DeploymentCart.self, from: data)
        guard c.format == "pelikan-cart" else { throw CommandError.notAvailable(L10n.tr("To nie jest koszyk Pelikana")) }
        return c
    }

    /// Skrypt wdrożenia: DDL w kolejności zależności (typy obiektów jak w eksporcie), potem dane (INSERT, tabele
    /// nadrzędne pierwsze), COMMIT; SQL*Plus-zgodny.
    public func deploymentScript(in s: any DatabaseSession, progress: (@MainActor (String) -> Void)? = nil) async throws -> String {
        var out = "-- " + L10n.tr("Koszyk „\(name)” — skrypt wdrożenia wygenerowany przez Pelikana") + "\n"
        out += "-- " + ISO8601DateFormatter().string(from: Date()) + "\nset define off\nwhenever sqlerror exit failure rollback\n"
        var options = ObjectExportOptions()
        options.includeOwner = includeOwner
        options.includePrivileges = includeGrants
        let sorted = items.filter(\.includeDDL).sorted {
            (ObjectExport.sortKey(DBObjectType(rawValue: $0.type) ?? .table), $0.name) < (ObjectExport.sortKey(DBObjectType(rawValue: $1.type) ?? .table), $1.name)
        }
        for item in sorted {
            await progress?(item.name)
            out += "\n-- \(item.type) \(item.name)\n"
            if let sync = item.syncScript {
                out += sync + "\n"
            } else if let o = item.object {
                out += try await ObjectExport.ddl(o, options: options, in: s) + "\n"
            }
        }
        let data = items.filter { $0.includeData && $0.type == "TABLE" }
        for owner in Set(data.map(\.owner)).sorted() {
            let byName = Dictionary(data.filter { $0.owner == owner }.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            let ordered = try await TableTransfer.orderByForeignKeys(Array(byName.keys), owner: owner, in: s)
            var o = TableExportOptions()
            for t in ordered.compactMap({ byName[$0] }) {
                o.whereClause = t.whereClause
                await progress?(t.name)
                out += "\n-- " + L10n.tr("Dane \(t.name)") + "\n"
                out += try await TableTransfer.sqlInserts([t.name], owner: owner, options: o, in: s)
            }
        }
        return out + "\ncommit;\nset define on\n"
    }
}

extension Workspace {
    /// Koszyk bieżący (Tools › Cart) — wspólny dla Database Diff, Object Browser i komend.
    public var cartURL: URL? { dataDirectory?.appendingPathComponent("cart.json") }

    public func loadCart() -> DeploymentCart {
        guard let u = cartURL, let d = try? Data(contentsOf: u), let c = try? DeploymentCart.decode(d) else { return DeploymentCart(name: L10n.tr("Koszyk")) }
        return c
    }

    public func saveCart(_ c: DeploymentCart) throws {
        guard let u = cartURL else { return }
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try c.encoded().write(to: u, options: .atomic)
    }
}
