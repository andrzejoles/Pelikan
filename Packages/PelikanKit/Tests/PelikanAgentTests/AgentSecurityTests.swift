#if canImport(Darwin)
import Darwin
import Foundation
import PelikanBridgeKit
import PelikanDB
import Testing
@testable import PelikanAgent
@testable import PelikanWorkspace

@MainActor
@Suite("Kanał agentów: bezpieczeństwo (SECURITY §5)", .serialized)
struct AgentSecurityTests {
    @Test("Gniazdo 0600 w katalogu 0700")
    func socketPermissions() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        var st = stat()
        #expect(lstat(env.runDir.path, &st) == 0 && st.st_mode & 0o777 == 0o700)
        #expect(lstat(env.socket.path, &st) == 0 && st.st_mode & 0o777 == 0o600)
        #expect(st.st_mode & S_IFMT == S_IFSOCK)
    }

    @Test("Połączenie bez ramki hello jest zamykane po limicie czasu")
    func connectionWithoutHelloIsDropped() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let fd = try Wire.connect(path: env.socket.path)
        defer { close(fd) }
        let reply = await Task.detached { try? Wire.readFrame(from: fd) }.value
        let decoded = reply.flatMap { try? JSONDecoder().decode(Wire.Reply.self, from: $0) }
        #expect(decoded?.type == "error")
        // Zdarzenie trafia do kontrolera asynchronicznie (zadanie na głównym aktorze) — krótkie oczekiwanie.
        let rejected = { env.controller.connectionEvents.contains { if case .rejected("no_hello", _) = $0 { true } else { false } } }
        for _ in 0..<40 where !rejected() { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(rejected())
    }

    @Test("Brak tokenu, zły token, token zamkniętej sesji — odrzucone")
    func tokens() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let (session, token) = env.session()

        let noToken = try BridgeClient(socket: env.socket, token: nil)
        #expect(await noToken.waitForExit() == 1)

        let wrong = try BridgeClient(socket: env.socket, token: SessionRegistry.base64url([UInt8](repeating: 7, count: 32)))
        #expect(await wrong.waitForExit() == 1)
        #expect(wrong.stderr.contains("bad_token"))

        env.controller.closeSession(session.id)
        let closed = try BridgeClient(socket: env.socket, token: token)
        #expect(await closed.waitForExit() == 1)
    }

    @Test("Proces spoza drzewa procesów CLI sesji — odrzucony")
    func processOutsideAgentTreeIsRejected() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let stranger = Process()
        stranger.executableURL = URL(fileURLWithPath: "/bin/sleep")
        stranger.arguments = ["10"]
        try stranger.run()
        defer { stranger.terminate() }
        let (_, token) = env.session(cliPID: stranger.processIdentifier)
        let client = try BridgeClient(socket: env.socket, token: token)
        #expect(await client.waitForExit() == 1)
        #expect(client.stderr.contains("not_descendant"))
    }

    @Test("Narzędzia: Brak niewidoczne; komendy bazy, Command Window i plików niedostępne przez run_command")
    func toolsWithLevelNoneAreHidden() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let (_, token) = env.session()
        let client = try BridgeClient(socket: env.socket, token: token)
        defer { client.terminate() }
        try await client.initialize()
        let tools = try await client.tools()
        let names = tools.compactMap { $0["name"] as? String }
        for t in ["list_connections", "get_state", "get_editor", "open_editor", "insert_text", "replace_range", "navigate_to", "format_code", "run_command",
                  "run_query", "get_source", "execute_statement", "commit", "rollback", "compile", "run_tests", "session_list"] {
            #expect(names.contains(t), "\(t)")
        }
        let runCommand = tools.first { $0["name"] as? String == "run_command" }?["description"] as? String ?? ""
        for hidden in ["sql.execute ", "session.commit ", "session.rollback ", "file.new.command ", "file.save ", "conn.edit ", "utplsql.install ",
                       "ob.drop ", "ob.test ", "utplsql.cliScript ", "edit.gotoDeclaration ", "file.close "] {
            #expect(!runCommand.contains(hidden), "\(hidden)")
        }
        // Okno SQL — stan menu pozwala, odmawia bramka.
        _ = env.workspace.newDocument(.sql, text: "select 1 from dual")
        let (text, isError) = try await client.call("run_command", ["command": "sql.execute"])
        #expect(isError && text.contains("permission_denied"))
    }

    @Test("Połączenia tylko pod aliasem i środowiskiem — bez hasła, hosta, portu, usługi i użytkownika")
    func connectionsByAliasOnly() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let dev = ConnectionDefinition(name: "Rozwój", target: ConnectionTarget(user: "SCOTT_DEV", connectString: "db-host.example:1599/SVC_DEV"))
        let prod = ConnectionDefinition(name: "Produkcja", target: ConnectionTarget(user: "APP_PROD", connectString: "prod.example:1521/SVC_PROD"), environment: .production)
        var hidden = ConnectionDefinition(name: "Ukryte", target: ConnectionTarget(user: "HIDDEN_USER", connectString: "h.example:1521/H"))
        hidden.agent.visibleToAgent = false
        // Hasła losowe (żadne nie trafia do repozytorium); odpowiedź agenta nie może zawierać żadnego z nich.
        let secrets = (0..<3).map { _ in UUID().uuidString }
        for (def, secret) in zip([dev, prod, hidden], secrets) { try env.workspace.connections.upsert(def, password: secret) }
        let (_, token) = env.session()
        let client = try BridgeClient(socket: env.socket, token: token)
        defer { client.terminate() }
        try await client.initialize()
        let (text, isError) = try await client.call("list_connections")
        #expect(!isError && text.contains("Rozwój") && text.contains("Produkcja") && text.contains("production"))
        for secret in ["SCOTT_DEV", "APP_PROD", "db-host", "1599", "SVC_DEV", "prod.example", "Ukryte", "HIDDEN_USER", NSUserName()] + secrets {
            #expect(!text.contains(secret), "\(secret)")
        }
        let list = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] ?? []
        #expect(list.first { $0["alias"] as? String == "Produkcja" }?["changesAllowed"] as? Bool == false)
    }

    @Test("Edytor: odczyt jako untrusted_content, zmiany pełne bez pytania i cofnięcie sesji")
    func editorToolsAndUndo() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let doc = env.workspace.newDocument(.sql, text: "select 1\nfrom dual;\n")
        let (session, token) = env.session()
        let client = try BridgeClient(socket: env.socket, token: token)
        defer { client.terminate() }
        try await client.initialize()
        let (editor, _) = try await client.call("get_editor")
        #expect(editor.contains("untrusted_content") && editor.contains("from dual"))
        #expect(try await client.call("replace_range", ["fromLine": 1, "toLine": 1, "text": "select 2"]).1 == false)
        #expect(try await client.call("insert_text", ["line": 3, "text": "-- koniec\n"]).1 == false)
        #expect(doc.text == "select 2\nfrom dual;\n-- koniec\n")
        let (opened, _) = try await client.call("open_editor", ["kind": "program", "text": "create package p as end;"])
        #expect(opened.contains("window") && env.workspace.documents.count == 2)
        #expect(env.approver.requests.isEmpty)
        let r = env.workspace.undoAgentEdits(session: session.id)
        #expect(r.undone == 3 && r.conflicts.isEmpty)
        #expect(doc.text == "select 1\nfrom dual;\n" && env.workspace.documents.count == 1)
    }

    @Test("Komenda zmieniająca edytor przez run_command wymaga zgody; odrzucenie nic nie zmienia")
    func approvalViaRunCommand() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let doc = env.workspace.newDocument(.sql, text: "SELECT 1 FROM dual")
        let (_, token) = env.session()
        let client = try BridgeClient(socket: env.socket, token: token)
        defer { client.terminate() }
        try await client.initialize()
        env.approver.answer = false
        let (denied, deniedError) = try await client.call("run_command", ["command": "edit.lowercase"])
        #expect(deniedError && denied.contains("rejected_by_user") && doc.text == "SELECT 1 FROM dual")
        #expect(env.approver.requests.count == 1 && env.approver.requests[0].command == "edit.lowercase")
        env.approver.answer = true
        doc.selectedRange = 0..<(doc.text as NSString).length
        let (_, okError) = try await client.call("run_command", ["command": "edit.lowercase"])
        #expect(!okError && doc.text == "select 1 from dual")
    }

    @Test("Połączenie produkcyjne: zmiany odrzucone przed dotknięciem bazy, odczyt widoczny; Brak dla niewidocznego")
    func productionIsReadOnly() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let prod = ConnectionDefinition(name: "Produkcja", target: ConnectionTarget(user: "U", connectString: "127.0.0.1:9/X"), environment: .production)
        try env.workspace.connections.upsert(prod, password: UUID().uuidString)
        let (_, token) = env.session()
        let client = try BridgeClient(socket: env.socket, token: token)
        defer { client.terminate() }
        try await client.initialize()
        for (tool, args) in [("execute_statement", ["sql": "delete from emp"]), ("commit", [:]), ("compile", ["object": "p"]), ("install_utplsql", [:])] as [(String, [String: Any])] {
            var a = args
            a["connection"] = "Produkcja"
            let (text, isError) = try await client.call(tool, a)
            #expect(isError && text.contains("permission_denied") && text.contains("production"), "\(tool): \(text)")
        }
        #expect(env.approver.requests.isEmpty)
        let (unknown, unknownError) = try await client.call("run_query", ["connection": "Nieznane", "sql": "select 1 from dual"])
        #expect(unknownError && unknown.contains("Nieznane"))
    }

    @Test("Limit wywołań na minutę")
    func rateLimit() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        env.workspace.settings.agent.callsPerMinute = 3
        let (_, token) = env.session()
        let client = try BridgeClient(socket: env.socket, token: token)
        defer { client.terminate() }
        try await client.initialize()
        for _ in 0..<3 { #expect(try await client.call("get_state").1 == false) }
        let (text, isError) = try await client.call("get_state")
        #expect(isError && text.contains("rate_limited"))
    }

    @Test("Dziennik JSONL bez tokenu")
    func logWithoutToken() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let (_, token) = env.session()
        let client = try BridgeClient(socket: env.socket, token: token)
        defer { client.terminate() }
        try await client.initialize()
        _ = try await client.call("get_state")
        env.controller.log.flush()
        let files = try FileManager.default.contentsOfDirectory(at: env.logDir, includingPropertiesForKeys: nil)
        let all = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(all.contains("get_state") && all.contains("connection_accepted"))
        #expect(!all.contains(token))
    }

    @Test("Agent bez bramki (serwer wyłączony) nie wykona komendy")
    func noGateNoInvocation() async {
        let ws = Workspace()
        _ = ws.newDocument(.sql, text: "x")
        await #expect(throws: AgentDenial.self) { try await ws.invoke("agent.state", invoker: .agent(sessionID: "x", agentName: "t")) }
    }
}

