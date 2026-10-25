import Foundation
import PelikanDB
import PelikanSQL

/// Oczekiwana wartość zmiennej po wykonaniu testu (UG 24.16): równa, LIKE, IN (lista po przecinku), NULL, NOT NULL.
public struct TestExpectation: Sendable, Codable, Hashable {
    public enum Operator: String, Sendable, Codable, CaseIterable { case equals = "=", like = "LIKE", inList = "IN", isNull = "IS NULL", isNotNull = "IS NOT NULL" }
    public var op: Operator
    public var value: String
    public init(_ op: Operator, _ value: String = "") { self.op = op; self.value = value }

    /// Czy wartość spełnia oczekiwanie (LIKE z `%` i `_`, z rozróżnianiem wielkości liter jak w Oracle; `%` i `_` obejmują
    /// też znaki nowej linii — wielolinijkowe DBMS_OUTPUT).
    public func matches(_ actual: String?) -> Bool {
        switch op {
        case .isNull: return actual == nil || actual == ""
        case .isNotNull: return !(actual == nil || actual == "")
        case .equals: return actual == value
        case .inList: return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(actual ?? "")
        case .like:
            let pattern = "(?s)^" + NSRegularExpression.escapedPattern(for: value).replacingOccurrences(of: "%", with: ".*").replacingOccurrences(of: "_", with: ".") + "$"
            return (actual ?? "").range(of: pattern, options: [.regularExpression]) != nil
        }
    }

    public var description: String { op == .isNull || op == .isNotNull ? op.rawValue : "\(op.rawValue) \(value)" }
}

/// Zmienna testu: wartość wejściowa (albo odwołanie do zmiennej globalnej `&nazwa`) i oczekiwanie.
public struct TestCaseVariable: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var type: TestVariableType
    public var input: String?
    public var expected: TestExpectation?
    public init(name: String, type: TestVariableType, input: String? = nil, expected: TestExpectation? = nil) {
        self.name = name; self.type = type; self.input = input; self.expected = expected
    }
}

/// Test zestawu: blok (jak w oknie testu), zmienne, oczekiwane DBMS_OUTPUT (wzorzec LIKE) i limit czasu.
public struct TestCase: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var block: String
    public var variables: [TestCaseVariable]
    public var expectedOutput: String?
    public var maxSeconds: Double?
    public init(name: String, block: String, variables: [TestCaseVariable] = []) { self.name = name; self.block = block; self.variables = variables }
}

/// Zestaw testów (plik `.pts`, JSON): zmienne globalne i testy.
public struct TestSet: Sendable, Codable, Hashable {
    public var format = "pelikan-test-set"
    public var version = 1
    public var name: String
    public var globals: [String: String] = [:]
    public var cases: [TestCase] = []
    public init(name: String) { self.name = name }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> TestSet {
        let s = try JSONDecoder().decode(TestSet.self, from: data)
        guard s.format == "pelikan-test-set" else { throw CommandError.notAvailable(L10n.tr("To nie jest plik zestawu testów Pelikana")) }
        return s
    }
}

public struct TestCaseResult: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var passed: Bool
    public var failures: [String]
    public var seconds: Double
    public var output: [String]
}

/// Test Manager (UG 24.16, PD-TOOL-018): wykonuje testy zestawu blokami jak okno testu, w osobnej sesji.
@MainActor
public enum TestManager {
    /// `&nazwa` w wartości wejściowej → wartość zmiennej globalnej.
    nonisolated public static func resolve(_ input: String, globals: [String: String]) -> String {
        var out = input
        for (k, v) in globals.sorted(by: { $0.key.count > $1.key.count }) {
            out = out.replacingOccurrences(of: "&" + k, with: v, options: .caseInsensitive)
        }
        return out
    }

    public static func run(_ set: TestSet, connectionID: UUID, in ws: Workspace, progress: ((TestCaseResult) -> Void)? = nil) async -> [TestCaseResult] {
        var results: [TestCaseResult] = []
        for c in set.cases {
            let r = await run(c, globals: set.globals, connectionID: connectionID, in: ws)
            results.append(r)
            progress?(r)
        }
        return results
    }

