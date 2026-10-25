import Foundation
import Observation
import PelikanDB
import PelikanSQL

/// Harmonogram zadania lokalnego.
public enum LocalTaskSchedule: Sendable, Codable, Hashable {
    /// Co n minut.
    case interval(minutes: Int)
    /// Codziennie o godzinie.
    case daily(hour: Int, minute: Int)
    /// W dni tygodnia (1 = niedziela … 7 = sobota, jak `Calendar`) o godzinie.
    case weekly(weekdays: [Int], hour: Int, minute: Int)

    /// Następne uruchomienie po `date`.
    public func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .interval(let m):
            return date.addingTimeInterval(TimeInterval(max(1, m) * 60))
        case .daily(let h, let m):
            return calendar.nextDate(after: date, matching: DateComponents(hour: h, minute: m, second: 0), matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
        case .weekly(let days, let h, let m):
            let candidates = (days.isEmpty ? [2] : days).compactMap {
                calendar.nextDate(after: date, matching: DateComponents(hour: h, minute: m, second: 0, weekday: $0), matchingPolicy: .nextTime)
            }
            return candidates.min() ?? date.addingTimeInterval(7 * 86_400)
        }
    }

    public var displayText: String {
        switch self {
        case .interval(let m): L10n.tr("co \(m) min")
        case .daily(let h, let m): L10n.tr("codziennie o \(String(format: "%02d:%02d", h, m))")
        case .weekly(let d, let h, let m):
            L10n.tr("w dni \(d.map(String.init).joined(separator: ",")) o \(String(format: "%02d:%02d", h, m))")
        }
    }
}

/// Zadanie lokalne (DB-TASK-001): skrypt SQL, eksport wyniku zapytania do pliku albo zapisane przeniesienie danych.
/// Definicja zawiera tylko nazwę połączenia — hasło pochodzi z Pęku kluczy w chwili uruchomienia (nigdy z pliku).
public struct LocalTaskDefinition: Sendable, Codable, Hashable, Identifiable {
    public enum Action: Sendable, Codable, Hashable {
        /// Skrypt (plik albo tekst); `commit` — zatwierdzenie na końcu (inaczej wycofanie).
        case script(file: String?, text: String, commit: Bool)
        /// Eksport zapytania: katalog, wzorzec nazwy pliku (`{date}`, `{time}`), format.
        case export(query: String, directory: String, fileName: String, format: ExportFormat)
        /// Zapisana definicja przeniesienia danych (Transfers/nazwa.json).
        case transfer(name: String)
    }
    public var id = UUID()
    public var name: String
    public var connection: String
    public var action: Action
    public var schedule: LocalTaskSchedule
    public var enabled = true
    public init(name: String, connection: String, action: Action, schedule: LocalTaskSchedule) {
        self.name = name; self.connection = connection; self.action = action; self.schedule = schedule
    }
}

/// Stan uruchomień (osobny plik, żeby definicje zmieniały się tylko przez użytkownika).
public struct LocalTaskRunState: Sendable, Codable, Hashable {
    public var lastRun: Date?
    public var lastStatus: String?
    public var lastLog: String?
    public var nextRun: Date?
}

/// Magazyn definicji i stanu zadań lokalnych (`Tasks/tasks.json`, `Tasks/state.json`, `Tasks/logs/`).
public struct LocalTaskStore: Sendable {
    public let directory: URL?
    public init(directory: URL?) { self.directory = directory }

    var tasksURL: URL? { directory?.appendingPathComponent("tasks.json") }
    var stateURL: URL? { directory?.appendingPathComponent("state.json") }
    public var logsDirectory: URL? { directory?.appendingPathComponent("logs", isDirectory: true) }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func load() -> [LocalTaskDefinition] {
        guard let u = tasksURL, let d = try? Data(contentsOf: u) else { return [] }
        return (try? Self.decoder.decode([LocalTaskDefinition].self, from: d)) ?? []
    }

    public func save(_ tasks: [LocalTaskDefinition]) throws {
        guard let u = tasksURL else { return }
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(tasks).write(to: u, options: .atomic)
    }

    public func loadState() -> [UUID: LocalTaskRunState] {
        guard let u = stateURL, let d = try? Data(contentsOf: u) else { return [:] }
        return (try? Self.decoder.decode([UUID: LocalTaskRunState].self, from: d)) ?? [:]
    }

    public func saveState(_ s: [UUID: LocalTaskRunState]) throws {
        guard let u = stateURL else { return }
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(s).write(to: u, options: .atomic)
    }
}

