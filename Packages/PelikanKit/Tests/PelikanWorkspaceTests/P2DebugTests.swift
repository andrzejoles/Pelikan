import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Debuger P2 bez bazy (PD-DBG-005, PD-DBG-008, PD-DBG-011)")
struct P2DebugTests {
    @Test("Plik punktów: jednostki, blok okna testu z plikiem, kody błędów; dopisanie bez duplikatów i zastąpienie")
    func breakpointFile() throws {
        let ws = Workspace()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bp-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tst = dir.appendingPathComponent("a.tst")
        let doc = ws.newDocument(.test, text: "begin null; end;")
        doc.fileURL = tst
        let unsaved = ws.newDocument(.test, text: "begin null; end;")
        var unit = Breakpoint(owner: "HR", unit: "PKG", type: .packageBody, line: 12)
        unit.condition = "i > 3"
        ws.breakpoints = [unit, Breakpoint(document: doc.id.raw, line: 1), Breakpoint(document: unsaved.id.raw, line: 1)]
        ws.errorBreakpoints = [1403]
        let data = try ws.exportBreakpoints()
        ws.breakpoints = []
        ws.errorBreakpoints = [20001]
        #expect(try ws.importBreakpoints(data, replace: false) == 2)
        #expect(ws.breakpoints.first { $0.unit == "PKG" }?.condition == "i > 3")
        #expect(ws.breakpoints.contains { $0.document == doc.id.raw })
        #expect(ws.errorBreakpoints == [1403, 20001])
        #expect(try ws.importBreakpoints(data, replace: false) == 0)
        #expect(try ws.importBreakpoints(data, replace: true) == 2 && ws.errorBreakpoints == [1403])
        #expect(throws: (any Error).self) { try ws.importBreakpoints(Data("{}".utf8), replace: true) }
    }

    @Test("NEVER wygrywa z ALWAYS, potem preferencja; wpisy user@baza i [SCHEMAT.]OBIEKT")
    func debugInfoLists() throws {
        let ws = Workspace()
        let prod = ConnectionDefinition(name: "PRD", target: ConnectionTarget(user: "app", connectString: "prod1/svc"))
        let dev = ConnectionDefinition(name: "DEV", target: ConnectionTarget(user: "scott", connectString: "devdb"))
        try ws.connections.upsert(prod, password: nil)
        try ws.connections.upsert(dev, password: nil)
        let pkg = DBObject(owner: "HR", name: "PKG_A", type: .packageBody)
        #expect(!ws.addsDebugInfo(object: pkg, connectionID: dev.id))
        ws.settings.debugInfoAlways = ["scott@dev*"]
        ws.settings.debugInfoNever = ["*@prod*", "HR.PKG_SECRET*"]
        #expect(ws.addsDebugInfo(object: pkg, connectionID: dev.id))
        #expect(!ws.addsDebugInfo(object: pkg, connectionID: prod.id))
        #expect(!ws.addsDebugInfo(object: DBObject(owner: "HR", name: "PKG_SECRET_X", type: .package), connectionID: dev.id))
        ws.settings.debugInfoAlways = ["PKG_A"]
        ws.settings.debugInfoNever = []
        #expect(ws.addsDebugInfo(object: pkg, connectionID: prod.id))
        ws.settings.debugInfoOnCompile = true
        #expect(ws.addsDebugInfo(object: DBObject(owner: "HR", name: "INNY", type: .procedure), connectionID: prod.id))
    }