@MainActor
@Suite("Kanał agentów: jednostki")
struct AgentUnitTests {
    @Test("run_command: argumenty spoza schematu usuwane, stan menu sprawdzany, historia okna niedostępna; hasła poza panelem i dziennikiem")
    func argumentsFilteredAndRedacted() async throws {
        let ws = Workspace()
        let dir = URL(fileURLWithPath: "/tmp/pat-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = AgentController(workspace: ws, socketURL: dir.appendingPathComponent("a.sock"), logDirectory: dir.appendingPathComponent("logs"))
        let approver = MockApprover()
        controller.approvals = approver
        let (session, _) = controller.createSession(profile: AgentProfile.builtIn[0], directory: dir.path)
        let noWindow = await controller.callTool("run_command", arguments: ["command": "edit.lowercase"], sessionID: session.id)
        #expect(noWindow.isError == true && approver.requests.isEmpty)
        let doc = ws.newDocument(.sql, text: "SELECT 1")
        doc.selectedRange = 0..<8
        let r = await controller.callTool("run_command", arguments: ["command": "edit.lowercase", "arguments": ["extra": "x"]], sessionID: session.id)
        #expect(r.isError == false && doc.text == "select 1")
        #expect(approver.requests.count == 1 && approver.requests[0].arguments["extra"] == nil)
        doc.statementHistory = ["alter user u identified by x"]
        let history = await controller.callTool("run_command", arguments: ["command": "sql.historyBack"], sessionID: session.id)
        #expect(history.isError == true && doc.text == "select 1")
        let s = AgentController.summarize(CommandArguments(["sql": "create user x identified by Tajne1", "list": ["alter user y identified by Tajne2"], "n": 1]))
        #expect(!s.contains("Tajne") && s.contains("identified by ********") && s.contains("\"n\""))
        // Samo słowo PASSWORD (kolumna, parametr) nie ukrywa całego tekstu — dziennik zachowuje ślad.
        let plain = AgentController.summarize(CommandArguments(["sql": "select password_versions from dba_users"]))
        #expect(plain.contains("password_versions"))
    }

    @Test("R7-01: połączenie tymczasowe Okna poleceń (CONNECT … AS SYSDBA) poza zasięgiem agenta, bez aliasu w get_state")
    func temporaryConnectionHidden() async throws {
        let ws = Workspace()
        let dir = URL(fileURLWithPath: "/tmp/pat-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = AgentController(workspace: ws, socketURL: dir.appendingPathComponent("a.sock"), logDirectory: dir.appendingPathComponent("logs"))
        controller.approvals = MockApprover()
        let (session, _) = controller.createSession(profile: AgentProfile.builtIn[0], directory: dir.path)
        var target = ConnectionTarget(user: "sys", connectString: "//prod-host.example:1521/svc")
        target.role = .sysdba
        let temp = ConnectionDefinition(name: "sys@//prod-host.example:1521/svc", target: target, savePassword: false)
        ws.connections.registerTemporary(temp, password: UUID().uuidString)
        let cmd = ws.newDocument(.command, text: "")
        cmd.connectionID = temp.id
        ws.activate(cmd.id)
        // Bez połączenia głównego: odmowa; jawne wskazanie przypiętym kluczem też nie przejdzie.
        #expect(throws: CommandError.self) { try ws.agentConnection(alias: nil) }
        #expect(throws: CommandError.self) { try ws.agentConnection(CommandArguments([Workspace.agentConnectionKey: .string(temp.id.uuidString)])) }
        let query = await controller.callTool("run_query", arguments: ["sql": "select 1 from dual"], sessionID: session.id)
        #expect(query.isError == true)
        let state = await controller.callTool("get_state", arguments: [:], sessionID: session.id)
        let text = state.content.map { "\($0)" }.joined()
        #expect(!text.contains("prod-host") && !text.contains("sys@"))
        // Z połączeniem głównym z listy: agent dostaje główne, nie połączenie okna poleceń.
        let dev = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: "u", connectString: "localhost:1521/x"))
        try ws.connections.upsert(dev)
        ws.sessions.setMainConnection(dev.id)
        #expect(try ws.agentConnection(alias: nil).id == dev.id)
    }

