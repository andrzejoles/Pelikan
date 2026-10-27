import Foundation
import PelikanSQL
import Testing

@Suite("Parser strukturalny PL/SQL")
struct PLSQLOutlineTests {
    let body = """
    create or replace package body emp_api as
      g_calls pls_integer := 0;
      c_max constant number := 10;
      cursor c_emp(p_dept number) is select * from emp where deptno = p_dept;
      type t_tab is table of emp%rowtype;
      e_brak exception;

      function get_salary(p_empno in emp.empno%type, p_def number default 0) return emp.sal%type is
        l_sal emp.sal%type;
      begin
        if l_sal is null then
          return p_def;
        end if;
        for r in c_emp(10) loop
          null;
        end loop;
        return case when l_sal > 0 then l_sal else 0 end;
      end get_salary;

      procedure raise_salary(p_empno number) is
        procedure local_log(p_msg varchar2) is begin null; end;
      begin
        declare
          v_tmp number;
        begin
          v_tmp := 1;
        end;
        local_log('x');
      end;
    begin
      g_calls := 0;
    end emp_api;
    /
    """

    @Test("Jednostka, zmienne globalne, stała, kursor, typ, wyjątek, podprogramy z parametrami i typem zwracanym")
    func outline() throws {
        let nodes = PLSQLOutline.parse(body)
        let pkg = try #require(nodes.first)
        #expect(pkg.kind == .packageBody && pkg.name == "emp_api")
        let kinds = pkg.children.map { "\($0.kind.rawValue):\($0.name)" }
        #expect(kinds.prefix(7) == ["variable:g_calls", "constant:c_max", "cursor:c_emp", "typeDeclaration:t_tab", "exception:e_brak",
                                    "function:get_salary", "procedure:raise_salary"])
        let f = pkg.children[5]
        #expect(f.detail == "emp.sal%type")
        #expect(f.children.filter { $0.kind == .parameter }.map(\.name) == ["p_empno", "p_def"])
        #expect(f.children.first { $0.name == "p_empno" }?.detail == "in emp.empno%type")
        #expect(f.children.contains { $0.kind == .variable && $0.name == "l_sal" })
        // Koniec funkcji na „end get_salary;” mimo END IF / END LOOP / CASE … END w środku.
        let fText = (body as NSString).substring(with: NSRange(location: f.range.lowerBound, length: f.range.count))
        #expect(fText.hasSuffix("end get_salary;"))
        let p = pkg.children[6]
        #expect(p.children.contains { $0.kind == .procedure && $0.name == "local_log" })
        #expect(p.children.contains { $0.kind == .block && $0.children.contains { $0.name == "v_tmp" } })
        #expect((body as NSString).substring(with: NSRange(location: pkg.range.lowerBound, length: pkg.range.count)).hasSuffix("end emp_api;"))
    }

    @Test("Ścieżka przy kursorze (Code Hierarchy) i deklaracja identyfikatora z zakresu")
    func pathAndDeclaration() {
        let nodes = PLSQLOutline.parse(body)
        let pos = (body as NSString).range(of: "v_tmp := 1").location
        #expect(PLSQLOutline.path(at: pos, in: nodes).map(\.name) == ["emp_api", "raise_salary", "BEGIN"])
        let use = (body as NSString).range(of: "return p_def").location + 7
        #expect(PLSQLOutline.declaration(of: "P_DEF", at: use, in: nodes)?.kind == .parameter)
        let g = PLSQLOutline.declaration(of: "g_calls", at: pos, in: nodes)
        #expect(g?.kind == .variable && g?.nameOffset == (body as NSString).range(of: "g_calls").location)
    }

    @Test("Specyfikacja pakietu, typ obiektowy, wyzwalacz, blok anonimowy, kod niekompletny bez awarii")
    func misc() {
        let spec = PLSQLOutline.parse("create package p as procedure a(x number); function b return number; end p;\n/")
        #expect(spec.first?.children.map(\.name) == ["a", "b"])
        let typ = PLSQLOutline.parse("create or replace type addr_t as object (street varchar2(40), city varchar2(30));\n/")
        #expect(typ.first?.children.map(\.name) == ["street", "city"])
        let trg = PLSQLOutline.parse("create or replace trigger t before insert on emp for each row declare v number; begin v := 1; end;\n/")
        #expect(trg.first?.kind == .trigger && trg.first?.children.first?.name == "v")
        let anon = PLSQLOutline.parse("declare x number; begin null; end;")
        #expect(anon.first?.kind == .block && anon.first?.children.first?.name == "x")
        let broken = PLSQLOutline.parse("create or replace package body q as procedure a is begin if x then")
        #expect(broken.first?.name == "q")
    }

    @Test("Wyzwalacz złożony (COMPOUND TRIGGER) i wyzwalacz CALL — zakres jednostki")
    func compoundAndCallTriggers() {
        let src = """
            create or replace trigger t for update on emp compound trigger
              g number;
              before statement is
              begin
                g := 0;
              end before statement;
              after each row is
              begin
                g := g + 1;
              end after each row;
            end t;
            /
            create or replace trigger c before insert on emp for each row when (new.sal / 2 > 10) call log_proc
            /
            begin null; end;
            """
        let nodes = PLSQLOutline.parse(src)
        #expect(nodes.map(\.kind) == [.trigger, .trigger, .block])
        let ns = src as NSString
        let t = nodes[0]
        #expect(t.children.map(\.name) == ["g"])
        #expect(ns.substring(with: NSRange(location: t.range.lowerBound, length: t.range.count)).hasSuffix("end t;"))
        let c = nodes[1]
        #expect(ns.substring(with: NSRange(location: c.range.lowerBound, length: c.range.count)).hasSuffix("call log_proc"))
    }

    @Test("Zakresy zwijania: blok podprogramu, IF, LOOP, CASE")
    func folding() {
        let ranges = PLSQLOutline.foldingRanges(body)
        let texts = ranges.map { (body as NSString).substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }
        #expect(texts.contains { $0.hasPrefix("if l_sal is null") && $0.hasSuffix("end if") })
        #expect(texts.contains { $0.hasPrefix("loop") && $0.hasSuffix("end loop") })
        #expect(texts.contains { $0.hasPrefix("begin") && $0.hasSuffix("end get_salary") })
    }

    @Test("Wydajność: zarys pakietu 50 000 linii")
    func performance() {
        var s = "create or replace package body big as\n"
        for i in 1...5000 {
            s += "  procedure p\(i)(a number) is\n    v number;\n  begin\n    if a > 0 then\n      v := a;\n    end if;\n    for r in 1..2 loop null; end loop;\n  end p\(i);\n\n"
        }
        s += "end big;\n/\n"
        let clock = ContinuousClock()
        var count = 0
        let t = clock.measure { count = PLSQLOutline.parse(s).first?.children.count ?? 0 }
        #expect(count == 5000)
        #expect(t < (ProcessInfo.processInfo.environment["PELIKAN_PERF_STRICT"] == "1" ? .milliseconds(300) : .seconds(5)), "\(t)")
    }
}

