import Foundation
import PelikanSQL
import Testing

/// Pomiary wydajności (cele w konfiguracji Release: `make test-release`, PELIKAN_PERF_STRICT=1).
/// W Debug cele są luźniejsze (×15) — testy pilnują rzędu wielkości, a twarde cele sprawdza Release.
enum Perf {
    static let strict = ProcessInfo.processInfo.environment["PELIKAN_PERF_STRICT"] == "1"
    static func target(_ release: Duration) -> Duration { strict ? release : release * 15 }

    static func measure(_ iterations: Int = 5, _ body: () -> Void) -> Duration {
        let clock = ContinuousClock()
        var best = Duration.seconds(1000)
        for _ in 0..<iterations { best = min(best, clock.measure(body)) }
        return best
    }

    static func ms(_ d: Duration) -> String { String(format: "%.2f ms", Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000) }

    /// Wynik pomiaru do raportu (scripts/status.py perf) — tylko w Release (PELIKAN_PERF_STRICT=1); w Debug cel Release
    /// i tak nie obowiązuje, a „fail” przy zielonym teście tylko mylił w dzienniku.
    static func report(_ name: String, _ value: Duration, _ target: Duration) {
        guard strict else { return }
        print("PERF\t\(name)\t\(ms(value))\t< \(ms(target))\t\(value < target ? "ok" : "fail")")
    }

    /// Pakiet PL/SQL z ok. 50 000 linii: procedury z kursorami, komentarzami, literałami.
    static let package50k: String = {
        var s = "create or replace package body big_pkg as\n"
        var n = 1
        while n <= 5000 {
            s += """
              /* procedura \(n)
                 opis wieloliniowy */
              procedure proc_\(n)(p_id in number, p_name in varchar2 default 'x''y') is
                cursor c is select e.empno, e.ename from emp e where e.deptno = p_id; -- kursor
                v_txt varchar2(4000) := q'[tekst ; z / średnikiem]';
              begin
                for r in c loop
                  dbms_output.put_line(r.ename || ' ' || to_char(:b_\(n)));
                end loop;
              end proc_\(n);

            """
            n += 1
        }
        return s + "end big_pkg;\n/\n"
    }()

    /// Pakiet z ok. 50 000 linii gęsto wypełniony strukturami sterującymi (D203): w każdej procedurze IF z ELSIF
    /// i ELSE, pętle FOR (kursorowa z zapytaniem i liczbowa), WHILE z etykietą, instrukcja CASE, FORALL, blok
    /// zagnieżdżony z obsługą wyjątków — 13 struktur i blok na 20 linii.
    static let controlFlow50k: String = {
        var s = "create or replace package body flow_pkg as\n"
        for n in 1...2500 {
            s += """
              procedure proc_\(n)(p_id in number) is
                v number := 0;
              begin
                if p_id > \(n) then
                  for r in (select case when e.sal > 0 then 1 end s from emp e where e.deptno = p_id) loop
                    v := v + r.s;
                  end loop;
                elsif p_id < 0 then
                  <<petla>> while v < 10 loop v := v + 1; end loop petla;
                else
                  case p_id when 1 then forall i in 1..10 insert into t values (i); else null; end case;
                end if;
                for i in 1..p_id loop v := v + case when i > 2 then 1 else 0 end; end loop;
                begin
                  v := v / p_id;
                exception
                  when zero_divide then v := 0;
                  when others then raise;
                end;
              end proc_\(n);

            """
        }
        return s + "end flow_pkg;\n/\n"
    }()
}

@Suite("PerformanceTests — edytor i lekser", .serialized)
struct SQLPerformanceTests {
    @Test("Pakiet ma ok. 50 000 linii")
    func size() {
        let lines = Perf.package50k.utf16.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        #expect(lines >= 50_000)
    }

    @Test("Pełne podświetlenie pakietu 50 000 linii (otwarcie pliku)")
    func lexAll() {
        let text = Array(Perf.package50k.utf16)
        var tokens = 0
        let t = Perf.measure(3) {
            tokens = 0
            IncrementalLexer().lexAll(text, onLine: { _ in }, onToken: { _ in tokens += 1 })
        }
        let target = Perf.target(.milliseconds(250))
        Perf.report("Podświetlenie całego pakietu 50 000 linii", t, .milliseconds(250))
        #expect(tokens > 500_000)
        #expect(t < target, "\(Perf.ms(t))")
    }

    @Test("Wpisanie znaku w środku pakietu 50 000 linii: kopia tekstu + linie + leksowanie zmiany")
    func keystroke() {
        let base = Array(Perf.package50k.utf16)
        let inc = IncrementalLexer()
        inc.lexAll(base, onLine: { _ in }, onToken: { _ in })
        let at = inc.lineStarts[25_003] + 6
        var text = base
        var lines = 0
        let t = Perf.measure(20) {
            text.insert(0x78, at: at)                       // „x”
            let copy = text                                 // edytor kopiuje bufor UTF-16 z NSTextStorage
            lines = 0
            inc.relex(copy, editedRange: at..<(at + 1), delta: 1, onLine: { _ in lines += 1 }, onToken: { _ in })
            text.remove(at: at)
            inc.relex(text, editedRange: at..<at, delta: -1, onLine: { _ in }, onToken: { _ in })
        }
        Perf.report("Klawisz w pakiecie 50 000 linii (podświetlanie przyrostowe)", t, .milliseconds(8))
        #expect(lines == 1)
        #expect(t < Perf.target(.milliseconds(8)), "\(Perf.ms(t))")
    }

