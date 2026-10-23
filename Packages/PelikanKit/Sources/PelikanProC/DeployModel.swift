import Foundation
import Observation
import PelikanWorkspace

/// Krok pipeline'u w konsoli (sekcja ze statusem i czasem).
public struct DeployStep: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Codable, Hashable { case running, ok, failed, stopped }
    public var name: String
    public var status: Status
    public var started: Date
    public var finished: Date?
    public var code: Int32?
    public var id: String { name }

    public var title: String { DeployStep.title(of: name) }
    public var duration: TimeInterval? { finished.map { $0.timeIntervalSince(started) } }

    public static func title(of name: String) -> String {
        switch name {
        case "lock": L10n.tr("Blokada")
        case "check": L10n.tr("Kontrola working copy")
        case "pull": L10n.tr("Pobranie zmian (git pull --ff-only)")
        case "backup": L10n.tr("Backup binarek")
        case "build": L10n.tr("Build")
        case "install": L10n.tr("Instalacja do bin")
        case "history": L10n.tr("Historia")
        case "rollback": L10n.tr("Wycofanie binarki")
        default: name
        }
    }
}

/// Linia konsoli: wyjście, błąd (stderr), nagłówek kroku albo komunikat Pelikana.
public struct DeployConsoleLine: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, Hashable { case output, error, step, info }
    public var id: Int
    public var kind: Kind
    public var text: String
    /// Krok, do którego należy linia (filtr i sekcje).
    public var step: String?
}

/// Wynik wdrożenia albo wycofania.
public enum DeployOutcome: String, Sendable, Codable, Hashable {
    case success, failed, stopped, locked, staleLock, dirty, wrongBranch, noFastForward, buildFailed, cancelled

    public var title: String {
        switch self {
        case .success: L10n.tr("Zakończone powodzeniem")
        case .failed: L10n.tr("Błąd")
        case .stopped: L10n.tr("Zatrzymane")
        case .locked: L10n.tr("Cel zablokowany przez inne wdrożenie")
        case .staleLock: L10n.tr("Przeterminowana blokada (proces już nie działa)")
        case .dirty: L10n.tr("Zmiany w working copy na serwerze — wdrożenie przerwane przed pull")
        case .wrongBranch: L10n.tr("Working copy na innej gałęzi")
        case .noFastForward: L10n.tr("Brak fast-forward — pull przerwany")
        case .buildFailed: L10n.tr("Build nie powiódł się — bin bez zmian")
        case .cancelled: L10n.tr("Anulowane")
        }
    }

    /// Wynik z kodu wyjścia skryptu (`DeployScripts.Exit`).
    public static func from(exitCode: Int32) -> DeployOutcome {
        switch exitCode {
        case 0: .success
        case DeployScripts.Exit.locked: .locked
        case DeployScripts.Exit.staleLock: .staleLock
        case DeployScripts.Exit.dirty: .dirty
        case DeployScripts.Exit.wrongBranch: .wrongBranch
        case DeployScripts.Exit.noFastForward: .noFastForward
        case DeployScripts.Exit.buildFailed: .buildFailed
        case 129...255: .stopped
        default: .failed
        }
    }
}

/// Stan wdrożenia odczytany ze strumienia skryptu: linie, kroki (`@@STEP`/`@@END`), commity, blokada, zmiany
/// w working copy, kopie, zainstalowane binarki, komunikaty kompilatora. Czysta logika — testowana bez serwera.
public struct DeployProgress: Sendable {
    public private(set) var lines: [DeployConsoleLine] = []
    public private(set) var steps: [DeployStep] = []
    public private(set) var headBefore: String?
    public private(set) var headAfter: String?
    public private(set) var lockInfo: [String] = []
    public private(set) var dirtyFiles: [String] = []
    public private(set) var backups: [String] = []
    public private(set) var installed: [String] = []
    public private(set) var missing: [String] = []
    public private(set) var serverBranch: String?
    public private(set) var finishedMarker = false
    public private(set) var exitCode: Int32?

