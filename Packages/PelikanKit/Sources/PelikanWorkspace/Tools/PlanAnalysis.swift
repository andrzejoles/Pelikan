import Foundation
import PelikanDB
import PelikanSQL

// MARK: Diagram planu i flame graph (SD-PLAN-001)

/// Węzeł diagramu planu: kolumna = głębokość, wiersz = kolejność w drzewie (pre-order), linia planu.
public struct PlanDiagramNode: Sendable, Hashable, Identifiable {
    public var id: Int
    public var column: Int
    public var row: Int
    public var line: PlanLine
    public var parentID: Int?
}

/// Pasek flame graph: poziom, początek i szerokość w zakresie 0…1 (proporcjonalnie do kosztu względem rodzica).
public struct FlameBar: Sendable, Hashable, Identifiable {
    public var id: Int
    public var depth: Int
    public var start: Double
    public var width: Double
    public var title: String
    public var cost: Int64?
}

public enum PlanGraph {
    /// Układ drzewa: każdy węzeł w osobnym wierszu (pre-order), kolumna = głębokość — strzałki od dzieci do rodzica.
    public static func layout(_ roots: [PlanLine]) -> [PlanDiagramNode] {
        var out: [PlanDiagramNode] = []
        func visit(_ l: PlanLine, _ depth: Int, _ parent: Int?) {
            out.append(PlanDiagramNode(id: l.id, column: depth, row: out.count, line: l, parentID: parent))
            for c in l.children ?? [] { visit(c, depth + 1, l.id) }
        }
        for r in roots { visit(r, 0, nil) }
        return out
    }

    /// Flame graph kosztu: korzeń zajmuje całą szerokość, dzieci dzielą szerokość rodzica proporcjonalnie do własnego
    /// kosztu (koszt w Oracle obejmuje dzieci); bez kosztów — równo. Suma dzieci większa niż rodzic jest skalowana.
    public static func flame(_ roots: [PlanLine]) -> [FlameBar] {
        var out: [FlameBar] = []
        func visit(_ l: PlanLine, _ depth: Int, _ start: Double, _ width: Double) {
            out.append(FlameBar(id: l.id, depth: depth, start: start, width: width, title: l.object.isEmpty ? l.title : "\(l.title) \(l.object)", cost: l.cost))
            let kids = l.children ?? []
            guard !kids.isEmpty else { return }
            let costs = kids.map { Double(max(0, $0.cost ?? 0)) }
            let sum = costs.reduce(0, +)
            let parent = Double(max(0, l.cost ?? 0))
            // Udział dzieci w szerokości rodzica: ich koszt / koszt rodzica (najwyżej 1); bez kosztów — całość, po równo.
            let share = sum > 0 && parent > 0 ? min(1, sum / parent) : 1
            var x = start
            for (k, c) in zip(kids, costs) {
                let w = sum > 0 ? width * share * (c / sum) : width / Double(kids.count)
                visit(k, depth + 1, x, w)
                x += w
            }
        }
        for (i, r) in roots.enumerated() { visit(r, 0, Double(i) / Double(roots.count), 1 / Double(roots.count)) }
        return out
    }
}

// MARK: Autotrace (SD-PLAN-002)

/// Linia planu rzeczywistego z V$SQL_PLAN_STATISTICS_ALL (ostatnie wykonanie).
public struct ActualPlanLine: Sendable, Hashable, Identifiable {
    public var id: Int
    public var parentID: Int?
    public var depth: Int
    public var operation: String
    public var options: String
    public var object: String
    public var cost: Int64?
    public var estimatedRows: Int64?
    public var actualRows: Int64?
    public var starts: Int64?
    /// Czas ostatniego wykonania w milisekundach.
    public var elapsedMs: Double?
    public var buffers: Int64?
    public var diskReads: Int64?
    public var title: String { options.isEmpty ? operation : "\(operation) \(options)" }

    /// Rozbieżność szacunku: A-Rows / (E-Rows × Starts) poza zakresem 0,1…10 (wskazówka do statystyk).
    public var misestimated: Bool {
        guard let a = actualRows, let e = estimatedRows, e > 0 else { return false }
        let expected = Double(e) * Double(max(1, starts ?? 1))
        let ratio = Double(a) / expected
        return ratio > 10 || (a > 0 && ratio < 0.1)
    }
}

public struct AutotraceResult: Sendable {
    public var sqlID: String
    public var childNumber: Int
    public var rowsFetched: Int
    public var elapsedSeconds: Double
    public var lines: [ActualPlanLine]
    /// Statystyki sesji zmienione w trakcie wykonania (różnica po − przed), najważniejsze pierwsze.
    public var statistics: [SessionStatistic]
    /// DBMS_XPLAN.DISPLAY_CURSOR(…, 'ALLSTATS LAST').
    public var planText: String
}