    @Test("Dzielenie pakietu 50 000 linii na polecenia (F8 / Ctrl+F8)")
    func split() {
        var count = 0
        let t = Perf.measure(3) { count = ScriptSplitter.split(Perf.package50k).count }
        Perf.report("Dzielenie skryptu 50 000 linii na polecenia", t, .milliseconds(400))
        #expect(count == 1)
        #expect(t < Perf.target(.milliseconds(400)), "\(Perf.ms(t))")
    }

    @Test("Zawartość kodu skryptu 50 000 poleceń (okno SQL, w tle) i pakietu 50 000 linii")
    func scriptOutline() {
        let script = (1...50_000).map { "select e.empno, e.ename /* \($0) */ from emp e where e.deptno = :d_\($0);\n" }.joined()
        var outline = PLSQLOutline.ScriptOutline(nodes: [])
        let t = Perf.measure(3) { outline = PLSQLOutline.parseScriptOutline(script) }
        Perf.report("Zawartość kodu skryptu 50 000 poleceń", t, .milliseconds(600))
        #expect(outline.omittedStatements == 50_000 && outline.nodes.isEmpty)
        #expect(t < Perf.target(.milliseconds(600)), "\(Perf.ms(t))")
        // Do limitu — polecenia ze szczegółami.
        let limit = (1...PLSQLOutline.scriptStatementLimit).map { "select e.empno, e.ename /* \($0) */ from emp e where e.deptno = :d_\($0);\n" }.joined()
        var nodes: [OutlineNode] = []
        let t2 = Perf.measure(3) { nodes = PLSQLOutline.parseScript(limit) }
        #expect(nodes.count == PLSQLOutline.scriptStatementLimit)
        Perf.report("Zawartość kodu skryptu 5000 poleceń ze szczegółami", t2, .milliseconds(100))
        #expect(t2 < Perf.target(.milliseconds(100)), "\(Perf.ms(t2))")
        var pkg: [OutlineNode] = []
        let t3 = Perf.measure(3) { pkg = PLSQLOutline.parseScript(Perf.package50k) }
        Perf.report("Zawartość kodu pakietu 50 000 linii w oknie SQL", t3, .milliseconds(600))
        #expect(pkg.count == 1)
        #expect(t3 < Perf.target(.milliseconds(600)), "\(Perf.ms(t3))")
    }

    @Test("Zawartość kodu ze strukturami sterującymi: pakiet 50 000 linii gęsto wypełniony strukturami (D203)")
    func controlFlowOutline() {
        let lines = Perf.controlFlow50k.utf16.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        #expect(lines >= 50_000)
        var nodes: [OutlineNode] = []
        let t = Perf.measure(3) { nodes = PLSQLOutline.parse(Perf.controlFlow50k, controlFlow: true) }
        Perf.report("Zawartość kodu ze strukturami sterującymi, pakiet 50 000 linii", t, .milliseconds(400))
        #expect(t < Perf.target(.milliseconds(400)), "\(Perf.ms(t))")
        func count(_ list: [OutlineNode]) -> Int { list.reduce(0) { $0 + 1 + count($1.children) } }
        func controls(_ list: [OutlineNode]) -> Int { list.reduce(0) { $0 + ($1.kind.isControlFlow ? 1 : 0) + controls($1.children) } }
        // 13 struktur (w tym gałęzie i obsługi) i blok na procedurę — 32 500 elementów sterujących.
        #expect(nodes.first?.children.count == 2500)
        #expect(controls(nodes) == 2500 * 13)
        // Bez struktur (przełącznik panelu) — przycięcie gotowego drzewa, bez ponownej analizy.
        var plain: [OutlineNode] = []
        let t2 = Perf.measure(3) { plain = PLSQLOutline.withoutControlFlow(nodes) }
        Perf.report("Zawartość kodu: ukrycie struktur sterujących (50 000 linii)", t2, .milliseconds(30))
        #expect(t2 < Perf.target(.milliseconds(30)), "\(Perf.ms(t2))")
        #expect(controls(plain) == 0 && count(plain) < count(nodes))
        // Ten sam pakiet w oknie SQL (skrypt) i bez struktur (inne analizy edytora) — bez dużego narzutu.
        var script: [OutlineNode] = []
        let t3 = Perf.measure(3) { script = PLSQLOutline.parseScript(Perf.controlFlow50k, controlFlow: true) }
        Perf.report("Zawartość kodu ze strukturami sterującymi w oknie SQL (50 000 linii)", t3, .milliseconds(600))
        #expect(t3 < Perf.target(.milliseconds(600)), "\(Perf.ms(t3))")
        #expect(controls(script) == 2500 * 13)
        let t4 = Perf.measure(3) { plain = PLSQLOutline.parse(Perf.controlFlow50k) }
        Perf.report("Zarys bez struktur sterujących, pakiet 50 000 linii ze strukturami", t4, .milliseconds(400))
        #expect(t4 < Perf.target(.milliseconds(400)), "\(Perf.ms(t4))")
        #expect(plain == PLSQLOutline.withoutControlFlow(nodes))
    }
}
