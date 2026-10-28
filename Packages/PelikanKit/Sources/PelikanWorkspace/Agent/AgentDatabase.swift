import Foundation
import PelikanDB
import PelikanSQL

/// Baza widziana przez agenta (PROMPT §7.3): własna sesja na połączeniu, odczyt w transakcji READ ONLY z limitami,
/// maskowanie kolumn, dane oznaczone jako niezaufane.
extension Workspace {
    /// Sesja bazy agenta na połączeniu — nigdy sesja użytkownika (MODULE „Pelikan agent”, ACTION = narzędzie).
    func agentDatabaseSession(_ ctx: CommandContext, _ def: ConnectionDefinition, action: String) async throws -> any DatabaseSession {
        guard let id = ctx.invoker.agentSessionID else { throw AgentDenial.sessionClosed }
        let key = SessionKey(connectionID: def.id, purpose: .agent(id))
        let fresh = sessions.existingSession(key) == nil
        let s: any DatabaseSession
        do {
            s = try await sessions.session(key)
        } catch {
            // Błąd łączenia zawiera deskryptor, host albo wyjście ssh — agent zna połączenia tylko z aliasu (PROMPT §7.3 p.1).
            throw CommandError.notAvailable(Self.agentConnectError(error, alias: def.agentAlias))
        }
        if fresh { _ = try? await s.execute("begin dbms_output.enable(null); end;") }
        try? await s.setTags(SessionTags(module: "Pelikan agent", action: action, clientInfo: "Pelikan agent \(id)"))
        return s
    }

    /// Komunikat błędu łączenia dla agenta: alias i sam kod błędu Oracle (ORA-, TNS-, DPI-), bez treści.
    nonisolated static func agentConnectError(_ error: any Error, alias: String) -> String {
        let text = error.localizedDescription
        let code = text.range(of: #"\b(ORA|TNS|DPI)-\d{4,5}\b"#, options: .regularExpression).map { String(text[$0]) }
        return code.map { L10n.tr("Nie udało się połączyć z „\(alias)” (\($0))") } ?? L10n.tr("Nie udało się połączyć z „\(alias)”")
    }

    /// Koniec sesji agenta: ROLLBACK niezatwierdzonych zmian i zamknięcie jego sesji bazy na wszystkich połączeniach.
    public func closeAgentDatabase(session id: String) async {
        for key in [id, "\(id)/run", "\(id)/events"].flatMap({ sessions.keys(purpose: .agent($0)) }) {
            if let s = sessions.existingSession(key) { try? await s.rollback() }
            await sessions.close(key)
        }
    }

    /// Kontekst narzędzia bazy: połączenie z argumentu `connection` i sesja agenta.
    func agentDatabase(_ ctx: CommandContext, action: String) async throws -> (ConnectionDefinition, any DatabaseSession) {
        let def = try agentConnection(ctx.arguments)
        return (def, try await agentDatabaseSession(ctx, def, action: action))
    }
}

/// Reguły odczytu dla agenta (PROMPT §7.3 p.4): jedno zapytanie SELECT/WITH, bez FOR UPDATE i bez funkcji PL/SQL
/// zdefiniowanych w klauzuli WITH (mogą mieć transakcje autonomiczne), bez odwołań do kolumn maskowanych.
public enum AgentQueryRules {
    public enum Violation: Error, LocalizedError, Equatable {
        case notSingleStatement, notQuery(String), locksRows, inlinePLSQL, maskedColumn(String), maskedWildcard, maskedDynamic(String)

        public var errorDescription: String? {
            switch self {
            case .notSingleStatement: "permission_denied: " + L10n.tr("run_query przyjmuje dokładnie jedno polecenie")
            case .notQuery(let c): "permission_denied: " + L10n.tr("run_query przyjmuje tylko SELECT/WITH (rozpoznano: \(c))")
            case .locksRows: "permission_denied: " + L10n.tr("SELECT … FOR UPDATE blokuje wiersze — to nie jest odczyt")
            case .inlinePLSQL: "permission_denied: " + L10n.tr("funkcje i procedury w klauzuli WITH są niedozwolone")
            case .maskedColumn(let c): "permission_denied: " + L10n.tr("kolumna \(c) jest maskowana dla agenta")
            case .maskedWildcard: "permission_denied: " + L10n.tr("przy kolumnach maskowanych funkcja nie może przyjmować * (wszystkich kolumn)")
            case .maskedDynamic(let c): "permission_denied: " + L10n.tr("przy kolumnach maskowanych zapytanie nie może używać \(c) (dynamiczny SQL albo XQuery)")
            }
        }
    }

