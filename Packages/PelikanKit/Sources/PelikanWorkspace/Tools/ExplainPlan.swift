import Foundation
import PelikanDB
import PelikanSQL

/// Wiersz planu wykonania (PLAN_TABLE).
public struct PlanLine: Sendable, Hashable, Identifiable {
    public var id: Int
    public var parentID: Int?
    public var depth: Int
    public var position: Int
    public var operation: String
    public var options: String
    public var objectOwner: String
    public var objectName: String
    public var optimizer: String
    public var cost: Int64?
    public var cardinality: Int64?
    public var bytes: Int64?
    public var cpuCost: Int64?
    public var ioCost: Int64?
    public var time: Int64?
    public var accessPredicates: String
    public var filterPredicates: String
    /// Kolejność wykonania (1 = pierwszy krok).
    public var executionOrder = 0
    public var children: [PlanLine]?

    public var title: String { options.isEmpty ? operation : "\(operation) \(options)" }
    public var object: String { objectName.isEmpty ? "" : (objectOwner.isEmpty ? objectName : "\(objectOwner).\(objectName)") }
}

/// Cel optymalizatora dla Explain Plan (UG 17.1 „Optimizer goal”).
public enum OptimizerGoal: String, Sendable, CaseIterable, Codable {
    case session, allRows = "ALL_ROWS", firstRows = "FIRST_ROWS", firstRows1 = "FIRST_ROWS_1", firstRows10 = "FIRST_ROWS_10",
         firstRows100 = "FIRST_ROWS_100", firstRows1000 = "FIRST_ROWS_1000"

    public var displayName: String { self == .session ? L10n.tr("Jak w sesji") : rawValue }
}

/// Formaty DBMS_XPLAN (PD-OPT-003).
public enum PlanFormat: String, Sendable, CaseIterable {
    case text, html, xml
}

public struct ExplainPlanResult: Sendable {
    public var statementID: String
    public var roots: [PlanLine]
    public var lines: [PlanLine]
    /// Tekst DBMS_XPLAN.DISPLAY (TYPICAL).
    public var text: String
    public var html: String
    public var xml: String
    /// Polecenie, dla którego wyznaczono plan (bez wskazówki celu optymalizatora) — nowe polecenie rozwija całe drzewo.
    public var sql = ""

    /// Wiersze w kolejności wykonania (nawigacja Pierwszy/Poprzedni/Następny/Ostatni).
    public var executionOrder: [PlanLine] { lines.sorted { $0.executionOrder < $1.executionOrder } }

    /// Kroki z dziećmi — gałęzie drzewa planu, które można rozwinąć („Rozwiń wszystko”, PD-OPT-001).
    public var branchIDs: Set<Int> { Set(lines.compactMap(\.parentID)) }

    /// Przodkowie kroku od rodzica do korzenia — gałęzie do rozwinięcia, żeby zaznaczony krok był widoczny w drzewie.
    public func ancestors(of id: Int) -> [Int] {
        let parent = Dictionary(lines.map { ($0.id, $0.parentID) }, uniquingKeysWith: { a, _ in a })
        var out: [Int] = []
        var current = parent[id] ?? nil
        while let p = current, !out.contains(p) {
            out.append(p)
            current = parent[p] ?? nil
        }
        return out
    }
}

