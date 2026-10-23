import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@Suite("Diagram i Query Builder na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct DiagramDBTests {
    @Test("Słownik: kolumny z PK, klucz obcy EMP → DEPT, zależności; diagram z linią FK; Query Builder ze złączeniem")
    func metadata() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let meta = SessionSchemaMetadata(session: s)
        let emp = try #require(try await meta.resolve("emp"))
        #expect(emp.type == .table)
        let cols = try await meta.columns(owner: emp.owner, name: "EMP")
        #expect(cols.first { $0.name == "EMPNO" }?.primaryKey == true && cols.contains { $0.name == "DEPTNO" })
        let fks = try await meta.foreignKeys(owner: emp.owner, table: "EMP")
        #expect(fks.contains { $0.childTable == "EMP" && $0.parentTable == "DEPT" && $0.childColumns == ["DEPTNO"] })
        #expect(try await meta.foreignKeys(owner: emp.owner, table: "DEPT").contains { $0.childTable == "EMP" })
        #expect(try await meta.references(owner: emp.owner, name: "EMP_API").contains { $0.name == "EMP" })

        var d = Diagram()
        let e = try await DiagramEditor.add(emp, to: &d, source: meta)
        try await DiagramEditor.addRelated([e], to: &d, source: meta)
        #expect(d.items.contains { $0.name == "DEPT" } && d.links.contains { $0.kind == .foreignKey })

        var q = QueryModel()
        q.addTable(owner: emp.owner, name: "EMP", columns: cols, foreignKeys: fks)
        q.addTable(owner: emp.owner, name: "DEPT", columns: try await meta.columns(owner: emp.owner, name: "DEPT"),
                   foreignKeys: try await meta.foreignKeys(owner: emp.owner, table: "DEPT"))
        q.toggleColumn("ENAME", of: q.tables[0].id)
        q.toggleColumn("DNAME", of: q.tables[1].id)
        let (_, rows) = try await s.queryAll(q.sql(), limit: 100)
        #expect(!rows.isEmpty)
    }
}
