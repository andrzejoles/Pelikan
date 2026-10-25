import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Sesja odrzucająca zapytania zawierające wskazany fragment (brak kolumny/widoku na starszym serwerze).
final class OldDictionarySession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 11, minor: 2),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    let missing: [String: Int32]
    let executed = Mutex<[String]>([])
    init(missing: [String: Int32]) { self.missing = missing }
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        executed.withLock { $0.append(sql) }
        for (fragment, code) in missing where sql.contains(fragment) {
            throw OracleError(code: code, message: "ORA-\(String(format: "%05d", code)): missing")
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

@MainActor
@Suite("P1 dane: siatka, Large Data Editor, edytor tabeli, Object Browser, wyszukiwanie")
struct P1DataTests {
    // MARK: Siatka

    @Test("Układ liczb: separator regionalny i tysięcy bez utraty precyzji; notacja wykładnicza bez zmian (PD-GRID-004)")
    func numberLayout() {
        #expect(NumberLayout.thousands.apply("1234567.891", decimal: ",", group: " ") == "1 234 567,891")
        #expect(NumberLayout.thousands.apply("-1234", decimal: ".", group: ",") == "-1,234")
        #expect(NumberLayout.thousands.apply("123", decimal: ",", group: " ") == "123")
        #expect(NumberLayout.thousands.apply("12345678901234567890123456789012345678", decimal: ".", group: ",")
                == "12,345,678,901,234,567,890,123,456,789,012,345,678")
        #expect(NumberLayout.formatted.apply("1234.5", decimal: ",", group: " ") == "1234,5")
        #expect(NumberLayout.formatted.apply(".5", decimal: ",", group: " ") == ",5")
        #expect(NumberLayout.thousands.apply("1.5E+20", decimal: ",", group: " ") == "1.5E+20")
        #expect(NumberLayout.right.apply("1234.5", decimal: ",", group: " ") == "1234.5")
        #expect(NumberLayout.left.apply("1234.5", decimal: ",", group: " ") == "1234.5")
        #expect(!NumberLayout.left.alignsRight && NumberLayout.thousands.alignsRight)
    }

    func grid(_ rows: [[OracleValue]]) -> ResultGridModel {
        ResultGridModel(columns: [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER"), ColumnInfo(name: "NAME", type: .varchar2, typeName: "VARCHAR2(20)"),
                                  ColumnInfo(name: "D", type: .date, typeName: "DATE")],
                        resultSet: ResultSetID(1), session: RowsSession(rows), sql: "select id, name, d from t", format: ValueFormat())
    }

    @Test("Tekst komórki wg układu: tylko kolumny liczbowe (PD-GRID-004)")
    func displayText() async {
        let g = grid([[.number("12345.5"), .text("12345"), .timestamp(OracleTimestamp(year: 2024, month: 5, day: 1, hour: 13), .date)]])
        await g.fetchAll()
        #expect(g.displayText(row: 0, column: 0, layout: .thousands, separators: (",", " ")) == "12 345,5")
        #expect(g.displayText(row: 0, column: 1, layout: .thousands, separators: (",", " ")) == "12345")
        #expect(g.isDateColumn(2) && !g.isDateColumn(0))
        #expect(g.timestamp(row: 0, column: 2)?.hour == 13)
    }

    @Test("Blok komórek: kolumny w kolejności widocznej, wiersze w obu kierunkach (PD-GRID-007)")
    func block() {
        #expect(GridBlock.columns(from: 3, to: 1, order: [0, 3, 2, 1]) == [3, 2, 1])
        #expect(GridBlock.columns(from: 0, to: 2, order: [0, 3, 2, 1]) == [0, 3, 2])
        #expect(GridBlock.columns(from: 9, to: 2, order: [0, 2]) == [2])
        #expect(GridBlock.rows(from: 5, to: 2) == [2, 3, 4, 5])
    }

    func workspaceWithGrid(_ rows: [[OracleValue]]) async -> (Workspace, ResultTab, ResultGridModel) {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: FakeDriver()])
        let doc = ws.newDocument(.sql)
        let g = grid(rows)
        await g.fetchAll()
        let tab = ResultTab(title: "t", statementRange: 0..<0, grid: g)
        doc.results = [tab]
        doc.activeResultID = tab.id
        return (ws, tab, g)
    }

    @Test("Kopia bloku: tylko kolumny bloku; komenda grid.selectBlock i grid.selectColumn (PD-GRID-007)")
    func blockCopy() async throws {
        let (ws, tab, _) = await workspaceWithGrid([[.number("1"), .text("a"), .null], [.number("2"), .text("b"), .null], [.number("3"), .text("c"), .null]])
        try await ws.invoke("grid.selectBlock", CommandArguments(["fromRow": 3, "toRow": 2, "fromColumn": "name", "toColumn": "id"]))
        #expect(tab.selectedRows == [1, 2])
        #expect(tab.selectedColumns == [0, 1])
        let d = try #require(GridCommands.selection(ws))
        #expect(d.columns.map(\.name) == ["ID", "NAME"])
        #expect(d.rows.count == 2)
        try await ws.invoke("grid.selectColumn", CommandArguments(["column": "NAME"]))
        #expect(tab.selectedRows == [0, 1, 2])
        #expect(GridCommands.selection(ws)?.columns.map(\.name) == ["NAME"])
        await #expect(throws: CommandError.self) {
            try await ws.invoke("grid.selectBlock", CommandArguments(["fromRow": 1, "toRow": 9, "fromColumn": "ID"]))
        }
    }

    @Test("Rekord z komentarzami kolumn ze słownika karty (PD-GRID-010)")
    func recordFields() async {
        let (_, tab, _) = await workspaceWithGrid([[.number("7"), .null, .null]])
        tab.columnInfo = [1: ColumnDictionaryInfo(type: "VARCHAR2(20)", nullable: true, comment: "Nazwa działu", keys: [], values: [])]
        let f = tab.recordFields(row: 0, columns: [1, 0])
        #expect(f.map(\.name) == ["NAME", "ID"])
        #expect(f[0].comment == "Nazwa działu" && f[0].isNull)
        #expect(f[1].comment.isEmpty && f[1].value == "7")
        #expect(tab.recordFields(row: 5, columns: [0]).isEmpty)
    }

    @Test("Układ liczb komendą i w ustawieniach; Auto Format przełączany (PD-GRID-004, PD-LDE-001)")
    func settingsCommands() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: FakeDriver()])
        try await ws.invoke("grid.numberLayout", CommandArguments(["layout": "thousands"]))
        #expect(ws.settings.gridNumberLayout == .thousands)
        await #expect(throws: CommandError.self) { try await ws.invoke("grid.numberLayout", CommandArguments(["layout": "x"])) }
        try await ws.invoke("grid.largeDataAutoFormat")
        #expect(ws.settings.largeDataAutoFormat)
        // Dekodowanie starych ustawień: nowe pola z wartościami domyślnymi.
        let old = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(old.gridNumberLayout == .right && !old.largeDataAutoFormat && old.browserDropAction == .name && old.savedDatabaseSearches.isEmpty)
    }

    // MARK: Large Data Editor

    @Test("XML z wcięciami, elementy z tekstem w linii; Auto Format JSON/XML; podgląd HTML z CSP (PD-LDE-001)")
    func largeData() {
        let xml = LargeDataModel.prettyXML("<?xml version=\"1.0\"?><a><b>1</b><c x=\"2\"/><!-- k --><d><e>t</e></d></a>")
        #expect(xml == """
            <?xml version="1.0"?>
            <a>
              <b>1</b>
              <c x="2"/>
              <!-- k -->
              <d>
                <e>t</e>
              </d>
            </a>
            """)
        #expect(LargeDataModel.prettyXML("tekst") == nil)
        #expect(LargeDataModel.autoFormatted("{\"a\":1}", format: .json)?.contains("\n") == true)
        #expect(LargeDataModel.autoFormatted("<a><b/></a>", format: .xml) == "<a>\n  <b/>\n</a>")
        #expect(LargeDataModel.autoFormatted("zwykły", format: .text) == nil)
        let html = LargeDataModel.htmlPreviewDocument("<b>x</b>")
        #expect(html.contains("default-src 'none'") && html.hasSuffix("<b>x</b>"))
    }

    // MARK: Słownik wg wersji (PD-OB-026)

    @Test("Foldery wg wersji i widoków słownika: 19c, 21c, 23ai bez asercji, 26ai")
    func dictionaryFeatures() {
        let v19 = DictionaryFeatures(major: 19)
        #expect(!v19.supports(.domain) && !v19.supports(.annotation) && !v19.supports(.mleModule) && v19.supports(.table))
        #expect(!DictionaryFeatures(major: 21).availableTypes.contains(.assertion))
        let v23 = DictionaryFeatures(major: 23, minor: 4, views: ["ALL_MLE_MODULES", "ALL_MLE_ENVS", "ALL_DOMAINS", "ALL_ANNOTATIONS"])
        #expect(v23.supports(.annotation) && v23.supports(.domain) && !v23.supports(.assertion) && !v23.supports(.property))
        let v26 = DictionaryFeatures(major: 23, minor: 26, views: Set(DictionaryFeatures.probedViews))
        #expect(v26.availableTypes.contains(.assertion) && v26.availableTypes.contains(.annotation))
        // Bez sprawdzenia widoków: asercje z numeru wydania.
        #expect(!DictionaryFeatures(major: 23, minor: 4).supports(.assertion))
        #expect(DictionaryFeatures(major: 23, minor: 26).supports(.assertion))
        #expect(!DictionaryFeatures(major: 11).has12cColumns)
        // Kolejność folderów jak we wzorcu (adnotacje i asercje po domenach).
        let order = v26.availableTypes
        #expect(order.firstIndex(of: .domain)! < order.firstIndex(of: .annotation)! && order.firstIndex(of: .annotation)! < order.firstIndex(of: .assertion)!)
    }

    @Test("Zapytanie słownika z wariantem zapasowym: ORA-00904/00942 → następny wariant, inny błąd przerywa")
    func dictionaryFallback() async throws {
        let s = OldDictionarySession(missing: ["editionable": 904, "all_assertions": 942, "boom": 1])
        _ = try await DictionaryQuery.queryAll(["select editionable from all_objects", "select status from all_objects"], in: s)
        #expect(s.executed.withLock { $0 } == ["select editionable from all_objects", "select status from all_objects"])
        await #expect(throws: OracleError.self) { try await DictionaryQuery.queryAll(["select boom", "select ok"], in: s) }
        await #expect(throws: OracleError.self) { try await DictionaryQuery.queryAll(["select * from all_assertions"], in: s) }
        // Serwer 11g: bez sprawdzania widoków 23ai.
        let f = await DictionaryQuery.features(in: s)
        #expect(f.major == 11 && f.views == nil && !f.supports(.domain))
    }

    // MARK: Object Browser

    @Test("Zmiana nazwy: normalizacja, ALTER/RENAME, elementy tabeli; RENAME tylko we własnym schemacie (PD-OB-016)")
    func rename() throws {
        #expect(ObjectRename.normalizedName(" emp_new ") == "EMP_NEW")
        #expect(ObjectRename.normalizedName("\"Mixed Case\"") == "Mixed Case")
        #expect(ObjectRename.normalizedName("1abc") == nil && ObjectRename.normalizedName("a b") == nil)
        let t = DBObject(owner: "HR", name: "EMP", type: .table)
        #expect(try ObjectRename.statement(t, to: "EMP2", currentSchema: "X") == "ALTER TABLE HR.EMP RENAME TO EMP2")
        #expect(try ObjectRename.statement(DBObject(owner: "HR", name: "V", type: .view), to: "Mixed", currentSchema: "HR") == "RENAME V TO \"Mixed\"")
        #expect(throws: CommandError.self) { try ObjectRename.statement(DBObject(owner: "HR", name: "S", type: .sequence), to: "S2", currentSchema: "SCOTT") }
        #expect(throws: CommandError.self) { try ObjectRename.statement(DBObject(owner: "HR", name: "P", type: .package), to: "P2", currentSchema: "HR") }
        #expect(try ObjectRename.statement(DBObject(owner: "HR", name: "I", type: .index), to: "I2", currentSchema: "HR") == "ALTER INDEX HR.I RENAME TO I2")
        #expect(try ObjectRename.childStatement(table: t, kind: .column, name: "SAL", to: "SALARY") == "ALTER TABLE HR.EMP RENAME COLUMN SAL TO SALARY")
        #expect(try ObjectRename.childStatement(table: t, kind: .constraint, name: "EMP_PK", to: "EMP_ID_PK")
                == "ALTER TABLE HR.EMP RENAME CONSTRAINT EMP_PK TO EMP_ID_PK")
        #expect(throws: CommandError.self) { try ObjectRename.childStatement(table: t, kind: .dependency, name: "X", to: "Y") }
    }

    @Test("Duplikat: nazwa w nagłówku CREATE, nazwy więzów tabeli, END pakietu (PD-OB-016)")
    func duplicate() throws {
        let table = """
            CREATE TABLE "HR"."EMP"
               (\t"ID" NUMBER NOT NULL ENABLE,
            \t CONSTRAINT "EMP_PK" PRIMARY KEY ("ID") ENABLE,
            \t CONSTRAINT "SAL_CK" CHECK (sal > 0) ENABLE
               ) ;
            """
        let t = try ObjectRename.duplicateScript(table, object: DBObject(owner: "HR", name: "EMP", type: .table), newName: "EMP_COPY")
        #expect(t.hasPrefix("CREATE TABLE \"HR\".EMP_COPY"))
        #expect(t.contains("CONSTRAINT \"EMP_COPY_PK\"") && t.contains("CONSTRAINT \"EMP_COPY_SAL_CK\""))
        let pkg = "CREATE OR REPLACE PACKAGE emp_api AS\n  procedure p;\nEND emp_api;"
        let p = try ObjectRename.duplicateScript(pkg, object: DBObject(owner: "HR", name: "EMP_API", type: .package), newName: "EMP_API2")
        #expect(p == "CREATE OR REPLACE PACKAGE EMP_API2 AS\n  procedure p;\nEND EMP_API2;")
        let view = "CREATE OR REPLACE FORCE EDITIONABLE VIEW \"HR\".\"V\" (\"A\") AS select 1 a from dual"
        #expect(try ObjectRename.duplicateScript(view, object: DBObject(owner: "HR", name: "V", type: .view), newName: "V2")
                == "CREATE OR REPLACE FORCE EDITIONABLE VIEW \"HR\".V2 (\"A\") AS select 1 a from dual")
        #expect(throws: CommandError.self) { try ObjectRename.duplicateScript("select 1", object: DBObject(owner: "HR", name: "V", type: .view), newName: "V2") }
    }

    @Test("Upuszczenie obiektu: akcje wg typu, akcja na obszarze okien, nazwy folderu (PD-OB-010)")
    func drop() {
        #expect(BrowserDropAction.actions(for: .table).contains(.select) && !BrowserDropAction.actions(for: .table).contains(.call))
        #expect(BrowserDropAction.actions(for: .procedure).contains(.call) && !BrowserDropAction.actions(for: .procedure).contains(.columns))
        #expect(BrowserWorkspaceDrop.queryData.command(for: .package) == "ob.edit")
        #expect(BrowserWorkspaceDrop.queryData.command(for: .table) == "ob.queryData")
        #expect(BrowserWorkspaceDrop.ddl.command == "ob.ddl")
        #expect(BrowserDrop.namesList(["ID", "NAME", "Mixed"]) == "id, name, \"mixed\"")
        let o = DBObject(owner: "HR", name: "EMP", type: .table)
        #expect(BrowserDrop.name(o, currentSchema: "HR", qualified: false) == "emp")
        #expect(BrowserDrop.name(o, currentSchema: "SCOTT", qualified: false) == "hr.emp")
        #expect(BrowserDrop.name(o, currentSchema: "HR", qualified: true) == "hr.emp")
    }

    @Test("Adnotacja: skrypt ALTER … ANNOTATIONS (ADD …) dla tabeli, kolumny i domeny (PD-OB-002)")
    func annotationScript() {
        let s = Oracle23Dictionary.annotationScript(name: "UI_LABEL", owner: "HR", usages: [
            .init(objectType: "TABLE", object: "EMP", column: nil, value: "Pracownicy"),
            .init(objectType: "TABLE", object: "EMP", column: "SAL", value: "O'Brien"),
            .init(objectType: "VIEW", object: "V", column: nil, value: nil),
        ])
        #expect(s.contains("ALTER TABLE HR.EMP ANNOTATIONS (ADD UI_LABEL 'Pracownicy');"))
        #expect(s.contains("ALTER TABLE HR.EMP MODIFY (SAL ANNOTATIONS (ADD UI_LABEL 'O''Brien'));"))
        #expect(s.contains("ALTER VIEW HR.V ANNOTATIONS (ADD UI_LABEL);"))
        #expect(Oracle23Dictionary.annotationScript(name: "X", owner: "HR", usages: []).contains("--"))
    }

    // MARK: Edytor tabeli

    @Test("CREATE: składowanie, kolumna niewidoczna, indeks z kompresją, odwrócony, lokalny (PD-OED-001/002/004)")
    func createStorage() {
        var d = TableDefinition(owner: "HR", name: "T")
        var c = TableDefinition.Column(name: "ID", type: "NUMBER")
        c.invisible = true
        d.columns = [c, TableDefinition.Column(name: "N", type: "VARCHAR2(10 CHAR)")]
        d.storage.pctFree = "5"
        d.storage.initial = "64K"
        d.storage.logging = false
        d.storage.compression = .advanced
        var x = TableDefinition.Index(name: "T_IX", columns: ["N", "ID"])
        x.compression = "1"
        x.reverse = true
        x.local = true
        x.pctFree = "20"
        d.indexes = [x]
        let sql = TableDDL.statements(from: nil, to: d)
        #expect(sql[0].contains("ID NUMBER INVISIBLE"))
        #expect(sql[0].hasSuffix("PCTFREE 5 STORAGE (INITIAL 64K) NOLOGGING ROW STORE COMPRESS ADVANCED"))
        #expect(sql[1] == "CREATE INDEX HR.T_IX ON HR.T (N, ID) LOCAL PCTFREE 20 COMPRESS 1 REVERSE")
        x.compression = "ADVANCED LOW"
        x.reverse = false
        x.local = false
        x.pctFree = ""
        #expect(TableDDL.createIndex(x, table: d) == "CREATE INDEX HR.T_IX ON HR.T (N, ID) COMPRESS ADVANCED LOW")
    }

    @Test("CREATE: klaster, tabela zewnętrzna, tabela obiektowa (PD-OED-001/002)")
    func createOrganizations() {
        var d = TableDefinition(owner: "HR", name: "T")
        d.columns = [TableDefinition.Column(name: "DEPTNO", type: "NUMBER(2)")]
        d.cluster = "EMP_DEPT"
        d.clusterColumns = ["DEPTNO"]
        d.tablespace = "USERS"
        #expect(TableDDL.statements(from: nil, to: d)[0].hasSuffix("CLUSTER EMP_DEPT (DEPTNO)"))
        d.cluster = ""
        d.external = TableDefinition.External(directory: "data_dir", locations: ["a.csv", "b.csv"])
        d.external?.accessParameters = "FIELDS TERMINATED BY ','"
        d.keys = [TableDefinition.Key(name: "T_PK", kind: .primary, columns: ["DEPTNO"])]
        let ext = TableDDL.statements(from: nil, to: d)[0]
        #expect(ext.contains("ORGANIZATION EXTERNAL (\n  TYPE ORACLE_LOADER\n  DEFAULT DIRECTORY DATA_DIR"))
        #expect(ext.contains("ACCESS PARAMETERS (\n    FIELDS TERMINATED BY ','\n  )") && ext.contains("LOCATION ('a.csv', 'b.csv')"))
        #expect(ext.hasSuffix("REJECT LIMIT UNLIMITED") && !ext.contains("T_PK") && !ext.contains("TABLESPACE"))
        d.external = nil
        d.objectType = "HR.ADDRESS_T"
        #expect(TableDDL.statements(from: nil, to: d)[0].hasPrefix("CREATE TABLE HR.T OF HR.ADDRESS_T (\n  CONSTRAINT T_PK PRIMARY KEY (DEPTNO)\n)"))
    }

    @Test("ALTER: składowanie, przestrzeń, kolumna niewidoczna, kompresja indeksu (PD-OED-001/002/004)")
    func alterStorage() {
        var old = TableDefinition(owner: "HR", name: "T")
        old.originalName = "T"
        var c = TableDefinition.Column(name: "ID", type: "NUMBER")
        c.originalName = "ID"
        old.columns = [c]
        old.tablespace = "USERS"
        old.storage.pctFree = "10"
        var x = TableDefinition.Index(name: "T_IX", columns: ["ID"])
        x.originalName = "T_IX"
        old.indexes = [x]
        var new = old
        new.columns[0].invisible = true
        new.tablespace = "SYSAUX"
        new.storage.pctFree = "20"
        new.storage.next = "1M"
        new.storage.logging = false
        new.storage.compression = .basic
        new.indexes[0].compression = "1"
        let sql = TableDDL.statements(from: old, to: new)
        #expect(sql.contains("ALTER TABLE HR.T MODIFY (ID INVISIBLE)"))
        #expect(sql.contains("ALTER TABLE HR.T MOVE TABLESPACE SYSAUX UPDATE INDEXES"))
        #expect(sql.contains("ALTER TABLE HR.T PCTFREE 20"))
        #expect(sql.contains("ALTER TABLE HR.T STORAGE (NEXT 1M)"))
        #expect(sql.contains("ALTER TABLE HR.T NOLOGGING"))
        #expect(sql.contains("ALTER TABLE HR.T ROW STORE COMPRESS BASIC"))
        #expect(sql.contains("DROP INDEX HR.T_IX") && sql.contains("CREATE INDEX HR.T_IX ON HR.T (ID) COMPRESS 1"))
    }

    @Test("Recreate table: kopia, DROP, CREATE, przeniesienie kolumn (także przemianowanych), wyzwalacze i FK innych tabel (PD-OED-001)")
    func recreate() {
        var old = TableDefinition(owner: "HR", name: "T")
        old.originalName = "T"
        var a = TableDefinition.Column(name: "A", type: "NUMBER")
        a.originalName = "A"
        var b = TableDefinition.Column(name: "B", type: "VARCHAR2(10 CHAR)")
        b.originalName = "B"
        old.columns = [a, b]
        var new = old
        new.columns = [b, a]
        new.columns[0].name = "BB"
        new.columns.append(TableDefinition.Column(name: "C", type: "DATE"))
        new.storage.initial = "1M"
        new.recreate = true
        new.triggerDDL = ["CREATE OR REPLACE TRIGGER HR.T_BI BEFORE INSERT ON HR.T BEGIN NULL; END;"]
        new.referencingForeignKeys = ["ALTER TABLE HR.CHILD ADD CONSTRAINT C_FK FOREIGN KEY (A) REFERENCES HR.T (A)"]
        let sql = TableDDL.statements(from: old, to: new)
        #expect(sql[0] == "CREATE TABLE HR.PLK$T AS SELECT * FROM HR.T")
        #expect(sql[1] == "DROP TABLE HR.T CASCADE CONSTRAINTS")
        #expect(sql[2].hasPrefix("CREATE TABLE HR.T (\n  BB VARCHAR2(10 CHAR),\n  A NUMBER,\n  C DATE\n)") && sql[2].contains("INITIAL 1M"))
        #expect(sql.contains("INSERT INTO HR.T (BB, A) SELECT B, A FROM HR.PLK$T"))
        #expect(sql.firstIndex(of: new.triggerDDL[0])! > sql.firstIndex { $0.hasPrefix("INSERT") }!)
        #expect(sql.contains(new.referencingForeignKeys[0]))
        #expect(sql.last == "DROP TABLE HR.PLK$T PURGE")
    }

    // MARK: Find Database Objects

    @Test("Eksport wyników CSV z cudzysłowami; kryteria zapisane i odczytane, odporne na stare zapisy (PD-TOOL-001)")
    func search() async throws {
        let hits = [DatabaseSearchHit(object: DBObject(owner: "HR", name: "P", type: .packageBody), line: 12, text: "x := 'a, \"b\"';"),
                    DatabaseSearchHit(object: DBObject(owner: "HR", name: "EMP", type: .table), line: 0, text: "COLUMN SAL")]
        let csv = DatabaseSearch.exportText(hits, csv: true).split(separator: "\n").map(String.init)
        #expect(csv.count == 3)
        #expect(csv[1] == "HR,P,PACKAGE BODY,12,\"x := 'a, \"\"b\"\"';\"")
        #expect(csv[2] == "HR,EMP,TABLE,,COLUMN SAL")
        #expect(DatabaseSearch.exportText(hits, csv: false).contains("HR\tP\tPACKAGE BODY\t12\t"))
        let old = try JSONDecoder().decode(DatabaseSearchCriteria.self, from: Data(#"{"text":"emp","wholeWords":true}"#.utf8))
        #expect(old.text == "emp" && old.wholeWords && old.searchNames && !old.searchTableDefinitions)
        #expect(DatabaseSearch.selectableTypes.contains(.mleModule) && DatabaseSearch.selectableTypes.contains(.table))
        // Tekst dosłowny: najpierw INSTR (szybkie), potem REGEXP_LIKE; wyrażenie regularne — samo REGEXP_LIKE (D164).
        var c = DatabaseSearchCriteria(text: "commit")
        #expect(DatabaseSearch.match("text", c) == "case when nvl(instr(upper(text), upper(:t)), 0) = 0 then 0 when regexp_like(text, :p, :f) then 1 else 0 end = 1")
        c.caseSensitive = true
        #expect(DatabaseSearch.match("text", c) == "case when nvl(instr(text, :t), 0) = 0 then 0 when regexp_like(text, :p, :f) then 1 else 0 end = 1")
        c.regularExpression = true
        #expect(DatabaseSearch.match("text", c) == "regexp_like(text, :p, :f)")

        let ws = Workspace(secrets: MemorySecretStore(), drivers: [.instantClient: FakeDriver()])
        try await ws.invoke("tools.saveObjectSearch", CommandArguments(["saveAs": "pensje", "text": "sal", "regex": true, "owner": "hr, scott",
                                                                         "types": "package body, TABLE", "tableDefinitions": true]))
        let saved = try #require(ws.settings.savedDatabaseSearches.first)
        #expect(saved.name == "pensje" && saved.criteria.regularExpression && saved.criteria.owners == ["HR", "SCOTT"])
        #expect(saved.criteria.types == [.packageBody, .table] && saved.criteria.searchTableDefinitions)
        await #expect(throws: CommandError.self) {
            try await ws.invoke("tools.saveObjectSearch", CommandArguments(["saveAs": "x", "types": "NOPE"]))
        }
        try await ws.invoke("tools.deleteObjectSearch", CommandArguments(["saved": "pensje"]))
        #expect(ws.settings.savedDatabaseSearches.isEmpty)
    }
}
