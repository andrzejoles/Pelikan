import Foundation
@testable import PelikanSQL
import Testing

/// Opcje formatera (D174): wyrównania, układ klauzul, łamanie linii, odstępy, wielkość liter grup słów, przykłady.
@Suite("Formater — opcje")
struct BeautifierOptionsTests {
    func f(_ s: String, _ change: (inout BeautifierOptions) -> Void) throws -> String {
        var o = BeautifierOptions.legacy
        change(&o)
        return try Beautifier.format(s, options: o)
    }

    /// Ustawienia z wszystkimi wyrównaniami i nietypowym układem — do sprawdzania bezpieczeństwa i idempotencji.
    static var heavy: BeautifierOptions {
        var o = BeautifierOptions()
        o.alignDeclarations = true; o.alignParameters = true; o.alignNamedArguments = true; o.alignAssignments = true
        o.alignAliases = true; o.alignSetValues = true; o.alignTrailingComments = true
        o.parameterDeclarations = .onePerLine; o.callParameters = .onePerLine; o.insertLists = .onePerLine
        o.caseLayout = .multiline; o.thenOnNewLine = true; o.blankLineBetweenSubprograms = true; o.maxBlankLines = 2
        o.dataTypeCase = .lower; o.functionCase = .upper; o.packageCase = .upper
        return o
    }

    static var corpus: [String] {
        [BeautifierTests.query, BeautifierTests.body, BeautifierTests.misc] + BeautifierExamples.previews.map(\.code)
            + BeautifierExamples.all.map(\.snippet)
    }

    @Test("każda opcja zmienia swój przykład; każda wartość każdej opcji zmienia przypisany przykład podglądu i zmiana jest zaznaczona")
    func everyOptionVisible() throws {
        for base in [BeautifierOptions(), Self.heavy] {
            for e in BeautifierExamples.all {
                let now = try Beautifier.format(e.snippet, options: base)
                let other = try Beautifier.format(e.snippet, options: e.variant(base))
                #expect(now != other, "przykład \(e.id) bez zmiany")
            }
            // Podgląd: przypisany przykład (PL/SQL, Zapytania, DML, DDL) przy każdej innej wartości każdej opcji i każdej
            // reguły AND/OR każdego miejsca.
            for key in BeautifierExamples.previewKeys {
                let sample = try #require(BeautifierExamples.previewOf[key].flatMap(BeautifierExamples.previewSample), "\(key) bez przykładu podglądu")
                let prepared = BeautifierExamples.prepared(key, base)
                let shown = try Beautifier.format(sample.code, options: prepared)
                let values = BeautifierExamples.alternatives(key, base)
                #expect(!values.isEmpty, "\(key) bez wartości")
                for v in values {
                    let changed = try Beautifier.format(sample.code, options: v)
                    #expect(changed != shown, "podgląd \(sample.id) nie pokazuje opcji \(key) = \(v)")
                    #expect(!BeautifierExamples.marks(baseline: shown, current: changed).isEmpty, "\(key): zmiana bez zaznaczenia")
                }
            }
        }
        // Każda opcja wpływająca na wynik ma przykład i przykład podglądu; każde miejsce warunków — trzy reguły.
        let documented = Set(BeautifierExamples.all.map(\.id))
        let mirror = Mirror(reflecting: BeautifierOptions()).children.compactMap(\.label)
        let automatic: Set<String> = ["afterLoad", "beforeCompile", "beforeSave", "defaultsVersion"]
        #expect(Set(mirror).subtracting(automatic) == documented)
        #expect(documented.isSubset(of: Set(BeautifierExamples.previewOf.keys)))
        #expect(BeautifierExamples.previewKeys.count == documented.count - 1 + 3 * BeautifierOptions.ConditionContext.allCases.count)
    }

    @Test("znaczniki podglądu: zmienione, dodane i miejsce usuniętych linii")
    func previewMarks() {
        let m = BeautifierExamples.marks(baseline: "a\nb\n\nc\nd", current: "a\nB\nc\nd\ne")
        #expect(m.changed == [1, 4])
        #expect(m.removedBefore == [2])
        #expect(m.first == 1)
        #expect(BeautifierExamples.marks(baseline: "a\n\n\nb", current: "a\n\nb").removedBefore == [2])
        #expect(BeautifierExamples.marks(baseline: "x", current: "x").isEmpty)
    }

