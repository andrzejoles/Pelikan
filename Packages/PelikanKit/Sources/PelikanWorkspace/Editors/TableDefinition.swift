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
        /// Sposób generowania kolumny identity: `ALWAYS`, `BY DEFAULT`, `BY DEFAULT ON NULL` (ze słownika — ALL_TAB_IDENTITY_COLS).
        public var identityGeneration = "BY DEFAULT ON NULL"
        /// Krok sekwencji identity (INCREMENT BY); puste — domyślny (1).
        public var identityIncrement = ""
        public var comment = ""
        /// Domena SQL kolumny (23ai, `WŁAŚCICIEL.NAZWA`) i adnotacje (PD-OED-003).
        public var domain = ""
        public var annotations: [Annotation] = []
        /// Kolumna niewidoczna (INVISIBLE, 12c) — PD-OED-002.
        public var invisible = false

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
        /// Podpartycje HASH (szablon przy tworzeniu): kolumny i liczba podpartycji w każdej partycji (0 — bez).
        public var subpartitionColumns: [String] = []
        public var subpartitionCount = 0
        public init(method: Method, columns: [String]) { self.method = method; self.columns = columns }
    }

    public struct Partition: Sendable, Hashable {
        public var name: String
        /// RANGE: wartości VALUES LESS THAN, LIST: VALUES, HASH: puste.
        public var values: String
        /// Nazwa w bazie (istniejąca partycja) — zmiana nazwy i usuwanie; nil — nowa.
        public var originalName: String?
        public init(name: String, values: String = "", originalName: String? = nil) { self.name = name; self.values = values; self.originalName = originalName }
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
        /// Kompresja klucza (PD-OED-004): "" — brak, liczba — COMPRESS n (kolumny prefiksu), `ADVANCED LOW` / `ADVANCED HIGH`.
        public var compression = ""
        public var reverse = false
        /// Indeks lokalny tabeli partycjonowanej (LOCAL).
        public var local = false
        public var pctFree = ""

        public init(name: String, columns: [String]) { self.name = name; self.columns = columns }
    }

    /// Parametry składowania (PD-OED-001): puste pola — domyślne serwera.
    public struct Storage: Sendable, Hashable {
        public enum Compression: String, Sendable, Hashable, CaseIterable { case none = "", basic = "BASIC", advanced = "ADVANCED" }
        public var pctFree = ""
        public var iniTrans = ""
        /// INITIAL / NEXT w bajtach albo z jednostką (np. 64K, 1M).
        public var initial = ""
        public var next = ""
        public var logging = true
        public var compression: Compression = .none
        public init() {}
    }

    /// Tabela zewnętrzna (ORGANIZATION EXTERNAL) — PD-OED-001.
    public struct External: Sendable, Hashable {
        /// ORACLE_LOADER, ORACLE_DATAPUMP, ORACLE_HDFS, ORACLE_HIVE, ORACLE_BIGDATA.
        public var driver = "ORACLE_LOADER"
        public var directory = ""
        public var accessParameters = ""
        public var locations: [String] = []
        /// REJECT LIMIT: liczba albo UNLIMITED; puste — domyślne (0).
        public var rejectLimit = "UNLIMITED"
        public init(directory: String = "", locations: [String] = []) { self.directory = directory; self.locations = locations }
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
    /// Składowanie, klaster, tabela zewnętrzna, tabela obiektowa (PD-OED-001/002); klaster i typ — tylko przy tworzeniu.
    public var storage = Storage()
    public var cluster = ""
    public var clusterColumns: [String] = []
    public var external: External?
    /// Tabela obiektowa: `CREATE TABLE … OF typ` (kolumny z typu).
    public var objectType = ""
    /// Recreate table (PD-OED-001): zmiany przez odtworzenie tabeli z przeniesieniem danych zamiast ALTER.
    public var recreate = false
    /// Dla odtworzenia: DDL wyzwalaczy tabeli i kluczy obcych innych tabel wskazujących tę tabelę.
    public var triggerDDL: [String] = []
    public var referencingForeignKeys: [String] = []

    public init(owner: String, name: String) { self.owner = owner; self.name = name }

    public var isNew: Bool { originalName == nil }
}

/// Wczytanie definicji ze słownika i generowanie DDL (CREATE dla nowej tabeli, ALTER — różnica dla istniejącej).
public enum TableDDL {
    /// Identyfikator w DDL: bez cudzysłowu, gdy to zwykła nazwa wielkimi literami.
    public static func q(_ name: String) -> String { ResultExporter.identifier(name) }

