import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Etap 7: filtr i grupowanie siatki, SQL z wierszy, kod z obiektu, SQLFORMAT, snippety, panel wartości")
struct Stage7Tests {
    let columns = [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER"),
                   ColumnInfo(name: "NAME", type: .varchar2, typeName: "VARCHAR2(20)"),
                   ColumnInfo(name: "DEPT", type: .number, typeName: "NUMBER")]

    var sample: [[OracleValue]] {
        [[.number("1"), .text("Smith"), .number("10")],
         [.number("2"), .text("Allen"), .number("20")],
         [.number("3"), .text("Scott"), .number("20")],
         [.number("4"), .text("O'Hara"), .null],
         [.number("15"), .text("King"), .number("10")]]
    }

    func grid() async -> ResultGridModel {
        let g = ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession(sample), sql: "select id, name, dept from emp", format: ValueFormat())
        await g.fetchAll()
        return g
    }

    @Test("Filtr wyrażeniem (liczby numerycznie, LIKE, IS NULL, AND/OR), filtr po wartości, z sortowaniem; błędy składni")
    func filter() async throws {
        let g = await grid()
        let names = { (0..<g.rowCount).map { g.text(row: $0, column: 1) } }
        g.setFilter(try GridFilter.parse("id > 2 and name like 's%'", columns: g.columns.map(\.name)))
        #expect(names() == ["Scott"])
        g.setFilter(try GridFilter.parse("ID >= 3 OR DEPT IS NULL", columns: g.columns.map(\.name)))
        #expect(names() == ["Scott", "O'Hara", "King"])
        g.setFilter(try GridFilter.parse("name = 'O''Hara'", columns: g.columns.map(\.name)))
        #expect(names() == ["O'Hara"])
        g.setFilter(GridFilter.value(column: "DEPT", value: .number("20"), format: ValueFormat(), exclude: true))
        #expect(names() == ["Smith", "King"])        // NULL nie spełnia „<> 20” (jak w SQL)
        g.setFilter(GridFilter.value(column: "DEPT", value: .null, format: ValueFormat(), exclude: false))
        #expect(names() == ["O'Hara"])
        g.setFilter(try GridFilter.parse("dept <> 20", columns: g.columns.map(\.name)))
        g.toggleSort(column: 0)
        g.toggleSort(column: 0)
        #expect(names() == ["King", "Smith"] && g.fetchedRowCount == 5)
        g.setFilter(nil)
        #expect(g.rowCount == 5)
        #expect(throws: GridFilter.ParseError.self) { try GridFilter.parse("nope = 1", columns: g.columns.map(\.name)) }
        #expect(throws: GridFilter.ParseError.self) { try GridFilter.parse("id >", columns: g.columns.map(\.name)) }
        #expect(throws: GridFilter.ParseError.self) { try GridFilter.parse("id = 1 xor id = 2", columns: g.columns.map(\.name)) }
    }

    @Test("Grupowanie z licznikami (na widocznych wierszach, NULL osobno)")
    func groups() async throws {
        let g = await grid()
        let c = g.groupCounts(column: 2)
        #expect(c.map(\.count) == [2, 2, 1] && c.first { $0.isNull }?.count == 1)
        g.setFilter(try GridFilter.parse("id < 10", columns: g.columns.map(\.name)))
        #expect(g.groupCounts(column: 2).map { "\($0.value):\($0.count)" }.sorted() == ["10:1", "20:2", "NULL:1"])
    }

    @Test("SQL z wierszy: INSERT, UPDATE/DELETE po kluczu, MERGE; ROWID; brak klucza")
    func rowSQL() throws {
        let rows = Array(sample.prefix(2))
        let ins = try RowSQLGenerator.statements(.insert, table: "EMP", columns: columns, rows: rows, keyColumns: [])
        #expect(ins.contains("INSERT INTO EMP (ID, NAME, DEPT)\n  VALUES (1, 'Smith', 10);"))
        let upd = try RowSQLGenerator.statements(.update, table: "EMP", columns: columns, rows: rows, keyColumns: ["ID"])
        #expect(upd.contains("UPDATE EMP\n   SET NAME = 'Smith',\n       DEPT = 10\n WHERE ID = 1;"))
        #expect(try RowSQLGenerator.statements(.delete, table: "EMP", columns: columns, rows: [sample[3]], keyColumns: ["ID"]).contains("DELETE FROM EMP WHERE ID = 4;"))
        let merge = try RowSQLGenerator.statements(.merge, table: "EMP", columns: columns, rows: [sample[0]], keyColumns: ["ID"])
        #expect(merge.contains("USING (SELECT 1 AS ID, 'Smith' AS NAME, 10 AS DEPT FROM dual) s") && merge.contains("ON (t.ID = s.ID)")
                && merge.contains("WHEN NOT MATCHED THEN INSERT (ID, NAME, DEPT) VALUES (s.ID, s.NAME, s.DEPT);"))
        let withRowid = columns + [ColumnInfo(name: "ROWID", type: .rowid, typeName: "ROWID")]
        let del = try RowSQLGenerator.statements(.delete, table: "EMP", columns: withRowid, rows: [sample[0] + [.rowid("AAAB")]], keyColumns: [])
        #expect(del == "DELETE FROM EMP WHERE ROWID = 'AAAB';\n")
        #expect(!(try RowSQLGenerator.statements(.insert, table: "EMP", columns: withRowid, rows: [sample[0] + [.rowid("AAAB")]], keyColumns: [])).contains("ROWID"))
        #expect(throws: RowSQLGenerator.GenerationError.self) { try RowSQLGenerator.statements(.update, table: "EMP", columns: columns, rows: rows, keyColumns: []) }
    }

    @Test("Kod z obiektu: SQL z kluczem, Java JDBC, Python")
    func codeGen() {
        let o = DBObject(owner: "SCOTT", name: "EMP", type: .table)
        let cols = [CodeGenerator.Column(name: "EMPNO", type: "NUMBER(4)", isKey: true), CodeGenerator.Column(name: "ENAME", type: "VARCHAR2(10)"),
                    CodeGenerator.Column(name: "HIREDATE", type: "DATE")]
        #expect(CodeGenerator.generate(.select, object: o, columns: cols).hasSuffix("FROM SCOTT.EMP\n WHERE EMPNO = :empno;\n"))
        #expect(CodeGenerator.generate(.update, object: o, columns: cols).contains("SET ENAME = :ename,\n       HIREDATE = :hiredate\n WHERE EMPNO = :empno;"))
        #expect(CodeGenerator.generate(.insert, object: o, columns: cols).contains("VALUES (:empno, :ename, :hiredate)"))
        let java = CodeGenerator.generate(.javaSelect, object: o, columns: cols, connectionAlias: "DEV")
        #expect(java.contains("WHERE EMPNO = ?") && java.contains("java.math.BigDecimal empno = rs.getBigDecimal(\"EMPNO\");")
                && java.contains("java.sql.Timestamp hiredate = rs.getTimestamp(\"HIREDATE\");") && java.contains("ps.setObject(1, empno);"))
        let py = CodeGenerator.generate(.pythonInsert, object: o, columns: cols)
        #expect(py.contains("cur.execute(sql, {\"empno\": empno, \"ename\": ename, \"hiredate\": hiredate})"))
        // Słowa zastrzeżone jako zmienne wiązane (ORA-01745) z przyrostkiem; identyfikator w cudzysłowie w literale Java.
        let odd = [CodeGenerator.Column(name: "DATE", type: "DATE", isKey: true), CodeGenerator.Column(name: "Level", type: "NUMBER")]
        #expect(CodeGenerator.generate(.insert, object: o, columns: odd).contains("VALUES (:date_, :level_)"))
        let quoted = CodeGenerator.generate(.javaInsert, object: DBObject(owner: "SCOTT", name: "Emp", type: .table), columns: odd)
        #expect(quoted.contains("String sql = \"INSERT INTO SCOTT.\\\"Emp\\\" (\\\"DATE\\\", \\\"Level\\\") VALUES (?, ?)\";"))
    }

    @Test("SQLFORMAT: parsowanie i formaty csv, json, xml, html, insert, loader, delimited, fixed, ansiconsole")
    func sqlFormat() throws {
        #expect(try SQLFormat.parse(["csv"]) == .csv && (try SQLFormat.parse(["default"])) == nil && (try SQLFormat.parse([])) == nil)
        #expect(try SQLFormat.parse(["delimited", "|", "'"]) == .delimited(separator: "|", left: "'", right: "'"))
        #expect(throws: SQLPlusError.self) { try SQLFormat.parse(["yaml"]) }
        let rows = [sample[0], sample[3]]
        func run(_ f: SQLFormat) -> [String] {
            var fm = SQLFormatter(format: f, columns: columns, valueFormat: ValueFormat(), table: "EMP")
            return fm.header() + fm.lines(rows) + fm.footer()
        }
        #expect(run(.csv) == ["\"ID\",\"NAME\",\"DEPT\"", "1,\"Smith\",10", "4,\"O'Hara\","])
        let json = run(.json).joined()
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let items = ((obj?["results"] as? [[String: Any]])?.first?["items"] as? [[String: Any]]) ?? []
        #expect(items.count == 2 && items[0]["name"] as? String == "Smith" && items[1]["dept"] is NSNull)
        #expect(run(.xml).joined().contains("<COLUMN NAME=\"NAME\"><![CDATA[O'Hara]]></COLUMN>"))
        #expect(run(.html).contains("<tr><td>4</td><td>O&apos;Hara</td><td></td></tr>") || run(.html).contains("<tr><td>4</td><td>O'Hara</td><td></td></tr>"))
        #expect(run(.insert)[0] == "INSERT INTO EMP (ID,NAME,DEPT) VALUES (1,'Smith',10);")
        #expect(run(.loader)[0] == "\"1\"|\"Smith\"|\"10\"|")
        #expect(run(.delimited(separator: ";", left: "'", right: "'"))[2] == "4;'O''Hara';")
        #expect(run(.fixed)[0] == " 1Smith   10")
        let ansi = run(.ansiconsole)
        #expect(ansi[0].hasPrefix("ID NAME") && ansi[1].hasPrefix("-- ------"))
    }

    @Test("Snippety: wbudowane, własne zastępują wbudowane, zapis i usunięcie")
    func snippets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-snip-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = SnippetLibrary(directory: dir)
        #expect(lib.all.count == SnippetLibrary.builtIn.count && lib.categories.contains("PL/SQL"))
        let first = SnippetLibrary.builtIn[0]
        try lib.save(Snippet(category: first.category, name: first.name, text: "SYSDATE"))
        try lib.save(Snippet(category: "Moje", name: "Licznik", text: "count(*)"))
        let again = SnippetLibrary(directory: dir)
        #expect(again.all.count == SnippetLibrary.builtIn.count + 1)
        #expect(again.all.first { $0.id == first.id }?.text == "SYSDATE" && again.all.first { $0.id == first.id }?.isBuiltIn == false)
        try again.remove(id: "Moje/Licznik")
        #expect(SnippetLibrary(directory: dir).all.contains { $0.id == "Moje/Licznik" } == false)
    }

    @Test("Snippety: uszkodzony plik własnych nie zostaje nadpisany przy zapisie ani usunięciu")
    func snippetsCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-snip-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("snippets.json")
        let broken = Data(#"[{"category": "Moje", "name": "A", "text": "x"},"#.utf8)
        try broken.write(to: file)
        let lib = SnippetLibrary(directory: dir)
        #expect(lib.loadError != nil && lib.all.count == SnippetLibrary.builtIn.count)
        #expect(throws: CommandError.self) { try lib.save(Snippet(category: "Moje", name: "B", text: "y")) }
        #expect(throws: CommandError.self) { try lib.remove(id: "Moje/A") }
        #expect(try Data(contentsOf: file) == broken)
    }

    @Test("Filtr siatki: LIKE z % i _ obejmuje znak nowej linii, koniec wzorca — koniec wartości")
    func gridFilterLikeNewline() {
        #expect(GridFilter.like("pierwsza\ndruga", "pierwsza%"))
        #expect(GridFilter.like("a\nb", "a_b"))
        #expect(!GridFilter.like("abc\n", "abc"))
    }

    @Test("Panel wartości: JSON, XML z wcięciami, obraz z BLOB, hex, NULL")
    func valuePanel() {
        let c = ColumnInfo(name: "DOC", type: .clob, typeName: "CLOB")
        let json = CellValuePresentation.make(.lob(LOBValue(kind: .clob, text: "{\"a\":1}", length: 7, truncated: false)), column: c, format: ValueFormat())
        #expect(json.detected == .json && json.rendered(.json).contains("\"a\" : 1"))
        let xml = CellValuePresentation.make(.text("<a><b>1</b></a>"), column: ColumnInfo(name: "X", type: .varchar2, typeName: "VARCHAR2"), format: ValueFormat())
        #expect(xml.detected == .xml && xml.rendered(.xml).contains("\n"))
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let img = CellValuePresentation.make(.lob(LOBValue(kind: .blob, bytes: png, length: 8, truncated: false)), column: ColumnInfo(name: "B", type: .blob, typeName: "BLOB"), format: ValueFormat())
        #expect(img.detected == .image && img.modes.contains(.hex) && img.rendered(.hex).hasPrefix("00000000  89 50 4E 47"))
        #expect(CellValuePresentation.make(.null, column: c, format: ValueFormat()).rendered(.text) == "NULL")
    }

    @Test("Wstawianie snippetu do edytora")
    func insertSnippet() async throws {
        let ws = Workspace()
        let doc = ws.newDocument(.sql, text: "select  from dual")
        doc.selectedRange = 7..<7
        let s = SnippetLibrary.builtIn.first { $0.category == "JSON" }!
        try await ws.invoke("edit.insertSnippet", CommandArguments(["id": .string(s.id)]))
        #expect(doc.text == "select \(s.text) from dual")
    }
}