    public static func run(_ c: TestCase, globals: [String: String], connectionID: UUID, in ws: Workspace) async -> TestCaseResult {
        // Dokument testu poza listą okien — własna sesja, zamykana po teście (zmiany wycofane).
        let doc = Document(kind: .test, ordinal: 0, text: c.block)
        doc.connectionID = connectionID
        doc.testVariables = c.variables.map { v in
            let value = v.input.map { resolve($0, globals: globals) }
            return TestVariable(name: v.name, type: v.type, value: value ?? "", isNull: value == nil)
        }
        // Osobna sesja także w trybie dual/single — sesja główna (transakcje okien) zostaje nietknięta.
        let key = SessionKey(connectionID: connectionID, purpose: .tool("tests-\(doc.id.description.prefix(8))"))
        doc.sessionPurpose = key.purpose
        var failures: [String] = []
        let started = Date()
        do {
            _ = try await TestRunner.execute(doc, in: ws, allowAutoCommit: false)
        } catch {
            failures.append(L10n.tr("Błąd: \(error.localizedDescription)"))
        }
        let seconds = Date().timeIntervalSince(started)
        try? await ws.sessions.existingSession(key)?.rollback()
        await ws.sessions.close(key)
        if failures.isEmpty {
            for v in c.variables {
                guard let exp = v.expected else { continue }
                let actual = doc.testVariables.first { $0.name.caseInsensitiveCompare(v.name) == .orderedSame }
                let value = actual.flatMap { $0.isNull ? nil : $0.value }
                if !exp.matches(value) { failures.append(L10n.tr("\(v.name): oczekiwano \(exp.description), jest \(value ?? "NULL")")) }
            }
            if let pattern = c.expectedOutput, !pattern.isEmpty,
               !TestExpectation(.like, pattern).matches(doc.output.joined(separator: "\n")) {
                failures.append(L10n.tr("DBMS_OUTPUT nie pasuje do wzorca \(pattern)"))
            }
            if let max = c.maxSeconds, seconds > max { failures.append(L10n.tr("Czas \(String(format: "%.2f", seconds)) s przekracza \(max) s")) }
        }
        return TestCaseResult(id: c.id, name: c.name, passed: failures.isEmpty, failures: failures, seconds: seconds, output: doc.output)
    }
}

/// Komendy Test Managera.
@MainActor
enum TestManagerCommands {
    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "tools.testManager", title: L10n.tr("Test Manager"), category: .tools,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zestawy testów: bloki z wartościami wejściowymi i oczekiwanymi (=, LIKE, IN, NULL), zmienne globalne, DBMS_OUTPUT, limit czasu; uruchamianie i przejście do okna testu."),
                                      feature: "PD-TOOL-018"),
                    validate: { $0.sessions.mainConnectionID != nil }) { ctx in
                ctx.ui?.showTestManager()
                return .ok
            },
            Command(CommandDescriptor(id: "testManager.run", title: L10n.tr("Uruchom zestaw testów"), category: .tools, submenu: L10n.tr("Test Manager"),
                                      parameters: [CommandParameter("file", .string, required: true, L10n.tr("Plik zestawu testów (.pts)"))],
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Uruchamia zestaw testów z pliku i zwraca wynik każdego testu (zmiany testów są wycofywane)."), inMenu: false,
                                      feature: "PD-TOOL-018")) { ctx in
                guard let path = ctx.arguments.string("file"), let conn = ctx.workspace.sessions.mainConnectionID else { throw CommandError.missingArgument("file") }
                let set = try TestSet.decode(Data(contentsOf: URL(fileURLWithPath: path)))
                let results = await TestManager.run(set, connectionID: conn, in: ctx.workspace)
                return CommandResult(message: L10n.tr("Udane: \(results.filter(\.passed).count) z \(results.count)"),
                                     value: .array(results.map { .object(["name": .string($0.name), "passed": .bool($0.passed), "failures": .array($0.failures.map { .string($0) })]) }))
            },
        ]
    }
}
