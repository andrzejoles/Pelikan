import Foundation
import PelikanSQL
import Testing

/// Struktury sterujące w zarysie (D203): IF/ELSIF/ELSE, pętle, FORALL, instrukcja CASE, bloki zagnieżdżone, sekcja
/// EXCEPTION z obsługami, etykiety, punkty czasowe wyzwalacza złożonego, sekcja inicjalizacji pakietu, skrypt okna SQL;
/// odporność na niedokończony kod, kompilację warunkową, literały i komentarze; pozycje UTF-16.
@Suite("Parser strukturalny PL/SQL — struktury sterujące")
struct PLSQLOutlineControlFlowTests {
    /// Drzewo jako wcięte linie „rodzaj [<<etykieta>>] nazwa szczegóły” — jednostki, podprogramy, bloki i struktury.
    static func dump(_ nodes: [OutlineNode], depth: Int = 0) -> [String] {
        nodes.flatMap { n -> [String] in
            guard n.kind.isControlFlow || n.isContainer else { return [] }
            let line = String(repeating: "  ", count: depth) + n.kind.rawValue + " " + (n.label.map { "<<\($0)>> " } ?? "") + n.name
                + (n.detail.isEmpty ? "" : " " + n.detail)
            return [line] + dump(n.children, depth: depth + 1)
        }
    }

    static func text(_ s: String, _ r: Range<Int>) -> String { (s as NSString).substring(with: NSRange(location: r.lowerBound, length: r.count)) }

    /// Wszystkie elementy drzewa (w głąb).
    static func flat(_ nodes: [OutlineNode]) -> [OutlineNode] { nodes.flatMap { [$0] + flat($0.children) } }

    static let procedure = """
    create or replace procedure p(a number) is
      x number;
    begin
      if a > 0 then
        for r in (select case when e.sal > 0 then 1 end s from emp e) loop
          null;
        end loop;
      elsif a < 0 then
        x := case a when 1 then 2 else 3 end;
      else
        <<wew>>
        while x < 10 loop
          x := x + 1;
          exit wew when x = 5;
        end loop wew;
      end if;
      case a
        when 1 then
          forall i in 1..10 insert into t values (i);
        else
          loop exit; end loop;
      end case;
      declare
        y number;
      begin
        null;
      exception
        when no_data_found or too_many_rows then
          null;
        when others then
          raise;
      end;
    exception
      when others then
        if sqlcode = -1 then null; end if;
    end p;
    """

