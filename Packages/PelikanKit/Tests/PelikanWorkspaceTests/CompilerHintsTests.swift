import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Podpowiedzi kompilatora i konwencje nazw")
struct CompilerHintsTests {
    let unit = """
    create or replace package body emp_api as
      counter number;
      g_total number;
      procedure raise_sal(emp_id number, p_pct number) is
        l_old number;
        tmp number;
        c_max constant number := 10;
        unused_var number; -- Ignore
      begin
        update emp set sal = sal * p_pct where empno = emp_id;
        delete from bonus;
      end;
    end;
    """

    @Test("Konwencje nazw: parametry, zmienne lokalne i globalne; -- Ignore wycisza linię")
    func naming() {
        var c = NamingConventions()
        c.enabled = true
        let v = CompilerHints.namingViolations(unit, conventions: c).map(\.message)
        #expect(v.contains { $0.contains("„counter”") } && !v.contains { $0.contains("„g_total”") })
        #expect(v.contains { $0.contains("„emp_id”") } && !v.contains { $0.contains("„p_pct”") })
        #expect(v.contains { $0.contains("„tmp”") } && !v.contains { $0.contains("„l_old”") } && !v.contains { $0.contains("„c_max”") })
        let hints = CompilerHints.hints(for: unit, conventions: c).map(\.text)
        #expect(!hints.contains { $0.contains("unused_var") })
        #expect(hints.contains { $0.uppercased().contains("WHERE") })
        c.enabled = false
        #expect(CompilerHints.namingViolations(unit, conventions: c).isEmpty)
    }
}
