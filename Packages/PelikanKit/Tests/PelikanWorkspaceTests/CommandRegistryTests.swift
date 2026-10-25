import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

@MainActor
@Suite("Rejestr komend i model")
struct CommandRegistryTests {
    @Test("Identyfikatory komend są unikalne")
    func uniqueIDs() {
        let ids = BuiltinCommands.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Brak konfliktów skrótów w obu profilach")
    func noShortcutConflicts() {
        let d = BuiltinCommands.all.map(\.descriptor)
        for profile in ShortcutProfile.allCases {
            let c = Keymap.conflicts(in: d, profile: profile)
            #expect(c.isEmpty, "\(profile): \(c)")
        }
    }

    @Test("Skróty potwierdzone we wzorcu: F8 wykonuje, Ctrl+F8 odwrotnie, F5 Explain Plan, Ctrl+E historia")
    func plsqlDeveloperProfile() {
        let ws = Workspace(profile: .plsqlDeveloper)
        #expect(ws.keymap.command(for: KeyChord(string: "f8")!) == "sql.execute")
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+f8")!) == "sql.executeAlternate")
        #expect(ws.keymap.command(for: KeyChord(string: "f5")!) == "tools.explainPlan")
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+e")!) == "edit.recallStatement")
    }

    @Test("Profil macOS: Cmd+Enter wykonuje, F-klawisze wzorca nadal działają")
    func macProfile() {
        let ws = Workspace(profile: .macOS)
        #expect(ws.keymap.command(for: KeyChord(string: "cmd+enter")!) == "sql.execute")
        #expect(ws.keymap.command(for: KeyChord(string: "f8")!) == "sql.execute")
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+e")!) == nil)
    }

    @Test("Nadpisanie skrótu przez użytkownika")
    func overrides() {
        let ws = Workspace(profile: .plsqlDeveloper)
        ws.keyOverrides = ["ctrl+enter": "sql.executeAlternate", "f8": ""]
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+enter")!) == "sql.executeAlternate")
        #expect(ws.keymap.command(for: KeyChord(string: "f8")!) == nil)
    }

    @Test("Nowe okna, numeracja, aktywacja, zamykanie i przełączanie")
    func documents() async throws {
        let ws = Workspace()
        try await ws.invoke("file.new.sql")
        try await ws.invoke("file.new.sql")
        try await ws.invoke("file.new.program")
        #expect(ws.documents.map(\.fullTitle) == ["Okno SQL – Nowe", "Okno SQL – Nowe 2", "Okno programu – Nowe"])
        #expect(ws.activeDocument?.kind == .program)
        ws.cycleDocuments(forward: true)
        #expect(ws.activeDocument?.ordinal == 1 && ws.activeDocument?.kind == .sql)
        try await ws.invoke("file.close")
        #expect(ws.documents.count == 2)
        #expect(ws.activeDocument?.fullTitle == "Okno SQL – Nowe 2")
    }

    @Test("Komenda niedostępna w bieżącym stanie (Scheduler bez połączenia) jest wyłączona i zwraca czytelny błąd")
    func unavailableWithoutConnection() async {
        let ws = Workspace()
        #expect(!ws.isEnabled("tools.scheduler"))
        await #expect(throws: CommandError.self) { try await ws.invoke("tools.scheduler") }
    }

    @Test("Komenda wyłączona w bieżącym stanie (COMMIT bez transakcji) nie wykonuje się — także dla agenta")
    func disabledCommand() async {
        let ws = Workspace()
        _ = ws.newDocument(.sql)
        #expect(!ws.isEnabled("session.commit"))
        await #expect(throws: CommandError.self) { try await ws.invoke("session.commit", invoker: .agent(sessionID: "t", agentName: "test")) }
    }

    @Test("Każda komenda wskazuje istniejący wiersz macierzy funkcji")
    func featureIDsExist() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/FEATURES.md").standardizedFileURL
        let text = try String(contentsOf: url, encoding: .utf8)
        for c in BuiltinCommands.all {
            guard let f = c.descriptor.feature else { continue }
            #expect(text.contains("| \(f) |"), "\(c.id) → \(f)")
        }
    }
}

