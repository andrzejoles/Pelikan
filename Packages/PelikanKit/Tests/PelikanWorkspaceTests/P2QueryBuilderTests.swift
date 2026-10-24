import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Query Builder: podzapytania w FROM (PD-QB-001)")
struct P2QueryBuilderTests {
    let emp = [SchemaColumn(name: "EMPNO", type: "NUMBER"), SchemaColumn(name: "DEPTNO", type: "NUMBER")]

    @Test("Podzapytanie z aliasem w SQL, złączenie z tabelą; odczyt SELECT z podzapytaniem w FROM i w JOIN")
    func subqueries() throws {
        var m = QueryModel()
        let e = m.addTable(owner: "HR", name: "EMP", columns: emp, foreignKeys: [])
        let s = m.addSubquery("select deptno, count(*) cnt\n  from emp\n group by deptno;", alias: "d", columns: [SchemaColumn(name: "DEPTNO", type: "NUMBER"), SchemaColumn(name: "CNT", type: "NUMBER")])
        m.joins.append(QBJoin(left: e, leftColumns: ["DEPTNO"], right: s, rightColumns: ["DEPTNO"]))
        m.fields = [QBField(table: e, expression: "EMPNO"), QBField(table: s, expression: "CNT")]
        let sql = m.sql()
        #expect(sql.contains("join (\n         select deptno, count(*) cnt\n           from emp\n          group by deptno\n     ) d on e.deptno = d.deptno"))
        #expect(sql.hasPrefix("select e.empno,\n       d.cnt"))

        let parsed = try #require(QueryModel.parse(
            "select e.empno, d.cnt from emp e join (select deptno, count(*) cnt from emp group by deptno) d on e.deptno = d.deptno, (select 1 x from dual) y where d.cnt > 1",
            resolve: { owner, name in (owner ?? "HR", name, emp) }, describe: { q in q.contains("cnt") ? [SchemaColumn(name: "CNT", type: "NUMBER")] : [] }))
        #expect(parsed.tables.count == 3)
        #expect(parsed.tables[1].subquery == "select deptno, count(*) cnt from emp group by deptno" && parsed.tables[1].alias == "d")
        #expect(parsed.tables[1].columns.map(\.name) == ["CNT"])
        #expect(parsed.tables[2].subquery == "select 1 x from dual" && parsed.tables[2].alias == "y")
        #expect(parsed.joins.count == 1 && parsed.joins[0].right == parsed.tables[1].id)
        #expect(parsed.fields.last?.table == parsed.tables[1].id && parsed.whereClause == "d.cnt > 1")
        #expect(QueryModel.parse("select * from (update t set a = 1) x", resolve: { _, n in ("", n, []) }) == nil)
    }
}
