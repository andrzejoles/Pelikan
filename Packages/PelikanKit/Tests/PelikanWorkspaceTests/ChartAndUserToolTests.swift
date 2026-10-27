import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@Suite("Wykresy bez bazy")
struct ChartTests {
    let columns = [ColumnInfo(name: "DEPT", type: .varchar2, typeName: "VARCHAR2(20)"),
                   ColumnInfo(name: "SAL", type: .number, typeName: "NUMBER(7,2)"),
                   ColumnInfo(name: "COMM", type: .number, typeName: "NUMBER(7,2)")]
    let rows: [[OracleValue]] = [[.text("A"), .number("100"), .number("5")],
                                 [.text("B"), .number("200"), .null],
                                 [.text("A"), .number("50"), .number("7")],
                                 [.text("C"), .text("x"), .number("1,5")]]

    @Test("Propozycja: kategoria nieliczbowa, serie liczbowe")
    func suggest() {
        let d = ChartBuilder.suggest(columns)
        #expect(d.categoryColumn == "DEPT" && d.seriesColumns == ["SAL", "COMM"])
        // Same kolumny liczbowe: pierwsza (klucz, np. DEPTNO) jako kategoria; jedna kolumna — bez kategorii.
        let numeric = [ColumnInfo(name: "DEPTNO", type: .number, typeName: "NUMBER(2)"), ColumnInfo(name: "SUMA", type: .number, typeName: "NUMBER")]
        let n = ChartBuilder.suggest(numeric)
        #expect(n.categoryColumn == "DEPTNO" && n.seriesColumns == ["SUMA"])
        #expect(ChartBuilder.suggest([numeric[1]]).categoryColumn == nil)
    }

    @Test("Agregacje, kolejność kategorii, pominięte wartości nieliczbowe, przecinek dziesiętny")
    func build() {
        var d = ChartBuilder.suggest(columns)
        d.aggregation = .sum
        let data = ChartBuilder.build(d, columns: columns, rows: rows)
        #expect(data.categories == ["A", "B", "C"] && data.series == ["SAL", "COMM"])
        func v(_ s: String, _ c: String) -> Double? { data.points.first { $0.series == s && $0.category == c }?.value }
        #expect(v("SAL", "A") == 150 && v("SAL", "B") == 200 && v("SAL", "C") == nil)
        #expect(v("COMM", "A") == 12 && v("COMM", "C") == 1.5 && v("COMM", "B") == nil)
        #expect(data.skipped == 2)
        d.aggregation = .average
        #expect(ChartBuilder.build(d, columns: columns, rows: rows).points.first { $0.series == "SAL" && $0.category == "A" }?.value == 75)
        d.aggregation = .count
        #expect(ChartBuilder.build(d, columns: columns, rows: rows).points.first { $0.series == "COMM" && $0.category == "A" }?.value == 2)
        d.aggregation = .none
        #expect(ChartBuilder.build(d, columns: columns, rows: rows).points.first { $0.series == "SAL" && $0.category == "A" }?.value == 50)
        d.categoryColumn = nil
        #expect(ChartBuilder.build(d, columns: columns, rows: rows).categories == ["1", "2", "3", "4"])
    }

    @Test("Liczba z komórki: tylko zapis dziesiętny (bez inf, nan, 0x10)")
    func number() {
        #expect(ChartBuilder.number(.text("1 234,5")) == 1234.5 && ChartBuilder.number(.number("-2e3")) == -2000)
        #expect(ChartBuilder.number(.text("inf")) == nil && ChartBuilder.number(.text("nan")) == nil && ChartBuilder.number(.text("0x10")) == nil)
        #expect(ChartBuilder.number(.text("Inf")) == nil)
    }

    @MainActor
    @Test("Auto-odświeżanie wykresu: zakres karty musi zawierać to samo polecenie (po edycji okna — błąd, bez wykonania)")
    func reexecuteGuard() async throws {
        let ws = Workspace(drivers: [:])
        let doc = ws.newDocument(.sql, text: "select 1 from dual;\nselect 2 from dual;")
        let st = SQLExecutor.statements(text: doc.text, selection: 0..<0, scope: .allStatements, autoSelect: false)[1]
        let tab = ResultTab(title: "x", statementRange: st.start..<st.end)
        tab.statementText = st.text
        #expect(ws.statementUnchanged(tab, in: doc))
        doc.text = "select 1 from dual;\ndelete from emp;  "
        #expect(!ws.statementUnchanged(tab, in: doc))
        await #expect(throws: CommandError.self) { _ = try await ws.reexecute(tab, in: doc) }
        doc.text = "select 1 from dual;\nselect 2 from dual;"
        tab.statementText = nil
        #expect(!ws.statementUnchanged(tab, in: doc))
    }

