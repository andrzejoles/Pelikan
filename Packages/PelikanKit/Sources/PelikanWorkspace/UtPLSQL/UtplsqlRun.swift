import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Observation
import PelikanDB

/// Stan elementu wyników utPLSQL.
public enum UtStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case pending, running, success, failure, error, disabled

    public var displayName: String {
        switch self {
        case .pending: L10n.tr("oczekuje")
        case .running: L10n.tr("w toku")
        case .success: L10n.tr("sukces")
        case .failure: L10n.tr("niepowodzenie")
        case .error: L10n.tr("błąd")
        case .disabled: L10n.tr("wyłączony")
        }
    }
}

/// Niespełnione oczekiwanie testu (`ut.expect`): opis, komunikat z wartością oczekiwaną i otrzymaną, miejsce wywołania.
public struct UtExpectation: Sendable, Hashable, Codable {
    public var description: String
    public var message: String
    public var caller: String

    /// Wartość otrzymana i oczekiwana z komunikatu utPLSQL (`Actual: … was expected to equal: …`, także dla kursorów
    /// z sekcją `Diff:` — wiersze `Row No. n - Actual:/Expected:`) do porównania obok siebie (UT-RES-002).
    public var comparison: (actual: String, expected: String)? {
        let lines = message.components(separatedBy: "\n")
        let rows = lines.compactMap { l -> (Bool, String)? in
            let t = l.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("Row No.") || t.hasPrefix("Column") else { return nil }
            if let r = t.range(of: " - Actual:") { return (true, t[..<r.lowerBound] + ":" + t[r.upperBound...].trimmingCharacters(in: .whitespaces)) }
            if let r = t.range(of: " - Expected:") { return (false, t[..<r.lowerBound] + ":" + t[r.upperBound...].trimmingCharacters(in: .whitespaces)) }
            return nil
        }
        if !rows.isEmpty {
            return (rows.filter(\.0).map(\.1).joined(separator: "\n"), rows.filter { !$0.0 }.map(\.1).joined(separator: "\n"))
        }
        let first = lines.first ?? ""
        guard let a = first.range(of: "Actual: "), let e = first.range(of: #" was expected (not )?to [a-z_ ]+?:? "#, options: .regularExpression),
              a.upperBound <= e.lowerBound else { return nil }
        let actual = String(first[a.upperBound..<e.lowerBound])
        let expected = String(first[e.upperBound...])
        return (actual, expected.isEmpty ? String(first[e]).trimmingCharacters(in: .whitespaces) : expected)
    }

    public static func == (a: Self, b: Self) -> Bool { a.description == b.description && a.message == b.message && a.caller == b.caller }
    public func hash(into h: inout Hasher) { h.combine(message); h.combine(caller) }
}

/// Sortowanie drzewa wyników (UT-RES-001): kolejność wykonania, nazwa, czas (malejąco), status (najpierw błędy).
public enum UtSortOrder: String, Sendable, CaseIterable {
    case execution, name, time, status

    public var displayName: String {
        switch self {
        case .execution: L10n.tr("Kolejność wykonania")
        case .name: L10n.tr("Nazwa")
        case .time: L10n.tr("Czas")
        case .status: L10n.tr("Status")
        }
    }

    public func sorted(_ nodes: [UtNode]) -> [UtNode] {
        let children = nodes.map { n -> UtNode in
            var c = n
            c.children = n.children.map(sorted)
            return c
        }
        func rank(_ s: UtStatus) -> Int {
            switch s { case .error: 0; case .failure: 1; case .disabled: 4; case .success: 5; default: 3 }
        }
        switch self {
        case .execution: return children
        case .name: return children.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .time: return children.sorted { ($0.executionTime ?? 0) > ($1.executionTime ?? 0) }
        case .status: return children.sorted { rank($0.status) < rank($1.status) }
        }
    }
}

/// Węzeł drzewa wyników: suita (logiczna albo pakiet, kontekst) albo test.
public struct UtNode: Sendable, Hashable, Identifiable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable { case suite, test }
    /// Ścieżka utPLSQL (np. `pelikan.przyklady.test_emp_api.zwraca_pensje`).
    public var id: String
    public var kind: Kind
    public var name: String
    public var description: String
    public var owner: String
    public var objectName: String
    public var procedureName: String
    public var status: UtStatus = .pending
    public var executionTime: Double?
    public var expectations: [UtExpectation] = []
    public var errorStack = ""
    public var serverOutput = ""
    public var warnings = ""
    public var disabledReason = ""
    public var children: [UtNode]?

