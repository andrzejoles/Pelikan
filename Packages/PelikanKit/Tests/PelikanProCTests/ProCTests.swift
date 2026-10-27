import Foundation
import Testing
@testable import PelikanProC
import PelikanRemote
import PelikanWorkspace

@MainActor
final class OwnerPrompter: ConnectionPrompter {
    var ownerAnswers: [Bool] = []
    var ownerAsked = 0
    func askPassword(for connection: ConnectionDefinition, reason: String?) async -> (password: String, remember: Bool)? { nil }
    func askNewPassword(for connection: ConnectionDefinition, message: String) async -> String? { nil }
    func authenticateOwner(reason: String) async -> Bool {
        ownerAsked += 1
        return ownerAnswers.isEmpty ? false : ownerAnswers.removeFirst()
    }
}

@MainActor
@Suite("Cele SSH (Pro*C)")
struct SSHTargetTests {
    func target(_ name: String = "app-uat") -> PelikanSSHTarget {
        var t = PelikanSSHTarget(name: name, host: "build.example.invalid", user: "builder", baseDirectory: "/build/app",
                                 backupDirectory: "/build/backup")
        t.keyFile = "/keys/id_test"
        return t
    }

    @Test("Ścieżki wyliczane z katalogu bazowego, nadpisanie w zaawansowanych, domyślne binarki i walidacja")
    func derivedPaths() {
        var t = target()
        #expect(t.sourceDirectory == "/build/app/src" && t.binaryDirectory == "/build/app/bin")
        #expect(t.effectiveWorkingCopy == "/build/app/src" && t.pelikanDirectory == "/build/backup/.pelikan")
        #expect(t.branch == "MASTER" && t.remote == "origin" && t.buildCommand == "make" && t.effectiveBinaries == ["app-uat"])
        #expect(t.validationErrors.isEmpty)
        t.sourceFolderName = "source"
        t.workingCopyDirectory = "/repo/app"
        #expect(t.sourceDirectory == "/build/app/source" && t.effectiveWorkingCopy == "/repo/app")
        t.backupDirectory = "/repo/app/backup"
        #expect(t.validationErrors.count == 1)
        t.backupDirectory = "relative"
        t.auth = .keyFile
        t.keyFile = ""
        #expect(t.validationErrors.count == 2)
        #expect(PelikanSSHTarget.suggestedBackupDirectory(base: "/build/app/") == "/build/app/backup")
    }

    @Test("Prolog środowiska: ORACLE_HOME, LIBPATH, PATH i dodatkowe zmienne (puste pomijane)")
    func environment() throws {
        var t = target()
        t.oracleHome = "/opt/oracle"
        t.libPath = "/opt/oracle/lib"
        t.extraEnvironment = [SSHEnvironmentVariable(name: "TNS_ADMIN", value: "/opt/tns"), SSHEnvironmentVariable(name: "", value: "x")]
        #expect(t.remoteEnvironment.map(\.name) == ["ORACLE_HOME", "LIBPATH", "TNS_ADMIN"])
        #if canImport(Darwin)
        let prolog = try SSHSession.environmentProlog(t.remoteEnvironment)
        #expect(prolog.contains("ORACLE_HOME='/opt/oracle'; export ORACLE_HOME;"))
        #endif
    }

