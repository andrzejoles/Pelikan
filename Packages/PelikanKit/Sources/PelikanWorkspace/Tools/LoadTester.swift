import Foundation
import Observation
import PelikanDB
import PelikanSQL

/// Krok testu obciążenia: polecenie SQL albo blok PL/SQL; zmienne `:thread` i `:iteration` wiązane automatycznie.
public struct LoadStep: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var sql: String
    public init(name: String, sql: String) { self.name = name; self.sql = sql }
}

/// Definicja testu obciążenia (UG 24.17, PD-TOOL-019).
public struct LoadTest: Sendable, Codable, Hashable {
    public var steps: [LoadStep] = []
    public var threads = 4
    public var iterations = 10
    /// Wycofanie zmian po każdej iteracji (testy DML bez śladów).
    public var rollback = true
    public init() {}
}

/// Statystyka kroku.
public struct LoadStepStats: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var count = 0
    public var errors = 0
    public var totalMs = 0.0
    public var minMs = Double.infinity
    public var maxMs = 0.0
    public var lastError: String?
    public var averageMs: Double { count == 0 ? 0 : totalMs / Double(count) }
}

/// Wykonanie testu obciążenia: wątki = osobne sesje narzędzi, wyniki na żywo (liczba, średni/min/maks czas, błędy),
/// przepustowość w czasie (punkty co sekundę).
@MainActor
@Observable
public final class LoadTester {
    public let test: LoadTest
    public private(set) var stats: [LoadStepStats]
    public private(set) var running = false
    public private(set) var completedIterations = 0
    /// (sekunda od startu, liczba wykonań w tej sekundzie).
    public private(set) var throughput: [(Int, Int)] = []
    public private(set) var started: Date?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let workspace: Workspace
    @ObservationIgnored private let connectionID: UUID
    @ObservationIgnored private let runID = UUID().uuidString.prefix(8)

    public init(_ test: LoadTest, connectionID: UUID, in ws: Workspace) {
        self.test = test
        stats = test.steps.map { LoadStepStats(id: $0.id, name: $0.name) }
        self.connectionID = connectionID
        workspace = ws
    }

    nonisolated static func prepare(_ sql: String) -> (String, Bool, Bool) {
        var text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPLSQL = ScriptSplitter.split(text).first?.isPLSQL ?? false
        if text.hasSuffix("/") { text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        if !isPLSQL { while text.hasSuffix(";") { text.removeLast() } }
        let binds = Set(Lexer(text).tokenize().filter { $0.kind == .bindVariable }.map {
            (text as NSString).substring(with: NSRange(location: $0.start + 1, length: $0.length - 1)).lowercased()
        })
        return (text, binds.contains("thread"), binds.contains("iteration"))
    }

    public func start() {
        guard !running, !test.steps.isEmpty else { return }
        running = true
        started = Date()
        completedIterations = 0
        throughput = []
        let steps = test.steps.map { ($0.id, Self.prepare($0.sql)) }
        for t in 0..<max(1, test.threads) {
            let key = SessionKey(connectionID: connectionID, purpose: .tool("load-\(runID)-\(t)"))
            tasks.append(Task { [weak self] in
                guard let self else { return }
                do {
                    let s = try await self.workspace.sessions.session(key)
                    for i in 1...max(1, self.test.iterations) {
                        guard self.running, !Task.isCancelled else { break }
                        for (id, (sql, threadBind, iterBind)) in steps {
                            var binds: [BindVariable] = []
                            if threadBind { binds.append(BindVariable(name: "thread", type: .number, value: .text(String(t + 1)))) }
                            if iterBind { binds.append(BindVariable(name: "iteration", type: .number, value: .text(String(i)))) }
                            let clock = ContinuousClock()
                            let begin = clock.now
                            var failure: String?
                            do {
                                let r = try await s.execute(sql, binds: binds)
                                if let rs = r.resultSet {
                                    while try await s.fetch(rs.id, maxRows: 500).hasMore {}
                                }
                            } catch { failure = error.localizedDescription }
                            let d = clock.now - begin
                            self.record(id, ms: Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15, error: failure)
                        }
                        if self.test.rollback { try? await s.rollback() }
                        self.completedIterations += 1
                    }
                    try? await s.rollback()
                } catch {
                    if let first = steps.first { self.record(first.0, ms: 0, error: error.localizedDescription) }
                }
                await self.workspace.sessions.close(key)
                self.threadFinished()
            })
        }
    }

    private var finishedThreads = 0

    private func threadFinished() {
        finishedThreads += 1
        if finishedThreads >= max(1, test.threads) { running = false }
    }

    private func record(_ id: UUID, ms: Double, error: String?) {
        guard let i = stats.firstIndex(where: { $0.id == id }) else { return }
        stats[i].count += 1
        if let error { stats[i].errors += 1; stats[i].lastError = error } else {
            stats[i].totalMs += ms
            stats[i].minMs = min(stats[i].minMs, ms)
            stats[i].maxMs = max(stats[i].maxMs, ms)
        }
        let second = Int(Date().timeIntervalSince(started ?? Date()))
        if let last = throughput.last, last.0 == second { throughput[throughput.count - 1].1 += 1 } else { throughput.append((second, 1)) }
    }

    public func stop() {
        running = false
        for t in tasks { t.cancel() }
    }

    /// Czekanie na zakończenie (testy, tryb wsadowy).
    public func wait() async {
        for t in tasks { _ = await t.value }
    }

    /// Wyniki do Excela (CSV z separatorem średnika, jak eksport wyników).
    public func csv() -> String {
        var out = [L10n.tr("Krok;Wykonania;Błędy;Średnio ms;Min ms;Maks ms")]
        for s in stats {
            out.append([s.name, String(s.count), String(s.errors), String(format: "%.2f", s.averageMs),
                        s.minMs.isFinite ? String(format: "%.2f", s.minMs) : "", String(format: "%.2f", s.maxMs)].joined(separator: ";"))
        }
        return out.joined(separator: "\n") + "\n"
    }
}

/// Komendy monitora zdarzeń i testu obciążenia.
@MainActor
enum MonitorCommands {
    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "tools.eventMonitor", title: L10n.tr("Monitor zdarzeń…"), category: .tools,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Odbiera alerty DBMS_ALERT i wiadomości DBMS_PIPE w osobnej sesji."),
                                      feature: "PD-TOOL-014"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                ctx.ui?.showEventMonitor()
                return .ok
            },
            Command(CommandDescriptor(id: "tools.loadTester", title: L10n.tr("Test obciążenia…"), category: .tools,
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Wykonuje kroki SQL/PL/SQL w wielu sesjach równolegle; wyniki na żywo (czasy, błędy, przepustowość), zapis do Excela."),
                                      feature: "PD-TOOL-019"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                ctx.ui?.showLoadTester()
                return .ok
            },
        ]
    }
}
