import Foundation
@testable import PelikanProC
import PelikanWorkspace
import Testing
#if canImport(Darwin)
@testable import PelikanRemote
#endif

private func sampleTarget() -> PelikanSSHTarget {
    var t = PelikanSSHTarget(name: "UAT app", host: "build.example.invalid", user: "dev", baseDirectory: "/u/app base", backupDirectory: "/u/kopie")
    t.binaries = ["app", "app.cgi"]
    t.buildCommand = "make all"
    return t
}

@Suite("Skrypty wdrożenia ksh88 i postęp z konsoli")
struct DeployScriptTests {
    let plan = DeployPlan(id: "abc-123", timestamp: "20261023120000", owner: "dev@mac")

    @Test("Skrypt wdrożenia: wartości przez shellQuote, kroki w kolejności, bez konstrukcji spoza ksh88")
    func deployScript() throws {
        let s = try DeployScripts.deploy(sampleTarget(), plan: plan)
        #expect(s.contains("WC='/u/app base/src'") && s.contains("BK='/u/kopie'") && s.contains("PD='/u/kopie/.pelikan'"))
        #expect(s.contains("for B in 'app' 'app.cgi'; do"))
        let order = ["step lock", "step check", "step pull", "step backup", "step build", "step install", "step history"]
        let positions = order.map { s.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil })
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0! < $1! })
        #expect(s.contains("git pull --ff-only \"$REMOTE\" \"$BRANCH\"") && !s.contains("git merge") && !s.contains("git reset"))
        #expect(s.contains("grep '^app\\.cgi\\.[0-9]\\{14\\}\\.' | sed -n '6,$p'"))
        #expect(DeployScripts.forbiddenConstructs(s).isEmpty, "\(DeployScripts.forbiddenConstructs(s))")
        let r = try DeployScripts.rollback(sampleTarget(), plan: plan, binary: "app", source: .backup("app.20261020101010.1a2b3c4d.Z"))
        #expect(r.contains("uncompress -c \"$F\"") && DeployScripts.forbiddenConstructs(r).isEmpty)
        #expect(try DeployScripts.rollback(sampleTarget(), plan: plan, binary: "app", source: .previous).contains("\"$BIN/$B.prev\""))
    }

    @Test("Strażnik zakazanych konstrukcji wykrywa przykłady z listy zadania")
    func forbidden() {
        let bad = "set -o pipefail\nlocal x=1\nX=${v//a/b}\nsed -i s/a/b/ f\nT=$(mktemp)\ndate +%s\n[[ $a =~ b ]]\nY=$(< f)\ngit -C /x status\n"
        let found = Set(DeployScripts.forbiddenConstructs(bad))
        #expect(found.isSuperset(of: ["set -o pipefail", "local", "${v//a/b}", "sed -i", "mktemp", "date +%s", "[[ ]]", "$(< plik)", "git -C"]))
        #expect(DeployScripts.forbiddenConstructs("# local komentarz\ngit status --porcelain\n").isEmpty)
    }

    @Test("Walidacja: nazwy binarek, identyfikator, ścieżki, pusta komenda builda")
    func validation() {
        var t = sampleTarget()
        t.binaries = ["../etc"]
        #expect(throws: DeployScriptError.invalidBinaryName("../etc")) { try DeployScripts.deploy(t, plan: plan) }
        #expect(throws: DeployScriptError.invalidIdentifier("x;y")) { try DeployScripts.deploy(sampleTarget(), plan: DeployPlan(id: "x;y", owner: "a")) }
        t = sampleTarget()
        t.buildCommand = "  "
        #expect(throws: DeployScriptError.emptyBuildCommand) { try DeployScripts.deploy(t, plan: plan) }
        t = sampleTarget()
        t.workingCopyDirectory = "src"
        #expect(throws: DeployScriptError.invalidPath("src")) { try DeployScripts.deploy(t, plan: plan) }
        // Remote i gałąź nie mogą zamienić się w opcje gita (R8-09).
        t = sampleTarget()
        t.remote = "--upload-pack=touch /tmp/x"
        #expect(throws: DeployScriptError.invalidGitName(t.remote)) { try DeployScripts.deploy(t, plan: plan) }
        #expect(t.gitNameErrors.count == 1 && t.validationErrors.contains(t.gitNameErrors[0]))
        t = sampleTarget()
        t.branch = "-x"
        #expect(throws: DeployScriptError.invalidGitName("-x")) { try DeployScripts.deploy(t, plan: plan) }
        #expect(PelikanSSHTarget.isSafeGitName("feature/ABC-12_x.1") && !PelikanSSHTarget.isSafeGitName("a b")
                && !PelikanSSHTarget.isSafeGitName("") && !PelikanSSHTarget.isSafeGitName("a;b"))
        #expect((try? DeployScripts.deploy(sampleTarget(), plan: plan))?.contains("git fetch -- \"$REMOTE\"") == true)
    }

    #if canImport(Darwin)
    @Test("Składnia skryptów (ksh -n; ksh93 na macOS — wiarygodny test tylko na AIX)", .enabled(if: FileManager.default.isExecutableFile(atPath: "/bin/ksh")))
    func syntax() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-ksh-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scripts = [try DeployScripts.deploy(sampleTarget(), plan: plan),
                       try DeployScripts.rollback(sampleTarget(), plan: plan, binary: "app", source: .previous),
                       try DeployScripts.rollback(sampleTarget(), plan: plan, binary: "app", source: .backup("app.20261020101010.1a2b3c4d.gz"))]
        for (i, s) in scripts.enumerated() {
            let f = dir.appendingPathComponent("s\(i).ksh")
            try Data(s.utf8).write(to: f)
            let r = try Spawn.run("/bin/ksh", [Array("-n".utf8), Array(f.path.utf8)], environment: [:])
            #expect(r.status == 0, "\(r.errorText)")
        }
    }
    #endif

    @Test("Kopie: nazwa z kropkami, kompresja, lista z ls -t")
    func backups() {
        let e = BackupEntry.parse("app.cgi.20261023120000.1a2b3c4d.gz", binaries: ["app", "app.cgi"])
        #expect(e?.binary == "app.cgi" && e?.timestamp == "20261023120000" && e?.commit == "1a2b3c4d" && e?.compression == .gzip)
        #expect(BackupEntry.parse("app.2026.1a", binaries: ["app"]) == nil)
        let list = BackupEntry.list("app.20261023120000.aa.Z\nhistory.log\n.pelikan\napp.20261022120000.bb\n", binaries: ["app"])
        #expect(list.map(\.commit) == ["aa", "bb"] && list[0].compression == .compress)
    }

    @Test("Postęp: kroki, commity, blokada, brudna working copy, komunikaty kompilatora, porcje rozcięte w pół linii")
    func progress() {
        var p = DeployProgress()
        p.feed("@@STEP lock\n@@END lo")
        p.feed("ck 0\n@@STEP check\n@@DIRTY_BEGIN\n?? nowy.pc\n M main.pc\n@@DIRTY_END\n")
        p.feed("@@END check 20\n")
        p.finish(exitCode: 20)
        #expect(p.steps.map(\.name) == ["lock", "check"] && p.steps.map(\.status) == [.ok, .failed])
        #expect(p.dirtyFiles == ["?? nowy.pc", " M main.pc"] && p.outcome == .dirty)

        var b = DeployProgress()
        b.feed("@@STEP pull\n@@HEAD_BEFORE 1111\n@@HEAD_AFTER 2222\n@@END pull 0\n@@STEP build\n")
        b.feed("xlc -c app.c\n\"app.c\", line 3.5: 1506-045 (S) Undeclared identifier x.\n")
        b.feed("make: 1254-004 The error code from the last command is 1.\n", error: true)
        b.feed("@@END build 2\n")
        b.finish(exitCode: DeployScripts.Exit.buildFailed)
        #expect(b.headBefore == "1111" && b.headAfter == "2222" && b.outcome == .buildFailed)
        #expect(b.messages.count == 1 && b.messages[0].code == "1506-045" && b.messages[0].line == 3)
        let line = b.lines[b.messages[0].outputLine]
        #expect(line.text.hasPrefix("\"app.c\"") && line.step == "build" && b.messageLines[line.id] != nil)
        #expect(b.lines.contains { $0.kind == .error && $0.text.contains("1254-004") })
        #expect(b.logText.contains("== Build"))

        var l = DeployProgress()
        l.feed("@@STEP lock\n@@LOCKINFO\nid=x\nowner=kto@mac\npid=42\n@@LOCKINFO_END\n@@END lock 10\n")
        l.finish(exitCode: 10)
        #expect(l.lockInfo == ["id=x", "owner=kto@mac", "pid=42"] && l.outcome == .locked)

        var s = DeployProgress()
        s.feed("@@STEP build\nmake\n")
        s.finish(exitCode: 255, stopped: true)
        #expect(s.outcome == .stopped && s.steps.last?.status == .stopped)

        // Kod 255 bez Stop: ssh zerwał połączenie — błąd, nie zatrzymanie przez użytkownika.
        var lost = DeployProgress()
        lost.feed("@@STEP build\nmake\n")
        lost.finish(exitCode: 255)
        #expect(lost.outcome == .failed && lost.steps.last?.status == .failed)
        #expect(DeployOutcome.from(exitCode: 143) == .stopped)
    }

    @Test("Historia z serwera i lokalna (zapis, log, ostatnie udane, commit na UAT)")
    @MainActor
    func history() throws {
        let entries = ServerHistoryEntry.parse("20261023120000|a|dev@mac|deploy|11|22|done|0\nzły wiersz\n20261023130000|b|dev@mac|deploy|22|33|build|2\n")
        #expect(entries.map(\.id) == ["b", "a"] && entries[1].succeeded && !entries[0].succeeded)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-hist-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DeployHistoryStore(directory: dir)
        var uat = sampleTarget()
        uat.environment = .uat
        var r = DeployRecord(id: "d1", kind: .deploy, target: uat, owner: "dev@mac")
        r.outcome = .success
        r.headAfter = "2222333344445555"
        try store.save(r, log: "== Build\nok")
        let again = DeployHistoryStore(directory: dir)
        #expect(again.records.count == 1 && again.log("d1") == "== Build\nok")
        #expect(again.isDeployed(commit: "2222333344445555", onAnyOf: [uat.id]) && !again.isDeployed(commit: "9999", onAnyOf: [uat.id]))
    }
}

