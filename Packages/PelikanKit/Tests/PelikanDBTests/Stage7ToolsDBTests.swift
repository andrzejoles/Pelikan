import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Etap 7 na bazie testowej: SQLcl, notatnik, raporty, Diff/koszyk, kopiowanie, import, diagram ER, przenoszenie, zadania", .enabled(if: TestDatabase.isAvailable), .serialized)
struct Stage7ToolsDBTests {
    func workspace(dataDirectory: URL? = nil) throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(dataDirectory: dataDirectory, drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    func temporaryDirectory() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-s7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Sesja SYSTEM i pusty schemat docelowy (bez logowania) — cel kopiowania i porównań.
    func targetSchema(_ name: String) async throws -> ODPISession {
        let c = TestDatabase.config!
        let sys = try await ODPISession.connect(target: ConnectionTarget(user: "SYSTEM", connectString: c.connectString),
                                                credentials: Credentials(password: c.systemPassword), options: ConnectOptions())
        _ = try? await sys.execute("drop user \(name) cascade")
        _ = try await sys.execute("create user \(name) no authentication quota 20m on users")
        return sys
    }

    @Test("SQLcl w oknie poleceń: INFO+, DDL, CTAS, ALIAS, HISTORY TIME, FORMAT BUFFER, REPEAT, LOAD NEW")
    func sqlcl() async throws {
        let (ws, id) = try workspace()
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "ID;NAZWA;KWOTA\n1;Łódź;10.5\n2;Kraków;3\n".write(to: dir.appendingPathComponent("dane.csv"), atomically: true, encoding: .utf8)
        let doc = ws.newDocument(.command)
        doc.connectionID = id
        let e = ws.sqlplusEngine(for: doc)
        _ = await e.run("""
            whenever sqlerror continue
            drop table pelikan_load purge;
            info+ dept
            ddl dept
            ctas emp emp_copy
            alias depts=select count(*) from dept;
            depts
            select 1 from dual;
            history time
            format buffer
            repeat 2 0
            load pelikan_load dane.csv new
            select count(*) from pelikan_load;
            """, baseDirectory: dir)
        let out = doc.console.map(\.text)
        let all = out.joined(separator: "\n")
        #expect(all.contains("NUM_DISTINCT") && all.contains("DEPTNO"), "\(all)")
        #expect(all.uppercased().contains("CREATE TABLE") && all.contains("\"DEPT\""))
        #expect(all.contains("create table emp_copy as") && all.contains("from \(TestDatabase.config!.user.lowercased()).emp"))
        #expect(e.state.aliases["DEPTS"] == "select count(*) from dept")
        #expect(out.contains { $0.range(of: #"^\s+\d+\s+\(\s*\d+\.\d{3} s\)\s+select 1 from dual"#, options: .regularExpression) != nil }, "\(out)")
        #expect(out.contains("Powtórzenie 2 z 2"))
        #expect(all.contains("Wczytano wierszy: 2, pominięto: 0, błędy: 0"), "\(all)")
        let s = try await TestDatabase.connect()
        #expect(try await s.scalar("select nazwa from pelikan_load where id = 1") == "Łódź")
        _ = try? await s.execute("drop table pelikan_load purge")
        await s.close()
        await ws.sessions.disconnectAll()
    }

    @Test("Notatnik: Run All (zapytanie, PL/SQL z DBMS_OUTPUT, błąd zatrzymuje), wyniki zapisane w pliku i wczytane")
    func notebook() async throws {
        let (ws, id) = try workspace()
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = ws.newDocument(.notebook)
        doc.connectionID = id
        doc.notebook.cells = [NotebookCell(kind: .markdown, text: "# Działy"),
                              NotebookCell(kind: .sql, text: "select dname, count(*) n from dept d join emp e on e.deptno = d.deptno group by dname order by 1;"),
                              NotebookCell(kind: .sql, text: "begin dbms_output.put_line('ok ' || 42); end;\n/"),
                              NotebookCell(kind: .sql, text: "select * from nie_ma_takiej_tabeli"),
                              NotebookCell(kind: .sql, text: "select 1 from dual")]
        ws.activate(doc.id)
        try await ws.invoke("notebook.runAll")
        let cells = doc.notebook.cells
        #expect(cells[1].result?.columns == ["DNAME", "N"] && (cells[1].result?.rows.count ?? 0) > 0)
        #expect(cells[2].result?.output == ["ok 42"])
        #expect(cells[3].result?.error?.contains("ORA-00942") == true)
        #expect(cells[4].result == nil)
        let chart = try #require(cells[1].result).chartData(try #require(cells[1].result).suggestedChart())
        #expect(chart.points.count == cells[1].result?.rows.count)
        let url = dir.appendingPathComponent("n.sqlnb")
        try ws.save(doc, to: url)
        ws.close(doc.id)
        let back = try ws.openFile(url)
        #expect(back.kind == .notebook && back.notebook.cells[1].result?.rows == cells[1].result?.rows)
        await ws.sessions.disconnectAll()
    }

    @Test("Raporty predefiniowane: każdy raport katalogu wykonuje się; szczegóły wiersza; DBMS_OUTPUT")
    func predefinedReports() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        for r in PredefinedReports.catalog {
            let values = Dictionary(uniqueKeysWithValues: r.variables.map { ($0.name, $0.defaultValue) })
            let res = try await PredefinedReports.run(r, values: values, in: s)
            #expect(r.style == .dbmsOutput ? !res.output.isEmpty : !res.columns.isEmpty, "\(r.id)")
        }
        let r = try #require(PredefinedReports.report("objectsByType"))
        let master = try await PredefinedReports.run(r, values: [:], in: s)
        let row = try #require(master.rows.firstIndex { $0.first?.displayText == "TABLE" })
        let detail = try #require(try await PredefinedReports.detail(r, master: master, row: row, values: [:], in: s))
        #expect(detail.rows.contains { $0.first?.displayText == "EMP" })
        let tables = try await PredefinedReports.run(try #require(PredefinedReports.report("tableRows")), values: [:], in: s)
        #expect(tables.rows.contains { $0.first?.displayText == "DEPT" })
    }

    @Test("Database Diff i koszyk: ALTER TABLE dla różnych kolumn wyrównuje cel; skrypt wdrożenia z DDL i danymi")
    func diffAndCart() async throws {
        let sys = try await targetSchema("pelikan_dif")
        let src = try await TestDatabase.connect()
        defer { Task { _ = try? await sys.execute("drop user pelikan_dif cascade"); await sys.close(); _ = try? await src.execute("drop table pelikan_dif_t purge"); await src.close() } }
        _ = try? await src.execute("drop table pelikan_dif_t purge")
        _ = try await src.execute("create table pelikan_dif_t (id number primary key, name varchar2(40), created date default sysdate)")
        _ = try await src.execute("insert into pelikan_dif_t (id, name) values (1, 'A''B')")
        try await src.commit()
        _ = try await sys.execute("create table pelikan_dif.pelikan_dif_t (id number primary key, name varchar2(20), old number)")
        var o = DatabaseDiff.Options()
        o.types = ["TABLE"]
        let schema = TestDatabase.config!.user.uppercased()
        let diffs = try await DatabaseDiff.run(sourceOwner: schema, source: src, targetOwner: "PELIKAN_DIF", target: sys, options: o)
        let t = try #require(diffs.first { $0.name == "PELIKAN_DIF_T" })
        #expect(t.status == .different && t.sync.contains("modify (\"NAME\"") == false && t.sync.contains("alter table PELIKAN_DIF_T modify (NAME varchar2(40))"), "\(t.sync)")
        #expect(t.sync.contains("add (CREATED date default sysdate)") && t.sync.contains("-- alter table PELIKAN_DIF_T drop column OLD;"))
        #expect(diffs.contains { $0.name == "DEPT" && $0.status == .onlySource })
        _ = try await sys.execute("alter session set current_schema = pelikan_dif")
        for st in SchemaCopy.statements(t.sync) { _ = try await sys.execute(st) }
        let again = try await DatabaseDiff.run(sourceOwner: schema, source: src, targetOwner: "PELIKAN_DIF", target: sys, options: o)
        let after = try #require(again.first { $0.name == "PELIKAN_DIF_T" })
        let sc = try await DatabaseDiff.columns(owner: schema, table: after.name, in: src)
        let tc = try await DatabaseDiff.columns(owner: "PELIKAN_DIF", table: after.name, in: sys)
        #expect(after.status == .different && DatabaseDiff.alterTable(after.name, source: sc, target: tc, dropColumns: false) == ["-- alter table PELIKAN_DIF_T drop column OLD;"])
        var cart = DeploymentCart(name: "test")
        cart.add(DBObject(owner: schema, name: "PELIKAN_DIF_T", type: .table))
        cart.items[0].includeData = true
        cart.add(DBObject(owner: schema, name: "EMP_V", type: .view))
        let script = try await cart.deploymentScript(in: src)
        #expect(script.contains("CREATE TABLE \"PELIKAN_DIF_T\"") && script.contains("insert into PELIKAN_DIF_T (ID, NAME, CREATED)") && script.contains("'A''B'"), "\(script)")
        #expect(script.range(of: "PELIKAN_DIF_T\"")!.lowerBound < script.range(of: "EMP_V")!.lowerBound)
    }

    @Test("Kopiowanie schematu: tabele z danymi, sekwencja, widok, klucz obcy i wyzwalacz w schemacie docelowym")
    func schemaCopy() async throws {
        let sys = try await targetSchema("pelikan_cpy")
        let src = try await TestDatabase.connect()
        defer { Task { _ = try? await sys.execute("drop user pelikan_cpy cascade"); await sys.close(); await src.close() } }
        var o = SchemaCopy.Options()
        o.objects = ["TABLE DEPT", "TABLE EMP", "TABLE EMP_AUDIT", "SEQUENCE EMP_SEQ", "VIEW EMP_V", "TRIGGER EMP_SAL_TRG"]
        let schema = TestDatabase.config!.user.uppercased()
        let report = try await SchemaCopy.run(sourceOwner: schema, source: src, targetOwner: "PELIKAN_CPY", target: sys, options: o)
        #expect(report.errors.isEmpty, "\(report.errors)")
        #expect(Set(report.created) == o.objects)
        let srcEmp = try await src.scalar("select count(*) from emp")
        #expect(try await sys.scalar("select count(*) from pelikan_cpy.emp") == srcEmp)
        let fkDDL = try await SchemaCopy.foreignKeyDDL(DBObject(owner: schema, name: "EMP", type: .table), in: src)
        let fks = try await sys.scalar("select count(*) from all_constraints where owner = 'PELIKAN_CPY' and table_name = 'EMP' and constraint_type = 'R'")
        #expect(fks == "2", "\(fkDDL)")
        #expect(try await sys.scalar("select status from all_objects where owner = 'PELIKAN_CPY' and object_name = 'EMP_V'") == "VALID")
        let audit = try await src.scalar("select count(*) from emp_audit")
        #expect(try await sys.scalar("select count(*) from pelikan_cpy.emp_audit") == audit)
        // Ponownie: istniejące obiekty pominięte.
        let second = try await SchemaCopy.run(sourceOwner: schema, source: src, targetOwner: "PELIKAN_CPY", target: sys, options: o)
        #expect(Set(second.skipped) == o.objects && second.rows == 0)
        #expect(try await sys.scalar("select sys_context('userenv', 'current_schema') from dual") == "SYSTEM")
    }

    @Test("Kreator importu: plik o stałej szerokości w ISO-8859-2 do nowej tabeli, CSV do istniejącej z mapowaniem po nazwach")
    func importWizard() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { _ = try? await s.execute("drop table pelikan_imp purge"); await s.close() } }
        _ = try? await s.execute("drop table pelikan_imp purge")
        let fixed = "ID  NAZWA     KWOTA\n1   Łódź      10.5\n22  Kraków    3\n"
        var st = ImportWizard.suggest(fileName: "pelikan_imp.txt", data: Data(fixed.utf8))
        st.encoding = "ISO-8859-2"
        st.owner = TestDatabase.config!.user
        st.createTable = true
        let data = try ImportWizard.read(try #require(fixed.data(using: .isoLatin2)), state: st)
        try await ImportWizard.prepareMappings(&st, data: data, in: s)
        #expect(st.table == "PELIKAN_IMP" && st.mappings.map(\.type) == [.number, .string, .number])
        let r = try await ImportWizard.execute(st, data: data, in: s)
        #expect(r.inserted == 2 && r.errors.isEmpty, "\(r.errors)")
        #expect(try await s.scalar("select nazwa from pelikan_imp where id = 1") == "Łódź")
        var csv = ImportWizard.suggest(fileName: "x.csv", data: Data("kwota;id;nazwa\n7;3;Gdańsk\n".utf8))
        csv.owner = TestDatabase.config!.user
        csv.table = "pelikan_imp"
        let cd = try ImportWizard.read(Data("kwota;id;nazwa\n7;3;Gdańsk\n".utf8), state: csv)
        try await ImportWizard.prepareMappings(&csv, data: cd, in: s)
        let r2 = try await ImportWizard.execute(csv, data: cd, in: s)
        let kwota = try await s.scalar("select kwota from pelikan_imp where id = 3")
        #expect(r2.inserted == 1 && kwota == "7")
    }

