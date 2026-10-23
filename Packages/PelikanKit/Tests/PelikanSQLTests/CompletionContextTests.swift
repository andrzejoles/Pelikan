import Foundation
import PelikanSQL
import Testing

@Suite("Kontekst podpowiedzi (Code Assistant)")
struct CompletionContextTests {
    func ctx(_ marked: String) -> CompletionContext {
        let r = (marked as NSString).range(of: "|")
        return CompletionContext.analyze(marked.replacingOccurrences(of: "|", with: ""), offset: r.location)
    }

    @Test("Alias tabeli, prefiks i zakres zastąpienia; tabele z FROM, JOIN i podzapytania")
    func aliases() {
        let c = ctx("select e.ena| from scott.emp e, (select 1 x from dual) s join dept d on d.deptno = e.deptno where 1=1")
        #expect(c.qualifier == ["E"] && c.prefix == "ena")
        #expect(c.tables.map { "\($0.owner ?? "-").\($0.name) \($0.alias ?? "-")" } == ["SCOTT.EMP E", "-. S", "-.DEPT D"])
        #expect(c.tables[1].subquery?.contains("select 1 x") == true)
        #expect(c.inSQLStatement)
        let u = ctx("update emp x set x.| = 1")
        #expect(u.tables == [TableReference(name: "EMP", alias: "X")])
        let ins = ctx("insert into emp (|) values (1)")
        #expect(ins.tables.first?.name == "EMP")
        let del = ctx("delete from emp where |")
        #expect(del.tables.first?.name == "EMP")
    }

    @Test("Granice instrukcji w PL/SQL: tabele tylko z bieżącej instrukcji")
    func statementBounds() {
        let c = ctx("begin\n  select 1 into v from dept;\n  if x then\n    update emp e set e.sal = 0 where e.| = 1;\n  end if;\nend;")
        #expect(c.tables.map(\.name) == ["EMP"])
    }

    @Test("Kwalifikatory wieloczłonowe, :new, @, literał i komentarz")
    func qualifiers() {
        #expect(ctx("begin scott.emp_api.|").qualifier == ["SCOTT", "EMP_API"])
        #expect(ctx("x := \"MyPkg\".f|").qualifier == ["MyPkg"])
        let n = ctx("create trigger t before insert on scott.emp for each row begin :new.| := 1; end;")
        #expect(n.bindQualifier && n.qualifier == ["NEW"])
        #expect(n.triggerTable == TableReference(owner: "SCOTT", name: "EMP"))
        #expect(ctx("select * from emp@|").afterAt)
        #expect(ctx("select 'abc| ' from dual").inLiteralOrComment)
        #expect(ctx("select 1 -- e.|\nfrom dual").inLiteralOrComment)
        #expect(!ctx("select e.| from emp e").inLiteralOrComment)
    }

    @Test("Deklaracje w zasięgu, typy rekordowe, rekordy pętli FOR")
    func declarations() {
        let c = ctx("""
            create or replace package body p as
              g number;
              procedure a(p_x number) is
                type t_rec is record (id number, name varchar2(10));
                v t_rec;
                cursor c is select empno, ename from emp;
              begin
                for r in c loop
                  for q in (select deptno, dname from dept) loop
                    for i in 1..10 loop
                      x := |
            """)
        let names = c.declarations.map(\.name)
        #expect(["v", "c", "t_rec", "p_x", "g", "a"].allSatisfy(names.contains))
        #expect(names.firstIndex(of: "v")! < names.firstIndex(of: "g")!)
        #expect(c.typeDeclarations["T_REC"]?.contains("record") == true)
        #expect(c.loopRecords["R"] == "C")
        #expect(c.loopRecords["Q"]?.contains("select deptno, dname from dept") == true)
        #expect(c.loopRecords["I"] == nil)
    }
}
