import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Źródło metadanych w pamięci (diagram ER bez bazy).
struct ERFakeSchema: SchemaMetadataSource {
    var tables: [String: [SchemaColumn]]
    var fks: [ForeignKey]
    func resolve(_ raw: String) async throws -> DBObject? { nil }
    func columns(owner: String, name: String) async throws -> [SchemaColumn] { tables[name] ?? [] }
    func foreignKeys(owner: String, table: String) async throws -> [ForeignKey] {
        fks.filter { $0.childTable == table || $0.parentTable == table }
    }
    func references(owner: String, name: String) async throws -> [DBObject] { [] }
}

@MainActor
@Suite("Etap 7: notatnik, raporty predefiniowane, Diff/koszyk, kopiowanie, import, diagram ER, przenoszenie, zadania lokalne")
struct Stage7ToolsTests {
    @Test("Notatnik: zapis i odczyt JSON z wynikami, eksport Markdown, dane wykresu z wyniku komórki")
    func notebook() throws {
        var n = Notebook()
        var r = NotebookResult()
        r.columns = ["DEPT", "SAL"]
        r.columnTypes = ["VARCHAR2", "NUMBER"]
        r.rows = [["A", "10"], ["B", "2,5"], ["C", nil]]
        r.output = ["hello"]
        r.finished = Date(timeIntervalSince1970: 1_800_000_000)
        n.cells[1].result = r
        n.cells[1].chart = r.suggestedChart()
        let back = try Notebook.decode(n.encoded())
        #expect(back == n)
        let md = NotebookRunner.markdown(back)
        #expect(md.contains("# ") && md.contains("```sql") && md.contains("| DEPT | SAL |") && md.contains("| B | 2,5 |") && md.contains("hello"))
        let chart = r.chartData(try #require(n.cells[1].chart))
        #expect(chart.categories == ["A", "B", "C"] && chart.points.map(\.value) == [10, 2.5])
        #expect(throws: (any Error).self) { try Notebook.decode(Data(#"{"format":"x","version":1,"cells":[],"maxRows":1}"#.utf8)) }
        #expect(DocumentKind.forFile(URL(fileURLWithPath: "/x/a.sqlnb")) == .notebook)
    }

    @Test("Notatnik: wynik trafia do wykonywanej komórki mimo przestawienia komórek w trakcie; drugie wykonanie naraz pominięte")
    func notebookRunTracksCell() async throws {
        let ws = Workspace(drivers: [.instantClient: GateDriver()])
        let def = ConnectionDefinition(name: "nb", target: ConnectionTarget(user: "u", connectString: "db"))
        try ws.connections.upsert(def, password: "good")
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.notebook)
        doc.notebook.cells = [NotebookCell(kind: .sql, text: "select 'gate' from dual"), NotebookCell(kind: .sql, text: "select 2 from dual")]
        let first = doc.notebook.cells[0].id
        let task = Task { await NotebookRunner.run(cell: 0, in: doc, ws: ws) }
        for _ in 0..<1000 where !GateSession.waiting.withLock({ $0 }) { await Task.yield() }
        #expect(doc.isExecuting)
        await NotebookRunner.run(cell: 1, in: doc, ws: ws)                 // w trakcie — pominięte
        #expect(doc.notebook.cells[1].result == nil)
        doc.notebook.cells.swapAt(0, 1)
        GateSession.open.withLock { $0 = true }
        await task.value
        #expect(!doc.isExecuting)
        #expect(doc.notebook.cells.first { $0.id == first }?.result != nil)
        #expect(doc.notebook.cells.first { $0.id != first }?.result == nil)
    }

