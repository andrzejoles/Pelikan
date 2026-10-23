import Foundation
import PelikanDB
import PelikanSQL

/// Definicja tabeli dla edytora (UG 9.1): ogólne, kolumny, klucze, warunki CHECK, indeksy.
public struct TableDefinition: Sendable, Hashable {
    public struct Column: Sendable, Hashable, Identifiable {
        public var id = UUID()
        /// Nazwa w bazie przed edycją (nil — nowa kolumna); zmiana nazwy = RENAME COLUMN.
        public var originalName: String?
        public var name: String
        /// Typ z rozmiarem, np. `VARCHAR2(30 CHAR)`, `NUMBER(10,2)`, `DATE`.
        public var type: String
        public var nullable = true
        public var defaultValue = ""
        public var defaultOnNull = false
        /// Wyrażenie kolumny wirtualnej (GENERATED ALWAYS AS (…)); puste — zwykła kolumna.
        public var virtualExpression = ""
        public var identity = false
        public var comment = ""
        /// Domena SQL kolumny (23ai, `WŁAŚCICIEL.NAZWA`) i adnotacje (PD-OED-003).
        public var domain = ""
        public var annotations: [Annotation] = []

        public init(name: String, type: String, nullable: Bool = true) {
            self.name = name; self.type = type; self.nullable = nullable
        }
    }

    /// Adnotacja schematu (23ai): nazwa i opcjonalna wartość.
    public struct Annotation: Sendable, Hashable, Identifiable {
        public var name: String
        public var value: String
        public var id: String { name.uppercased() }
        public init(name: String, value: String = "") { self.name = name; self.value = value }
    }

    /// Uprawnienie do tabeli (PD-OED-005).
    public struct Grant: Sendable, Hashable, Identifiable {
        public var grantee: String
        public var privilege: String
        public var grantable = false
        public var id: String { grantee.uppercased() + ":" + privilege.uppercased() }
        public init(grantee: String, privilege: String, grantable: Bool = false) { self.grantee = grantee; self.privilege = privilege; self.grantable = grantable }
    }

    /// Partycjonowanie nowej tabeli (PD-OED-006): metoda, kolumny i partycje (nazwa, wartości).
    public struct Partitioning: Sendable, Hashable {
        public enum Method: String, Sendable, Hashable, CaseIterable { case range = "RANGE", list = "LIST", hash = "HASH" }
        public var method: Method
        public var columns: [String]
        public var partitions: [Partition] = []
        /// Przedział dla partycjonowania automatycznego (INTERVAL) w RANGE, np. NUMTOYMINTERVAL(1,'MONTH').
        public var interval = ""
        public init(method: Method, columns: [String]) { self.method = method; self.columns = columns }
    }

    public struct Partition: Sendable, Hashable {
        public var name: String
        /// RANGE: wartości VALUES LESS THAN, LIST: VALUES, HASH: puste.
        public var values: String
        public init(name: String, values: String = "") { self.name = name; self.values = values }
    }

    public struct Trigger: Sendable, Hashable {
        public var name: String
        public var enabled: Bool
    }

    public struct Key: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable, CaseIterable { case primary = "P", unique = "U", foreign = "R" }
        public var id = UUID()
        public var originalName: String?
        public var name: String
        public var kind: Kind
        public var columns: [String]
        public var referencedTable = ""
        public var referencedColumns: [String] = []
        /// ON DELETE: "" (brak), CASCADE, SET NULL.
        public var onDelete = ""
        public var enabled = true

