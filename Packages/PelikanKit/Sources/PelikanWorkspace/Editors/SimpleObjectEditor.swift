import Foundation
import PelikanDB

/// Pole formularza prostego edytora obiektu.
public struct EditorField: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case text, number, bool, multiline
        case choice([String])
        /// Lista po przecinku (role, uprawnienia, kolumny).
        case list
        /// Hasło: nie trafia do podglądu SQL ani do żadnego zapisu (D26).
        case secret
    }
    public var key: String
    public var label: String
    public var kind: Kind
    /// Tylko przy tworzeniu (dla istniejącego obiektu pole tylko do odczytu).
    public var createOnly = false
    public var id: String { key }
}

/// Proste edytory obiektów (UG 9.2–9.11): sekwencja, synonim, indeks, użytkownik, rola — wartości pól jako tekst,
/// DDL tworzenia albo zmian względem stanu z bazy.
public struct SimpleObjectEditor: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable { case sequence, synonym, index, user, role }

    public var kind: Kind
    public var owner: String
    public var values: [String: String]
    /// Wartości wczytane z bazy (nil — nowy obiekt).
    public var original: [String: String]?

    public init(kind: Kind, owner: String, values: [String: String] = [:], original: [String: String]? = nil) {
        self.kind = kind; self.owner = owner; self.values = values; self.original = original
    }

    public var isNew: Bool { original == nil }
    public func value(_ k: String) -> String { values[k] ?? "" }
    func old(_ k: String) -> String { original?[k] ?? "" }
    func flag(_ k: String) -> Bool { value(k) == "Y" }

    public var title: String {
        switch kind {
        case .sequence: L10n.tr("Sekwencja")
        case .synonym: L10n.tr("Synonim")
        case .index: L10n.tr("Indeks")
        case .user: L10n.tr("Użytkownik")
        case .role: L10n.tr("Rola")
        }
    }

    public var fields: [EditorField] {
        switch kind {
        case .sequence:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text),
             EditorField(key: "start", label: L10n.tr("Wartość początkowa"), kind: .number, createOnly: true),
             EditorField(key: "increment", label: L10n.tr("Przyrost"), kind: .number),
             EditorField(key: "min", label: L10n.tr("Minimum"), kind: .number),
             EditorField(key: "max", label: L10n.tr("Maksimum"), kind: .number),
             EditorField(key: "cache", label: L10n.tr("Bufor (0 — bez bufora)"), kind: .number),
             EditorField(key: "cycle", label: L10n.tr("Cykliczna"), kind: .bool),
             EditorField(key: "order", label: L10n.tr("Uporządkowana (ORDER)"), kind: .bool)]
        case .synonym:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text),
             EditorField(key: "public", label: L10n.tr("Publiczny"), kind: .bool, createOnly: true),
             EditorField(key: "targetOwner", label: L10n.tr("Właściciel obiektu"), kind: .text),
             EditorField(key: "target", label: L10n.tr("Obiekt"), kind: .text),
             EditorField(key: "dblink", label: L10n.tr("Łącze bazy danych"), kind: .text)]
        case .index:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text),
             EditorField(key: "table", label: L10n.tr("Tabela"), kind: .text, createOnly: true),
             EditorField(key: "columns", label: L10n.tr("Kolumny / wyrażenia (DESC)"), kind: .list, createOnly: true),
             EditorField(key: "type", label: L10n.tr("Rodzaj"), kind: .choice(["NORMAL", "UNIQUE", "BITMAP"]), createOnly: true),
             EditorField(key: "tablespace", label: L10n.tr("Przestrzeń tabel"), kind: .text, createOnly: true),
             EditorField(key: "invisible", label: L10n.tr("Niewidoczny"), kind: .bool)]
        case .user:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text, createOnly: true),
             EditorField(key: "password", label: L10n.tr("Hasło (puste — bez zmiany)"), kind: .secret),
             EditorField(key: "defaultTablespace", label: L10n.tr("Domyślna przestrzeń tabel"), kind: .text),
             EditorField(key: "temporaryTablespace", label: L10n.tr("Przestrzeń tymczasowa"), kind: .text),
             EditorField(key: "profile", label: L10n.tr("Profil"), kind: .text),
             EditorField(key: "locked", label: L10n.tr("Konto zablokowane"), kind: .bool),
             EditorField(key: "expire", label: L10n.tr("Hasło wygasa przy logowaniu"), kind: .bool),
             EditorField(key: "roles", label: L10n.tr("Role"), kind: .list),
             EditorField(key: "privileges", label: L10n.tr("Uprawnienia systemowe"), kind: .list),
             EditorField(key: "quotas", label: L10n.tr("Limity (przestrzeń:rozmiar, np. USERS:UNLIMITED)"), kind: .list)]
        case .role:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text, createOnly: true),
             EditorField(key: "roles", label: L10n.tr("Role"), kind: .list),
             EditorField(key: "privileges", label: L10n.tr("Uprawnienia systemowe"), kind: .list)]
        }
    }

    static func list(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
    }

    static let q = TableDDL.q

    // MARK: DDL

    /// Polecenia DDL; `masked` — hasło zastąpione gwiazdkami (podgląd w edytorze).
    public func statements(masked: Bool = false) -> [String] {
        let name = value("name").uppercased()
        guard !name.isEmpty else { return [] }
        let qn = Self.q(owner) + "." + Self.q(name)
        var out: [String] = []
        switch kind {
        case .sequence:
            var opts: [String] = []
            func num(_ k: String, _ kw: String, none: String) {
                let v = value(k)
                if isNew ? !v.isEmpty : v != old(k) { opts.append(v.isEmpty ? none : "\(kw) \(v)") }
            }
            if !isNew, old("name") != name { out.append("RENAME \(Self.q(old("name"))) TO \(Self.q(name))") }
            num("increment", "INCREMENT BY", none: "INCREMENT BY 1")
            num("min", "MINVALUE", none: "NOMINVALUE")
            num("max", "MAXVALUE", none: "NOMAXVALUE")
            if isNew ? !value("cache").isEmpty : value("cache") != old("cache") {
                opts.append(value("cache") == "0" || value("cache").isEmpty ? "NOCACHE" : "CACHE \(value("cache"))")
            }
            if isNew ? flag("cycle") : value("cycle") != old("cycle") { opts.append(flag("cycle") ? "CYCLE" : "NOCYCLE") }
            if isNew ? flag("order") : value("order") != old("order") { opts.append(flag("order") ? "ORDER" : "NOORDER") }
            if isNew {
                if !value("start").isEmpty { opts.insert("START WITH \(value("start"))", at: 0) }
                out.append("CREATE SEQUENCE \(qn)" + (opts.isEmpty ? "" : " " + opts.joined(separator: " ")))
            } else if !opts.isEmpty {
                out.append("ALTER SEQUENCE \(qn) " + opts.joined(separator: " "))
            }
        case .synonym:
            let pub = flag("public")
            let target = (value("targetOwner").isEmpty ? "" : Self.q(value("targetOwner").uppercased()) + ".") + Self.q(value("target").uppercased())
            let link = value("dblink").isEmpty ? "" : "@" + value("dblink")
            let changed = isNew || ["name", "targetOwner", "target", "dblink"].contains { value($0) != old($0) }
            if changed {
                if !isNew, old("name") != name { out.append("DROP \(pub ? "PUBLIC " : "")SYNONYM \(pub ? Self.q(old("name")) : Self.q(owner) + "." + Self.q(old("name")))") }
                out.append("CREATE OR REPLACE \(pub ? "PUBLIC " : "")SYNONYM \(pub ? Self.q(name) : qn) FOR \(target)\(link)")
            }
        case .index:
            if isNew {
                var x = TableDefinition.Index(name: name, columns: Self.list(value("columns")).isEmpty ? [] : value("columns").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                x.kind = value("type") == "UNIQUE" ? .unique : value("type") == "BITMAP" ? .bitmap : .normal
                x.tablespace = value("tablespace").uppercased()
                x.invisible = flag("invisible")
                var t = TableDefinition(owner: owner, name: value("table").uppercased())
                t.originalName = t.name
                out.append(TableDDL.createIndex(x, table: t))
            } else {
                if old("name") != name { out.append("ALTER INDEX \(Self.q(owner)).\(Self.q(old("name"))) RENAME TO \(Self.q(name))") }
                if value("invisible") != old("invisible") { out.append("ALTER INDEX \(qn) \(flag("invisible") ? "INVISIBLE" : "VISIBLE")") }
            }
        case .user:
            let u = Self.q(name)
            var opts: [String] = []
            let pw = value("password")
            if !pw.isEmpty { opts.append("IDENTIFIED BY " + (masked ? "********" : "\"" + pw.replacingOccurrences(of: "\"", with: "") + "\"")) }
            for (k, kw) in [("defaultTablespace", "DEFAULT TABLESPACE"), ("temporaryTablespace", "TEMPORARY TABLESPACE"), ("profile", "PROFILE")] {
                let v = value(k).uppercased()
                if !v.isEmpty, v != old(k).uppercased() { opts.append("\(kw) \(Self.q(v))") }
            }
            for q in Self.list(value("quotas")) where !Self.list(old("quotas")).contains(q) {
                let p = q.split(separator: ":").map(String.init)
                if p.count == 2 { opts.append("QUOTA \(p[1] == "UNLIMITED" ? "UNLIMITED" : p[1]) ON \(Self.q(p[0]))") }
            }
            if isNew || value("locked") != old("locked") { opts.append(flag("locked") ? "ACCOUNT LOCK" : "ACCOUNT UNLOCK") }
            if flag("expire"), isNew || old("expire") != "Y" { opts.append("PASSWORD EXPIRE") }
            if isNew {
                if pw.isEmpty { opts.insert("NO AUTHENTICATION", at: 0) }
                out.append("CREATE USER \(u) " + opts.joined(separator: " "))
            } else if !opts.isEmpty {
                out.append("ALTER USER \(u) " + opts.joined(separator: " "))
            }
            out += grants(to: u)
        case .role:
            let r = Self.q(name)
            if isNew { out.append("CREATE ROLE \(r)") }
            out += grants(to: r)
        }
        return out
    }

    /// GRANT / REVOKE ról i uprawnień systemowych wg różnicy list.
    func grants(to grantee: String) -> [String] {
        var out: [String] = []
        for k in ["roles", "privileges"] {
            let now = Set(Self.list(value(k))), before = Set(Self.list(old(k)))
            for g in now.subtracting(before).sorted() { out.append("GRANT \(k == "roles" ? Self.q(g) : g) TO \(grantee)") }
            for g in before.subtracting(now).sorted() { out.append("REVOKE \(k == "roles" ? Self.q(g) : g) FROM \(grantee)") }
        }
        return out
    }

    // MARK: Wczytanie

    @MainActor
    public static func load(_ kind: Kind, owner: String, name: String, metadata m: MetadataProvider) async throws -> SimpleObjectEditor {
        let s = try await m.session()
        let b = [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(name))]
        let bn = [BindVariable(name: "n", value: .text(name))]
        var v: [String: String] = ["name": name]
        func one(_ sql: String, _ binds: [BindVariable]) async throws -> [String] {
            let (_, rows) = try await s.queryAll(sql, binds: binds, limit: 1)
            guard let r = rows.first else { throw CommandError.invalidArgument("object", L10n.tr("nie znaleziono \(owner).\(name)")) }
            return r.map { $0.displayText ?? "" }
        }
        func many(_ sql: String, _ binds: [BindVariable]? = nil) async throws -> String {
            let (_, rows) = try await s.queryAll(sql, binds: binds ?? bn, limit: 10_000)
            return rows.compactMap { $0.first?.displayText }.joined(separator: ", ")
        }
        switch kind {
        case .sequence:
            let r = try await one("select increment_by, min_value, max_value, cache_size, cycle_flag, order_flag from all_sequences where sequence_owner = :o and sequence_name = :n", b)
            v["increment"] = r[0]; v["min"] = r[1]; v["max"] = r[2]; v["cache"] = r[3]; v["cycle"] = r[4]; v["order"] = r[5]
        case .synonym:
            let r = try await one("select table_owner, table_name, db_link, decode(owner, 'PUBLIC', 'Y', 'N') from all_synonyms where owner = :o and synonym_name = :n", b)
            v["targetOwner"] = r[0]; v["target"] = r[1]; v["dblink"] = r[2]; v["public"] = r[3]
        case .index:
            let r = try await one("""
                select table_name, decode(uniqueness, 'UNIQUE', 'UNIQUE', decode(substr(index_type, 1, 6), 'BITMAP', 'BITMAP', 'NORMAL')),
                       tablespace_name, decode(visibility, 'INVISIBLE', 'Y', 'N') from all_indexes where owner = :o and index_name = :n
                """, b)
            v["table"] = r[0]; v["type"] = r[1]; v["tablespace"] = r[2]; v["invisible"] = r[3]
            v["columns"] = try await many("select column_name from all_ind_columns where index_owner = :o and index_name = :n order by column_position", b)
        case .user:
            let r = try await one("""
                select default_tablespace, temporary_tablespace, profile, case when account_status like '%LOCKED%' then 'Y' else 'N' end,
                       case when account_status like '%EXPIRED%' then 'Y' else 'N' end
                from dba_users where username = :n
                """, bn)
            v["defaultTablespace"] = r[0]; v["temporaryTablespace"] = r[1]; v["profile"] = r[2]; v["locked"] = r[3]; v["expire"] = r[4]
            v["roles"] = try await many("select granted_role from dba_role_privs where grantee = :n order by 1")
            v["privileges"] = try await many("select privilege from dba_sys_privs where grantee = :n order by 1")
            v["quotas"] = try await many("select tablespace_name || ':' || decode(max_bytes, -1, 'UNLIMITED', max_bytes) from dba_ts_quotas where username = :n order by 1")
        case .role:
            _ = try await one("select role from dba_roles where role = :n", bn)
            v["roles"] = try await many("select granted_role from dba_role_privs where grantee = :n order by 1")
            v["privileges"] = try await many("select privilege from dba_sys_privs where grantee = :n order by 1")
        }
        return SimpleObjectEditor(kind: kind, owner: owner, values: v, original: v)
    }

    /// Wykonanie DDL w sesji kompilacji po strażniku; zatrzymanie przy pierwszym błędzie.
    @MainActor
    public func apply(in ws: Workspace, connectionID: UUID) async throws -> TableDDL.ApplyResult {
        let sql = statements()
        guard !sql.isEmpty else { return TableDDL.ApplyResult(executed: []) }
        try await ws.guardModification(statements(masked: true), connectionID: connectionID)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: connectionID))
        var done: [String] = []
        let masked = statements(masked: true)
        for (i, stmt) in sql.enumerated() {
            do {
                _ = try await s.execute(stmt)
                done.append(masked[i])
            } catch {
                ws.metadata(for: connectionID)?.refresh()
                return TableDDL.ApplyResult(executed: done, failed: masked[i], error: error.localizedDescription)
            }
        }
        ws.metadata(for: connectionID)?.refresh()
        return TableDDL.ApplyResult(executed: done)
    }
}
