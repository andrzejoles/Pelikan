import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Zawartość kodu ze strukturami sterującymi (D203, R4-01): filtr i sortowanie drzewa pakietu 50 000 linii gęsto
/// wypełnionego strukturami (cele Release: `make test-release`, PELIKAN_PERF_STRICT=1; w Debug ×15).
@Suite("CodeContentsPerformanceTests — filtr i sortowanie", .serialized)
struct CodeContentsPerformanceTests {
    static let strict = ProcessInfo.processInfo.environment["PELIKAN_PERF_STRICT"] == "1"
    static func target(_ release: Duration) -> Duration { strict ? release : release * 15 }

    static func measure(_ body: () -> Void) -> Duration {
        let clock = ContinuousClock()
        var best = Duration.seconds(1000)
        for _ in 0..<3 { best = min(best, clock.measure(body)) }
        return best
    }

    static func report(_ name: String, _ value: Duration, _ target: Duration) {
        guard strict else { return }
        let ms = { (d: Duration) in String(format: "%.2f ms", Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000) }
        print("PERF\t\(name)\t\(ms(value))\t< \(ms(target))\t\(value < target ? "ok" : "fail")")
    }

    /// Ten sam układ co `Perf.controlFlow50k` w PelikanSQLTests: 2500 procedur po 20 linii, 13 struktur i blok w każdej.
    static let package: String = {
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

    @Test("filtr i sortowanie drzewa ze strukturami sterującymi, pakiet 50 000 linii")
    func filterAndSort() {
        let nodes = PLSQLOutline.parse(Self.package, controlFlow: true)
        var out: [OutlineNode] = []
        // Odświeżenie panelu bez filtra (kolejność alfabetyczna — sortowanie na każdym poziomie).
        let t1 = Self.measure { out = CodeContents.sorted(CodeContents.filtered(nodes, matching: ""), order: .name) }
        Self.report("Zawartość kodu: sortowanie drzewa ze strukturami (50 000 linii)", t1, .milliseconds(100))
        #expect(out.first?.children.count == 2500)
        #expect(t1 < Self.target(.milliseconds(100)), "\(t1)")
        // Filtr pasujący do warunków wszystkich struktur IF/WHILE (tysiące trafień).
        let t2 = Self.measure { out = CodeContents.sorted(CodeContents.filtered(nodes, matching: "p_id"), order: .source) }
        Self.report("Zawartość kodu: filtr „p_id” w drzewie ze strukturami (50 000 linii)", t2, .milliseconds(150))
        #expect(out.first?.children.count == 2500)
        #expect(t2 < Self.target(.milliseconds(150)), "\(t2)")
        // Filtr z jednym trafieniem.
        let t3 = Self.measure { out = CodeContents.filtered(nodes, matching: "proc_1234") }
        Self.report("Zawartość kodu: filtr z jednym trafieniem (50 000 linii)", t3, .milliseconds(100))
        #expect(out.first?.children.map(\.name) == ["proc_1234"])
        #expect(t3 < Self.target(.milliseconds(100)), "\(t3)")
    }
}