    @Test("Plik celów bez sekretów; sekret w SecretStore; eksport/import z nowymi identyfikatorami")
    func storeKeepsSecretsOut() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-ssh-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let secrets = MemorySecretStore()
        let file = dir.appendingPathComponent("ssh-targets.json")
        let store = SSHTargetStore(fileURL: file, secrets: secrets)
        let folder = SSHTargetFolder(name: "Sklep")
        try store.upsert(folder: folder)
        var t = target()
        t.folderID = folder.id
        t.auth = .password
        let secret = "s-" + UUID().uuidString
        try store.upsert(t, secret: secret)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains(secret) && text.contains("build.example.invalid"))
        #expect(try secrets.password(for: t.id.uuidString) == secret && store.hasSecret(for: t.id))

        let reloaded = SSHTargetStore(fileURL: file, secrets: secrets)
        #expect(reloaded.targets == [t] && reloaded.folders == [folder])

        let copy = try #require(try store.duplicate(t.id))
        #expect(copy.id != t.id && copy.name != t.name && copy.host == t.host && !store.hasSecret(for: copy.id))

        let exported = try store.exportData()
        #expect(!String(decoding: exported, as: UTF8.self).contains(secret))
        let other = SSHTargetStore(fileURL: nil, secrets: MemorySecretStore())
        #expect(try other.importData(exported) == 2)
        #expect(other.targets.allSatisfy { $0.id != t.id } && other.folders.count == 1)
        #expect(other.targets.allSatisfy { $0.folderID == other.folders[0].id })
        #expect(throws: (any Error).self) { try other.importData(Data("{\"format\":\"x\",\"version\":1,\"folders\":[],\"targets\":[]}".utf8)) }

        try store.remove(folder: folder.id)
        #expect(store.target(t.id)?.folderID == nil)
        try store.remove(t.id)
        #expect(try secrets.password(for: t.id.uuidString) == nil)
    }

    @Test("Nieczytelny plik celów i historii wdrożeń: kopia .bad, komunikat, zapis nie nadpisuje oryginału (R8-08)")
    func damagedFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-ssh-bad-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(SSHTargetStore.fileName)
        try Data(#"{"format":"pelikan-ssh-targets","version":1,"folders":[],"targets":[{"name":"stary"}]}"#.utf8).write(to: file)
        let store = SSHTargetStore(fileURL: file, secrets: MemorySecretStore())
        #expect(store.targets.isEmpty && store.loadProblem != nil)
        try store.upsert(target())
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let bad = try #require(files.first { $0.hasPrefix(SSHTargetStore.fileName + ".bad-") })
        #expect(try String(contentsOf: dir.appendingPathComponent(bad), encoding: .utf8).contains("stary"))

        let hist = dir.appendingPathComponent("proc-deploys", isDirectory: true)
        try FileManager.default.createDirectory(at: hist, withIntermediateDirectories: true)
        try Data("[{\"id\":".utf8).write(to: hist.appendingPathComponent("history.json"))
        let history = DeployHistoryStore(directory: hist)
        #expect(history.records.isEmpty && history.loadProblem != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: hist.path).contains { $0.hasPrefix("history.json.bad-") })
    }

    @Test("Sekret bez zapamiętania tylko w pamięci; ochrona D56: bez potwierdzenia właściciela zapisany sekret nie jest użyty")
    func ownerGate() async throws {
        let secrets = MemorySecretStore()
        let ws = Workspace(secrets: MemorySecretStore())
        let store = SSHTargetStore(fileURL: nil, secrets: secrets)
        let saved = target("saved")
        let temporary = target("temp")
        let s1 = UUID().uuidString, s2 = UUID().uuidString
        try store.upsert(saved, secret: s1)
        try store.upsert(temporary, secret: s2, remember: false)
        #expect(try secrets.password(for: temporary.id.uuidString) == nil)
        let prompter = OwnerPrompter()
        ws.sessions.prompter = prompter
        ws.settings.requireOwnerForSavedPasswords = true
        #expect(try await store.secret(for: temporary.id, in: ws) == s2 && prompter.ownerAsked == 0)
        await #expect(throws: CommandError.cancelledByUser) { _ = try await store.secret(for: saved.id, in: ws) }
        prompter.ownerAnswers = [true]
        #expect(try await store.secret(for: saved.id, in: ws) == s1)
        #expect(try await store.secret(for: saved.id, in: ws) == s1 && prompter.ownerAsked == 2)
        ws.settings.requireOwnerForSavedPasswords = false
        let other = target("other")
        try store.upsert(other, secret: s2)
        #expect(try await store.secret(for: other.id, in: ws) == s2 && prompter.ownerAsked == 2)
    }

    @Test("PROD: potwierdzenie dokładną nazwą celu; UAT bez pytania")
    func productionConfirmation() async {
        var t = target("SKLEP-PROD")
        var asked = 0
        #expect(await ProductionConfirmation.confirm(t, operation: "deploy") { _ in asked += 1; return nil })
        #expect(asked == 0)
        t.environment = .prod
        #expect(await ProductionConfirmation.confirm(t, operation: "deploy") { _ in " SKLEP-PROD " })
        #expect(await !ProductionConfirmation.confirm(t, operation: "deploy") { _ in "sklep-prod" })
        #expect(await !ProductionConfirmation.confirm(t, operation: "deploy") { _ in nil })
    }

    @Test("Komendy celów SSH w rejestrze: poziom agenta Brak")
    func commands() {
        let ws = Workspace()
        for id in ["ssh.manager", "ssh.test", "ssh.export", "ssh.import"] {
            let c = ws.registry.command(CommandID(rawValue: id))
            #expect(c?.descriptor.agentAccess == AgentAccess.none, "\(id)")
        }
    }
}