    /// Tekst jedynego zapytania (bez końcowego średnika) albo naruszenie reguł.
    public static func validate(_ sql: String, masked: Set<String> = []) throws -> String {
        let parts = ScriptSplitter.split(sql)
        guard parts.count == 1, let only = parts.first else { throw Violation.notSingleStatement }
        let c = StatementClassifier.classify(sql)
        guard c.category == .query else { throw Violation.notQuery(c.category.rawValue) }
        guard !c.locksRows else { throw Violation.locksRows }
        let ns = only.text as NSString
        let words = Lexer(only.text).tokenize().filter { !$0.isTrivia }.map {
            (kind: $0.kind, text: ns.substring(with: NSRange(location: $0.start, length: $0.length)).uppercased())
        }
        for (i, w) in words.enumerated() where w.text == "WITH" && i + 1 < words.count && ["FUNCTION", "PROCEDURE"].contains(words[i + 1].text) {
            throw Violation.inlinePLSQL
        }
        for w in words where w.kind == .identifier || w.kind == .quotedIdentifier || w.kind == .keyword {
            let name = w.kind == .quotedIdentifier ? String(w.text.dropFirst().dropLast()) : w.text
            if masked.contains(name) { throw Violation.maskedColumn(name) }
        }
        if !masked.isEmpty { try checkMaskBypass(words, masked: masked) }
        var text = only.text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast() }
        return text
    }

    /// Wywołania i wyrażenia, które czytają kolumny bez ich nazwy w tekście zapytania: dynamiczny SQL (`DBMS_XMLGEN.GETXML
    /// ('select …')`, `CURSOR(…)`) i XQuery (`fn:collection("oradb:/…")`).
    static let dynamicSQL: Set<String> = ["CURSOR", "DBMS_XMLGEN", "DBMS_SQL", "DBMS_XMLQUERY", "XMLQUERY", "XMLTABLE", "XMLEXISTS"]

    /// Słowa, po których nawias otwiera podzapytanie albo grupowanie, nie argumenty funkcji.
    static let subqueryWords: Set<String> = ["FROM", "JOIN", "IN", "EXISTS", "AS", "SELECT", "WHERE", "AND", "OR", "NOT", "ON", "UNION",
                                             "INTERSECT", "MINUS", "EXCEPT", "ALL", "ANY", "SOME", "LATERAL", "APPLY", "WITH", "HAVING", "BY",
                                             "WHEN", "THEN", "ELSE", "USING", "DISTINCT", "PIVOT", "UNPIVOT", "FOR"]

    /// Obejścia maskowania jednym zapytaniem (przy niepustej liście maskowanej): `*` jako argument funkcji
    /// (`JSON_OBJECT(*)`, `JSON_OBJECT(t.*)`, `JSON {*}` — wszystkie kolumny w jednej wartości; `COUNT(*)` dozwolone),
    /// dynamiczny SQL i XQuery (`dynamicSQL`) oraz nazwa kolumny maskowanej w literale (tekst zapytania dla dynamicznego
    /// SQL). To nadal ułatwienie, nie granica — funkcja PL/SQL użytkownika z dynamicznym SQL albo nazwa sklejona z części
    /// je omija (SECURITY.md); granicą są uprawnienia użytkownika bazy agenta.
    static func checkMaskBypass(_ words: [(kind: TokenKind, text: String)], masked: Set<String>) throws {
        var openers: [String] = []   // funkcja każdego otwartego nawiasu ("" — podzapytanie albo grupowanie)
        for (i, w) in words.enumerated() {
            let prev = i > 0 ? words[i - 1] : nil
            switch w.kind {
            case .leftParen:
                let call = prev.map { ($0.kind == .identifier || $0.kind == .keyword) && !subqueryWords.contains($0.text) } ?? false
                openers.append(call ? prev!.text : "")
            case .rightParen:
                _ = openers.popLast()
            case .operator where w.text == "{":
                openers.append("{")
            case .operator where w.text == "}":
                _ = openers.popLast()
            case .operator where w.text == "*":
                // Gwiazdka-symbol wszystkich kolumn (po nawiasie, kropce, przecinku albo klamrze), nie mnożenie.
                let wildcard = prev.map { [.leftParen, .dot, .comma].contains($0.kind) || $0.text == "{" } ?? false
                if wildcard, let f = openers.last, !f.isEmpty, f != "COUNT" { throw Violation.maskedWildcard }
            case .identifier, .keyword:
                if dynamicSQL.contains(w.text) { throw Violation.maskedDynamic(w.text) }
            case .string:
                let parts = w.text.split { !($0.isLetter || $0.isNumber || "_$#".contains($0)) }.map(String.init)
                if let name = parts.first(where: masked.contains) { throw Violation.maskedColumn(name) }
            default:
                break
            }
        }
    }

