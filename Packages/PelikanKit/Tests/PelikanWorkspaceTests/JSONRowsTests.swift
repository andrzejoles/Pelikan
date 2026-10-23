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
}
