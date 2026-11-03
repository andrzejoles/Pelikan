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

    @Test("Konwencja RMS: parametry IN, OUT i IN OUT osobno, zmienne pakietu w ciele i specyfikacji, kilka przedrostków (D215)")
    func rms() throws {
        let c = NamingConventions.rms
        let body = """
        create or replace package body item_sql as
          LP_vdate date := get_vdate;
          g_old number;
          K_max constant number := 10;
          function exists_item(O_error_message in out varchar2, O_exists out boolean, I_item in item_master.item%type,
                               IO_qty in out nocopy number, p_loc number, x_flag out boolean, item_type in varchar2) return boolean is
            L_program varchar2(64) := 'ITEM_SQL.EXISTS_ITEM';
            v_count number;
            cursor C_item is select 1 from dual;
            cursor get_loc is select 1 from dual;
          begin
            return true;
          end;
        end;
        """
        let v = CompilerHints.namingViolations(body, conventions: c).map(\.message)
        let flagged = { (n: String) in v.contains { $0.contains("„\(n)”") } }
        for ok in ["LP_vdate", "K_max", "O_error_message", "O_exists", "I_item", "IO_qty", "L_program", "C_item"] { #expect(!flagged(ok), "\(ok)") }
        for bad in ["g_old", "p_loc", "x_flag", "item_type", "v_count", "get_loc"] { #expect(flagged(bad), "\(bad)") }
        #expect(v.contains { $0.hasPrefix("Parametr OUT „x_flag”") })
        #expect(v.contains { $0.hasPrefix("Parametr IN „p_loc”") })
        #expect(v.contains { $0.contains("„O_”, „IO_”") } == false)   // IO_qty i O_error_message spełniają listę IN OUT
        let spec = """
        create or replace package item_sql as
          GP_replace boolean;
          LP_wrong number;
        end;
        """
        let s = CompilerHints.namingViolations(spec, conventions: c).map(\.message)
        #expect(!s.contains { $0.contains("„GP_replace”") } && s.contains { $0.contains("Zmienna pakietu (specyfikacja) „LP_wrong”") })
        // Puste OUT / IN OUT — jak IN; stare ustawienia bez nowych pól odczytują się z wartościami domyślnymi.
        var d = NamingConventions()
        d.enabled = true
        #expect(d.parameterPrefix(.out) == "p_" && d.parameterPrefix(.inOut) == "p_")
        let old = try JSONDecoder().decode(NamingConventions.self, from: Data(#"{"enabled":true,"parameter":"a_","local":"l_","global":"g_","constant":"c_","cursor":"cur_","type":"t_"}"#.utf8))
        #expect(old.parameter == "a_" && old.parameterOut == "" && old.publicGlobal == "")
        #expect(NamingConventions.mode("IN OUT NOCOPY NUMBER") == .inOut && NamingConventions.mode("OUT BOOLEAN") == .out && NamingConventions.mode("NUMBER") == .in)
    }
}
