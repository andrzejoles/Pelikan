import Foundation
import PelikanDB
import PelikanSQL

/// Opcje eksportu tabel jako SQL Inserts (UG 24.4, PD-TOOL-003).
public struct TableExportOptions: Sendable, Codable, Hashable {
    public var drop = false
    public var create = false
    public var truncate = false
    public var delete = false
    public var disableTriggers = false
    public var disableForeignKeys = false
    public var includeStorage = false
    public var includePrivileges = false
    /// COMMIT co tyle wierszy (0 — tylko na końcu).
    public var commitEvery = 100
    /// Warunek WHERE dla wszystkich tabel (pusty — wszystkie wiersze).
    public var whereClause = ""
    /// LOB-y jako literały (TO_CLOB/TO_BLOB; większe niż limit literału — NULL z komentarzem) albo pomijane (NULL).
    public var includeLOBs = true
    public init() {}
}

/// Tabela w formacie własnym Pelikana (PD-TOOL-004): DDL, kolumny i wiersze z wartościami w postaci tekstowej.
public struct PelikanTableData: Sendable, Codable, Hashable {
    public struct Column: Sendable, Codable, Hashable { public var name: String; public var type: String }
    public var owner: String
    public var name: String
    public var ddl: String
    public var columns: [Column]
    /// Wartości: nil — NULL; tekst (liczby z kropką, daty `YYYY-MM-DD HH24:MI:SS.FF9`, RAW/BLOB w base64).
    public var rows: [[String?]]
}

public struct PelikanTableFile: Sendable, Codable, Hashable {
    public var format = "pelikan-tables"
    public var version = 1
    public var created: String
    public var tables: [PelikanTableData]
}

/// Opcje importu tabel (format własny, UG 24.5).
public struct TableImportOptions: Sendable, Codable, Hashable {
    public var create = false
    public var truncate = false
    public var delete = false
    public var disableTriggers = false
    public var disableForeignKeys = false
    public var commitEvery = 100
    public init() {}
}

/// Eksport i import tabel (PD-TOOL-003…006).
public enum TableTransfer {
    static func q(_ s: String) -> String { ResultExporter.identifier(s) }

    /// Tabele schematu (bez tabel zagnieżdżonych, tymczasowych systemowych i kosza).
    public static func tables(owner: String, in s: any DatabaseSession) async throws -> [String] {
        let (_, rows) = try await s.queryAll("""
            select table_name from all_tables where owner = :o and nested = 'NO' and table_name not like 'BIN$%'
               and (iot_type is null or iot_type = 'IOT') and secondary = 'N' order by table_name
            """, binds: [BindVariable(name: "o", value: .text(owner))], limit: 100_000)
        return rows.compactMap { $0.first?.displayText }
    }

    /// Kolejność wg kluczy obcych: tabele nadrzędne przed podrzędnymi (cykle — kolejność alfabetyczna).
    public static func orderByForeignKeys(_ tables: [String], owner: String, in s: any DatabaseSession) async throws -> [String] {
        let (_, rows) = try await s.queryAll("""
            select c.table_name, p.table_name from all_constraints c join all_constraints p on p.owner = c.r_owner and p.constraint_name = c.r_constraint_name
             where c.owner = :o and c.constraint_type = 'R' and p.owner = :o and c.table_name <> p.table_name
            """, binds: [BindVariable(name: "o", value: .text(owner))], limit: 100_000)
        let set = Set(tables)
        var parents: [String: Set<String>] = [:]
        for r in rows {
            guard let child = r[0].displayText, let parent = r[1].displayText, set.contains(child), set.contains(parent) else { continue }
            parents[child, default: []].insert(parent)
        }
        var done: [String] = []
        var remaining = tables.sorted()
        var doneSet = Set<String>()
        while !remaining.isEmpty {
            let ready = remaining.filter { (parents[$0] ?? []).isSubset(of: doneSet) }
            let next = ready.isEmpty ? [remaining[0]] : ready
            done += next
            doneSet.formUnion(next)
            remaining.removeAll { next.contains($0) }
        }
        return done
    }