/// Wykonanie zadania lokalnego (bez interfejsu) — wynik to tekst dziennika.
public enum LocalTaskRunner {
    /// Nazwa pliku z wzorca: `{date}` → RRRR-MM-DD, `{time}` → GGMMSS.
    public static func fileName(_ pattern: String, at date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let d = f.string(from: date)
        f.dateFormat = "HHmmss"
        return pattern.replacingOccurrences(of: "{date}", with: d).replacingOccurrences(of: "{time}", with: f.string(from: date))
    }

    /// Skrypt: polecenia SQL i bloki PL/SQL po kolei (polecenia SQL*Plus pomijane z adnotacją), DBMS_OUTPUT do dziennika.
    public static func runScript(_ text: String, commit: Bool, in s: any DatabaseSession) async throws -> [String] {
        var log: [String] = []
        try? await SessionUtilities.enableOutput(s, bufferSize: 1_000_000)
        do {
            for st in ScriptSplitter.split(text, mode: .commandWindow) {
                try Task.checkCancellation()
                if let cmd = st.sqlplusCommand {
                    log.append(L10n.tr("Pominięto polecenie SQL*Plus: \(cmd)"))
                    continue
                }
                var sql = st.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if sql.hasSuffix("/") { sql = String(sql.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
                if !st.isPLSQL { while sql.hasSuffix(";") { sql.removeLast() } }
                guard !sql.isEmpty else { continue }
                let r = try await s.execute(sql, binds: [], options: ExecuteOptions())
                let first = sql.components(separatedBy: "\n").first ?? ""
                log.append(r.kind == .dml ? "\(first) — " + L10n.tr("wierszy: \(r.rowsAffected)") : first)
                if let rs = r.resultSet { await s.closeResultSet(rs.id) }
                log += (try? await SessionUtilities.readOutput(s)) ?? []
            }
        } catch {
            try? await s.rollback()
            log.append(L10n.tr("Błąd: \(error.localizedDescription) — wycofano"))
            throw LocalTaskError(log: log, message: error.localizedDescription)
        }
        if commit { try await s.commit(); log.append(L10n.tr("Zatwierdzono.")) } else { try await s.rollback(); log.append(L10n.tr("Wycofano (zadanie bez zatwierdzania).")) }
        return log
    }

    /// Eksport wyniku zapytania do pliku w katalogu; zwraca ścieżkę pliku.
    public static func runExport(query: String, directory: URL, fileName pattern: String, format: ExportFormat, in s: any DatabaseSession,
                                 at date: Date = Date()) async throws -> URL {
        var sql = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while sql.hasSuffix(";") { sql.removeLast() }
        let (cols, rows) = try await s.queryAll(sql, limit: 5_000_000)
        let data = ExportData(title: pattern, columns: cols, rows: rows, sql: sql)
        var name = fileName(pattern, at: date)
        let ext = format == .expressionList ? "txt" : format.rawValue
        if (name as NSString).pathExtension.isEmpty { name += "." + ext }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let bytes = format == .xlsx ? ResultExporter.xlsx([data]) : Data(ResultExporter.text(format, data).utf8)
        try bytes.write(to: url, options: .atomic)
        return url
    }
}

public struct LocalTaskError: Error, LocalizedError {
    public var log: [String]
    public var message: String
    public var errorDescription: String? { message }
}

/// Planista zadań lokalnych: co 30 s sprawdza zadania do uruchomienia i wykonuje je jako zadania w tle (`ws.tasks`)
/// w sesjach narzędzi połączeń wskazanych nazwą. Działa tylko, gdy aplikacja jest uruchomiona.
@MainActor
@Observable
public final class LocalTaskScheduler {
    public let store: LocalTaskStore
    public private(set) var definitions: [LocalTaskDefinition]
    public private(set) var state: [UUID: LocalTaskRunState]
    @ObservationIgnored weak var workspace: Workspace?
    @ObservationIgnored var timer: Task<Void, Never>?
    @ObservationIgnored var running: Set<UUID> = []

    public init(directory: URL?) {
        store = LocalTaskStore(directory: directory)
        definitions = store.load()
        state = store.loadState()
    }

    public var isStarted: Bool { timer != nil }

    public func start(_ ws: Workspace, interval: Duration = .seconds(30)) {
        workspace = ws
        guard timer == nil else { return }
        let now = Date()
        for d in definitions where state[d.id]?.nextRun == nil { state[d.id, default: LocalTaskRunState()].nextRun = d.schedule.next(after: now) }
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.tick()
            }
        }
    }

    public func stop() { timer?.cancel(); timer = nil }

    public func upsert(_ d: LocalTaskDefinition) throws {
        if let i = definitions.firstIndex(where: { $0.id == d.id }) { definitions[i] = d } else { definitions.append(d) }
        state[d.id, default: LocalTaskRunState()].nextRun = d.schedule.next(after: Date())
        try store.save(definitions)
        try store.saveState(state)
    }