@MainActor
@Suite("Własne skróty klawiszowe")
struct KeyboardCustomizationTests {
    @Test("Przypisanie skrótu przejmuje go od innej komendy; usunięcie domyślnego; przywrócenie domyślnych")
    func customize() {
        let ws = Workspace(profile: .plsqlDeveloper)
        let f9 = KeyChord(string: "f9")!
        let f8 = KeyChord(string: "f8")!
        #expect(ws.keymap.command(for: f8) == "sql.execute")
        ws.assignShortcut(f9, to: "sql.execute")
        #expect(ws.keymap.command(for: f9) == "sql.execute")
        #expect(ws.keymap.chords(for: "sql.execute").contains(f8))     // domyślny zostaje, dopóki go nie usunąć
        ws.removeShortcut(f8)
        #expect(ws.keymap.command(for: f8) == nil)
        #expect(ws.conflictingCommand(for: KeyChord(string: "f10")!, assigning: "sql.execute") == "session.commit")
        ws.resetShortcuts(for: "sql.execute")
        #expect(ws.keymap.command(for: f8) == "sql.execute")
        #expect(ws.keymap.command(for: f9) == ws.defaultCommand(for: f9))    // F9 wraca do domyślnej komendy profilu
        ws.assignShortcut(f9, to: "session.commit")
        ws.resetShortcuts()
        #expect(ws.settings.keyOverrides.isEmpty)
    }

    @Test("Zmiana profilu skrótów przebudowuje mapę klawiszy")
    func profile() {
        let ws = Workspace(profile: .plsqlDeveloper)
        #expect(ws.keymap.command(for: KeyChord(string: "ctrl+f8")!) == "sql.executeAlternate")
        ws.settings.shortcutProfile = .macOS
        #expect(ws.keymap.command(for: KeyChord(string: "cmd+shift+enter")!) == "sql.executeAlternate")
    }
}

/// Bramka agenta jak w PelikanAgent: podgląd i przypięcie poleceń przed zgodą; `duringApproval` symuluje działania
/// agenta w czasie, gdy użytkownik czyta okno zgody (MCP obsługuje żądania równolegle).
@MainActor
final class PinningGate: AgentInvocationGate {
    var duringApproval: (@MainActor () -> Void)?
    var previews: [EffectPreview] = []
    func authorize(_ command: Command, context: CommandContext) async throws -> CommandArguments {
        guard command.descriptor.agentAccess == .approval else { return context.arguments }
        let (preview, pinned) = try await context.workspace.agentApprovalPreview(command.id, context.arguments, invoker: context.invoker)
        previews.append(preview)
        duringApproval?()
        return pinned
    }
}

/// Atrapa sesji z jednym zapytaniem (`select x …`): kursor ma 3 wiersze, a pobranie 0 wierszy daje pustą porcję
/// z hasMore (jak ODPI); po 50 pobraniach błąd zamiast zawieszenia testu.
final class AgentQuerySession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    let state = Mutex((fetches: 0, left: 3))
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        guard sql.lowercased().hasPrefix("select x") else { return ExecutionResult(kind: .other) }
        return ExecutionResult(kind: .query, resultSet: ResultSetDescriptor(id: ResultSetID(1), columns: [ColumnInfo(name: "X", type: .number, typeName: "NUMBER")]))
    }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch {
        try state.withLock { s in
            s.fetches += 1
            if s.fetches > 50 { throw CommandError.notAvailable("pętla pobierania") }
            let n = min(maxRows, s.left)
            s.left -= n
            return RowBatch(rows: Array(repeating: [.text("1")], count: n), hasMore: s.left > 0)
        }
    }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
}

final class AgentQueryDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession { AgentQuerySession() }
}

@MainActor
final class CallLog {
    var items: [String] = []
}

@MainActor
@Suite("Agent: zgoda na wykonywane polecenia i komendy edycji (D163)")
struct AgentGateTests {
    let agent = Invoker.agent(sessionID: "g1", agentName: "test")

    func workspace(_ driver: any DatabaseDriver = FakeDriver()) throws -> (Workspace, PinningGate) {
        let ws = Workspace(drivers: [.instantClient: driver])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        ws.sessions.setMainConnection(def.id)
        let gate = PinningGate()
        ws.agentGate = gate
        return (ws, gate)
    }