    @Test("Szablony w katalogu danych: zapis, zastąpienie po nazwie, usunięcie")
    func templates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-charts-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        var t = ChartDefinition(name: "Pensje")
        t.kind = .pie
        try ChartTemplateStore.upsert(t, in: dir)
        t.kind = .line
        try ChartTemplateStore.upsert(t, in: dir)
        #expect(ChartTemplateStore.load(from: dir).map(\.kind) == [.line])
        try ChartTemplateStore.remove(named: "Pensje", in: dir)
        #expect(ChartTemplateStore.load(from: dir).isEmpty)
    }
}

@MainActor
@Suite("Narzędzia użytkownika bez bazy")
struct UserToolTests {
    func context() -> UserToolContext {
        var c = UserToolContext()
        c.file = "/tmp/projekt/emp_api.pck"
        c.owner = "SCOTT"; c.name = "EMP_API"; c.type = "PACKAGE"
        c.connection = "Rozwój"; c.selection = "select 1"
        return c
    }

    @Test("Rozwijanie zmiennych: najdłuższa nazwa, granica słowa, nieznane bez zmian")
    func expand() {
        let c = context()
        #expect(UserTools.expand("#filename w #filedir (#fileext)", c) == "emp_api.pck w /tmp/projekt (pck)")
        #expect(UserTools.expand("#object/#type @#connection", c) == "SCOTT.EMP_API/PACKAGE @Rozwój")
        #expect(UserTools.expand("#name2 #unknown ##name", c) == "#name2 #unknown #EMP_API")
        #expect(UserTools.expand("#FILE", c) == "/tmp/projekt/emp_api.pck")
    }

    @Test("Program bez powłoki: argumenty jako tablica (spacje i znaki powłoki dosłownie), środowisko bez zmiennych Pelikana")
    func run() async throws {
        var t = UserTool(name: "Echo")
        t.program = "echo"
        t.arguments = ["#object", "$(whoami); #selection"]
        let r = try await UserTools.run(t, context())
        #expect(r.status == 0 && r.output == "SCOTT.EMP_API $(whoami); select 1\n")
        let p = try UserTools.process(t, context())
        #expect(p.executableURL?.path == "/bin/echo" && p.environment?.keys.contains { $0.hasPrefix("PELIKAN_") } == false)
        t.arguments = ["-n", "", "#object", ""]     // pole „każdy w osobnej linii” z pustą i końcową linią
        #expect(try UserTools.process(t, context()).arguments == ["-n", "SCOTT.EMP_API"])
        t.program = "brak-takiego-programu-pelikan"
        #expect(throws: CommandError.self) { _ = try UserTools.process(t, context()) }
        // Ponad 64 KiB na stderr przed stdout — bez zakleszczenia (oba potoki czytane równolegle).
        var noisy = UserTool(name: "Głośny")
        noisy.program = "/bin/sh"
        noisy.arguments = ["-c", "head -c 200000 /dev/zero | tr '\\000' x >&2; echo ok"]
        let n = try await UserTools.run(noisy, context())
        #expect(n.output == "ok\n" && n.errors.count == 200_000)
    }

    @Test("Komendy narzędzi: rejestracja, wyjście do nowego okna, narzędzie sesji otwiera okno SQL, usunięcie")
    func commands() async throws {
        let ws = Workspace()
        var echo = UserTool(name: "Echo")
        echo.program = "/bin/echo"
        echo.arguments = ["ok"]
        echo.output = .newWindow
        var sql = UserTool(name: "Liczba wierszy", kind: .session)
        sql.sql = "select count(*) from #object"
        ws.selectedObject = DBObject(owner: "SCOTT", name: "EMP", type: .table)
        ws.updateUserTools([echo, sql])
        #expect(ws.registry.command(echo.commandID) != nil && ws.registry.command(sql.commandID)?.descriptor.agentAccess == AgentAccess.none)
        try await ws.invoke(echo.commandID)
        #expect(ws.documents.last?.text == "ok\n")
        try await ws.invoke(sql.commandID)
        #expect(ws.documents.last?.text == "select count(*) from SCOTT.EMP" && ws.documents.last?.kind == .sql)
        ws.updateUserTools([sql])
        #expect(ws.registry.command(echo.commandID) == nil)
    }
}
