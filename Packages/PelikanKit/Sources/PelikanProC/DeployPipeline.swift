#if canImport(Darwin)
import Foundation
import Observation
import PelikanLog
import PelikanRemote
import PelikanWorkspace

/// Podsumowanie przed wdrożeniem: commit na serwerze → commit `<remote>/<gałąź>`, commity i pliki między nimi,
/// ostrzeżenia (lokalne zmiany niewypchnięte, PROD bez tego commita na UAT).
public struct DeploySummary: Sendable, Hashable {
    public var serverHead: String?
    public var remoteHead: String?
    public var commits: [String] = []
    public var diffStat = ""
    public var warnings: [String] = []

    public var isUpToDate: Bool { serverHead != nil && serverHead == remoteHead }

    /// Zestawienie podsumowania: commit z serwera (sesja SSH), stan lokalnego repo po `fetch`, historia UAT.
    @MainActor
    public static func prepare(target t: PelikanSSHTarget, session: SSHSession, repo: URL?, history: DeployHistoryStore,
                               uatTargets: [UUID]) async -> DeploySummary {
        var s = DeploySummary()
        let serverHead: String? = await Task.detached {
            guard let r = try? session.run(DeployScripts.serverHeadCommand(t), timeout: 60), r.status == 0 else { return nil }
            let h = String(decoding: r.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return h.isEmpty ? nil : h
        }.value
        s.serverHead = serverHead
        if serverHead == nil { s.warnings.append(L10n.tr("Nie udało się odczytać commita working copy na serwerze")) }
        if let repo {
            let local: Result<LocalGitStatus, any Error> = await Task.detached {
                Result {
                    try? LocalGit.fetch(repo: repo, remote: t.remote)
                    return try LocalGit.status(repo: repo, remote: t.remote, branch: t.branch)
                }
            }.value
            switch local {
            case .success(let st):
                s.remoteHead = st.remoteHead
                s.warnings += st.warnings
                if let from = serverHead, let to = st.remoteHead, from != to {
                    let (commits, stat): ([String], String) = await Task.detached {
                        guard LocalGit.hasCommit(repo: repo, from) else { return ([], "") }
                        return ((try? LocalGit.commits(repo: repo, from: from, to: to)) ?? [], (try? LocalGit.diffStat(repo: repo, from: from, to: to)) ?? "")
                    }.value
                    s.commits = commits
                    s.diffStat = stat
                    if !LocalGit.hasCommit(repo: repo, from) {
                        s.warnings.append(L10n.tr("Commita z serwera nie ma w lokalnym repo — lista zmian niedostępna"))
                    }
                }
            case .failure(let e):
                s.warnings.append(e.localizedDescription)
            }
        } else {
            s.warnings.append(L10n.tr("Brak lokalnego repo projektu — bez listy zmian i kontroli niewypchniętych commitów"))
        }
        if t.environment == .prod {
            if let head = s.remoteHead {
                if !history.isDeployed(commit: head, onAnyOf: uatTargets) {
                    s.warnings.append(L10n.tr("Ten commit nie został jeszcze wdrożony z powodzeniem na UAT"))
                }
            } else {
                s.warnings.append(L10n.tr("Nie wiadomo, czy ten commit jest na UAT (brak commita remote)"))
            }
        }
        return s
    }
}

/// Wdrożenie albo wycofanie binarki na celu (zadanie Pro*C, „Pipeline Wdrożenie”): skrypt ksh88 wysłany przez
/// `scp -O` do `<backupy>/.pelikan`, uruchomiony przez `ssh -tt`, postęp ze znaczników, Stop (pty + `@@PID`),
/// zawsze zdjęcie własnej blokady po zatrzymaniu, historia z pełnym logiem.
@MainActor
@Observable
public final class DeployPipeline: Identifiable {
    public enum Operation: Sendable, Hashable {
        case deploy
        case rollback(binary: String, source: RollbackSource)
    }

    public let id: String
    public let target: PelikanSSHTarget
    public let operation: Operation
    public private(set) var progress = DeployProgress()
    public private(set) var running = false
    public private(set) var record: DeployRecord
    public private(set) var stopRequested = false