    @Test("R7-07: historia kodu rozpoznaje modyfikatory w dowolnej kolejności (DDL z DBMS_METADATA)")
    func codeTargetModifiers() {
        let cases: [(String, DBObjectType, String, Bool)] = [
            ("\n  CREATE OR REPLACE FORCE EDITIONABLE VIEW \"SCOTT\".\"EMP_V\" (\"A\") AS select 1 a from dual", .view, "SCOTT.EMP_V", false),
            ("create or replace editionable force view v as select 1 x from dual", .view, "S.V", false),
            ("create or replace noneditionable no force view v2 as select 1 x from dual", .view, "S.V2", false),
            ("create editioning view ev as select a from t", .view, "S.EV", false),
            ("CREATE OR REPLACE EDITIONABLE PACKAGE BODY \"SCOTT\".\"P\" AS end;", .packageBody, "SCOTT.P", false),
            ("drop view v", .view, "S.V", true),
        ]
        for (sql, type, name, drop) in cases {
            let t = AgentChanges.codeTarget(sql, defaultOwner: "S")
            #expect(t?.object.type == type && "\(t?.object.owner ?? "").\(t?.object.name ?? "")" == name && t?.drop == drop, "\(sql)")
        }
        #expect(AgentChanges.codeTarget("create table t (a number)", defaultOwner: "S") == nil)
    }