#if canImport(Darwin)
/// Lokalny „serwer” na sshd: bare repo jako GitLab, working copy `<baza>/src` na gałęzi MASTER, makefile kopiujący
/// skrypt do binarki, klon deweloperski do nowych commitów i klon „Maca” do podsumowania.
@MainActor
final class DeployFixture {
    let sshd: TestSSHD
    let session: SSHSession
    let run: URL
    var target: PelikanSSHTarget
    let origin: String
    let dev: String
    let base: String

    nonisolated static let gitEnv = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.temporaryDirectory.path, "GIT_CONFIG_GLOBAL": "/dev/null",
                         "GIT_CONFIG_NOSYSTEM": "1", "LC_ALL": "C"]

    @discardableResult
    nonisolated static func git(_ dir: String, _ args: String...) throws -> String {
        let r = try Spawn.run("/usr/bin/git", (["-C", dir, "-c", "user.email=t@example.invalid", "-c", "user.name=t", "-c", "commit.gpgsign=false",
                                                "-c", "init.defaultBranch=MASTER"] + args).map { Array($0.utf8) }, environment: gitEnv)
        guard r.status == 0 else { throw SSHError.io(code: r.status, detail: "git \(args): \(r.errorText)") }
        return String(decoding: r.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init() throws {
        sshd = try TestSSHD()
        let root = sshd.root.path
        origin = root + "/origin.git"
        dev = root + "/dev"
        base = root + "/app base"
        try FileManager.default.createDirectory(atPath: origin, withIntermediateDirectories: true)
        try Self.git(origin, "init", "-q", "--bare")
        try FileManager.default.createDirectory(atPath: dev, withIntermediateDirectories: true)
        try Self.git(dev, "init", "-q")
        try Self.git(dev, "checkout", "-q", "-b", "MASTER")
        try sshd.root.file("dev/Makefile", "all:\n\tcp app.sh app\n\tchmod 755 app\n")
        try sshd.root.file("dev/app.sh", "echo v1\n")
        try sshd.root.file("dev/.gitignore", "app\n")
        try Self.git(dev, "add", "-A")
        try Self.git(dev, "commit", "-q", "--no-verify", "-m", "v1")
        try Self.git(dev, "remote", "add", "origin", origin)
        try Self.git(dev, "push", "-q", "origin", "MASTER")
        try FileManager.default.createDirectory(atPath: base + "/bin", withIntermediateDirectories: true)
        try Self.git(base, "clone", "-q", "-b", "MASTER", origin, base + "/src")
        try sshd.root.file("app base/bin/app", "echo stara\n")

        target = PelikanSSHTarget(name: "lokalny UAT", host: "127.0.0.1", user: NSUserName(), baseDirectory: base, backupDirectory: root + "/kopie")
        target.port = sshd.port
        target.keyFile = sshd.clientKey
        target.legacyAlgorithms = true
        target.kshPath = "/bin/ksh"
        target.binaries = ["app"]
        target.buildCommand = "make all"
        run = try SocketDirectory.make(preferred: URL(fileURLWithPath: "/tmp/plk-\(UUID().uuidString.prefix(6))"))
        session = try SSHSession(config: SSHTargetTester.sessionConfig(target, configFile: sshd.clientConfig, knownHostsFile: sshd.knownHosts),
                                 runDirectory: run, secret: { TestSSHD.passphrase })
        try session.recordHostKey()
        try FileManager.default.createDirectory(atPath: target.backupDirectory, withIntermediateDirectories: true)
    }

    /// Nowy commit w GitLabie (klon deweloperski).
    func publish(_ file: String, _ text: String, message: String) throws {
        try sshd.root.file("dev/" + file, text)
        try Self.git(dev, "add", "-A")
        try Self.git(dev, "commit", "-q", "--no-verify", "-m", message)
        try Self.git(dev, "push", "-q", "origin", "MASTER")
    }

    func read(_ rel: String) -> String? { try? String(contentsOfFile: base + "/" + rel, encoding: .utf8) }
    func backups() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: target.backupDirectory))?.filter { $0.hasPrefix("app.") } ?? [] }
    var lockExists: Bool { FileManager.default.fileExists(atPath: target.pelikanDirectory + "/.lock") }
    var serverHead: String { (try? Self.git(base + "/src", "rev-parse", "HEAD")) ?? "" }

    func pipeline(_ op: DeployPipeline.Operation = .deploy, history: DeployHistoryStore? = nil, timestamp: String = DeployPlan.timestamp()) -> DeployPipeline {
        DeployPipeline(target: target, operation: op, plan: DeployPlan(timestamp: timestamp, owner: "test@mac"), session: session, history: history)
    }

    func close() {
        session.disconnect()
        try? FileManager.default.removeItem(at: run)
    }
}

