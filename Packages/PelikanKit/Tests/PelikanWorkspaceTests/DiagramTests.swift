import Foundation
@testable import PelikanWorkspace
import Testing

/// Atrapa słownika: EMP → DEPT (FK_EMP_DEPT), widok EMP_V zależny od EMP.
struct FakeSchema: SchemaMetadataSource {
    func resolve(_ name: String) async throws -> DBObject? {
        let n = name.replacingOccurrences(of: "\"", with: "").split(separator: ".").last.map(String.init)?.uppercased() ?? ""
        switch n {
        case "EMP", "DEPT": return DBObject(owner: "SCOTT", name: n, type: .table)
        case "EMP_V": return DBObject(owner: "SCOTT", name: n, type: .view)
        default: return nil
        }
    }

    func columns(owner: String, name: String) async throws -> [SchemaColumn] {
        switch name {
        case "EMP": [SchemaColumn(name: "EMPNO", type: "NUMBER(4)", nullable: false, primaryKey: true), SchemaColumn(name: "ENAME", type: "VARCHAR2(10)"),
                     SchemaColumn(name: "DEPTNO", type: "NUMBER(2)")]
        case "DEPT": [SchemaColumn(name: "DEPTNO", type: "NUMBER(2)", nullable: false, primaryKey: true), SchemaColumn(name: "DNAME", type: "VARCHAR2(14)")]
        case "EMP_V": [SchemaColumn(name: "ENAME", type: "VARCHAR2(10)")]
        default: []
        }
    }

    func foreignKeys(owner: String, table: String) async throws -> [ForeignKey] {
        guard ["EMP", "DEPT"].contains(table) else { return [] }
        return [ForeignKey(name: "FK_EMP_DEPT", childOwner: "SCOTT", childTable: "EMP", childColumns: ["DEPTNO"],
                           parentOwner: "SCOTT", parentTable: "DEPT", parentColumns: ["DEPTNO"])]
    }

    func references(owner: String, name: String) async throws -> [DBObject] {
        name == "EMP_V" ? [DBObject(owner: "SCOTT", name: "EMP", type: .table)] : []
    }
}

@Suite("Diagram i Query Builder bez bazy")
struct DiagramTests {
    @Test("Dodawanie obiektów, linie FK, powiązane, zależności, siatka, grupy, usuwanie, aktualizacja")
    func diagram() async throws {
        let s = FakeSchema()
        var d = Diagram()
        let emp = try await DiagramEditor.add(DBObject(owner: "SCOTT", name: "EMP", type: .table), to: &d, source: s)
        #expect(d.items.count == 1 && d.links.isEmpty && d.items[0].columns.count == 3)
        try await DiagramEditor.addRelated([emp], to: &d, source: s)
        #expect(d.items.count == 2 && d.links.count == 1 && d.links[0].kind == .foreignKey && d.links[0].label == "FK_EMP_DEPT")
        #expect(d.item(d.links[0].to)?.name == "DEPT" && d.links[0].startEnd == .crowFoot)
        try await DiagramEditor.addRelated([emp], to: &d, source: s)
        #expect(d.links.count == 1)
        let v = try await DiagramEditor.add(DBObject(owner: "SCOTT", name: "EMP_V", type: .view), to: &d, source: s)
        try await DiagramEditor.addReferences([v], to: &d, source: s)
        #expect(d.links.contains { $0.kind == .reference && $0.from == v && $0.to == emp })
        // Nowe elementy nie nachodzą na siebie.
        for (i, a) in d.items.enumerated() { for b in d.items[(i + 1)...] { #expect(!a.frame.intersects(b.frame)) } }
        d.move([emp], dx: 13, dy: 3)
        #expect(d.item(emp)!.frame.x.truncatingRemainder(dividingBy: Diagram.grid) == 0)
        d.setShowColumns(false, for: [emp])
        #expect(d.item(emp)!.frame.height == 32)
        #expect(d.addGroup("Kadry", around: [emp, v]) != nil && d.groups.count == 1)
        d.setZoom(5)
        #expect(d.zoom == 2)
        _ = d.addNote("uwaga")
        let missing = try await DiagramEditor.update(&d, source: s)
        #expect(missing.isEmpty && d.item(emp)!.frame.height == 32)
        d.remove([emp])
        #expect(d.item(emp) == nil && !d.links.contains { $0.from == emp || $0.to == emp })
    }

    @MainActor
    @Test("Zapis i odczyt pliku .pdd przez Workspace")
    func file() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.diagram)
        var d = Diagram()
        _ = try await DiagramEditor.add(DBObject(owner: "SCOTT", name: "DEPT", type: .table), to: &d, source: FakeSchema())
        _ = d.addNote("Notatka")
        doc.diagram = d
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-\(UUID().uuidString).pdd")
        defer { try? FileManager.default.removeItem(at: url) }
        try ws.save(doc, to: url)
        let saved = doc.diagram
        ws.close(doc.id)
        let opened = try ws.openFile(url)
        #expect(opened.kind == .diagram && opened.diagram == saved && !opened.isModified)
    }

