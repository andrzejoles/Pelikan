import Foundation
import PelikanDB

/// Dalsze proste edytory (PD-OED-008/009/010): biblioteka, katalog, zadanie (DBMS_SCHEDULER), kolejka AQ z tabelą
/// kolejki, profil, łącze bazy danych, widok.
extension SimpleObjectEditor {
    static let literal = TableDDL.literal

    var extraFields: [EditorField] {
        switch kind {
        case .library:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text, createOnly: true),
             EditorField(key: "file", label: L10n.tr("Plik biblioteki na serwerze"), kind: .text)]
        case .directory:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text, createOnly: true),
             EditorField(key: "path", label: L10n.tr("Ścieżka na serwerze"), kind: .text)]
        case .job:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text, createOnly: true),
             EditorField(key: "jobType", label: L10n.tr("Rodzaj"), kind: .choice(["PLSQL_BLOCK", "STORED_PROCEDURE"])),
             EditorField(key: "action", label: L10n.tr("Akcja (blok PL/SQL albo procedura)"), kind: .multiline),
             EditorField(key: "repeat", label: L10n.tr("Powtarzanie (np. FREQ=DAILY;BYHOUR=2)"), kind: .text),
             EditorField(key: "enabled", label: L10n.tr("Włączone"), kind: .bool),
             EditorField(key: "comments", label: L10n.tr("Komentarz"), kind: .text)]
        case .queue:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text, createOnly: true),
             EditorField(key: "queueTable", label: L10n.tr("Tabela kolejki"), kind: .text, createOnly: true),
             EditorField(key: "createTable", label: L10n.tr("Utwórz tabelę kolejki"), kind: .bool, createOnly: true),
             EditorField(key: "payload", label: L10n.tr("Typ ładunku (RAW, JSON albo typ obiektowy)"), kind: .text, createOnly: true),
             EditorField(key: "maxRetries", label: L10n.tr("Maksymalna liczba prób"), kind: .number),
             EditorField(key: "retryDelay", label: L10n.tr("Opóźnienie ponowienia (s)"), kind: .number),
             EditorField(key: "enqueue", label: L10n.tr("Wstawianie włączone"), kind: .bool),
             EditorField(key: "dequeue", label: L10n.tr("Pobieranie włączone"), kind: .bool),
             EditorField(key: "comments", label: L10n.tr("Komentarz"), kind: .text)]
        case .profile:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text, createOnly: true),
             EditorField(key: "limits", label: L10n.tr("Limity (zasób:wartość, np. FAILED_LOGIN_ATTEMPTS:5)"), kind: .list)]
        case .databaseLink:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text, createOnly: true),
             EditorField(key: "public", label: L10n.tr("Publiczne"), kind: .bool, createOnly: true),
             EditorField(key: "user", label: L10n.tr("Użytkownik zdalny"), kind: .text),
             EditorField(key: "password", label: L10n.tr("Hasło (puste — bez zmiany)"), kind: .secret),
             EditorField(key: "connect", label: L10n.tr("Baza (alias TNS albo host:port/usługa)"), kind: .text)]
        case .view:
            [EditorField(key: "name", label: L10n.tr("Nazwa"), kind: .text),
             EditorField(key: "query", label: L10n.tr("Zapytanie"), kind: .multiline),
             EditorField(key: "force", label: L10n.tr("Wymuś (FORCE)"), kind: .bool),
             EditorField(key: "readOnly", label: L10n.tr("Tylko do odczytu"), kind: .bool),
             EditorField(key: "checkOption", label: L10n.tr("WITH CHECK OPTION"), kind: .bool),
             EditorField(key: "comments", label: L10n.tr("Komentarz"), kind: .text)]
        default: []
        }
    }

    /// Powód, dla którego zmian nie da się zapisać (np. łącze bez hasła), albo nil.
    public var issue: String? {
        // Oracle nie dopuszcza cudzysłowu w haśle — usunięcie go po cichu zmieniłoby hasło bez wiedzy użytkownika.
        if kind == .user || kind == .databaseLink, value("password").contains("\"") {
            return L10n.tr("Hasło nie może zawierać cudzysłowu (\")")
        }
        if kind == .databaseLink, !isNew, value("password").isEmpty, ["user", "connect"].contains(where: { value($0) != old($0) }) {
            return L10n.tr("Zmiana użytkownika albo bazy łącza wymaga podania hasła")
        }
        return nil
    }

    func extraStatements(name: String, masked: Bool) -> [String] {
        let qn = Self.q(owner) + "." + Self.q(name)
        func changed(_ keys: [String]) -> Bool { isNew || keys.contains { value($0) != old($0) } }
        switch kind {
        case .library:
            guard changed(["file"]) else { return [] }
            return ["CREATE OR REPLACE LIBRARY \(qn) AS \(Self.literal(value("file")))"]
        case .directory:
            guard changed(["path"]) else { return [] }
            return ["CREATE OR REPLACE DIRECTORY \(Self.q(name)) AS \(Self.literal(value("path")))"]
        case .job:
            var j = SchedulerJob(name: name, action: value("action"))
            j.owner = owner
            j.type = SchedulerJob.JobType(rawValue: value("jobType")) ?? .plsqlBlock
            j.repeatInterval = value("repeat").isEmpty ? nil : value("repeat")
            j.enabled = flag("enabled")
            j.comments = value("comments")
            if isNew { return [Scheduler.createSQL(j)] }
            var o = SchedulerJob(name: name, action: old("action"))
            o.owner = owner
            o.type = SchedulerJob.JobType(rawValue: old("jobType")) ?? .plsqlBlock
            o.repeatInterval = old("repeat").isEmpty ? nil : old("repeat")
            o.enabled = old("enabled") == "Y"
            o.comments = old("comments")
            let sql = Scheduler.alterSQL(from: o, to: j)
            return sql.isEmpty ? [] : [sql]
        case .queue:
            let qname = Self.literal("\(owner).\(name)")
            let table = value("queueTable").uppercased()
            var calls: [String] = []
            func opt(_ k: String, _ arg: String) -> String? { value(k).isEmpty ? nil : "\(arg) => \(value(k))" }
            if isNew {
                if flag("createTable") {
                    let payload = value("payload").isEmpty ? "RAW" : value("payload").uppercased()
                    calls.append("dbms_aqadm.create_queue_table(queue_table => \(Self.literal("\(owner).\(table)")), queue_payload_type => \(Self.literal(payload)))")
                }
                var args = ["queue_name => \(qname)", "queue_table => \(Self.literal("\(owner).\(table)"))"]
                args += [opt("maxRetries", "max_retries"), opt("retryDelay", "retry_delay")].compactMap { $0 }
                if !value("comments").isEmpty { args.append("comment => \(Self.literal(value("comments")))") }
                calls.append("dbms_aqadm.create_queue(\(args.joined(separator: ", ")))")
                if flag("enqueue") || flag("dequeue") {
                    calls.append("dbms_aqadm.start_queue(queue_name => \(qname), enqueue => \(flag("enqueue") ? "true" : "false"), dequeue => \(flag("dequeue") ? "true" : "false"))")
                }
            } else {
                var args: [String] = []
                if value("maxRetries") != old("maxRetries"), let a = opt("maxRetries", "max_retries") { args.append(a) }
                if value("retryDelay") != old("retryDelay"), let a = opt("retryDelay", "retry_delay") { args.append(a) }
                if value("comments") != old("comments") { args.append("comment => \(Self.literal(value("comments")))") }
                if !args.isEmpty { calls.append("dbms_aqadm.alter_queue(queue_name => \(qname), \(args.joined(separator: ", ")))") }
                // Włączenie i wyłączenie wstawiania/pobierania: START_QUEUE / STOP_QUEUE tylko dla zmienionych.
                let start = [("enqueue", value("enqueue") != old("enqueue") && flag("enqueue")), ("dequeue", value("dequeue") != old("dequeue") && flag("dequeue"))]
                let stop = [("enqueue", value("enqueue") != old("enqueue") && !flag("enqueue")), ("dequeue", value("dequeue") != old("dequeue") && !flag("dequeue"))]
                if start.contains(where: \.1) {
                    calls.append("dbms_aqadm.start_queue(queue_name => \(qname), enqueue => \(start[0].1 ? "true" : "false"), dequeue => \(start[1].1 ? "true" : "false"))")
                }
                if stop.contains(where: \.1) {
                    calls.append("dbms_aqadm.stop_queue(queue_name => \(qname), enqueue => \(stop[0].1 ? "true" : "false"), dequeue => \(stop[1].1 ? "true" : "false"))")
                }
            }
            return calls.isEmpty ? [] : ["BEGIN\n  " + calls.joined(separator: ";\n  ") + ";\nEND;"]
        case .profile:
            func limits(_ s: String) -> [String: String] {
                Dictionary(Self.list(s).compactMap { e -> (String, String)? in
                    let p = e.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    return p.count == 2 ? (p[0], p[1]) : nil
                }, uniquingKeysWith: { _, b in b })
            }
            let now = limits(value("limits")), before = limits(old("limits"))
            var parts = now.filter { before[$0.key] != $0.value }.map { "\($0.key) \($0.value)" }
            if !isNew { parts += before.keys.filter { now[$0] == nil }.map { "\($0) DEFAULT" } }
            parts.sort()
            if isNew { return ["CREATE PROFILE \(Self.q(name)) LIMIT " + (parts.isEmpty ? "SESSIONS_PER_USER DEFAULT" : parts.joined(separator: " "))] }
            return parts.isEmpty ? [] : ["ALTER PROFILE \(Self.q(name)) LIMIT " + parts.joined(separator: " ")]
        case .databaseLink:
            guard issue == nil else { return [] }
            let pub = flag("public") ? "PUBLIC " : ""
            let pw = value("password")
            let ident = pw.isEmpty ? "" : " IDENTIFIED BY " + (masked ? "********" : "\"" + pw + "\"")
            let connectTo = value("user").isEmpty ? "" : " CONNECT TO \(Self.q(value("user").uppercased()))\(ident)"
            let create = "CREATE \(pub)DATABASE LINK \(Self.q(name))\(connectTo) USING \(Self.literal(value("connect")))"
            if isNew { return [create] }
            if ["user", "connect"].contains(where: { value($0) != old($0) }) { return ["DROP \(pub)DATABASE LINK \(Self.q(name))", create] }
            if !pw.isEmpty { return ["ALTER \(pub)DATABASE LINK \(Self.q(name)) CONNECT TO \(Self.q(value("user").uppercased()))\(ident)"] }
            return []
        case .view:
            var out: [String] = []
            if changed(["name", "query", "force", "readOnly", "checkOption"]) {
                var q = value("query").trimmingCharacters(in: .whitespacesAndNewlines)
                while q.hasSuffix(";") || q.hasSuffix("/") { q = String(q.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
                let clause = flag("readOnly") ? "\nWITH READ ONLY" : flag("checkOption") ? "\nWITH CHECK OPTION" : ""
                out.append("CREATE OR REPLACE \(flag("force") ? "FORCE " : "")VIEW \(qn) AS\n\(q)\(clause)")
                // Zmiana nazwy: stary widok usuwany dopiero po utworzeniu nowego — błąd CREATE nie zostawia bazy bez widoku (WS2-04).
                if !isNew, old("name") != name { out.append("DROP VIEW \(Self.q(owner)).\(Self.q(old("name")))") }
            }
            if isNew ? !value("comments").isEmpty : value("comments") != old("comments") || old("name") != name {
                out.append("COMMENT ON TABLE \(qn) IS \(Self.literal(value("comments")))")
            }
            return out
        default:
            return []
        }
    }

    /// Tekst widoku ze słownika zawiera klauzule `WITH READ ONLY` / `WITH CHECK OPTION [CONSTRAINT n]` — edytor trzyma je
    /// w polach, więc są zdejmowane z zapytania.
    static func stripViewClauses(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?is)\s+with\s+(read\s+only|check\s+option)(\s+constraint\s+("[^"]+"|\S+))?\s*$"#
        while let r = t.range(of: pattern, options: .regularExpression) { t.removeSubrange(r) }
        return t
    }

    @MainActor
    static func loadExtra(_ kind: Kind, owner: String, name: String, into v: inout [String: String], session s: any DatabaseSession) async throws {
        let b = [BindVariable(name: "o", value: .text(owner)), BindVariable(name: "n", value: .text(name))]
        let bn = [BindVariable(name: "n", value: .text(name))]
        func one(_ sql: String, _ binds: [BindVariable]) async throws -> [String] {
            let (_, rows) = try await s.queryAll(sql, binds: binds, limit: 1)
            guard let r = rows.first else { throw CommandError.invalidArgument("object", L10n.tr("nie znaleziono \(owner).\(name)")) }
            return r.map { $0.displayText ?? "" }
        }
        switch kind {
        case .library:
            v["file"] = try await one("select file_spec from all_libraries where owner = :o and library_name = :n", b)[0]
        case .directory:
            v["path"] = try await one("select directory_path from all_directories where directory_name = :n", bn)[0]
        case .job:
            let j = try await Scheduler.job(owner: owner, name: name, in: s)
            v["jobType"] = j.type.rawValue
            v["action"] = j.action
            v["repeat"] = j.repeatInterval ?? ""
            v["enabled"] = j.enabled ? "Y" : "N"
            v["comments"] = j.comments
        case .queue:
            let r = try await one("""
                select q.queue_table, nvl(t.object_type, t.type), q.max_retries, q.retry_delay, trim(q.enqueue_enabled), trim(q.dequeue_enabled), q.user_comment
                  from all_queues q left join all_queue_tables t on t.owner = q.owner and t.queue_table = q.queue_table
                 where q.owner = :o and q.name = :n
                """, b)
            v["queueTable"] = r[0]; v["payload"] = r[1]; v["maxRetries"] = r[2]; v["retryDelay"] = r[3]
            v["enqueue"] = r[4] == "YES" ? "Y" : "N"; v["dequeue"] = r[5] == "YES" ? "Y" : "N"; v["comments"] = r[6]
            v["createTable"] = "N"
        case .profile:
            let (_, rows) = try await s.queryAll("select resource_name || ':' || limit from dba_profiles where profile = :n and limit <> 'DEFAULT' order by 1",
                                                 binds: bn, limit: 200)
            if rows.isEmpty { _ = try await one("select 1 from dba_profiles where profile = :n", bn) }
            v["limits"] = rows.compactMap { $0.first?.displayText }.joined(separator: ", ")
        case .databaseLink:
            let r = try await one("select username, host, decode(owner, 'PUBLIC', 'Y', 'N') from all_db_links where owner in (:o, 'PUBLIC') and db_link = :n order by decode(owner, :o, 0, 1)", b)
            v["user"] = r[0]; v["connect"] = r[1]; v["public"] = r[2]
        case .view:
            // Pełny tekst z TEXT (LONG; 11g–26ai) — TEXT_VC ma 4000 bajtów i obcina dłuższe widoki, a zapis z obciętym
            // zapytaniem zastąpiłby działający widok niepoprawnym (WS2-04). Tekst krótszy niż TEXT_LENGTH (bajty) — odczyt
            // niepełny, edytor się nie otwiera.
            let r = try await one("select text, text_length from all_views where owner = :o and view_name = :n", b)
            if let length = Int(r[1]), r[0].utf8.count < length {
                throw CommandError.notAvailable(L10n.tr("Nie udało się wczytać pełnego tekstu widoku \(owner).\(name) — edycja wyłączona"))
            }
            v["query"] = Self.stripViewClauses(r[0])
            v["force"] = "N"
            // WITH READ ONLY (więz O) i WITH CHECK OPTION (V) — z więzów widoku (ALL_VIEWS.READ_ONLY jest dopiero od 12c).
            let (_, chk) = try await s.queryAll("select constraint_type from all_constraints where owner = :o and table_name = :n and constraint_type in ('V', 'O')",
                                                binds: b, limit: 10)
            v["readOnly"] = chk.contains { $0.first?.displayText == "O" } ? "Y" : "N"
            v["checkOption"] = chk.contains { $0.first?.displayText == "V" } ? "Y" : "N"
            v["comments"] = (try await s.queryAll("select comments from all_tab_comments where owner = :o and table_name = :n", binds: b, limit: 1)).rows.first?.first?.displayText ?? ""
        default:
            break
        }
    }
}
