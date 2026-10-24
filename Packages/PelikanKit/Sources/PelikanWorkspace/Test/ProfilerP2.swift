import Foundation
import PelikanDB

/// Przebieg profilera zapisany w bazie (PD-OPT-005): numer, data, komentarz, czas całkowity.
public struct ProfilerRun: Sendable, Hashable, Identifiable {
    public var run: Int
    public var date: String
    public var comment: String
    public var totalTime: Double
    public var id: Int { run }
}

/// Jednostka czasu w raportach profilera (Preferencje, PD-OPT-005).
public enum ProfilerTimeUnit: String, Sendable, Codable, CaseIterable {
    case seconds, milliseconds, microseconds

    public var symbol: String {
        switch self {
        case .seconds: "s"
        case .milliseconds: "ms"
        case .microseconds: "µs"
        }
    }

    /// Czas w nanosekundach w tej jednostce jako tekst.
    public func format(nanoseconds ns: Double) -> String {
        switch self {
        case .seconds: String(format: "%.6f", ns / 1e9)
        case .milliseconds: String(format: "%.3f", ns / 1e6)
        case .microseconds: String(format: "%.0f", ns / 1e3)
        }
    }
}

/// Węzeł drzewa wywołań profilera hierarchicznego (PD-OPT-006): funkcja z wywoływanymi (rodzic → dziecko).
public struct ProfilerTreeNode: Sendable, Hashable, Identifiable {
    public var id: String
    public var function: ProfilerFunction
    public var children: [ProfilerTreeNode]?
}

extension Profiler {
    /// Ostatnie przebiegi profilera danego rodzaju (najnowsze pierwsze).
    public static func runs(_ kind: ProfilerKind, session s: any DatabaseSession, limit: Int = 200) async throws -> [ProfilerRun] {
        let sql = kind == .lines
            ? "select runid, to_char(run_date, 'YYYY-MM-DD HH24:MI:SS'), run_comment, run_total_time from plsql_profiler_runs order by runid desc"
            : "select runid, to_char(run_timestamp, 'YYYY-MM-DD HH24:MI:SS'), run_comment, total_elapsed_time * 1000 from dbmshp_runs order by runid desc"
        guard await !needsTables(kind, session: s) else { return [] }
        let (_, rows) = try await s.queryAll(sql, limit: limit)
        return rows.map {
            ProfilerRun(run: Int($0[0].format(.default)) ?? 0, date: $0[1].displayText ?? "", comment: $0[2].displayText ?? "",
                        totalTime: Double($0[3].format(.default)) ?? 0)
        }
    }

    /// Raport zapisanego przebiegu.
    public static func report(_ kind: ProfilerKind, run: Int, session s: any DatabaseSession) async throws -> ProfilerReport {
        kind == .lines ? try await lineReport(run: run, session: s) : try await hierarchicalReport(run: run, session: s)
    }

    /// Linie z udziałem w czasie co najmniej `minShare` procent (0 — wszystkie).
    public nonisolated static func lines(_ r: ProfilerReport, minShare: Double) -> [ProfilerLine] {
        let total = max(r.lines.reduce(0) { $0 + $1.totalTime }, 1)
        return minShare <= 0 ? r.lines : r.lines.filter { $0.totalTime / total * 100 >= minShare }
    }

    /// Drzewo wywołań: korzenie to funkcje, których nikt nie wywołuje; cykle (rekurencja) przerywane, głębokość ograniczona.
    public nonisolated static func callTree(_ r: ProfilerReport, maxDepth: Int = 40) -> [ProfilerTreeNode] {
        let bySymbol = Dictionary(r.functions.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })
        let called = Set(r.functions.flatMap(\.children))
        func node(_ f: ProfilerFunction, path: [Int]) -> ProfilerTreeNode {
            let id = (path + [f.symbol]).map(String.init).joined(separator: "/")
            guard path.count < maxDepth else { return ProfilerTreeNode(id: id, function: f, children: nil) }
            let kids = f.children.filter { !path.contains($0) && $0 != f.symbol }.compactMap { bySymbol[$0] }
                .sorted { $0.subtreeTime > $1.subtreeTime }
                .map { node($0, path: path + [f.symbol]) }
            return ProfilerTreeNode(id: id, function: f, children: kids.isEmpty ? nil : kids)
        }
        var roots = r.functions.filter { !called.contains($0.symbol) }
        if roots.isEmpty, let top = r.functions.max(by: { $0.subtreeTime < $1.subtreeTime }) { roots = [top] }
        return roots.sorted { $0.subtreeTime > $1.subtreeTime }.map { node($0, path: []) }
    }
}

/// Komendy historii przebiegów profilera (PD-OPT-005).
enum ProfilerCommands {
    @MainActor
    static func testDocument(_ ws: Workspace) throws -> Document {
        guard let d = ws.activeDocument, d.kind == .test else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest oknem testu")) }
        return d
    }

    static let kindParam = CommandParameter("kind", .string, L10n.tr("lines albo hierarchical (domyślnie profiler okna)"))

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "test.profilerRuns", title: L10n.tr("Przebiegi profilera"), category: .debug,
                                      parameters: [kindParam], agent: .none, effect: .none,
                                      summary: L10n.tr("Lista zapisanych przebiegów profilera (numer, data, komentarz, czas)."), feature: "PD-OPT-005"),
                    validate: { $0.activeDocument?.kind == .test }) { ctx in
                let d = try testDocument(ctx.workspace)
                let kind = ctx.arguments.string("kind").flatMap(ProfilerKind.init(rawValue:)) ?? d.profiler ?? .lines
                let runs = try await Profiler.runs(kind, session: try await ctx.workspace.session(for: d))
                return CommandResult(message: runs.map { "\($0.run)  \($0.date)  \($0.comment)" }.joined(separator: "\n"),
                                     value: .array(runs.map { .object(["run": .int(Int64($0.run)), "date": .string($0.date), "comment": .string($0.comment)]) }))
            },
            Command(CommandDescriptor(id: "test.profilerOpenRun", title: L10n.tr("Otwórz przebieg profilera…"), category: .debug,
                                      parameters: [CommandParameter("run", .integer, required: true, L10n.tr("Numer przebiegu")), kindParam],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pokazuje raport zapisanego przebiegu profilera w karcie Profiler okna testu."), feature: "PD-OPT-005"),
                    validate: { $0.activeDocument?.kind == .test }) { ctx in
                let d = try testDocument(ctx.workspace)
                guard let run = ctx.arguments.int("run") else { throw CommandError.invalidArgument("run", L10n.tr("Podaj numer przebiegu")) }
                let kind = ctx.arguments.string("kind").flatMap(ProfilerKind.init(rawValue:)) ?? d.profiler ?? .lines
                d.profilerReport = try await Profiler.report(kind, run: Int(run), session: try await ctx.workspace.session(for: d))
                return .ok
            },
        ]
    }
}