    var pendingOut = ""
    var pendingErr = ""
    var inLockInfo = false
    var inDirty = false
    var current: String?
    let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    /// Komunikaty kompilatora (parser wieloliniowy — Pro*C i `-qsrcmsg`) i linia konsoli każdego z nich.
    public private(set) var messages: [BuildMessage] = []
    public private(set) var messageLines: [Int: BuildMessage] = [:]
    public var errorCount: Int { messages.filter(\.isError).count }
    public var outcome: DeployOutcome? { exitCode.map(DeployOutcome.from(exitCode:)) }

    /// Tekst logu (do zapisu i historii).
    public var logText: String {
        lines.map { l in
            switch l.kind {
            case .step: "== \(l.text)"
            case .error: "! " + l.text
            case .info: "# " + l.text
            case .output: l.text
            }
        }.joined(separator: "\n")
    }

    public mutating func info(_ text: String) { append(.info, text) }

    /// Porcja wyjścia (tekst już zdekodowany); linie przetwarzane po znaku nowej linii.
    public mutating func feed(_ text: String, error: Bool = false) {
        var buffer = (error ? pendingErr : pendingOut) + text
        while let nl = buffer.firstIndex(of: "\n") {
            var line = String(buffer[..<nl])
            if line.hasSuffix("\r") { line.removeLast() }
            buffer = String(buffer[buffer.index(after: nl)...])
            process(line, error: error)
        }
        if error { pendingErr = buffer } else { pendingOut = buffer }
    }

    /// Koniec procesu: reszta bez nowej linii, kod wyjścia, krok w toku zamknięty jako błąd/zatrzymany.
    public mutating func finish(exitCode code: Int32, stopped: Bool = false) {
        if !pendingOut.isEmpty { process(pendingOut, error: false); pendingOut = "" }
        if !pendingErr.isEmpty { process(pendingErr, error: true); pendingErr = "" }
        exitCode = stopped ? 143 : code
        analyzeMessages()
        if let i = steps.lastIndex(where: { $0.status == .running }) {
            steps[i].status = stopped ? .stopped : (code == 0 ? .ok : .failed)
            steps[i].finished = now()
        }
    }

    mutating func append(_ kind: DeployConsoleLine.Kind, _ text: String) {
        lines.append(DeployConsoleLine(id: lines.count, kind: kind, text: text, step: current))
    }

    /// Rozpoznanie komunikatów w wyjściu (po zakończeniu kroku i procesu): `outputLine` parsera → id linii konsoli.
    public mutating func analyzeMessages() {
        let output = lines.filter { $0.kind == .output || $0.kind == .error }
        let parsed = BuildMessageParser.parse(output.map(\.text).joined(separator: "\n"))
        messages = []
        messageLines = [:]
        for var m in parsed where m.outputLine >= 1 && m.outputLine <= output.count {
            let id = output[m.outputLine - 1].id
            m.outputLine = id
            messages.append(m)
            messageLines[id] = m
        }
    }

    mutating func process(_ line: String, error: Bool) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("@@") {
            if handleMarker(t) { return }
        }
        if inLockInfo { lockInfo.append(t) }
        if inDirty, !t.isEmpty { dirtyFiles.append(line) }
        append(error ? .error : .output, line)
    }

    /// Znacznik skryptu; true — linia nie trafia do konsoli jako zwykłe wyjście.
    mutating func handleMarker(_ t: String) -> Bool {
        let parts = t.split(separator: " ", maxSplits: 2).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "@@STEP":
            current = arg
            steps.append(DeployStep(name: arg, status: .running, started: now()))
            append(.step, DeployStep.title(of: arg))
        case "@@END":
            let code = parts.count > 2 ? Int32(parts[2]) ?? -1 : -1
            if let i = steps.lastIndex(where: { $0.name == arg }) {
                steps[i].status = code == 0 ? .ok : .failed
                steps[i].finished = now()
                steps[i].code = code
            }
            if arg == "build" { analyzeMessages() }
        case "@@HEAD_BEFORE": headBefore = arg
        case "@@HEAD_AFTER": headAfter = arg
        case "@@LOCKINFO": inLockInfo = true
        case "@@LOCKINFO_END": inLockInfo = false
        case "@@DIRTY_BEGIN": inDirty = true
        case "@@DIRTY_END": inDirty = false
        case "@@BACKUP":
            backups.append(arg)
            append(.info, L10n.tr("Kopia: \(arg)"))
        case "@@NOBINARY": append(.info, L10n.tr("Brak binarki \(arg) w bin — bez kopii"))
        case "@@INSTALLED":
            installed.append(arg)
            append(.info, L10n.tr("Zainstalowano: \(arg)"))
        case "@@MISSING":
            missing.append(arg)
            append(.error, L10n.tr("Build nie utworzył binarki \(arg)"))
        case "@@BRANCH":
            serverBranch = arg.replacingOccurrences(of: "refs/heads/", with: "")
            append(.error, L10n.tr("Working copy na gałęzi „\(serverBranch ?? "")”"))
        case "@@NO_FF": append(.error, L10n.tr("Brak fast-forward: historia na serwerze rozeszła się z remote — Pelikan nie robi merge"))
        case "@@DONE": finishedMarker = true
        default: return false
        }
        return true
    }
}