    @ObservationIgnored let plan: DeployPlan
    @ObservationIgnored let session: SSHSession
    @ObservationIgnored let history: DeployHistoryStore?
    @ObservationIgnored var process: RemoteProcess?

    public init(target: PelikanSSHTarget, operation: Operation, plan: DeployPlan, session: SSHSession, history: DeployHistoryStore?) {
        id = plan.id
        self.target = target
        self.operation = operation
        self.plan = plan
        self.session = session
        self.history = history
        let kind: DeployRecord.Kind = if case .deploy = operation { .deploy } else { .rollback }
        record = DeployRecord(id: plan.id, kind: kind, target: target, owner: plan.owner)
    }

    /// Właściciel do blokady i historii: `użytkownik@host-Maca`.
    public nonisolated static func defaultOwner() -> String {
        NSUserName() + "@" + (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
    }

    public var outcome: DeployOutcome? { record.outcome }

    func script() throws -> String {
        switch operation {
        case .deploy: try DeployScripts.deploy(target, plan: plan)
        case let .rollback(binary, source): try DeployScripts.rollback(target, plan: plan, binary: binary, source: source)
        }
    }

    /// Uruchomienie (wywołujący wcześniej pokazał podsumowanie i — dla PROD — uzyskał `ProductionConfirmation`).
    public func run() async {
        guard !running else { return }
        Log.proc.info("Pro*C: start \(record.kind.rawValue, privacy: .public) na cel \(target.name, privacy: .hash) (\(target.environment.rawValue, privacy: .public))")
        running = true
        defer { running = false }
        progress.info(L10n.tr("Cel: \(target.name) (\(target.environment.rawValue)), \(target.user)@\(target.host), working copy \(target.effectiveWorkingCopy)"))
        let t = target, session = session, id = plan.id
        let scriptText: String
        do { scriptText = try script() } catch {
            finish(code: -1, stopped: false, error: error.localizedDescription)
            return
        }
        // Przygotowanie: katalog roboczy Pelikana i skrypt przez scp -O (zapis lokalny z prawami tylko dla użytkownika).
        let upload: String? = await Task.detached {
            do {
                let mk = try session.run(DeployScripts.prepareCommand(t), timeout: 60)
                guard mk.status == 0 else { return L10n.tr("Nie można utworzyć katalogu \(t.pelikanDirectory): \(mk.errorText)") }
                let local = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-run-\(id).ksh")
                try Data(scriptText.utf8).write(to: local, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: local.path)
                defer { try? FileManager.default.removeItem(at: local) }
                try session.scp(upload: local.path, to: DeployScripts.scriptPath(t, id: id))
                return nil
            } catch { return SSHTargetTester.describe(error) }
        }.value
        if let upload {
            finish(code: -1, stopped: false, error: upload)
            return
        }
        guard !stopRequested else {
            finish(code: 143, stopped: true, error: nil)
            await cleanUp(releaseLock: false)
            return
        }
        let command = SSHSession.shellQuote(t.kshPath) + " " + SSHSession.shellQuote(DeployScripts.scriptPath(t, id: id))
        var exitCode: Int32 = -1
        var failure: String?
        do {
            let p = try session.stream(command, environment: t.remoteEnvironment, tty: true, outputEncoding: t.consoleEncoding)
            process = p
            for try await e in p.events {
                switch e {
                case .stdout(let s): progress.feed(s)
                case .stderr(let s): progress.feed(s, error: true)
                case .exit(let c): exitCode = c
                }
            }
        } catch {
            if !stopRequested { failure = SSHTargetTester.describe(error) }
        }
        process = nil
        finish(code: exitCode, stopped: stopRequested, error: failure)
        // Po Stop albo zerwaniu (błąd strumienia, kod 255 ssh) — zawsze zdjęcie własnej blokady (skrypt zabity KILL
        // nie wykona pułapki).
        await cleanUp(releaseLock: stopRequested || failure != nil || exitCode == 255)
    }

    func finish(code: Int32, stopped: Bool, error: String?) {
        if let error { progress.info(error) }
        progress.finish(exitCode: code, stopped: stopped)
        record.finished = Date()
        record.exitCode = progress.exitCode
        record.headBefore = progress.headBefore
        record.headAfter = progress.headAfter ?? (progress.outcome == .success ? nil : progress.headBefore)
        record.outcome = stopped ? .stopped : (code == -1 ? .failed : progress.outcome)
        record.failedStep = progress.steps.last(where: { $0.status == .failed || $0.status == .stopped })?.name
        record.detail = error ?? record.outcome?.title
        progress.info(record.outcome?.title ?? "")
        try? history?.save(record, log: progress.logText)
        Log.proc.info("Pro*C: \(record.kind.rawValue, privacy: .public) na cel \(target.name, privacy: .hash) (\(target.environment.rawValue, privacy: .public)) — \(record.outcome.map { String(describing: $0) } ?? "?", privacy: .public), kod \(code), krok z błędem \(record.failedStep, privacy: .public)")
    }

    func cleanUp(releaseLock: Bool) async {
        let t = target, session = session, id = plan.id
        let released: Bool = await Task.detached {
            var released = false
            if releaseLock, let r = try? session.run(DeployScripts.releaseOwnLockCommand(t, id: id), timeout: 30) {
                released = String(decoding: r.output, as: UTF8.self).contains("released")
            }
            _ = try? session.run(DeployScripts.cleanupCommand(t, id: id), timeout: 30)
            return released
        }.value
        if released { progress.info(L10n.tr("Zdjęto blokadę tego wdrożenia")) }
    }

    /// Stop: zakończenie `ssh -tt` (SIGHUP po stronie serwera) i zapasowe `kill` po `@@PID`; blokada zdejmowana po
    /// zakończeniu strumienia.
    public func stop() {
        guard running, !stopRequested else { return }
        stopRequested = true
        progress.info(L10n.tr("Zatrzymywanie…"))
        guard let p = process else { return }
        Task.detached { p.stop() }
    }

    /// Ręczne zdjęcie cudzej/przeterminowanej blokady (wywołujący pyta o potwierdzenie; PROD — nazwa celu).
    public nonisolated static func forceReleaseLock(_ t: PelikanSSHTarget, session: SSHSession) async throws {
        let r: Spawn.Result = try await Task.detached { try session.run(DeployScripts.forceReleaseLockCommand(t), timeout: 30) }.value
        guard r.status == 0 else { throw SSHError.io(code: r.status, detail: r.errorText) }
    }

    /// Kopie binarek w katalogu backupów (najnowsze pierwsze).
    public nonisolated static func backups(_ t: PelikanSSHTarget, session: SSHSession) async throws -> [BackupEntry] {
        let r: Spawn.Result = try await Task.detached { try session.run(DeployScripts.listBackupsCommand(t), timeout: 60) }.value
        guard r.status == 0 else { throw SSHError.io(code: r.status, detail: r.errorText) }
        return BackupEntry.list(String(decoding: r.output, as: UTF8.self), binaries: t.effectiveBinaries)
    }

    /// Historia z serwera (najnowsze pierwsze).
    public nonisolated static func serverHistory(_ t: PelikanSSHTarget, session: SSHSession) async throws -> [ServerHistoryEntry] {
        let r: Spawn.Result = try await Task.detached { try session.run(DeployScripts.serverHistoryCommand(t), timeout: 60) }.value
        return ServerHistoryEntry.parse(String(decoding: r.output, as: UTF8.self))
    }
}

/// Bieżące i ostatnie wdrożenia w aplikacji (konsola pokazuje wybrane).
@MainActor
@Observable
public final class DeployCenter {
    public private(set) var pipelines: [DeployPipeline] = []
    public var selectedID: String?

    public init() {}

    public var selected: DeployPipeline? { pipelines.first { $0.id == selectedID } ?? pipelines.first }

    public func add(_ p: DeployPipeline) {
        pipelines.insert(p, at: 0)
        if pipelines.count > 20 { pipelines.removeLast(pipelines.count - 20) }
        selectedID = p.id
    }

    /// Czy na celu trwa wdrożenie z tej aplikacji.
    public func isRunning(target id: UUID) -> Bool { pipelines.contains { $0.target.id == id && $0.running } }
}
#endif
