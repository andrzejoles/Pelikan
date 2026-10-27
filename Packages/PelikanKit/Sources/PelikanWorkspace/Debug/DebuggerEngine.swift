import Foundation
import Observation
import PelikanDB
import PelikanLog
import PelikanSQL

/// Miejsce w programie: jednostka (bez nazwy — blok testu) i linia.
public struct DebugLocation: Sendable, Hashable {
    public var owner: String
    public var name: String
    /// Typ jednostki wg DBMS_DEBUG (LibunitType: 0 kursor/blok, 7 procedura, 8 funkcja, 9 pakiet, 11 ciało pakietu, 12 wyzwalacz).
    public var unitType: Int
    public var line: Int

    public var isTestBlock: Bool { name.isEmpty }

    /// Typ obiektu bazy dla jednostki (do otwarcia źródła i punktów przerwania).
    public var objectType: DBObjectType? {
        switch unitType {
        case 7: .procedure
        case 8: .function
        case 9: .package
        case 11: .packageBody
        case 12: .trigger
        case 13: .type
        case 14: .typeBody
        default: nil
        }
    }

    /// Przestrzeń nazw DBMS_DEBUG dla punktów przerwania.
    var namespace: Int {
        switch unitType {
        case 11, 14: 2      // namespace_pkg_body
        case 12: 3          // namespace_trigger
        case 0: 0           // namespace_cursor
        default: 1          // namespace_pkgspec_or_toplevel
        }
    }
}

/// Zmienna w podglądzie debugera (UG 5.10): wartość albo dzieci (pola rekordu, elementy kolekcji).
public struct DebugVariable: Sendable, Hashable, Identifiable {
    public var name: String
    /// Pełna nazwa dla GET_VALUE (np. `r.sal`, `t(3)`).
    public var path: String
    public var value: String
    public var type: String
    public var children: [DebugVariable]?
    public var id: String { path }
}

/// Punkt przerwania: jednostka (nil — blok testu okna) i linia (1 = pierwsza linia jednostki).
public struct Breakpoint: Sendable, Hashable, Identifiable, Codable {
    public var id = UUID()
    public var owner: String?
    public var unit: String?
    public var type: DBObjectType?
    public var document: UUID?
    public var line: Int
    public var enabled = true
    /// Liczba przejść do zatrzymania (0 — za każdym razem) — liczona po stronie Pelikana.
    public var passCount = 0
    /// Warunek zatrzymania (wyrażenie SQL ze zmiennymi ramki), komunikat do wyjścia (`{zmienna}` — wartość) i tryb
    /// „nie zatrzymuj” (logpoint) — wszystko po stronie Pelikana, DBMS_DEBUG ich nie ma (PD-DBG-007).
    public var condition: String?
    public var message: String?
    public var dontBreak: Bool?

    var hasActions: Bool { !(condition ?? "").isEmpty || !(message ?? "").isEmpty || dontBreak == true }

    public init(owner: String? = nil, unit: String? = nil, type: DBObjectType? = nil, document: UUID? = nil, line: Int) {
        self.owner = owner; self.unit = unit; self.type = type; self.document = document; self.line = line
    }
}

/// Debuger PL/SQL na DBMS_DEBUG (ADR 0006): sesja docelowa okna testu wykonuje blok, sesja nadzorująca steruje krokami.
@MainActor
@Observable
public final class DebuggerEngine {
    public enum State: Sendable, Equatable { case idle, running, paused, finished }
    public enum Step: Sendable { case into, over, out, run, runToException }

    public private(set) var state: State = .idle
    public private(set) var location: DebugLocation?
    public private(set) var stack: [DebugLocation] = []
    public private(set) var variables: [DebugVariable] = []
    /// Ramka wybrana na stosie (0 — bieżąca).
    public private(set) var selectedFrame = 0
    public private(set) var lastReason = 0
    /// Zatrzymanie na wyjątku (reason_exception = 11) albo na punkcie przerwania kodu błędu (26).
    public var stoppedOnException: Bool { state == .paused && (lastReason == 11 || lastReason == 26) }
    public private(set) var message: String?
    /// Obserwowane wyrażenia (nazwy zmiennych, pola `r.pole`, elementy `t(3)`) i ich wartości po zatrzymaniu (UG 5.10).
    /// Obserwowane wyrażenia — w dokumencie okna testu (zapis w .tst).
    public var watches: [String] {
        get { document.testWatches }
        set { document.testWatches = newValue }
    }
    public private(set) var watchValues: [DebugVariable] = []

    @ObservationIgnored let workspace: Workspace
    @ObservationIgnored let document: Document
    @ObservationIgnored var target: (any DatabaseSession)?
    @ObservationIgnored var debug: (any DatabaseSession)?
    @ObservationIgnored var execution: Task<ExecutionResult, any Error>?
    @ObservationIgnored var bindsUsed: [BindVariable] = []
    @ObservationIgnored var hitCounts: [UUID: Int] = [:]
    @ObservationIgnored var bpNumbers: [Int: UUID] = [:]
    @ObservationIgnored var sourceCache: [String: String] = [:]
    /// Stop w trakcie kroku: pętla zdarzeń zatrzymuje się przy najbliższym zdarzeniu, a program przerywa `stop()`.
    @ObservationIgnored var stopRequested = false
    /// PLSQL_OPTIMIZE_LEVEL sesji okna sprzed startu — przywracany w `cleanUp()`.
    @ObservationIgnored var previousOptimizeLevel: Int?

    /// Śledzenie wywołań DBMS_DEBUG w dzienniku aplikacji (poziom Szczegóły, D170): kody, statusy i numery linii jawne,
    /// nazwy jednostek i zmiennych jako skrót (`.hash`) — ślad jest użyteczny bez jawnych nazw i bez wartości zmiennych.
    nonisolated static func trace(_ m: @autoclosure () -> LogMessage) {
        Log.debugger.debug(m())
    }

    init(workspace: Workspace, document: Document) {
        self.workspace = workspace
        self.document = document
    }

    // MARK: Start i kroki