/// Wpis historii wdrożeń (lokalnie w katalogu danych; pełny log w osobnym pliku).
public struct DeployRecord: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, Hashable { case deploy, rollback }
    public var id: String
    public var kind: Kind
    public var targetID: UUID
    public var targetName: String
    public var environment: SSHTargetEnvironment
    public var owner: String
    public var started: Date
    public var finished: Date?
    public var headBefore: String?
    public var headAfter: String?
    public var binaries: [String]
    public var outcome: DeployOutcome?
    public var exitCode: Int32?
    public var failedStep: String?
    public var detail: String?

    public init(id: String, kind: Kind, target: PelikanSSHTarget, owner: String, started: Date = Date()) {
        self.id = id; self.kind = kind; targetID = target.id; targetName = target.name; environment = target.environment
        self.owner = owner; self.started = started; binaries = target.effectiveBinaries
    }
}

/// Wpis historii z serwera (`czas|id|właściciel|rodzaj|przed|po|krok|kod`).
public struct ServerHistoryEntry: Sendable, Hashable, Identifiable {
    public var timestamp: String
    public var id: String
    public var owner: String
    public var kind: String
    public var headBefore: String
    public var headAfter: String
    public var step: String
    public var code: Int32
    public var succeeded: Bool { step == "done" && code == 0 }

    public static func parse(_ text: String) -> [ServerHistoryEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { l in
            let p = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard p.count == 8, let code = Int32(p[7]) else { return nil }
            return ServerHistoryEntry(timestamp: p[0], id: p[1], owner: p[2], kind: p[3], headBefore: p[4], headAfter: p[5], step: p[6], code: code)
        }.reversed()
    }
}

/// Historia wdrożeń w katalogu danych: `proc-deploys/history.json` i logi `<id>.log`.
@MainActor
@Observable
public final class DeployHistoryStore {
    public private(set) var records: [DeployRecord] = []
    @ObservationIgnored public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
        if let d = directory, let data = try? Data(contentsOf: d.appendingPathComponent("history.json")) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            records = (try? dec.decode([DeployRecord].self, from: data)) ?? []
        }
    }

    public func save(_ r: DeployRecord, log: String?) throws {
        if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r } else { records.insert(r, at: 0) }
        guard let d = directory else { return }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(records).write(to: d.appendingPathComponent("history.json"), options: .atomic)
        if let log { try Data(log.utf8).write(to: logURL(r.id)!, options: .atomic) }
    }

    public func logURL(_ id: String) -> URL? { directory?.appendingPathComponent("\(id).log") }

    public func log(_ id: String) -> String? { logURL(id).flatMap { try? String(contentsOf: $0, encoding: .utf8) } }

    /// Ostatnie udane wdrożenie celu (commit wdrożony według historii).
    public func lastSuccess(target id: UUID) -> DeployRecord? {
        records.first { $0.targetID == id && $0.kind == .deploy && $0.outcome == .success }
    }

    /// Czy commit jest już wdrożony z powodzeniem na którymś z celów UAT (ostrzeżenie przed PROD).
    public func isDeployed(commit: String, onAnyOf targets: [UUID]) -> Bool {
        targets.contains { t in lastSuccess(target: t)?.headAfter.map { $0.hasPrefix(commit) || commit.hasPrefix($0) } ?? false }
    }
}
