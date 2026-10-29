import Foundation
@testable import PelikanSQL
import Testing

/// Formatowanie podczas pisania (D205, PD-BEAU-003): opuszczana linia po Enter i wcięcie nowej linii.
@Suite("Formater: linia przy Enter")
struct BeautifierEnterTests {
    /// Enter w miejscu `|`.
    func enter(_ s: String, options: BeautifierOptions = BeautifierOptions(), lineLimit: Int = Beautifier.enterLineLimit,
               verifier: ((String, String) throws -> Void)? = nil) -> EnterFormatting? {
        let caret = (s as NSString).range(of: "|").location
        let text = (s as NSString).replacingCharacters(in: NSRange(location: caret, length: 1), with: "")
        if let verifier { return Beautifier.formatOnEnter(text, caret: caret, options: options, lineLimit: lineLimit, verifier: verifier) }
        return Beautifier.formatOnEnter(text, caret: caret, options: options, lineLimit: lineLimit)
    }

    func line(_ s: String, options: BeautifierOptions = BeautifierOptions()) -> String? { enter(s, options: options)?.line }
    func indent(_ s: String, options: BeautifierOptions = BeautifierOptions()) -> String? { enter(s, options: options)?.indent }

    @Test("opuszczana linia: wielkość liter słów kluczowych i identyfikatorów, odstępy wokół operatorów i przecinków")
    func caseAndSpacing() {
        #expect(line("select a,b from emp where x=1 and y<>2|") == "SELECT a, b FROM emp WHERE x = 1 AND y <> 2")
        #expect(line("begin\n  x:=nvl(a,0)+1;|") == "  x := nvl(a, 0) + 1;")
        var o = BeautifierOptions()
        o.keywordCase = .lower
        o.identifierCase = .upper
        #expect(line("SELECT a FROM emp|", options: o) == "select A from EMP")
        // Słowo po kropce to nazwa; końcowe odstępy znikają; tekst po kursorze przechodzi do nowej linii bez zmian.
        #expect(line("select t.offset from t   |") == "SELECT t.offset FROM t")
        #expect(enter("select a, |b from t") == EnterFormatting(line: "SELECT a,", indent: "       "))
        // Wyrównanie wpisane przez użytkownika (deklaracje, :=) zostaje, operatory i przecinki — normalizowane.
        #expect(line("declare\n  l_x   number   := 1;|") == "  l_x   NUMBER   := 1;")
        #expect(line("select a  =  b ,c|") == "SELECT a = b, c")
    }

    @Test("rzeka: linia zaczynająca się słowem klauzuli albo AND/OR wyrównana do polecenia, bez przenoszenia tekstu")
    func river() {
        #expect(line("SELECT a,\n       b\nfrom emp|") == "  FROM emp")
        #expect(line("SELECT a\n  FROM emp\nwhere x = 1|") == " WHERE x = 1")
        #expect(line("SELECT a\n  FROM emp\n WHERE x = 1\nand y = 2|") == "   AND y = 2")
        #expect(line("SELECT a\n  FROM t\n WHERE a = 1\norder by a|") == " ORDER BY a")
        #expect(line("SELECT a\n  FROM t\nleft join u on u.id = t.id|") == "  LEFT JOIN u ON u.id = t.id")
        #expect(line("UPDATE emp\nset sal = 1|") == "   SET sal = 1")
        // Polecenie wcięte w bloku: rzeka względem jego słowa otwierającego w dokumencie.
        #expect(line("begin\n    select a\n      into l_a\n from t|") == "      FROM t")
        // WITH, MERGE: formater przesuwa słowo otwierające do rzeki (`  WITH`); wpisane w kolumnie instrukcji — rzeka
        // względem tej kolumny, przesunięte jak w kodzie sformatowanym — względem słowa.
        #expect(line("with x as (select 1 a from dual)\nselect a|") == "SELECT a")
        #expect(line("with x as (select 1 a from dual)\nselect a\nfrom x|") == "  FROM x")
        #expect(line("  WITH x AS (SELECT 1 a FROM dual)\nselect a|") == "SELECT a")
        #expect(line("begin\n  merge into t\nusing s|") == "   USING s")
        // Słowo klauzuli w środku linii nie łamie linii.
        #expect(line("SELECT a FROM t WHERE x = 1|") == "SELECT a FROM t WHERE x = 1")
        // Słowa klauzul do lewej.
        var o = BeautifierOptions()
        o.clauseLayout = .leftAligned
        #expect(line("SELECT a\nFROM   t\n  where x = 1|", options: o) == "WHERE  x = 1")
        // Wcześniejsza linia klauzuli tej instrukcji jest kotwicą (wcięcie użytkownika zachowane względem niej).
        #expect(line("SELECT a\n  FROM t\n  where x = 1|", options: o) == "  WHERE  x = 1")
    }

