import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("utPLSQL na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(2)))
struct UtplsqlTests {
    func workspace() throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    func wait(_ run: UtplsqlRun) async {
        for _ in 0..<600 where !run.finished { try? await Task.sleep(for: .milliseconds(100)) }
    }

    @Test("Wersja, przebieg na żywo: drzewo suit, liczniki, nieudany test z oczekiwaniem")
    func run() async throws {
        let (ws, id) = try workspace()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        #expect(await UtplsqlRunner.version(s)?.hasPrefix("v.3") == true)
        let schema = try await ws.metadata()!.currentSchema()
        let run = try await UtplsqlRunner.start(paths: [schema], in: ws, connectionID: id)
        await wait(run)
        #expect(run.failure == nil, "\(run.failure ?? "")")
        #expect(run.finished && run.totalTests >= 5)
        #expect(run.counter.failure >= 1 && run.counter.success >= 4)
        #expect(run.roots.first?.id == "pelikan")
        let failed = run.tests.first { $0.status == .failure }
        #expect(failed?.expectations.first?.message.contains("was expected to equal") == true)
        #expect(run.failedPaths.contains { $0.hasSuffix("deliberately_failing") })
        #expect(run.tests.allSatisfy { $0.executionTime != nil || $0.status == .disabled })
        await ws.sessions.disconnectAll()
    }

    @Test("Pokrycie: linie pokryte i niepokryte pakietu, raport HTML")
    func coverage() async throws {
        let (ws, id) = try workspace()
        let schema = try await ws.metadata()!.currentSchema()
        let run = try await UtplsqlRunner.start(paths: ["\(schema).test_emp_api"], coverageSchemes: [schema], in: ws, connectionID: id)
        await wait(run)
        #expect(run.failure == nil, "\(run.failure ?? "")")
        #expect(run.coverage.contains { $0.key.contains("EMP_API") && !$0.value.covered.isEmpty })
        #expect(run.coverageHTML?.contains("<html") == true)
        // Pokrycie na marginesie okna programu pakietu (linie dokumentu ciała).
        try await ws.invoke("ob.edit", CommandArguments(["object": .string("emp_api"), "type": .string("PACKAGE")]))
        let doc = try #require(ws.activeDocument)
        let lines = ws.coverageLines(in: doc)
        #expect(!lines.covered.isEmpty)
        let bodyStart = ProgramCompiler.units(in: doc.text).first { $0.type == .packageBody }?.line ?? 0
        #expect(lines.covered.allSatisfy { $0 > bodyStart })
        #expect(ws.coverageStatus(in: doc)?.hasPrefix("Pokrycie ") == true)
        await ws.sessions.disconnectAll()
    }

    @Test("Opcje przebiegu: pokrycie tylko obiektów z listy uwzględnionych; pominięte nie trafiają do raportu (UT-COV-001)")
    func coverageOptions() async throws {
        let (ws, id) = try workspace()
        let schema = try await ws.metadata()!.currentSchema()
        let run = try await UtplsqlRunner.start(paths: ["\(schema).test_emp_api"], coverageSchemes: [schema], include: ["emp_api"], in: ws, connectionID: id)
        await wait(run)
        #expect(run.failure == nil, "\(run.failure ?? "")")
        #expect(!run.coverage.isEmpty && run.coverage.keys.allSatisfy { $0.hasSuffix(".EMP_API") }, "\(run.coverage.keys)")
        let excluded = try await UtplsqlRunner.start(paths: ["\(schema).test_emp_api"], coverageSchemes: [schema], exclude: ["emp_api"], in: ws, connectionID: id)
        await wait(excluded)
        #expect(!excluded.coverage.keys.contains { $0.hasSuffix(".EMP_API") }, "\(excluded.coverage.keys)")
        await ws.sessions.disconnectAll()
    }

    @Test("Z edytora: test pod kursorem w oknie programu pakietu testowego; ponownie nieudane")
    func editorAndRerun() async throws {
        let (ws, _) = try workspace()
        try await ws.invoke("ob.edit", CommandArguments(["object": .string("test_emp_api"), "type": .string("PACKAGE")]))
        let doc = try #require(ws.activeDocument)
        let ns = doc.text as NSString
        // Kursor w ciele procedury deliberately_failing.
        let body = ns.range(of: "package body", options: .caseInsensitive).location
        let at = ns.range(of: "deliberately_failing", options: .caseInsensitive, range: NSRange(location: body, length: ns.length - body)).location + 3
        doc.selectedRange = at..<at
        let path = await UtplsqlCommands.editorPath(ws)
        #expect(path?.hasSuffix("test_emp_api.deliberately_failing") == true)
        try await ws.invoke("utplsql.runEditor")
        let run = try #require(ws.lastUtplsqlRun)
        await wait(run)
        #expect(run.totalTests == 1 && run.counter.failure == 1)
        try await ws.invoke("utplsql.rerunFailed")
        let again = try #require(ws.lastUtplsqlRun)
        await wait(again)
        #expect(again.id != run.id && again.totalTests == 1)
        await ws.sessions.disconnectAll()
    }

    @Test("Eksplorator: drzewo suit i testów; generator: szkielet się kompiluje i uruchamia; przejście pakiet ↔ test")
    func explorerGeneratorNavigation() async throws {
        let (ws, id) = try workspace()
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let tree = try await UtplsqlExplorer.load(owner: schema, metadata: m)
        func flat(_ n: [UtSuiteItem]) -> [UtSuiteItem] { n.flatMap { [$0] + flat($0.children ?? []) } }
        let tests = flat(tree).filter { $0.kind == .test }
        #expect(tree.first?.path == "pelikan" && tests.count >= 5)
        #expect(tests.allSatisfy { $0.object == "TEST_EMP_API" && $0.line > 0 })

        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        _ = try await s.execute("create or replace package pelikan_gen_p as procedure a(x number); function b return number; end;")
        try await ws.invoke("utplsql.generateTest", CommandArguments(["object": .string("pelikan_gen_p"), "type": .string("PACKAGE")]))
        let doc = try #require(ws.activeDocument)
        #expect(doc.text.contains("create or replace package test_pelikan_gen_p"))
        let r = try await ProgramCompiler.compile(doc, in: ws)
        #expect(r.ok && r.compiled == 2, "\(r.messages.map(\.text))")
        let run = try await UtplsqlRunner.start(paths: ["\(schema).test_pelikan_gen_p"], in: ws, connectionID: id)
        await wait(run)
        #expect(run.totalTests == 2 && run.counter.failure == 2)

        let toTest = try await UtplsqlExplorer.counterpart(of: "EMP_API", owner: schema, metadata: m)
        #expect(toTest?.name == "TEST_EMP_API")
        let back = try await UtplsqlExplorer.counterpart(of: "TEST_EMP_API", owner: schema, metadata: m)
        #expect(back?.name == "EMP_API")
        for o in ["package test_pelikan_gen_p", "package pelikan_gen_p"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }

    @Test("Eksport JUnit i Cobertura, skrypt CLI bez hasła")
    func exports() async throws {
        let (ws, id) = try workspace()
        let schema = try await ws.metadata()!.currentSchema()
        let junit = try await UtplsqlRunner.report(paths: ["\(schema).test_emp_api"], format: .junit, coverageSchemes: [], in: ws, connectionID: id)
        #expect(junit.contains("<testsuites") && junit.contains("failures=\"1\""))
        let teamcity = try await UtplsqlRunner.report(paths: ["\(schema).test_emp_api"], format: .teamcity, coverageSchemes: [], in: ws, connectionID: id)
        #expect(teamcity.contains("##teamcity[testStarted"))
        let cobertura = try await UtplsqlRunner.report(paths: ["\(schema).test_emp_api"], format: .coberturaCoverage, coverageSchemes: [schema], in: ws, connectionID: id)
        #expect(cobertura.contains("<coverage"))
        let r = try await ws.invoke("utplsql.cliScript", CommandArguments(["path": .string("\(schema).test_emp_api")]))
        let sql = r.value?.objectValue?["sql"]?.stringValue ?? ""
        #expect(sql.contains("ut_junit_reporter()") && sql.contains("spool utplsql-junit.xml"))
        let c = TestDatabase.config!
        #expect(!sql.contains(c.password) && !(r.value?.objectValue?["shell"]?.stringValue ?? "").contains(c.password))
        await ws.sessions.disconnectAll()
    }

    @Test("Debugowanie testu pod kursorem: zatrzymanie w procedurze testowej; historia i porównanie przebiegów")
    func debugAndHistory() async throws {
        let (ws, id) = try workspace()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        _ = try? await s.execute("alter package test_emp_api compile debug body")
        try await ws.invoke("ob.edit", CommandArguments(["object": .string("test_emp_api"), "type": .string("PACKAGE")]))
        let doc = try #require(ws.activeDocument)
        let ns = doc.text as NSString
        let body = ns.range(of: "package body", options: .caseInsensitive).location
        let at = ns.range(of: "procedure get_salary_existing", options: .caseInsensitive, range: NSRange(location: body, length: ns.length - body)).location + 12
        doc.selectedRange = at..<at
        try await ws.invoke("utplsql.debugTest")
        let test = try #require(ws.documents.last { $0.kind == .test })
        let d = ws.debugger(for: test)
        #expect(d.state == .paused && d.location?.name == "TEST_EMP_API")
        await d.stop()
        ws.breakpoints = []

        let schema = try await ws.metadata()!.currentSchema()
        let a = try await UtplsqlRunner.start(paths: ["\(schema).test_emp_api"], in: ws, connectionID: id)
        await wait(a)
        let b = try await UtplsqlRunner.start(paths: ["\(schema).test_emp_api.nested_context_#2"], in: ws, connectionID: id)
        await wait(b)
        #expect(ws.utplsqlHistory.prefix(2).map(\.id) == [b.id, a.id])
        #expect(b.compare(with: a).isEmpty)          // te same stany wspólnych testów
        await ws.sessions.disconnectAll()
    }
}
