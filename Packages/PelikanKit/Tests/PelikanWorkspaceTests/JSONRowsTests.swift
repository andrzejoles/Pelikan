import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Wiersze JSON z sesji debugowanej")
struct JSONRowsTests {
    @Test("Kolejność kolumn, liczby, NULL, znaki specjalne", .timeLimit(.minutes(1)))
    func rows() {
        #expect(DebuggerEngine.jsonRows(#"[{"DNAME":"KSIĘGOWOŚĆ"}]"#) == ["KSIĘGOWOŚĆ"])
        #expect(DebuggerEngine.jsonRows(#"[{"B":2,"A":"x\ty","C":null},{"B":3.5,"A":"","C":true}]"#) == ["2\tx\ty\t", "3.5\t\ttrue"])
    }

    @Test("Sekwencje \\r \\b \\f \\/ i pary surogatów; ucięty JSON bez awarii")
    func escapes() {
        #expect(DebuggerEngine.jsonRows(#"[{"A":"a\rb\bc\fd\/e"}]"#) == ["a\rb\u{8}c\u{C}d/e"])
        #expect(DebuggerEngine.jsonRows(#"[{"A":"😀 ą"}]"#) == ["😀 ą"])
        #expect(DebuggerEngine.jsonRows(#"[{"A":"abc"#) == [])
        #expect(DebuggerEngine.jsonRows(#"[{"A":"ab\u01"#) == [])
    }

    @Test("SET_VALUE: literał wg typu zmiennej; warunek — liczba bez inf/nan/hex i zer wiodących")
    func literals() {
        #expect(DebuggerEngine.literal("007", type: "varchar2(10)") == "'007'")
        #expect(DebuggerEngine.literal("1,5", type: "VARCHAR2(10)") == "'1,5'")
        #expect(DebuggerEngine.literal("1,5", type: "number") == "1.5")
        #expect(DebuggerEngine.literal("007", type: "pls_integer") == "007")
        #expect(DebuggerEngine.literal("inf", type: "number") == "'inf'")
        #expect(DebuggerEngine.literal("0x10", type: "") == "'0x10'")
        #expect(DebuggerEngine.literal("007", type: "emp.ename%type") == "'007'")
        #expect(DebuggerEngine.literal("42", type: "") == "42")
        #expect(DebuggerEngine.literal("true", type: "boolean") == "TRUE")
        #expect(DebuggerEngine.literal("true", type: "varchar2(5)") == "'true'")
        #expect(DebuggerEngine.literal("null", type: "varchar2(5)") == "NULL")
        #expect(DebuggerEngine.literal("O'Brien", type: "varchar2(20)") == "'O''Brien'")
        #expect(DebuggerEngine.isPlainNumber(".5") && DebuggerEngine.isPlainNumber("-1.5e3") && !DebuggerEngine.isPlainNumber("nan"))
        #expect(!DebuggerEngine.isPlainNumber("007", leadingZeros: false) && DebuggerEngine.isPlainNumber("0.7", leadingZeros: false))
    }
}