    @Test("R7-14: pokrycie dla agenta jako untrusted_content, filtr pełnym członem nazwy")
    func coverageUntrustedAndFilter() async throws {
        #expect(AgentDatabaseCommands.coverageKey("PACKAGE BODY S.EMP", matches: "EMP"))
        #expect(AgentDatabaseCommands.coverageKey("PACKAGE BODY S.EMP", matches: "S.EMP"))
        #expect(!AgentDatabaseCommands.coverageKey("PACKAGE BODY S.XEMP", matches: "EMP"))
        #expect(!AgentDatabaseCommands.coverageKey("PACKAGE BODY T.EMP", matches: "S.EMP"))
        #expect(!AgentDatabaseCommands.coverageKey("PACKAGE BODY S.EMP_API", matches: "EMP"))
        let ws = Workspace()
        let dir = URL(fileURLWithPath: "/tmp/pat-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = AgentController(workspace: ws, socketURL: dir.appendingPathComponent("a.sock"), logDirectory: dir.appendingPathComponent("logs"))
        let (session, _) = controller.createSession(profile: AgentProfile.builtIn[0], directory: dir.path)
        let run = UtplsqlRun(paths: ["S"])
        run.coverage = ["PACKAGE BODY S.EMP": CoverageLines(covered: [1], uncovered: [2]), "PACKAGE BODY S.XEMP": CoverageLines(covered: [1], uncovered: [])]
        ws.lastUtplsqlRun = run
        let r = await controller.callTool("get_coverage", arguments: ["object": "emp"], sessionID: session.id)
        let text = r.content.map { "\($0)" }.joined()
        #expect(r.isError == false && text.contains("untrusted_content") && text.contains("S.EMP") && !text.contains("XEMP"))
    }

    @Test("Porównanie stałoczasowe, base64url, tokeny 256 bit i unikalne")
    func tokens() {
        let a: [UInt8] = Array(0..<32)
        #expect(SessionRegistry.constantTimeEqual(a, a))
        #expect(!SessionRegistry.constantTimeEqual(a, Array(a.reversed())))
        #expect(!SessionRegistry.constantTimeEqual(a, Array(a.prefix(31))))
        #expect(SessionRegistry.decodeBase64url(SessionRegistry.base64url(a)) == a)
        let r = SessionRegistry()
        let (_, t1) = r.create(profile: AgentProfile.builtIn[1], directory: "/")
        let (_, t2) = r.create(profile: AgentProfile.builtIn[1], directory: "/")
        #expect(t1 != t2 && SessionRegistry.decodeBase64url(t1)?.count == 32)
        #expect(r.authenticate(token: t1) != nil && r.authenticate(token: "x") == nil)
    }

    @Test("AI-SEC-011: Command Window, HOST, debuger, AWR/ASH/ADDM, SQL Monitor, Tuning Advisor, Kill i SQL Trace — niedostępne dla agenta")
    func forbiddenAreas() {
        let ws = Workspace()
        let r = SessionRegistry()
        let (s, _) = r.create(profile: AgentProfile.builtIn[0], directory: "/")
        // Nawet nadpisanie w ustawieniach nie podnosi poziomu powyżej Brak.
        var settings = AgentSettings()
        let forbidden = ws.registry.commands.map(\.descriptor).filter { d in
            let id = d.id.rawValue
            return id.hasPrefix("cmd.") || id.hasPrefix("debug.") || id.hasPrefix("sessions.") || id.hasPrefix("proc.") || id.hasPrefix("ssh.")
                || ["tools.awrReport", "tools.ashReport", "tools.addmReport", "tools.sqlMonitor", "tools.sqlMonitorReport",
                    "tools.sqlTuningAdvisor", "session.kill", "session.sqlTrace", "tools.userTools"].contains(id)
        }
        #expect(forbidden.count > 20)
        for d in forbidden {
            settings.accessOverrides[d.id.rawValue] = .full
            #expect(AgentPolicy.effectiveAccess(command: d, session: s, settings: settings) == .none, "\(d.id.rawValue)")
            #expect(AgentPolicy.effectiveAccess(command: d, session: s, settings: settings, viaRunCommand: true) == .none, "\(d.id.rawValue)")
        }
        // Narzędzia agenta nie dają powłoki, terminala ani poleceń systemu.
        let agentTools = ws.registry.commands.map(\.descriptor.id.rawValue).filter { $0.hasPrefix("agent.") }
        #expect(!agentTools.contains { $0.localizedCaseInsensitiveContains("host") || $0.localizedCaseInsensitiveContains("shell")
                                       || $0.localizedCaseInsensitiveContains("terminal") || $0.localizedCaseInsensitiveContains("debug") })
    }

    @Test("Najmniejszy poziom: komendy bazy spoza agent.* niedostępne, nadpisania tylko obniżają, prod = Odczyt")
    func leastPrivilege() {
        let ws = Workspace()
        let r = SessionRegistry()
        let (s, _) = r.create(profile: AgentProfile.builtIn[0], directory: "/", accessOverrides: ["agent.insertText": .read])
        var settings = AgentSettings()
        let d = { (id: CommandID) in ws.registry.command(id)!.descriptor }
        #expect(AgentPolicy.effectiveAccess(command: d("sql.execute"), session: s, settings: settings) == .none)
        #expect(AgentPolicy.effectiveAccess(command: d("session.commit"), session: s, settings: settings) == .none)
        #expect(AgentPolicy.effectiveAccess(command: d("agent.insertText"), session: s, settings: settings) == .read)
        #expect(AgentPolicy.effectiveAccess(command: d("agent.format"), session: s, settings: settings) == .full)
        #expect(AgentPolicy.effectiveAccess(command: d("agent.format"), session: s, settings: settings, viaRunCommand: true) == .approval)
        settings.accessOverrides["agent.format"] = .read
        #expect(AgentPolicy.effectiveAccess(command: d("agent.format"), session: s, settings: settings) == .read)
        settings.accessOverrides["agent.state"] = .full
        #expect(AgentPolicy.effectiveAccess(command: d("agent.state"), session: s, settings: settings) == .read)
        let prod = ConnectionDefinition(name: "p", target: ConnectionTarget(user: "u", connectString: "h/s"), environment: .production)
        let dev = ConnectionDefinition(name: "d", target: ConnectionTarget(user: "u", connectString: "h/s"))
        #expect(AgentPolicy.connectionAccess(prod) == .read && AgentPolicy.connectionAccess(dev) == .full)
        #expect(AgentPolicy.decide(level: .read, effect: .modifiesDatabase) != .allow)
        #expect(AgentPolicy.decide(level: .approval, effect: .modifiesDatabase) == .needsApproval)
        #expect(AgentPolicy.decide(level: .read, effect: .none) == .allow)
    }

    @Test("Uruchomienie CLI: token tylko w środowisku, MCP tylko dla sesji, tryb ścisły")
    func launchSpecsKeepTokenOutOfArguments() {
        for p in AgentProfile.builtIn {
            let spec = AgentLauncher.spec(profile: p, bridge: "/App/pelikan-mcp", socket: "/tmp/s.sock", token: "SECRET", directory: "/tmp",
                                          strict: true, sessionDirectory: "/tmp/sess")
            #expect(!spec.shellArguments.joined().contains("SECRET"), "\(p.id)")
            #expect(!spec.files.values.joined().contains("SECRET"), "\(p.id)")
            #expect(spec.environment[Bridge.tokenVariable] == "SECRET")
            #expect(spec.shellArguments.last!.hasPrefix("exec "))
        }
        let claude = AgentLauncher.spec(profile: AgentProfile.builtIn[0], bridge: "/b", socket: "/s", token: "T", directory: "/", strict: true, sessionDirectory: "/x")
        #expect(claude.displayCommand.contains("--strict-mcp-config") && claude.displayCommand.contains("mcp__pelikan__*"))
        let codex = AgentLauncher.spec(profile: AgentProfile.builtIn[1], bridge: "/b", socket: "/s", token: "T", directory: "/", strict: true, sessionDirectory: "/x")
        #expect(codex.displayCommand.contains("read-only"))
        let agy = AgentLauncher.spec(profile: AgentProfile.builtIn[3], bridge: "/b", socket: "/s", token: "T", directory: "/", strict: true, sessionDirectory: "/x")
        #expect(agy.persistentRegistration != nil)
    }

    @Test("Drzewo procesów i środowisko procesu tego samego użytkownika")
    func processTree() {
        #expect(ProcessTree.environmentValue("PATH", of: getpid()) != nil)
        #expect(ProcessTree.ancestry(of: getpid()).count >= 2)
    }
}
#endif
