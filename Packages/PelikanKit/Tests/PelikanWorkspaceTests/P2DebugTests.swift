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
