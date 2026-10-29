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

    /// Przykład podglądu (przełączany w Preferencjach): identyfikator i kod.
    public struct PreviewSample: Sendable, Identifiable {
        /// `plsql`, `queries`, `dml`, `ddl` (tytuł w interfejsie nadaje warstwa aplikacji).
        public let id: String
        public let code: String
    }

    /// Cztery przykłady podglądu (docs/research/formater.md, rozdz. 6.3): każda opcja zmienia coś widocznego w swoim
    /// przykładzie (`previewOf`) przy każdej wartości (`alternatives`) — pilnuje tego test. Słowa o mieszanej wielkości
    /// liter (`Exception_init`, `g_Licznik`, `Pls_integer`, `Dbms_output`, `To_char`) rozróżniają reguły wielkości liter.
    public static let previews: [PreviewSample] = [
        PreviewSample(id: "plsql", code: """
            create or replace package body kadry_api as
            c_limit constant number(12,2) := 1000; -- próg podwyżki
            g_Licznik Pls_integer := 0; -- zmiany w sesji
            e_brak exception;
            pragma Exception_init(e_brak, -20001);
            cursor c_dzial(p_dzial number) is select empno, ename, sal from emp where deptno = p_dzial;


            procedure podwyzka(p_dzial in number, p_procent in out nocopy number, p_data_od date default sysdate, p_tryb varchar2 := 'N') is
            v_suma number(12,2);
            v_opis varchar2(200) := 'brak';
            begin
            if v_suma > c_limit and p_tryb = 'N' and p_data_od < sysdate or p_procent is null and g_Licznik < 10 then
            v_opis := 'Dział ' || to_char(p_dzial) || ': suma ' || to_char(v_suma, 'FM999G990D00') || ' przekracza limit ' || c_limit;
            elsif v_suma between 1 and c_limit then
            v_opis := case when v_suma > 500 then 'średnia' else 'niska' end;
            end if;
            g_Licznik := g_Licznik+1;
            v_opis := v_opis || '!';
            v_suma := round(v_suma, 2);
            Dbms_output.put_line(v_opis);
            zapisz_log(p_dzial => p_dzial, p_opis => v_opis, p_kiedy => systimestamp);
            exception
            when no_data_found then
            v_opis := null;
            raise e_brak;
            end podwyzka;
            function suma_dzialu(p_dzial number, p_rok number) return number is
            begin
            return 0;
            end suma_dzialu;
            end kadry_api;
            /
            """),
        PreviewSample(id: "queries", code: """
            with dzialy as (select deptno, sum(sal) suma from emp group by deptno), duze as (select deptno from dzialy where suma > 9000)
            select e.ename imie, d.dname dzial, nvl(e.comm,0) prowizja, -- bez NULL
            To_char(e.hiredate,'YYYY') rok,
            case when e.sal > 3000 then 'wysoka' when e.sal > 1500 then 'średnia' else 'niska' end poziom,
            rank() over (partition by e.deptno order by e.sal desc) ranking
            from emp e join dept d on d.deptno = e.deptno and d.loc is not null
            where (e.job = 'CLERK' or e.job = 'ANALYST') and e.deptno in (select deptno from duze)
            and e.ename not in ('SMITH', 'ALLEN', 'WARD', 'JONES', 'MARTIN', 'BLAKE', 'CLARK', 'SCOTT', 'KING', 'TURNER', 'ADAMS')
            union all
            select ename, null, 0, null, null, null from emp_hist where sal > 0
            order by 1, 2 desc;
            """),
        PreviewSample(id: "dml", code: """
            update emp set sal = sal * (1 + p_procent / 100), comm = nvl(comm, 0) + 10, data_zmiany = sysdate where deptno = p_dzial and job <> 'PRESIDENT';
            insert into log_zmian (dzial, procent, kiedy, kto) values (p_dzial, p_procent, sysdate, user);
            insert into emp_hist (empno, ename, sal) select empno, ename, sal from emp where deptno = p_dzial;
            merge into emp t using (select empno, sal from emp_stage) s on (t.empno = s.empno) when matched then update set t.sal = s.sal, t.data_zmiany = sysdate when not matched then insert (empno, sal) values (s.empno, s.sal);
            delete from emp where deptno = p_dzial and sal is null;
            """),
        PreviewSample(id: "ddl", code: """
            create table log_zmian (id number generated always as identity, dzial number(2) not null, procent number(5,2) default 0 not null, kiedy date default sysdate, kto varchar2(128 char), constraint log_zmian_pk primary key (id), constraint log_zmian_dzial_fk foreign key (dzial) references dept (deptno) on delete cascade, constraint log_zmian_proc_ck check (procent between -100 and 100)) tablespace users;
            comment on table log_zmian is 'Historia podwyżek';
            create index log_zmian_ix on log_zmian (dzial, kiedy) compress 1;
            alter table log_zmian add (uwagi varchar2(4000), zrodlo varchar2(30) default 'APP');
            create or replace view v_log (dzial, procent, kiedy) as select dzial, procent, kiedy from log_zmian where procent <> 0 with read only;
            create or replace trigger log_zmian_bi before insert or update of procent on log_zmian for each row when (new.procent > 50) begin :new.kto := user; end;
            /
            create or replace type t_zmiana as object (dzial number(2), procent number(5,2), kiedy date, member function opis return varchar2);
            /
            grant select, insert on log_zmian to kadry_role, raport_user;
            """),
    ]

    /// Kod podglądu PL/SQL (pierwszy przykład).
    public static var preview: String { previews[0].code }

    public static func previewSample(_ id: String) -> PreviewSample? { previews.first { $0.id == id } }

    /// Przykład podglądu, w którym widać opcję (docs/research/formater.md, tabela 6.3).
    public static let previewOf: [String: String] = [
        "indent": "plsql", "useTabs": "plsql", "rightMargin": "plsql", "keepBlankLines": "plsql", "maxBlankLines": "plsql",
        "blankLineBetweenSubprograms": "plsql", "listLayout": "queries", "parameterDeclarations": "plsql", "callParameters": "plsql",
        "insertLists": "dml", "commaBefore": "queries", "clauseLayout": "queries", "andOrPosition": "queries",
        "joinConditionOnNewLine": "queries", "thenOnNewLine": "plsql", "caseLayout": "queries", "spaceAroundOperators": "plsql",
        "spaceAfterComma": "queries", "spaceInsideParentheses": "queries", "alignDeclarations": "plsql", "alignParameters": "plsql",
        "alignNamedArguments": "plsql", "alignAssignments": "plsql", "alignAliases": "queries", "alignSetValues": "dml",
        "alignTrailingComments": "plsql", "keywordCase": "plsql", "identifierCase": "plsql", "dataTypeCase": "plsql",
        "functionCase": "queries", "packageCase": "plsql", "specialCase": "plsql",
    ]

    /// Ustawienia, przy których opcja ma widoczny skutek (np. wyrównanie parametrów wymaga parametrów w osobnych liniach).
    public static func prepared(_ id: String, _ o: BeautifierOptions) -> BeautifierOptions {
        var o = o
        switch id {
        case "alignParameters": o.parameterDeclarations = .onePerLine
        case "alignNamedArguments": o.callParameters = .onePerLine
        case "alignAliases", "alignSetValues", "commaBefore": o.listLayout = .onePerLine
        case "maxBlankLines": o.keepBlankLines = true
        default: break
        }
        return o
    }

    /// Wszystkie inne wartości opcji (z `prepared`), które zmieniają wynik — liczby: wartości reprezentatywne; reguły
    /// wielkości liter grup słów bez wartości równej dziedziczonej.
    public static func alternatives(_ id: String, _ base: BeautifierOptions) -> [BeautifierOptions] {
        let o = prepared(id, base)
        func alt<T: Equatable>(_ kp: WritableKeyPath<BeautifierOptions, T>, _ values: [T]) -> [BeautifierOptions] {
            values.filter { $0 != o[keyPath: kp] }.map { var x = o; x[keyPath: kp] = $0; return x }
        }
        func altCase(_ kp: WritableKeyPath<BeautifierOptions, BeautifierOptions.WordCase?>, inherited: BeautifierOptions.WordCase) -> [BeautifierOptions] {
            let effective = o[keyPath: kp] ?? inherited
            return ([nil] + BeautifierOptions.WordCase.allCases.map(Optional.some)).filter { ($0 ?? inherited) != effective }
                .map { var x = o; x[keyPath: kp] = $0; return x }
        }
        switch id {
        case "indent": return alt(\.indent, [2, 3, 4])
        case "useTabs": return alt(\.useTabs, [false, true])
        case "rightMargin": return alt(\.rightMargin, [60, 100, 140])
        case "keepBlankLines": return alt(\.keepBlankLines, [false, true])
        case "maxBlankLines": return alt(\.maxBlankLines, [1, 2])
        case "blankLineBetweenSubprograms": return alt(\.blankLineBetweenSubprograms, [false, true])
        case "listLayout": return alt(\.listLayout, BeautifierOptions.ListLayout.allCases)
        case "parameterDeclarations": return alt(\.parameterDeclarations, BeautifierOptions.ListLayout.allCases)
        case "callParameters": return alt(\.callParameters, BeautifierOptions.ListLayout.allCases)
        case "insertLists": return alt(\.insertLists, BeautifierOptions.ListLayout.allCases)
        case "commaBefore": return alt(\.commaBefore, [false, true])
        case "clauseLayout": return alt(\.clauseLayout, BeautifierOptions.ClauseLayout.allCases)
        case "andOrPosition": return alt(\.andOrPosition, BeautifierOptions.OperatorPosition.allCases)
        case "joinConditionOnNewLine": return alt(\.joinConditionOnNewLine, [false, true])
        case "thenOnNewLine": return alt(\.thenOnNewLine, [false, true])
        case "caseLayout": return alt(\.caseLayout, BeautifierOptions.CaseLayout.allCases)
        case "spaceAroundOperators": return alt(\.spaceAroundOperators, [false, true])
        case "spaceAfterComma": return alt(\.spaceAfterComma, [false, true])
        case "spaceInsideParentheses": return alt(\.spaceInsideParentheses, [false, true])
        case "alignDeclarations": return alt(\.alignDeclarations, [false, true])
        case "alignParameters": return alt(\.alignParameters, [false, true])
        case "alignNamedArguments": return alt(\.alignNamedArguments, [false, true])
        case "alignAssignments": return alt(\.alignAssignments, [false, true])
        case "alignAliases": return alt(\.alignAliases, [false, true])
        case "alignSetValues": return alt(\.alignSetValues, [false, true])
        case "alignTrailingComments": return alt(\.alignTrailingComments, [false, true])
        case "keywordCase": return alt(\.keywordCase, BeautifierOptions.WordCase.allCases)
        case "identifierCase": return alt(\.identifierCase, BeautifierOptions.WordCase.allCases)
        case "dataTypeCase": return altCase(\.dataTypeCase, inherited: o.keywordCase)
        case "functionCase": return altCase(\.functionCase, inherited: o.identifierCase)
        case "packageCase": return altCase(\.packageCase, inherited: o.identifierCase)
        case "specialCase": return alt(\.specialCase, [[], ["DBMS_Output"], ["dbms_%"]])
        default: return []
        }
    }

    /// Znaczniki zmian w podglądzie: linie wyniku (od 0) zmienione albo dodane i miejsca usuniętych linii (indeks linii
    /// wyniku, przed którą je usunięto; liczba linii — na końcu).
    public struct Marks: Sendable, Equatable {
        public var changed: Set<Int> = []
        public var removedBefore: Set<Int> = []
        public init() {}
        public var isEmpty: Bool { changed.isEmpty && removedBefore.isEmpty }
        /// Pierwsza zaznaczona linia (do przewinięcia).
        public var first: Int? { (changed.union(removedBefore)).min() }
    }

    public static func marks(baseline: String, current: String) -> Marks {
        var m = Marks()
        guard baseline != current else { return m }
        var next = 0
        for r in TextDiff.rows(baseline, current) {
            switch r.kind {
            case .same: next = r.right ?? next
            case .changed, .added: if let line = r.right { m.changed.insert(line - 1); next = line }
            case .removed: m.removedBefore.insert(next)
            }
        }
        return m
    }

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