    @Test("Raporty predefiniowane: unikalne identyfikatory, kategorie, zmienne zadeklarowane, wiązania szczegółów z kolumn")
    func predefinedCatalog() throws {
        let cat = PredefinedReports.catalog
        #expect(Set(cat.map(\.id)).count == cat.count)
        #expect(PredefinedReports.categories.count >= 6)
        #expect(cat.contains { $0.style == .chart } && cat.contains { $0.style == .dbmsOutput })
        for r in cat {
            let declared = Set(r.variables.map(\.name))
            #expect(Set(PredefinedReports.bindNames(r.sql)).isSubset(of: declared), "\(r.id)")
            if let d = r.detailSQL {
                let binds = PredefinedReports.bindNames(d).filter { !$0.hasPrefix("PARENT_") }
                #expect(Set(binds).isSubset(of: declared), "\(r.id)")
            }
        }
        let r = try #require(PredefinedReports.report("objectsByType"))
        let res = PredefinedReportResult(columns: [ColumnInfo(name: "OBJECT_TYPE", type: .varchar2, typeName: "VARCHAR2"),
                                                   ColumnInfo(name: "LICZBA", type: .number, typeName: "NUMBER")],
                                         rows: [[.text("TABLE"), .number("3")]])
        #expect(PredefinedReports.detailValues(r, result: res, row: 0, values: ["OWNER": "X"]) == ["OWNER": "X", "PARENT_OBJECT_TYPE": "TABLE", "PARENT_LICZBA": "3"])
        #expect(PredefinedReports.chartData(r, res)?.points.first?.value == 3)
        #expect(PredefinedReports.exportData(r, res).rows.count == 1)
    }