    @Test("struktura bloku: END, ELSE, EXCEPTION i nawias zamykający podzapytania wyrównane do otwierającego")
    func blockWords() {
        #expect(line("begin\n  if a > 0 then\n    x := 1;\n    end if;|") == "  END IF;")
        #expect(line("begin\n  if a > 0 then\n    x := 1;\n    else|") == "  ELSE")
        #expect(line("begin\n    x := 1;\n    end;|") == "END;")
        #expect(line("begin\n  null;\n  exception|") == "EXCEPTION")
        #expect(line("SELECT *\n  FROM (\n         SELECT a\n           FROM t\n)|") == "       )")
        // Zwykła instrukcja zachowuje wcięcie użytkownika.
        #expect(line("begin\n      x:=1;|") == "      x := 1;")
    }

    @Test("wcięcie nowej linii: lista po przecinku, treść bloku, następna klauzula, podzapytanie, CASE, styl wcięć użytkownika")
    func newLineIndent() {
        #expect(indent("SELECT a,|") == "       ")
        #expect(indent("SELECT|") == "       ")
        #expect(indent("SELECT a|") == "")
        #expect(indent("SELECT a\n  FROM emp|") == "")
        #expect(indent("UPDATE emp\n   SET a = 1,|") == "       ")
        #expect(indent("begin|") == "  ")
        #expect(indent("begin\n  if a > 0 then|") == "    ")
        #expect(indent("begin\n  for i in 1..10 loop|") == "    ")
        #expect(indent("begin\n  if a > 0 then\n    x := 1;\n  end if;|") == "  ")
        #expect(indent("create or replace procedure p is|") == "  ")
        #expect(indent("SELECT *\n  FROM (|") == "         ")
        #expect(indent("x := f(a,|") == "       ")
        #expect(indent("begin\n  x := CASE|") == "         ")
        // Wcięcie użytkownika (4) zostaje dla kolejnych instrukcji; pusta linia — wcięcie jak po poprzedniej.
        #expect(indent("begin\n    x := 1;|") == "    ")
        // Enter na początku linii albo w jej wiodących odstępach — zwykły Enter (D205).
        #expect(enter("begin\n  x := 1;\n  |") == nil)
        #expect(enter("begin\n|  x := 1;") == nil)
        #expect(enter("begin\n  |x := 1;") == nil)
        var o = BeautifierOptions()
        o.useTabs = true
        #expect(indent("begin\n\tif a then|", options: o) == "\t\t")
    }