    public func remove(_ id: UUID) throws {
        definitions.removeAll { $0.id == id }
        state[id] = nil
        try store.save(definitions)
        try store.saveState(state)
    }

    /// Zadania, których termin minął (włączone i nieuruchomione).
    public func due(at now: Date = Date()) -> [LocalTaskDefinition] {
        definitions.filter { d in d.enabled && !running.contains(d.id) && (state[d.id]?.nextRun.map { $0 <= now } ?? false) }
    }

    func tick(now: Date = Date()) {
        for d in due(at: now) { run(d) }
    }

    /// Uruchomienie (planowe albo ręczne „Uruchom teraz”); zwraca zadanie w tle.
    @discardableResult
    public func run(_ d: LocalTaskDefinition) -> WorkspaceTask? {
        guard let ws = workspace, !running.contains(d.id) else { return nil }
        running.insert(d.id)
        let started = Date()
        state[d.id, default: LocalTaskRunState()].nextRun = d.schedule.next(after: started)
        return ws.tasks.run(L10n.tr("Zadanie lokalne: \(d.name)"), kind: "local-task") { [weak self] task in
            var log: [String] = [L10n.tr("Start: \(ISO8601DateFormatter().string(from: started))")]
            var status = "OK"
            do {
                log += try await Self.execute(d, in: ws, task: task)
            } catch let e as LocalTaskError {
                log += e.log
                status = e.message
            } catch {
                log.append(error.localizedDescription)
                status = error.localizedDescription
            }
            self?.finish(d, started: started, status: status, log: log)
            if status != "OK" { throw LocalTaskError(log: log, message: status) }
        }
    }

    func finish(_ d: LocalTaskDefinition, started: Date, status: String, log: [String]) {
        running.remove(d.id)
        var s = state[d.id] ?? LocalTaskRunState()
        s.lastRun = started
        s.lastStatus = status
        if let dir = store.logsDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(ImportProfileStore.safe(d.name) + "-" + LocalTaskRunner.fileName("{date}-{time}", at: started) + ".log")
            try? (log.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            s.lastLog = url.lastPathComponent
        }
        state[d.id] = s
        try? store.saveState(state)
    }

    /// Połączenie zadania: po nazwie; pusta nazwa to „(główne)” z edytora zadań — połączenie główne, nie połączenie
    /// okna aktywnego w chwili uruchomienia (zadanie cykliczne nie może trafiać na przypadkową bazę).
    static func connection(_ d: LocalTaskDefinition, in ws: Workspace) throws -> UUID {
        let name = d.connection.trimmingCharacters(in: .whitespaces)
        guard let id = name.isEmpty ? ws.sessions.mainConnectionID : ws.connectionID(named: name) else {
            throw CommandError.notAvailable(name.isEmpty ? L10n.tr("Brak połączenia głównego dla zadania") : L10n.tr("Nieznane połączenie „\(d.connection)”"))
        }
        return id
    }

    static func execute(_ d: LocalTaskDefinition, in ws: Workspace, task: WorkspaceTask) async throws -> [String] {
        switch d.action {
        case .transfer(let name):
            let job = try DataTransferStore.load(name, in: ws.dataDirectory)
            let r = try await ws.runDataTransfer(job) { n in task.message = L10n.tr("Wierszy: \(n)") }
            return [L10n.tr("Przeniesiono wierszy: \(r.inserted), błędy: \(r.errors.count)")] + r.errors.prefix(50)
        case .script(let file, let text, let commit):
            let conn = try connection(d, in: ws)
            let script = try file.map { try String(contentsOf: URL(fileURLWithPath: $0), encoding: .utf8) } ?? text
            // Strażnik zawsze: bez COMMIT DDL i tak zatwierdza się sam (połączenie tylko do odczytu, produkcja).
            try await ws.guardModification(ScriptSplitter.split(script).map(\.text), connectionID: conn)
            let s = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("task-\(d.id.uuidString.prefix(8))")))
            return try await LocalTaskRunner.runScript(script, commit: commit, in: s)
        case .export(let query, let directory, let fileName, let format):
            let conn = try connection(d, in: ws)
            let s = try await ws.sessions.session(SessionKey(connectionID: conn, purpose: .tool("task-\(d.id.uuidString.prefix(8))")))
            let url = try await LocalTaskRunner.runExport(query: query, directory: URL(fileURLWithPath: (directory as NSString).expandingTildeInPath),
                                                          fileName: fileName, format: format, in: s)
            return [L10n.tr("Zapisano \(url.lastPathComponent)")]
        }
    }
}