        public init(name: String, kind: Kind, columns: [String]) {
            self.name = name; self.kind = kind; self.columns = columns
        }
    }

    public struct Check: Sendable, Hashable, Identifiable {
        public var id = UUID()
        public var originalName: String?
        public var name: String
        public var condition: String
        public var enabled = true

        public init(name: String, condition: String) { self.name = name; self.condition = condition }
    }

    public struct Index: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable, CaseIterable { case normal, unique, bitmap }
        public var id = UUID()
        public var originalName: String?
        public var name: String
        public var kind: Kind = .normal
        /// Kolumny albo wyrażenia, z opcjonalnym DESC (`kolumna DESC`).
        public var columns: [String]
        public var tablespace = ""
        public var invisible = false

        public init(name: String, columns: [String]) { self.name = name; self.columns = columns }
    }

    public var owner: String
    public var name: String
    /// Nazwa przed edycją (nil — nowa tabela).
    public var originalName: String?
    public var tablespace = ""
    public var temporary = false
    /// Tabela tymczasowa: ON COMMIT PRESERVE ROWS (true) albo DELETE ROWS.
    public var preserveRows = false
    public var indexOrganized = false
    public var comment = ""
    public var columns: [Column] = []
    public var keys: [Key] = []
    public var checks: [Check] = []
    public var indexes: [Index] = []
    public var annotations: [Annotation] = []
    public var grants: [Grant] = []
    /// ROW ARCHIVAL (In-Database Archiving, PD-OED-012).
    public var rowArchival = false
    /// Partycjonowanie (tylko przy tworzeniu; istniejące — opis w `partitionInfo`).
    public var partitioning: Partitioning?
    public var partitionInfo = ""
    /// Wyzwalacze tabeli (nazwa, stan) — karta Wyzwalacze, włączanie przez Object Browser.
    public var triggers: [Trigger] = []

    public init(owner: String, name: String) { self.owner = owner; self.name = name }

    public var isNew: Bool { originalName == nil }
}

