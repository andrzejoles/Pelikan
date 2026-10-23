import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Pomoc kontekstowa w dokumentacji Oracle")
struct OracleDocsTests {
    let base = "https://docs.oracle.com/en/database/oracle/oracle-database/"

    @Test("Błędy, pakiety, widoki słownika, polecenia i funkcje SQL, PL/SQL; reszta — wyszukiwanie")
    func urls() {
        #expect(OracleDocs.url(for: "ORA-1403")?.absoluteString == "https://docs.oracle.com/error-help/db/ora-01403/")
        #expect(OracleDocs.url(for: "pls-00201")?.absoluteString == "https://docs.oracle.com/error-help/db/pls-00201/")
        #expect(OracleDocs.url(for: "dbms_output.put_line", release: "23")?.absoluteString == base + "23/arpls/DBMS_OUTPUT.html")
        #expect(OracleDocs.url(for: "sys.utl_file.fopen")?.absoluteString == base + "19/arpls/UTL_FILE.html")
        #expect(OracleDocs.url(for: "v$session")?.absoluteString == base + "19/refrn/V-SESSION.html")
        #expect(OracleDocs.url(for: "all_tables", release: "26")?.absoluteString == base + "26/refrn/ALL_TABLES.html")
        #expect(OracleDocs.url(for: "create", next: "table")?.absoluteString == base + "19/sqlrf/CREATE-TABLE.html")
        #expect(OracleDocs.url(for: "nvl")?.absoluteString == base + "19/sqlrf/NVL.html")
        #expect(OracleDocs.url(for: "forall")?.absoluteString == base + "19/lnpls/FORALL-statement.html")
        #expect(OracleDocs.url(for: "execute", next: "immediate")?.absoluteString == base + "19/lnpls/EXECUTE-IMMEDIATE-statement.html")
        let s = OracleDocs.url(for: "emp_api", release: "99")?.absoluteString ?? ""
        #expect(s.hasPrefix("https://docs.oracle.com/search/?q=emp_api") && s.contains("oracle-database/19"))
        #expect(OracleDocs.url(for: "  ") == nil)
    }

    @Test("Słowo pod kursorem: kropki, $, kod błędu, myślnik jako operator, następne słowo")
    func word() {
        let t = "begin dbms_output.put_line(x); end;\nselect * from v$session where a-b > 0;\n-- ORA-01403 brak\ncreate table t"
        #expect(OracleDocs.word(at: 10, in: t)?.word == "dbms_output.put_line")
        let v = (t as NSString).range(of: "v$session").location + 3
        #expect(OracleDocs.word(at: v, in: t)?.word == "v$session")
        let e = (t as NSString).range(of: "ORA-01403").location + 5
        #expect(OracleDocs.word(at: e, in: t)?.word == "ORA-01403")
        let ab = (t as NSString).range(of: "a-b").location + 2
        #expect(OracleDocs.word(at: ab, in: t)?.word == "b")
        let c = (t as NSString).range(of: "create").location + 1
        let w = OracleDocs.word(at: c, in: t)
        #expect(w?.word == "create" && w?.next == "table")
        #expect(OracleDocs.word(at: 0, in: "") == nil)
    }

    @MainActor @Test("Komenda F1 otwiera adres dla słowa pod kursorem")
    func command() async throws {
        let ws = Workspace()
        let d = ws.newDocument(.sql, text: "select nvl(a, 0) from dual")
        d.selectedRange = 8..<8
        let r = try await ws.invoke("help.context")
        #expect(r.value == .string(base + "19/sqlrf/NVL.html"))
    }
}