    @Test("Słowo pod myszą: ścieżka z kropką do wskazanego członu, bez :zmiennych; wyszukanie zmiennej i globalnej pakietu")
    func hoverWord() {
        let text = "  v_total := r.ename || :b1;"
        func at(_ s: String) -> Int { (text as NSString).range(of: s).location }
        #expect(DebugHover.word(in: text, at: at("total")) == "v_total")
        #expect(DebugHover.word(in: text, at: at("ename") + 2) == "r.ename")
        #expect(DebugHover.word(in: text, at: at("r.")) == "r")
        #expect(DebugHover.word(in: text, at: at("b1")) == nil)
        #expect(DebugHover.word(in: text, at: at(":=")) == nil)
        let vars = [DebugVariable(name: "r", path: "r", value: "(rekord)", type: "emp%rowtype",
                                  children: [DebugVariable(name: "ename", path: "r.ename", value: "KING", type: "")]),
                    DebugVariable(name: "Globalne", path: "#pkg", value: "", type: "",
                                  children: [DebugVariable(name: "g_x", path: "pkg.g_x", value: "7", type: "")])]
        #expect(Workspace.findVariable("r.ename", in: vars)?.value == "KING")
        #expect(Workspace.findVariable("g_x", in: vars)?.value == "7")
        #expect(Workspace.findVariable("brak", in: vars) == nil)
    }
}

@Suite("Statystyki i profiler bez bazy (PD-OPT-004, PD-OPT-005, PD-OPT-006)")
struct P2ProfilerTests {
    @Test("Wiersze statystyk: wszystkie niezerowe albo wybrane z sumą; filtr; CSV")
    func statisticRows() {
        let last = [SessionStatistic(name: "consistent gets", value: 10), SessionStatistic(name: "db block gets", value: 2)]
        let totals = ["consistent gets": 30.0, "db block gets": 2, "physical reads": 4]
        #expect(Profiler.rows(last: last, totals: totals, selected: []).map(\.name) == ["consistent gets", "db block gets"])
        let chosen = Profiler.rows(last: last, totals: totals, selected: ["Physical Reads", "consistent gets"])
        #expect(chosen.map(\.name) == ["consistent gets", "physical reads"] && chosen[1].last == 0 && chosen[1].total == 4)
        #expect(Profiler.rows(last: last, totals: totals, selected: [], filter: "BLOCK").map(\.name) == ["db block gets"])
        #expect(Profiler.csv(chosen) == "\"statystyka\",\"ostatnie\",\"suma\"\n\"consistent gets\",10,30\n\"physical reads\",0,4\n")
    }

    @Test("Drzewo HPROF: korzenie bez wywołujących, dzieci wg czasu, rekurencja przerwana; jednostki czasu i próg udziału")
    func tree() {
        func f(_ s: Int, _ name: String, _ t: Double, _ kids: [Int]) -> ProfilerFunction {
            ProfilerFunction(symbol: s, owner: "HR", module: "PKG", type: "PACKAGE BODY", function: name, line: 1, calls: 1, functionTime: t, subtreeTime: t, children: kids)
        }
        let r = ProfilerReport(kind: .hierarchical, run: 1, totalTime: 0, lines: [],
                               functions: [f(1, "MAIN", 100, [2, 3]), f(2, "A", 20, [2]), f(3, "B", 60, [])])
        let tree = Profiler.callTree(r)
        #expect(tree.map(\.function.function) == ["MAIN"])
        #expect(tree[0].children?.map(\.function.function) == ["B", "A"])
        #expect(tree[0].children?.last?.children == nil)
        #expect(ProfilerTimeUnit.milliseconds.format(nanoseconds: 1_500_000) == "1.500" && ProfilerTimeUnit.microseconds.format(nanoseconds: 2_000) == "2")
        func line(_ n: Int, _ t: Double) -> ProfilerLine {
            ProfilerLine(unitNumber: 1, unitOwner: "HR", unitName: "P", unitType: "PROCEDURE", line: n, occurrences: 1, totalTime: t, minTime: t, maxTime: t, text: "")
        }
        let lr = ProfilerReport(kind: .lines, run: 1, totalTime: 100, lines: [line(1, 90), line(2, 9), line(3, 1)], functions: [])
        #expect(Profiler.lines(lr, minShare: 5).map(\.line) == [1, 2] && Profiler.lines(lr, minShare: 0).count == 3)
    }
}