    static func foreignKeys(_ table: String, owner: String, in s: any DatabaseSession) async throws -> [String] {
        let (_, rows) = try await s.queryAll("select constraint_name from all_constraints where owner = :o and table_name = :t and constraint_type = 'R'",
                                             binds: [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "t", value: .text(table))])
        return rows.compactMap { $0.first?.displayText }
    }

    /// Kolumna tabeli w przenoszeniu danych.
    struct TableColumn: Sendable, Hashable {
        var name: String
        var type: String
        /// Kolumna wirtualna — bez wartości w INSERT/UPDATE (ORA-54013).
        var virtual: Bool
        /// Identity GENERATED ALWAYS — INSERT z wartością daje ORA-32795.
        var identityAlways: Bool
    }

    /// Kolumny użytkownika tabeli (także INVISIBLE — `SELECT *` je pomija; bez ukrytych systemowych) w kolejności tabeli.
    static func columns(_ table: String, owner: String, in s: any DatabaseSession) async throws -> [TableColumn] {
        let b = [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "t", value: .text(table))]
        let filter = "c.owner = :o and c.table_name = :t and (c.hidden_column = 'NO' or c.user_generated = 'YES') order by c.column_id nulls last, c.internal_column_id"
        let rows: [[OracleValue]]
        do {
            rows = try await s.queryAll("""
                select c.column_name, c.data_type, c.virtual_column,
                       (select max(i.generation_type) from all_tab_identity_cols i
                         where i.owner = c.owner and i.table_name = c.table_name and i.column_name = c.column_name)
                  from all_tab_cols c where \(filter)
                """, binds: b, limit: 10_000).1
        } catch {
            // Oracle 11g: bez ALL_TAB_IDENTITY_COLS (i bez kolumn identity).
            rows = try await s.queryAll("select c.column_name, c.data_type, c.virtual_column, null from all_tab_cols c where \(filter)",
                                        binds: b, limit: 10_000).1
        }
        return rows.map { TableColumn(name: $0[0].displayText ?? "", type: $0[1].displayText ?? "", virtual: $0[2].displayText == "YES",
                                      identityAlways: $0[3].displayText == "ALWAYS") }
    }

    /// Wszystkie wiersze tabeli z LOB-ami pobranymi w całości do limitu; kolumny z wartościami (bez wirtualnych, z INVISIBLE).
    static func fetch(_ table: String, owner: String, whereClause: String, columns: [TableColumn]? = nil, in s: any DatabaseSession,
                      row: ([ColumnInfo], [OracleValue]) async throws -> Void) async throws -> [ColumnInfo] {
        let cond = whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cond.contains(";") else { throw CommandError.invalidArgument("where", L10n.tr("warunek bez średnika")) }
        var stored: [TableColumn] = []
        if let columns { stored = columns } else { stored = try await self.columns(table, owner: owner, in: s) }
        stored.removeAll(where: \.virtual)
        let list = stored.isEmpty ? "*" : stored.map { q($0.name) }.joined(separator: ", ")
        let r = try await s.execute("select \(list) from \(q(owner)).\(q(table))\(cond.isEmpty ? "" : " where \(cond)")", binds: [],
                                    options: ExecuteOptions(lobLimit: 10_000_000, bulk: true))
        guard let rs = r.resultSet else { return [] }
        while true {
            let batch = try await s.fetch(rs.id, maxRows: 5000)
            for v in batch.rows { try await row(rs.columns, v) }
            if !batch.hasMore { break }
        }
        return rs.columns
    }

    /// Skrypt SQL Inserts zgodny z oknem poleceń / SQL*Plus.
    public static func sqlInserts(_ tables: [String], owner: String, options o: TableExportOptions, in s: any DatabaseSession,
                                  progress: (@MainActor (String) -> Void)? = nil) async throws -> String {
        let ordered = try await orderByForeignKeys(tables, owner: owner, in: s)
        var out = "-- " + L10n.tr("Eksport tabel \(owner) — wygenerowane przez Pelikana") + " " + ISO8601DateFormatter().string(from: Date()) + "\n"
        out += "set define off\nset feedback off\n"
        if o.drop { for t in ordered.reversed() { out += "drop table \(q(t)) cascade constraints;\n" } }
        if o.create {
            for t in ordered {
                var e = ObjectExportSettings(storage: o.includeStorage)
                e.privileges = o.includePrivileges
                out += try await tableDDL(t, owner: owner, settings: e, in: s) + "\n"
            }
        }
        if o.disableTriggers { for t in ordered { out += "alter table \(q(t)) disable all triggers;\n" } }
        // Więzy FK po nazwie z bieżącej bazy (po CREATE nazwy systemowe SYS_C… są inne) — blok PL/SQL w skrypcie.
        func toggleFKs(_ action: String) -> String {
            let list = ordered.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }.joined(separator: ", ")
            return """
                begin
                  for c in (select table_name, constraint_name from user_constraints where constraint_type = 'R' and table_name in (\(list))) loop
                    execute immediate 'alter table "' || c.table_name || '" \(action) constraint "' || c.constraint_name || '"';
                  end loop;
                end;
                /

                """
        }
        if o.disableForeignKeys { out += toggleFKs("disable") }
        if o.truncate { for t in ordered.reversed() { out += "truncate table \(q(t));\n" } } else if o.delete { for t in ordered.reversed() { out += "delete from \(q(t));\n" } }
        for t in ordered {
            await progress?(t)
            var n = 0
            var header = ""
            out += "prompt " + L10n.tr("Wiersze tabeli \(t)") + "\n"
            let columns = try await self.columns(t, owner: owner, in: s)
            // Identity ALWAYS przyjmuje wartości tylko jako BY DEFAULT; potem licznik od największej wartości.
            let always = columns.filter(\.identityAlways)
            for c in always { out += "alter table \(q(t)) modify (\(q(c.name)) generated by default as identity);\n" }
            _ = try await fetch(t, owner: owner, whereClause: o.whereClause, columns: columns, in: s) { cols, row in
                if header.isEmpty { header = "insert into \(q(t)) (\(cols.map { q($0.name) }.joined(separator: ", "))) values (" }
                let values = row.map { v -> String in
                    if case .lob = v, !o.includeLOBs { return "NULL" }
                    return ResultExporter.literal(v)
                }
                out += header + values.joined(separator: ", ") + ");\n"
                n += 1
                if o.commitEvery > 0, n % o.commitEvery == 0 { out += "commit;\n" }
            }
            out += "commit;\n"
            for c in always { out += "alter table \(q(t)) modify (\(q(c.name)) generated always as identity (start with limit value));\n" }
        }
        if o.disableForeignKeys { out += toggleFKs("enable") }
        if o.disableTriggers { for t in ordered { out += "alter table \(q(t)) enable all triggers;\n" } }
        return out + "set feedback on\nset define on\n"
    }

    struct ObjectExportSettings {
        var storage: Bool
        var privileges = false
    }

    /// DDL tabeli bez nazwy schematu (z więzami; indeksy i uprawnienia jako zależne DDL).
    static func tableDDL(_ table: String, owner: String, settings: ObjectExportSettings, in s: any DatabaseSession) async throws -> String {
        let r = try await s.execute("""
            declare d clob; x clob; begin
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'DEFAULT', true);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', true);
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES', :st = 1); exception when others then null; end;
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'EMIT_SCHEMA', false); exception when others then null; end;
              d := dbms_metadata.get_ddl('TABLE', :n, :o);
              -- Indeksy poza indeksami więzów PRIMARY/UNIQUE (te tworzy już CREATE TABLE).
              for i in (select index_name from all_indexes where table_owner = :o and table_name = :n and index_type not like 'LOB%'
                          and index_name not in (select constraint_name from all_constraints where owner = :o and table_name = :n
                                                    and constraint_type in ('P', 'U'))) loop
                d := d || chr(10) || dbms_metadata.get_ddl('INDEX', i.index_name, :o);
              end loop;
              if :pr = 1 then
                begin x := dbms_metadata.get_dependent_ddl('OBJECT_GRANT', :n, :o); d := d || chr(10) || x; exception when others then null; end;
              end if;
              :ddl := d;
            end;
            """, binds: [BindVariable(name: "st", type: .number, value: .number(settings.storage ? "1" : "0")),
                         BindVariable(name: "pr", type: .number, value: .number(settings.privileges ? "1" : "0")),
                         BindVariable(name: "n", value: .text(table)), BindVariable(name: "o", value: .text(owner)),
                         BindVariable(name: "ddl", type: .clob, direction: .output)])
        guard case .lob(let l)? = r.outBinds["ddl"], let text = l.text else { return "" }
        // DDL indeksów obejmuje też indeksy kluczy utworzone już przez więzy (ORA-00955 przy imporcie) — import
        // formatu własnego zbiera takie błędy w raporcie, a okno poleceń domyślnie kontynuuje po błędzie.
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Format własny

    /// Wartość w formacie własnym (tekst) i z powrotem do wyrażenia SQL przy imporcie.
    static func encode(_ v: OracleValue) -> String? {
        switch v {
        case .null: return nil
        case .number(let s): return s
        case .double(let d): return String(d)
        case .text(let s), .rowid(let s), .json(let s): return s
        case .boolean(let b): return b ? "1" : "0"
        case .timestamp(let t, let type):
            // TIMESTAMP WITH TIME ZONE z przesunięciem — bez niego import przyjąłby strefę sesji celu (inna chwila).
            return t.formatted(type == .timestampTZ ? "YYYY-MM-DD HH24:MI:SS.FF9 TZH:TZM" : "YYYY-MM-DD HH24:MI:SS.FF9")
        case .raw(let d): return d.base64EncodedString()
        case .lob(let l):
            if let t = l.text { return t }
            return l.bytes?.base64EncodedString()
        default: return v.format(.default)
        }
    }

    /// Eksport do formatu własnego: JSON skompresowany (LZFSE na macOS; nagłówek określa wariant).
    public static func exportNative(_ tables: [String], owner: String, whereClause: String = "", includeDDL: Bool = true,
                                    in s: any DatabaseSession, progress: (@MainActor (String) -> Void)? = nil) async throws -> Data {
        var file = PelikanTableFile(created: ISO8601DateFormatter().string(from: Date()), tables: [])
        for t in try await orderByForeignKeys(tables, owner: owner, in: s) {
            await progress?(t)
            var rows: [[String?]] = []
            let columns = try await self.columns(t, owner: owner, in: s)
            // Wartość, której nie da się wiernie zapisać (LOB obcięty przy odczycie, obiekt, BFILE) — błąd zamiast
            // cichego obcięcia albo tekstu zamiast wartości (D168/D169).
            let cols = try await fetch(t, owner: owner, whereClause: whereClause, columns: columns, in: s) { info, row in
                rows.append(try zip(info, row).map { c, v in
                    try TransferValues.check(v, column: "\(t).\(c.name)")
                    return encode(v)
                })
            }
            let types = Dictionary(columns.map { ($0.name, $0.type) }, uniquingKeysWith: { a, _ in a })
            let ddl = includeDDL ? try await tableDDL(t, owner: owner, settings: ObjectExportSettings(storage: false), in: s) : ""
            file.tables.append(PelikanTableData(owner: owner, name: t, ddl: ddl,
                                                columns: cols.map { .init(name: $0.name, type: types[$0.name] ?? $0.typeName) }, rows: rows))
        }
        return try packNative(file)
    }

    static let magicJSON = Data("PLKT1J".utf8)
    static let magicLZFSE = Data("PLKT1Z".utf8)

    public static func packNative(_ file: PelikanTableFile) throws -> Data {
        let json = try JSONEncoder().encode(file)
        #if canImport(Darwin)
        if let z = try? (json as NSData).compressed(using: .lzfse) as Data { return magicLZFSE + z }
        #endif
        return magicJSON + json
    }

    public static func unpackNative(_ data: Data) throws -> PelikanTableFile {
        let head = data.prefix(6)
        let body = data.dropFirst(6)
        if head == magicJSON { return try JSONDecoder().decode(PelikanTableFile.self, from: Data(body)) }
        if head == magicLZFSE {
            #if canImport(Darwin)
            let json = try (Data(body) as NSData).decompressed(using: .lzfse) as Data
            return try JSONDecoder().decode(PelikanTableFile.self, from: json)
            #else
            throw CommandError.notAvailable(L10n.tr("Plik skompresowany LZFSE — odczyt tylko na macOS"))
            #endif
        }
        throw CommandError.notAvailable(L10n.tr("To nie jest plik eksportu tabel Pelikana"))
    }

    /// Wyrażenie wiązania wartości kolumny danego typu w formacie własnym.
    static func valueExpression(_ type: String, bind: String) -> String {
        let t = type.uppercased()
        if t == "DATE" { return "TO_DATE(SUBSTR(:\(bind), 1, 19), 'YYYY-MM-DD HH24:MI:SS')" }
        if t.hasPrefix("TIMESTAMP"), t.hasSuffix("WITH TIME ZONE"), !t.contains("LOCAL") {
            return "TO_TIMESTAMP_TZ(:\(bind), 'YYYY-MM-DD HH24:MI:SS.FF9 TZH:TZM')"
        }
        if t.hasPrefix("TIMESTAMP") { return "TO_TIMESTAMP(:\(bind), 'YYYY-MM-DD HH24:MI:SS.FF9')" }
        // RAW, BLOB i CLOB wiązane bezpośrednio (bindValue) — bez limitu VARCHAR2 4000 B dla tekstu szesnastkowego.
        return ":\(bind)"
    }

    /// Zmienna wiązana wartości z formatu własnego: RAW/BLOB z base64 jako dane binarne, CLOB/NCLOB jako LOB, liczby
    /// jako NUMBER, reszta jako tekst.
    static func bindValue(_ type: String, name: String, value v: String?) -> BindVariable {
        guard let v else { return BindVariable(name: name, value: .null) }
        let t = type.uppercased()
        switch t {
        case "RAW", "BLOB", "LONG RAW":
            let d = Data(base64Encoded: v) ?? Data()
            if t != "BLOB" { return BindVariable(name: name, type: .raw, value: .raw(d), maxSize: UInt32(max(1, d.count))) }
            return BindVariable(name: name, type: .blob, value: .lob(LOBValue(kind: .blob, bytes: d, length: UInt64(d.count), truncated: false)))
        case "CLOB", "NCLOB":
            return BindVariable(name: name, type: t == "CLOB" ? .clob : .nclob,
                                value: .lob(LOBValue(kind: t == "CLOB" ? .clob : .nclob, text: v, length: UInt64(v.count), truncated: false)))
        case "NUMBER", "FLOAT":
            return BindVariable(name: name, type: .number, value: .number(v))
        default:
            if t.hasPrefix("BINARY_") { return BindVariable(name: name, type: .number, value: .number(v)) }
            return BindVariable(name: name, value: .text(v), maxSize: UInt32(max(32767, v.utf8.count)))
        }
    }

    /// Polecenie z pola DDL pliku, które wolno wykonać przy imporcie z „Utwórz”: CREATE TABLE tej tabeli, CREATE INDEX
    /// na niej, ALTER TABLE … ADD/MODIFY/ENABLE/DISABLE i COMMENT ON tej tabeli (bez podzapytań). Nazwa bez schematu
    /// albo ze schematem celu.
    static func isTableDDL(_ sql: String, table: String, owner: String) -> Bool {
        let ns = sql as NSString
        let tokens = Lexer(sql).tokenize().filter { !$0.isTrivia && $0.kind != .hint }
        func text(_ i: Int) -> String { ns.substring(with: NSRange(location: tokens[i].start, length: tokens[i].length)) }
        func word(_ i: Int) -> String? { i < tokens.count && [.identifier, .keyword].contains(tokens[i].kind) ? text(i).uppercased() : nil }
        func part(_ i: Int) -> String? {
            guard i < tokens.count else { return nil }
            if tokens[i].kind == .quotedIdentifier {
                let t = text(i)
                return t.count >= 2 ? String(t.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"") : nil
            }
            return word(i)
        }
        /// Nazwa `[a.]b[.c]` od pozycji `i`: części i pozycja za nazwą.
        func name(_ i: Int, maxParts: Int = 2) -> ([String], Int)? {
            guard var p = part(i).map({ [$0] }) else { return nil }
            var j = i + 1
            while p.count < maxParts, j + 1 < tokens.count, tokens[j].kind == .dot, let n = part(j + 1) { p.append(n); j += 2 }
            return (p, j)
        }
        func isTable(_ p: [String]) -> Bool { p.last == table && (p.count == 1 || (p.count == 2 && p[0] == owner)) }
        guard !tokens.contains(where: { $0.kind == .semicolon }),
              !tokens.indices.contains(where: { word($0) == "SELECT" }) else { return false }
        switch word(0) {
        case "CREATE":
            var i = 1
            while let w = word(i), ["GLOBAL", "PRIVATE", "TEMPORARY", "SHARDED", "DUPLICATED", "BLOCKCHAIN", "IMMUTABLE"].contains(w) { i += 1 }
            if word(i) == "TABLE" { return name(i + 1).map { isTable($0.0) } ?? false }
            i = 1
            while let w = word(i), ["UNIQUE", "BITMAP", "MULTIVALUE"].contains(w) { i += 1 }
            guard word(i) == "INDEX", let index = name(i + 1), index.0.count == 1 || index.0[0] == owner, word(index.1) == "ON",
                  let on = name(index.1 + 1) else { return false }
            return isTable(on.0)
        case "ALTER":
            guard word(1) == "TABLE", let t = name(2), isTable(t.0), let w = word(t.1) else { return false }
            return ["ADD", "MODIFY", "ENABLE", "DISABLE"].contains(w)
        case "COMMENT":
            guard word(1) == "ON" else { return false }
            if word(2) == "TABLE" { return name(3).map { isTable($0.0) && word($0.1) == "IS" } ?? false }
            guard word(2) == "COLUMN", let c = name(3, maxParts: 3), c.0.count >= 2, word(c.1) == "IS" else { return false }
            return isTable(Array(c.0.dropLast()))
        default:
            return false
        }
    }

    /// Import wskazanych tabel z formatu własnego (tabele w zapisanej kolejności — nadrzędne pierwsze).
    public static func importNative(_ file: PelikanTableFile, tables selected: Set<String>, intoOwner owner: String, options o: TableImportOptions,
                                    in s: any DatabaseSession, progress: (@MainActor (String) -> Void)? = nil) async throws -> ImportResult {
        var result = ImportResult()
        let tables = file.tables.filter { selected.contains($0.name) }
        let existing = Set(try await self.tables(owner: owner, in: s))
        if o.create {
            // Plik danych od kogoś innego: wykonujemy tylko DDL tej tabeli (CREATE TABLE/INDEX, ALTER TABLE, COMMENT) —
            // całość sprawdzona przed pierwszym poleceniem (np. GRANT albo blok PL/SQL w pliku przerywa import).
            let ddl = try tables.filter { !existing.contains($0.name) && !$0.ddl.isEmpty }.map { t in
                (t.name, try ScriptSplitter.split(t.ddl).map { st -> String in
                    var text = st.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    while text.hasSuffix(";") { text.removeLast() }
                    guard isTableDDL(text, table: t.name, owner: owner) else {
                        throw CommandError.notAvailable(L10n.tr("Tabela \(t.name): plik zawiera polecenie spoza definicji tabeli — import przerwany:\n\(String(text.prefix(200)))"))
                    }
                    return text
                })
            }
            // DDL z pliku jest bez schematu — tabela i indeksy w schemacie docelowym, nie w bieżącym schemacie sesji.
            var previous = owner
            if !ddl.isEmpty { previous = try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? owner }
            if previous != owner { _ = try await s.execute("alter session set current_schema = \(q(owner))") }
            for (name, statements) in ddl {
                for text in statements {
                    do { _ = try await s.execute(text) } catch { result.errors.append("\(name): \(error.localizedDescription)") }
                }
            }
            if previous != owner { _ = try await s.execute("alter session set current_schema = \(q(previous))") }
        }
        if o.disableTriggers { for t in tables { _ = try? await s.execute("alter table \(q(owner)).\(q(t.name)) disable all triggers") } }
        var fks: [String: [String]] = [:]
        if o.disableForeignKeys {
            for t in tables {
                fks[t.name] = try await foreignKeys(t.name, owner: owner, in: s)
                for c in fks[t.name] ?? [] { _ = try? await s.execute("alter table \(q(owner)).\(q(t.name)) disable constraint \(q(c))") }
            }
        }
        for t in tables.reversed() {
            if o.truncate { _ = try await s.execute("truncate table \(q(owner)).\(q(t.name))") } else if o.delete { _ = try await s.execute("delete from \(q(owner)).\(q(t.name))") }
        }
        for t in tables {
            await progress?(t.name)
            // Kolumny celu: wirtualne pomijane (pliki sprzed poprawki je zawierają — ORA-54013); identity ALWAYS na czas
            // importu BY DEFAULT, potem licznik od największej wartości (jak Recreate table).
            let target = try await columns(t.name, owner: owner, in: s)
            let virtual = Set(target.filter(\.virtual).map(\.name))
            let used = t.columns.indices.filter { !virtual.contains(t.columns[$0].name) }
            let always = t.rows.isEmpty ? [] : target.filter { c in c.identityAlways && used.contains { t.columns[$0].name == c.name } }
            let table = "\(q(owner)).\(q(t.name))"
            let sql = "insert into \(table) (\(used.map { q(t.columns[$0].name) }.joined(separator: ", "))) values ("
                + used.map { valueExpression(t.columns[$0].type, bind: "c\($0)") }.joined(separator: ", ") + ")"
            for c in always { _ = try await s.execute("alter table \(table) modify (\(q(c.name)) generated by default as identity)") }
            do {
                for (i, row) in t.rows.enumerated() {
                    let values: [BindVariable] = used.map { j in bindValue(t.columns[j].type, name: "c\(j)", value: j < row.count ? row[j] : nil) }
                    do {
                        _ = try await s.execute(sql, binds: values)
                        result.inserted += 1
                    } catch {
                        result.errors.append("\(t.name) " + L10n.tr("wiersz \(i + 1): \(error.localizedDescription)"))
                    }
                    if o.commitEvery > 0, (i + 1) % o.commitEvery == 0 { try await s.commit() }
                }
                try await s.commit()
            } catch {
                for c in always { _ = try? await s.execute("alter table \(table) modify (\(q(c.name)) generated always as identity (start with limit value))") }
                throw error
            }
            for c in always {
                do { _ = try await s.execute("alter table \(table) modify (\(q(c.name)) generated always as identity (start with limit value))") }
                catch { result.errors.append("\(t.name).\(c.name): \(error.localizedDescription)") }
            }
        }
        if o.disableForeignKeys {
            for t in tables { for c in fks[t.name] ?? [] {
                do { _ = try await s.execute("alter table \(q(owner)).\(q(t.name)) enable constraint \(q(c))") } catch { result.errors.append("\(t.name).\(c): \(error.localizedDescription)") }
            } }
        }
        if o.disableTriggers { for t in tables { _ = try? await s.execute("alter table \(q(owner)).\(q(t.name)) enable all triggers") } }
        return result
    }

    // MARK: Import SQL Inserts (okno poleceń)

    /// Wykonuje skrypt SQL Inserts silnikiem okna poleceń w nowym dokumencie połączenia (wynik i błędy w konsoli
    /// okna); zwraca liczbę błędów.
    @MainActor
    public static func importSQLScript(_ script: String, baseDirectory: URL?, connectionID: UUID, in ws: Workspace) async throws -> (document: Document, errors: Int) {
        try await ws.guardModification(ScriptSplitter.split(script).filter { $0.sqlplusCommand == nil }.map(\.text), connectionID: connectionID)
        let doc = ws.newDocument(.command, text: "")
        doc.connectionID = connectionID
        doc.customTitle = L10n.tr("Import tabel")
        let engine = ws.sqlplusEngine(for: doc)
        _ = await engine.run(script, baseDirectory: baseDirectory)
        return (doc, doc.console.filter { $0.kind == .error }.count)
    }
}