    /// Start: inicjalizacja DBMS_DEBUG w sesji okna, dołączenie sesji nadzorującej, uruchomienie bloku i zatrzymanie
    /// w pierwszej linii (Step into przy starcie, UG 5.10).
    public func start() async throws {
        guard state == .idle || state == .finished else { return }
        TestRunner.synchronize(document)
        guard let conn = workspace.effectiveConnection(of: document) else { throw CommandError.notConnected }
        var sql = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if sql.hasSuffix("/") { sql = String(sql.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        try await workspace.guardModification([sql], connectionID: conn)
        let binds = try document.testVariables.map { v -> BindVariable in
            let (t, size) = v.type.bind
            return BindVariable(name: v.name, type: t, direction: v.type == .cursor ? .output : .inputOutput, value: try TestRunner.value(v, format: workspace.settings.valueFormat), maxSize: size)
        }
        let target = try await workspace.session(for: document)
        let debug = try await workspace.sessions.session(workspace.sessions.debuggerKey(document: document.id, connection: conn))
        self.target = target
        self.debug = debug
        hitCounts = [:]
        bpNumbers = [:]
        sourceCache = [:]
        message = nil
        // Informacja debugowania dla bloku testu (PLSQL_OPTIMIZE_LEVEL 1 zachowuje wszystkie linie i zmienne).
        Self.trace("start")
        Log.debugger.info("Debuger: start sesji debugowania")
        // Poprzednia wartość wraca po debugowaniu (w trybie single ta sama sesja kompiluje obiekty). V$PARAMETER pokazuje
        // wartość sesji; bez uprawnień do widoku — wartość domyślna 2.
        let level = (try? await target.scalar("select value from v$parameter where name = 'plsql_optimize_level'")) ?? nil
        previousOptimizeLevel = level.flatMap { Int($0) } ?? 2
        _ = try? await target.execute("alter session set plsql_optimize_level = 1")
        // DBMS_OUTPUT przed DEBUG_ON — potem każde wywołanie PL/SQL w tej sesji czeka na debuger.
        if document.outputEnabled && workspace.settings.dbmsOutputEnabled {
            if workspace.settings.dbmsOutputClearBeforeExecute { document.output = [] }
            try? await SessionUtilities.enableOutput(target, bufferSize: workspace.settings.dbmsOutputBufferSize)
        }
        let initResult: ExecutionResult
        do {
            initResult = try await target.execute("begin :id := dbms_debug.initialize; dbms_debug.debug_on; end;",
                                                  binds: [BindVariable(name: "id", direction: .output, maxSize: 100)])
        } catch {
            await restoreOptimizeLevel()
            throw error
        }
        // Od DEBUG_ON błąd startu nie może zostawić sesji okna w trybie debugowania (każde kolejne wywołanie PL/SQL
        // czekałoby na debuger): z dołączoną sesją nadzorującą — sprzątanie jak przy Stop, bez niej — zamknięcie sesji.
        var attached = false
        let info: RuntimeInfo
        do {
            guard let id = initResult.outBinds["id"]?.displayText ?? initResult.outBinds["ID"]?.displayText else {
                throw CommandError.notAvailable(L10n.tr("DBMS_DEBUG nie zwrócił identyfikatora sesji"))
            }
            Self.trace("initialize -> \(id, privacy: .hash)")
            _ = try await debug.execute("begin dbms_debug.attach_session(:id); end;", binds: [BindVariable(name: "id", value: .text(id))])
            attached = true
            Self.trace("attached")
            bindsUsed = binds
            document.isExecuting = true
            document.errorStack = []
            execution = Task.detached { try await target.execute(sql, binds: binds) }
            state = .running
            // Pierwsze zdarzenie: start interpretera; punkty przerwania; potem pierwsza linia.
            info = try await runtimeCall("dbms_debug.synchronize(ri, dbms_debug.info_getstackdepth + dbms_debug.info_getbreakpoint + dbms_debug.info_getlineinfo)")
            if !info.terminated { try await applyBreakpoints(block: false) }
        } catch {
            if attached {
                await cleanUp()
            } else {
                await workspace.sessions.close(workspace.sessions.key(forDocument: document.id, connection: conn))
            }
            state = .finished
            throw error
        }
        if info.terminated { return await finish() }
        // Punkty przerwania na kodach błędów (ORA-n, PD-DBG-008).
        for code in workspace.errorBreakpoints {
            _ = try? await debug.execute("begin :st := dbms_debug.set_oer_breakpoint(:c); end;",
                                         binds: [BindVariable(name: "st", type: .number, direction: .output),
                                                 BindVariable(name: "c", type: .number, value: .number(String(code)))])
        }
        try await continueOrAbandon(breakflags: "dbms_debug.break_any_call")
    }

    /// Krok albo uruchomienie do punktu przerwania / wyjątku / końca (UG 5.10).
    public func step(_ s: Step) async throws {
        guard state == .paused else { return }
        // Punkty przerwania bloku testu: SET_BREAKPOINT nie działa w bloku anonimowym — emulacja (kroki w bloku,
        // w jednostkach do powrotu; punkty w jednostkach i wyjątki zatrzymują jak zwykle).
        let blockLines = Set(workspace.breakpoints.filter { $0.enabled && $0.document == document.id.raw }.map(\.line))
        if !blockLines.isEmpty, s == .run || s == .runToException {
            let exc = s == .runToException ? " + dbms_debug.break_exception" : ""
            while state == .paused {
                let inBlock = location?.isTestBlock == true
                try await continueOrAbandon(breakflags: (inBlock ? "dbms_debug.break_next_line" : "dbms_debug.break_any_return") + exc)
                guard state == .paused, !stopRequested, let l = location else { return }
                if lastReason == 3 || lastReason == 11 || lastReason == 26 { return }                  // punkt przerwania jednostki / wyjątek
                if l.isTestBlock, blockLines.contains(l.line) {
                    let bp = workspace.breakpoints.first { $0.enabled && $0.document == document.id.raw && $0.line == l.line }
                    if let bp, bp.hasActions, !(await shouldStop(at: bp)) { continue }
                    return
                }
            }
            return
        }
        let flags: String = switch s {
        case .into: "dbms_debug.break_any_call"
        case .over: "dbms_debug.break_next_line"
        case .out: "dbms_debug.break_any_return"
        case .run: "0"
        case .runToException: "dbms_debug.break_exception"
        }
        try await continueOrAbandon(breakflags: flags)
    }

    /// Krok z obsługą błędu sesji nadzorującej: sesja okna nie może zostać w trybie debugowania (każde kolejne wywołanie
    /// PL/SQL czekałoby na debuger) — sprzątanie jak przy końcu programu i stan „zakończony”.
    func continueOrAbandon(breakflags: String) async throws {
        do {
            try await continueExecution(breakflags: breakflags)
        } catch {
            await cleanUp()
            location = nil
            stack = []
            variables = []
            state = .finished
            throw error
        }
    }

    /// Przerywa program (abort) i kończy sesję debugowania.
    public func stop() async {
        guard state == .paused || state == .running else { return }
        Log.debugger.info("Debuger: przerwanie przez użytkownika")
        // Krok w toku: program zatrzymany na punkcie przerwania czekałby na debuger, a Stop na program — pętla zdarzeń
        // zatrzymuje się przy najbliższym zdarzeniu (bez odczytu zmiennych) i dopiero wtedy przerwanie.
        if state == .running {
            stopRequested = true
            defer { stopRequested = false }
            while state == .running { try? await Task.sleep(for: .milliseconds(20)) }
            // Program zakończył się sam (finish() już posprzątał).
            guard state == .paused else { return }
        }
        // Program może przechwycić przerwanie (np. ut.run uruchamia dalsze testy) — przerwanie aż do zakończenia.
        if state == .paused {
            for _ in 0..<200 {
                guard let info = try? await runtimeCall("dbms_debug.continue(ri, dbms_debug.abort_execution, 0)") else { break }
                if info.terminated || info.reason == 15 || info.reason == 25 { break }
            }
        }
        _ = try? await execution?.value
        await cleanUp()
        location = nil
        stack = []
        variables = []
        state = .finished
        message = L10n.tr("Przerwano")
    }

    /// Wybór ramki stosu — zmienne tej ramki (UG 5.10 „klik = ramka i jej zmienne”).
    public func selectFrame(_ index: Int) async {
        guard state == .paused, index >= 0, index < stack.count else { return }
        selectedFrame = index
        await loadVariables()
    }

    // MARK: Pętla zdarzeń

    struct RuntimeInfo {
        var status: Int
        var line: Int
        var terminated: Bool
        var breakpoint: Int
        var reason: Int
        var owner: String
        var name: String
        var unitType: Int
    }

    /// Wywołanie SYNCHRONIZE / CONTINUE w bloku rozpakowującym RUNTIME_INFO do zmiennych skalarnych.
    func runtimeCall(_ call: String) async throws -> RuntimeInfo {
        guard let debug else { throw CommandError.notAvailable(L10n.tr("Debuger nie jest uruchomiony")) }
        Self.trace("call \(call.prefix(40), privacy: .public)")
        defer { Self.trace("call done") }
        let names = ["ret", "line", "term", "bp", "reason", "owner", "name", "utype"]
        let binds = names.map { n in BindVariable(name: n, type: ["owner", "name"].contains(n) ? .varchar2 : .number, direction: .output, maxSize: 200) }
        let r = try await debug.execute("""
            declare
              ri dbms_debug.runtime_info;
            begin
              :ret := \(call);
              :line := ri.line#; :term := ri.terminated; :bp := ri.breakpoint; :reason := ri.reason;
              :owner := ri.program.owner; :name := ri.program.name; :utype := ri.program.libunittype;
            end;
            """, binds: binds)
        func n(_ k: String) -> Int { Int(r.outBinds[k]?.displayText ?? r.outBinds[k.uppercased()]?.displayText ?? "") ?? 0 }
        func s(_ k: String) -> String { r.outBinds[k]?.displayText ?? r.outBinds[k.uppercased()]?.displayText ?? "" }
        return RuntimeInfo(status: n("ret"), line: n("line"), terminated: n("term") != 0, breakpoint: n("bp"), reason: n("reason"),
                           owner: s("owner"), name: s("name"), unitType: n("utype"))
    }

    func continueExecution(breakflags: String) async throws {
        state = .running
        var flags = breakflags
        while true {
            let info = try await runtimeCall("dbms_debug.continue(ri, \(flags), dbms_debug.info_getstackdepth + dbms_debug.info_getbreakpoint + dbms_debug.info_getlineinfo)")
            flags = breakflags
            lastReason = info.reason
            Self.trace("event status=\(info.status) reason=\(info.reason) term=\(info.terminated) unit=\(info.owner, privacy: .hash).\(info.name, privacy: .hash)/\(info.unitType) line=\(info.line) bp=\(info.breakpoint)")
            // reason_exit (15) / reason_knl_exit (25) / zakończony program.
            if info.terminated || info.reason == 15 || info.reason == 25 { return await finish() }
            // Stop w trakcie kroku — program czeka na debuger, przerwie go stop().
            if stopRequested {
                location = nil
                state = .paused
                return
            }
            // Punkt przerwania z licznikiem przejść: kontynuacja do osiągnięcia liczby (UG 5.10 „Pass Count”).
            if info.breakpoint > 0, let id = bpNumbers[info.breakpoint],
               let bp = workspace.breakpoints.first(where: { $0.id == id }), bp.passCount > 0 {
                hitCounts[id, default: 0] += 1
                if hitCounts[id, default: 0] < bp.passCount { continue }
            }
            // Warunek, komunikat i logpoint (PD-DBG-007).
            if info.breakpoint > 0, let id = bpNumbers[info.breakpoint],
               let bp = workspace.breakpoints.first(where: { $0.id == id }), bp.hasActions, !(await shouldStop(at: bp)) { continue }
            // Wejście do jednostki (reason_enter) i jednostki bez informacji debugowania (linia 0) — dalej do pierwszej linii.
            if info.line == 0 || info.reason == 6 { continue }
            // Pomijanie kodu SYS (wyjście z jednostki) i inicjalizacji specyfikacji pakietu (preferencje debugera).
            let isBreakpoint = info.breakpoint > 0 || info.reason == 11 || info.reason == 26
            if !isBreakpoint, workspace.settings.debuggerSkipSys, info.owner == "SYS" { flags = "dbms_debug.break_any_return"; continue }

            location = DebugLocation(owner: info.owner, name: info.name, unitType: info.unitType, line: info.line)
            selectedFrame = 0
            state = .paused
            await loadStack()
            // Typ jednostki z RUNTIME_INFO bywa 0 — poprawny jest w ramce stosu (PRINT_BACKTRACE).
            if location?.unitType == 0, let top = stack.first, top.name == location?.name, top.unitType != 0 {
                location?.unitType = top.unitType
            }
            // Inicjalizacja specyfikacji pakietu (typ 9) — dalej, chyba że to punkt przerwania (preferencja debugera).
            if !isBreakpoint, workspace.settings.debuggerSkipPackageInit, location?.unitType == 9 {
                state = .running
                continue
            }
            await loadVariables()
            Self.trace("paused: watches")
            await loadWatches()
            await readOutputWhilePaused()
            return
        }
    }

    /// DBMS_OUTPUT zebrany do chwili zatrzymania — odczyt w sesji docelowej przez DBMS_DEBUG.EXECUTE (PD-DBG-010).
    func readOutputWhilePaused() async {
        guard document.outputEnabled, workspace.settings.dbmsOutputEnabled, let debug else { return }
        Self.trace("output: read while paused")
        defer { Self.trace("output: done") }
        // Elementy SYS.DBMS_DEBUG_VC2COLL mają limit w bajtach (zakładamy najgorszy przypadek VARCHAR2(1000) BYTE):
        // linia dzielona na kawałki po 249 znaków (≤ 4 bajty na znak), koniec linii — chr(10) w ostatnim kawałku.
        let block = "declare pp sys.dbms_debug_vc2coll := sys.dbms_debug_vc2coll(); l varchar2(32767); st integer; i pls_integer; " +
            "begin loop dbms_output.get_line(l, st); exit when st <> 0; i := 1; " +
            "loop pp.extend; pp(pp.count) := substr(l, i, 249); i := i + 249; exit when i > nvl(length(l), 0); end loop; " +
            "pp(pp.count) := pp(pp.count) || chr(10); end loop; :1 := pp; end;"
        let r = try? await debug.execute("""
            declare
              coll sys.dbms_debug_vc2coll;
              errm varchar2(4000);
              s varchar2(32767);
            begin
              dbms_debug.execute(:b, -1, 1, coll, errm);
              if coll is not null and coll.count > 0 then
                for i in coll.first .. coll.last loop
                  if nvl(lengthb(s), 0) <= 31000 then s := s || coll(i); end if;
                end loop;
              end if;
              :s := s;
            end;
            """, binds: [BindVariable(name: "b", value: .text(block)), BindVariable(name: "s", direction: .output, maxSize: 32767)])
        let text = r?.outBinds["s"]?.displayText ?? r?.outBinds["S"]?.displayText ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast()
        if !lines.isEmpty { document.output.append(contentsOf: lines) }
    }

    /// Wykonanie SQL albo PL/SQL w sesji debugowanej podczas zatrzymania (DBMS_DEBUG.EXECUTE, UG 5.10). Zapytanie —
    /// pierwsze 100 wierszy jako tekst (kolumny rozdzielone tabulatorem).
    public func executeInTarget(_ sql: String) async throws -> [String] {
        guard state == .paused, let debug else { throw CommandError.notAvailable(L10n.tr("Debuger nie jest zatrzymany")) }
        var trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuery = trimmed.lowercased().hasPrefix("select") || trimmed.lowercased().hasPrefix("with")
        // Średnik końcowy tylko z zapytania (blok PL/SQL musi go zachować).
        if isQuery { trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "; \n")) }
        // Zapytanie: wiersze jako JSON (DBMS_SQL jest zablokowany w DBMS_DEBUG.EXECUTE — ORA-29471), w kawałkach po 250 znaków
        // (elementy SYS.DBMS_DEBUG_VC2COLL mają limit w bajtach — najgorszy przypadek VARCHAR2(1000) BYTE, ≤ 4 bajty na znak).
        let what = isQuery ? """
            declare pp sys.dbms_debug_vc2coll := sys.dbms_debug_vc2coll(); j clob;
            begin select json_arrayagg(json_object(*) returning clob) into j from (\(trimmed) fetch first 100 rows only);
              if j is not null then
                for i in 0 .. ceil(dbms_lob.getlength(j) / 250) - 1 loop pp.extend; pp(pp.count) := dbms_lob.substr(j, 250, i * 250 + 1); end loop;
              end if;
              :1 := pp; end;
            """ : trimmed
        let r = try await debug.execute("""
            declare
              coll sys.dbms_debug_vc2coll;
              errm varchar2(4000);
              s varchar2(32767);
            begin
              dbms_debug.execute(:w, -1, :b, coll, errm);
              if coll is not null and coll.count > 0 then
                for i in coll.first .. coll.last loop
                  if nvl(lengthb(s), 0) <= 31000 then s := s || coll(i) || chr(10); end if;
                end loop;
              end if;
              :s := s;
              :e := errm;
            end;
            """, binds: [BindVariable(name: "w", value: .text(what)), BindVariable(name: "b", type: .number, value: .number(isQuery ? "1" : "0")),
                         BindVariable(name: "s", direction: .output, maxSize: 32767), BindVariable(name: "e", direction: .output, maxSize: 4000)])
        if let e = (r.outBinds["e"] ?? r.outBinds["E"])?.displayText, !e.isEmpty { throw CommandError.notAvailable(e) }
        let text = r.outBinds["s"]?.displayText ?? r.outBinds["S"]?.displayText ?? ""
        if isQuery {
            // Kawałki JSON (separator chr(10) dodany przez blok — w JSON nowe linie są zawsze w postaci \n).
            return Self.jsonRows(text.replacingOccurrences(of: "\n", with: ""))
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast().map { $0 }
    }

    /// Wiersze z `[{"A":1,"B":"x"},…]` z zachowaniem kolejności kolumn; wartości rozdzielone tabulatorem.
    nonisolated static func jsonRows(_ json: String) -> [String] {
        var rows: [String] = []
        var values: [String] = []
        var i = json.startIndex
        var depth = 0
        var expectValue = false
        func readString() -> String {
            var s = ""
            i = json.index(after: i)
            while i < json.endIndex, json[i] != "\"" {
                if json[i] == "\\" {
                    i = json.index(after: i)
                    guard i < json.endIndex else { break }
                    switch json[i] {
                    case "n": s.append("\n")
                    case "t": s.append("\t")
                    case "r": s.append("\r")
                    case "b": s.append("\u{8}")
                    case "f": s.append("\u{C}")
                    case "u":
                        let hex = json[json.index(after: i)...].prefix(4)
                        i = json.index(i, offsetBy: 4, limitedBy: json.endIndex) ?? json.endIndex
                        guard var v = UInt32(hex, radix: 16) else { break }
                        // Para surogatów (znaki spoza BMP, np. emoji): \uD83D\uDE00.
                        if (0xD800...0xDBFF).contains(v), i < json.endIndex, json[json.index(after: i)...].hasPrefix("\\u"),
                           let low = UInt32(json[json.index(after: i)...].dropFirst(2).prefix(4), radix: 16), (0xDC00...0xDFFF).contains(low) {
                            v = 0x10000 + ((v - 0xD800) << 10) + (low - 0xDC00)
                            i = json.index(i, offsetBy: 6, limitedBy: json.endIndex) ?? json.endIndex
                        }
                        if let u = Unicode.Scalar(v) { s.unicodeScalars.append(u) }
                    default: s.append(json[i])
                    }
                } else {
                    s.append(json[i])
                }
                if i < json.endIndex { i = json.index(after: i) }
            }
            return s
        }
        while i < json.endIndex {
            let c = json[i]
            switch c {
            case "{": depth += 1; if depth == 1 { values = [] }
            case "}": depth -= 1; if depth == 0 { rows.append(values.joined(separator: "\t")) }
            case ":" where depth == 1: expectValue = true
            case "\"":
                let s = readString()
                if expectValue, depth == 1 { values.append(s); expectValue = false }
            default:
                if expectValue, depth == 1, !c.isWhitespace, c != "," {
                    var raw = ""
                    while i < json.endIndex, json[i] != ",", json[i] != "}" { raw.append(json[i]); i = json.index(after: i) }
                    values.append(raw == "null" ? "" : raw.trimmingCharacters(in: .whitespaces))
                    expectValue = false
                    continue
                }
            }
            if i < json.endIndex { i = json.index(after: i) }
        }
        return rows
    }

    /// Wartości obserwowanych wyrażeń w bieżącej ramce.
    func loadWatches() async {
        guard !watches.isEmpty, stack.indices.contains(selectedFrame) else { watchValues = []; return }
        let frame = stack[selectedFrame]
        let text = await source(of: frame)
        let ctx = CompletionContext.analyze(text, offset: ProgramCompiler.offset(line: frame.line, column: 1, in: text))
        var out: [DebugVariable] = []
        for w in watches {
            let decl = ctx.declarations.first { $0.name.uppercased() == w.uppercased() }
            out.append(await variable(w, path: w, type: decl?.detail ?? "", frame: selectedFrame, context: ctx))
        }
        watchValues = out
    }

    public func addWatch(_ expression: String) async {
        let e = expression.trimmingCharacters(in: .whitespaces)
        if Self.isUnsupportedName(e) { workspace.ui?.showError(L10n.tr("Wyrażenia z dwukropkiem (:new, :old, zmienne wiązane) nie są dostępne w debugerze DBMS_DEBUG")); return }
        guard !e.isEmpty, !watches.contains(e) else { return }
        watches.append(e)
        if state == .paused { await loadWatches() }
    }

    public func removeWatch(_ expression: String) {
        watches.removeAll { $0 == expression }
        watchValues.removeAll { $0.path == expression }
    }

    /// Zmiana wartości zmiennej skalarnej w bieżącej ramce (SET_VALUE, „Set Variable”, UG 5.10).
    public func setValue(_ path: String, to value: String) async throws {
        guard state == .paused, let debug else { return }
        func find(_ vs: [DebugVariable]) -> DebugVariable? {
            for v in vs { if v.path == path { return v }; if let c = find(v.children ?? []) { return c } }
            return nil
        }
        let literal = Self.literal(value, type: find(variables + watchValues)?.type ?? "")
        let r = try await debug.execute("begin :st := dbms_debug.set_value(:f, :a); end;", binds: [
            BindVariable(name: "st", type: .number, direction: .output),
            BindVariable(name: "f", type: .number, value: .number(String(selectedFrame))),
            BindVariable(name: "a", value: .text("\(path) := \(literal);")),
        ])
        let st = Int(r.outBinds["st"]?.displayText ?? r.outBinds["ST"]?.displayText ?? "") ?? -1
        guard st == 0 else { throw CommandError.notAvailable(L10n.tr("Nie można ustawić wartości (status DBMS_DEBUG \(st))")) }
        await loadVariables()
        await loadWatches()
    }

    /// Typy liczbowe PL/SQL (pierwsze słowo deklaracji) — wartość bez apostrofów.
    nonisolated static let numericTypes: Set<String> = ["NUMBER", "INTEGER", "INT", "PLS_INTEGER", "BINARY_INTEGER", "SIMPLE_INTEGER",
        "BINARY_FLOAT", "BINARY_DOUBLE", "FLOAT", "DECIMAL", "DEC", "NUMERIC", "REAL", "SMALLINT", "DOUBLE", "NATURAL", "NATURALN",
        "POSITIVE", "POSITIVEN", "SIGNTYPE"]

    /// Liczba dziesiętna w zapisie SQL (bez inf/nan/zapisu szesnastkowego); `leadingZeros: false` — bez zer wiodących (`007`).
    nonisolated static func isPlainNumber(_ s: String, leadingZeros: Bool = true) -> Bool {
        guard s.range(of: #"^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil else { return false }
        return leadingZeros || s.range(of: #"^[+-]?0\d"#, options: .regularExpression) == nil
    }

    /// Literał PL/SQL dla SET_VALUE wg typu deklaracji zmiennej: liczba (przecinek dziesiętny → kropka) tylko dla typów
    /// liczbowych, TRUE/FALSE dla BOOLEAN, napisy w apostrofach. Typ nieznany (`%TYPE`, pole) — liczba bez zer wiodących.
    nonisolated static func literal(_ value: String, type: String) -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.uppercased() == "NULL" { return "NULL" }
        let base = type.uppercased().split(whereSeparator: { $0 == "(" || $0 == " " }).first.map(String.init) ?? ""
        let known = !base.isEmpty && !base.contains("%") && !base.contains(".")
        let number = v.replacingOccurrences(of: ",", with: ".")
        if known {
            if numericTypes.contains(base), isPlainNumber(number) { return number }
            if base == "BOOLEAN", ["TRUE", "FALSE"].contains(v.uppercased()) { return v.uppercased() }
        } else {
            if isPlainNumber(number, leadingZeros: false) { return number }
            if ["TRUE", "FALSE"].contains(v.uppercased()) { return v.uppercased() }
        }
        return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// Koniec programu: wynik wykonania (zmienne OUT jak w Test Window) albo błąd ze stosem.
    func finish() async {
        state = .finished
        location = nil
        stack = []
        variables = []
        guard let execution else { return }
        do {
            let r = try await execution.value
            for i in document.testVariables.indices {
                let v = document.testVariables[i]
                let out = r.outBinds[v.name] ?? r.outBinds[v.name.uppercased()] ?? .null
                var n = v
                if case .cursor = out { n.value = L10n.tr("(kursor)"); n.isNull = false } else {
                    n.isNull = out.isNull
                    n.value = out.isNull ? "" : TestRunner.outputText(out, format: workspace.settings.valueFormat)
                }
                n.changed = n.value != v.value || n.isNull != v.isNull
                document.testVariables[i] = n
            }
            message = L10n.tr("Zakończono")
            Log.debugger.info("Debuger: program zakończony")
        } catch let e as OracleError {
            Log.debugger.info("Debuger: program zakończony błędem \(e as any Error)")
            document.errorStack = TestRunner.errorStack(e.message)
            message = e.message.components(separatedBy: "\n").first
        } catch {
            // Inne błędy (zamknięta sesja, anulowanie) — też sprzątanie, inaczej sesja okna zostaje w trybie debugowania.
            message = error.localizedDescription
        }
        await cleanUp()
        if document.outputEnabled && workspace.settings.dbmsOutputEnabled, let t = target, let lines = try? await SessionUtilities.readOutput(t) {
            document.output.append(contentsOf: lines)
        }
        document.isExecuting = false
    }

    /// Wyłączenie trybu debugowania: DEBUG_OFF w sesji docelowej też jest „debugowanym” wywołaniem — sesja nadzorująca
    /// odbiera jego zdarzenia (SYNCHRONIZE, CONTINUE do końca), potem się odłącza.
    func cleanUp() async {
        if let target, let debug {
            Self.trace("debug_off")
            let off = Task.detached { try await target.execute("begin dbms_debug.debug_off; end;") }
            if let info = try? await runtimeCall("dbms_debug.synchronize(ri, 0)"), !info.terminated {
                for _ in 0..<20 {
                    guard let i = try? await runtimeCall("dbms_debug.continue(ri, 0, 0)") else { break }
                    if i.terminated || i.reason == 15 || i.reason == 25 { break }
                }
            }
            _ = try? await off.value
            _ = try? await debug.execute("begin dbms_debug.detach_session; end;")
        }
        await restoreOptimizeLevel()
        // Program mógł zmienić dane bez COMMIT — stan transakcji sesji okna jak po wykonaniu w oknie testu (po DEBUG_OFF,
        // inaczej zapytanie czekałoby na debuger).
        if let target { document.transactionOpen = (try? await SessionUtilities.transactionOpen(target)) ?? document.transactionOpen }
        execution = nil
        document.isExecuting = false
    }

    /// PLSQL_OPTIMIZE_LEVEL sesji okna sprzed startu (po DEBUG_OFF — inaczej czekałby na debuger).
    func restoreOptimizeLevel() async {
        guard let level = previousOptimizeLevel else { return }
        previousOptimizeLevel = nil
        _ = try? await target?.execute("alter session set plsql_optimize_level = \(level)")
    }

    // MARK: Stos i zmienne

    func loadStack() async {
        guard let debug else { return }
        let r = try? await debug.execute("""
            declare
              bt dbms_debug.backtrace_table;
              s varchar2(32767);
            begin
              dbms_debug.print_backtrace(bt);
              for i in reverse 1 .. bt.count loop
                s := s || bt(i).owner || '|' || bt(i).name || '|' || bt(i).line# || '|' || bt(i).libunittype || chr(10);
              end loop;
              :s := s;
            end;
            """, binds: [BindVariable(name: "s", direction: .output, maxSize: 32767)])
        let text = r?.outBinds["s"]?.displayText ?? r?.outBinds["S"]?.displayText ?? ""
        stack = text.split(separator: "\n").compactMap { l in
            let p = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard p.count == 4 else { return nil }
            return DebugLocation(owner: p[0], name: p[1], unitType: Int(p[3]) ?? 0, line: Int(p[2]) ?? 0)
        }
        if stack.isEmpty, let location { stack = [location] }
    }

    /// Źródło jednostki ramki (blok testu — tekst okna) do ustalenia deklaracji w zasięgu.
    func source(of l: DebugLocation) async -> String {
        if l.isTestBlock { return document.text }
        let key = "\(l.owner).\(l.name).\(l.unitType)"
        if let c = sourceCache[key] { return c }
        guard let type = l.objectType, let m = workspace.metadata(for: workspace.effectiveConnection(of: document)) else { return "" }
        let s = (try? await m.source(of: DBObject(owner: l.owner, name: l.name, type: type))) ?? ""
        sourceCache[key] = s
        return s
    }

    /// Zmienne ramki: deklaracje w zasięgu linii (parser) i wartości z GET_VALUE; rekordy i kolekcje jako drzewo.
    func loadVariables() async {
        guard stack.indices.contains(selectedFrame) else { variables = []; return }
        let frame = stack[selectedFrame]
        Self.trace("vars: source \(frame.name, privacy: .hash)")
        let text = await source(of: frame)
        Self.trace("vars: source done \(text.count)")
        let offset = ProgramCompiler.offset(line: frame.line, column: 1, in: text)
        let ctx = CompletionContext.analyze(text, offset: offset)
        Self.trace("vars: \(ctx.declarations.count) declarations, \(ctx.loopRecords.count) loop records")
        // Ramka dla GET_VALUE: 0 — bieżąca; numeracja od najnowszej.
        let frameNo = selectedFrame
        var out: [DebugVariable] = []
        for d in ctx.declarations where [.variable, .constant, .parameter].contains(d.kind) {
            out.append(await variable(d.name, path: d.name, type: d.detail, frame: frameNo, context: ctx))
        }
        // Zmienne globalne pakietu: prywatne (ciało) i publiczne (specyfikacja) — GET_VALUE z uchwytem pakietu (UG 5.10).
        if [9, 11].contains(frame.unitType) {
            out += await packageGlobals(owner: frame.owner, name: frame.name, context: ctx)
        }
        // SELF w metodzie typu (ciało typu, LibunitType 14): atrybuty jako drzewo (GET_VALUE „SELF.ATRYBUT”).
        if frame.unitType == 14 {
            out.insert(await variable("self", path: "self", type: "\(frame.owner).\(frame.name)", frame: frameNo, context: ctx), at: 0)
        }
        // Wyzwalacz (12): DBMS_DEBUG nie udostępnia :new/:old — informacja zamiast wartości.
        if frame.unitType == 12 {
            out.append(DebugVariable(name: ":new / :old", path: "#trigger", value: L10n.tr("(niedostępne przez DBMS_DEBUG)"), type: ""))
        }
        // Zmienne pętli FOR (rekordy, liczniki) obejmujących linię.
        for (name, _) in ctx.loopRecords.sorted(by: { $0.key < $1.key }) {
            out.append(await variable(name.lowercased(), path: name.lowercased(), type: "record", frame: frameNo, context: ctx))
        }
        variables = out
    }

    /// Wartość zmiennej; rekord (pola z typu) i kolekcja (indeksy z GET_INDEXES) — rozwinięte jeden poziom.
    func variable(_ name: String, path: String, type: String, frame: Int, context ctx: CompletionContext) async -> DebugVariable {
        let (status, value) = await getValue(path, frame: frame)
        var v = DebugVariable(name: name, path: path, value: value ?? "", type: type)
        switch status {
        case 0: break                                              // success
        case 2: v.value = L10n.tr("(brak informacji debugowania)")  // error_no_debug_info
        case 3, 11:                                                  // error_no_such_object / error_name_incomplete
            let fields = await recordFields(type, context: ctx)
            if fields.isEmpty { v.value = L10n.tr("(niedostępna)"); break }
            var children: [DebugVariable] = []
            for f in fields { children.append(await variable(f.lowercased(), path: path + "." + f.lowercased(), type: "", frame: frame, context: ctx)) }
            v.children = children
            v.value = L10n.tr("(rekord)")
        case 32: v.value = "NULL"                                    // error_nullvalue
        case 40: v.value = L10n.tr("(kolekcja NULL)")               // error_nullcollection
        case 18:                                                     // error_indexed_table
            v.children = await collection(path, frame: frame, type: type, context: ctx)
            v.value = L10n.tr("(\(v.children?.count ?? 0) elementów)")
        default:
            // Rekord: pola wg typu (%ROWTYPE, typ lokalny).
            let fields = await recordFields(type, context: ctx)
            if !fields.isEmpty {
                var children: [DebugVariable] = []
                for f in fields { children.append(await variable(f.lowercased(), path: path + "." + f.lowercased(), type: "", frame: frame, context: ctx)) }
                v.children = children
                v.value = L10n.tr("(rekord)")
            } else if value == nil {
                v.value = "NULL"
            }
        }
        return v
    }

    /// Zmienne z poziomu pakietu (bez podprogramów): grupy „Globalne prywatne” i „Globalne publiczne”.
    func packageGlobals(owner: String, name: String, context ctx: CompletionContext) async -> [DebugVariable] {
        guard let m = workspace.metadata(for: workspace.effectiveConnection(of: document)) else { return [] }
        var groups: [DebugVariable] = []
        for (type, ns, title) in [(DBObjectType.packageBody, 2, L10n.tr("Globalne prywatne")), (DBObjectType.package, 1, L10n.tr("Globalne publiczne"))] {
            let key = "\(owner).\(name).\(type.rawValue)"
            let src: String
            if let c = sourceCache[key] { src = c } else {
                src = (try? await m.source(of: DBObject(owner: owner, name: name, type: type))) ?? ""
                sourceCache[key] = src
            }
            guard let unit = PLSQLOutline.parse(src).first else { continue }
            var children: [DebugVariable] = []
            for d in unit.children where [.variable, .constant].contains(d.kind) {
                var (st, v) = await getValue(d.name, package: (owner, name, ns))
                // Prywatne zmienne ciała są widoczne w zasięgu ramki podprogramu ciała — odczyt przez ramkę.
                if st == 3 { (st, v) = await getValue(d.name, frame: selectedFrame) }
                children.append(DebugVariable(name: d.name, path: "\(name).\(d.name)", value: st == 0 ? (v ?? "NULL") : st == 32 ? "NULL" : L10n.tr("(niedostępna)"),
                                              type: d.detail))
            }
            if !children.isEmpty {
                groups.append(DebugVariable(name: title, path: "#\(type.rawValue)", value: "", type: "", children: children))
            }
        }
        return groups
    }

    /// GET_VALUE dla zmiennej pakietu (uchwyt program_info zamiast numeru ramki).
    func getValue(_ variable: String, package p: (owner: String, name: String, namespace: Int)) async -> (Int, String?) {
        guard let debug else { return (-1, nil) }
        let r = try? await debug.execute("""
            declare
              h dbms_debug.program_info;
            begin
              h.namespace := :ns; h.owner := :o; h.name := :n; h.dblink := null;
              :st := dbms_debug.get_value(:v, h, :val, null);
            end;
            """, binds: [BindVariable(name: "ns", type: .number, value: .number(String(p.namespace))), BindVariable(name: "o", value: .text(p.owner)),
                         BindVariable(name: "n", value: .text(p.name)), BindVariable(name: "v", value: .text(variable.uppercased())),
                         BindVariable(name: "st", type: .number, direction: .output), BindVariable(name: "val", direction: .output, maxSize: 4000)])
        let st = Int(r?.outBinds["st"]?.displayText ?? r?.outBinds["ST"]?.displayText ?? "") ?? -1
        let v = r?.outBinds["val"] ?? r?.outBinds["VAL"]
        Self.trace("get_value pkg \(p.name, privacy: .hash).\(variable, privacy: .hash) ns=\(p.namespace) status=\(st)")
        return (st, v.flatMap { $0.isNull ? nil : $0.displayText })
    }

    func getValue(_ path: String, frame: Int) async -> (Int, String?) {
        guard let debug else { return (-1, nil) }
        // `:new`/`:old` i inne nazwy z dwukropkiem zawieszają GET_VALUE w sesji debugera (sprawdzone na 23ai) —
        // DBMS_DEBUG ich nie udostępnia, więc odpowiedź „brak takiego obiektu” bez wywołania.
        if Self.isUnsupportedName(path) { return (3, nil) }
        let r = try? await debug.execute("begin :st := dbms_debug.get_value(:n, :f, :v, null); end;", binds: [
            BindVariable(name: "st", type: .number, direction: .output),
            // Nazwy bez cudzysłowu — wielkimi literami (tak zapisuje je kompilator w informacji debugowania).
            BindVariable(name: "n", value: .text(path.contains("\"") ? path : path.uppercased())),
            BindVariable(name: "f", type: .number, value: .number(String(frame))),
            BindVariable(name: "v", direction: .output, maxSize: 4000),
        ])
        let st = Int(r?.outBinds["st"]?.displayText ?? r?.outBinds["ST"]?.displayText ?? "") ?? -1
        let v = r?.outBinds["v"] ?? r?.outBinds["V"]
        Self.trace("get_value \(path, privacy: .hash) frame=\(frame) status=\(st)")
        return (st, v.flatMap { $0.isNull ? nil : $0.displayText })
    }

    func collection(_ path: String, frame: Int, type: String, context ctx: CompletionContext) async -> [DebugVariable] {
        guard let debug else { return [] }
        let r = try? await debug.execute("""
            declare
              ix dbms_debug.index_table;
              h dbms_debug.program_info;
              st binary_integer;
              s varchar2(32767);
            begin
              st := dbms_debug.get_indexes(:n, :f, h, ix);
              if ix.count > 0 then
                for i in ix.first .. ix.last loop
                  if ix.exists(i) and (length(s) < 30000 or s is null) then s := s || ix(i) || ','; end if;
                end loop;
              end if;
              :s := s;
            end;
            """, binds: [BindVariable(name: "n", value: .text(path.uppercased())), BindVariable(name: "f", type: .number, value: .number(String(frame))),
                         BindVariable(name: "s", direction: .output, maxSize: 32767)])
        let idx = (r?.outBinds["s"]?.displayText ?? r?.outBinds["S"]?.displayText ?? "").split(separator: ",").map(String.init).prefix(200)
        var out: [DebugVariable] = []
        for i in idx { out.append(await variable("(\(i))", path: "\(path)(\(i))", type: "", frame: frame, context: ctx)) }
        return out
    }

    /// Pola rekordu: typ lokalny RECORD albo `tabela%ROWTYPE` (kolumny ze słownika).
    func recordFields(_ type: String, context ctx: CompletionContext) async -> [String] {
        let up = type.uppercased().trimmingCharacters(in: .whitespaces)
        if let decl = ctx.typeDeclarations[up] { return CodeAssistant.recordFields(decl).map(\.name) }
        // Typ obiektowy schematu (zmienna obiektu, SELF w metodzie): atrybuty z ALL_TYPE_ATTRS.
        // Rekord pętli FOR (typ „record”) nie ma typu w słowniku.
        if !up.isEmpty, up != "RECORD", !up.contains("%"), let m = workspace.metadata(for: workspace.effectiveConnection(of: document)),
           let s = try? await m.session() {
            let parts = up.split(separator: ".").map(String.init)
            let owner = parts.count > 1 ? parts[0] : nil
            let name = parts.last ?? up
            let sql = "select attr_name from all_type_attrs where type_name = :t" + (owner == nil ? " and owner in (sys_context('userenv', 'current_schema'), 'SYS', 'PUBLIC')" : " and owner = :o") + " order by attr_no"
            var binds = [BindVariable(name: "t", value: .text(name))]
            if let owner { binds.append(BindVariable(name: "o", value: .text(owner))) }
            if let rows = try? await s.queryAll(sql, binds: binds, limit: 500).rows, !rows.isEmpty {
                return rows.compactMap { $0[0].displayText }
            }
        }
        if up.hasSuffix("%ROWTYPE"), let m = workspace.metadata(for: workspace.effectiveConnection(of: document)) {
            let base = String(up.dropLast("%ROWTYPE".count))
            let parts = base.split(separator: ".").map(String.init)
            if let o = try? await m.resolve(owner: parts.count > 1 ? parts[0] : nil, name: parts.last ?? base) {
                return ((try? await m.columns(of: o)) ?? []).map(\.name)
            }
        }
        return []
    }

    // MARK: Punkty przerwania

    /// Nazwa z dwukropkiem poza cudzysłowem (`:new.x`, `:b`) — GET_VALUE/SET_VALUE nie obsługują jej i zawieszają sesję.
    nonisolated static func isUnsupportedName(_ s: String) -> Bool {
        var quoted = false
        for ch in s {
            if ch == "\"" { quoted.toggle() } else if ch == ":", !quoted { return true }
        }
        return false
    }

    /// Komunikat punktu przerwania z `{zmienna}` zastąpionymi wartościami bieżącej ramki.
    func expandMessage(_ m: String) async -> String {
        var out = ""
        var rest = Substring(m)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let name = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            let (st, v) = await getValue(name, frame: 0)
            out += st == 0 ? (v ?? "") : st == 32 ? "NULL" : "{\(name)?}"
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    /// Warunek: identyfikatory (także ścieżki `a.b`) ze zmiennymi ramki zastępowane literałami, wynik z
    /// `select case when … then 1 else 0 end from dual` w sesji nadzorującej. Błąd warunku — zatrzymanie z komunikatem.
    func evaluateCondition(_ c: String) async -> Bool {
        guard let debug else { return true }
        let ns = c as NSString
        var sql = ""
        var pos = 0
        let tokens = Lexer(c).tokenize().filter { !$0.isTrivia }
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            guard t.kind == .identifier || t.kind == .quotedIdentifier else { i += 1; continue }
            // Ścieżka a.b.c
            var end = i
            while end + 2 < tokens.count, tokens[end + 1].kind == .dot, [.identifier, .quotedIdentifier].contains(tokens[end + 2].kind) { end += 2 }
            let start = t.start, stop = tokens[end].start + tokens[end].length
            let name = ns.substring(with: NSRange(location: start, length: stop - start))
            let (st, v) = await getValue(name, frame: 0)
            if st == 0 || st == 32 {
                sql += ns.substring(with: NSRange(location: pos, length: start - pos))
                if st == 32 || v == nil { sql += "NULL" } else if let v, Self.isPlainNumber(v, leadingZeros: false) { sql += v } else { sql += "'" + (v ?? "").replacingOccurrences(of: "'", with: "''") + "'" }
                pos = stop
            }
            i = end + 1
        }
        sql += ns.substring(from: pos)
        do {
            let r = try await debug.queryAll("select case when (\(sql)) then 1 else 0 end from dual", limit: 1)
            return r.rows.first?.first?.displayText == "1"
        } catch {
            document.output.append(L10n.tr("Błąd warunku punktu przerwania „\(c)”: \(error.localizedDescription)"))
            return true
        }
    }

    /// Czy zatrzymać na punkcie z akcjami: komunikat do wyjścia, logpoint (nigdy), warunek.
    func shouldStop(at bp: Breakpoint) async -> Bool {
        if let m = bp.message, !m.isEmpty {
            document.output.append("▸ " + (await expandMessage(m)))
        }
        if bp.dontBreak == true { return false }
        if let c = bp.condition, !c.trimmingCharacters(in: .whitespaces).isEmpty { return await evaluateCondition(c) }
        return true
    }

    /// Tymczasowy punkt przerwania (Wykonaj do kursora) w trakcie sesji.
    func applyTemporary(_ bp: Breakpoint) async throws {
        guard bp.document == nil else { return }       // blok testu — emulacja w `step(.run)`
        try await applyBreakpoints(block: false, only: bp.id)
    }

    func applyBreakpoints(block: Bool, only: UUID? = nil) async throws {
        guard let debug else { return }
        let schema = target?.info.currentSchema ?? ""
        for bp in workspace.breakpoints where bp.enabled && (only == nil || bp.id == only) {
            let isBlock = bp.document == document.id.raw
            guard isBlock == block, isBlock || (bp.unit != nil && bp.type != nil) else { continue }
            let ns: Int
            switch bp.type {
            case .packageBody?, .typeBody?: ns = 2
            case .trigger?: ns = 3
            default: ns = isBlock ? 0 : 1
            }
            let r = try? await debug.execute("""
                declare
                  p dbms_debug.program_info;
                  n binary_integer;
                begin
                  p.namespace := :ns; p.owner := :o; p.name := :u; p.dblink := null; p.line# := :l;
                  :st := dbms_debug.set_breakpoint(p, :l, n);
                  :bp := n;
                end;
                """, binds: [BindVariable(name: "ns", type: .number, value: isBlock ? .null : .number(String(ns))),
                             BindVariable(name: "o", value: isBlock ? .null : .text(bp.owner ?? schema)),
                             BindVariable(name: "u", value: isBlock ? .null : .text(bp.unit ?? "")),
                             BindVariable(name: "l", type: .number, value: .number(String(bp.line))),
                             BindVariable(name: "st", type: .number, direction: .output),
                             BindVariable(name: "bp", type: .number, direction: .output)])
            Self.trace("breakpoint \(bp.unit ?? "<blok>", privacy: .hash):\(bp.line) status=\(r?.outBinds["st"]?.displayText ?? r?.outBinds["ST"]?.displayText ?? "?", privacy: .public) nr=\(r?.outBinds["bp"]?.displayText ?? r?.outBinds["BP"]?.displayText ?? "?", privacy: .public)")
            if let n = Int(r?.outBinds["bp"]?.displayText ?? r?.outBinds["BP"]?.displayText ?? ""), n > 0 { bpNumbers[n] = bp.id }
            // Niezastosowany (brak jednostki, brak informacji debugowania, linia bez kodu): pusty znacznik na marginesie.
            let status = Int(r?.outBinds["st"]?.displayText ?? r?.outBinds["ST"]?.displayText ?? "") ?? -1
            if isBlock { continue }
            if status == 0 { workspace.unappliedBreakpoints.remove(bp.id) } else { workspace.unappliedBreakpoints.insert(bp.id) }
        }
    }
}

extension Workspace {
    /// Debuger okna testu (jeden na okno).
    public func debugger(for doc: Document) -> DebuggerEngine {
        if let d = debuggers[doc.id] { return d }
        let d = DebuggerEngine(workspace: self, document: doc)
        debuggers[doc.id] = d
        return d
    }
}