@Suite("Zwijanie kodu")
struct CodeFoldingTests {
    let text = """
    begin
      if a then
        x := 1;
      end if;
      loop exit; end loop;
    end;
    """

    @Test("Obszary wielolinijkowe, ukryte linie, zwinięcia zagnieżdżone pochłaniane")
    func regions() {
        let r = CodeFolding.regions(text)
        #expect(r.map { "\($0.startLine)-\($0.endLine)" } == ["0-5", "1-3"])   // LOOP w jednej linii — bez obszaru
        let ns = text as NSString
        let inner = r[1]
        #expect(ns.substring(with: NSRange(location: inner.hidden.lowerBound, length: inner.hidden.count)) == "    x := 1;\n  end if;\n")
        #expect(CodeFolding.hiddenRanges(r, folded: [r[0].start, r[1].start]) == [r[0].hidden])
    }

    @Test("Przesunięcie zwinięć przy edycji przed, za i wewnątrz obszaru")
    func shift() {
        let start = (text as NSString).range(of: "if a").location
        #expect(CodeFolding.shift([start], from: text, to: "-- k\n" + text) == [start + 5])
        #expect(CodeFolding.shift([start], from: text, to: text + "\n/") == [start])
        #expect(CodeFolding.shift([start], from: text, to: text.replacingOccurrences(of: "if a", with: "IF a")).isEmpty)
    }

    @Test("Obszary przesuwane razem z kluczami zwinięć — zwinięcie poniżej miejsca pisania nie rozwija się (APP2-12)")
    func shiftRegions() {
        let r = CodeFolding.regions(text)
        let inner = r[1]
        // Linia dopisana na początku: oba obszary przesunięte o 5 znaków (numery linii przelicza dopiero analiza w tle).
        let edited = "-- k\n" + text
        let moved = CodeFolding.shift(r, edited: 0..<5, delta: 5)
        #expect(moved == CodeFolding.regions(edited).map { var x = $0; x.startLine -= 1; x.endLine -= 1; return x })
        // Ukryte zakresy po przesunięciu takie jak przeliczone dla nowego tekstu.
        let folded = CodeFolding.shift([inner.start], from: text, to: edited)
        #expect(CodeFolding.hiddenRanges(moved, folded: folded) == CodeFolding.hiddenRanges(CodeFolding.regions(edited), folded: folded))
        // Edycja wewnątrz ukrytego zakresu wydłuża go; za nim — bez zmian; na początku struktury — obszar znika.
        let x = (text as NSString).range(of: "x := 1").location
        #expect(CodeFolding.shift([inner], edited: x..<(x + 2), delta: 2).first?.hidden == inner.hidden.lowerBound..<(inner.hidden.upperBound + 2))
        #expect(CodeFolding.shift([inner], edited: inner.hidden.upperBound..<(inner.hidden.upperBound + 1), delta: 1).first?.hidden == inner.hidden)
        #expect(CodeFolding.shift([inner], edited: inner.start..<(inner.start + 2), delta: 0).isEmpty)
    }
}