    static func literal(_ s: String) -> String { ResultExporter.quote(s) }

    static func qualified(_ d: TableDefinition, _ name: String? = nil) -> String { q(d.owner) + "." + q(name ?? d.name) }

    // MARK: Wczytanie

    @MainActor
    public static func load(owner: String, name: String, metadata m: MetadataProvider) async throws -> TableDefinition {
        let s = try await m.session()
        let b = [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(name))]
        var d = TableDefinition(owner: owner, name: name)
        d.originalName = name
        // Tabele obiektowe są w ALL_OBJECT_TABLES (nie w ALL_TABLES) — PD-OED-002.
        var found: [OracleValue]?
        for view in ["all_tables", "all_object_tables"] {
            let (_, t) = try await s.queryAll("""
                select t.tablespace_name, t.temporary, t.duration, t.iot_type, c.comments, t.pct_free, t.ini_trans, t.initial_extent,
                       t.next_extent, t.logging, t.compression, t.compress_for, t.cluster_name, \(view == "all_tables" ? "null, null" : "t.table_type_owner, t.table_type")
                from \(view) t left join all_tab_comments c on c.owner = t.owner and c.table_name = t.table_name
                where t.owner = :o and t.table_name = :n
                """, binds: b, limit: 1)
            if let r = t.first { found = r; break }
        }
        guard let tr = found else { throw CommandError.invalidArgument("object", L10n.tr("nie znaleziono tabeli \(owner).\(name)")) }
        d.tablespace = tr[0].displayText ?? ""
        d.temporary = tr[1].displayText == "Y"
        d.preserveRows = tr[2].displayText == "SYS$SESSION"
        d.indexOrganized = tr[3].displayText == "IOT"
        d.comment = tr[4].displayText ?? ""
        d.storage.pctFree = tr[5].displayText ?? ""
        d.storage.iniTrans = tr[6].displayText ?? ""
        d.storage.initial = tr[7].displayText ?? ""
        d.storage.next = tr[8].displayText ?? ""
        d.storage.logging = tr[9].displayText != "NO"
        if tr[10].displayText == "ENABLED" {
            d.storage.compression = (tr[11].displayText ?? "").contains("ADVANCED") || tr[11].displayText == "OLTP" ? .advanced : .basic
        }
        d.cluster = tr[12].displayText ?? ""
        if let typeName = tr[14].displayText { d.objectType = (tr[13].displayText.map { q($0) + "." } ?? "") + q(typeName) }
        if !d.cluster.isEmpty {
            let (_, cc) = try await s.queryAll("""
                select tab_column_name from all_clu_columns where owner = :o and table_name = :n order by clu_column_name
                """, binds: b, limit: 100)
            d.clusterColumns = cc.compactMap { $0.first?.displayText }
        }
        // Tabela zewnętrzna: sterownik, katalog, parametry dostępu, pliki.
        if let (_, ext) = try? await s.queryAll("""
            select type_name, default_directory_name, access_parameters, reject_limit from all_external_tables where owner = :o and table_name = :n
            """, binds: b, limit: 1), let e = ext.first {
            var x = TableDefinition.External(directory: e[1].displayText ?? "")
            x.driver = e[0].displayText ?? x.driver
            x.accessParameters = (e[2].displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            x.rejectLimit = e[3].displayText ?? ""
            let (_, loc) = (try? await s.queryAll("select location from all_external_locations where owner = :o and table_name = :n",
                                                   binds: b, limit: 1000)) ?? ([], [])
            x.locations = loc.compactMap { $0.first?.displayText }
            d.external = x
        }
        let (_, cols) = try await s.queryAll("""
            select c.column_name, c.data_type, c.char_length, c.char_used, c.data_precision, c.data_scale, c.data_length, c.nullable,
                   c.data_default_vc, c.default_on_null, c.identity_column, c.virtual_column, cc.comments, c.hidden_column
            from all_tab_cols c left join all_col_comments cc on cc.owner = c.owner and cc.table_name = c.table_name and cc.column_name = c.column_name
            where c.owner = :o and c.table_name = :n and (c.hidden_column = 'NO' or c.user_generated = 'YES')
            order by c.column_id nulls last, c.internal_column_id
            """, binds: b, limit: 10_000)
        d.columns = cols.map { r in
            var c = TableDefinition.Column(name: r[0].displayText ?? "", type: typeText(r), nullable: r[7].displayText != "N")
            c.originalName = c.name
            let def = (r[8].displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            c.defaultOnNull = r[9].displayText == "YES"
            c.identity = r[10].displayText == "YES"
            if r[11].displayText == "YES" { c.virtualExpression = def } else if !c.identity { c.defaultValue = def }
            c.comment = r[12].displayText ?? ""
            // Kolumna niewidoczna: ukryta, ale utworzona przez użytkownika (bez COLUMN_ID).
            c.invisible = r[13].displayText == "YES"
            return c
        }
        // Kolumna identity: ALWAYS / BY DEFAULT [ON NULL] i krok — do odtworzenia przy Recreate table.
        if d.columns.contains(where: \.identity), let (_, ids) = try? await s.queryAll("""
            select column_name, generation_type, identity_options from all_tab_identity_cols where owner = :o and table_name = :n
            """, binds: b, limit: 10) {
            for r in ids {
                guard let i = d.columns.firstIndex(where: { $0.name == r[0].displayText }) else { continue }
                d.columns[i].identityGeneration = identityGeneration(r[1].displayText ?? "", onNull: d.columns[i].defaultOnNull)
                d.columns[i].identityIncrement = identityIncrement(r[2].displayText ?? "")
            }
        }
        let (_, cons) = try await s.queryAll("""
            select c.constraint_name, c.constraint_type, c.search_condition_vc, c.status, c.delete_rule, c.generated,
                   (select listagg(cc.column_name, ',') within group (order by cc.position) from all_cons_columns cc
                     where cc.owner = c.owner and cc.constraint_name = c.constraint_name),
                   r.table_name,
                   (select listagg(rc.column_name, ',') within group (order by rc.position) from all_cons_columns rc
                     where rc.owner = c.r_owner and rc.constraint_name = c.r_constraint_name),
                   r.owner
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
                    // Tabela w innym schemacie — nazwa kwalifikowana (inaczej DDL wskazałby schemat edytowanej tabeli).
                    let rTable = r[7].displayText ?? "", rOwner = r[9].displayText ?? owner
                    k.referencedTable = rOwner == owner && !rTable.contains(".") ? rTable : q(rOwner) + "." + q(rTable)
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
                      from all_ind_columns ic where ic.index_owner = i.owner and ic.index_name = i.index_name), i.owner,
                   i.compression, i.prefix_length, i.pct_free,
                   (select p.locality from all_part_indexes p where p.owner = i.owner and p.index_name = i.index_name)
            from all_indexes i
            where i.table_owner = :o and i.table_name = :n
              and not exists (select 1 from all_constraints c where c.owner = i.table_owner and c.index_name = i.index_name and c.constraint_type in ('P', 'U'))
              and i.index_type not in ('LOB', 'IOT - TOP')
            order by i.index_name
            """, binds: b, limit: 10_000)
        for r in idx {
            // Nazwy kolumn w składni DDL (małe litery, słowa zastrzeżone — w cudzysłowie); wyrażenia podstawiane niżej bez zmian.
            var columns = (r[5].displayText ?? "").components(separatedBy: "|").map { c in
                c.isEmpty ? c : c.hasSuffix(" DESC") ? q(String(c.dropLast(5))) + " DESC" : q(c)
            }
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
            x.reverse = (r[2].displayText ?? "").hasSuffix("/REV")
            let comp = r[7].displayText ?? ""
            x.compression = comp.hasPrefix("ADVANCED") ? comp : comp == "ENABLED" ? (r[8].displayText ?? "") : ""
            x.pctFree = r[9].displayText ?? ""
            x.local = r[10].displayText == "LOCAL"
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
        // Partycje istniejącej tabeli (PD-OED-006): metoda, kolumny klucza i partycje z wartościami granicznymi.
        if let (_, pt) = try? await s.queryAll("select partitioning_type, nvl(interval, '') from all_part_tables where owner = :o and table_name = :n", binds: b),
           let row = pt.first, let method = TableDefinition.Partitioning.Method(rawValue: row[0].displayText ?? "") {
            let (_, keys) = (try? await s.queryAll("""
                select column_name from all_part_key_columns where owner = :o and name = :n and object_type = 'TABLE' order by column_position
                """, binds: b)) ?? ([], [])
            var p = TableDefinition.Partitioning(method: method, columns: keys.compactMap { $0[0].displayText })
            p.interval = row[1].displayText ?? ""
            let (_, parts) = (try? await s.queryAll("""
                select partition_name, high_value from all_tab_partitions where table_owner = :o and table_name = :n order by partition_position
                """, binds: b, limit: 100_000)) ?? ([], [])
            p.partitions = parts.map { TableDefinition.Partition(name: $0[0].displayText ?? "", values: $0[1].displayText ?? "", originalName: $0[0].displayText) }
            d.partitioning = p
        }
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
        // Klucze obce innych tabel wskazujące tę tabelę (do odtworzenia po Recreate table).
        let (_, refs) = (try? await s.queryAll("""
            select c.owner, c.table_name, c.constraint_name, c.delete_rule,
                   (select listagg(cc.column_name, ',') within group (order by cc.position) from all_cons_columns cc
                     where cc.owner = c.owner and cc.constraint_name = c.constraint_name),
                   (select listagg(rc.column_name, ',') within group (order by rc.position) from all_cons_columns rc
                     where rc.owner = r.owner and rc.constraint_name = r.constraint_name)
            from all_constraints c join all_constraints r on r.owner = c.r_owner and r.constraint_name = c.r_constraint_name
            where c.constraint_type = 'R' and r.owner = :o and r.table_name = :n and not (c.owner = :o and c.table_name = :n)
            order by 1, 2, 3
            """, binds: b, limit: 10_000)) ?? ([], [])
        d.referencingForeignKeys = refs.map { r in
            let cols = (r[4].displayText ?? "").split(separator: ",").map { q(String($0)) }.joined(separator: ", ")
            let rcols = (r[5].displayText ?? "").split(separator: ",").map { q(String($0)) }.joined(separator: ", ")
            let rule = r[3].displayText ?? ""
            return "ALTER TABLE \(q(r[0].displayText ?? "")).\(q(r[1].displayText ?? "")) ADD CONSTRAINT \(q(r[2].displayText ?? "")) FOREIGN KEY (\(cols)) "
                + "REFERENCES \(q(owner)).\(q(name)) (\(rcols))" + (rule == "NO ACTION" || rule.isEmpty ? "" : " ON DELETE \(rule)")
        }
        return d
    }

    /// DDL wyzwalaczy tabeli (DBMS_METADATA) — do odtworzenia po Recreate table.
    @MainActor
    public static func triggerDDL(_ d: TableDefinition, metadata m: MetadataProvider) async throws -> [String] {
        var out: [String] = []
        for trg in d.triggers {
            var text = try await m.ddl(of: DBObject(owner: d.owner, name: trg.name, type: .trigger))
            // DBMS_METADATA kończy wyzwalacz `/` i dodaje ALTER TRIGGER … ENABLE — jedno polecenie PL/SQL na wyzwalacz.
            if let r = text.range(of: #"\n\s*/\s*(\n|$)"#, options: .regularExpression) { text = String(text[..<r.lowerBound]) }
            out.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            if !trg.enabled { out.append("ALTER TRIGGER \(q(d.owner)).\(q(trg.name)) DISABLE") }
        }
        return out
    }

    /// Kolumny i klucz obcy do tabeli wskazywanej (Add foreign key columns, PD-OED-002): kolumny klucza głównego
    /// wskazywanej tabeli z typami; nazwy kolumn jak w tabeli wskazywanej (albo z przedrostkiem, gdy już istnieją).
    @MainActor
    public static func foreignKeyColumns(for d: TableDefinition, referencing spec: String, metadata m: MetadataProvider) async throws
        -> (columns: [TableDefinition.Column], key: TableDefinition.Key) {
        let parts = spec.split(separator: ".").map { $0.hasPrefix("\"") ? String($0.dropFirst().dropLast()) : $0.uppercased() }
        let rOwner = parts.count > 1 ? parts[0] : d.owner, rTable = parts.last ?? spec.uppercased()
        let s = try await m.session()
        let (_, rows) = try await s.queryAll("""
            select c.column_name, c.data_type, c.char_length, c.char_used, c.data_precision, c.data_scale, c.data_length
            from all_constraints k join all_cons_columns kc on kc.owner = k.owner and kc.constraint_name = k.constraint_name
            join all_tab_columns c on c.owner = k.owner and c.table_name = k.table_name and c.column_name = kc.column_name
            where k.owner = :o and k.table_name = :n and k.constraint_type = 'P' order by kc.position
            """, binds: [BindVariable(name: "o", value: .text(rOwner)), BindVariable(name: "n", value: .text(rTable))], limit: 100)
        guard !rows.isEmpty else { throw CommandError.notAvailable(L10n.tr("Tabela \(rOwner).\(rTable) nie ma klucza głównego")) }
        let existing = Set(d.columns.map(\.name))
        let cols = rows.map { r -> TableDefinition.Column in
            let n = r[0].displayText ?? ""
            let name = existing.contains(n) ? String((rTable + "_" + n).prefix(128)) : n
            return TableDefinition.Column(name: name, type: typeText(r))
        }
        var key = TableDefinition.Key(name: String((d.name + "_" + rTable + "_FK").prefix(128)), kind: .foreign, columns: cols.map(\.name))
        key.referencedTable = rOwner == d.owner ? rTable : "\(q(rOwner)).\(q(rTable))"
        key.referencedColumns = rows.compactMap { $0[0].displayText }
        return (cols, key)
    }

    /// Sposób generowania identity ze słownika (GENERATION_TYPE i DEFAULT_ON_NULL).
    static func identityGeneration(_ type: String, onNull: Bool) -> String {
        type == "ALWAYS" ? "ALWAYS" : onNull ? "BY DEFAULT ON NULL" : "BY DEFAULT"
    }

    /// Krok sekwencji z IDENTITY_OPTIONS (`START WITH: 1, INCREMENT BY: 10, …`); "" — domyślny (1).
    static func identityIncrement(_ options: String) -> String {
        guard let r = options.range(of: #"INCREMENT BY: *-?[0-9]+"#, options: .regularExpression) else { return "" }
        let n = options[r].split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return n == "1" ? "" : n
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
        if new.recreate { return recreate(from: old, to: new) }
        var out: [String] = []
        let table = qualified(new, old.name)
        if old.name != new.name {
            out.append("ALTER TABLE \(table) RENAME TO \(q(new.name))")
        }
        let t = qualified(new)
        // Więzy i indeksy usunięte albo zmienione (usunięcie i utworzenie) — przed usunięciem kolumn: kolumna usuwana
        // razem z więzem wielokolumnowym dawałaby ORA-12991.
        let sameKey: (TableDefinition.Key, TableDefinition.Key) -> Bool = {
            $0.kind == $1.kind && $0.columns == $1.columns && $0.referencedTable == $1.referencedTable && $0.referencedColumns == $1.referencedColumns && $0.onDelete == $1.onDelete
        }
        let sameIndex: (TableDefinition.Index, TableDefinition.Index) -> Bool = {
            $0.kind == $1.kind && $0.columns == $1.columns && $0.tablespace == $1.tablespace && $0.compression == $1.compression
                && $0.reverse == $1.reverse && $0.local == $1.local && $0.pctFree == $1.pctFree
        }
        func dropped<T>(_ o: [T], _ n: [T], name: (T) -> String, orig: (T) -> String?, same: (T, T) -> Bool) -> [String] {
            o.filter { x in
                guard let now = n.first(where: { orig($0) == name(x) }) else { return true }
                return !same(x, now)
            }.map(name)
        }
        for k in dropped(old.keys, new.keys, name: \.name, orig: \.originalName, same: sameKey) { out.append("ALTER TABLE \(t) DROP CONSTRAINT \(q(k))") }
        for c in dropped(old.checks, new.checks, name: \.name, orig: \.originalName, same: { $0.condition == $1.condition }) {
            out.append("ALTER TABLE \(t) DROP CONSTRAINT \(q(c))")
        }
        for x in dropped(old.indexes, new.indexes, name: \.name, orig: \.originalName, same: sameIndex) { out.append("DROP INDEX \(q(new.owner)).\(q(x))") }
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
        // Kolumny niewidoczne (PD-OED-002).
        for c in new.columns {
            guard let orig = c.originalName, let before = old.columns.first(where: { $0.name == orig }), before.invisible != c.invisible else { continue }
            out.append("ALTER TABLE \(t) MODIFY (\(q(c.name)) \(c.invisible ? "INVISIBLE" : "VISIBLE"))")
        }
        out += storageChanges(old, new, table: t)
        // Uprawnienia: odebrane, nadane, zmiana opcji nadawania (REVOKE + GRANT).
        let newGrants = Dictionary(new.grants.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldGrants = Dictionary(old.grants.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for g in old.grants where newGrants[g.id] == nil || newGrants[g.id]?.grantable != g.grantable {
            out.append("REVOKE \(g.privilege.uppercased()) ON \(t) FROM \(q(g.grantee))")
        }
        for g in new.grants where oldGrants[g.id] == nil || oldGrants[g.id]?.grantable != g.grantable { out.append(grantStatement(g, table: t)) }
        // Więzy i indeksy: zmienione definicje — utworzenie (usunięte wyżej); tylko nazwa — RENAME; stan — ENABLE/DISABLE.
        func constraintsDiff<T>(_ o: [T], _ n: [T], name: (T) -> String, orig: (T) -> String?, same: (T, T) -> Bool, enabled: (T) -> Bool,
                                add: (T) -> String) {
            for x in n {
                guard let on = orig(x), let before = o.first(where: { name($0) == on }), same(before, x) else { out.append(add(x)); continue }
                if on != name(x) { out.append("ALTER TABLE \(t) RENAME CONSTRAINT \(q(on)) TO \(q(name(x)))") }
                if enabled(before) != enabled(x) { out.append("ALTER TABLE \(t) \(enabled(x) ? "ENABLE" : "DISABLE") CONSTRAINT \(q(name(x)))") }
            }
        }
        constraintsDiff(old.keys, new.keys, name: \.name, orig: \.originalName, same: sameKey,
                        enabled: \.enabled, add: { "ALTER TABLE \(t) ADD " + keyClause($0, owner: new.owner) })
        constraintsDiff(old.checks, new.checks, name: \.name, orig: \.originalName, same: { $0.condition == $1.condition }, enabled: \.enabled,
                        add: { "ALTER TABLE \(t) ADD " + checkClause($0) })
        for x in new.indexes {
            guard let on = x.originalName, let before = old.indexes.first(where: { $0.name == on }), sameIndex(before, x) else {
                out.append(createIndex(x, table: new)); continue
            }
            if on != x.name { out.append("ALTER INDEX \(q(new.owner)).\(q(on)) RENAME TO \(q(x.name))") }
            if before.invisible != x.invisible { out.append("ALTER INDEX \(q(new.owner)).\(q(x.name)) \(x.invisible ? "INVISIBLE" : "VISIBLE")") }
        }
        out += partitionChanges(old.partitioning, new.partitioning, table: t)
        return out
    }

    /// Partycje istniejącej tabeli (PD-OED-006): usunięte — DROP PARTITION, nowa nazwa — RENAME PARTITION, nowe — ADD
    /// PARTITION (RANGE/LIST z wartościami, HASH — ADD PARTITION bez wartości). Zmiana metody albo klucza — tylko przez Recreate.
    static func partitionChanges(_ old: TableDefinition.Partitioning?, _ new: TableDefinition.Partitioning?, table t: String) -> [String] {
        guard let old, let new, old.method == new.method, old.columns == new.columns else { return [] }
        var out: [String] = []
        let kept = Set(new.partitions.compactMap(\.originalName))
        for x in old.partitions where !kept.contains(x.name) { out.append("ALTER TABLE \(t) DROP PARTITION \(q(x.name))") }
        for x in new.partitions {
            if let on = x.originalName {
                if on != x.name { out.append("ALTER TABLE \(t) RENAME PARTITION \(q(on)) TO \(q(x.name))") }
                continue
            }
            switch new.method {
            case .range: out.append("ALTER TABLE \(t) ADD PARTITION \(q(x.name)) VALUES LESS THAN (\(x.values))")
            case .list: out.append("ALTER TABLE \(t) ADD PARTITION \(q(x.name)) VALUES (\(x.values))")
            case .hash: out.append("ALTER TABLE \(t) ADD PARTITION \(q(x.name))")
            }
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
        // Więzy w CREATE TABLE (tabela IOT wymaga tu klucza głównego); tabela zewnętrzna nie ma więzów.
        if d.external == nil {
            body += d.keys.map { keyClause($0, owner: d.owner) }
            body += d.checks.map { checkClause($0) }
        }
        var sql: String
        if !d.objectType.isEmpty {
            // Tabela obiektowa (PD-OED-002): kolumny z typu, więzy w nawiasie.
            sql = "CREATE TABLE \(t) OF \(d.objectType)"
            let cons = d.keys.map { keyClause($0, owner: d.owner) } + d.checks.map { checkClause($0) }
            if !cons.isEmpty { sql += " (\n  " + cons.joined(separator: ",\n  ") + "\n)" }
        } else {
            sql = "CREATE \(d.temporary ? "GLOBAL TEMPORARY " : "")TABLE \(t) (\n  " + body.joined(separator: ",\n  ") + "\n)"
        }
        if d.temporary { sql += "\nON COMMIT \(d.preserveRows ? "PRESERVE" : "DELETE") ROWS" }
        if let e = d.external {
            sql += "\n" + externalClause(e)
            var out = [sql]
            if !d.comment.isEmpty { out.append("COMMENT ON TABLE \(t) IS \(literal(d.comment))") }
            for c in d.columns where !c.comment.isEmpty { out.append("COMMENT ON COLUMN \(t).\(q(c.name)) IS \(literal(c.comment))") }
            out += d.grants.map { grantStatement($0, table: t) }
            return out
        }
        if d.indexOrganized, !d.temporary { sql += "\nORGANIZATION INDEX" }
        if !d.cluster.isEmpty, !d.temporary {
            // Tabela w klastrze: składowanie z klastra (bez przestrzeni i parametrów składowania).
            sql += "\nCLUSTER " + d.cluster.split(separator: ".").map { q(String($0)) }.joined(separator: ".") + " (" + d.clusterColumns.map(q).joined(separator: ", ") + ")"
        } else {
            if !d.tablespace.isEmpty, !d.temporary { sql += "\nTABLESPACE \(q(d.tablespace))" }
            if !d.temporary, let s = storageClause(d.storage) { sql += "\n" + s }
        }
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
        if !p.subpartitionColumns.isEmpty, p.subpartitionCount > 0 {
            s += " SUBPARTITION BY HASH (" + p.subpartitionColumns.map(q).joined(separator: ", ") + ") SUBPARTITIONS \(p.subpartitionCount)"
        }
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
        if c.invisible { s += " INVISIBLE" }
        if !c.virtualExpression.isEmpty {
            s += " GENERATED ALWAYS AS (\(c.virtualExpression)) VIRTUAL"
        } else if c.identity {
            s += " GENERATED \(c.identityGeneration) AS IDENTITY" + (c.identityIncrement.isEmpty ? "" : " (INCREMENT BY \(c.identityIncrement))")
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
        if x.local { s += " LOCAL" }
        if !x.pctFree.isEmpty { s += " PCTFREE \(x.pctFree)" }
        if !x.tablespace.isEmpty { s += " TABLESPACE \(q(x.tablespace))" }
        let comp = x.compression.trimmingCharacters(in: .whitespaces).uppercased()
        if !comp.isEmpty, comp != "0" { s += " COMPRESS" + (comp == "ENABLED" ? "" : " " + comp) }
        if x.reverse, x.kind != .bitmap { s += " REVERSE" }
        if x.invisible { s += " INVISIBLE" }
        return s
    }

    /// Klauzula składowania tabeli (PCTFREE, INITRANS, STORAGE, LOGGING, kompresja); nil — wszystko domyślne.
    static func storageClause(_ st: TableDefinition.Storage) -> String? {
        var parts: [String] = []
        if !st.pctFree.isEmpty { parts.append("PCTFREE \(st.pctFree)") }
        if !st.iniTrans.isEmpty { parts.append("INITRANS \(st.iniTrans)") }
        let storage = [st.initial.isEmpty ? nil : "INITIAL \(st.initial)", st.next.isEmpty ? nil : "NEXT \(st.next)"].compactMap { $0 }
        if !storage.isEmpty { parts.append("STORAGE (" + storage.joined(separator: " ") + ")") }
        if !st.logging { parts.append("NOLOGGING") }
        if st.compression != .none { parts.append("ROW STORE COMPRESS \(st.compression.rawValue)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Zmiany składowania istniejącej tabeli: PCTFREE/INITRANS, NEXT, LOGGING, kompresja; przestrzeń — MOVE z indeksami.
    /// INITIAL nie zmienia się przez ALTER (tylko Recreate table).
    static func storageChanges(_ old: TableDefinition, _ new: TableDefinition, table t: String) -> [String] {
        guard new.external == nil, new.cluster.isEmpty, !new.temporary else { return [] }
        var out: [String] = []
        let a = old.storage, b = new.storage
        if old.tablespace != new.tablespace, !new.tablespace.isEmpty { out.append("ALTER TABLE \(t) MOVE TABLESPACE \(q(new.tablespace)) UPDATE INDEXES") }
        var phys: [String] = []
        if a.pctFree != b.pctFree, !b.pctFree.isEmpty { phys.append("PCTFREE \(b.pctFree)") }
        if a.iniTrans != b.iniTrans, !b.iniTrans.isEmpty { phys.append("INITRANS \(b.iniTrans)") }
        if !phys.isEmpty { out.append("ALTER TABLE \(t) " + phys.joined(separator: " ")) }
        if a.next != b.next, !b.next.isEmpty { out.append("ALTER TABLE \(t) STORAGE (NEXT \(b.next))") }
        if a.logging != b.logging { out.append("ALTER TABLE \(t) \(b.logging ? "LOGGING" : "NOLOGGING")") }
        if a.compression != b.compression {
            out.append("ALTER TABLE \(t) " + (b.compression == .none ? "NOCOMPRESS" : "ROW STORE COMPRESS \(b.compression.rawValue)"))
        }
        return out
    }

    /// ORGANIZATION EXTERNAL (…) REJECT LIMIT.
    static func externalClause(_ e: TableDefinition.External) -> String {
        var s = "ORGANIZATION EXTERNAL (\n  TYPE \(e.driver.uppercased())\n  DEFAULT DIRECTORY \(q(e.directory.uppercased()))"
        let ap = e.accessParameters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ap.isEmpty { s += "\n  ACCESS PARAMETERS (\n    \(ap)\n  )" }
        s += "\n  LOCATION (" + e.locations.map(literal).joined(separator: ", ") + ")\n)"
        if !e.rejectLimit.isEmpty { s += "\nREJECT LIMIT \(e.rejectLimit.uppercased())" }
        return s
    }

    /// Recreate table (PD-OED-001): kopia danych do tabeli roboczej, usunięcie tabeli (do kosza), utworzenie wg nowej
    /// definicji, przeniesienie wierszy (kolumny zachowane i przemianowane), wyzwalacze i klucze obce innych tabel.
    public static func recreate(from old: TableDefinition, to new: TableDefinition) -> [String] {
        let backupName = String(("PLK$" + old.name).prefix(128))
        let backup = q(old.owner) + "." + q(backupName)
        let oldTable = qualified(old)
        var out = ["CREATE TABLE \(backup) AS SELECT * FROM \(oldTable)", "DROP TABLE \(oldTable) CASCADE CONSTRAINTS"]
        // Kolumny przenoszone: istniejące wcześniej (wg nazwy pierwotnej), bez wirtualnych.
        func copied(_ c: TableDefinition.Column) -> Bool {
            guard let orig = c.originalName, c.virtualExpression.isEmpty else { return false }
            return old.columns.contains(where: { $0.name == orig && $0.virtualExpression.isEmpty })
        }
        let pairs: [(String, String)] = new.columns.filter(copied).map { (q($0.name), q($0.originalName ?? $0.name)) }
        let copyData = !pairs.isEmpty && new.external == nil
        var created = new
        created.recreate = false
        // Identity ALWAYS nie przyjmuje wartości w INSERT (ORA-32795) — na czas kopiowania BY DEFAULT.
        let identities = copyData ? new.columns.filter { $0.identity && copied($0) } : []
        for i in created.columns.indices where created.columns[i].identityGeneration == "ALWAYS" && identities.contains(where: { $0.id == created.columns[i].id }) {
            created.columns[i].identityGeneration = "BY DEFAULT"
        }
        out += create(created)
        if copyData {
            out.append("INSERT INTO \(qualified(new)) (" + pairs.map(\.0).joined(separator: ", ") + ") SELECT "
                       + pairs.map(\.1).joined(separator: ", ") + " FROM \(backup)")
        }
        // Licznik identity od największej przeniesionej wartości (inaczej kolejne wstawienia dają ORA-00001).
        for c in identities {
            out.append("ALTER TABLE \(qualified(new)) MODIFY (\(q(c.name)) GENERATED \(c.identityGeneration) AS IDENTITY (START WITH LIMIT VALUE"
                       + (c.identityIncrement.isEmpty ? "" : " INCREMENT BY \(c.identityIncrement)") + "))")
        }
        out += new.triggerDDL
        out += new.referencingForeignKeys
        out.append("DROP TABLE \(backup) PURGE")
        return out
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
        var new = new
        // Recreate table: wyzwalacze odtwarzane z DDL pobranego przed usunięciem tabeli.
        if new.recreate, new.triggerDDL.isEmpty, !new.triggers.isEmpty, let m = ws.metadata(for: connectionID) {
            new.triggerDDL = try await triggerDDL(new, metadata: m)
        }
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