@MainActor
@Suite("Wdrożenie na lokalnym sshd (ksh, git, make)", .serialized, .enabled(if: sshdAvailable && FileManager.default.isExecutableFile(atPath: "/bin/ksh")),
       .timeLimit(.minutes(3)))
struct DeployPipelineTests {
    @Test("Pełny cykl: pull --ff-only, backup, make, instalacja (.prev), historia, blokada zdjęta, rollback z .prev i z kopii")
    func fullCycle() async throws {
        let f = try DeployFixture()
        defer { f.close() }
        let histDir = f.sshd.root.url.appendingPathComponent("hist")
        let history = DeployHistoryStore(directory: histDir)
        let before = f.serverHead
        try f.publish("app.sh", "echo v2\n", message: "v2")

        // Podsumowanie: klon „Maca” widzi commit z serwera → nowy commit remote.
        let mac = f.sshd.root.path + "/mac"
        try DeployFixture.git(f.sshd.root.path, "clone", "-q", "-b", "MASTER", f.origin, mac)
        let summary = await DeploySummary.prepare(target: f.target, session: f.session, repo: URL(fileURLWithPath: mac), history: history, uatTargets: [])
        #expect(summary.serverHead == before && summary.remoteHead != before && summary.commits.count == 1 && summary.commits[0].hasSuffix("v2"))
        #expect(summary.diffStat.contains("app.sh"))

        let p = f.pipeline(history: history, timestamp: "20261023100000")
        await p.run()
        #expect(p.outcome == .success, "\(p.progress.logText)")
        #expect(p.progress.steps.map(\.name) == ["lock", "check", "pull", "backup", "build", "install", "history"])
        #expect(p.progress.steps.allSatisfy { $0.status == .ok })
        #expect(p.progress.headBefore == before && p.progress.headAfter == f.serverHead && f.serverHead != before)
        #expect(f.read("bin/app") == "echo v2\n" && f.read("bin/app.prev") == "echo stara\n")
        #expect(f.backups().count == 1 && f.backups()[0].hasPrefix("app.20261023100000.\(before.prefix(8))"))
        #expect(!f.lockExists && !FileManager.default.fileExists(atPath: DeployScripts.scriptPath(f.target, id: p.id)))
        #expect(history.records.first?.outcome == .success && history.log(p.id)?.contains("== Build") == true)
        let server = try await DeployPipeline.serverHistory(f.target, session: f.session)
        #expect(server.first?.id == p.id && server.first?.succeeded == true)

        // Rollback z .prev: zamiana miejscami.
        let r1 = f.pipeline(.rollback(binary: "app", source: .previous), history: history)
        await r1.run()
        #expect(r1.outcome == .success, "\(r1.progress.logText)")
        #expect(f.read("bin/app") == "echo stara\n" && f.read("bin/app.prev") == "echo v2\n")

        // Rollback z kopii (kopia sprzed wdrożenia = stara binarka; rozpakowanie, gdy skompresowana).
        let backups = try await DeployPipeline.backups(f.target, session: f.session)
        #expect(backups.count == 1)
        let r2 = f.pipeline(.rollback(binary: "app", source: .backup(backups[0].fileName)), history: history)
        await r2.run()
        #expect(r2.outcome == .success && f.read("bin/app") == "echo stara\n" && !f.lockExists, "\(r2.progress.logText)")
    }

