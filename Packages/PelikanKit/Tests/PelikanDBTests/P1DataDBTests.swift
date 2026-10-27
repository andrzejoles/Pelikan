import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu: odpowiedzi na pytania i wybór daty.
@MainActor
final class P1UI: UIServices {
    var date: OracleTimestamp?
    var dateAsks: [(OracleTimestamp?, Bool)] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { 0 }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { [:] }
    func copyToClipboard(_ text: String, html: String?) {}
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { true }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { nil }
    func chooseDate(_ title: String, initial: OracleTimestamp?, withTime: Bool) async -> OracleTimestamp? {
        dateAsks.append((initial, withTime))
        return date
    }
}

@MainActor
@Suite("P1 dane na bazie testowej: siatka, edytor tabeli, Object Browser, wyszukiwanie", .enabled(if: TestDatabase.isAvailable), .serialized,
       .timeLimit(.minutes(5)))
struct P1DataDBTests {
    func workspace() throws -> (Workspace, P1UI) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = P1UI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, ui)
    }

    func run(_ statements: [String]) async throws {
        let s = try await TestDatabase.connect()
        for q in statements { _ = try? await s.execute(q) }
        await s.close()
    }

    func scalar(_ sql: String) async throws -> String? {
        let s = try await TestDatabase.connect()
        let v = try await s.scalar(sql)
        await s.close()
        return v
    }

    @Test("Rekord z komentarzami kolumn; kalendarz daty z zachowaniem godziny (PD-GRID-010, PD-GRID-005)")
    func recordAndDate() async throws {
        try await run(["drop table pelikan_p1_rec purge",
                       "create table pelikan_p1_rec (id number primary key, hired date, note varchar2(20))",
                       "comment on column pelikan_p1_rec.hired is 'Data zatrudnienia'",
                       "insert into pelikan_p1_rec values (1, to_date('2024-05-01 13:45:10', 'YYYY-MM-DD HH24:MI:SS'), 'x')", "commit"])
        let (ws, ui) = try workspace()
        let doc = ws.newDocument(.sql, text: "select r.id, r.hired, r.note, r.rowid from pelikan_p1_rec r")
        try await ws.invoke("sql.execute")
        let tab = try #require(doc.results.first { $0.id == doc.activeResultID })
        let grid = try #require(tab.grid)
        let r = try await ws.invoke("grid.recordView", CommandArguments(["row": 1]))
        guard case .array(let fields)? = r.value, case .object(let hired) = fields[1] else { Issue.record("brak pól"); return }
        #expect(hired["column"] == .string("HIRED") && hired["comment"] == .string("Data zatrudnienia") && hired["type"] == .string("DATE"))
        #expect(tab.recordFields(row: 0, columns: [1])[0].comment == "Data zatrudnienia")

        try await ws.invoke("grid.edit")
        tab.selectedRows = [0]
        tab.currentColumn = 1
        #expect(ws.isEnabled("grid.chooseDate"))
        try await ws.invoke("grid.chooseDate", CommandArguments(["value": "2024-02-29"]))
        #expect(grid.timestamp(row: 0, column: 1) == OracleTimestamp(year: 2024, month: 2, day: 29, hour: 13, minute: 45, second: 10))
        // Okno kalendarza: format DATE z godziną — wybór z czasem.
        ui.date = OracleTimestamp(year: 2023, month: 12, day: 24, hour: 8)
        try await ws.invoke("grid.chooseDate")
        #expect(ui.dateAsks.first?.0?.day == 29 && ui.dateAsks.first?.1 == true)
        #expect(grid.text(row: 0, column: 1) == "2023-12-24 08:00:00")
        try await ws.invoke("grid.post")
        try await ws.invoke("session.commit")
        #expect(try await scalar("select to_char(hired, 'YYYY-MM-DD HH24:MI') from pelikan_p1_rec") == "2023-12-24 08:00")
        tab.currentColumn = 2
        #expect(!ws.isEnabled("grid.chooseDate"))
        await ws.sessions.disconnectAll()
        try await run(["drop table pelikan_p1_rec purge"])
    }

    @Test("Foldery 26ai: adnotacje z użyciem i DDL, asercje z DDL; możliwości słownika (PD-OB-002, PD-OB-026)")
    func annotationsAssertions() async throws {
        try await run(["drop assertion pelikan_p1_ok", "drop table pelikan_p1_ann purge",
                       "create table pelikan_p1_ann (id number, sal number annotations (pelikan_p1_label 'Pensja')) annotations (pelikan_p1_label 'Tabela')"])
        let (ws, _) = try workspace()
        let m = try #require(ws.metadata())
        let f = try await m.dictionaryFeatures()
        #expect(f.major >= 23 && f.views?.contains("ALL_ANNOTATIONS") == true)
        let types = try await m.availableTypes()
        #expect(types.contains(.annotation) && types.contains(.domain) && types.contains(.mleModule))
        let schema = try await m.currentSchema()
        let ann = try await m.objects(.annotation, owner: schema)
        let label = try #require(ann.first { $0.name == "PELIKAN_P1_LABEL" })
        let usage = try await m.children(of: label)
        #expect(usage.map(\.name).sorted() == ["TABLE PELIKAN_P1_ANN", "TABLE PELIKAN_P1_ANN.SAL"])
        #expect(usage.allSatisfy { $0.kind == .usage && $0.object?.type == .table })
        let ddl = try await m.ddl(of: label)
        #expect(ddl.contains("ALTER TABLE \(schema).PELIKAN_P1_ANN MODIFY (SAL ANNOTATIONS (ADD PELIKAN_P1_LABEL 'Pensja'));"))
        // Asercje: tylko gdy serwer je ma i użytkownik ma uprawnienie (seed nadaje CREATE ASSERTION na 23.26+).
        if types.contains(.assertion) {
            let s = try await TestDatabase.connect()
            let created = (try? await s.execute("create assertion pelikan_p1_ok check (not exists (select 1 from pelikan_p1_ann where sal < 0))")) != nil
            await s.close()
            if created {
                m.refresh()
                let list = try await m.objects(.assertion, owner: schema)
                let a = try #require(list.first { $0.name == "PELIKAN_P1_OK" })
                #expect(a.isValid)
                let text = try await m.ddl(of: a)
                #expect(text.hasPrefix("CREATE ASSERTION") && text.contains("PELIKAN_P1_OK") && text.hasSuffix(";"))
                let props = try await m.properties(of: a)
                #expect(props.contains { $0.0 == "STATUS" && $0.1 == "ENABLED" })
            }
        }
        // Właściwości z wariantem zapasowym nadal działają na bieżącym serwerze.
        let props = try await m.properties(of: DBObject(owner: schema, name: "PELIKAN_P1_ANN", type: .table))
        #expect(props.contains { $0.0 == "EDITIONABLE" || $0.0 == "OBJECT_TYPE" })
        await ws.sessions.disconnectAll()
        try await run(["drop assertion pelikan_p1_ok", "drop table pelikan_p1_ann purge"])
    }

    @Test("Zmiana nazwy tabeli i kolumny, duplikat ze strukturą i danymi, wstawienie obiektu do edytora (PD-OB-016, PD-OB-010)")
    func renameDuplicate() async throws {
        try await run(["drop table pelikan_p1_ren purge", "drop table pelikan_p1_ren2 purge", "drop table pelikan_p1_copy purge",
                       "create table pelikan_p1_ren (id number constraint pelikan_p1_ren_pk primary key, nm varchar2(10))",
                       "insert into pelikan_p1_ren values (1, 'a')", "commit"])
        let (ws, _) = try workspace()
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let r = try await ws.invoke("ob.rename", CommandArguments(["object": .string("pelikan_p1_ren"), "type": "TABLE", "newName": "pelikan_p1_ren2"]))
        #expect(r.value == .string("ALTER TABLE \(schema).PELIKAN_P1_REN RENAME TO PELIKAN_P1_REN2"))
        try await ws.invoke("ob.renameChild", CommandArguments(["object": .string("pelikan_p1_ren2"), "type": "TABLE", "kind": "column",
                                                                 "name": "NM", "newName": "name_txt"]))
        #expect(try await scalar("select count(*) from user_tab_columns where table_name = 'PELIKAN_P1_REN2' and column_name = 'NAME_TXT'") == "1")
        // Duplikat: skrypt w nowym oknie (bez wykonania); po wykonaniu — kopia z więzem o nowej nazwie i z danymi.
        let d = try await ws.invoke("ob.duplicate", CommandArguments(["object": .string("pelikan_p1_ren2"), "type": "TABLE",
                                                                       "newName": "pelikan_p1_copy", "withData": .bool(true)]))
        guard case .string(let script)? = d.value else { Issue.record("brak skryptu"); return }
        #expect(script.contains("PELIKAN_P1_COPY") && script.contains("INSERT INTO \(schema).PELIKAN_P1_COPY SELECT * FROM \(schema).PELIKAN_P1_REN2"))
        #expect(ws.activeDocument?.text == script)
        let s = try await TestDatabase.connect()
        for stmt in script.components(separatedBy: ";").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !stmt.isEmpty {
            _ = try await s.execute(stmt)
        }
        try await s.commit()
        await s.close()
        #expect(try await scalar("select count(*) from pelikan_p1_copy") == "1")
        // Nazwa więzu bez nazwy tabeli źródłowej (PELIKAN_P1_REN_PK po zmianie nazwy tabeli) — z przedrostkiem nazwy kopii.
        #expect(try await scalar("select constraint_name from user_constraints where table_name = 'PELIKAN_P1_COPY' and constraint_type = 'P'")
                == "PELIKAN_P1_COPY_PELIKAN_P1_REN_PK")
        // Wstawienie do edytora: lista kolumn i SELECT.
        let editor = ws.newDocument(.sql)
        _ = editor
        try await ws.invoke("ob.dropText", CommandArguments(["object": .string("pelikan_p1_ren2"), "type": "TABLE", "action": "columns"]))
        #expect(ws.activeDocument?.text == "id, name_txt")
        let sel = try await ws.invoke("ob.dropText", CommandArguments(["object": .string("pelikan_p1_ren2"), "type": "TABLE", "action": "select"]))
        #expect(sel.value?.stringValue?.lowercased().contains("from") == true)
        await ws.sessions.disconnectAll()
        try await run(["drop table pelikan_p1_ren2 purge", "drop table pelikan_p1_copy purge"])
    }

    @Test("Edytor tabeli: składowanie, kolumna niewidoczna, kompresja i odwrócony indeks — zapis i odczyt (PD-OED-001/002/004)")
    func storageRoundTrip() async throws {
        try await run(["drop table pelikan_p1_st purge"])
        let (ws, _) = try workspace()
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        var d = TableDefinition(owner: schema, name: "PELIKAN_P1_ST")
        var hidden = TableDefinition.Column(name: "SECRET", type: "VARCHAR2(10 CHAR)")
        hidden.invisible = true
        d.columns = [TableDefinition.Column(name: "ID", type: "NUMBER"), TableDefinition.Column(name: "NM", type: "VARCHAR2(20 CHAR)"), hidden]
        d.storage.pctFree = "15"
        d.storage.compression = .basic
        var ix = TableDefinition.Index(name: "PELIKAN_P1_ST_IX", columns: ["NM", "ID"])
        ix.compression = "1"
        var rev = TableDefinition.Index(name: "PELIKAN_P1_ST_RX", columns: ["ID"])
        rev.reverse = true
        d.indexes = [ix, rev]
        let r = try await TableDDL.apply(from: nil, to: d, in: ws, connectionID: m.connectionID)
        #expect(r.error == nil, "\(r.failed ?? ""): \(r.error ?? "")")
        let loaded = try await TableDDL.load(owner: schema, name: "PELIKAN_P1_ST", metadata: m)
        #expect(loaded.storage.pctFree == "15" && loaded.storage.compression == .basic && loaded.storage.logging)
        #expect(loaded.columns.map(\.name) == ["ID", "NM", "SECRET"] && loaded.columns[2].invisible && !loaded.columns[0].invisible)
        #expect(loaded.indexes.first { $0.name == "PELIKAN_P1_ST_IX" }?.compression == "1")
        #expect(loaded.indexes.first { $0.name == "PELIKAN_P1_ST_RX" }?.reverse == true)
        // Bez zmian po wczytaniu — brak poleceń; zmiana: widoczna kolumna, PCTFREE, NOLOGGING, bez kompresji indeksu.
        #expect(TableDDL.statements(from: loaded, to: loaded).isEmpty)
        var changed = loaded
        changed.columns[2].invisible = false
        changed.storage.pctFree = "25"
        changed.storage.logging = false
        changed.indexes = changed.indexes.map { var x = $0; x.compression = ""; return x }
        let r2 = try await TableDDL.apply(from: loaded, to: changed, in: ws, connectionID: m.connectionID)
        #expect(r2.error == nil, "\(r2.failed ?? ""): \(r2.error ?? "")")
        let again = try await TableDDL.load(owner: schema, name: "PELIKAN_P1_ST", metadata: m)
        #expect(!again.columns[2].invisible && again.storage.pctFree == "25" && !again.storage.logging)
        #expect(again.indexes.allSatisfy { $0.compression.isEmpty })
        await ws.sessions.disconnectAll()
        try await run(["drop table pelikan_p1_st purge"])
    }

    @Test("Recreate table: dane (także kolumny INVISIBLE), wyzwalacz i klucz obcy innej tabeli zachowane; zmiana kolejności kolumn (PD-OED-001)")
    func recreateTable() async throws {
        try await run(["drop table pelikan_p1_child purge", "drop table pelikan_p1_rc purge",
                       "create table pelikan_p1_rc (id number constraint pelikan_p1_rc_pk primary key, a varchar2(10), b number, h number invisible)",
                       "create table pelikan_p1_child (id number, rc_id number constraint pelikan_p1_child_fk references pelikan_p1_rc)",
                       "create or replace trigger pelikan_p1_rc_bi before insert on pelikan_p1_rc for each row begin :new.b := nvl(:new.b, 0); end;",
                       "insert into pelikan_p1_rc (id, a, h) values (1, 'x', 7)", "insert into pelikan_p1_rc (id, a, b) values (2, 'y', 5)",
                       "insert into pelikan_p1_child values (1, 2)", "commit"])
        let (ws, _) = try workspace()
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let old = try await TableDDL.load(owner: schema, name: "PELIKAN_P1_RC", metadata: m)
        #expect(old.referencingForeignKeys.count == 1 && old.referencingForeignKeys[0].contains("PELIKAN_P1_CHILD_FK"))
        var new = old
        #expect(old.columns.map(\.name) == ["ID", "A", "B", "H"] && old.columns[3].invisible)
        new.columns = [old.columns[0], old.columns[2], old.columns[1], old.columns[3]]
        new.columns[2].name = "A_TXT"
        new.storage.initial = "128K"
        new.recreate = true
        let r = try await TableDDL.apply(from: old, to: new, in: ws, connectionID: m.connectionID)
        #expect(r.error == nil, "\(r.failed ?? ""): \(r.error ?? "")")
        #expect(try await scalar("select listagg(column_name, ',') within group (order by column_id) from user_tab_columns where table_name = 'PELIKAN_P1_RC' and column_id is not null")
                == "ID,B,A_TXT")
        #expect(try await scalar("select a_txt || b || '/' || h from pelikan_p1_rc where id = 1") == "x0/7")
        #expect(try await scalar("select hidden_column from user_tab_cols where table_name = 'PELIKAN_P1_RC' and column_name = 'H'") == "YES")
        #expect(try await scalar("select status from user_triggers where trigger_name = 'PELIKAN_P1_RC_BI'") == "ENABLED")
        #expect(try await scalar("select count(*) from user_constraints where constraint_name = 'PELIKAN_P1_CHILD_FK'") == "1")
        #expect(try await scalar("select count(*) from user_tables where table_name = 'PLK$PELIKAN_P1_RC'") == "0")
        await ws.sessions.disconnectAll()
        try await run(["drop table pelikan_p1_child purge", "drop table pelikan_p1_rc purge"])
    }

    @Test("Tabela zewnętrzna i obiektowa: utworzenie i odczyt; kolumny klucza obcego do DEPT (PD-OED-001/002)")
    func externalObjectTables() async throws {
        try await run(["drop table pelikan_p1_ext purge", "drop table pelikan_p1_obj purge", "drop type pelikan_p1_addr_t",
                       "create type pelikan_p1_addr_t as object (street varchar2(40), city varchar2(30))"])
        let (ws, _) = try workspace()
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        var e = TableDefinition(owner: schema, name: "PELIKAN_P1_EXT")
        e.columns = [TableDefinition.Column(name: "ID", type: "NUMBER"), TableDefinition.Column(name: "NM", type: "VARCHAR2(20)")]
        e.external = TableDefinition.External(directory: "DATA_PUMP_DIR", locations: ["pelikan_p1.csv"])
        e.external?.accessParameters = "RECORDS DELIMITED BY NEWLINE FIELDS TERMINATED BY ','"
        let r = try await TableDDL.apply(from: nil, to: e, in: ws, connectionID: m.connectionID)
        #expect(r.error == nil, "\(r.failed ?? ""): \(r.error ?? "")")
        let le = try await TableDDL.load(owner: schema, name: "PELIKAN_P1_EXT", metadata: m)
        #expect(le.external?.driver == "ORACLE_LOADER" && le.external?.directory == "DATA_PUMP_DIR" && le.external?.locations == ["pelikan_p1.csv"])
        #expect(le.external?.accessParameters.contains("FIELDS TERMINATED BY") == true)

        var o = TableDefinition(owner: schema, name: "PELIKAN_P1_OBJ")
        o.objectType = "PELIKAN_P1_ADDR_T"
        let r2 = try await TableDDL.apply(from: nil, to: o, in: ws, connectionID: m.connectionID)
        #expect(r2.error == nil, "\(r2.failed ?? ""): \(r2.error ?? "")")
        let lo = try await TableDDL.load(owner: schema, name: "PELIKAN_P1_OBJ", metadata: m)
        #expect(lo.objectType.hasSuffix("PELIKAN_P1_ADDR_T") && lo.columns.map(\.name) == ["STREET", "CITY"])

        var t = TableDefinition(owner: schema, name: "PELIKAN_P1_NEW")
        t.columns = [TableDefinition.Column(name: "ID", type: "NUMBER")]
        let (cols, key) = try await TableDDL.foreignKeyColumns(for: t, referencing: "dept", metadata: m)
        #expect(cols.map(\.name) == ["DEPTNO"] && cols[0].type.hasPrefix("NUMBER"))
        #expect(key.kind == .foreign && key.referencedTable == "DEPT" && key.referencedColumns == ["DEPTNO"])
        await #expect(throws: CommandError.self) { try await TableDDL.foreignKeyColumns(for: t, referencing: "pelikan_p1_obj", metadata: m) }
        await ws.sessions.disconnectAll()
        try await run(["drop table pelikan_p1_ext purge", "drop table pelikan_p1_obj purge", "drop type pelikan_p1_addr_t"])
    }

    @Test("Find Database Objects: definicje tabel (kolumny, komentarze, CHECK) i typ TABLE (PD-TOOL-001)")
    func searchTableDefinitions() async throws {
        try await run(["drop view pelikan_p1_find_v", "drop table pelikan_p1_find purge",
                       "create table pelikan_p1_find (zzq_amount number constraint pelikan_p1_find_ck check (zzq_amount > 0), note varchar2(10))",
                       "comment on column pelikan_p1_find.note is 'opis zzq'", "comment on table pelikan_p1_find is 'tabela zzq'",
                       "create or replace view pelikan_p1_find_v (zzq_v) as select note from pelikan_p1_find",
                       "comment on column pelikan_p1_find_v.zzq_v is 'widok zzq'"])
        let (ws, _) = try workspace()
        let m = try #require(ws.metadata())
        var c = DatabaseSearchCriteria(text: "zzq")
        c.searchNames = false
        #expect(try await DatabaseSearch.search(c, metadata: m).isEmpty)
        c.searchTableDefinitions = true
        let hits = try await DatabaseSearch.search(c, metadata: m)
        let texts = Set(hits.filter { $0.object.name == "PELIKAN_P1_FIND" }.map(\.text))
        #expect(texts.contains("COLUMN ZZQ_AMOUNT") && texts.contains("COMMENT NOTE: opis zzq") && texts.contains("COMMENT: tabela zzq"))
        #expect(texts.contains { $0.hasPrefix("CHECK PELIKAN_P1_FIND_CK") })
        // Kolumny i komentarze widoku to nie definicja tabeli (filtr po ALL_TABLES zamiast półzłączenia — D165).
        #expect(!hits.contains { $0.object.name == "PELIKAN_P1_FIND_V" })
        c.nameFilter = "pelikan_p1_find_v"
        #expect(try await DatabaseSearch.search(c, metadata: m).isEmpty)
        c.nameFilter = ""
        let r = try await ws.invoke("tools.findObjects", CommandArguments(["text": "zzq", "types": "TABLE", "names": .bool(false)]))
        guard case .array(let list)? = r.value else { Issue.record("brak wyników"); return }
        #expect(list.count == hits.count)
        await ws.sessions.disconnectAll()
        try await run(["drop view pelikan_p1_find_v", "drop table pelikan_p1_find purge"])
    }
}
