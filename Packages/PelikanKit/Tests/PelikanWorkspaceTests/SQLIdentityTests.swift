import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("SQL_ID i hash zapytania (D217)")
struct SQLIdentityTests {
    @Test("MD5: wektory RFC 1321")
    func md5() {
        func hex(_ s: String) -> String { MD5.digest(Array(s.utf8)).map { String(format: "%02x", $0) }.joined() }
        #expect(hex("") == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(hex("abc") == "900150983cd24fb0d6963f7d28e17f72")
        #expect(hex(String(repeating: "1234567890", count: 8)) == "57edf4a22be3c955ac49da2e2107b67a")
    }

    @Test("SQL_ID i HASH_VALUE z tekstu — jak V$SQL (wartości z bazy testowej)")
    func fromText() {
        #expect(SQLIdentity.sqlID(text: "select 'pelikan sqlid probe' from dual") == "ghkw1782vah43")
        #expect(SQLIdentity.hashValue(sqlID: "ghkw1782vah43") == 95764611)
        #expect(SQLIdentity.sqlID(SQLIdentity.value("ghkw1782vah43")!) == "ghkw1782vah43")
    }

    @Test("Rozpoznawanie wartości i kolumn")
    func parse() {
        #expect(SQLIdentity.parse("ghkw1782vah43") == .sqlID("ghkw1782vah43"))
        #expect(SQLIdentity.parse(" GHKW1782VAH43 ") == .sqlID("ghkw1782vah43"))
        #expect(SQLIdentity.parse("95764611") == .hash(95764611))
        #expect(SQLIdentity.parse("1234567890123") == nil)      // same cyfry — nie SQL_ID
        #expect(SQLIdentity.parse("abcdefghijklm") == nil)      // e, i, l spoza alfabetu
        #expect(SQLIdentity.parse("0") == nil && SQLIdentity.parse("4294967296") == nil)
        #expect(SQLIdentity.columnKind("SQL_ID") == .sqlID && SQLIdentity.columnKind("prev_sql_id") == .sqlID)
        #expect(SQLIdentity.columnKind("SQL_HASH_VALUE") == .hash && SQLIdentity.columnKind("PLAN_HASH_VALUE") == nil)
        #expect(SQLIdentity.target(columns: ["SID", "SQL_HASH_VALUE", "SQL_ID"], values: ["12", "95764611", "ghkw1782vah43"]) == .sqlID("ghkw1782vah43"))
        #expect(SQLIdentity.target(columns: ["SID", "SQL_HASH_VALUE", "SQL_ID"], values: ["12", "95764611", ""]) == .hash(95764611))
        #expect(SQLIdentity.target(columns: ["A"], values: ["ghkw1782vah43"]) == nil)
    }
}
