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

    @Test("$X{} z nieznaną funkcją zostaje bez zmian — nie warunek zawsze prawdziwy")
    func jasperUnknownFunction() {
        let p = Variables.prepare("delete from t where $X{EQUALS, id, p}", values: ["p": .text("1")])
        #expect(p.sql == "delete from t where $X{EQUALS, id, p}")
        #expect(p.binds.isEmpty)
        #expect(Variables.prepare("delete from t where $X{INN, id, p}", values: [:]).sql == "delete from t where $X{INN, id, p}")
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

@Suite("Zmienne: opcje &<…> i &\"Nazwa\" (UG 12.3)")
struct VariableOptionsTests {
    @Test("&\"Nazwa ze spacjami\" i &<name=…> rozpoznawane jako jedna zmienna")
    func syntax() {
        let occ = Variables.find(in: """
            select * from emp where deptno = &"Numer działu" and ename like &<name="Pracownik" type="string" ifempty="%"> and x = &<name="A b" list="1, 2">
            """)
        #expect(occ.map(\.name) == ["Numer działu", "Pracownik", "A b"])
        #expect(occ[1].options?.type == .string)
        #expect(occ[1].options?.ifEmpty == "%")
        #expect(occ[2].options?.listItems.map(\.value) == ["1", "2"])
    }

    @Test("Typ string dodaje cudzysłowy (z podwojeniem apostrofu), uppercase, ifempty")
    func stringType() {
        let sql = "where ename = &<name=\"E\" type=\"string\" uppercase=\"yes\"> and job like &<name=\"J\" type=\"string\" ifempty=\"%\">"
        let p = Variables.prepare(sql, values: ["E": .text("o'brien"), "J": .text("")])
        #expect(p.sql == "where ename = 'O''BRIEN' and job like '%'")
    }

    @Test("Prefix/suffix znikają przy pustej wartości; checkbox; multiselect")
    func prefixCheckboxMulti() {
        let sql = "select * from emp &<name=\"Sort\" prefix=\"order by \" suffix=\" desc\"> &<name=\"D\" checkbox=\"desc,asc\"> where deptno in (&<name=\"Dz\" multiselect=\"yes\">)"
        let empty = Variables.prepare(sql, values: ["Sort": .text(""), "D": .text("1"), "Dz": .list(["10", "20"])])
        #expect(empty.sql == "select * from emp  desc where deptno in (10, 20)")
        let filled = Variables.prepare(sql, values: ["Sort": .text("empno"), "D": .text("0"), "Dz": .list(["10"])])
        #expect(filled.sql == "select * from emp order by empno desc asc where deptno in (10)")
    }

    @Test("Lista z opisami i z zapytaniem; nazwa zmiennej wiązanej dla list zależnych")
    func lists() {
        let o = VariableOptions.parse("&<name=\"Dział\" list=\"10, KSIĘGOWOŚĆ, 20, BADANIA\" description=\"yes\" restricted=\"yes\">")
        #expect(o.listItems.map(\.label) == ["KSIĘGOWOŚĆ", "BADANIA"])
        #expect(o.restricted)
        let q = VariableOptions.parse("&<name=\"Owner of the table\" list=\"select username from all_users\">")
        #expect(q.listIsQuery)
        #expect(q.bindName == "owner_of_the_table")
    }

    @Test("W SQL Window && to dosłowne & (także w literale); w SQL*Plus — zmienna zapamiętywana")
    func doubleAmpersand() {
        let sql = "select * from dept where dname = 'R&&D' and x = &&y"
        let w = Variables.prepare(sql, values: [:])
        #expect(w.sql == "select * from dept where dname = 'R&D' and x = &y")
        #expect(Variables.distinct(Variables.find(in: sql)).isEmpty)
        let plus = Variables.find(in: sql, syntax: .sqlplus)
        #expect(plus.map(\.name) == ["D", "y"])
        #expect(plus.allSatisfy { $0.persistent })
    }
}