    @Test("Ręczna zmiana w working copy zatrzymuje wdrożenie przed pull; bin i HEAD bez zmian")
    func dirtyWorkingCopy() async throws {
        let f = try DeployFixture()
        defer { f.close() }
        let before = f.serverHead
        try f.publish("app.sh", "echo v2\n", message: "v2")
        try f.sshd.root.file("app base/src/poprawka.pc", "ręcznie na serwerze")
        let p = f.pipeline()
        await p.run()
        #expect(p.outcome == .dirty && p.progress.dirtyFiles == ["?? poprawka.pc"], "\(p.progress.logText)")
        #expect(f.serverHead == before && f.read("bin/app") == "echo stara\n" && f.backups().isEmpty && !f.lockExists)
        #expect(!p.progress.steps.contains { $0.name == "pull" })
    }

    @Test("Błąd builda: bin nietknięty, working copy na nowym commicie, komunikat xlc klikalny; zła gałąź przerywa")
    func buildFailure() async throws {
        let f = try DeployFixture()
        defer { f.close() }
        try f.publish("Makefile", "all:\n\t@echo '\"app.c\", line 3.5: 1506-045 (S) Undeclared identifier x.'\n\t@exit 1\n", message: "zepsuty")
        let p = f.pipeline()
        await p.run()
        #expect(p.outcome == .buildFailed, "\(p.progress.logText)")
        #expect(p.progress.messages.first?.code == "1506-045" && p.progress.messages.first?.file == "app.c")
        #expect(f.read("bin/app") == "echo stara\n" && f.read("bin/app.prev") == nil && f.serverHead == p.progress.headAfter && !f.lockExists)

        var other = f.target
        other.branch = "master"
        let q = DeployPipeline(target: other, operation: .deploy, plan: DeployPlan(owner: "t"), session: f.session, history: nil)
        await q.run()
        #expect(q.outcome == .wrongBranch && q.progress.serverBranch == "MASTER")
    }

