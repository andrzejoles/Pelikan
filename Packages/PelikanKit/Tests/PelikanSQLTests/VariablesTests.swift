import PelikanSQL
import Testing

@Suite("Zmienne: &, :bind i parametry JasperReports")
struct VariablesTests {
    @Test("Wykrywa &, &&, :bind; pomija := i literały dla :bind")
    func detect() {
        let occ = Variables.find(in: "select &kol, ':nie' from t where id = :id and x := 1 and n = '&w'")
        #expect(occ.map(\.name) == ["kol", "id", "w"])
        #expect(occ.first { $0.name == "id" }?.kind == .bind)
        #expect(occ.first { $0.name == "w" }?.kind == .substitution)
    }

    @Test(":new i :old w wyzwalaczu nie są zmiennymi wiązanymi")
    func trigger() {
        let occ = Variables.find(in: "create or replace trigger t before update on emp for each row begin :new.x := :old.x; end;")
        #expect(occ.isEmpty)
    }

    @Test("Parametry Jaspera: $P{} jako wartość, $P!{} jako tekst, $X{} z kolumną")
    func jasperDetect() {
        let occ = Variables.find(in: "select * from emp where empno = $P{EmpNo} and $X{IN, deptno, Depts} order by $P!{Sort}")
        #expect(occ.map(\.kind) == [.jasperValue, .jasperClause, .jasperText])
        #expect(occ[1].clause == JasperClause(function: "IN", column: "deptno", parameters: ["Depts"]))
        #expect(Variables.distinct(occ).map(\.name) == ["EmpNo", "Depts", "Sort"])
    }

    @Test("Przygotowanie: & i $P!{} wstawiane jako tekst, $P{} zamieniane na zmienną wiązaną")
    func prepareTextAndBinds() {
        let p = Variables.prepare("select &kol from emp where empno = $P{EmpNo} order by $P!{Sort}",
                                  values: ["kol": .text("ename"), "EmpNo": .text("7839"), "Sort": .text("ename desc")])
        #expect(p.sql == "select ename from emp where empno = :EmpNo order by ename desc")
        #expect(p.binds.map(\.name) == ["EmpNo"])
        #expect(p.binds.first?.value == .text("7839"))
    }

    @Test("$X{IN} z listą, pustą listą i NOTIN", arguments: [
        (VariableValue.list(["10", "20"]), "select * from emp where deptno IN (:jx1, :jx2)"),
        (VariableValue.list([]), "select * from emp where 0 = 0"),
        (VariableValue.null, "select * from emp where 0 = 0"),
    ])
    func jasperIn(value: VariableValue, expected: String) {
        let p = Variables.prepare("select * from emp where $X{IN, deptno, Depts}", values: ["Depts": value])
        #expect(p.sql == expected)
    }

    @Test("$X{EQUAL}/{NOTEQUAL} z NULL daje IS [NOT] NULL")
    func jasperEqual() {
        #expect(Variables.prepare("where $X{EQUAL, comm, C}", values: [:]).sql == "where comm IS NULL")
        #expect(Variables.prepare("where $X{NOTEQUAL, comm, C}", values: ["C": .text("1")]).sql == "where comm <> :jx1")
    }

    @Test("$X{BETWEEN} i warianty z nawiasami; brak jednej granicy pomija ją")
    func jasperBetween() {
        let both = Variables.prepare("where $X{[BETWEEN], sal, Lo, Hi}", values: ["Lo": .text("1000"), "Hi": .text("2000")])
        #expect(both.sql == "where sal >= :jx1 AND sal <= :jx2")
        #expect(both.binds.map(\.value) == [.text("1000"), .text("2000")])
        let lo = Variables.prepare("where $X{BETWEEN, sal, Lo, Hi}", values: ["Lo": .text("1000")])
        #expect(lo.sql == "where sal > :jx1")
        let none = Variables.prepare("where $X{BETWEEN], sal, Lo, Hi}", values: [:])
        #expect(none.sql == "where 0 = 0")
    }

    @Test("$X{LESS]} i [GREATER")
    func jasperCompare() {
        #expect(Variables.prepare("where $X{LESS], sal, X}", values: ["X": .text("5")]).sql == "where sal <= :jx1")
        #expect(Variables.prepare("where $X{[GREATER, sal, X}", values: ["X": .text("5")]).sql == "where sal >= :jx1")
        #expect(Variables.prepare("where $X{GREATER, sal, X}", values: [:]).sql == "where 0 = 0")
    }

    @Test("Zmienna :bind bez wartości zostaje w tekście, z wartością NULL")
    func bindKept() {
        let p = Variables.prepare("select * from emp where empno = :id", values: [:])
        #expect(p.sql == "select * from emp where empno = :id")
        #expect(p.binds.map(\.name) == ["id"])
        #expect(p.binds.first?.value == .null)
    }

    @Test("Nazwa $P{} z niedozwolonymi znakami zamieniana na p_…")
    func jasperNames() {
        let p = Variables.prepare("where a = $P{Data od}", values: ["Data od": .text("x")])
        #expect(p.sql == "where a = :p_Data_od")
    }
}
