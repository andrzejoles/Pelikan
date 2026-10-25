import Foundation
import PelikanDB
import Testing

@Suite("DML RETURNING INTO na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct DMLReturningTests {
    @Test("INSERT … RETURNING ROWID INTO zwraca ROWID wstawionego wiersza (siatka usuwa i odświeża po nim — D168)")
    func returningRowid() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { try? await s.rollback(); await s.close() } }
        let r = try await s.execute("insert into dept (deptno, dname) values (98, 'RETURNING') returning rowid into :rid",
                                    binds: [BindVariable(name: "rid", type: .varchar2, direction: .output, maxSize: 4000)], options: ExecuteOptions())
        let rid = try #require(r.outBinds["rid"]?.displayText)
        #expect(try await s.scalar("select rowid from dept where deptno = 98") == rid)
        let d = try await s.execute("delete from dept where rowid = :rid", binds: [BindVariable(name: "rid", type: .varchar2, value: .text(rid))],
                                    options: ExecuteOptions())
        #expect(d.rowsAffected == 1)
        try await s.rollback()
    }
}