public enum Autotrace {
    /// Statystyki pokazywane jako pierwsze (jak w SQL*Plus AUTOTRACE STATISTICS).
    static let keyStatistics = ["recursive calls", "db block gets", "consistent gets", "physical reads", "redo size",
                                "bytes sent via SQL*Net to client", "bytes received via SQL*Net from client",
                                "SQL*Net roundtrips to/from client", "sorts (memory)", "sorts (disk)", "rows processed"]

    /// Wskazówka `GATHER_PLAN_STATISTICS` i znacznik do odnalezienia kursora w V$SQL po pierwszym SELECT/DML.
    nonisolated static func instrument(_ sql: String, tag: String) -> String {
        let ns = sql as NSString
        var depth = 0
        for tok in Lexer(sql).tokenize() where !tok.isTrivia {
            if tok.kind == .leftParen { depth += 1 } else if tok.kind == .rightParen { depth -= 1 }
            let w = ns.substring(with: NSRange(location: tok.start, length: tok.length)).uppercased()
            if depth == 0, ["SELECT", "UPDATE", "DELETE", "INSERT", "MERGE"].contains(w) {
                return ns.replacingCharacters(in: NSRange(location: tok.end, length: 0), with: " /*+ GATHER_PLAN_STATISTICS */ /* \(tag) */")
            }
        }
        return sql
    }

    /// Różnica statystyk: tylko zmienione, najpierw kluczowe, potem malejąco.
    nonisolated static func delta(before: [String: Double], after: [String: Double]) -> [SessionStatistic] {
        let changed = after.compactMap { k, v -> SessionStatistic? in
            let d = v - (before[k] ?? 0)
            return d != 0 ? SessionStatistic(name: k, value: d) : nil
        }
        let key = changed.filter { keyStatistics.contains($0.name) }.sorted { keyStatistics.firstIndex(of: $0.name)! < keyStatistics.firstIndex(of: $1.name)! }
        let rest = changed.filter { !keyStatistics.contains($0.name) }.sorted { $0.value > $1.value }
        return key + rest
    }

    /// Wykonuje polecenie z pomiarem planu rzeczywistego (zapytanie — wszystkie wiersze do `maxRows`; DML — wycofywane).
    public static func run(_ sql: String, in s: any DatabaseSession, maxRows: Int = 100_000) async throws -> AutotraceResult {
        let parts = ScriptSplitter.split(sql)
        guard parts.count == 1, let only = parts.first, [.query, .dml].contains(only.category) else {
            throw CommandError.invalidArgument("sql", L10n.tr("Autotrace dla jednego zapytania albo polecenia DML"))
        }
        var text = only.text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast() }
        let tag = "PLK-AT-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        let instrumented = instrument(text, tag: tag)
        let before = await Profiler.statistics(s) ?? [:]
        let started = Date()
        var rows = 0
        do {
            let r = try await s.execute(instrumented)
            if let rs = r.resultSet {
                while rows < maxRows {
                    let b = try await s.fetch(rs.id, maxRows: 1000)
                    rows += b.rows.count
                    if !b.hasMore { break }
                }
                await s.closeResultSet(rs.id)
            } else {
                rows = Int(r.rowsAffected)
            }
        } catch {
            try? await s.rollback()
            throw error
        }
        let elapsed = Date().timeIntervalSince(started)
        if only.category == .dml { try? await s.rollback() }
        let after = await Profiler.statistics(s) ?? [:]
        let (_, cur) = try await s.queryAll("""
            select sql_id, child_number from v$sql
             where sql_text like '%' || :t || '%' and sql_text not like '%v$sql%' order by last_active_time desc
            """, binds: [BindVariable(name: "t", value: .text(tag))], limit: 1)
        guard let c = cur.first, let sqlID = c[0].displayText else {
            throw CommandError.notAvailable(L10n.tr("Nie znaleziono kursora w V$SQL (brak uprawnień albo kursor wyparty)"))
        }
        let child = Int(c[1].displayText ?? "0") ?? 0
        let b = [BindVariable(name: "id", value: .text(sqlID)), BindVariable(name: "c", type: .number, value: .text(String(child)))]
        let (_, plan) = try await s.queryAll("""
            select id, parent_id, depth, operation, nvl(options, ' '), nvl(object_owner || nvl2(object_owner, '.', '') || object_name, ' '),
                   cost, cardinality, last_output_rows, last_starts, last_elapsed_time, nvl(last_cr_buffer_gets, 0) + nvl(last_cu_buffer_gets, 0), last_disk_reads
              from v$sql_plan_statistics_all where sql_id = :id and child_number = :c order by id
            """, binds: b, limit: 10_000)
        func int(_ v: OracleValue) -> Int64? { v.displayText.flatMap { Int64($0) } }
        func str(_ v: OracleValue) -> String { (v.displayText ?? "").trimmingCharacters(in: .whitespaces) }
        let lines = plan.map { r in
            ActualPlanLine(id: Int(int(r[0]) ?? 0), parentID: int(r[1]).map { Int($0) }, depth: Int(int(r[2]) ?? 0), operation: str(r[3]), options: str(r[4]),
                           object: str(r[5]), cost: int(r[6]), estimatedRows: int(r[7]), actualRows: int(r[8]), starts: int(r[9]),
                           elapsedMs: int(r[10]).map { Double($0) / 1000 }, buffers: int(r[11]), diskReads: int(r[12]))
        }
        let (_, xp) = try await s.queryAll("select plan_table_output from table(dbms_xplan.display_cursor(:id, :c, 'ALLSTATS LAST'))", binds: b, limit: 5000)
        return AutotraceResult(sqlID: sqlID, childNumber: child, rowsFetched: rows, elapsedSeconds: elapsed, lines: lines,
                               statistics: delta(before: before, after: after), planText: xp.map { $0.first?.displayText ?? "" }.joined(separator: "\n"))
    }
}