    @Test("agent.compile wykonuje polecenia z podglądu: zmiana tekstu okna i aktywnego okna w trakcie zgody nic nie zmienia")
    func compileRunsApprovedStatements() async throws {
        let driver = FakeDriver()
        let (ws, gate) = try workspace(driver)
        let doc = ws.newDocument(.program, text: "create or replace procedure pelikan_ok is begin null; end;\n/\n")
        gate.duringApproval = {
            // replace_range agenta (poziom Pełny, bez zgody) i navigate_to/window.next na inne okno.
            doc.text = "create or replace trigger pelikan_evil before logon on database begin null; end;\n/\n"
            _ = ws.newDocument(.program, text: "create or replace procedure pelikan_other is begin null; end;\n/\n")
        }
        _ = try await ws.invoke("agent.compile", invoker: agent)
        let shown = try #require(gate.previews.first).statements
        #expect(shown.count == 1 && shown[0].contains("pelikan_ok"))
        let executed = driver.sessions.withLock { $0.flatMap { $0.executed.withLock { $0 } } }
        #expect(executed.contains { $0.contains("pelikan_ok") })
        #expect(!executed.contains { $0.contains("pelikan_evil") || $0.contains("pelikan_other") })
    }

    @Test("Komendy edycji przez agenta: okno poleceń odrzucone, okno tylko do odczytu odrzucone, zmiana do cofnięcia sesji agenta")
    func agentEditCommands() async throws {
        let (ws, gate) = try workspace()
        defer { withExtendedLifetime(gate) {} }                 // bramka w Workspace jest słaba
        let command = ws.newDocument(.command, text: "connect u/secret@db")
        command.selectedRange = 0..<(command.text as NSString).length
        await #expect(throws: AgentDenial.self) { try await ws.invoke("edit.uppercase", invoker: agent) }
        await #expect(throws: AgentDenial.self) { try await ws.invoke("edit.beautify", invoker: agent) }
        #expect(command.text == "connect u/secret@db")
        let sql = ws.newDocument(.sql, text: "select 1 from dual")
        sql.selectedRange = 0..<(sql.text as NSString).length
        _ = try await ws.invoke("edit.uppercase", invoker: agent)
        #expect(sql.text == "SELECT 1 FROM DUAL")
        #expect(ws.undoAgentEdits(session: "g1").undone == 1 && sql.text == "select 1 from dual")
        sql.isReadOnly = true
        for id: CommandID in ["edit.uppercase", "edit.beautify"] {
            await #expect(throws: CommandError.self) { try await ws.invoke(id, invoker: agent) }
            await #expect(throws: CommandError.self) { try await ws.invoke(id) }
        }
        sql.statementHistory = ["select 2 from dual"]
        await #expect(throws: CommandError.self) { try await ws.invoke("sql.historyBack") }
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.todoInsert") }
        #expect(throws: CommandError.self) { try Stage7Commands.insert("x", into: sql) }
        #expect(throws: CommandError.self) { try ws.insertInEditor("x") }
        #expect(sql.text == "select 1 from dual")
    }

    @Test("Stan menu sprawdzany mimo kluczy wewnętrznych (run_command); agent bez numeru linii nie dostaje okna dialogowego")
    func validationAndGotoLine() async throws {
        let (ws, gate) = try workspace()
        defer { withExtendedLifetime(gate) {} }                 // bramka w Workspace jest słaba
        await #expect(throws: CommandError.self) {
            try await ws.invoke("edit.uppercase", CommandArguments(["__viaRunCommand": true]), invoker: agent)
        }
        let doc = ws.newDocument(.sql, text: "a\nb\nc")
        await #expect(throws: CommandError.self) { try await ws.invoke("edit.gotoLine", invoker: agent) }
        _ = try await ws.invoke("edit.gotoLine", CommandArguments(["line": 3]), invoker: agent)
        #expect(doc.selectedRange == 4..<4)
    }

    @Test("run_query: ujemny limit wierszy nie zapętla pobierania")
    func negativeMaxRows() async throws {
        let (ws, gate) = try workspace(AgentQueryDriver())
        defer { withExtendedLifetime(gate) {} }
        let r = try await ws.invoke("agent.query", CommandArguments(["sql": "select x from t", "maxRows": -1]), invoker: agent)
        let content = r.value?["content"]
        #expect(content?["rowCount"] == .int(0) && content?["truncated"] == .bool(true))
    }

    @Test("Wywołania na sesji bazy agenta po kolei: drugie czeka na koniec pierwszego, inne sesje bez czekania")
    func agentCallsSerialized() async throws {
        let ws = Workspace()
        let log = CallLog()
        let first = Task {
            try await ws.agentSerialized("s1") {
                log.items.append("a+")
                try await Task.sleep(for: .milliseconds(200))
                log.items.append("a-")
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        try await ws.agentSerialized("s2") { log.items.append("c") }
        try await ws.agentSerialized("s1") { log.items.append("b") }
        try await first.value
        #expect(log.items == ["a+", "c", "a-", "b"] && ws.agentQueue.isEmpty)
    }
}