/// Explain Plan (PD-OPT-001..003) w osobnej sesji narzędzi — EXPLAIN PLAN wstawia wiersze do PLAN_TABLE, więc nie może
/// działać w sesji okna z transakcją użytkownika.
public enum ExplainPlan {
    /// Polecenie do planu: zaznaczenie z okna PL/SQL — bez `INTO` listy zmiennych (SELECT) i bez `RETURNING … INTO`
    /// (DML), zmienne, stałe i parametry PL/SQL widoczne w pozycji zastąpione zmiennymi wiązanymi (PD-OPT-002),
    /// bez końcowego średnika.
    public static func prepare(_ sql: String, plsqlContext: String? = nil, offset: Int = 0) -> String {
        var text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast() }
        var names = Set<String>()
        if let ctx = plsqlContext {
            let c = CompletionContext.analyze(ctx, offset: offset)
            names = Set(c.declarations.filter { [.variable, .constant, .parameter].contains($0.kind) }.map { $0.name.uppercased() })
        }
        let ns = text as NSString
        let tokens = Lexer(text).tokenize()
        let sig = tokens.filter { !$0.isTrivia }
        func upper(_ t: Token) -> String { ns.substring(with: NSRange(location: t.start, length: t.length)).uppercased() }
        var removed: Range<Int>?
        if let first = sig.first.map(upper) {
            var depth = 0, intoStart: Int?, returningStart: Int?
            for t in sig {
                if t.kind == .leftParen { depth += 1 } else if t.kind == .rightParen { depth -= 1 }
                guard depth == 0 else { continue }
                let u = upper(t)
                if ["SELECT", "WITH"].contains(first) {
                    if u == "INTO", intoStart == nil { intoStart = t.start }
                    if u == "FROM", let s = intoStart { removed = s..<t.start; break }
                } else if ["INSERT", "UPDATE", "DELETE", "MERGE"].contains(first), u == "RETURNING" || u == "RETURN" {
                    returningStart = t.start
                }
            }
            if let r = returningStart { removed = r..<ns.length }
        }
        var out = ""
        var last = 0
        for (i, t) in tokens.enumerated() {
            if let r = removed, r.contains(t.start) {
                if t.start == r.lowerBound { out += ns.substring(with: NSRange(location: last, length: t.start - last)) }
                last = t.end
                continue
            }
            guard t.kind == .identifier, names.contains(upper(t)) else { continue }
            let prev = tokens[..<i].last { !$0.isTrivia }
            let next = tokens[(i + 1)...].first { !$0.isTrivia }
            // Pola rekordów (r.pole) i kwalifikowane nazwy (t.kolumna) zostają bez zmian.
            if prev?.kind == .dot || next?.kind == .dot { continue }
            out += ns.substring(with: NSRange(location: last, length: t.start - last)) + ":" + ns.substring(with: NSRange(location: t.start, length: t.length))
            last = t.end
        }
        out += ns.substring(from: last)
        return out.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// EXPLAIN PLAN w sesji narzędzi, drzewo z PLAN_TABLE i teksty DBMS_XPLAN; wiersze planu usuwane, transakcja wycofana.
    public static func explain(_ sql: String, goal: OptimizerGoal = .session, in s: any DatabaseSession) async throws -> ExplainPlanResult {
        let id = "PLK" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)
        do {
            _ = try await s.execute("explain plan set statement_id = '\(id)' for \(withGoal(sql, goal))")
        } catch {
            try? await s.rollback()
            throw error
        }
        let b = [BindVariable(name: "id", value: .text(id))]
        let (_, rows) = try await s.queryAll("""
            select id, parent_id, depth, position, operation, nvl(options, ' '), nvl(object_owner, ' '), nvl(object_name, ' '), nvl(optimizer, ' '),
                   cost, cardinality, bytes, cpu_cost, io_cost, time, nvl(access_predicates, ' '), nvl(filter_predicates, ' ')
              from plan_table where statement_id = :id order by id
            """, binds: b, limit: 10_000)
        func int(_ v: OracleValue) -> Int64? { v.displayText.flatMap { Int64($0) } }
        func str(_ v: OracleValue) -> String { (v.displayText ?? "").trimmingCharacters(in: .whitespaces) }
        var lines = rows.map { r in
            PlanLine(id: Int(int(r[0]) ?? 0), parentID: int(r[1]).map { Int($0) }, depth: Int(int(r[2]) ?? 0), position: Int(int(r[3]) ?? 0),
                     operation: str(r[4]), options: str(r[5]), objectOwner: str(r[6]), objectName: str(r[7]), optimizer: str(r[8]),
                     cost: int(r[9]), cardinality: int(r[10]), bytes: int(r[11]), cpuCost: int(r[12]), ioCost: int(r[13]), time: int(r[14]),
                     accessPredicates: str(r[15]), filterPredicates: str(r[16]))
        }
        lines = numberExecution(lines)
        let text = try await display(id, format: "TYPICAL", in: s)
        let html = try await s.scalar("""
            select dbms_xplan.display_plan(table_name => 'PLAN_TABLE', statement_id => :id, format => 'TYPICAL', type => 'HTML') from dual
            """, binds: b) ?? ""
        let xml = try await s.scalar("""
            select dbms_xplan.display_plan(table_name => 'PLAN_TABLE', statement_id => :id, format => 'TYPICAL', type => 'XML') from dual
            """, binds: b) ?? ""
        try? await s.rollback()
        return ExplainPlanResult(statementID: id, roots: tree(lines), lines: lines, text: text, html: html, xml: xml, sql: sql)
    }

    /// Cel optymalizatora jako wskazówka w głównym poleceniu (bez zmiany parametrów sesji, do których odczytu trzeba
    /// uprawnień do V$PARAMETER).
    nonisolated static func withGoal(_ sql: String, _ goal: OptimizerGoal) -> String {
        let hint: String
        switch goal {
        case .session: return sql
        case .allRows: hint = "ALL_ROWS"
        case .firstRows: hint = "FIRST_ROWS"
        case .firstRows1: hint = "FIRST_ROWS(1)"
        case .firstRows10: hint = "FIRST_ROWS(10)"
        case .firstRows100: hint = "FIRST_ROWS(100)"
        case .firstRows1000: hint = "FIRST_ROWS(1000)"
        }
        let ns = sql as NSString
        var depth = 0
        for tok in Lexer(sql).tokenize() where !tok.isTrivia {
            if tok.kind == .leftParen { depth += 1 } else if tok.kind == .rightParen { depth -= 1 }
            let w = ns.substring(with: NSRange(location: tok.start, length: tok.length)).uppercased()
            if depth == 0, ["SELECT", "UPDATE", "DELETE", "INSERT", "MERGE"].contains(w) {
                return ns.replacingCharacters(in: NSRange(location: tok.end, length: 0), with: " /*+ \(hint) */")
            }
        }
        return sql
    }

    static func display(_ id: String, format: String, in s: any DatabaseSession) async throws -> String {
        let (_, rows) = try await s.queryAll("select plan_table_output from table(dbms_xplan.display('PLAN_TABLE', :id, :f))",
                                             binds: [BindVariable(name: "id", value: .text(id)), BindVariable(name: "f", value: .text(format))], limit: 5000)
        return rows.map { $0.first?.displayText ?? "" }.joined(separator: "\n")
    }

    /// Kolejność wykonania: przejście post-order (dzieci wg POSITION) — liść najbardziej po lewej jest pierwszy.
    nonisolated static func numberExecution(_ lines: [PlanLine]) -> [PlanLine] {
        var byParent: [Int?: [PlanLine]] = [:]
        for l in lines { byParent[l.parentID, default: []].append(l) }
        var order: [Int: Int] = [:]
        var n = 0
        func visit(_ l: PlanLine) {
            for c in (byParent[l.id] ?? []).sorted(by: { ($0.position, $0.id) < ($1.position, $1.id) }) { visit(c) }
            n += 1
            order[l.id] = n
        }
        for r in (byParent[nil] ?? []).sorted(by: { $0.id < $1.id }) { visit(r) }
        return lines.map { var l = $0; l.executionOrder = order[l.id] ?? 0; return l }
    }

    nonisolated static func tree(_ lines: [PlanLine]) -> [PlanLine] {
        var byParent: [Int?: [PlanLine]] = [:]
        for l in lines { byParent[l.parentID, default: []].append(l) }
        func build(_ l: PlanLine) -> PlanLine {
            var c = l
            let kids = (byParent[l.id] ?? []).sorted { ($0.position, $0.id) < ($1.position, $1.id) }
            c.children = kids.isEmpty ? nil : kids.map(build)
            return c
        }
        return (byParent[nil] ?? []).sorted { $0.id < $1.id }.map(build)
    }
}

