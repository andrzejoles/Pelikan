import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Etap 7 na bazie testowej: Autotrace, plany, DBA, instancja, dokumentacja", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct Stage7PlanDBTests {
    func workspace() throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    @Test("Autotrace zapytania: plan rzeczywisty (A-Rows, E-Rows, czasy, bufory), statystyki, tekst ALLSTATS; DML wycofane")
    func autotrace() async throws {
        let s = try await TestDatabase.connect()
        let n = Int(try await s.scalar("select count(*) from emp e join dept d on d.deptno = e.deptno") ?? "") ?? -1
        let total = Int(try await s.scalar("select count(*) from emp") ?? "") ?? -1
        let r = try await Autotrace.run("select e.ename, d.dname from emp e join dept d on d.deptno = e.deptno", in: s)
        #expect(r.rowsFetched == n && !r.lines.isEmpty && r.planText.contains("A-Rows"), "\(r.rowsFetched) \(r.lines.count)")
        #expect(r.lines.contains { $0.object.hasSuffix("EMP") && $0.actualRows == Int64(total) && $0.estimatedRows != nil }, "\(r.lines)")
        #expect(r.statistics.contains { $0.name == "consistent gets" || $0.name == "session logical reads" })
        let before = try await s.scalar("select sum(sal) from emp")
        let u = try await Autotrace.run("update emp set sal = sal + 1", in: s)
        #expect(u.rowsFetched == total && u.lines.first?.operation == "UPDATE STATEMENT")
        #expect(try await s.scalar("select sum(sal) from emp") == before)
        await #expect(throws: CommandError.self) { _ = try await Autotrace.run("begin null; end;", in: s) }
        await s.close()
    }

    @Test("Komenda Autotrace i porównanie planów z poprzednim (cel optymalizatora); zadanie w Task Monitorze")
    func commands() async throws {
        let (ws, id) = try workspace()
        let doc = ws.newDocument(.sql, text: "select * from emp where deptno = 10")
        doc.connectionID = id
        let r = try await ws.invoke("tools.autotrace")
        #expect(r.value?.stringValue?.contains("A-Rows") == true)
        #expect(ws.tasks.tasks.first?.kind == "autotrace" && ws.tasks.tasks.first?.status == .succeeded)
        try await ws.invoke("tools.explainPlan")
        let plan = try #require(ws.activeDocument)
        #expect(plan.kind == .explainPlan && plan.previousPlan == nil)
        plan.planGoal = .firstRows1
        try await ws.invoke("tools.explainPlan")
        #expect(plan.previousPlan != nil)
        let c = try await ws.invoke("plan.compare")
        #expect(c.message?.hasPrefix("Różnice:") == true)
        await ws.sessions.disconnectAll()
    }

    @Test("Panel DBA: wszystkie sekcje dla użytkownika z grantami, brak uprawnień jako komunikat; Instance Viewer z przyrostami")
    func dba() async throws {
        let s = try await TestDatabase.connect()
        for section in DBAPanel.Section.allCases {
            let r = await DBAPanel.load(section, in: s)
            if case .rows(let cols, _) = r { #expect(!cols.isEmpty, "\(section)") } else { Issue.record("\(section): \(r)") }
        }
        #expect(await DBAPanel.load(.tablespaces, in: s).rows.contains { $0.first == "SYSTEM" })
        let agent = try await TestDatabase.connect(agent: true)
        if case .noPrivilege = await DBAPanel.load(.tablespaces, in: agent) {} else { Issue.record("brak komunikatu o uprawnieniach") }
        let first = await InstanceViewer.snapshot(in: s)
        #expect(first.version?.contains("Oracle") == true && first.instanceName != nil && (first.sessionsTotal ?? 0) > 0)
        #expect(!first.waitClasses.isEmpty && !first.topSQL.isEmpty && !first.sga.isEmpty && first.pgaAllocatedMB != nil && first.unavailable.isEmpty)
        let second = await InstanceViewer.snapshot(in: s, previous: first)
        #expect(second.waitClasses.contains { $0.rate != nil } && (second.uptime ?? 0) > 0)
        let restricted = await InstanceViewer.snapshot(in: agent)
        #expect(!restricted.unavailable.isEmpty)
        await agent.close()
        await s.close()
    }

    @Test("Dokumentacja schematu: index, tabela z kolumnami, kluczami i indeksami, pakiet z parametrami i źródłem")
    func schemaDoc() async throws {
        let (ws, _) = try workspace()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-doc-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try await ws.invoke("tools.schemaDoc", CommandArguments(["directory": .string(dir.path), "source": .bool(true)]))
        #expect((r.value?.intValue ?? 0) > 5)
        let index = try String(contentsOf: dir.appendingPathComponent("index.html"), encoding: .utf8)
        #expect(index.contains("table-emp.html") && index.contains("package-emp_api.html"))
        let emp = try String(contentsOf: dir.appendingPathComponent("table-emp.html"), encoding: .utf8)
        #expect(emp.contains("ENAME") && emp.contains("FOREIGN KEY"))
        let pkg = try String(contentsOf: dir.appendingPathComponent("package-emp_api.html"), encoding: .utf8)
        #expect(pkg.contains("IN") && pkg.contains("PACKAGE BODY"))
        #expect(ws.tasks.tasks.first?.kind == "doc")
        await ws.sessions.disconnectAll()
    }
}