    @Test("wszystkie rodzaje: IF z ELSIF i ELSE, FOR kursorowa z zapytaniem, WHILE z etykietą, CASE z WHEN i ELSE, FORALL, LOOP, blok z obsługami wyjątków")
    func allKinds() {
        let nodes = PLSQLOutline.parse(Self.procedure, controlFlow: true)
        #expect(Self.dump(nodes) == [
            "procedure p",
            "  ifStatement IF a > 0",
            "    loop FOR r in (select case when e.sal > 0 then 1 end s from emp e)",
            "    elsifBranch ELSIF a < 0",
            "    elseBranch ELSE",
            "      loop <<wew>> WHILE x < 10",
            "  caseStatement CASE a",
            "    whenBranch WHEN 1",
            "      forall FORALL i in 1..10",
            "    elseBranch ELSE",
            "      loop LOOP",
            "  block BEGIN",
            "    exceptionSection EXCEPTION",
            "      exceptionHandler WHEN no_data_found or too_many_rows",
            "      exceptionHandler WHEN others",
            "  exceptionSection EXCEPTION",
            "    exceptionHandler WHEN others",
            "      ifStatement IF sqlcode = -1",
        ])
        // Deklaracje bloku zagnieżdżonego zostają jego dziećmi, przed strukturami.
        let p = nodes[0]
        let block = p.children.first { $0.kind == .block }!
        #expect(block.children.first?.name == "y")
    }

    @Test("zakresy od słowa otwierającego do END …; gałęzie do następnej gałęzi; nazwa — słowo otwierające")
    func ranges() {
        let src = Self.procedure
        let p = PLSQLOutline.parse(src, controlFlow: true)[0]
        let ifNode = p.children.first { $0.kind == .ifStatement }!
        let ifText = Self.text(src, ifNode.range)
        #expect(ifText.hasPrefix("if a > 0 then") && ifText.hasSuffix("end if;"))
        #expect(Self.text(src, ifNode.nameOffset..<(ifNode.nameOffset + 2)) == "if")
        let elsif = ifNode.children.first { $0.kind == .elsifBranch }!
        let elsifText = Self.text(src, elsif.range)
        #expect(elsifText.hasPrefix("elsif a < 0 then") && elsifText.hasSuffix("else 3 end;"))
        let elseNode = ifNode.children.first { $0.kind == .elseBranch }!
        #expect(Self.text(src, elseNode.range).hasSuffix("end loop wew;"))
        let loop = elseNode.children[0]
        #expect(Self.text(src, loop.range).hasPrefix("<<wew>>\n    while x < 10 loop") && Self.text(src, loop.range).hasSuffix("end loop wew;"))
        let forall = Self.flat([p]).first { $0.kind == .forall }!
        #expect(Self.text(src, forall.range) == "forall i in 1..10 insert into t values (i);")
        let caseNode = p.children.first { $0.kind == .caseStatement }!
        #expect(Self.text(src, caseNode.range).hasSuffix("end case;"))
        let section = p.children.last!
        #expect(section.kind == .exceptionSection && Self.text(src, section.range).hasPrefix("exception") && Self.text(src, section.range).hasSuffix("end if;"))
        // Element zawierający pozycję: kursor w pętli WHILE — najgłębsza struktura.
        let offset = (src as NSString).range(of: "x := x + 1").location
        #expect(Self.flat([p]).filter { $0.range.contains(offset) }.last?.kind == .loop)
        // Ścieżka hierarchii kodu pomija struktury sterujące — jak w zarysie bez nich.
        #expect(PLSQLOutline.path(at: offset, in: [p]).map(\.name) == ["p"])
        let inBlock = (src as NSString).range(of: "raise;").location
        #expect(PLSQLOutline.path(at: inBlock, in: [p]).map(\.kind) == [.procedure, .block])
        #expect(PLSQLOutline.path(at: inBlock, in: [p]).map(\.range) == PLSQLOutline.path(at: inBlock, in: PLSQLOutline.parse(src)).map(\.range))
    }

    @Test("bez controlFlow zarys jak dotąd — równy zarysowi ze strukturami po ich usunięciu")
    func withoutControlFlowEqualsLegacy() {
        let fixtures = [Self.procedure, Self.compound, Self.packageBody, Self.unfinished, PLSQLOutlinePackageTests.source,
                        "begin if a then begin null; end; else declare x number; begin null; end; end if; end;"]
        for src in fixtures {
            let plain = PLSQLOutline.parse(src)
            #expect(plain == PLSQLOutline.withoutControlFlow(PLSQLOutline.parse(src, controlFlow: true)))
            #expect(!Self.flat(plain).contains { $0.kind.isControlFlow })
        }
        // Bloki zagnieżdżone w gałęziach należą bez struktur do podprogramu.
        let p = PLSQLOutline.parse(Self.procedure)[0]
        #expect(p.children.filter { $0.kind == .block }.count == 1)
        let blocks = PLSQLOutline.parse(fixtures.last!)[0].children
        #expect(blocks.map(\.kind) == [.block, .block] && blocks[1].children.map(\.name) == ["x"])
    }

    @Test("CASE: instrukcja (END CASE) jest strukturą, wyrażenie CASE … END w PL/SQL i SQL — nie")
    func caseStatementVersusExpression() {
        let src = """
        begin
          x := case when a > 0 then 1 else 0 end;
          select case d when 10 then 'A' else 'B' end into y from dept;
          return case a when 1 then 'x' end;
          case
            when a > 0 then
              p(case b when 1 then 2 end);
            when a < 0 then
              null;
          end case;
          for r in (select case when x = 1 then 'a' end c from t) loop
            null;
          end loop;
          if (case when a = 1 then 1 end) = 1 then null; end if;
        end;
        """
        let nodes = PLSQLOutline.parse(src, controlFlow: true)
        #expect(Self.dump(nodes) == [
            "block BEGIN",
            "  caseStatement CASE",
            "    whenBranch WHEN a > 0",
            "    whenBranch WHEN a < 0",
            "  loop FOR r in (select case when x = 1 then 'a' end c from t)",
            "  ifStatement IF (case when a = 1 then 1 end) = 1",
        ])
        // Blok kończy się na swoim END, nie na END wyrażenia CASE.
        #expect(Self.text(src, nodes[0].range).hasSuffix("end if;\nend;"))
    }

    @Test("etykiety: pętla, blok i struktura z etykietą w węźle; END LOOP etykieta; i END etykieta; zamykają strukturę")
    func labels() {
        let src = """
        begin
          <<zewn>>
          for i in reverse 1 .. 10 loop
            <<blok>>
            declare
              z number;
            begin
              <<wew>> loop
                exit zewn when i = 2;
              end loop wew;
            end blok;
          end loop zewn;
          <<"Etykieta">>
          begin null; end "Etykieta";
        end;
        """
        let nodes = PLSQLOutline.parse(src, controlFlow: true)
        #expect(Self.dump(nodes) == [
            "block BEGIN",
            "  loop <<zewn>> FOR i in reverse 1 .. 10",
            "    block <<blok>> BEGIN",
            "      loop <<wew>> LOOP",
            "  block <<Etykieta>> BEGIN",
        ])
        let block = nodes[0].children[0].children[0]
        // Zakres od „<<” etykiety, nazwa (przejście) — słowo otwierające.
        #expect(Self.text(src, block.range).hasPrefix("<<blok>>\n    declare") && Self.text(src, block.range).hasSuffix("end blok;"))
        #expect(block.nameOffset == (src as NSString).range(of: "declare").location)
        let outer = nodes[0].children[0]
        #expect(Self.text(src, outer.range).hasPrefix("<<zewn>>") && outer.nameOffset == (src as NSString).range(of: "for i").location)
        #expect(Self.text(src, nodes[0].range).hasSuffix("end;"))
    }

    static let unfinished = """
    create or replace package body pk is
      procedure a is
      begin
        if x then
          loop
            null;
        end;
      procedure b is
      begin
        while c loop
          null;
      procedure c is
      begin
        null;
        end if;
        end loop;
      end c;
    end pk;
    """

    @Test("niedokończone struktury: brak END IF/END LOOP kończy je na END nadrzędnym albo granicy podprogramu, END bez dopasowania pomijane")
    func unfinishedStructures() {
        let nodes = PLSQLOutline.parse(Self.unfinished, controlFlow: true)
        #expect(Self.dump(nodes) == [
            "packageBody pk",
            "  procedure a",
            "    ifStatement IF x",
            "      loop LOOP",
            "  procedure b",
            "    loop WHILE c",
            "  procedure c",
        ])
        let a = nodes[0].children[0]
        // Procedura a kończy się na swoim END, struktury przed nim.
        #expect(Self.text(Self.unfinished, a.range).hasSuffix("null;\n    end;"))
        #expect(Self.text(Self.unfinished, a.children[0].range).hasSuffix("null;"))
        // Procedura b bez END — do nagłówka procedury c; c cała (END IF i END LOOP bez dopasowania pominięte).
        let b = nodes[0].children[1]
        #expect(Self.text(Self.unfinished, b.range).hasSuffix("null;"))
        let c = nodes[0].children[2]
        #expect(Self.text(Self.unfinished, c.range).hasSuffix("end c;"))
        #expect(Self.text(Self.unfinished, nodes[0].range).hasSuffix("end pk;"))
    }

    @Test("pisany kod: IF bez THEN i FOR bez LOOP to zwykłe instrukcje; blok bez END w gałęzi kończy się przed ELSE")
    func typing() {
        let src = """
        begin
          if x > 0
          y := 1;
          for i in 1..3
          z := 2;
          if a then
            begin
              null;
          else
            null;
          end if;
          if b then null; end if;
        end;
        """
        let nodes = PLSQLOutline.parse(src, controlFlow: true)
        #expect(Self.dump(nodes) == [
            "block BEGIN",
            "  ifStatement IF a",
            "    block BEGIN",
            "    elseBranch ELSE",
            "  ifStatement IF b",
        ])
        #expect(Self.text(src, nodes[0].range).hasSuffix("end if;\nend;"))
        // Same END bez struktury: nie psują dalszych jednostek.
        let stray = "begin null; end; end; end if;\ncreate procedure q is begin if z then null; end if; end;"
        #expect(Self.dump(PLSQLOutline.parse(stray, controlFlow: true)) == ["block BEGIN", "procedure q", "  ifStatement IF z"])
        // Tekst urwany w środku struktury — do końca tekstu.
        let cut = "begin\n  if a then\n    loop\n      null;"
        let n = PLSQLOutline.parse(cut, controlFlow: true)
        #expect(Self.dump(n) == ["block BEGIN", "  ifStatement IF a", "    loop LOOP"])
        #expect(n[0].range.upperBound == (cut as NSString).length && n[0].children[0].children[0].range.upperBound == (cut as NSString).length)
    }

    @Test("kompilacja warunkowa $IF … $THEN … $ELSE … $END to nie IF, $END nie kończy bloku; literały i komentarze bez struktur")
    func conditionalCompilationAndLiterals() {
        let src = """
        create or replace procedure p is
        begin
          $IF DBMS_DB_VERSION.VER_LE_12 $THEN
            if a then null; end if;
          $ELSIF $$dbg $THEN
            null;
          $ELSE
            $ERROR 'za stara wersja ' || $$PLSQL_UNIT $END
          $END
          x := 'end if; loop begin';
          -- if y then loop
          /* while z loop case */
          y := q'[end; end loop; end case;]';
          for i in 1..2 loop null; end loop;
        end p;
        """
        let nodes = PLSQLOutline.parse(src, controlFlow: true)
        #expect(Self.dump(nodes) == ["procedure p", "  ifStatement IF a", "  loop FOR i in 1..2"])
        #expect(Self.text(src, nodes[0].range).hasSuffix("end p;"))
    }

    @Test("niedomknięta dyrektywa: $IF bez $THEN i literówka $THN nie pochłaniają reszty")
    func unfinishedDirectives() {
        let noThen = """
        create procedure p is
        begin
          $IF $$dbg
          if a then null; end if;
          for i in 1..2 loop null; end loop;
        end p;
        create procedure q is begin null; end;
        """
        let n1 = PLSQLOutline.parse(noThen, controlFlow: true)
        #expect(Self.dump(n1) == ["procedure p", "  ifStatement IF a", "  loop FOR i in 1..2", "procedure q"])
        let typo = "begin\n  $IF $$x IS NULL $THN null; $END\n  while b loop null; end loop;\nend;"
        #expect(Self.dump(PLSQLOutline.parse(typo, controlFlow: true)) == ["block BEGIN", "  loop WHILE b"])
        // Flagi zapytania o nazwach słów kluczowych ($$begin, $$loop) nie kończą warunku.
        let flags = "begin\n  $IF $$begin AND NOT $$loop $THEN\n    if a then null; end if;\n  $END\n  for i in 1..2 loop null; end loop;\nend;"
        #expect(Self.dump(PLSQLOutline.parse(flags, controlFlow: true)) == ["block BEGIN", "  ifStatement IF a", "  loop FOR i in 1..2"])
        let error = "begin\n  $ERROR 'brak' \n  if c then null; end if;\nend;"
        #expect(Self.dump(PLSQLOutline.parse(error, controlFlow: true)) == ["block BEGIN", "  ifStatement IF c"])
    }

    @Test("pisany kod bez średnika: instrukcja kończy się przed ELSE i WHEN gałęzi (poza INSERT ALL, MERGE, EXIT WHEN), deklaracja — przed podprogramem")
    func missingSemicolons() {
        let src = """
        begin
          if a then
            x := 1
          else
            insert all when c > 0 then into t values (1) else into u values (2) select c from s;
          end if;
          case b
            when 1 then y := 2
            when 2 then exit when z > 0;
          end case;
          loop exit when q; end loop;
        end;
        """
        #expect(Self.dump(PLSQLOutline.parse(src, controlFlow: true)) == [
            "block BEGIN",
            "  ifStatement IF a",
            "    elseBranch ELSE",
            "  caseStatement CASE b",
            "    whenBranch WHEN 1",
            "    whenBranch WHEN 2",
            "  loop LOOP",
        ])
        let decl = """
        create or replace package body pk is
          g number
          procedure a is
            x varchar2(10)
          function f return number is begin return 1; end;
          begin null; end a;
          procedure b accessible by (function inny, procedure p2) is begin null; end b;
        end pk;
        create or replace package pk2 is
          procedure c(p number)
          function d return number;
        end;
        """
        let nodes = PLSQLOutline.parse(decl)
        #expect(nodes[0].children.map(\.name) == ["g", "a", "b"])
        #expect(nodes[0].children[1].children.map(\.name) == ["x", "f"])
        #expect(Self.text(decl, nodes[0].children[0].range) == "g number")
        #expect(nodes[1].children.map(\.name) == ["c", "d"])
        #expect(Self.text(decl, nodes[1].children[0].range) == "procedure c(p number)")
    }

    static let compound = """
    create or replace trigger t_emp
      for insert or update on emp
      compound trigger
      g_licznik pls_integer := 0;
      before statement is
      begin
        g_licznik := 0;
      end before statement;
      after each row is
      begin
        if inserting then
          g_licznik := g_licznik + 1;
        end if;
      end after each row;
      after statement is
      begin
        null;
      exception
        when others then null;
      end after statement;
    end t_emp;
    """

    @Test("wyzwalacz złożony: punkty czasowe ze strukturami; wyzwalacz zwykły z blokiem")
    func compoundTrigger() {
        let nodes = PLSQLOutline.parse(Self.compound, controlFlow: true)
        #expect(Self.dump(nodes) == [
            "trigger t_emp",
            "  timingPoint BEFORE statement",
            "  timingPoint AFTER each row",
            "    ifStatement IF inserting",
            "  timingPoint AFTER statement",
            "    exceptionSection EXCEPTION",
            "      exceptionHandler WHEN others",
        ])
        let t = nodes[0]
        #expect(t.children.first?.name == "g_licznik")
        #expect(Self.text(Self.compound, t.children[2].range).hasPrefix("after each row is") && Self.text(Self.compound, t.children[2].range).hasSuffix("end after each row;"))
        #expect(Self.text(Self.compound, t.range).hasSuffix("end t_emp;"))
        let simple = "create trigger t2 before insert on emp for each row\ndeclare v number;\nbegin\n  if :new.x is null then :new.x := 1; end if;\nend;"
        #expect(Self.dump(PLSQLOutline.parse(simple, controlFlow: true)) == ["trigger t2", "  ifStatement IF :new.x is null"])
    }

    static let packageBody = """
    create or replace package body pk as
      function f(a number) return number is
      begin
        <<petla>>
        while a > 0 loop
          return a;
        end loop;
        return 0;
      end f;
    begin
      if f(1) > 0 then
        null;
      end if;
    end pk;
    /
    create or replace type body t_osoba as
      member function opis return varchar2 is
      begin
        case self.plec when 'K' then return 'Pani'; else return 'Pan'; end case;
      end;
    end;
    """

    @Test("ciało pakietu z sekcją inicjalizacji i ciało typu z metodą")
    func packageAndTypeBody() {
        let nodes = PLSQLOutline.parse(Self.packageBody, controlFlow: true)
        #expect(Self.dump(nodes) == [
            "packageBody pk",
            "  function f number",
            "    loop <<petla>> WHILE a > 0",
            "  beginSection BEGIN",
            "    ifStatement IF f(1) > 0",
            "typeBody t_osoba",
            "  function opis varchar2",
            "    caseStatement CASE self.plec",
            "      whenBranch WHEN 'K'",
            "      elseBranch ELSE",
        ])
        // Struktury sterujące bez znacznika publiczny/prywatny.
        #expect(nodes[0].children.last?.isPublic == nil)
    }

    @Test("skrypt okna SQL: struktury w bloku anonimowym i jednostce, polecenia SQL bez zmian")
    func script() {
        let src = """
        select 1 from dual;
        begin
          for r in c loop
            null;
          end loop;
        end;
        /
        create or replace procedure q is
        begin
          if a then null; end if;
        /
        update t set x = 1;
        """
        let nodes = PLSQLOutline.parseScript(src, controlFlow: true)
        #expect(nodes.map(\.kind) == [.statement, .block, .procedure, .statement])
        #expect(Self.dump(nodes) == ["block BEGIN", "  loop FOR r in c", "procedure q", "  ifStatement IF a"])
        #expect(PLSQLOutline.parseScript(src) == PLSQLOutline.withoutControlFlow(nodes))
    }

    @Test("pozycje UTF-16 z polskimi znakami i emoji przed strukturami")
    func utf16Offsets() {
        let src = """
        -- zażółć gęślą jaźń 🦤
        begin
          /* łódź 👍 */ if zmienna_ąę > 0 then
            null;
          end if;
          ŻÓŁW := 'ś';
          while ćma loop null; end loop;
        end;
        """
        let ns = src as NSString
        let nodes = PLSQLOutline.parse(src, controlFlow: true)
        let ifNode = nodes[0].children[0]
        #expect(ifNode.nameOffset == ns.range(of: "if zmienna").location)
        #expect(ifNode.detail == "zmienna_ąę > 0")
        #expect(Self.text(src, ifNode.range).hasSuffix("end if;"))
        let loop = nodes[0].children[1]
        #expect(loop.nameOffset == ns.range(of: "while").location && loop.detail == "ćma")
        #expect(Self.text(src, loop.range) == "while ćma loop null; end loop;")
    }

    @Test("długi nagłówek: szczegóły z białymi znakami zwiniętymi, najwyżej 1000 znaków")
    func longHeader() {
        let cond = (1...300).map { "a\($0) > 0" }.joined(separator: "\n   and ")
        let src = "begin\n  if \(cond) then null; end if;\nend;"
        let n = PLSQLOutline.parse(src, controlFlow: true)[0].children[0]
        #expect(n.kind == .ifStatement && n.detail.hasPrefix("a1 > 0 and a2 > 0") && n.detail.hasSuffix("…"))
        #expect(!n.detail.contains("\n") && n.detail.count <= PLSQLOutline.statementDetailLimit + 1)
    }
}