/// Komendy Explain Plan (PD-OPT-001..003).
@MainActor
enum PlanCommands {
    /// Polecenie do planu z okna: zaznaczenie albo polecenie pod kursorem; okno planu — cały tekst.
    static func statement(of doc: Document) -> String {
        let ns = doc.text as NSString
        let sel = doc.selectedRange
        if !sel.isEmpty, sel.upperBound <= ns.length {
            let raw = ns.substring(with: NSRange(location: sel.lowerBound, length: sel.count))
            return doc.kind == .sql ? ExplainPlan.prepare(raw) : ExplainPlan.prepare(raw, plsqlContext: doc.text, offset: sel.lowerBound)
        }
        if doc.kind == .explainPlan { return ExplainPlan.prepare(doc.text) }
        let parts = ScriptSplitter.split(doc.text)
        guard let s = ScriptSplitter.statement(at: sel.lowerBound, in: parts) else { return ExplainPlan.prepare(doc.text) }
        return ExplainPlan.prepare(s.text)
    }

    /// Aktywne okno planu z planem, który ma gałęzie (komendy drzewa: Rozwiń/Zwiń wszystkie gałęzie).
    static func treeDocument(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, d.kind == .explainPlan, let p = d.plan, !p.branchIDs.isEmpty else { return nil }
        return d
    }

