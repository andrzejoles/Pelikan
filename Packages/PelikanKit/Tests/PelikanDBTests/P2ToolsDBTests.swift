import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Narzędzia P2 na bazie: statystyki, profiler, HTP, debuger (PD-OPT-004/005/006, PD-TEST-008, PD-DBG-005/011)",
       .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(2)))
struct P2ToolsDBTests {
    func workspace() throws -> (Workspace, ConnectionDefinition) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def)
    }

    @Test("Statystyki: suma dwóch wykonań, wybrane statystyki i CSV; profiler: historia przebiegów, otwarcie przebiegu, drzewo HPROF")
    func statisticsAndProfiler() async throws {
        let (ws, def) = try workspace()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await s.execute("""
            create or replace procedure pelikan_p2_prof(n number) is
              v number := 0;
              procedure inner_p is begin v := v + 1; end;
            begin
              for i in 1 .. n loop
                inner_p;
              end loop;
            end;
            """)
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_p2_prof(50);\nend;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        ws.activate(doc.id)
        _ = try await TestRunner.execute(doc, in: ws)
        let first = doc.statistics.first { $0.name == "opened cursors cumulative" }?.value ?? doc.statistics.first?.value ?? 0
        let name = doc.statistics.first { $0.name == "opened cursors cumulative" }?.name ?? doc.statistics.first!.name
        _ = try await TestRunner.execute(doc, in: ws)
        let second = doc.statistics.first { $0.name == name }?.value ?? 0
        #expect(doc.statisticTotals[name] == first + second)
        let rows = Profiler.rows(last: doc.statistics, totals: doc.statisticTotals, selected: [name])
        #expect(rows.map(\.name) == [name] && rows[0].total == first + second)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("stat-\(UUID().uuidString.prefix(6)).csv")
        defer { try? FileManager.default.removeItem(at: file) }
        ws.settings.selectedStatistics = [name]
        _ = try await ws.invoke("stats.export", CommandArguments(["file": .string(file.path)]))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("\"\(name)\""))

        try await ws.invoke("test.profiler", CommandArguments(["kind": .string("lines")]))
        _ = try await TestRunner.execute(doc, in: ws)
        let run = try #require(doc.profilerReport?.run)
        let runs = try await Profiler.runs(.lines, session: try await ws.session(for: doc))
        #expect(runs.first?.run == run)
        doc.profilerReport = nil
        try await ws.invoke("test.profilerOpenRun", CommandArguments(["run": .int(Int64(run))]))
        #expect(doc.profilerReport?.lines.contains { $0.unitName == "PELIKAN_P2_PROF" } == true)
        let all = Profiler.lines(doc.profilerReport!, minShare: 0).count
        #expect(Profiler.lines(doc.profilerReport!, minShare: 30).count < all)

        try await ws.invoke("test.profiler", CommandArguments(["kind": .string("hierarchical")]))
        _ = try await TestRunner.execute(doc, in: ws)
        let tree = Profiler.callTree(try #require(doc.profilerReport))
        func find(_ nodes: [ProfilerTreeNode], _ fn: String) -> ProfilerTreeNode? {
            for n in nodes { if n.function.function == fn { return n }; if let f = find(n.children ?? [], fn) { return f } }
            return nil
        }
        let proc = try #require(find(tree, "PELIKAN_P2_PROF"))
        #expect(proc.children?.contains { $0.function.function.contains("INNER_P") && $0.function.calls == 50 } == true)
        #expect(!(try await Profiler.runs(.hierarchical, session: try await ws.session(for: doc))).isEmpty)
        _ = try? await s.execute("drop procedure pelikan_p2_prof")
        await ws.sessions.disconnectAll()
    }

    @Test("Wiele obiektów: rekompilacja z listą nieprawidłowych, DDL w jednym oknie, usunięcie po jednym potwierdzeniu (PD-OB-011)")
    func multiObjects() async throws {
        let (ws, def) = try workspace()
        ws.ui = TestUI()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        let schema = try await ws.metadata()!.currentSchema()
        _ = try await s.execute("create or replace procedure pelikan_p2_m1 is begin null; end;")
        _ = try? await s.execute("create or replace procedure pelikan_p2_m2 is begin nie_ma_takiej; end;")
        let list = "\(schema).PELIKAN_P2_M1:PROCEDURE, \(schema).PELIKAN_P2_M2:PROCEDURE"
        let r = try await ws.invoke("ob.recompileSelected", CommandArguments(["objects": .string(list)]))
        #expect(r.value == .array([.string("\(schema).PELIKAN_P2_M2")]))
        _ = try await ws.invoke("ob.ddlSelected", CommandArguments(["objects": .string(list)]))
        let text = ws.activeDocument?.text.uppercased() ?? ""
        #expect(text.contains("PELIKAN_P2_M1") && text.contains("PELIKAN_P2_M2"))
        let d = try await ws.invoke("ob.dropSelected", CommandArguments(["objects": .string(list)]))
        #expect(d.value == .int(2))
        #expect(try await s.scalar("select count(*) from user_objects where object_name like 'PELIKAN_P2_M_'") == "0")
        await ws.sessions.disconnectAll()
    }

    @Test("Query Builder: kolumny podzapytania z opisu wyniku, wygenerowany SQL z podzapytaniem wykonuje się (PD-QB-001)")
    func queryBuilderSubquery() async throws {
        let (ws, def) = try workspace()
        let cols = try await ws.describeQuery("select deptno, count(*) cnt from emp group by deptno;", connection: def.id)
        #expect(cols.map(\.name) == ["DEPTNO", "CNT"])
        let source = try await ws.schemaSource(connection: def.id)
        let schema = try await ws.metadata()!.currentSchema()
        var m = QueryModel()
        let d = m.addTable(owner: schema, name: "DEPT", columns: try await source.columns(owner: schema, name: "DEPT"), foreignKeys: [])
        let s = m.addSubquery("select deptno, count(*) cnt from emp group by deptno", alias: "x", columns: cols)
        m.joins.append(QBJoin(left: d, leftColumns: ["DEPTNO"], right: s, rightColumns: ["DEPTNO"], kind: .left))
        m.fields = [QBField(table: d, expression: "DNAME"), QBField(table: s, expression: "CNT")]
        let session = try await ws.metadata()!.session()
        let (_, rows) = try await session.queryAll(m.sql())
        #expect(!rows.isEmpty)
        await ws.sessions.disconnectAll()
    }

    @Test("HTP Output: strona z HTP.P po wykonaniu; bez zbierania HTP — błąd OWA i brak strony")
    func htp() async throws {
        let (ws, def) = try workspace()
        let doc = ws.newDocument(.test, text: "begin\n  htp.p('<h1>Pelikan</h1>');\n  htp.p('linia 2');\nend;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        // Bez inicjalizacji OWA HTP.P zgłasza ORA-06502 (tak samo w SQL*Plus) — dlatego Pelikan inicjalizuje OWA.
        await #expect(throws: (any Error).self) { _ = try await TestRunner.execute(doc, in: ws) }
        #expect(doc.htpOutput == nil)
        doc.htpEnabled = true
        _ = try await TestRunner.execute(doc, in: ws)
        let page = try #require(doc.htpOutput)
        #expect(page.contains("<h1>Pelikan</h1>") && page.contains("linia 2"))
        await ws.sessions.disconnectAll()
    }

    @Test("Dymek debugera: wartość zmiennej i pola rekordu bez wywołań DBMS_DEBUG; lista ALWAYS dodaje informację debugowania")
    func hoverAndDebugInfo() async throws {
        let (ws, def) = try workspace()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        _ = try await s.execute("""
            create or replace procedure pelikan_p2_dbg is
              v_total number := 41;
              r dept%rowtype;
            begin
              select * into r from dept where rownum = 1;
              v_total := v_total + 1;
            end;
            """)
        _ = try await s.execute("alter procedure pelikan_p2_dbg compile debug")
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_p2_dbg;\nend;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        let d = ws.debugger(for: doc)
        try await d.start()
        try await d.step(.into)
        for _ in 0..<3 where d.location?.line ?? 0 < 6 { try await d.step(.over) }
        #expect(ws.debugHoverText("v_total")?.hasPrefix("v_total = 41") == true)
        #expect(ws.debugHoverText("r.deptno")?.hasPrefix("r.deptno = ") == true)
        #expect(ws.debugHoverText(":new.x") == nil)
        await d.stop()

        // Lista ALWAYS: kompilacja okna programu dodaje informację debugowania mimo wyłączonej preferencji.
        ws.settings.debugInfoOnCompile = false
        ws.settings.debugInfoAlways = ["PELIKAN_P2_DBG"]
        let prog = ws.newDocument(.program, text: "create or replace procedure pelikan_p2_dbg is\nbegin\n  null;\nend;\n/\n")
        prog.connectionID = def.id
        prog.connectionPinned = true
        _ = try await ProgramCompiler.compile(prog, in: ws)
        #expect(try await s.scalar("select plsql_debug from user_plsql_object_settings where name = 'PELIKAN_P2_DBG'") == "TRUE")
        ws.settings.debugInfoAlways = []
        ws.settings.debugInfoNever = ["PELIKAN_P2_*"]
        ws.settings.debugInfoOnCompile = true
        _ = try await ProgramCompiler.compile(prog, in: ws)
        #expect(try await s.scalar("select plsql_debug from user_plsql_object_settings where name = 'PELIKAN_P2_DBG'") == "FALSE")
        _ = try? await s.execute("drop procedure pelikan_p2_dbg")
        await ws.sessions.disconnectAll()
    }
}