// MARK: Porównanie planów (SD-PLAN-003)

/// Wiersz porównania dwóch planów (dopasowanie operacji w kolejności drzewa).
public struct PlanComparisonRow: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Hashable { case same, changed, onlyLeft, onlyRight }
    public var id: Int
    public var left: PlanLine?
    public var right: PlanLine?
    public var status: Status
    /// Opis różnic (koszt, kardynalność, kolejność wykonania, predykaty).
    public var differences: [String]
}

public struct PlanComparison: Sendable {
    public var rows: [PlanComparisonRow]
    public var leftCost: Int64?
    public var rightCost: Int64?
    public var identicalShape: Bool { rows.allSatisfy { $0.status == .same || $0.status == .changed } }
}

public enum PlanCompare {
    /// Sygnatura operacji do dopasowania: głębokość, operacja, opcje, obiekt.
    nonisolated static func signature(_ l: PlanLine) -> String { "\(l.depth)|\(l.operation)|\(l.options)|\(l.object)" }

    /// Dopasowanie linii (najdłuższy wspólny podciąg sygnatur w kolejności id), różnice kosztu, kardynalności,
    /// kolejności wykonania i predykatów dla dopasowanych.
    public static func compare(_ left: [PlanLine], _ right: [PlanLine]) -> PlanComparison {
        let a = left.sorted { $0.id < $1.id }, b = right.sorted { $0.id < $1.id }
        let sa = a.map(signature), sb = b.map(signature)
        var lcs = Array(repeating: Array(repeating: 0, count: sb.count + 1), count: sa.count + 1)
        for i in stride(from: sa.count - 1, through: 0, by: -1) {
            for j in stride(from: sb.count - 1, through: 0, by: -1) {
                lcs[i][j] = sa[i] == sb[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var rows: [PlanComparisonRow] = []
        var i = 0, j = 0
        func add(_ l: PlanLine?, _ r: PlanLine?) {
            var diffs: [String] = []
            let status: PlanComparisonRow.Status
            if let l, let r {
                if l.cost != r.cost { diffs.append(L10n.tr("koszt \(l.cost.map(String.init) ?? "—") → \(r.cost.map(String.init) ?? "—")")) }
                if l.cardinality != r.cardinality { diffs.append(L10n.tr("wiersze \(l.cardinality.map(String.init) ?? "—") → \(r.cardinality.map(String.init) ?? "—")")) }
                if l.executionOrder != r.executionOrder { diffs.append(L10n.tr("kolejność \(l.executionOrder) → \(r.executionOrder)")) }
                if l.accessPredicates != r.accessPredicates || l.filterPredicates != r.filterPredicates { diffs.append(L10n.tr("predykaty")) }
                status = diffs.isEmpty ? .same : .changed
            } else {
                status = l != nil ? .onlyLeft : .onlyRight
            }
            rows.append(PlanComparisonRow(id: rows.count, left: l, right: r, status: status, differences: diffs))
        }
        while i < sa.count || j < sb.count {
            if i < sa.count, j < sb.count, sa[i] == sb[j] { add(a[i], b[j]); i += 1; j += 1 }
            else if j < sb.count, i == sa.count || lcs[i][j + 1] >= lcs[i + 1][j] { add(nil, b[j]); j += 1 }
            else { add(a[i], nil); i += 1 }
        }
        return PlanComparison(rows: rows, leftCost: a.first { $0.parentID == nil }?.cost, rightCost: b.first { $0.parentID == nil }?.cost)
    }
}