/// Eksport i import przez Data Pump (DBMS_DATAPUMP, PD-TOOL-005) w katalogu bazy (domyślnie DATA_PUMP_DIR);
/// zadanie synchroniczne (WAIT_FOR_JOB), dziennik czytany przez UTL_FILE.
public enum DataPump {
    public struct Result: Sendable {
        public var state: String
        public var log: String
    }

    static func lit(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    /// Błąd w bloku po OPEN: zatrzymanie zadania z usunięciem tabeli głównej (bez tego zadanie i jego tabela główna
    /// zostają w schemacie); potem błąd dalej.
    static let cleanup = """
        exception when others then
              if h is not null then begin dbms_datapump.stop_job(h, immediate => 1, keep_master => 0, delay => 0); exception when others then null; end; end if;
              raise;
        """

    static func nameList(_ names: [String]) -> String {
        names.map { "''" + $0.replacingOccurrences(of: "'", with: "") + "''" }.joined(separator: ",")
    }

    /// Eksport schematu albo wskazanych tabel do pliku zrzutu w katalogu bazy.
    public static func export(schema: String, tables: [String]?, dumpFile: String, directory: String = "DATA_PUMP_DIR",
                              in s: any DatabaseSession) async throws -> Result {
        let log = (dumpFile as NSString).deletingPathExtension + "_exp.log"
        let mode = tables == nil ? "SCHEMA" : "TABLE"
        var filters = "dbms_datapump.metadata_filter(h, 'SCHEMA_EXPR', 'IN (''\(schema.replacingOccurrences(of: "'", with: ""))'')');"
        if let tables { filters += " dbms_datapump.metadata_filter(h, 'NAME_EXPR', 'IN (\(nameList(tables)))');" }
        let block = """
            declare h number; st varchar2(30); begin
              h := dbms_datapump.open('EXPORT', '\(mode)');
              dbms_datapump.add_file(h, \(lit(dumpFile)), \(lit(directory)), reusefile => 1);
              dbms_datapump.add_file(h, \(lit(log)), \(lit(directory)), filetype => dbms_datapump.ku$_file_type_log_file, reusefile => 1);
              \(filters)
              dbms_datapump.start_job(h);
              dbms_datapump.wait_for_job(h, st);
              :st := st;
            \(cleanup)
            end;
            """
        return try await run(block, log: log, directory: directory, in: s)
    }