    @Test("Blokada: aktywna (żywy proces) i przeterminowana; ręczne zdjęcie")
    func locks() async throws {
        let f = try DeployFixture()
        defer { f.close() }
        let lock = f.target.pelikanDirectory + "/.lock"
        try FileManager.default.createDirectory(atPath: lock, withIntermediateDirectories: true)
        try Data("id=inny\nowner=kolega@mac\ntime=20261023000000\npid=\(getpid())\n".utf8).write(to: URL(fileURLWithPath: lock + "/info"))
        let p = f.pipeline()
        await p.run()
        #expect(p.outcome == .locked && p.progress.lockInfo.contains("owner=kolega@mac") && f.lockExists)

        try Data("id=inny\nowner=kolega@mac\npid=999999\n".utf8).write(to: URL(fileURLWithPath: lock + "/info"))
        let s = f.pipeline()
        await s.run()
        #expect(s.outcome == .staleLock && f.lockExists)
        try await DeployPipeline.forceReleaseLock(f.target, session: f.session)
        #expect(!f.lockExists)
    }

    @Test("Stop w trakcie builda: proces na serwerze kończy się, blokada zdjęta, wynik „zatrzymane”")
    func stop() async throws {
        let f = try DeployFixture()
        defer { f.close() }
        let marker = "pelikan-stop-\(UUID().uuidString.prefix(6))"
        f.target.buildCommand = "/bin/sh -c 'sleep 30' \(marker)"
        let p = f.pipeline()
        let task = Task { await p.run() }
        for _ in 0..<200 where !p.progress.steps.contains(where: { $0.name == "build" }) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(p.progress.steps.contains { $0.name == "build" })
        p.stop()
        await task.value
        #expect(p.outcome == .stopped && !f.lockExists, "\(p.progress.logText)")
        #expect(f.read("bin/app") == "echo stara\n")
        let ps = try f.session.run("ps -ax -o pid,pgid,command | grep \(marker) | grep -v grep", timeout: 20)
        #expect(String(decoding: ps.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(String(decoding: ps.output, as: UTF8.self))")
    }
}

