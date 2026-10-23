import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Atrapa słownika: EMP(EMPNO, ENAME, DEPTNO, SAL), DEPT(DEPTNO, DNAME); pakiet EMP_API, schemat SCOTT.
struct FakeNames: NameResolutionSource {
    let tables = ["EMP": ["EMPNO", "ENAME", "DEPTNO", "SAL"], "DEPT": ["DEPTNO", "DNAME"]]
    func relationExists(owner: String?, name: String) async -> Bool { tables[name] != nil || name == "DUAL" }
    func columns(owner: String?, relation: String) async -> [String]? { tables[relation] }
    func objectOrSchemaExists(_ name: String) async -> Bool { ["EMP_API", "SCOTT", "EMP_SEQ"].contains(name) }
}

@Suite("DataGrip: rozwiązywanie nazw i inspekcje")
struct NameResolutionTests {
    @Test("Nieznana tabela, kolumna po aliasie, nieznany alias; CTE, pseudokolumny, pakiet i schemat bez fałszywych alarmów")
    func names() async {
        let sql = """
            select e.ename, e.salary, x.dname, d.dname, e.rowid, emp_api.get_salary(e.empno), emp_seq.nextval
              from emp e join dept d on d.deptno = e.deptno, nie_ma t;
            with c as (select 1 a from dual) select c.a from c;
            update emp set sal = sal * 2 where empno = 1;
            insert into scott.emp (empno) values (1);
            """
        let d = await NameResolver.unresolved(in: sql, source: FakeNames())
        let ns = sql as NSString
        let found = d.map { "\($0.code):\(ns.substring(with: NSRange(location: $0.range.lowerBound, length: $0.range.count)))" }
        #expect(found.sorted() == ["unknown-alias:x", "unknown-column:salary", "unknown-table:nie_ma"], "\(found)")
    }

    @Test("SQL w PL/SQL: SELECT INTO zmiennej nie jest tabelą, rekord nie jest aliasem")
    func plsql() async {
        let body = """
            declare r emp%rowtype; n number;
            begin
              select count(*) into n from emp where deptno = 10;
              select ename into r.ename from emp where empno = r.empno;
              delete from brak where 1 = 1;
            end;
            """
        let d = await NameResolver.unresolved(in: body, source: FakeNames())
        #expect(d.map(\.code) == ["unknown-table"] && d.first?.message.contains("BRAK") == true, "\(d.map(\.message))")
    }

    @Test("Inspekcje: nieużywana zmienna i parametr, kod nieosiągalny, UPDATE/DELETE bez WHERE, niejawna konwersja")
    func inspections() {
        let src = """
            create or replace procedure p(p_used number, p_unused varchar2) is
              l_count number;
              l_name varchar2(30);
              l_never number;
            begin
              if l_count = '10' then
                l_name := 'x';
              end if;
              if l_name = 5 then null; end if;
              update emp set sal = p_used;
              delete from emp where empno = p_used;
              return;
              dbms_output.put_line('nigdy');
            end;
            """
        let d = CodeInspections.inspect(src)
        let ns = src as NSString
        let found = d.map { "\($0.code):\(ns.substring(with: NSRange(location: $0.range.lowerBound, length: min($0.range.count, 20))))" }
        #expect(found.contains("unused-parameter:p_unused") && found.contains("unused-variable:l_never"), "\(found)")
        #expect(!found.contains { $0.hasPrefix("unused-parameter:p_used") || $0.hasPrefix("unused-variable:l_count") })
        #expect(found.contains("missing-where:update") && !found.contains("missing-where:delete"))
        #expect(found.contains { $0.hasPrefix("unreachable-code:dbms_output") })
        #expect(found.contains("implicit-conversion:'10'") && found.contains("implicit-conversion:5"), "\(found)")
    }

    @Test("Inspekcje bez fałszywych alarmów: EXIT WHEN, SELECT FOR UPDATE, MERGE, RETURN na końcu")
    func noFalsePositives() {
        let src = """
            create or replace function f return number is
              cursor c is select * from emp for update;
              v number := 0;
            begin
              open c; close c;
              loop exit when v > 3; v := v + 1; end loop;
              merge into emp d using dept s on (d.deptno = s.deptno) when matched then update set d.sal = 1;
              return v;
            end;
            """
        let d = CodeInspections.inspect(src)
        #expect(d.isEmpty, "\(d.map { "\($0.code) \($0.message)" })")
    }
}