    @Test("wyjątki: komentarze, literały wieloliniowe, kompilacja warunkowa, SQL*Plus, Java, region bez formatowania")
    func exceptions() {
        // Komentarz `--` na końcu linii bez zmian, część przed nim — normalizowana; linia komentarza — bez zmian.
        #expect(line("x:=1;   --  a  b|") == "x := 1;   --  a  b")
        #expect(line("begin\n    --  a  b|") == "    --  a  b")
        #expect(enter("/* a\n b|") == nil)
        #expect(enter("x := 'ab|c';") == nil)
        #expect(enter("x := q'[abc\ndef]' || 'x';|") == nil)
        #expect(enter("x := 1; -- ko|mentarz") != nil)
        #expect(enter("$IF $$debug $THEN\n  a := 1;|") == nil)
        #expect(enter("begin\n  $if $$debug $then\n    a := 1;|\n  $end\nend;") == nil)
        #expect(enter("set serveroutput on|") == nil)
        #expect(enter("create or replace and compile java source named x as\npublic class X {|") == nil)
        #expect(enter("-- NoFormat Start\nselect   a|\n-- NoFormat End") == nil)
    }

    @Test("niedomknięty nawias: tylko wielkość liter; verify odrzuca — linia bez zmian")
    func safety() {
        let open = enter("select f(a,b|")
        #expect(open?.line == "SELECT f(a,b")
        #expect(open?.indent == "         ")
        struct Rejected: Error {}
        let rejected = enter("select a,b from t|", verifier: { _, _ in throw Rejected() })
        #expect(rejected?.line == "select a,b from t")
        // Linia po zmianie ma te same tokeny co przed — weryfikacja domyślna przechodzi dla każdego przypadku z testów.
        let checked = enter("select a,b from t|", verifier: { a, b in try Beautifier.verify(original: a, formatted: b) })
        #expect(checked?.line == "SELECT a, b FROM t")
    }

    @Test("długie polecenie: tylko wielkość liter, a w ciele pakietu — kontekst od początku podprogramu")
    func longStatements() {
        let plain = enter("select a,\n b,\n c,\n d,\n e from t|", lineLimit: 2)
        #expect(plain == EnterFormatting(line: " e FROM t", indent: nil))
        var body = "create or replace package body p is\n"
        for n in 0..<5 { body += "  procedure p\(n) is\n  begin\n    null;\n  end;\n" }
        body += "  procedure z is\n  begin\n    if a>0 then|"
        let sub = enter(body, lineLimit: 10)
        #expect(sub == EnterFormatting(line: "    IF a > 0 THEN", indent: "      "))
    }

    @Test("pamięć podziału: początek polecenia linii, ważny do zmiany tekstu przed nim")
    func statementMemory() {
        let text = "select 1 from dual;\nbegin\n  null;\n  x := 1;\nend;\n/\nselect 2\n  from dual" as NSString
        var m = StatementStartMemory()
        let inBlock = text.range(of: "  x := 1;").location
        #expect(m.contextStart(forLineAt: inBlock, in: text) == text.range(of: "begin").location)
        let inSelect = text.range(of: "  from dual").location
        #expect(m.contextStart(forLineAt: inSelect, in: text) == text.range(of: "select 2").location)
        #expect(m.starts.contains(0) && m.starts.contains(text.range(of: "begin").location))
        // Linia po zakończonym poleceniu zaczyna nowe.
        #expect(m.contextStart(forLineAt: text.range(of: "begin").location, in: text) == text.range(of: "begin").location)
        m.invalidate(from: text.range(of: "begin").location)
        #expect(m.starts == [0])
    }

    @Test("korpus: Enter na końcu każdej linii — kod sformatowany zostaje bez zmian, każdy wynik zachowuje tokeny")
    func corpus() throws {
        for src in BeautifierOptionsTests.corpus {
            let formatted = try Beautifier.format(src)
            for text in [src, formatted] {
                let ns = text as NSString
                var p = 0
                while p < ns.length {
                    let lr = ns.lineRange(for: NSRange(location: p, length: 0))
                    var end = lr.location + lr.length
                    if end > lr.location, ns.character(at: end - 1) == 0x0A { end -= 1 }
                    let left = ns.substring(with: NSRange(location: lr.location, length: end - lr.location))
                    if let r = Beautifier.formatOnEnter(text, caret: end) {
                        if text == formatted {
                            #expect(r.line == String(left.reversed().drop { $0 == " " }.reversed()), "\(left.debugDescription) → \(r.line.debugDescription)")
                        }
                        let a = ns.replacingCharacters(in: NSRange(location: end, length: 0), with: "\n")
                        let b = ns.replacingCharacters(in: NSRange(location: lr.location, length: end - lr.location), with: r.line + "\n")
                        #expect(throws: Never.self, "\(left.debugDescription)") { try Beautifier.verify(original: a, formatted: b) }
                    }
                    p = lr.location + lr.length
                }
            }
        }
    }

