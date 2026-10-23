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
}