@MainActor
@Suite("DataGrip: Find Usages, refaktoryzacja, historia lokalna, konsole, zmiany w siatce")
struct DataGripModelTests {
    func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-dg-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test("Użycia w tekście: tylko identyfikatory (bez komentarzy, literałów i innych schematów); kolumna w poleceniach tabeli")
    func usagesInText() {
        let text = """
            select * from emp;          -- emp w komentarzu
            select 'emp' from dual;
            insert into scott.emp values (1);
            select * from other.emp;
            update dept set dname = 'x' where deptno = 1;
            select e.sal, d.deptno from emp e join dept d on d.deptno = e.deptno;
            """
        #expect(UsageFinder.lines(in: text, name: "EMP", owner: "SCOTT").map(\.line) == [1, 3, 6])
        #expect(UsageFinder.lines(in: text, name: "emp").map(\.line) == [1, 3, 4, 6])
        #expect(UsageFinder.columnLines(in: text, table: "DEPT", column: "DEPTNO").map(\.line) == [5, 6])
        #expect(UsageFinder.columnLines(in: text, table: "EMP", column: "DNAME").isEmpty)
        #expect(NameResolver.relation(qualifier: "d", at: (text as NSString).range(of: "d.deptno").location, in: text)?.name == "DEPT")
    }

    @Test("Zmiana nazwy zmiennej w zakresie: bez pól innych obiektów, notacji nazwanej, komentarzy i innego podprogramu")
    func renameLocal() throws {
        let src = """
            create or replace package body p is
              procedure a(n number) is
                total number := 0; -- total
              begin
                total := total + n;
                q(total => total);
                r.total := 1;
              end;
              procedure b is
                total number;
              begin
                total := 2;
              end;
            end;
            """
        let at = (src as NSString).range(of: "total := total").location
        let (out, n) = try Refactoring.renameLocal(in: src, at: at, to: "l_sum")
        #expect(n == 4, "\(out)")
        #expect(out.contains("l_sum number := 0; -- total") && out.contains("l_sum := l_sum + n;") && out.contains("q(total => l_sum);"))
        #expect(out.contains("r.total := 1;") && out.contains("    total := 2;"))
        #expect(throws: CommandError.self) { try Refactoring.renameLocal(in: src, at: at, to: "1zła") }
    }

    @Test("Zmiana nazwy obiektu w oknach i plikach z podglądem; zastosowanie zapisuje historię; DDL bez wykonania")
    func renameObject() throws {
        let ws = Workspace()
        let d1 = ws.newDocument(.sql, text: "select * from emp e where emp.id = 1; -- emp\nselect * from scott.emp, other.emp;")
        let d2 = ws.newDocument(.sql, text: "select 1 from dual;")
        let dir = tempDir()
        let file = dir.appendingPathComponent("x.sql")
        try Data("begin emp_api.go; delete from EMP; end;\n".utf8).write(to: file)
        let changes = try Refactoring.renameObject("EMP", owner: "SCOTT", to: "employees",
                                                   texts: [(.document(d1.id), d1.title, d1.text), (.document(d2.id), d2.title, d2.text),
                                                           (.file(file), "x.sql", try String(contentsOf: file, encoding: .utf8))])
        #expect(changes.count == 2)
        #expect(changes[0].after == "select * from employees e where employees.id = 1; -- emp\nselect * from scott.employees, other.emp;")
        #expect(changes[0].changedLines.count == 2 && changes[1].occurrences == 1)
        let ddl = Refactoring.renameDDL(owner: "SCOTT", name: "EMP", type: .table, newName: "employees")
        #expect(ddl == "alter table SCOTT.EMP rename to EMPLOYEES;")
        #expect(Refactoring.renameDDL(owner: "S", name: "T", type: .table, newName: "b", column: "a") == "alter table S.T rename column A to B;")
        let before = ws.documents.count
        let n = try ws.apply(RefactoringPlan(title: "t", changes: changes, ddl: ddl))
        #expect(n == 2 && d1.text.contains("scott.employees"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "begin emp_api.go; delete from employees; end;\n")
        #expect(ws.documents.count == before + 1 && ws.activeDocument?.text == ddl)
        #expect(ws.localHistory.entries(LocalHistory.key(file: file)).first?.text.contains("EMP") == true)
    }