    @Test("linia nieedytowana: bez zmian, tylko wcięcie nowej linii")
    func untouchedLine() {
        let caret = ("begin\n  if a>0 then" as NSString).length
        let r = Beautifier.formatOnEnter("begin\n  if a>0 then", caret: caret, formatLine: false)
        #expect(r == EnterFormatting(line: "  if a>0 then", indent: "    "))
    }

    @Test("słowo po kropce: reguła identyfikatora (nie typu); ß w pisowni źródła, verify porównuje je dokładnie")
    func afterDot() throws {
        #expect(line("select j.doc.date from t j|") == "SELECT j.doc.date FROM t j")
        var o = BeautifierOptions()
        o.identifierCase = .upper
        #expect(try Beautifier.format("select j.doc.date, e.ename from t j", options: o) == "SELECT J.DOC.DATE,\n       E.ENAME\n  FROM T J")
        o.identifierCase = .lower
        o.dataTypeCase = .upper
        #expect(try Beautifier.format("select j.doc.Date from t j", options: o) == "SELECT j.doc.date\n  FROM t j")
        #expect(throws: Never.self) { try Beautifier.verify(original: "select j.doc.date from t", formatted: "SELECT J.DOC.DATE FROM T") }
        #expect(throws: BeautifierError.self) { try Beautifier.verify(original: "x := straße;", formatted: "x := STRASSE;") }
        o.identifierCase = .upper
        #expect(try Beautifier.format("x := straße;", options: o) == "X := straße;")
    }

    @Test("regiony otwarte przed poleceniem: NoFormat i $IF obejmujące kilka poleceń albo podprogram")
    func regionsBeforeStatement() {
        #expect(enter("-- NoFormat Start\nselect 1 from dual;\nselect a,b from t|") == nil)
        #expect(enter("-- @formatter:off\nselect 1 from dual;\nselect a,b from t|") == nil)
        #expect(line("-- NoFormat Start\nselect 1 from dual;\n-- NoFormat End\nselect a,b from t|") == "SELECT a, b FROM t")
        // '-- NoFormat Start' w literale nie otwiera regionu.
        #expect(line("x := '-- NoFormat Start';\nselect a,b from t|") == "SELECT a, b FROM t")
        var body = "create or replace package body p is\n$if $$debug $then\n"
        for n in 0..<5 { body += "  procedure p\(n) is\n  begin\n    null;\n  end;\n" }
        body += "  procedure z is\n  begin\n    if a>0 then|"
        #expect(enter(body, lineLimit: 10) == nil)
    }

    @Test("długie polecenie: Java/MLE, linia z dyrektywą i region bez formatowania — bez zmian")
    func longStatementExceptions() {
        var java = "create or replace and compile java source named x as\npublic class X {\n"
        for _ in 0..<5 { java += "  int a;\n" }
        java += "  if (a) return|"
        #expect(enter(java, lineLimit: 3) == nil)
        var block = "begin\n"
        for _ in 0..<5 { block += "  null;\n" }
        #expect(enter(block + "  $if $$x $then a:=1; $end|", lineLimit: 3) == nil)
        #expect(enter(block + "  -- NoFormat Start\n  x:=1;|", lineLimit: 3) == nil)
        #expect(enter(block + "  x:=1;|", lineLimit: 3) == EnterFormatting(line: "  x:=1;", indent: nil))
    }