    /// Nazwy kolumn maskowanych połączenia (ostatni człon `SCHEMAT.TABELA.KOLUMNA`, wielkie litery). Maskowanie
    /// działa po nazwie niezależnie od tabeli — ostrożniej, niż wymaga reguła.
    public static func maskedNames(_ def: ConnectionDefinition) -> Set<String> {
        Set(def.agent.maskedColumns.compactMap { $0.split(separator: ".").last.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "").uppercased() } }
            .filter { !$0.isEmpty })
    }
}

/// Narzędzia bazy agenta: odczyt (PROMPT §7.5). Wszystkie przez sesję agenta; wyniki jako `untrusted_content`.
@MainActor
enum AgentDatabaseCommands {
    static let connectionParam = CommandParameter("connection", .string, L10n.tr("Alias połączenia z list_connections (domyślnie połączenie aktywnego okna albo główne)"))
    static let objectParam = CommandParameter("object", .string, required: true, L10n.tr("Obiekt: NAZWA albo SCHEMAT.NAZWA"))
    static let typeParam = CommandParameter("type", .string, L10n.tr("Typ obiektu, np. PACKAGE, PACKAGE BODY, TABLE (domyślnie wg słownika)"))

    static func bind(_ name: String, _ value: String?) -> BindVariable {
        BindVariable(name: name, value: value.map { .text($0) } ?? .null)
    }

    static func text(_ v: OracleValue, _ ws: Workspace) -> JSONValue {
        if case .null = v { return .null }
        if case .lob(let l) = v { return l.text.map { .string($0) } ?? .null }
        return .string(v.format(ws.settings.valueFormat))
    }

    static func rowsJSON(_ columns: [ColumnInfo], _ rows: [[OracleValue]], _ ws: Workspace) -> JSONValue {
        .array(rows.map { r in .object(Dictionary(uniqueKeysWithValues: zip(columns.map { $0.name.lowercased() }, r.map { text($0, ws) }))) })
    }

    /// Klucz pokrycia (`PACKAGE BODY SCHEMAT.NAZWA`) pasuje do filtra `NAZWA` albo `SCHEMAT.NAZWA` (wielkimi literami)
    /// tylko pełnym członem — `EMP` nie wybiera `XEMP`.
    nonisolated static func coverageKey(_ key: String, matches filter: String) -> Bool {
        key == filter || key.hasSuffix(" " + filter) || (!filter.contains(".") && key.hasSuffix("." + filter))
    }

