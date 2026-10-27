import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Narzędzia danych na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(5)))
struct DataTransferDBTests {
    func workspace() throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString), environment: .test)
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    var schema: String { TestDatabase.config!.user.uppercased() }

    /// Tabele nadrzędna i podrzędna z kluczem obcym, datą, CLOB-em i RAW.
    func createTables(_ s: any DatabaseSession) async throws {
        for t in ["pelikan_dt_d", "pelikan_dt_m"] { _ = try? await s.execute("drop table \(t) purge") }
        _ = try await s.execute("create table pelikan_dt_m (id number primary key, nazwa varchar2(50), utw date, opis clob, sumy raw(8))")
        _ = try await s.execute("create table pelikan_dt_d (id number primary key, m_id number references pelikan_dt_m, kwota number(10,2))")
        _ = try await s.execute("create index pelikan_dt_d_m on pelikan_dt_d (m_id)")
        _ = try await s.execute("insert into pelikan_dt_m values (1, 'Żółw ''A''', date '2024-05-06', 'długi tekst', hextoraw('0A0B'))")
        _ = try await s.execute("insert into pelikan_dt_m values (2, null, null, null, null)")
        _ = try await s.execute("insert into pelikan_dt_d values (10, 1, 12.5)")
        _ = try await s.execute("insert into pelikan_dt_d values (11, 2, -3)")
        try await s.commit()
    }

    func snapshot(_ s: any DatabaseSession) async throws -> [String] {
        let (_, m) = try await s.queryAll("select id || '|' || nazwa || '|' || to_char(utw, 'YYYY-MM-DD') || '|' || dbms_lob.substr(opis, 100) || '|' || rawtohex(sumy) from pelikan_dt_m order by id")
        let (_, d) = try await s.queryAll("select id || '|' || m_id || '|' || to_char(kwota, 'FM990.00') from pelikan_dt_d order by id")
        return (m + d).map { $0.first?.displayText ?? "" }
    }

    @Test("SQL Inserts: kolejność wg FK, drop/create z indeksem, wyłączone wyzwalacze i FK; import skryptem w oknie poleceń odtwarza dane")
    func sqlInserts() async throws {
        let (ws, conn) = try workspace()
        let s = try await DataTransferCommands.session(ws)
        try await createTables(s)
        let before = try await snapshot(s)
        #expect(try await TableTransfer.orderByForeignKeys(["PELIKAN_DT_D", "PELIKAN_DT_M"], owner: schema, in: s) == ["PELIKAN_DT_M", "PELIKAN_DT_D"])
        var o = TableExportOptions()
        o.drop = true
        o.create = true
        o.disableTriggers = true
        o.disableForeignKeys = true
        o.commitEvery = 1
        let script = try await TableTransfer.sqlInserts(["PELIKAN_DT_D", "PELIKAN_DT_M"], owner: schema, options: o, in: s)
        #expect(script.range(of: "drop table PELIKAN_DT_D")!.lowerBound < script.range(of: "drop table PELIKAN_DT_M")!.lowerBound)
        #expect(script.contains("PELIKAN_DT_D_M") && script.contains("TO_CLOB('długi tekst')") && script.contains("HEXTORAW('0A0B')"))
        let (doc, errors) = try await TableTransfer.importSQLScript(script, baseDirectory: nil, connectionID: conn, in: ws)
        #expect(errors == 0, "\(doc.console.filter { $0.kind == .error }.map(\.text))")
        #expect(try await snapshot(s) == before)
        let (_, idx) = try await s.queryAll("select index_name from user_indexes where table_name = 'PELIKAN_DT_D' and index_name = 'PELIKAN_DT_D_M'")
        #expect(idx.count == 1)
        await ws.sessions.disconnectAll()
    }

    @Test("Format własny: eksport, usunięcie tabel, import z utworzeniem tabel; wybór tabel; czyszczenie przed importem")
    func native() async throws {
        let (ws, _) = try workspace()
        let s = try await DataTransferCommands.session(ws)
        try await createTables(s)
        let before = try await snapshot(s)
        let data = try await TableTransfer.exportNative(["PELIKAN_DT_M", "PELIKAN_DT_D"], owner: schema, in: s)
        let file = try TableTransfer.unpackNative(data)
        #expect(file.tables.map(\.name) == ["PELIKAN_DT_M", "PELIKAN_DT_D"])
        for t in ["pelikan_dt_d", "pelikan_dt_m"] { _ = try await s.execute("drop table \(t) purge") }
        var o = TableImportOptions()
        o.create = true
        let r = try await TableTransfer.importNative(file, tables: ["PELIKAN_DT_M", "PELIKAN_DT_D"], intoOwner: schema, options: o, in: s)
        #expect(r.errors.isEmpty && r.inserted == 4, "\(r.errors)")
        #expect(try await snapshot(s) == before)
        o.create = false
        o.delete = true
        let r2 = try await TableTransfer.importNative(file, tables: ["PELIKAN_DT_M", "PELIKAN_DT_D"], intoOwner: schema, options: o, in: s)
        #expect(r2.errors.isEmpty && r2.inserted == 4)
        #expect(try await snapshot(s) == before)
        await ws.sessions.disconnectAll()
    }

    @Test("Kolumny wirtualne, identity ALWAYS, INVISIBLE i TIMESTAMP WITH TIME ZONE: format własny, SQL Inserts, przenoszenie i porównanie (R7-03, R7-05)")
    func specialColumns() async throws {
        let (ws, conn) = try workspace()
        let s = try await DataTransferCommands.session(ws)
        _ = try? await s.execute("drop table pelikan_dt_v purge")
        _ = try await s.execute("""
            create table pelikan_dt_v (id number generated always as identity (start with 100 increment by 10) primary key, v number,
              vv number generated always as (v * 2) virtual, inv varchar2(10) invisible, tz timestamp(6) with time zone)
            """)
        _ = try await s.execute("insert into pelikan_dt_v (v, inv, tz) values (5, 'ukryta', timestamp '2024-01-01 10:00:00.5 +05:00')")
        _ = try await s.execute("insert into pelikan_dt_v (v) values (7)")
        try await s.commit()
        let snap = """
            select listagg(id || '|' || v || '|' || vv || '|' || inv || '|' || to_char(tz, 'YYYY-MM-DD HH24:MI:SS.FF1 TZH:TZM'), ';')
                   within group (order by id) from pelikan_dt_v
            """
        let before = try await s.scalar(snap)
        #expect(before == "100|5|10|ukryta|2024-01-01 10:00:00.5 +05:00;110|7|14||")
        // Format własny: eksport z DDL, usunięcie, import z utworzeniem w sesji o innej strefie czasowej.
        let file = try TableTransfer.unpackNative(try await TableTransfer.exportNative(["PELIKAN_DT_V"], owner: schema, in: s))
        #expect(file.tables[0].columns.map(\.name) == ["ID", "V", "TZ", "INV"])
        _ = try await s.execute("drop table pelikan_dt_v purge")
        _ = try await s.execute("alter session set time_zone = '-03:00'")
        var o = TableImportOptions()
        o.create = true
        let r = try await TableTransfer.importNative(file, tables: ["PELIKAN_DT_V"], intoOwner: schema, options: o, in: s)
        #expect(r.errors.isEmpty && r.inserted == 2, "\(r.errors)")
        #expect(try await s.scalar(snap) == before)
        #expect(try await s.scalar("select generation_type from user_tab_identity_cols where table_name = 'PELIKAN_DT_V'") == "ALWAYS")
        _ = try await s.execute("insert into pelikan_dt_v (v) values (9)")
        #expect((Int(try await s.scalar("select id from pelikan_dt_v where v = 9") ?? "") ?? 0) > 110)
        _ = try await s.execute("delete from pelikan_dt_v where v = 9")
        try await s.commit()
        // SQL Inserts: bez kolumny wirtualnej, z INVISIBLE; identity ALWAYS przełączane na czas wstawiania.
        var e = TableExportOptions()
        e.delete = true
        let script = try await TableTransfer.sqlInserts(["PELIKAN_DT_V"], owner: schema, options: e, in: s)
        #expect(!script.contains("VV") && script.contains("INV") && script.contains("generated by default as identity"))
        let (doc, errors) = try await TableTransfer.importSQLScript(script, baseDirectory: nil, connectionID: conn, in: ws)
        #expect(errors == 0, "\(doc.console.filter { $0.kind == .error }.map(\.text))")
        #expect(try await s.scalar(snap) == before)
        #expect(try await s.scalar("select generation_type from user_tab_identity_cols where table_name = 'PELIKAN_DT_V'") == "ALWAYS")
        // Przenoszenie: kolumny celu bez wirtualnej i identity ALWAYS; porównanie bez kolumny wirtualnej.
        var job = DataTransferJob()
        job.targetOwner = schema
        job.targetTable = "PELIKAN_DT_V"
        #expect(try await DataTransferRunner.targetColumns(job, in: s) == ["V", "TZ", "INV"])
        let diff = try await TableDataCompare.compare(table: "PELIKAN_DT_V", sourceOwner: schema, source: s, targetOwner: schema, target: s)
        #expect(diff.isEmpty && !diff.columns.contains("VV"))
        _ = try await s.execute("drop table pelikan_dt_v purge")
        await ws.sessions.disconnectAll()
    }

    @Test("Format własny i Kopiowanie schematu: LOB ponad limit odczytu przerywa eksport tabeli błędem zamiast obcinać (R7-03)")
    func nativeLOBOverLimit() async throws {
        let s = try await TestDatabase.connect()
        _ = try? await s.execute("drop table pelikan_dt_big purge")
        _ = try await s.execute("create table pelikan_dt_big (id number primary key, b blob)")
        _ = try await s.execute("""
            declare b blob; begin
              dbms_lob.createtemporary(b, true);
              for i in 1..306 loop dbms_lob.writeappend(b, 32767, utl_raw.copies(hextoraw('AB'), 32767)); end loop;
              insert into pelikan_dt_big values (1, b);
              commit;
            end;
            """)
        await #expect(throws: CommandError.self) {
            _ = try await TableTransfer.exportNative(["PELIKAN_DT_BIG"], owner: schema, includeDDL: false, in: s)
        }
        _ = try await s.execute("drop table pelikan_dt_big purge")
        await s.close()
    }

    @Test("Data Pump: eksport tabel do DATA_PUMP_DIR i import z TABLE_EXISTS_ACTION=REPLACE")
    func dataPump() async throws {
        let (ws, _) = try workspace()
        let s = try await DataTransferCommands.session(ws)
        try await createTables(s)
        let before = try await snapshot(s)
        let e = try await DataPump.export(schema: schema, tables: ["PELIKAN_DT_M", "PELIKAN_DT_D"], dumpFile: "pelikan_dt.dmp", in: s)
        #expect(e.state == "COMPLETED", "\(e.log)")
        _ = try await s.execute("delete from pelikan_dt_d")
        try await s.commit()
        let i = try await DataPump.importDump(dumpFile: "pelikan_dt.dmp", tables: ["PELIKAN_DT_M", "PELIKAN_DT_D"], fromSchema: schema, toSchema: schema,
                                              tableExists: "REPLACE", in: s)
        #expect(i.state == "COMPLETED", "\(i.log)")
        #expect(try await snapshot(s) == before)
        await ws.sessions.disconnectAll()
    }

    @Test("Import tekstu: filtr, duplikaty pomijane i nadpisywane, błędne wiersze w raporcie, utworzenie tabeli z pliku")
    func textImport() async throws {
        let (ws, _) = try workspace()
        let s = try await DataTransferCommands.session(ws)
        try await createTables(s)
        let csv = "id;nazwa;kwota\n1;pomijany;5\n3;\"Nowy; wiersz\";100,5\n4;filtr;0\nx;błąd;1\n"
        let f = TextImport.detect(csv)
        let (h, rows) = TextImport.parse(csv, f)
        var t = ImportTarget(owner: schema, table: "PELIKAN_DT_M", mappings: try await TextImport.defaultMappings(owner: schema, table: "PELIKAN_DT_M", fieldNames: h, in: s))
        #expect(t.mappings.first { $0.column == "ID" }?.field == 0 && t.mappings.first { $0.column == "UTW" }?.field == nil)
        t.filter = ":KWOTA > 1"
        t.duplicates = .ignore
        t.mappings = t.mappings.map { var m = $0; if m.column == "NAZWA" { m.function = "upper(#)" }; return m }
        let r = try await TextImport.run(rows, fieldNames: h, target: t, in: s)
        #expect(r.inserted == 1 && r.skipped == 2 && r.errors.count == 1, "\(r)")
        #expect(try await s.scalar("select nazwa from pelikan_dt_m where id = 3") == "NOWY; WIERSZ")
        t.duplicates = .overwrite
        t.filter = ""
        let r2 = try await TextImport.run([["1", "nadpisany", "5"]], fieldNames: h, target: t, in: s)
        #expect(r2.updated == 1 && r2.inserted == 0)
        #expect(try await s.scalar("select nazwa from pelikan_dt_m where id = 1") == "NADPISANY")
        // Nowa tabela z pliku.
        _ = try? await s.execute("drop table pelikan_dt_csv purge")
        let csv2 = "lp,data,opis\n1,2024-03-01,alfa\n2,2024-03-02,beta\n"
        let (h2, rows2) = TextImport.parse(csv2, TextImport.detect(csv2))
        let (create, maps) = TextImport.createTable(owner: schema, table: "PELIKAN_DT_CSV", fieldNames: h2, rows: rows2)
        _ = try await s.execute(create)
        let r3 = try await TextImport.run(rows2, fieldNames: h2, target: ImportTarget(owner: schema, table: "PELIKAN_DT_CSV", mappings: maps), in: s)
        #expect(r3.inserted == 2 && r3.errors.isEmpty, "\(r3)")
        #expect(try await s.scalar("select to_char(max(data), 'YYYY-MM-DD') from pelikan_dt_csv") == "2024-03-02")
        _ = try await s.execute("drop table pelikan_dt_csv purge")
        await ws.sessions.disconnectAll()
    }

    @Test("Generator: domyślna definicja z kolumn, dane master/detail zapisane do bazy z kluczami obcymi")
    func generatorInsert() async throws {
        let (ws, _) = try workspace()
        let s = try await DataTransferCommands.session(ws)
        try await createTables(s)
        _ = try await s.execute("delete from pelikan_dt_d")
        _ = try await s.execute("delete from pelikan_dt_m")
        var m = try await DataGenerator.defaultTable(owner: schema, table: "PELIKAN_DT_M", in: s)
        #expect(m.fields.first?.definition == "Sequence(1)")
        m.fields = m.fields.filter { !["OPIS", "SUMY"].contains($0.name) }
        m.minRecords = 5
        m.maxRecords = 5
        var d = try await DataGenerator.defaultTable(owner: schema, table: "PELIKAN_DT_D", in: s)
        d.parent = "PELIKAN_DT_M"
        d.minRecords = 2
        d.maxRecords = 2
        d.fields = d.fields.map { var f = $0; if f.name == "M_ID" { f.definition = "Parent(ID)" }; if f.name == "ID" { f.definition = "Sequence(100)" }; return f }
        var g = DataGenerator(seed: 7, session: s)
        let data = try await g.generate([m, d])
        let r = try await DataGenerator.insert(data, tables: [m, d], owner: schema, in: s)
        #expect(r.errors.isEmpty && r.inserted == 15, "\(r.errors)")
        #expect(try await s.scalar("select count(*) from pelikan_dt_d d join pelikan_dt_m m on m.id = d.m_id") == "10")
        // List(select …) i SQL(…) z bazy.
        var g2 = DataGenerator(seed: 1, session: s)
        let t = GeneratorTable(name: "X", minRecords: 3, maxRecords: 3, fields: [
            .init(name: "A", type: "VARCHAR2", definition: "List(select dname from dept)"),
            .init(name: "B", type: "VARCHAR2", definition: "SQL(lower(:A))"),
        ])
        let x = try await g2.generate([t])["X"]!
        #expect(x.allSatisfy { $0["B"] == $0["A"]?.lowercased() && !($0["A"] ?? "").isEmpty })
        await ws.sessions.disconnectAll()
    }

    @Test("Przenoszenie danych i import formatu własnego: BLOB 5000 B i CLOB 40 000 znaków bez utraty (zmienne wiązane, nie NULL)")
    func largeLOBs() async throws {
        let src = try await TestDatabase.connect()
        let dst = try await TestDatabase.connect()
        defer { Task { for t in ["pelikan_lob_s", "pelikan_lob_t"] { _ = try? await src.execute("drop table \(t) purge") }; await src.close(); await dst.close() } }
        for t in ["pelikan_lob_s", "pelikan_lob_t"] { _ = try? await src.execute("drop table \(t) purge") }
        _ = try await src.execute("create table pelikan_lob_s (id number primary key, b blob, c clob)")
        _ = try await src.execute("create table pelikan_lob_t (id number primary key, b blob, c clob)")
        _ = try await src.execute("""
            declare b blob; c clob; begin
              dbms_lob.createtemporary(b, true); dbms_lob.createtemporary(c, true);
              for i in 1..5 loop dbms_lob.writeappend(b, 1000, utl_raw.copies(hextoraw('AB'), 1000)); end loop;
              for i in 1..10 loop dbms_lob.writeappend(c, 4000, rpad('x', 4000, 'y')); end loop;
              insert into pelikan_lob_s values (1, b, c);
              commit;
            end;
            """)
        let same = """
            select count(*) from pelikan_lob_s s join pelikan_lob_t t on t.id = s.id
             where dbms_lob.compare(s.b, t.b) = 0 and dbms_lob.compare(s.c, t.c) = 0 and dbms_lob.getlength(t.b) = 5000
            """
        var job = DataTransferJob()
        job.sourceOwner = schema; job.sourceTable = "PELIKAN_LOB_S"; job.targetOwner = schema; job.targetTable = "PELIKAN_LOB_T"
        job.mappings = ["ID", "B", "C"].map { TransferColumnMapping(target: $0, source: $0) }
        let r = try await DataTransferRunner.run(job, source: src, target: dst)
        #expect(r.inserted == 1 && r.errors.isEmpty, "\(r.errors)")
        #expect(try await src.scalar(same) == "1")
        // Format własny: eksport tabeli źródłowej, import do docelowej (po TRUNCATE).
        var file = try TableTransfer.unpackNative(try await TableTransfer.exportNative(["PELIKAN_LOB_S"], owner: schema, includeDDL: false, in: src))
        file.tables[0].name = "PELIKAN_LOB_T"
        var o = TableImportOptions()
        o.truncate = true
        let imp = try await TableTransfer.importNative(file, tables: ["PELIKAN_LOB_T"], intoOwner: schema, options: o, in: dst)
        #expect(imp.inserted == 1 && imp.errors.isEmpty, "\(imp.errors)")
        #expect(try await src.scalar(same) == "1")
    }

    @Test("Porównanie danych z drugim schematem: wstawienia, zmiany, usunięcia; skrypt i bezpośrednia aktualizacja wyrównują dane")
    func compareData() async throws {
        let c = TestDatabase.config!
        let (ws, _) = try workspace()
        let s = try await DataTransferCommands.session(ws)
        try await createTables(s)
        let sys = try await ODPISession.connect(target: ConnectionTarget(user: "SYSTEM", connectString: c.connectString),
                                                credentials: Credentials(password: c.systemPassword), options: ConnectOptions())
        _ = try? await sys.execute("drop user pelikan_dc cascade")
        _ = try await sys.execute("create user pelikan_dc no authentication quota 10m on users")
        _ = try await sys.execute("create table pelikan_dc.pelikan_dt_m (id number primary key, nazwa varchar2(50), utw date, opis clob, sumy raw(8))")
        _ = try await sys.execute("insert into pelikan_dc.pelikan_dt_m values (1, 'inna', date '2024-05-06', 'długi tekst', hextoraw('0A0B'))")
        _ = try await sys.execute("insert into pelikan_dc.pelikan_dt_m values (5, 'zbędny', null, null, null)")
        try await sys.commit()
        let diff = try await TableDataCompare.compare(table: "PELIKAN_DT_M", sourceOwner: schema, source: s, targetOwner: "PELIKAN_DC", target: sys)
        #expect(diff.inserts.count == 1 && diff.updates.count == 1 && diff.deletes.count == 1)
        let r = try await TableDataCompare.apply([diff], targetOwner: "PELIKAN_DC", options: DataCompareOptions(), in: sys)
        #expect(r.inserted == 1 && r.updated == 1 && r.deleted == 1 && r.errors.isEmpty, "\(r)")
        #expect(try await TableDataCompare.compare(table: "PELIKAN_DT_M", sourceOwner: schema, source: s, targetOwner: "PELIKAN_DC", target: sys).isEmpty)
        let script = TableDataCompare.script([diff], targetOwner: "PELIKAN_DC", options: DataCompareOptions())
        #expect(script.contains("insert into PELIKAN_DC.PELIKAN_DT_M") && script.contains("delete from PELIKAN_DC.PELIKAN_DT_M where ID = 5"))
        // Identity ALWAYS w celu: wyrównanie wstawia i zmienia wiersze z kluczem źródła, potem znowu ALWAYS.
        _ = try? await s.execute("drop table pelikan_dt_i purge")
        _ = try await s.execute("create table pelikan_dt_i (id number primary key, n varchar2(10))")
        _ = try await s.execute("insert into pelikan_dt_i values (1, 'a')")
        _ = try await s.execute("insert into pelikan_dt_i values (2, 'b')")
        try await s.commit()
        _ = try await sys.execute("create table pelikan_dc.pelikan_dt_i (id number generated always as identity primary key, n varchar2(10))")
        _ = try await sys.execute("insert into pelikan_dc.pelikan_dt_i (n) values ('x')")
        try await sys.commit()
        let di = try await TableDataCompare.compare(table: "PELIKAN_DT_I", sourceOwner: schema, source: s, targetOwner: "PELIKAN_DC", target: sys)
        #expect(di.identityAlways == ["ID"] && di.inserts.count == 1 && di.updates.count == 1)
        let ri = try await TableDataCompare.apply([di], targetOwner: "PELIKAN_DC", options: DataCompareOptions(), in: sys)
        #expect(ri.inserted == 1 && ri.updated == 1 && ri.errors.isEmpty, "\(ri)")
        #expect(try await TableDataCompare.compare(table: "PELIKAN_DT_I", sourceOwner: schema, source: s, targetOwner: "PELIKAN_DC", target: sys).isEmpty)
        #expect(try await sys.scalar("select generation_type from all_tab_identity_cols where owner = 'PELIKAN_DC' and table_name = 'PELIKAN_DT_I'") == "ALWAYS")
        _ = try await s.execute("drop table pelikan_dt_i purge")
        // Import formatu własnego z „Utwórz” do innego schematu niż bieżący: tabela w schemacie docelowym.
        let file = try TableTransfer.unpackNative(try await TableTransfer.exportNative(["PELIKAN_DT_M"], owner: schema, in: s))
        _ = try await sys.execute("drop table pelikan_dc.pelikan_dt_m purge")
        var io = TableImportOptions()
        io.create = true
        let imp = try await TableTransfer.importNative(file, tables: ["PELIKAN_DT_M"], intoOwner: "PELIKAN_DC", options: io, in: sys)
        #expect(imp.errors.isEmpty && imp.inserted == 2, "\(imp.errors)")
        #expect(try await sys.scalar("select count(*) from all_tables where table_name = 'PELIKAN_DT_M' and owner in ('PELIKAN_DC', 'SYSTEM')") == "1")
        #expect(try await sys.scalar("select count(*) from pelikan_dc.pelikan_dt_m") == "2")
        #expect(try await sys.scalar("select sys_context('userenv', 'current_schema') from dual") == "SYSTEM")
        _ = try? await sys.execute("drop user pelikan_dc cascade")
        await sys.close()
        for t in ["pelikan_dt_d", "pelikan_dt_m"] { _ = try? await s.execute("drop table \(t) purge") }
        await ws.sessions.disconnectAll()
    }

    func openTransaction(_ s: any DatabaseSession) async throws -> Bool {
        try await s.scalar("select dbms_transaction.local_transaction_id from dual") != nil
    }

    @Test("WS1-09: błąd w połowie importu i przeniesienia — wiersze wycofane, wyzwalacze i więzy włączone, sesja bez transakcji")
    func failureRollsBack() async throws {
        let s = try await TestDatabase.connect()
        let src = try await TestDatabase.connect()
        defer { Task { for t in ["pelikan_rb_c", "pelikan_rb_p", "pelikan_rb_t"] { _ = try? await s.execute("drop table \(t) purge") }; await s.close(); await src.close() } }
        for t in ["pelikan_rb_c", "pelikan_rb_p", "pelikan_rb_t"] { _ = try? await s.execute("drop table \(t) purge") }
        _ = try await s.execute("create table pelikan_rb_p (id number primary key, n varchar2(10))")
        _ = try await s.execute("create table pelikan_rb_c (id number primary key, p_id number constraint pelikan_rb_fk references pelikan_rb_p)")
        _ = try await s.execute("create or replace trigger pelikan_rb_trg before insert on pelikan_rb_p for each row begin null; end;")
        _ = try await s.execute("insert into pelikan_rb_p values (1, 'a')")
        _ = try await s.execute("insert into pelikan_rb_c values (1, 1)")
        try await s.commit()
        // Import formatu własnego: TRUNCATE tabeli nadrzędnej z włączonym kluczem obcym tabeli spoza importu — ORA-02266
        // po wyłączeniu wyzwalaczy; wyzwalacze wracają, transakcji nie ma.
        let file = PelikanTableFile(created: "", tables: [PelikanTableData(owner: schema, name: "PELIKAN_RB_P", ddl: "",
                                                                           columns: [.init(name: "ID", type: "NUMBER"), .init(name: "N", type: "VARCHAR2")],
                                                                           rows: [["2", "b"]])])
        var o = TableImportOptions()
        o.truncate = true
        o.disableTriggers = true
        await #expect(throws: (any Error).self) { _ = try await TableTransfer.importNative(file, tables: ["PELIKAN_RB_P"], intoOwner: schema, options: o, in: s) }
        #expect(try await s.scalar("select status from user_triggers where trigger_name = 'PELIKAN_RB_TRG'") == "ENABLED")
        #expect(try await openTransaction(s) == false)
        // Wyłączony FK tabeli podrzędnej, błąd wiersza (kolumna spoza tabeli) — po imporcie więz znowu włączony.
        o.truncate = false
        o.disableTriggers = false
        o.disableForeignKeys = true
        var bad = file
        bad.tables[0].name = "PELIKAN_RB_C"
        bad.tables[0].columns[1].name = "BRAK"
        let r = try await TableTransfer.importNative(bad, tables: ["PELIKAN_RB_C"], intoOwner: schema, options: o, in: s)
        #expect(r.inserted == 0 && r.errors.count == 1, "\(r.errors)")
        #expect(try await s.scalar("select status from user_constraints where constraint_name = 'PELIKAN_RB_FK'") == "ENABLED")
        #expect(try await openTransaction(s) == false)
        // Przeniesienie: błąd źródła w drugiej paczce (dzielenie przez zero w wierszu 6000) — 5000 wstawionych wierszy
        // wycofanych, sesja celu bez transakcji (jej następne użycie niczego nie zatwierdzi).
        _ = try await s.execute("create table pelikan_rb_t (id number)")
        var job = DataTransferJob()
        job.sourceQuery = "select 1 / (6000 - level) id from dual connect by level <= 6000"
        job.targetOwner = schema; job.targetTable = "PELIKAN_RB_T"
        job.mappings = [TransferColumnMapping(target: "ID", source: "ID")]
        job.commitEvery = 0
        await #expect(throws: (any Error).self) { _ = try await DataTransferRunner.run(job, source: src, target: s) }
        #expect(try await openTransaction(s) == false)
        #expect(try await s.scalar("select count(*) from pelikan_rb_t") == "0")
    }

    @Test("WS1-13, WS1-10: import CSV, przeniesienie i generator do tabeli i kolumn w cudzysłowie; liczba w polu daty CSV w formacie użytkownika")
    func mixedCaseNames() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { _ = try? await s.execute("drop table \"Pelikan_Mixed\" purge"); await s.close() } }
        _ = try? await s.execute("drop table \"Pelikan_Mixed\" purge")
        _ = try await s.execute("create table \"Pelikan_Mixed\" (\"colA\" number primary key, \"dataUr\" date)")
        let table = ResultExporter.dictionaryName("\"Pelikan_Mixed\"")
        #expect(table == "Pelikan_Mixed")
        let csv = "colA;dataUr\n1;240115\n"
        let (h, rows) = TextImport.parse(csv, TextImport.detect(csv))
        var t = ImportTarget(owner: schema, table: table, mappings: try await TextImport.defaultMappings(owner: schema, table: table, fieldNames: h, in: s))
        #expect(t.mappings.map(\.column) == ["colA", "dataUr"] && t.mappings.map(\.field) == [0, 1])
        // WS1-10: „240115” w pliku tekstowym to data w formacie pola, nie numer seryjny Excela.
        t.mappings[1].dateFormat = "YYMMDD"
        t.duplicates = .overwrite
        let r = try await TextImport.run(rows, fieldNames: h, target: t, in: s)
        #expect(r.inserted == 1 && r.errors.isEmpty, "\(r.errors)")
        #expect(try await s.scalar("select to_char(\"dataUr\", 'YYYY-MM-DD') from \"Pelikan_Mixed\" where \"colA\" = 1") == "2024-01-15")
        let r2 = try await TextImport.run([["1", "240116"]], fieldNames: h, target: t, in: s)
        #expect(r2.updated == 1 && r2.errors.isEmpty, "\(r2.errors)")
        // Przeniesienie: tabela wpisana w cudzysłowie, schemat małymi literami, kolumny celu ze słownika.
        var job = DataTransferJob()
        job.sourceQuery = "select 2 a, date '2024-02-03' d from dual"
        job.targetOwner = schema.lowercased(); job.targetTable = "\"Pelikan_Mixed\""
        #expect(try await DataTransferRunner.targetColumns(job, in: s) == ["colA", "dataUr"])
        job.mappings = [TransferColumnMapping(target: "colA", source: "A"), TransferColumnMapping(target: "dataUr", source: "D")]
        let r3 = try await DataTransferRunner.run(job, source: s, target: s)
        #expect(r3.inserted == 1 && r3.errors.isEmpty, "\(r3.errors)")
        // Generator: definicja ze słownika i zapis do bazy.
        var g = try await DataGenerator.defaultTable(owner: schema, table: table, in: s)
        #expect(g.name == "Pelikan_Mixed" && g.fields.map(\.name) == ["colA", "dataUr"])
        g.fields[0].definition = "Sequence(10)"
        g.minRecords = 2
        g.maxRecords = 2
        var gen = DataGenerator(seed: 1, session: s)
        let data = try await gen.generate([g])
        let r4 = try await DataGenerator.insert(data, tables: [g], owner: schema, in: s)
        #expect(r4.inserted == 2 && r4.errors.isEmpty, "\(r4.errors)")
        #expect(try await s.scalar("select count(*) from \"Pelikan_Mixed\"") == "4")
    }

    @Test("WS1-25: TIMESTAMP WITH LOCAL TIME ZONE między sesjami o różnej strefie — format własny, skrypt i porównanie bez przesunięcia")
    func localTimeZone() async throws {
        let a = try await TestDatabase.connect()
        let b = try await TestDatabase.connect()
        defer { Task { for t in ["pelikan_ltz_s", "pelikan_ltz_t"] { _ = try? await a.execute("drop table \(t) purge") }; await a.close(); await b.close() } }
        for t in ["pelikan_ltz_s", "pelikan_ltz_t"] { _ = try? await a.execute("drop table \(t) purge") }
        _ = try await a.execute("alter session set time_zone = '+02:00'")
        _ = try await b.execute("alter session set time_zone = '-05:00'")
        _ = try await a.execute("create table pelikan_ltz_s (id number primary key, t timestamp(9) with local time zone)")
        _ = try await a.execute("create table pelikan_ltz_t (id number primary key, t timestamp(9) with local time zone)")
        _ = try await a.execute("insert into pelikan_ltz_s values (1, timestamp '2024-06-01 12:00:00.123456789 +02:00')")
        try await a.commit()
        // Porównanie tej samej tabeli z dwóch sesji: bez fałszywych różnic.
        #expect(try await TableDataCompare.compare(table: "PELIKAN_LTZ_S", sourceOwner: schema, source: a, targetOwner: schema, target: b).isEmpty)
        // Format własny: eksport w sesji +02:00, import w sesji -05:00 — ta sama chwila.
        var file = try TableTransfer.unpackNative(try await TableTransfer.exportNative(["PELIKAN_LTZ_S"], owner: schema, includeDDL: false, in: a))
        #expect(file.tables[0].rows[0][1] == "2024-06-01 10:00:00.123456789 +00:00")
        file.tables[0].name = "PELIKAN_LTZ_T"
        let imp = try await TableTransfer.importNative(file, tables: ["PELIKAN_LTZ_T"], intoOwner: schema, options: TableImportOptions(), in: b)
        #expect(imp.inserted == 1 && imp.errors.isEmpty, "\(imp.errors)")
        let same = "select count(*) from pelikan_ltz_s s join pelikan_ltz_t t on t.id = s.id and sys_extract_utc(t.t) = sys_extract_utc(s.t)"
        #expect(try await a.scalar(same) == "1")
        // Plik sprzed poprawki (bez przesunięcia): strefa sesji celu, jak dawniej TO_TIMESTAMP.
        _ = try await b.execute("delete from pelikan_ltz_t")
        try await b.commit()
        file.tables[0].rows[0][1] = "2024-06-01 05:00:00.123456789"
        let old = try await TableTransfer.importNative(file, tables: ["PELIKAN_LTZ_T"], intoOwner: schema, options: TableImportOptions(), in: b)
        #expect(old.inserted == 1 && old.errors.isEmpty, "\(old.errors)")
        #expect(try await a.scalar(same) == "1")
        // Skrypt SQL Inserts: literał z przesunięciem.
        let script = try await TableTransfer.sqlInserts(["PELIKAN_LTZ_S"], owner: schema, options: TableExportOptions(), in: a)
        #expect(script.contains("TO_TIMESTAMP_TZ('2024-06-01 10:00:00.123456789 +00:00'"), "\(script)")
    }
}