    /// Ścieżka do ponownego uruchomienia: `schemat:ścieżka.suity` (identyfikator to ścieżka suity bez schematu).
    public var runPath: String { owner.isEmpty ? id : "\(owner.lowercased()):\(id)" }

    /// Tekst do wyświetlenia (opis z adnotacji albo nazwa).
    public var title: String { description.isEmpty ? name : description }
}

/// Liczniki przebiegu.
public struct UtCounter: Sendable, Hashable, Codable {
    public var success = 0
    public var failure = 0
    public var error = 0
    public var disabled = 0
    public var warning = 0
    public var total: Int { success + failure + error + disabled }
}

/// Przebieg testów utPLSQL (UG wtyczki, PROMPT §6): drzewo aktualizowane na żywo ze zdarzeń reportera.
@MainActor
@Observable
public final class UtplsqlRun: Identifiable {
    public let id = UUID()
    public let paths: [String]
    public let started = Date()
    public private(set) var roots: [UtNode] = []
    public private(set) var counter = UtCounter()
    public private(set) var totalTests = 0
    public private(set) var finishedTests = 0
    public private(set) var currentTest: String?
    public private(set) var executionTime: Double?
    public private(set) var finished = false
    public private(set) var errorStack = ""
    public private(set) var serverOutput = ""
    /// Błąd uruchomienia (np. brak utPLSQL) — przebieg nie wystartował.
    public internal(set) var failure: String?
    /// Raport pokrycia HTML (gdy uruchomiono z pokryciem).
    public internal(set) var coverageHTML: String?
    /// Pokrycie linii: obiekt (OWNER.NAZWA) → linie pokryte / niepokryte (z reportera Sonar).
    public internal(set) var coverage: [String: CoverageLines] = [:]

    init(paths: [String]) { self.paths = paths }

    /// Wszystkie testy (liście) w kolejności drzewa.
    public var tests: [UtNode] {
        func walk(_ n: [UtNode]) -> [UtNode] { n.flatMap { $0.kind == .test ? [$0] : walk($0.children ?? []) } }
        return walk(roots)
    }

    /// Ścieżki testów zakończonych niepowodzeniem albo błędem (ponowne uruchomienie nieudanych).
    public var failedPaths: [String] { tests.filter { $0.status == .failure || $0.status == .error }.map(\.runPath) }

    /// Zmiany względem wcześniejszego przebiegu (UT-RES-003): ścieżka testu, stan wcześniej (nil — nowy) i teraz.
    public func compare(with earlier: UtplsqlRun) -> [(path: String, before: UtStatus?, after: UtStatus)] {
        let old = Dictionary(earlier.tests.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        return tests.compactMap { t in
            let b = old[t.id]
            return b == t.status ? nil : (t.id, b, t.status)
        }
    }

    // MARK: Zdarzenia

    func apply(_ e: UtEvent) {
        switch e.type {
        case "pre-run":
            roots = e.items
            totalTests = e.totalTests
        case "pre-test":
            currentTest = e.id
            update(e.id) { $0.status = .running }
        case "post-test", "post-suite":
            update(e.id) { n in
                n.executionTime = e.executionTime
                n.errorStack = e.errorStack
                n.serverOutput = e.serverOutput
                n.warnings = e.warnings
                n.expectations = e.expectations
                if n.kind == .test || e.type == "post-test" {
                    n.status = e.counter.error > 0 ? .error : e.counter.failure > 0 ? .failure : e.counter.disabled > 0 ? .disabled : .success
                } else {
                    n.status = e.counter.error > 0 ? .error : e.counter.failure > 0 ? .failure : (e.counter.success == 0 && e.counter.disabled > 0) ? .disabled : .success
                }
            }
            if e.type == "post-test" {
                finishedTests += 1
                currentTest = nil
            }
        case "post-run":
            counter = e.counter
            executionTime = e.executionTime
            errorStack = e.errorStack
            serverOutput = e.serverOutput
            // `finished` ustawia uruchamiający po pobraniu raportów pokrycia.
        default:
            break
        }
    }

    func markFinished(error: String? = nil) {
        if let error { failure = error }
        finished = true
        currentTest = nil
    }

    private func update(_ id: String, _ change: (inout UtNode) -> Void) {
        func walk(_ nodes: inout [UtNode]) -> Bool {
            for i in nodes.indices {
                if nodes[i].id == id { change(&nodes[i]); return true }
                if var c = nodes[i].children, walk(&c) { nodes[i].children = c; return true }
            }
            return false
        }
        _ = walk(&roots)
    }
}

/// Linie pokrycia obiektu.
public struct CoverageLines: Sendable, Hashable, Codable {
    public var covered: Set<Int>
    public var uncovered: Set<Int>
    /// Linie pokryte częściowo (nie wszystkie gałęzie/bloki — `branchesToCover` > `coveredBranches`; UT-COV-002).
    public var partial: Set<Int> = []
    public var percent: Double {
        let all = covered.count + uncovered.count
        return all == 0 ? 0 : Double(covered.count) * 100 / Double(all)
    }
}

/// Zdarzenie reportera `ut_realtime_reporter` (jeden dokument XML).
struct UtEvent: Sendable {
    var type = ""
    var id = ""
    var items: [UtNode] = []
    var totalTests = 0
    var executionTime: Double?
    var counter = UtCounter()
    var errorStack = ""
    var serverOutput = ""
    var warnings = ""
    var expectations: [UtExpectation] = []