@Suite("Parsery błędów Pro*C i XL C")
struct BuildMessageParserTests {
    @Test("Pro*C: PCC-S/W/F i PLS z plikiem .pc, linią i kolumną; komunikat bez lokalizacji")
    func proc() {
        let m = BuildMessageParser.parse(BuildFixtures.procAndXlc).filter { $0.tool == .proc }
        #expect(m.count == 5)
        #expect(m[0].file == "orders.pc" && m[0].line == 45 && m[0].column == 12 && m[0].severity == .severe && m[0].code == "PCC-S-02322")
        #expect(m[0].text == "found undefined identifier")
        #expect(m[1].line == 51 && m[1].column == 5 && m[1].code == "PCC-S-02201" && m[1].text.hasPrefix("Encountered the symbol \"COMIT\""))
        #expect(m[2].file == "lib/util.pc" && m[2].line == 60 && m[2].code == "PLS-S-00201")
        #expect(m[3].severity == .warning && m[3].file == nil && !m[3].isError)
        #expect(m[4].severity == .unrecoverable && m[4].isError)
    }

    @Test("XL C: \"plik\", line L.C: 1506-NNN (S) — ważności I/W/E/S/U, kolumna opcjonalna, numery czterocyfrowe")
    func xlc() {
        let m = BuildMessageParser.parse(BuildFixtures.procAndXlc).filter { $0.tool == .xlc }
        #expect(m.map(\.severity) == [.severe, .severe, .warning, .info, .error, .unrecoverable])
        #expect(m[0].file == "orders.c" && m[0].line == 120 && m[0].column == 15 && m[0].code == "1506-045" && m[0].text == "Undeclared identifier v_cnt.")
        #expect(m[2].file == "/build/app/src/lib/util.c" && m[2].code == "1506-1385")
        #expect(m[3].line == 200 && m[3].column == nil)
    }

    @Test("XL C z -qsrcmsg: plik z polecenia kompilacji, linia ze źródła, kolumna ze znacznika")
    func srcmsg() {
        let m = BuildMessageParser.parse(BuildFixtures.srcmsg)
        #expect(m.count == 3)
        #expect(m[0].file == "report.c" && m[0].line == 120 && m[0].column == 15 && m[0].text == "Undeclared identifier v_cnt.")
        #expect(m[1].line == 120 && m[1].column == 27 && m[1].text.hasSuffix("bad."))
        #expect(m[2].line == 7 && m[2].column == 10 && m[2].code == "1506-296")
        // Opcje między -c a plikiem; znacznik bez kropek (błąd w kolumnie 1).
        let o = BuildMessageParser.parse("xlc -c -q64 -O2 src/orders.c -o orders.o\n   12 | x = 1;\n        a\na - 1506-045 (S) Undeclared identifier x.")
        #expect(o.count == 1 && o[0].file == "src/orders.c" && o[0].line == 12 && o[0].column == 1)
    }

    @Test("Ścieżka serwera → ścieżka względna projektu (względna wobec katalogu make, bezwzględna, poza repozytorium)")
    func mapping() {
        #expect(BuildMessageParser.projectRelativePath("orders.c", makeDirectory: "/build/app/src", remoteRoot: "/build/app/src") == "orders.c")
        #expect(BuildMessageParser.projectRelativePath("../lib/./util.pc", makeDirectory: "/build/app/src/make", remoteRoot: "/build/app/src/")
                == "lib/util.pc")
        #expect(BuildMessageParser.projectRelativePath("/build/app/src/lib/util.c", makeDirectory: "/x", remoteRoot: "/build/app/src") == "lib/util.c")
        #expect(BuildMessageParser.projectRelativePath("/opt/oracle/precomp/public/sqlca.h", makeDirectory: "/build/app/src",
                                                       remoteRoot: "/build/app/src") == nil)
        #expect(BuildMessageParser.projectRelativePath("/build/app/srcx/a.c", makeDirectory: "/", remoteRoot: "/build/app/src") == nil)
    }
}