    /// Import pliku zrzutu: tabele (opcjonalnie), przemapowanie schematu, zachowanie przy istniejących tabelach
    /// (SKIP, APPEND, TRUNCATE, REPLACE).
    public static func importDump(dumpFile: String, tables: [String]?, fromSchema: String, toSchema: String, tableExists: String = "APPEND",
                                  directory: String = "DATA_PUMP_DIR", in s: any DatabaseSession) async throws -> Result {
        let log = (dumpFile as NSString).deletingPathExtension + "_imp.log"
        let action = ["SKIP", "APPEND", "TRUNCATE", "REPLACE"].contains(tableExists.uppercased()) ? tableExists.uppercased() : "APPEND"
        // Tryb TABLE albo SCHEMA z filtrem schematu źródłowego (FULL z samym filtrem nazw daje ORA-39001).
        var filters = "dbms_datapump.metadata_filter(h, 'SCHEMA_EXPR', 'IN (''\(fromSchema.uppercased().replacingOccurrences(of: "'", with: ""))'')');"
        if let tables { filters += " dbms_datapump.metadata_filter(h, 'NAME_EXPR', 'IN (\(nameList(tables)))');" }
        if fromSchema.uppercased() != toSchema.uppercased() {
            filters += " dbms_datapump.metadata_remap(h, 'REMAP_SCHEMA', \(lit(fromSchema.uppercased())), \(lit(toSchema.uppercased())));"
        }
        let block = """
            declare h number; st varchar2(30); begin
              h := dbms_datapump.open('IMPORT', '\(tables == nil ? "SCHEMA" : "TABLE")');
              dbms_datapump.add_file(h, \(lit(dumpFile)), \(lit(directory)));
              dbms_datapump.add_file(h, \(lit(log)), \(lit(directory)), filetype => dbms_datapump.ku$_file_type_log_file, reusefile => 1);
              dbms_datapump.set_parameter(h, 'TABLE_EXISTS_ACTION', '\(action)');
              \(filters)
              dbms_datapump.start_job(h);
              dbms_datapump.wait_for_job(h, st);
              :st := st;
            \(cleanup)
            end;
            """
        return try await run(block, log: log, directory: directory, in: s)
    }

    static func run(_ block: String, log: String, directory: String, in s: any DatabaseSession) async throws -> Result {
        let r = try await s.execute(block, binds: [BindVariable(name: "st", direction: .output, maxSize: 64)])
        let state = r.outBinds["st"]?.displayText ?? r.outBinds["ST"]?.displayText ?? ""
        let l = try? await s.execute("""
            declare f utl_file.file_type; line varchar2(32767); buf clob; begin
              f := utl_file.fopen(\(lit(directory)), \(lit(log)), 'r', 32767);
              begin loop utl_file.get_line(f, line); buf := buf || line || chr(10); end loop; exception when no_data_found then null; end;
              utl_file.fclose(f);
              :log := buf;
            end;
            """, binds: [BindVariable(name: "log", type: .clob, direction: .output)])
        var text = ""
        if case .lob(let lob)? = l?.outBinds["log"] { text = lob.text ?? "" }
        return Result(state: state, log: text)
    }
}