    @Test("bezpieczeństwo i idempotencja przy każdej opcji osobno i wszystkich naraz")
    func safetyAllCombinations() throws {
        var cumulative = BeautifierOptions()
        var configs: [BeautifierOptions] = [Self.heavy]
        for e in BeautifierExamples.all {
            configs.append(e.variant(BeautifierOptions()))
            cumulative = e.variant(cumulative)
            configs.append(cumulative)
        }
        for o in configs {
            for s in Self.corpus {
                let once = try Beautifier.format(s, options: o)   // weryfikacja tokenów wewnątrz
                #expect(try Beautifier.format(once, options: o) == once, "nieidempotentne:\n\(once)")
            }
        }
    }

    @Test("wyrównanie deklaracji, przypisań i komentarzy")
    func alignDeclarations() throws {
        let out = try f("declare\nv_id number; -- klucz\nv_nazwa varchar2(10) := 'x'; -- nazwa\nbegin\nv_id := 1;\nv_nazwa := 'y'; -- nowa\nend;") {
            $0.alignDeclarations = true; $0.alignAssignments = true; $0.alignTrailingComments = true
        }
        #expect(out == """
            DECLARE
              v_id    NUMBER;              -- klucz
              v_nazwa VARCHAR2(10) := 'x'; -- nazwa
            BEGIN
              v_id    := 1;
              v_nazwa := 'y'; -- nowa
            END;
            """)
    }

    @Test("wyrównanie parametrów (tryb, typ, DEFAULT) i parametrów nazwanych, także z przecinkiem na początku")
    func alignLists() throws {
        let src = "procedure p(p_id in number, p_nazwa out varchar2, p_od date default sysdate) is begin q(a => 1, bb => 2); end;"
        let out = try f(src) { $0.alignParameters = true; $0.parameterDeclarations = .onePerLine; $0.alignNamedArguments = true; $0.callParameters = .onePerLine }
        #expect(out == """
            PROCEDURE p(p_id    IN  NUMBER,
                        p_nazwa OUT VARCHAR2,
                        p_od        DATE DEFAULT SYSDATE) IS
            BEGIN
              q(a  => 1,
                bb => 2);
            END;
            """)
        let comma = try f("select a x, bbb y from t") { $0.alignAliases = true; $0.commaBefore = true }
        #expect(comma == "SELECT a   x\n     , bbb y\nFROM   t")
    }

    @Test("układ klauzul: do prawej i w osobnej linii; AND na końcu linii; ON w linii JOIN")
    func clauseLayouts() throws {
        let q = "select a, b from t join u on u.id = t.id where a = 1 and b = 2 order by a"
        #expect(try f(q) { $0.clauseLayout = .ownLine } == """
            SELECT
              a,
              b
            FROM
              t
            JOIN
              u
              ON u.id = t.id
            WHERE
              a = 1
              AND b = 2
            ORDER BY
              a
            """)
        #expect(try f(q) { $0.clauseLayout = .rightAligned; $0.andOrPosition = .lineEnd; $0.joinConditionOnNewLine = false } == """
            SELECT a,
                   b
              FROM t
              JOIN u ON u.id = t.id
             WHERE a = 1 AND
                   b = 2
             ORDER BY a
            """)
    }

    @Test("klauzule w osobnej linii: wyrównanie aliasów i UPDATE … SET od linii po słowie klauzuli")
    func ownLineAlignment() throws {
        let q = "select e.a x, e.bbb yy from emp e, department d"
        #expect(try f(q) { $0.clauseLayout = .ownLine; $0.alignAliases = true } == """
            SELECT
              e.a   x,
              e.bbb yy
            FROM
              emp        e,
              department d
            """)
        let u = try f("update t set a = 1, bbb = 2 where c = 3") { $0.clauseLayout = .ownLine; $0.alignSetValues = true }
        #expect(u.contains("  a   = 1,\n  bbb = 2"), "\(u)")
    }

    @Test("AND/OR na końcu linii po komentarzu: warunek na początku następnej linii, nie samo AND")
    func andAfterLineComment() throws {
        let r = try f("select a from t where x = 1 -- c\n and y = 2 and z = 3") { $0.andOrPosition = .lineEnd }
        let lines = r.components(separatedBy: "\n")
        #expect(!lines.contains { $0.trimmingCharacters(in: .whitespaces) == "AND" }, "\(r)")
        #expect(lines.contains { $0.hasSuffix("x = 1 -- c") }, "\(r)")
        #expect(lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("AND") && $0.contains("y = 2 AND") }, "\(r)")
    }

    @Test("THEN w osobnej linii, CASE wieloliniowy w PL/SQL i SQL, CASE z AND w WHERE")
    func thenAndCase() throws {
        #expect(try f("begin if a then x := case when b then 1 else 2 end; end if; end;") { $0.thenOnNewLine = true; $0.caseLayout = .multiline } == """
            BEGIN
              IF a
              THEN
                x := CASE
                       WHEN b THEN 1
                       ELSE 2
                     END;
              END IF;
            END;
            """)
        #expect(try f("select a from t where case when a = 1 and b = 2 then 1 end = 1") { _ in } == "SELECT a\nFROM   t\nWHERE  CASE WHEN a = 1 AND b = 2 THEN 1 END = 1")
    }

    @Test("odstępy: operatory bez spacji bez sklejania w komentarz, spacje w nawiasach, bez spacji po przecinku")
    func spacing() throws {
        #expect(try f("begin x := a - -1; y := b / *c; end;") { $0.spaceAroundOperators = false } == "BEGIN\n  x := a- -1;\n  y := b/ *c;\nEND;")
        #expect(try f("select f( a,b ), g() from t") { $0.spaceInsideParentheses = true; $0.spaceAfterComma = false; $0.listLayout = .fit } == "SELECT f( a,b ),g()\nFROM   t")
        #expect(try f("select * from t where a<>b") { $0.spaceAroundOperators = false } == "SELECT *\nFROM   t\nWHERE  a<>b")
    }

    @Test("wielkość liter grup słów: typy, funkcje (przed nawiasem), pakiety (przed kropką); dziedziczenie")
    func wordClasses() throws {
        let src = "declare v number; begin v := nvl(v, 0); dbms_output.put_line(to_char(v)); select count into v from count; end;"
        #expect(try f(src) { $0.dataTypeCase = .lower; $0.functionCase = .upper; $0.packageCase = .upper; $0.keywordCase = .upper } == """
            DECLARE
              v number;
            BEGIN
              v := NVL(v, 0);
              DBMS_OUTPUT.put_line(TO_CHAR(v));
              SELECT count
              INTO   v
              FROM   count;
            END;
            """)
        // Bez własnych reguł typy idą za słowami kluczowymi, funkcje i pakiety — za identyfikatorami.
        #expect(try f("declare v number; begin v := nvl(v, 0); end;") { $0.keywordCase = .lower; $0.identifierCase = .upper } == "declare\n  V number;\nbegin\n  V := NVL(V, 0);\nend;")
    }

    @Test("puste linie: najwyżej n z rzędu, pusta linia między podprogramami; znaczniki @formatter:off/on")
    func blankLinesAndMarkers() throws {
        #expect(try f("begin\nx := 1;\n\n\n\n\ny := 2;\nend;") { $0.maxBlankLines = 2 } == "BEGIN\n  x := 1;\n\n\n  y := 2;\nEND;")
        let out = try f("begin\n-- @formatter:off\n  x   :=   1;\n-- @formatter:on\ny:=2;\nend;") { $0.alignAssignments = true }
        #expect(out == "BEGIN\n-- @formatter:off\n  x   :=   1;\n-- @formatter:on\n  y := 2;\nEND;")
    }

    @Test("wydajność z wszystkimi wyrównaniami: pakiet 50 000 linii")
    func performanceHeavy() throws {
        var s = "create or replace package body big as\n"
        for i in 1...5000 {
            s += "procedure p\(i)(a number, bb varchar2) is v number; ww varchar2(10) := 'x'; begin v := a; ww := bb; -- k\nselect count(*) cnt, max(x) mx into v, ww from dual where 1=1; end p\(i);\n"
        }
        s += "end big;\n/\n"
        let clock = ContinuousClock()
        var lines = 0
        let t = try clock.measure { lines = try Beautifier.format(s, options: Self.heavy).components(separatedBy: "\n").count }
        #expect(lines > 50_000)
        #expect(t < (ProcessInfo.processInfo.environment["PELIKAN_PERF_STRICT"] == "1" ? .seconds(4) : .seconds(30)), "\(t)")
    }

    @Test("ustawienia: zapis i odczyt nowych opcji, starszy zapis bez nich — wartości domyślne")
    func coding() throws {
        let h = Self.heavy
        #expect(try JSONDecoder().decode(BeautifierOptions.self, from: JSONEncoder().encode(h)) == h)
        let old = try JSONDecoder().decode(BeautifierOptions.self, from: Data(#"{"indent":4,"keywordCase":"lower"}"#.utf8))
        #expect(old.indent == 4 && old.keywordCase == .lower && old.clauseLayout == .rightAligned && old.dataTypeCase == nil && old.alignDeclarations && old.caseLayout == .auto)
    }
}