/// Wczytanie definicji ze słownika i generowanie DDL (CREATE dla nowej tabeli, ALTER — różnica dla istniejącej).
public enum TableDDL {
    /// Identyfikator w DDL: bez cudzysłowu, gdy to zwykła nazwa wielkimi literami.
    public static func q(_ name: String) -> String {
        let plain = name.range(of: #"^[A-Z][A-Z0-9_$#]*$"#, options: .regularExpression) != nil && !Keywords.reserved.contains(name)
        return plain ? name : "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func literal(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    static func qualified(_ d: TableDefinition, _ name: String? = nil) -> String { q(d.owner) + "." + q(name ?? d.name) }

    // MARK: Wczytanie

    @MainActor
    public static func load(owner: String, name: String, metadata m: MetadataProvider) async throws -> TableDefinition {
        let s = try await m.session()
        let b = [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(name))]
        var d = TableDefinition(owner: owner, name: name)
        d.originalName = name
        let (_, t) = try await s.queryAll("""
            select t.tablespace_name, t.temporary, t.duration, t.iot_type, c.comments
            from all_tables t left join all_tab_comments c on c.owner = t.owner and c.table_name = t.table_name
            where t.owner = :o and t.table_name = :n
            """, binds: b, limit: 1)
        guard let tr = t.first else { throw CommandError.invalidArgument("object", L10n.tr("nie znaleziono tabeli \(owner).\(name)")) }
        d.tablespace = tr[0].displayText ?? ""
        d.temporary = tr[1].displayText == "Y"
        d.preserveRows = tr[2].displayText == "SYS$SESSION"
        d.indexOrganized = tr[3].displayText == "IOT"
        d.comment = tr[4].displayText ?? ""
        let (_, cols) = try await s.queryAll("""
            select c.column_name, c.data_type, c.char_length, c.char_used, c.data_precision, c.data_scale, c.data_length, c.nullable,
                   c.data_default_vc, c.default_on_null, c.identity_column, c.virtual_column, cc.comments
            from all_tab_cols c left join all_col_comments cc on cc.owner = c.owner and cc.table_name = c.table_name and cc.column_name = c.column_name
            where c.owner = :o and c.table_name = :n and c.hidden_column = 'NO'
            order by c.column_id
            """, binds: b, limit: 10_000)
        d.columns = cols.map { r in
            var c = TableDefinition.Column(name: r[0].displayText ?? "", type: typeText(r), nullable: r[7].displayText != "N")
            c.originalName = c.name
            let def = (r[8].displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            c.defaultOnNull = r[9].displayText == "YES"
            c.identity = r[10].displayText == "YES"
            if r[11].displayText == "YES" { c.virtualExpression = def } else if !c.identity { c.defaultValue = def }
            c.comment = r[12].displayText ?? ""
            return c
        }
        let (_, cons) = try await s.queryAll("""
            select c.constraint_name, c.constraint_type, c.search_condition_vc, c.status, c.delete_rule, c.generated,
                   (select listagg(cc.column_name, ',') within group (order by cc.position) from all_cons_columns cc
                     where cc.owner = c.owner and cc.constraint_name = c.constraint_name),
                   r.table_name,
                   (select listagg(rc.column_name, ',') within group (order by rc.position) from all_cons_columns rc
                     where rc.owner = c.r_owner and rc.constraint_name = c.r_constraint_name)
            from all_constraints c left join all_constraints r on r.owner = c.r_owner and r.constraint_name = c.r_constraint_name
            where c.owner = :o and c.table_name = :n and c.constraint_type in ('P', 'U', 'R', 'C')
            order by decode(c.constraint_type, 'P', 1, 'U', 2, 'R', 3, 4), c.constraint_name
            """, binds: b, limit: 10_000)
        for r in cons {
            let cname = r[0].displayText ?? ""
            let type = r[1].displayText ?? ""
            let cols = (r[6].displayText ?? "").split(separator: ",").map(String.init)
            if type == "C" {
                let cond = r[2].displayText ?? ""
                // NOT NULL jako więz CHECK nadawany przez Oracle — to atrybut kolumny.
                if r[5].displayText == "GENERATED NAME", cond.range(of: #"^"?[A-Za-z0-9_$#]+"? IS NOT NULL$"#, options: .regularExpression) != nil { continue }
                var c = TableDefinition.Check(name: cname, condition: cond)
                c.originalName = cname
                c.enabled = r[3].displayText == "ENABLED"
                d.checks.append(c)
            } else if let kind = TableDefinition.Key.Kind(rawValue: type) {
                var k = TableDefinition.Key(name: cname, kind: kind, columns: cols)
                k.originalName = cname
                k.enabled = r[3].displayText == "ENABLED"
                if kind == .foreign {
                    k.referencedTable = r[7].displayText ?? ""
                    k.referencedColumns = (r[8].displayText ?? "").split(separator: ",").map(String.init)
                    let rule = r[4].displayText ?? ""
                    k.onDelete = rule == "NO ACTION" ? "" : rule
                }
                d.keys.append(k)
            }
        }
        let (_, idx) = try await s.queryAll("""
            select i.index_name, i.uniqueness, i.index_type, i.tablespace_name, i.visibility,
                   (select listagg(ic.column_name || case when ic.descend = 'DESC' then ' DESC' end, '|') within group (order by ic.column_position)
                      from all_ind_columns ic where ic.index_owner = i.owner and ic.index_name = i.index_name), i.owner
            from all_indexes i
            where i.table_owner = :o and i.table_name = :n
              and not exists (select 1 from all_constraints c where c.owner = i.table_owner and c.index_name = i.index_name and c.constraint_type in ('P', 'U'))
              and i.index_type not in ('LOB', 'IOT - TOP')
            order by i.index_name
            """, binds: b, limit: 10_000)
        for r in idx {
            var columns = (r[5].displayText ?? "").components(separatedBy: "|")
            // Indeksy funkcyjne i malejące: wyrażenia (LONG) z ALL_IND_EXPRESSIONS — osobne zapytanie, podstawienie po pozycji.
            if (r[2].displayText ?? "").contains("FUNCTION-BASED") {
                let (_, ex) = try await s.queryAll("""
                    select column_position, column_expression from all_ind_expressions where index_owner = :io and index_name = :i
                    """, binds: [BindVariable(name: "io", value: .text(r[6].displayText ?? owner)), BindVariable(name: "i", value: .text(r[0].displayText ?? ""))],
                    limit: 100)
                for e in ex {
                    guard let pos = Int(e[0].format(.default)), pos >= 1, pos <= columns.count else { continue }
                    let desc = columns[pos - 1].hasSuffix(" DESC")
                    columns[pos - 1] = (e[1].displayText ?? columns[pos - 1]) + (desc ? " DESC" : "")
                }
            }
            var x = TableDefinition.Index(name: r[0].displayText ?? "", columns: columns)
            x.originalName = x.name
            x.kind = (r[2].displayText ?? "").hasPrefix("BITMAP") ? .bitmap : r[1].displayText == "UNIQUE" ? .unique : .normal
            x.tablespace = r[3].displayText ?? ""
            x.invisible = r[4].displayText == "INVISIBLE"
            d.indexes.append(x)
        }
        // Uprawnienia (PD-OED-005), wyzwalacze (PD-OED-006), partycjonowanie (opis), ROW ARCHIVAL (PD-OED-012).
        let (_, grants) = (try? await s.queryAll("""
            select grantee, privilege, grantable from all_tab_privs where table_schema = :o and table_name = :n order by grantee, privilege
            """, binds: b, limit: 10_000)) ?? ([], [])
        d.grants = grants.map { TableDefinition.Grant(grantee: $0[0].displayText ?? "", privilege: $0[1].displayText ?? "", grantable: $0[2].displayText == "YES") }
        let (_, trg) = (try? await s.queryAll("select trigger_name, status from all_triggers where table_owner = :o and table_name = :n order by 1",
                                               binds: b, limit: 10_000)) ?? ([], [])
        d.triggers = trg.map { TableDefinition.Trigger(name: $0[0].displayText ?? "", enabled: $0[1].displayText == "ENABLED") }
        if let p = try? await s.scalar("""
            select partitioning_type || nvl2(subpartitioning_type, ' / ' || subpartitioning_type, '') || ', ' || partition_count
              from all_part_tables where owner = :o and table_name = :n
            """, binds: b) { d.partitionInfo = p }
        d.rowArchival = (try? await s.scalar("select count(*) from all_tab_cols where owner = :o and table_name = :n and column_name = 'ORA_ARCHIVE_STATE'",
                                             binds: b)) == "1"
        // Domeny i adnotacje (23ai, PD-OED-003) — na starszych bazach słownik ich nie ma (błąd pomijany).
        if let (_, dom) = try? await s.queryAll("""
            select column_name, domain_owner || '.' || domain_name from all_tab_cols where owner = :o and table_name = :n and domain_name is not null
            """, binds: b, limit: 10_000) {
            for r in dom { if let i = d.columns.firstIndex(where: { $0.name == r[0].displayText }) { d.columns[i].domain = r[1].displayText ?? "" } }
        }
        if let (_, ann) = try? await s.queryAll("""
            select column_name, annotation_name, annotation_value from all_annotations_usage
             where object_name = :n and object_type = 'TABLE' and domain_name is null order by annotation_name
            """, binds: [BindVariable(name: "n", value: .text(name))], limit: 10_000) {
            for r in ann {
                let a = TableDefinition.Annotation(name: r[1].displayText ?? "", value: r[2].displayText ?? "")
                if let col = r[0].displayText, let i = d.columns.firstIndex(where: { $0.name == col }) { d.columns[i].annotations.append(a) }
                else if r[0].displayText == nil { d.annotations.append(a) }
            }
        }
        return d
    }

    /// Typ kolumny w składni DDL ze słownika.
    static func typeText(_ r: [OracleValue]) -> String {
        let t = r[1].displayText ?? ""
        let charLen = r[2].displayText ?? "", charUsed = r[3].displayText ?? ""
        let prec = r[4].displayText, scale = r[5].displayText, len = r[6].displayText ?? ""
        switch t {
        case "VARCHAR2", "CHAR":
            return "\(t)(\(charLen)\(charUsed == "C" ? " CHAR" : " BYTE"))"
        case "NVARCHAR2", "NCHAR":
            return "\(t)(\(charLen))"
        case "RAW":
            return "RAW(\(len))"
        case "NUMBER":
            guard let p = prec else { return scale == "0" ? "INTEGER" : "NUMBER" }
            return scale == nil || scale == "0" ? "NUMBER(\(p))" : "NUMBER(\(p),\(scale!))"
        case "FLOAT":
            return prec.map { "FLOAT(\($0))" } ?? "FLOAT"
        default:
            return t
        }
    }

    // MARK: DDL

    /// Polecenia DDL zmieniające `old` w `new` (dla nowej tabeli — CREATE i dodatki).
    public static func statements(from old: TableDefinition?, to new: TableDefinition) -> [String] {
        guard let old, !new.isNew else { return create(new) }
        var out: [String] = []
        let table = qualified(new, old.name)
        if old.name != new.name {
            out.append("ALTER TABLE \(table) RENAME TO \(q(new.name))")
        }
        let t = qualified(new)
        // Kolumny: usunięte, zmienione nazwy, zmienione definicje, dodane.
        let kept = Set(new.columns.compactMap(\.originalName))
        for c in old.columns where !kept.contains(c.name) { out.append("ALTER TABLE \(t) DROP COLUMN \(q(c.name))") }
        for c in new.columns {
            guard let orig = c.originalName, let before = old.columns.first(where: { $0.name == orig }) else { continue }
            if orig != c.name { out.append("ALTER TABLE \(t) RENAME COLUMN \(q(orig)) TO \(q(c.name))") }
            var parts: [String] = []
            if before.type.uppercased() != c.type.uppercased(), c.virtualExpression.isEmpty { parts.append(c.type) }
            if before.defaultValue != c.defaultValue || before.defaultOnNull != c.defaultOnNull, c.virtualExpression.isEmpty, !c.identity {
                parts.append(c.defaultValue.isEmpty ? "DEFAULT NULL" : "DEFAULT\(c.defaultOnNull ? " ON NULL" : "") \(c.defaultValue)")
            }
            if before.nullable != c.nullable, !(c.defaultOnNull && !c.nullable) { parts.append(c.nullable ? "NULL" : "NOT NULL") }
            if !parts.isEmpty { out.append("ALTER TABLE \(t) MODIFY (\(q(c.name)) \(parts.joined(separator: " ")))") }
            if before.comment != c.comment { out.append("COMMENT ON COLUMN \(t).\(q(c.name)) IS \(literal(c.comment))") }
        }
        let added = new.columns.filter { $0.originalName == nil }
        if !added.isEmpty {
            out.append("ALTER TABLE \(t) ADD (" + added.map(columnClause).joined(separator: ", ") + ")")
            for c in added where !c.comment.isEmpty { out.append("COMMENT ON COLUMN \(t).\(q(c.name)) IS \(literal(c.comment))") }
        }
        if old.comment != new.comment { out.append("COMMENT ON TABLE \(t) IS \(literal(new.comment))") }
        // Domeny i adnotacje kolumn oraz tabeli (23ai).
        for c in new.columns {
            guard let orig = c.originalName, let before = old.columns.first(where: { $0.name == orig }) else { continue }
            if before.domain != c.domain {
                out.append(c.domain.isEmpty ? "ALTER TABLE \(t) MODIFY (\(q(c.name)) DROP DOMAIN)"
                           : "ALTER TABLE \(t) MODIFY (\(q(c.name)) DOMAIN " + c.domain.split(separator: ".").map { q(String($0)) }.joined(separator: ".") + ")")
            }
            out += annotationChanges(before.annotations, c.annotations) { "ALTER TABLE \(t) MODIFY (\(q(c.name)) \($0))" }
        }
        out += annotationChanges(old.annotations, new.annotations) { "ALTER TABLE \(t) \($0)" }
        if old.rowArchival != new.rowArchival { out.append("ALTER TABLE \(t) \(new.rowArchival ? "ROW ARCHIVAL" : "NO ROW ARCHIVAL")") }
        // Uprawnienia: odebrane, nadane, zmiana opcji nadawania (REVOKE + GRANT).
        let newGrants = Dictionary(new.grants.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldGrants = Dictionary(old.grants.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for g in old.grants where newGrants[g.id] == nil || newGrants[g.id]?.grantable != g.grantable {
            out.append("REVOKE \(g.privilege.uppercased()) ON \(t) FROM \(q(g.grantee))")
        }
        for g in new.grants where oldGrants[g.id] == nil || oldGrants[g.id]?.grantable != g.grantable { out.append(grantStatement(g, table: t)) }
        // Więzy i indeksy: zmienione definicje — usunięcie i utworzenie; tylko nazwa — RENAME; stan — ENABLE/DISABLE.
        func constraintsDiff<T>(_ o: [T], _ n: [T], name: (T) -> String, orig: (T) -> String?, same: (T, T) -> Bool, enabled: (T) -> Bool,
                                add: (T) -> String) {
            let keepNames = Set(n.compactMap(orig))
            for x in o where !keepNames.contains(name(x)) { out.append("ALTER TABLE \(t) DROP CONSTRAINT \(q(name(x)))") }
            for x in n {
                guard let on = orig(x), let before = o.first(where: { name($0) == on }) else { out.append(add(x)); continue }
                if !same(before, x) {
                    out.append("ALTER TABLE \(t) DROP CONSTRAINT \(q(on))")
                    out.append(add(x))
                    continue
                }
                if on != name(x) { out.append("ALTER TABLE \(t) RENAME CONSTRAINT \(q(on)) TO \(q(name(x)))") }
                if enabled(before) != enabled(x) { out.append("ALTER TABLE \(t) \(enabled(x) ? "ENABLE" : "DISABLE") CONSTRAINT \(q(name(x)))") }
            }
        }
        constraintsDiff(old.keys, new.keys, name: \.name, orig: \.originalName,
                        same: { $0.kind == $1.kind && $0.columns == $1.columns && $0.referencedTable == $1.referencedTable && $0.referencedColumns == $1.referencedColumns && $0.onDelete == $1.onDelete },
                        enabled: \.enabled, add: { "ALTER TABLE \(t) ADD " + keyClause($0, owner: new.owner) })
        constraintsDiff(old.checks, new.checks, name: \.name, orig: \.originalName, same: { $0.condition == $1.condition }, enabled: \.enabled,
                        add: { "ALTER TABLE \(t) ADD " + checkClause($0) })
        let keepIdx = Set(new.indexes.compactMap(\.originalName))
        for x in old.indexes where !keepIdx.contains(x.name) { out.append("DROP INDEX \(q(new.owner)).\(q(x.name))") }
        for x in new.indexes {
            guard let on = x.originalName, let before = old.indexes.first(where: { $0.name == on }) else { out.append(createIndex(x, table: new)); continue }
            if before.kind != x.kind || before.columns != x.columns || before.tablespace != x.tablespace {
                out.append("DROP INDEX \(q(new.owner)).\(q(on))")
                out.append(createIndex(x, table: new))
                continue
            }
            if on != x.name { out.append("ALTER INDEX \(q(new.owner)).\(q(on)) RENAME TO \(q(x.name))") }
            if before.invisible != x.invisible { out.append("ALTER INDEX \(q(new.owner)).\(q(x.name)) \(x.invisible ? "INVISIBLE" : "VISIBLE")") }
        }
        return out
    }

    /// Zmiany adnotacji: DROP usuniętych i zmienionych, ADD nowych i zmienionych.
    static func annotationChanges(_ old: [TableDefinition.Annotation], _ new: [TableDefinition.Annotation], wrap: (String) -> String) -> [String] {
        let o = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let n = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let drop = old.filter { n[$0.id] == nil || n[$0.id]?.value != $0.value }
        let add = new.filter { o[$0.id] == nil || o[$0.id]?.value != $0.value }
        var out: [String] = []
        if !drop.isEmpty { out.append(wrap(annotationsClause(drop.map { .init(name: $0.name) }, operation: "DROP"))) }
        if !add.isEmpty { out.append(wrap(annotationsClause(add, operation: "ADD"))) }
        return out
    }

    static func create(_ d: TableDefinition) -> [String] {
        let t = qualified(d)
        var body = d.columns.map(columnClause)
        // Więzy w CREATE TABLE (tabela IOT wymaga tu klucza głównego).
        body += d.keys.map { keyClause($0, owner: d.owner) }
        body += d.checks.map { checkClause($0) }
        var sql = "CREATE \(d.temporary ? "GLOBAL TEMPORARY " : "")TABLE \(t) (\n  " + body.joined(separator: ",\n  ") + "\n)"
        if d.temporary { sql += "\nON COMMIT \(d.preserveRows ? "PRESERVE" : "DELETE") ROWS" }
        if d.indexOrganized, !d.temporary { sql += "\nORGANIZATION INDEX" }
        if !d.tablespace.isEmpty, !d.temporary { sql += "\nTABLESPACE \(q(d.tablespace))" }
        if let p = d.partitioning, !d.temporary, !p.columns.isEmpty { sql += "\n" + partitionClause(p) }
        if d.rowArchival { sql += "\nROW ARCHIVAL" }
        if !d.annotations.isEmpty { sql += "\n" + annotationsClause(d.annotations) }
        var out = [sql]
        if !d.comment.isEmpty { out.append("COMMENT ON TABLE \(t) IS \(literal(d.comment))") }
        for c in d.columns where !c.comment.isEmpty { out.append("COMMENT ON COLUMN \(t).\(q(c.name)) IS \(literal(c.comment))") }
        out += d.indexes.map { createIndex($0, table: d) }
        out += d.grants.map { grantStatement($0, table: t) }
        return out
    }

    static func annotationsClause(_ a: [TableDefinition.Annotation], operation: String = "") -> String {
        "ANNOTATIONS (" + a.map { x in (operation.isEmpty ? "" : operation + " ") + q(x.name) + (x.value.isEmpty ? "" : " " + literal(x.value)) }
            .joined(separator: ", ") + ")"
    }

    static func partitionClause(_ p: TableDefinition.Partitioning) -> String {
        var s = "PARTITION BY \(p.method.rawValue) (" + p.columns.map(q).joined(separator: ", ") + ")"
        if p.method == .range, !p.interval.isEmpty { s += " INTERVAL (\(p.interval))" }
        if p.method == .hash, p.partitions.allSatisfy({ $0.values.isEmpty }), !p.partitions.isEmpty {
            return s + " (" + p.partitions.map { "PARTITION \(q($0.name))" }.joined(separator: ", ") + ")"
        }
        guard !p.partitions.isEmpty else { return s }
        let parts = p.partitions.map { x -> String in
            switch p.method {
            case .range: "PARTITION \(q(x.name)) VALUES LESS THAN (\(x.values))"
            case .list: "PARTITION \(q(x.name)) VALUES (\(x.values))"
            case .hash: "PARTITION \(q(x.name))"
            }
        }
        return s + " (\n  " + parts.joined(separator: ",\n  ") + "\n)"
    }

    static func grantStatement(_ g: TableDefinition.Grant, table: String) -> String {
        "GRANT \(g.privilege.uppercased()) ON \(table) TO \(q(g.grantee))" + (g.grantable ? " WITH GRANT OPTION" : "")
    }

    static func columnClause(_ c: TableDefinition.Column) -> String {
        var s = q(c.name) + " " + c.type
        if !c.virtualExpression.isEmpty {
            s += " GENERATED ALWAYS AS (\(c.virtualExpression)) VIRTUAL"
        } else if c.identity {
            s += " GENERATED BY DEFAULT ON NULL AS IDENTITY"
        } else if !c.defaultValue.isEmpty {
            s += " DEFAULT\(c.defaultOnNull ? " ON NULL" : "") \(c.defaultValue)"
        }
        if !c.nullable, !c.identity, !(c.defaultOnNull && !c.defaultValue.isEmpty) { s += " NOT NULL" }
        if !c.domain.isEmpty { s += " DOMAIN " + c.domain.split(separator: ".").map { q(String($0)) }.joined(separator: ".") }
        if !c.annotations.isEmpty { s += " " + annotationsClause(c.annotations) }
        return s
    }

    static func keyClause(_ k: TableDefinition.Key, owner: String) -> String {
        let cols = k.columns.map(q).joined(separator: ", ")
        var s = "CONSTRAINT \(q(k.name)) "
        switch k.kind {
        case .primary: s += "PRIMARY KEY (\(cols))"
        case .unique: s += "UNIQUE (\(cols))"
        case .foreign:
            let ref = k.referencedTable.contains(".") ? k.referencedTable : q(owner) + "." + q(k.referencedTable)
            s += "FOREIGN KEY (\(cols)) REFERENCES \(ref)"
            if !k.referencedColumns.isEmpty { s += " (\(k.referencedColumns.map(q).joined(separator: ", ")))" }
            if !k.onDelete.isEmpty { s += " ON DELETE \(k.onDelete)" }
        }
        if !k.enabled { s += " DISABLE" }
        return s
    }

    static func checkClause(_ c: TableDefinition.Check) -> String {
        "CONSTRAINT \(q(c.name)) CHECK (\(c.condition))" + (c.enabled ? "" : " DISABLE")
    }

    static func createIndex(_ x: TableDefinition.Index, table d: TableDefinition) -> String {
        let kind = x.kind == .unique ? "UNIQUE " : x.kind == .bitmap ? "BITMAP " : ""
        var s = "CREATE \(kind)INDEX \(q(d.owner)).\(q(x.name)) ON \(qualified(d)) (\(x.columns.joined(separator: ", ")))"
        if !x.tablespace.isEmpty { s += " TABLESPACE \(q(x.tablespace))" }
        if x.invisible { s += " INVISIBLE" }
        return s
    }
}

extension TableDDL {
    /// Wynik zastosowania: wykonane polecenia i błąd przy pierwszym niepowodzeniu (kolejne nie są wykonywane).
    public struct ApplyResult: Sendable {
        public var executed: [String]
        public var failed: String?
        public var error: String?
    }

    /// Wykonuje DDL zmian w sesji kompilacji po sprawdzeniu strażnika (tylko do odczytu / produkcja).
    @MainActor
    public static func apply(from old: TableDefinition?, to new: TableDefinition, in ws: Workspace, connectionID: UUID) async throws -> ApplyResult {
        let sql = statements(from: old, to: new)
        guard !sql.isEmpty else { return ApplyResult(executed: []) }
        try await ws.guardModification(sql, connectionID: connectionID)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: connectionID))
        var done: [String] = []
        for stmt in sql {
            do {
                _ = try await s.execute(stmt)
                done.append(stmt)
            } catch {
                ws.metadata(for: connectionID)?.refresh()
                return ApplyResult(executed: done, failed: stmt, error: error.localizedDescription)
            }
        }
        ws.metadata(for: connectionID)?.refresh()
        return ApplyResult(executed: done)
    }
}