    @Test("Query Builder: aliasy, złączenie z FK, pola, warunek, grupowanie, sortowanie, format")
    func queryBuilder() async throws {
        let s = FakeSchema()
        var q = QueryModel()
        let e = q.addTable(owner: "SCOTT", name: "EMP", columns: try await s.columns(owner: "SCOTT", name: "EMP"), foreignKeys: try await s.foreignKeys(owner: "SCOTT", table: "EMP"))
        let d = q.addTable(owner: "SCOTT", name: "DEPT", columns: try await s.columns(owner: "SCOTT", name: "DEPT"), foreignKeys: try await s.foreignKeys(owner: "SCOTT", table: "DEPT"))
        #expect(q.tables.map(\.alias) == ["e", "d"] && q.joins.count == 1)
        #expect(q.uniqueAlias(for: "EMP_DEPT_HIST") == "edh" && q.uniqueAlias(for: "EXT") == "e2")
        q.toggleColumn("DNAME", of: d)
        q.toggleColumn("ENAME", of: e)
        q.fields[0].groupBy = true
        q.fields[0].sort = .descending
        q.fields.append(QBField(table: nil, expression: "count(*)"))
        q.fields[2].alias = "ile"
        q.fields[1].groupBy = true
        q.whereClause = "e.sal > 1000"
        let sql = q.sql()
        #expect(sql == """
            select d.dname,
                   e.ename,
                   count(*) ile
              from emp e
              join dept d on e.deptno = d.deptno
             where e.sal > 1000
             group by d.dname, e.ename
             order by d.dname desc
            """)
        q.format.ansiJoins = false
        q.format.uppercaseKeywords = true
        q.format.columnPerLine = false
        #expect(q.sql().contains("FROM EMP e, DEPT d\n WHERE e.DEPTNO = d.DEPTNO\n   AND (e.sal > 1000)"))
    }

    @Test("Query Builder: odczyt prostego SELECT i ponowne wygenerowanie; zapytania spoza zakresu odrzucone")
    func parse() {
        let resolve: (String?, String) -> (owner: String, name: String, columns: [SchemaColumn])? = { owner, name in
            ["EMP", "DEPT"].contains(name) ? (owner ?? "SCOTT", name, [SchemaColumn(name: "DEPTNO", type: "NUMBER")]) : nil
        }
        let sql = """
            select distinct e.ename, d.dname nazwa, count(*) ile
              from emp e left join dept d on e.deptno = d.deptno
             where e.sal > 100
             group by e.ename, d.dname
             order by nazwa desc, e.ename;
            """
        let m = QueryModel.parse(sql, resolve: resolve)
        #expect(m != nil)
        guard let m else { return }
        #expect(m.distinct && m.tables.map(\.alias) == ["e", "d"] && m.joins.first?.kind == .left)
        #expect(m.fields.map(\.expression) == ["ENAME", "DNAME", "count(*)"] && m.fields[1].alias == "nazwa" && m.fields[1].sort == .descending)
        #expect(m.fields.filter(\.groupBy).count == 2 && m.whereClause == "e.sal > 100")
        #expect(m.sql().contains("left join dept d on e.deptno = d.deptno"))
        #expect(QueryModel.parse("select * from emp, dept where emp.deptno = dept.deptno", resolve: resolve)?.tables.count == 2)
        #expect(QueryModel.parse("select * from (select 1 from dual)", resolve: resolve) == nil)
        #expect(QueryModel.parse("select a from emp union select b from dept", resolve: resolve) == nil)
        #expect(QueryModel.parse("select * from nieznana", resolve: resolve) == nil)
    }
}