    @Test("Historia lokalna: zapis na dysk, pomijanie duplikatów, limit, przywrócenie z zapamiętaniem bieżącego tekstu")
    func localHistory() throws {
        let dir = tempDir()
        let ws = Workspace(dataDirectory: dir)
        let file = dir.appendingPathComponent("a.sql")
        let doc = ws.newDocument(.sql, text: "select 1 from dual")
        try ws.save(doc, to: file)
        doc.text = "select 2 from dual"
        try ws.save(doc, to: file)
        try ws.save(doc, to: file)                         // bez zmian — bez nowej wersji
        let key = LocalHistory.key(file: file)
        #expect(ws.localHistory.entries(key).map(\.text) == ["select 2 from dual", "select 1 from dual"])
        // Nowa instancja czyta z dysku.
        let fresh = LocalHistory(directory: dir.appendingPathComponent("LocalHistory"))
        #expect(fresh.entries(key).count == 2 && fresh.allItems().first?.title == "a.sql")
        doc.text = "select 3 from dual"                     // niezapisana zmiana trafia do historii przed przywróceniem
        ws.restore(ws.localHistory.entries(key)[1], in: doc)
        #expect(doc.text == "select 1 from dual")
        #expect(ws.localHistory.entries(key).first?.label == L10n.tr("przed przywróceniem"))
        #expect(ws.localHistory.entries(key).first?.text == "select 3 from dual")
        for i in 0..<(LocalHistory.maxEntries + 5) { fresh.record(key: "k", title: "k", text: "\(i)", label: "x") }
        #expect(fresh.entries("k").count == LocalHistory.maxEntries && fresh.entries("k").first?.text == "\(LocalHistory.maxEntries + 4)")
        // Okno programu bez pliku: klucz z jednostki.
        let prog = ws.newDocument(.program, text: "create or replace procedure hr.p is begin null; end;\n/\n")
        #expect(ws.localHistory.key(for: prog, connection: nil)?.title == "HR.P (PROCEDURE)")
        // Bez właściciela w nagłówku — schemat połączenia (jak klucz zapisywany przy kompilacji).
        let bare = ws.newDocument(.program, text: "create or replace function f return number is begin return 1; end;\n/\n")
        let conn = UUID()
        #expect(ws.localHistory.key(for: bare, connection: conn, schema: "U")?.key
                == LocalHistory.key(object: "U", type: "FUNCTION", name: "F", connection: conn))
        #expect(ws.localHistory.key(for: ws.newDocument(.sql), connection: nil) == nil)
    }

    @Test("Konsola połączenia: jedno okno na połączenie, tekst zachowany po zamknięciu i w nowej sesji aplikacji")
    func consoles() {
        let dir = tempDir()
        let conn = UUID()
        var ws = Workspace(dataDirectory: dir)
        let c = ws.openConsole(connection: conn)
        #expect(c.connectionID == conn && c.connectionPinned && c.consoleConnectionID == conn)
        c.text = "select sysdate from dual;"
        _ = ws.newDocument(.sql)
        #expect(ws.openConsole(connection: conn) === c && ws.activeDocument === c)
        ws.close(c.id)
        #expect(ws.openConsole(connection: conn).text == "select sysdate from dual;")
        ws.activeDocument?.text += "\nselect 1 from dual;"
        ws.persistConsoles()
        ws = Workspace(dataDirectory: dir)
        #expect(ws.openConsole(connection: conn).text == "select sysdate from dual;\nselect 1 from dual;")
    }

    @Test("Zmiany oczekujące w siatce: podsumowanie, stan wiersza, zmiana przywrócona do oryginału, nawigacja, cofnięcie wiersza")
    func gridPending() async throws {
        let columns = [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER"), ColumnInfo(name: "NAME", type: .varchar2, typeName: "VARCHAR2(20)"),
                       ColumnInfo(name: "ROWID", type: .rowid, typeName: "ROWID")]
        let rows: [[OracleValue]] = (1...5).map { [.number("\($0)"), .text("n\($0)"), .text("AAA\($0)")] }
        let g = ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession(rows), sql: "select id, name, rowid from t", format: ValueFormat())
        await g.fetchAll()
        var target = EditTarget(owner: "U", table: "T", rowidColumn: 2, editableColumns: [0, 1], tableColumn: [0: "ID", 1: "NAME"])
        target.largeDataColumns = []
        g.edit.target = target
        g.edit.isEditing = true
        #expect(g.pendingSummary.isEmpty && g.nextPendingRow(after: nil) == nil)
        try g.setText("x", row: 1, column: 1)
        try g.setText("9", row: 1, column: 0)
        try g.setText("y", row: 3, column: 1)
        try g.setText("n4", row: 3, column: 1)          // z powrotem do oryginału
        try g.deleteRecords([4])
        let new = try g.insertRecord()
        let s = g.pendingSummary
        #expect(s.inserted == 1 && s.updated == 1 && s.updatedCells == 2 && s.deleted == 1, "\(s)")
        #expect(g.rowEditState(row: 1) == .modified && g.rowEditState(row: 3) == .normal && g.rowEditState(row: 4) == .deleted)
        #expect(g.pendingCellState(row: 3, column: 1) == .normal && g.cellState(row: 3, column: 1) == .modified)
        #expect(g.nextPendingRow(after: nil) == 1 && g.nextPendingRow(after: 1) == 4 && g.nextPendingRow(after: new) == 1)
        #expect(g.nextPendingRow(after: 1, forward: false) == new)
        g.revertRows([1, 4, new])
        #expect(g.pendingSummary.isEmpty && g.rowCount == 5 && g.text(row: 1, column: 1) == "n2")
    }
}