#if canImport(Darwin)
@Suite("Testuj cel SSH na lokalnym sshd", .serialized, .enabled(if: sshdAvailable), .timeLimit(.minutes(2)))
struct SSHTargetTesterTests {
    @Test("Testuj: logowanie, wersja serwera, git w working copy (gałąź, czystość), katalogi i utworzenie katalogu backupów")
    func testTarget() throws {
        let sshd = try TestSSHD()
        let base = sshd.root.path + "/app base"
        try sshd.root.file("app base/bin/.keep", "")
        var t = PelikanSSHTarget(name: "lokalny", host: "127.0.0.1", user: NSUserName(), baseDirectory: base, backupDirectory: sshd.root.path + "/kopie")
        t.port = sshd.port
        t.keyFile = sshd.clientKey
        t.legacyAlgorithms = true
        let run = try SocketDirectory.make(preferred: URL(fileURLWithPath: "/tmp/plk-\(UUID().uuidString.prefix(6))"))
        let session = try SSHSession(config: SSHTargetTester.sessionConfig(t, configFile: sshd.clientConfig, knownHostsFile: sshd.knownHosts),
                                     runDirectory: run, secret: { TestSSHD.passphrase })
        defer { session.disconnect(); try? FileManager.default.removeItem(at: run) }
        #expect(SSHTargetTester.serverBanner(host: "127.0.0.1", port: sshd.port)?.hasPrefix("SSH-2.0-") == true)

        // Working copy przez tę samą sesję (git lokalnego „serwera”), bez podpisów i hooków użytkownika.
        try session.recordHostKey()
        let q = SSHSession.shellQuote
        let setup = try session.run("mkdir -p \(q(t.sourceDirectory)) && cd \(q(t.sourceDirectory)) && git init -q && git checkout -q -b MASTER && "
                                    + "git -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -q --no-verify --allow-empty -m init")
        #expect(setup.status == 0, "\(setup.errorText)")

        var checks = SSHTargetTester.run(t, session: session)
        func check(_ title: String) -> SSHTestCheck? { checks.first { $0.title == title } }
        #expect(check("Serwer SSH")?.status == .ok && check("Logowanie")?.status == .ok)
        #expect(check("uname -a")?.status == .ok && check("git --version")?.detail.hasPrefix("git version") == true)
        #expect(check("Gałąź")?.status == .ok && check("Gałąź")?.detail == "MASTER")
        #expect(check("Czystość working copy")?.status == .ok)
        #expect(check("Katalog bazowy")?.status == .ok && check("Katalog src")?.status == .ok && check("Katalog bin")?.status == .ok)
        #expect(check("Katalog backupów")?.status == .failed)

        try SSHTargetTester.createBackupDirectory(t, session: session)
        try sshd.root.file("app base/src/nowy.pc", "x")
        t.branch = "master"
        checks = SSHTargetTester.run(t, session: session)
        #expect(check("Katalog backupów")?.status == .ok)
        #expect(check("Czystość working copy")?.status == .warning && check("Czystość working copy")?.detail.contains("nowy.pc") == true)
        #expect(check("Gałąź")?.status == .warning)
        #expect(sshd.root.exists("kopie/.pelikan"))
    }

    @Test("Testuj: błąd logowania (brak wspólnych algorytmów) przerywa i podaje przyczynę")
    func negotiationFailure() throws {
        let sshd = try TestSSHD()
        var t = PelikanSSHTarget(name: "x", host: "127.0.0.1", user: NSUserName(), baseDirectory: "/x", backupDirectory: "/y")
        t.port = sshd.port
        t.keyFile = sshd.clientKey
        let run = try SocketDirectory.make(preferred: URL(fileURLWithPath: "/tmp/plk-\(UUID().uuidString.prefix(6))"))
        defer { try? FileManager.default.removeItem(at: run) }
        let session = try SSHSession(config: SSHTargetTester.sessionConfig(t, configFile: sshd.clientConfig, knownHostsFile: sshd.knownHosts),
                                     runDirectory: run, secret: { TestSSHD.passphrase })
        let checks = SSHTargetTester.run(t, session: session)
        #expect(checks.last?.title == "Logowanie" && checks.last?.status == .failed)
        #expect(checks.last?.detail.contains("Stare algorytmy") == true)
    }
}
#endif
