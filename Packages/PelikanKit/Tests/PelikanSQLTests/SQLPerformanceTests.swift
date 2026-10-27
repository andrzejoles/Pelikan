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
}