    @Test("para specyfikacja + ciało bez „/” dłuższa niż limit: kontekst od podprogramu ciała")
    func specAndBody() {
        var text = "create or replace package p is\n  -- opis\n  procedure p0;\nend;\n"
        text += "create or replace\n  -- ciało\n  package body p is\n"
        for n in 0..<5 { text += "  procedure p\(n) is\n  begin\n    null;\n  end;\n" }
        text += "  procedure z is\n  begin\n    if a>0 then|"
        #expect(enter(text, lineLimit: 10) == EnterFormatting(line: "    IF a > 0 THEN", indent: "      "))
    }

    @Test("wydajność: pakiet ~20 tys. linii i para — Enter bez leksowania całego pliku")
    func performance() {
        func body(_ n: Int) -> String {
            var s = ""
            for k in 0..<n {
                s += "  procedure p\(k)(a in number, b out varchar2) is\n    l_x number := 0;\n  begin\n"
                s += "    select count(*) into l_x from emp e join dept d on d.deptno = e.deptno where e.sal > a and d.loc = 'X';\n"
                s += "    if l_x > 0 then\n      b := 'tak';\n    else\n      b := 'nie';\n    end if;\n"
                s += "    for r in (select * from emp) loop\n      dbms_output.put_line(r.ename);\n    end loop;\n  end;\n\n"
            }
            return s
        }
        let package = "create or replace package body p is\n" + body(1400) + "  procedure z is\n  begin\n    x := 1;"
        let pair = "create or replace package p is\n  procedure z;\nend;\n/\n" + package
        let clock = ContinuousClock()
        for (name, text) in [("pakiet", package), ("para", pair)] {
            var memory = StatementStartMemory()
            let ns = text as NSString
            let caret = ns.length
            let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
            var r: EnterFormatting?
            let first = clock.measure {
                let c = memory.context(forLineAt: lineStart, in: ns)
                r = Beautifier.formatOnEnter(text, caret: caret, context: c)
            }
            #expect(r?.line == "    x := 1;")
            // Kolejny Enter niżej (po zmianie tekstu za punktami kontrolnymi): leksowanie tylko od podprogramu.
            let more = text + "\n    y:=2;"
            memory.invalidate(from: caret)
            let scanned = memory.scannedLength
            let mns = more as NSString
            let next = clock.measure {
                let c = memory.context(forLineAt: mns.lineRange(for: NSRange(location: mns.length, length: 0)).location, in: mns)
                r = Beautifier.formatOnEnter(more, caret: mns.length, context: c)
            }
            #expect(r?.line == "    y := 2;")
            #expect(memory.scannedLength - scanned < 2000, "\(name): leksowanie od punktu kontrolnego")
            // Enter w środku pakietu (po zmianie w podprogramie p700): od jego punktu kontrolnego.
            let p700 = mns.range(of: "procedure p700(").location
            let ifLine = mns.range(of: "    if l_x > 0 then", options: [], range: NSRange(location: p700, length: mns.length - p700))
            let middle = mns.replacingCharacters(in: ifLine, with: "    if l_x>0 then")
            memory.invalidate(from: ifLine.location)
            let before = memory.scannedLength
            let caretMid = ifLine.location + ("    if l_x>0 then" as NSString).length
            let mid = clock.measure {
                let c = memory.context(forLineAt: ifLine.location, in: middle as NSString)
                r = Beautifier.formatOnEnter(middle, caret: caretMid, context: c)
            }
            #expect(r == EnterFormatting(line: "    IF l_x > 0 THEN", indent: "      "))
            #expect(memory.scannedLength - before < 2000, "\(name): Enter w środku — od punktu kontrolnego")
            print("Enter \(name) \(ns.length) znaków, \(text.split(separator: "\n").count) linii: pierwszy \(first), kolejny \(next), w środku \(mid)")
        }
    }
}