    @Test("Diagram ER ze schematu: tabele, linia EMP → DEPT, poziomy układu; komenda diagram.fromSchema")
    func erDiagram() async throws {
        let (ws, id) = try workspace()
        let doc = try await ws.openERDiagram(owner: TestDatabase.config!.user, pattern: "%", connection: id)
        let d = doc.diagram
        let emp = try #require(d.item(owner: TestDatabase.config!.user.uppercased(), name: "EMP"))
        let dept = try #require(d.item(owner: TestDatabase.config!.user.uppercased(), name: "DEPT"))
        #expect(d.links.contains { $0.kind == .foreignKey && $0.from == emp.id && $0.to == dept.id })
        #expect(dept.frame.x < emp.frame.x)
        let r = try await ws.invoke("diagram.fromSchema", CommandArguments(["owner": .string(TestDatabase.config!.user), "pattern": .string("EMP%")]))
        #expect(r.message?.hasPrefix("Tabel:") == true && ws.activeDocument?.diagram.item(owner: emp.owner, name: "DEPT") == nil)
        await ws.sessions.disconnectAll()
    }

    @Test("Przenoszenie danych z mapowaniem: zapytanie źródłowe, stała, tryb truncate, zapis i wykonanie definicji")
    func dataTransfer() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (ws, _) = try workspace(dataDirectory: dir)
        let s = try await TestDatabase.connect()
        defer { Task { _ = try? await s.execute("drop table pelikan_xfer purge"); await s.close() } }
        _ = try? await s.execute("drop table pelikan_xfer purge")
        _ = try await s.execute("create table pelikan_xfer (nr number, nazwisko varchar2(30), zrodlo varchar2(10))")
        var job = DataTransferJob()
        job.sourceConnection = "t"
        job.targetConnection = "t"
        job.sourceQuery = "select empno, ename from emp where deptno = 10"
        job.targetOwner = TestDatabase.config!.user
        job.targetTable = "pelikan_xfer"
        job.mode = .truncate
        let tsess = try await ws.sessions.session(SessionKey(connectionID: try #require(ws.connectionID(named: "t")), purpose: .tool("x")))
        let srcCols = try await DataTransferRunner.sourceColumns(job, in: tsess)
        job.mappings = DataTransferRunner.defaultMappings(targetColumns: try await DataTransferRunner.targetColumns(job, in: tsess), sourceColumns: srcCols)
        #expect(job.mappings.map(\.source) == [nil, nil, nil])
        job.mappings = [TransferColumnMapping(target: "NR", source: "EMPNO"), TransferColumnMapping(target: "NAZWISKO", source: "ENAME"),
                        TransferColumnMapping(target: "ZRODLO", source: nil, constant: "'EMP'")]
        try DataTransferStore.save(job, name: "emp10", in: dir)
        try await ws.invoke("transfer.run", CommandArguments(["name": .string("emp10")]))
        if let t = ws.tasks.tasks.first { await ws.tasks.wait(t); #expect(t.status == .succeeded, "\(t.status)") }
        try await ws.invoke("transfer.run", CommandArguments(["name": .string("emp10")]))
        if let t = ws.tasks.tasks.first { await ws.tasks.wait(t) }
        let n = try await s.scalar("select count(*) from emp where deptno = 10")
        #expect(try await s.scalar("select count(*) from pelikan_xfer where zrodlo = 'EMP'") == n)
        await ws.sessions.disconnectAll()
    }

    @Test("Zadania lokalne: eksport do pliku i skrypt bez zatwierdzania (wycofany), dziennik i stan w katalogu danych")
    func localTasks() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (ws, _) = try workspace(dataDirectory: dir)
        let out = dir.appendingPathComponent("out")
        let export = LocalTaskDefinition(name: "eksport", connection: "t",
                                         action: .export(query: "select deptno, dname from dept order by 1", directory: out.path, fileName: "dept-{date}", format: .csv),
                                         schedule: .daily(hour: 3, minute: 0))
        let script = LocalTaskDefinition(name: "skrypt", connection: "t",
                                         action: .script(file: nil, text: "set echo on\nupdate dept set loc = loc;\nbegin dbms_output.put_line('x'); end;\n/", commit: false),
                                         schedule: .interval(minutes: 60))
        try ws.localTasks.upsert(export)
        try ws.localTasks.upsert(script)
        ws.localTasks.start(ws, interval: .seconds(3600))
        defer { ws.localTasks.stop() }
        for d in [export, script] {
            let t = try #require(ws.localTasks.run(d))
            await ws.tasks.wait(t)
            #expect(t.status == .succeeded, "\(d.name): \(t.status)")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(files.count == 1 && files[0].hasPrefix("dept-") && files[0].hasSuffix(".csv"))
        let csv = try String(contentsOf: out.appendingPathComponent(files[0]), encoding: .utf8)
        #expect(csv.contains("DEPTNO") && csv.contains("KSIĘGOWOŚĆ"))
        let st = ws.localTasks.state[script.id]
        #expect(st?.lastStatus == "OK" && st?.lastLog != nil && (st?.nextRun ?? .distantPast) > Date())
        let log = try String(contentsOf: dir.appendingPathComponent("Tasks/logs/\(try #require(st?.lastLog))"), encoding: .utf8)
        #expect(log.contains("Pominięto polecenie SQL*Plus: SET") && log.contains("x") && log.contains("Wycofano"), "\(log)")
        let defs = try String(contentsOf: dir.appendingPathComponent("Tasks/tasks.json"), encoding: .utf8)
        #expect(!defs.contains(TestDatabase.config!.password))
        await ws.sessions.disconnectAll()
    }
}