    /// Parser dokumentu zdarzenia (struktura z ut_realtime_reporter, utPLSQL 3.x).
    static func parse(_ xml: String) -> UtEvent? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let d = Delegate()
        let p = XMLParser(data: data)
        p.delegate = d
        guard p.parse() else { return nil }
        return d.event
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var event = UtEvent()
        var text = ""
        /// Stos węzłów drzewa z `pre-run` (suity i testy).
        var stack: [UtNode] = []
        var path: [String] = []
        var expectation: UtExpectation?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            path.append(name)
            text = ""
            switch name {
            case "event": event.type = attributes["type"] ?? ""
            case "suite", "test":
                let id = attributes["id"] ?? ""
                if event.type == "pre-run" {
                    stack.append(UtNode(id: id, kind: name == "suite" ? .suite : .test, name: "", description: "", owner: "", objectName: "", procedureName: "",
                                        children: name == "suite" ? [] : nil))
                } else {
                    event.id = id
                }
            case "expectation": expectation = UtExpectation(description: "", message: "", caller: "")
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = path.count >= 2 ? path[path.count - 2] : ""
            path.removeLast()
            defer { text = "" }
            if event.type == "pre-run", !stack.isEmpty {
                switch name {
                case "name": stack[stack.count - 1].name = value
                case "description": stack[stack.count - 1].description = value
                case "ownerName": stack[stack.count - 1].owner = value
                case "objectName": stack[stack.count - 1].objectName = value
                case "procedureName": stack[stack.count - 1].procedureName = value
                case "disabled": if value == "true" { stack[stack.count - 1].status = .disabled }
                case "disabledReason": stack[stack.count - 1].disabledReason = value
                case "suite", "test":
                    let node = stack.removeLast()
                    if stack.isEmpty { event.items.append(node) } else { stack[stack.count - 1].children?.append(node) }
                default: break
                }
                if name == "totalNumberOfTests" { event.totalTests = Int(value) ?? 0 }
                return
            }
            if let e = expectation {
                switch name {
                case "description": expectation?.description = value
                case "message": expectation?.message = value
                case "caller": expectation?.caller = value
                case "expectation": event.expectations.append(e); expectation = nil
                default: break
                }
                if name != "expectation" { return }
            }
            switch name {
            case "totalNumberOfTests": event.totalTests = Int(value) ?? event.totalTests
            case "executionTime": event.executionTime = Double(value)
            case "errorStack": event.errorStack = value
            case "serverOutput": event.serverOutput = value
            case "warnings": event.warnings = value
            case "success" where parent == "counter": event.counter.success = Int(value) ?? 0
            case "failure" where parent == "counter": event.counter.failure = Int(value) ?? 0
            case "error" where parent == "counter": event.counter.error = Int(value) ?? 0
            case "disabled" where parent == "counter": event.counter.disabled = Int(value) ?? 0
            case "warning" where parent == "counter": event.counter.warning = Int(value) ?? 0
            default: break
            }
        }
    }
}