    @Test("Database Diff: ALTER TABLE ADD/MODIFY/DROP kolumn; koszyk z różnic, zapis JSON")
    func diffAndCart() throws {
        let src = [TableColumnDefinition(name: "ID", type: "NUMBER", nullable: false), TableColumnDefinition(name: "NAME", type: "VARCHAR2(40 CHAR)"),
                   TableColumnDefinition(name: "CREATED", type: "DATE", defaultValue: "sysdate")]
        let dst = [TableColumnDefinition(name: "ID", type: "NUMBER"), TableColumnDefinition(name: "NAME", type: "VARCHAR2(20 CHAR)"),
                   TableColumnDefinition(name: "OLD", type: "NUMBER")]
        let alters = DatabaseDiff.alterTable("T", source: src, target: dst, dropColumns: false)
        #expect(alters == ["alter table T modify (ID not null);", "alter table T modify (NAME varchar2(40 char));",
                           "alter table T add (CREATED date default sysdate);", "-- alter table T drop column OLD;"])
        #expect(DatabaseDiff.alterTable("T", source: src, target: dst, dropColumns: true).last == "alter table T drop column OLD;")
        #expect(DatabaseDiff.alterTable("T", source: src, target: src, dropColumns: true).isEmpty)
        let diffs = [ObjectDifference(name: "T", type: .table, status: .different, sourceDDL: "", targetDDL: "", sync: alters.joined(separator: "\n")),
                     ObjectDifference(name: "F", type: .function, status: .onlySource, sourceDDL: "x", targetDDL: "", sync: "x"),
                     ObjectDifference(name: "G", type: .function, status: .onlyTarget, sourceDDL: "", targetDDL: "", sync: "")]
        var cart = DatabaseDiff.cart(from: diffs, sourceOwner: "S")
        #expect(cart.items.map(\.name) == ["T", "F"] && cart.items[0].syncScript != nil && cart.items[1].syncScript == nil)
        cart.add(DBObject(owner: "S", name: "F", type: .function))
        cart.add(DBObject(owner: "S", name: "V", type: .view))
        #expect(cart.items.count == 3)
        cart.remove([cart.items[0].id])
        #expect(try DeploymentCart.decode(cart.encoded()) == cart)
    }

    @Test("Kopiowanie schematu: plan w fazach (tabele, dane, obiekty, klucze obce, wyzwalacze), filtr typów i obiektów")
    func copyPlan() {
        let objs = [DBObject(owner: "S", name: "TRG", type: .trigger), DBObject(owner: "S", name: "V", type: .view),
                    DBObject(owner: "S", name: "EMP", type: .table), DBObject(owner: "S", name: "SEQ", type: .sequence),
                    DBObject(owner: "S", name: "DEPT", type: .table), DBObject(owner: "S", name: "PKG", type: .packageBody),
                    DBObject(owner: "S", name: "PKG", type: .package)]
        let plan = SchemaCopy.plan(objs, options: SchemaCopy.Options())
        #expect(plan.map { "\($0.phase.rawValue):\($0.object.name)" } == [
            "0:SEQ", "1:DEPT", "1:EMP", "2:DEPT", "2:EMP", "3:V", "3:PKG", "3:PKG", "4:DEPT", "4:EMP", "5:TRG"])
        #expect(plan.filter { $0.phase == .objects }.map(\.object.type) == [.view, .package, .packageBody])
        var o = SchemaCopy.Options()
        o.copyData = false
        o.types = ["TABLE"]
        o.objects = ["TABLE EMP"]
        #expect(SchemaCopy.plan(objs, options: o).map(\.phase) == [.tables, .foreignKeys])
        let sts = SchemaCopy.statements("create table a (x number);\ncreate or replace procedure p is begin null; end;\n/\nset echo on\n")
        #expect(sts == ["create table a (x number)", "create or replace procedure p is begin null; end;"])
    }

    @Test("Kreator importu: stała szerokość, kodowania (ISO-8859-2, Windows-1250), CSV, propozycja ustawień, profil")
    func importWizard() throws {
        let fixed = "ID  NAZWA     KWOTA\n1   Łódź      10.5\n22  Kraków    3\n"
        #expect(ImportWizard.guessFixedStarts(fixed) == [0, 4, 14])
        #expect(ImportWizard.splitFixed("22  Kraków    3", starts: [0, 4, 14]) == ["22", "Kraków", "3"])
        var s = ImportWizardState()
        s.source = .fixedWidth
        s.encoding = "ISO-8859-2"
        let data = try #require(fixed.data(using: .isoLatin2))
        let read = try ImportWizard.read(data, state: s)
        #expect(read.fieldNames == ["ID", "NAZWA", "KWOTA"] && read.rows == [["1", "Łódź", "10.5"], ["22", "Kraków", "3"]] && read.encoding == "ISO-8859-2")
        // Auto: Windows-1250 (polskie litery na pozycjach C1 nie istnieją w ISO-8859-2 — „ś” = 0x9C).
        let cp = try #require("a;b\nść;1\n".data(using: .windowsCP1250))
        #expect(ImportWizard.decode(cp, encoding: "auto").text == "a;b\nść;1\n")
        let sug = ImportWizard.suggest(fileName: "/tmp/Sprzedaż 2026.csv", data: Data("id;nazwa\n1;x\n".utf8))
        #expect(sug.source == .delimited && sug.text.delimiter == ";" && sug.table == "SPRZEDAŻ_2026")
        #expect(ImportWizard.suggest(fileName: "raport.txt", data: Data(fixed.utf8)).source == .fixedWidth)
        #expect(ImportWizard.suggest(fileName: "a.xlsx", data: Data()).source == .excel)
        let csv = try ImportWizard.read(Data("id;nazwa\n1;x\n2;y\n".utf8), state: sug)
        #expect(csv.fieldNames == ["id", "nazwa"] && csv.rows.count == 2)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-imp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try ImportProfileStore.save(s, name: "stała/szer", in: dir)
        #expect(ImportProfileStore.names(in: dir) == ["stała_szer"])
        #expect(try ImportProfileStore.load("stała/szer", in: dir) == s)
    }

    @Test("Diagram ER: poziomy z kluczy obcych (cykl przerwany), układ bez nakładania, linie FK")
    func erDiagram() async throws {
        let col = [SchemaColumn(name: "ID", type: "NUMBER", primaryKey: true)]
        func fk(_ c: String, _ p: String) -> ForeignKey {
            ForeignKey(name: "FK_\(c)_\(p)", childOwner: "S", childTable: c, childColumns: ["ID"], parentOwner: "S", parentTable: p, parentColumns: ["ID"])
        }
        let src = ERFakeSchema(tables: ["DEPT": col, "EMP": col + col, "BONUS": col, "A": col, "B": col],
                             fks: [fk("EMP", "DEPT"), fk("BONUS", "EMP"), fk("A", "B"), fk("B", "A")])
        let d = try await ERDiagram.build(owner: "S", tables: ["BONUS", "DEPT", "EMP", "A", "B"], source: src)
        #expect(d.items.count == 5 && d.links.count == 4)
        let lv = ERDiagram.levels(d)
        func level(_ n: String) -> Int? { d.item(owner: "S", name: n).flatMap { lv[$0.id] } }
        #expect(level("DEPT") == 0 && level("EMP") == 1 && level("BONUS") == 2)
        #expect(Set([level("A"), level("B")]) == Set([0, 1]))
        let frames = d.items.map(\.frame)
        for i in frames.indices { for j in frames.indices where i < j { #expect(!frames[i].intersects(frames[j])) } }
        #expect(try #require(d.item(owner: "S", name: "DEPT")).frame.x < (try #require(d.item(owner: "S", name: "EMP")).frame.x))
    }

    @Test("Diagram ER dużego schematu: 2000 tabel bez szukania wolnego miejsca dla każdej, układ bez nakładania (D165)",
          .timeLimit(.minutes(1)))
    func erDiagramLarge() async throws {
        let col = [SchemaColumn(name: "ID", type: "NUMBER", primaryKey: true)]
        let names = (0..<2000).map { String(format: "T%04d", $0) }
        let fks = (1..<200).map { i in
            ForeignKey(name: "FK\(i)", childOwner: "S", childTable: names[i], childColumns: ["ID"], parentOwner: "S", parentTable: names[i - 1], parentColumns: ["ID"])
        }
        let src = ERFakeSchema(tables: Dictionary(uniqueKeysWithValues: names.map { ($0, col) }), fks: fks)
        let d = try await ERDiagram.build(owner: "S", tables: names + ["T0000"], source: src, showColumns: false)
        #expect(d.items.count == 2000 && d.links.count == 199)
        #expect(d.items.allSatisfy { !$0.showColumns && $0.columns.count == 1 && $0.frame.height == 32 })
        // Bez nakładania: ramki posortowane po x, potem po y — sąsiednie w kolumnie się nie przecinają, kolumny się nie zachodzą.
        let byColumn = Dictionary(grouping: d.items.map(\.frame), by: \.x)
        for (_, frames) in byColumn {
            let f = frames.sorted { $0.y < $1.y }
            for i in f.indices.dropFirst() { #expect(!f[i - 1].intersects(f[i])) }
        }
        let xs = byColumn.keys.sorted()
        for i in xs.indices.dropFirst() { #expect(xs[i] - xs[i - 1] >= 200) }
        #expect(ERDiagram.levels(d)[try #require(d.item(owner: "S", name: "T0199")).id] == 199)
    }

    @Test("Przenoszenie danych: mapowanie po nazwach, INSERT z literałami i stałą, kontrola definicji")
    func transfer() throws {
        var job = DataTransferJob()
        job.sourceOwner = "s"
        job.sourceTable = "emp"
        job.whereClause = "deptno = 10"
        job.targetOwner = "t"
        job.targetTable = "emp_copy"
        #expect(job.sourceSQL == "select * from S.EMP where deptno = 10")
        job.mappings = DataTransferRunner.defaultMappings(targetColumns: ["ID", "NAME", "LOADED"], sourceColumns: ["name", "id", "sal"])
        #expect(job.mappings.map(\.source) == ["id", "name", nil])
        job.mappings[2].constant = "sysdate"
        #expect(DataTransferRunner.insert(job, columns: ["NAME", "ID", "SAL"], row: [.text("O'Brien"), .number("7"), .number("1")])
                == "insert into T.EMP_COPY (ID, NAME, LOADED) values (7, 'O''Brien', sysdate)")
        try DataTransferRunner.validate(job)
        job.mappings = job.mappings.map { TransferColumnMapping(target: $0.target, source: nil) }
        #expect(throws: (any Error).self) { try DataTransferRunner.validate(job) }
        job.sourceQuery = "select 1 x from dual;"
        #expect(job.sourceSQL == "select 1 x from dual")
    }

    @Test("Zadania lokalne: następne uruchomienie (co n min, codziennie, w dni tygodnia), nazwa pliku, brak haseł w definicjach")
    func localTasks() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let base = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 10, minute: 15))!   // piątek
        #expect(LocalTaskSchedule.interval(minutes: 30).next(after: base, calendar: cal) == base.addingTimeInterval(1800))
        #expect(LocalTaskSchedule.daily(hour: 9, minute: 0).next(after: base, calendar: cal) == cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9)))
        #expect(LocalTaskSchedule.daily(hour: 11, minute: 0).next(after: base, calendar: cal) == cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 11)))
        #expect(LocalTaskSchedule.weekly(weekdays: [2, 4], hour: 8, minute: 30).next(after: base, calendar: cal)
                == cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 8, minute: 30)))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        #expect(LocalTaskRunner.fileName("emp-{date}.csv", at: base) == "emp-\(f.string(from: base)).csv")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-tasks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sch = LocalTaskScheduler(directory: dir)
        let d = LocalTaskDefinition(name: "Eksport", connection: "test", action: .export(query: "select 1 from dual", directory: "/tmp", fileName: "x.csv", format: .csv),
                                    schedule: .interval(minutes: 5))
        try sch.upsert(d)
        #expect(sch.due(at: Date()).isEmpty && sch.due(at: Date().addingTimeInterval(400)).map(\.id) == [d.id])
        let json = try String(contentsOf: dir.appendingPathComponent("tasks.json"), encoding: .utf8)
        #expect(!json.lowercased().contains("password") && !json.lowercased().contains("hasło") && json.contains("\"connection\" : \"test\""))
        #expect(LocalTaskScheduler(directory: dir).definitions == [d])
        try sch.remove(d.id)
        #expect(sch.definitions.isEmpty)
    }

    @Test("Komendy narzędzi etapu 7 w rejestrze: identyfikatory wierszy macierzy, agent — Brak")
    func commands() {
        let ws = Workspace(drivers: [:])
        let ids: [String: String] = ["notebook.runAll": "SD-NB-001", "reports.predefined": "SD-REP-001", "tools.databaseDiff": "SD-DIFF-001",
                                     "cart.script": "SD-DIFF-001", "tools.schemaCopy": "SD-COPY-001", "tools.importWizard": "SD-IMP-001",
                                     "diagram.fromSchema": "DB-DIAG-001", "tools.dataTransfer": "DB-XFER-001", "tools.localTasks": "DB-TASK-001"]
        for (id, feature) in ids {
            let c = ws.registry.command(CommandID(rawValue: id))
            #expect(c?.descriptor.feature == feature, "\(id)")
            #expect(c?.descriptor.agentAccess == AgentAccess.none, "\(id)")
        }
    }
}

/// Sesja, której polecenie z „gate” czeka na otwarcie bramki (wykonanie „w trakcie” bez bazy).
final class GateSession: DatabaseSession, @unchecked Sendable {
    static let waiting = Mutex(false)
    static let open = Mutex(false)
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        if sql.contains("gate") {
            Self.waiting.withLock { $0 = true }
            while !Self.open.withLock({ $0 }) { await Task.yield() }
        }
        return ExecutionResult(kind: .other)
    }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch { RowBatch(rows: [], hasMore: false) }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
}

final class GateDriver: DatabaseDriver, @unchecked Sendable {
    let kind = DriverKind.instantClient
    let capabilities: DriverCapabilities = []
    func availability() -> Result<Void, DatabaseError> { .success(()) }
    func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession { GateSession() }
}