    /// Plan dla okna planu w sesji narzędzi połączenia okna.
    static func run(_ doc: Document, in ws: Workspace) async throws -> ExplainPlanResult {
        guard let conn = ws.effectiveConnection(of: doc) else { throw CommandError.notConnected }
        let s = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("plan")))
        doc.isExecuting = true
        defer { doc.isExecuting = false }
        do {
            let r = try await ExplainPlan.explain(ExplainPlan.prepare(doc.text), goal: doc.planGoal, in: s)
            doc.plan = r
            doc.planError = nil
            return r
        } catch {
            doc.planError = error.localizedDescription
            throw error
        }
    }

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "tools.explainPlan", title: L10n.tr("Explain Plan"), category: .tools,
                                      pd: ["f5"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Plan wykonania zaznaczenia albo polecenia pod kursorem w oknie planu; w kodzie PL/SQL zmienne zamieniane na wiązane, INTO pomijane."),
                                      feature: "PD-OPT-002"),
                    validate: { ws in ws.activeDocument.map { [.sql, .program, .test, .explainPlan].contains($0.kind) } ?? false }) { ctx in
                let ws = ctx.workspace
                guard let src = ws.activeDocument else { return .ok }
                let target: Document
                if src.kind == .explainPlan {
                    target = src
                } else {
                    let sql = statement(of: src)
                    guard !sql.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak polecenia do planu")) }
                    let conn = ws.effectiveConnection(of: src)
                    target = ws.newDocument(.explainPlan, text: sql)
                    target.connectionID = conn
                    target.isModified = false
                }
                let r = try await run(target, in: ws)
                return CommandResult(message: L10n.tr("Kroków planu: \(r.lines.count)"), value: .string(r.text))
            },
            Command(CommandDescriptor(id: "plan.expandAll", title: L10n.tr("Rozwiń wszystkie gałęzie"), category: .tools, submenu: L10n.tr("Plan"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Rozwija wszystkie gałęzie drzewa planu w aktywnym oknie planu."), feature: "PD-OPT-001"),
                    validate: { treeDocument($0) != nil }) { ctx in
                guard let doc = treeDocument(ctx.workspace), let plan = doc.plan else { return .ok }
                doc.planExpanded = plan.branchIDs
                return .ok
            },
            Command(CommandDescriptor(id: "plan.collapseAll", title: L10n.tr("Zwiń wszystkie gałęzie"), category: .tools, submenu: L10n.tr("Plan"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zwija wszystkie gałęzie drzewa planu w aktywnym oknie planu; widoczny zostaje korzeń planu."),
                                      feature: "PD-OPT-001"),
                    validate: { treeDocument($0) != nil }) { ctx in
                guard let doc = treeDocument(ctx.workspace) else { return .ok }
                doc.planExpanded = []
                return .ok
            },
            Command(CommandDescriptor(id: "plan.export", title: L10n.tr("Zapisz plan jako…"), category: .tools, submenu: L10n.tr("Plan"),
                                      parameters: [CommandParameter("format", .string, L10n.tr("Format"), allowed: PlanFormat.allCases.map(\.rawValue))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje plan z okna planu jako tekst, HTML albo XML (DBMS_XPLAN)."), feature: "PD-OPT-003"),
                    validate: { $0.activeDocument?.plan != nil }) { ctx in
                guard let plan = ctx.workspace.activeDocument?.plan else { return .ok }
                let format = PlanFormat(rawValue: ctx.arguments.string("format") ?? "text") ?? .text
                let text = switch format { case .text: plan.text; case .html: plan.html; case .xml: plan.xml }
                let ext = switch format { case .text: "txt"; case .html: "html"; case .xml: "xml" }
                _ = await ctx.ui?.saveFile(suggestedName: "plan", fileExtension: ext, data: Data(text.utf8))
                return .ok
            },
        ]
    }
}
