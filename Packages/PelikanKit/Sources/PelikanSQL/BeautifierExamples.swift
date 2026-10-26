/// Przykłady formatera w Preferencjach (D174): kod podglądu, na którym widać zmianę każdej opcji (pilnuje tego
/// test), i krótki przykład każdej opcji z jej inną wartością („teraz” i „po zmianie”).
public enum BeautifierExamples {
    public struct Example: Sendable {
        /// Nazwa właściwości `BeautifierOptions`.
        public let id: String
        public let snippet: String
        /// Ustawienia z inną wartością tej opcji.
        public let variant: @Sendable (BeautifierOptions) -> BeautifierOptions
    }

    public static let preview = """
        create or replace package body kadry_api as
        c_limit constant number := 1000; -- próg podwyżki
        g_licznik pls_integer := 0; -- liczba zmian w sesji


        procedure podwyzka(p_dzial in number, p_procent in out nocopy number, p_data_od date default sysdate, p_tryb varchar2 := 'N') is
        v_suma number(12,2);
        v_opis_zmiany varchar2(200) := 'brak';
        begin
        select d.dname nazwa, count(*) liczba, sum(nvl(e.sal,0)) suma, case when sum(e.sal)>c_limit then 'wysoka' else 'niska' end poziom
        into v_opis_zmiany, g_licznik, v_suma, v_opis_zmiany
        from emp e join dept d on d.deptno=e.deptno
        where e.deptno=p_dzial and e.hiredate<p_data_od or e.job in ('CLERK','ANALYST')
        group by d.dname;
        if v_suma>c_limit then
        update emp set sal=sal*(1+p_procent/100), comm=nvl(comm,0)+10, data_zmiany=sysdate where deptno=p_dzial;
        insert into log_zmian (dzial, procent, kiedy) values (p_dzial, p_procent, sysdate);
        end if;
        g_licznik := g_licznik+1;
        v_opis_zmiany := to_char(v_suma)||' zł';
        v_suma := round(v_suma, 2);
        dbms_output.put_line(v_opis_zmiany);
        zapisz_log(p_dzial => p_dzial, p_opis => v_opis_zmiany, p_kiedy => systimestamp, p_uzytkownik => user);
        end podwyzka;
        function suma_dzialu(p_dzial number, p_rok number) return number is
        begin
        return 0;
        end suma_dzialu;
        end kadry_api;
        /
        """

    static func nextCase(_ c: BeautifierOptions.WordCase) -> BeautifierOptions.WordCase {
        let all = BeautifierOptions.WordCase.allCases
        return all[(all.firstIndex(of: c)! + 1) % all.count]
    }

    /// Inna wartość reguły grupy słów: własna reguła różna od dziedziczonej albo powrót do dziedziczenia.
    static func otherCase(_ c: BeautifierOptions.WordCase?, inherited: BeautifierOptions.WordCase) -> BeautifierOptions.WordCase? {
        c == nil ? (inherited == .upper ? .lower : .upper) : nil
    }

    static let procedure = "procedure p(a number) is begin if a > 0 then x := 1; end if; end;"
    static let query = "select e.ename imie, d.dname dzial from emp e join dept d on d.deptno = e.deptno where e.sal > 1000 and e.job = 'CLERK';"