@Suite("Lokalny git projektu", .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
struct LocalGitTests {
    @Test("Niewypchnięte commity i niezatwierdzone pliki dają ostrzeżenia")
    func status() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-lgit-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = root.appendingPathComponent("o.git").path, work = root.appendingPathComponent("w").path
        try FileManager.default.createDirectory(atPath: origin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        try DeployFixture.git(origin, "init", "-q", "--bare")
        try DeployFixture.git(work, "init", "-q")
        try DeployFixture.git(work, "checkout", "-q", "-b", "MASTER")
        try Data("a".utf8).write(to: URL(fileURLWithPath: work + "/a.pc"))
        try DeployFixture.git(work, "add", "-A")
        try DeployFixture.git(work, "commit", "-q", "--no-verify", "-m", "a")
        try DeployFixture.git(work, "remote", "add", "origin", origin)
        let repo = URL(fileURLWithPath: work)
        #expect(try LocalGit.status(repo: repo, remote: "origin", branch: "MASTER").ahead == nil)
        try DeployFixture.git(work, "push", "-q", "origin", "MASTER")
        try LocalGit.fetch(repo: repo, remote: "origin")
        var s = try LocalGit.status(repo: repo, remote: "origin", branch: "MASTER")
        #expect(s.branch == "MASTER" && s.ahead == 0 && s.behind == 0 && s.warnings.isEmpty)
        try Data("b".utf8).write(to: URL(fileURLWithPath: work + "/a.pc"))
        try DeployFixture.git(work, "commit", "-q", "--no-verify", "-am", "b")
        try Data("c".utf8).write(to: URL(fileURLWithPath: work + "/nowy.pc"))
        s = try LocalGit.status(repo: repo, remote: "origin", branch: "MASTER")
        #expect(s.ahead == 1 && s.uncommitted == ["?? nowy.pc"] && s.warnings.count == 2)
        let head = try DeployFixture.git(work, "rev-parse", "HEAD")
        #expect(try LocalGit.commits(repo: repo, from: s.remoteHead!, to: head).count == 1)
        #expect(LocalGit.hasCommit(repo: repo, head) && !LocalGit.hasCommit(repo: repo, String(repeating: "0", count: 40)))
        // Nazwy z celu nie trafiają do gita jako opcje (R8-09); hasz zaczynający się od „-” to rewizja, nie opcja.
        #expect(throws: DeployScriptError.invalidGitName("--upload-pack=x")) { try LocalGit.fetch(repo: repo, remote: "--upload-pack=x") }
        #expect(throws: DeployScriptError.invalidGitName("-b")) { try LocalGit.status(repo: repo, remote: "origin", branch: "-b") }
        #expect(!LocalGit.hasCommit(repo: repo, "--help"))
        #expect((try? LocalGit.commits(repo: repo, from: "--output=x", to: head)) == [])
        #expect(!FileManager.default.fileExists(atPath: work + "/x..\(head)"))
    }
}
#endif