    /// Obiekt ze słownika: `NAZWA` (bieżący schemat sesji agenta, potem synonim prywatny i publiczny) albo `SCHEMAT.NAZWA`.
    static func resolve(_ raw: String, type: String?, in s: any DatabaseSession) async throws -> DBObject {
        let parts = raw.split(separator: ".", maxSplits: 1).map { String($0).replacingOccurrences(of: "\"", with: "") }
        let owner = parts.count == 2 ? parts[0].uppercased() : nil
        let name = (parts.last ?? raw).uppercased()
        let t = type?.uppercased()
        let (_, rows) = try await s.queryAll("""
            select owner, object_name, object_type from all_objects
             where object_name = :n and owner = nvl(:o, sys_context('userenv', 'current_schema'))
               and (:t is null or object_type = :t) and object_type not like '%PARTITION' and object_type <> 'PACKAGE BODY' || case when :t = 'PACKAGE BODY' then 'X' end
             order by decode(object_type, 'PACKAGE', 1, 'TYPE', 1, 'TABLE', 2, 'VIEW', 2, 3)
            """, binds: [bind("n", name), bind("o", owner), bind("t", t)], limit: 1)
        if let r = rows.first, let o = r[0].displayText, let n = r[1].displayText, let ty = r[2].displayText.flatMap(DBObjectType.init(rawValue:)) {
            return DBObject(owner: o, name: n, type: ty)
        }
        if owner == nil {
            let (_, syn) = try await s.queryAll("""
                select table_owner, table_name from all_synonyms
                 where synonym_name = :n and owner in (sys_context('userenv', 'current_schema'), 'PUBLIC')
                 order by decode(owner, 'PUBLIC', 2, 1)
                """, binds: [bind("n", name)], limit: 1)
            if let r = syn.first, let o = r[0].displayText, let n = r[1].displayText {
                return try await resolve("\"\(o)\".\"\(n)\"", type: type, in: s)
            }
        }
        throw CommandError.notAvailable(L10n.tr("Nie znaleziono obiektu \(raw)"))
    }

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "agent.searchObjects", title: L10n.tr("Szukaj obiektów (agent)"), category: .help,
                                      parameters: [connectionParam, CommandParameter("name", .string, required: true, L10n.tr("Nazwa albo wzorzec z % i _")),
                                                   typeParam, CommandParameter("owner", .string, L10n.tr("Schemat"))],
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Obiekty bazy pasujące do nazwy (ALL_OBJECTS): schemat, nazwa, typ, stan, ostatnia zmiana; do 200."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "search_objects")
                let (cols, rows) = try await s.queryAll("""
                    select owner, object_name, object_type, status, to_char(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') last_ddl_time
                      from all_objects
                     where object_name like upper(:n) and (:t is null or object_type = upper(:t)) and (:o is null or owner = upper(:o))
                       and object_type not like '%PARTITION' and object_type not in ('LOB', 'INDEX SUBPARTITION')
                       and rownum <= 200
                    """, binds: [bind("n", ctx.arguments.string("name")), bind("t", ctx.arguments.string("type")), bind("o", ctx.arguments.string("owner"))], limit: 200)
                return CommandResult(value: untrusted(rowsJSON(cols, rows, ctx.workspace)))
            },
            Command(CommandDescriptor(id: "agent.describe", title: L10n.tr("Opis obiektu (agent)"), category: .help,
                                      parameters: [connectionParam, objectParam, typeParam], agent: .read, effect: .none,
                                      summary: L10n.tr("Opis obiektu: tabela/widok — kolumny z typami i komentarzami; program — parametry procedur i funkcji; sekwencja — ustawienia."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "describe_object")
                let o = try await resolve(ctx.arguments.string("object") ?? "", type: ctx.arguments.string("type"), in: s)
                let b = [bind("o", o.owner), bind("n", o.name)]
                var out: [String: JSONValue] = ["owner": .string(o.owner), "name": .string(o.name), "type": .string(o.type.rawValue)]
                switch o.type {
                case .table, .view, .materializedView:
                    let (c, r) = try await s.queryAll("""
                        select c.column_name, c.data_type, c.data_length, c.data_precision, c.data_scale, c.nullable, m.comments
                          from all_tab_columns c left join all_col_comments m on m.owner = c.owner and m.table_name = c.table_name and m.column_name = c.column_name
                         where c.owner = :o and c.table_name = :n order by c.column_id
                        """, binds: b, limit: 2000)
                    out["columns"] = rowsJSON(c, r, ctx.workspace)
                    out["comment"] = try await s.scalar("select comments from all_tab_comments where owner = :o and table_name = :n", binds: b).map { .string($0) } ?? .null
                case .sequence:
                    let (c, r) = try await s.queryAll("select min_value, max_value, increment_by, cycle_flag, cache_size, last_number from all_sequences where sequence_owner = :o and sequence_name = :n", binds: b, limit: 1)
                    out["sequence"] = rowsJSON(c, r, ctx.workspace)
                default:
                    let (c, r) = try await s.queryAll("""
                        select object_name subprogram, overload, argument_name, position, in_out, data_type, type_name, defaulted
                          from all_arguments
                         where owner = :o and data_level = 0 and (package_name = :n or package_name is null and object_name = :n)
                         order by 1, 2, 4
                        """, binds: b, limit: 5000)
                    out["arguments"] = rowsJSON(c, r, ctx.workspace)
                    out["status"] = try await s.scalar("select status from all_objects where owner = :o and object_name = :n and object_type = :t",
                                                       binds: b + [bind("t", o.type.rawValue)]).map { .string($0) } ?? .null
                }
                return CommandResult(value: untrusted(.object(out)))
            },
            Command(CommandDescriptor(id: "agent.source", title: L10n.tr("Źródło programu (agent)"), category: .help,
                                      parameters: [connectionParam, objectParam, typeParam], agent: .read, effect: .none,
                                      summary: L10n.tr("Kod źródłowy programu z ALL_SOURCE (pakiet: specyfikacja i ciało) jako CREATE OR REPLACE."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "get_source")
                let o = try await resolve(ctx.arguments.string("object") ?? "", type: ctx.arguments.string("type"), in: s)
                var text = try await MetadataProvider.source(of: o, in: s) + "\n/\n"
                if ctx.arguments.string("type") == nil, o.type == .package || o.type == .type {
                    let body = DBObject(owner: o.owner, name: o.name, type: o.type == .package ? .packageBody : .typeBody)
                    if let b = try? await MetadataProvider.source(of: body, in: s) { text += "\n" + b + "\n/\n" }
                }
                return CommandResult(value: untrusted(.object(["owner": .string(o.owner), "name": .string(o.name), "type": .string(o.type.rawValue), "source": .string(text)])))
            },
            Command(CommandDescriptor(id: "agent.ddl", title: L10n.tr("DDL obiektu (agent)"), category: .help,
                                      parameters: [connectionParam, objectParam, typeParam], agent: .read, effect: .none,
                                      summary: L10n.tr("DDL obiektu z DBMS_METADATA (bez atrybutów składowania)."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "get_ddl")
                let o = try await resolve(ctx.arguments.string("object") ?? "", type: ctx.arguments.string("type"), in: s)
                return CommandResult(value: untrusted(.object(["ddl": .string(try await MetadataProvider.ddl(of: o, in: s))])))
            },
            Command(CommandDescriptor(id: "agent.dependencies", title: L10n.tr("Zależności obiektu (agent)"), category: .help,
                                      parameters: [connectionParam, objectParam, typeParam], agent: .read, effect: .none,
                                      summary: L10n.tr("Obiekty, od których obiekt zależy (uses) i które zależą od niego (usedBy), z ALL_DEPENDENCIES."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "get_dependencies")
                let o = try await resolve(ctx.arguments.string("object") ?? "", type: ctx.arguments.string("type"), in: s)
                let b = [bind("o", o.owner), bind("n", o.name)]
                let (c1, uses) = try await s.queryAll("select distinct referenced_owner owner, referenced_name name, referenced_type type from all_dependencies where owner = :o and name = :n and referenced_owner <> 'SYS' order by 1, 2", binds: b, limit: 2000)
                let (c2, used) = try await s.queryAll("select distinct owner, name, type from all_dependencies where referenced_owner = :o and referenced_name = :n order by 1, 2", binds: b, limit: 2000)
                return CommandResult(value: untrusted(.object(["uses": rowsJSON(c1, uses, ctx.workspace), "usedBy": rowsJSON(c2, used, ctx.workspace)])))
            },
            Command(CommandDescriptor(id: "agent.findUsages", title: L10n.tr("Użycia obiektu (agent)"), category: .help,
                                      parameters: [connectionParam, objectParam, typeParam], agent: .read, effect: .none,
                                      summary: L10n.tr("Linie kodu obiektów zależnych, w których występuje nazwa obiektu (do 500)."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "find_usages")
                let o = try await resolve(ctx.arguments.string("object") ?? "", type: ctx.arguments.string("type"), in: s)
                let (c, r) = try await s.queryAll("""
                    select s.owner, s.name, s.type, s.line, rtrim(s.text, chr(10)) text
                      from all_source s join (select distinct owner, name, type from all_dependencies where referenced_owner = :o and referenced_name = :n) d
                        on s.owner = d.owner and s.name = d.name and s.type = d.type
                     where upper(s.text) like '%' || :n || '%' and rownum <= 500
                    """, binds: [bind("o", o.owner), bind("n", o.name)], limit: 500)
                return CommandResult(value: untrusted(rowsJSON(c, r, ctx.workspace)))
            },
            Command(CommandDescriptor(id: "agent.query", title: L10n.tr("Zapytanie (agent)"), category: .help,
                                      parameters: [connectionParam, CommandParameter("sql", .sql, required: true, L10n.tr("Jedno zapytanie SELECT albo WITH")),
                                                   CommandParameter("maxRows", .integer, L10n.tr("Limit wierszy (nie więcej niż w ustawieniach)"))],
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Wykonuje jedno zapytanie SELECT/WITH w transakcji READ ONLY w sesji agenta, z limitem wierszy, czasu i rozmiaru wyniku; kolumny maskowane zakryte."),
                                      inMenu: false, feature: "AI-SEC-006")) { ctx in
                let ws = ctx.workspace
                let def = try ws.agentConnection(ctx.arguments)
                let masked = AgentQueryRules.maskedNames(def)
                let sql = try AgentQueryRules.validate(ctx.arguments.string("sql") ?? "", masked: masked)
                let s = try await ws.agentDatabaseSession(ctx, def, action: "run_query")
                let limits = ws.settings.agent
                // Ujemny limit dałby pobieranie po 0 wierszy (hasMore bez końca) — najmniej 0.
                let maxRows = max(0, min(Int(ctx.arguments.int("maxRows") ?? Int64(limits.queryMaxRows)), limits.queryMaxRows))
                // Otwarta transakcja agenta (niezatwierdzone DML) nie może zostać wycofana przez odczyt — wtedy zapytanie
                // idzie w niej (nadal tylko SELECT), w przeciwnym razie w osobnej transakcji READ ONLY.
                let pending = try await s.scalar("select dbms_transaction.local_transaction_id from dual") != nil
                if !pending { _ = try await s.execute("set transaction read only") }
                do {
                    let r = try await s.execute(sql, binds: [], options: ExecuteOptions(callTimeoutMs: UInt32(clamping: min(max(limits.queryTimeoutSeconds, 1), AgentSettings.queryTimeoutRange.upperBound) * 1000), lobLimit: 16_000))
                    guard let rs = r.resultSet else { throw AgentQueryRules.Violation.notQuery("?") }
                    var rows: [[JSONValue]] = [], bytes = 0, truncated = false
                    let maskIndex = Set(rs.columns.enumerated().filter { masked.contains($0.element.name.uppercased()) }.map(\.offset))
                    fetch: while true {
                        let batch = try await s.fetch(rs.id, maxRows: min(500, maxRows + 1 - rows.count))
                        for row in batch.rows {
                            if rows.count >= maxRows { truncated = true; break fetch }
                            let values = row.enumerated().map { maskIndex.contains($0.offset) ? JSONValue.string("***") : text($0.element, ws) }
                            bytes += values.reduce(0) { $0 + $1.description.utf8.count }
                            if bytes > limits.queryMaxBytes { truncated = true; break fetch }
                            rows.append(values)
                        }
                        if !batch.hasMore { break }
                    }
                    await s.closeResultSet(rs.id)
                    if !pending { try? await s.rollback() }
                    return CommandResult(value: untrusted(.object([
                        "columns": .array(rs.columns.map { .object(["name": .string($0.name), "type": .string($0.typeName), "masked": .bool(masked.contains($0.name.uppercased()))]) }),
                        "rows": .array(rows.map { .array($0) }), "rowCount": .int(Int64(rows.count)), "truncated": .bool(truncated),
                        "readOnlyTransaction": .bool(!pending),
                    ])))
                } catch {
                    if !pending { try? await s.rollback() }
                    throw error
                }
            },
            Command(CommandDescriptor(id: "agent.explain", title: L10n.tr("Plan wykonania (agent)"), category: .help,
                                      parameters: [connectionParam, CommandParameter("sql", .sql, required: true, L10n.tr("Jedno zapytanie albo DML (nie jest wykonywane)"))],
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("EXPLAIN PLAN i DBMS_XPLAN.DISPLAY dla jednego zapytania albo polecenia DML — polecenie nie jest wykonywane."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "explain_plan")
                let plan = try await AgentChanges.explain(ctx.arguments.string("sql") ?? "", in: s)
                return CommandResult(value: untrusted(.object(["plan": .string(plan.text), "estimatedRows": plan.rows.map { .int($0) } ?? .null])))
            },
            Command(CommandDescriptor(id: "agent.compileErrors", title: L10n.tr("Błędy kompilacji (agent)"), category: .help,
                                      parameters: [connectionParam, objectParam, typeParam], agent: .read, effect: .none,
                                      summary: L10n.tr("Błędy i ostrzeżenia kompilacji obiektu z ALL_ERRORS (typ, linia, kolumna, tekst)."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "get_compile_errors")
                let o = try await resolve(ctx.arguments.string("object") ?? "", type: ctx.arguments.string("type"), in: s)
                let (c, r) = try await s.queryAll("""
                    select type, line, position, attribute, text from all_errors
                     where owner = :o and name = :n and (:t is null or type = upper(:t)) order by type, sequence
                    """, binds: [bind("o", o.owner), bind("n", o.name), bind("t", ctx.arguments.string("type"))], limit: 2000)
                return CommandResult(value: untrusted(rowsJSON(c, r, ctx.workspace)))
            },
            Command(CommandDescriptor(id: "agent.dbmsOutput", title: L10n.tr("DBMS_OUTPUT sesji agenta"), category: .help,
                                      parameters: [connectionParam], agent: .read, effect: .none,
                                      summary: L10n.tr("Linie DBMS_OUTPUT z wywołań agenta w jego sesji (odczyt opróżnia bufor)."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "get_dbms_output")
                var lines: [JSONValue] = []
                while lines.count < 10_000 {
                    let r = try await s.execute("begin dbms_output.get_line(:l, :st); end;",
                                                binds: [BindVariable(name: "l", type: .varchar2, direction: .output, maxSize: 32767),
                                                        BindVariable(name: "st", type: .number, direction: .output)])
                    guard r.outBinds["st"]?.displayText == "0" else { break }
                    lines.append(.string(r.outBinds["l"]?.displayText ?? ""))
                }
                return CommandResult(value: untrusted(.array(lines)))
            },
            Command(CommandDescriptor(id: "agent.listTests", title: L10n.tr("Testy utPLSQL (agent)"), category: .help,
                                      parameters: [connectionParam, CommandParameter("owner", .string, L10n.tr("Schemat (domyślnie bieżący)"))],
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Suity, konteksty i testy utPLSQL schematu (ut_runner.get_suites_info) ze ścieżkami do uruchomienia."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "list_tests")
                var owner = ctx.arguments.string("owner")?.uppercased() ?? ""
                if owner.isEmpty { owner = try await s.scalar("select sys_context('userenv', 'current_schema') from dual") ?? "" }
                let (c, r) = try await s.queryAll("""
                    select object_owner, object_name, item_name, item_type, item_line_no, path, disabled_flag, item_description
                      from table(ut_runner.get_suites_info(:o)) order by path
                    """, binds: [bind("o", owner)], limit: 20_000)
                return CommandResult(value: untrusted(rowsJSON(c, r, ctx.workspace)))
            },
            Command(CommandDescriptor(id: "agent.testResults", title: L10n.tr("Wyniki testów (agent)"), category: .help,
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Ostatni przebieg utPLSQL w Pelikanie: liczniki, czas i testy nieudane z oczekiwaniami i stosem błędu."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                guard let run = ctx.workspace.lastUtplsqlRun else { return CommandResult(value: .null) }
                let failed: [JSONValue] = run.tests.filter { $0.status == .failure || $0.status == .error }.map { t in
                    .object(["path": .string(t.runPath), "status": .string(t.status.rawValue), "errorStack": .string(t.errorStack),
                             "expectations": .array(t.expectations.map { .object(["description": .string($0.description), "message": .string($0.message)]) })])
                }
                return CommandResult(value: untrusted(.object([
                    "paths": .array(run.paths.map { .string($0) }), "finished": .bool(run.finished),
                    "success": .int(Int64(run.counter.success)), "failure": .int(Int64(run.counter.failure)), "error": .int(Int64(run.counter.error)),
                    "disabled": .int(Int64(run.counter.disabled)), "seconds": run.executionTime.map { .double($0) } ?? .null, "failed": .array(failed),
                ])))
            },
            Command(CommandDescriptor(id: "agent.coverage", title: L10n.tr("Pokrycie kodu (agent)"), category: .help,
                                      parameters: [CommandParameter("object", .string, L10n.tr("Obiekt SCHEMAT.NAZWA (domyślnie wszystkie)"))],
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Pokrycie z ostatniego przebiegu utPLSQL z pokryciem: procent oraz linie pokryte i niepokryte."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let cov = ctx.workspace.lastUtplsqlRun?.coverage ?? [:]
                let filter = ctx.arguments.string("object")?.uppercased()
                let items: [JSONValue] = cov.filter { filter == nil || coverageKey($0.key, matches: filter!) }.sorted { $0.key < $1.key }.map { k, v in
                    .object(["object": .string(k), "percent": .double((v.percent * 10).rounded() / 10),
                             "covered": .array(v.covered.sorted().map { .int(Int64($0)) }), "uncovered": .array(v.uncovered.sorted().map { .int(Int64($0)) })])
                }
                return CommandResult(value: untrusted(.array(items)))
            },
            Command(CommandDescriptor(id: "agent.sessions", title: L10n.tr("Sesje bazy (agent)"), category: .help,
                                      parameters: [connectionParam], agent: .read, effect: .none,
                                      summary: L10n.tr("Sesje użytkowników bazy z V$SESSION (SID, użytkownik, stan, MODULE/ACTION, SQL_ID, zdarzenie) — bez nazw użytkowników systemu i hostów."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let (_, s) = try await ctx.workspace.agentDatabase(ctx, action: "session_list")
                let (c, r) = try await s.queryAll("""
                    select sid, serial#, username, status, schemaname, module, action, sql_id, event, seconds_in_wait,
                           to_char(logon_time, 'YYYY-MM-DD HH24:MI:SS') logon_time
                      from v$session where type = 'USER' and rownum <= 500 order by sid
                    """, limit: 500)
                return CommandResult(value: untrusted(rowsJSON(c, r, ctx.workspace)))
            },
            Command(CommandDescriptor(id: "agent.openObject", title: L10n.tr("Otwórz obiekt (agent)"), category: .help,
                                      parameters: [connectionParam, objectParam, typeParam, CommandParameter("line", .integer, L10n.tr("Linia do pokazania"))],
                                      agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Otwiera źródło programu (albo DDL innego obiektu) w nowym oknie, bez kompilacji; cofnięcie sesji agenta zamyka okno."),
                                      inMenu: false, feature: "AI-TOOL-002")) { ctx in
                let ws = ctx.workspace
                let (def, s) = try await ws.agentDatabase(ctx, action: "open_object")
                let o = try await resolve(ctx.arguments.string("object") ?? "", type: ctx.arguments.string("type"), in: s)
                let doc: Document
                if o.type.isProgram {
                    var sources = [try await MetadataProvider.source(of: o, in: s)]
                    if o.type == .package || o.type == .type,
                       let b = try? await MetadataProvider.source(of: DBObject(owner: o.owner, name: o.name, type: o.type == .package ? .packageBody : .typeBody), in: s) {
                        sources.append(b)
                    }
                    // Okno programu bez „/” (D192), chyba że preferencja.
                    doc = ws.newDocument(.program, text: ProgramText.join(sources, slash: ws.settings.programUnitSlash))
                } else {
                    doc = ws.newDocument(.sql, text: try await MetadataProvider.ddl(of: o, in: s))
                }
                doc.connectionID = def.id
                doc.isModified = false
                if let line = ctx.arguments.int("line") {
                    let p = AgentCommands.position(doc.text, line: Int(line))
                    doc.selectedRange = p..<p
                }
                ws.recordAgentEdit(ctx, doc, before: "", created: true)
                return CommandResult(value: .object(["window": .string(Workspace.agentWindowID(doc))]))
            },
        ]
    }
}