    public static let all: [Example] = [
        Example(id: "indent", snippet: procedure) { var o = $0; o.indent = o.indent == 2 ? 4 : 2; return o },
        Example(id: "useTabs", snippet: procedure) { var o = $0; o.useTabs.toggle(); return o },
        Example(id: "rightMargin", snippet: "select e.empno, e.ename, e.job, e.mgr, e.hiredate, e.sal, e.comm, e.deptno from emp e;") {
            var o = $0; o.rightMargin = o.rightMargin > 60 ? 40 : 100; o.listLayout = .fit; return o
        },
        Example(id: "listLayout", snippet: "select empno, ename, sal from emp order by ename, sal;") {
            var o = $0; o.listLayout = o.listLayout == .onePerLine ? .fit : .onePerLine; return o
        },
        Example(id: "parameterDeclarations", snippet: "procedure p(a number, b varchar2, c date) is begin null; end;") {
            var o = $0; o.parameterDeclarations = o.parameterDeclarations == .fit ? .onePerLine : .fit; return o
        },
        Example(id: "callParameters", snippet: "begin zapisz(1, 'x', sysdate); end;") {
            var o = $0; o.callParameters = o.callParameters == .fit ? .onePerLine : .fit; return o
        },
        Example(id: "insertLists", snippet: "insert into t (a, b, c) values (1, 2, 3);") {
            var o = $0; o.insertLists = o.insertLists == .fit ? .onePerLine : .fit; return o
        },
        Example(id: "commaBefore", snippet: "select empno, ename, sal from emp;") {
            var o = $0; o.commaBefore.toggle(); o.listLayout = .onePerLine; return o
        },
        Example(id: "keepBlankLines", snippet: "begin\nx := 1;\n\ny := 2;\nend;") { var o = $0; o.keepBlankLines.toggle(); return o },
        Example(id: "maxBlankLines", snippet: "begin\nx := 1;\n\n\n\ny := 2;\nend;") {
            var o = $0; o.keepBlankLines = true; o.maxBlankLines = o.maxBlankLines == 1 ? 2 : 1; return o
        },
        Example(id: "blankLineBetweenSubprograms", snippet: "create package body p as\nprocedure a is begin null; end;\nprocedure b is begin null; end;\nend;") {
            var o = $0; o.blankLineBetweenSubprograms.toggle(); return o
        },
        Example(id: "clauseLayout", snippet: query) {
            var o = $0
            let all = BeautifierOptions.ClauseLayout.allCases
            o.clauseLayout = all[(all.firstIndex(of: o.clauseLayout)! + 1) % all.count]
            return o
        },
        Example(id: "andOrPosition", snippet: query) { var o = $0; o.andOrPosition = o.andOrPosition == .lineStart ? .lineEnd : .lineStart; return o },
        Example(id: "joinConditionOnNewLine", snippet: query) { var o = $0; o.joinConditionOnNewLine.toggle(); return o },
        Example(id: "thenOnNewLine", snippet: "begin if a > 0 and b < 10 then x := 1; elsif a < 0 then x := 2; end if; end;") {
            var o = $0; o.thenOnNewLine.toggle(); return o
        },
        Example(id: "caseLayout", snippet: "select case when sal > 1000 then 'wysoka' when sal > 500 then 'średnia' else 'niska' end poziom from emp;") {
            var o = $0; o.caseLayout = o.caseLayout == .inline ? .multiline : .inline; return o
        },
        Example(id: "spaceAroundOperators", snippet: "begin x := (a+b)*c; if x>=10 then y := 'a'||'b'; end if; end;") {
            var o = $0; o.spaceAroundOperators.toggle(); return o
        },
        Example(id: "spaceAfterComma", snippet: "select nvl(a, 0), substr(b, 1, 3) from t;") { var o = $0; o.spaceAfterComma.toggle(); return o },
        Example(id: "spaceInsideParentheses", snippet: "select nvl(a, 0), substr(b, 1, 3) from t;") { var o = $0; o.spaceInsideParentheses.toggle(); return o },
        Example(id: "alignDeclarations", snippet: "declare\nv_id number;\nv_nazwa_klienta varchar2(100) := 'x';\nc_max constant pls_integer default 10;\nbegin null; end;") {
            var o = $0; o.alignDeclarations.toggle(); return o
        },
        Example(id: "alignParameters", snippet: "procedure p(p_id in number, p_nazwa_klienta in out nocopy varchar2, p_data date default sysdate) is begin null; end;") {
            var o = $0; o.alignParameters.toggle(); o.parameterDeclarations = .onePerLine; return o
        },
        Example(id: "alignNamedArguments", snippet: "begin zapisz(p_id => 1, p_nazwa_klienta => 'x', p_data => sysdate); end;") {
            var o = $0; o.alignNamedArguments.toggle(); o.callParameters = .onePerLine; return o
        },
        Example(id: "alignAssignments", snippet: "begin\nv_id := 1;\nv_nazwa_klienta := 'x';\nv_data := sysdate;\nend;") {
            var o = $0; o.alignAssignments.toggle(); return o
        },
        Example(id: "alignAliases", snippet: "select e.ename imie, count(*) liczba, sum(e.sal) as suma from emp e, dept d;") {
            var o = $0; o.alignAliases.toggle(); o.listLayout = .onePerLine; return o
        },
        Example(id: "alignSetValues", snippet: "update emp set sal = sal * 1.1, comm = 0, data_zmiany = sysdate where empno = 1;") {
            var o = $0; o.alignSetValues.toggle(); o.listLayout = .onePerLine; return o
        },
        Example(id: "alignTrailingComments", snippet: "declare\nv_id number; -- klucz\nv_nazwa_klienta varchar2(100); -- nazwa\nbegin null; end;") {
            var o = $0; o.alignTrailingComments.toggle(); return o
        },
        Example(id: "keywordCase", snippet: procedure) { var o = $0; o.keywordCase = nextCase(o.keywordCase); return o },
        Example(id: "identifierCase", snippet: procedure) { var o = $0; o.identifierCase = nextCase(o.identifierCase); return o },
        Example(id: "dataTypeCase", snippet: "declare v number(10); s varchar2(20); d date; begin null; end;") {
            var o = $0; o.dataTypeCase = otherCase(o.dataTypeCase, inherited: o.keywordCase); return o
        },
        Example(id: "functionCase", snippet: "select nvl(a, 0), to_char(sysdate, 'YYYY'), count(*) from t;") {
            var o = $0; o.functionCase = otherCase(o.functionCase, inherited: o.identifierCase); return o
        },
        Example(id: "packageCase", snippet: "begin dbms_output.put_line(utl_raw.cast_to_raw('x')); end;") {
            var o = $0; o.packageCase = otherCase(o.packageCase, inherited: o.identifierCase); return o
        },
        Example(id: "specialCase", snippet: "begin dbms_output.put_line('x'); end;") {
            var o = $0; o.specialCase = o.specialCase.isEmpty ? ["DBMS_Output"] : []; return o
        },
    ]

    public static func example(_ id: String) -> Example? { all.first { $0.id == id } }
}
