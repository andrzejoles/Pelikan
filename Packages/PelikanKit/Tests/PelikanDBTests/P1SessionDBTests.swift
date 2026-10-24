import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Okno testu na bazie — Substitution i AutoCommit (PD-TEST-002, PD-TEST-003)", .enabled(if: TestDatabase.isAvailable), .serialized)
struct P1SessionDBTests {
    @Test("Zmienna Substitution wstawia nazwę tabeli; AutoCommit po wykonaniu zatwierdza zmiany widoczne w innej sesji")
    func substitutionAutoCommit() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let other = try await TestDatabase.connect()
        _ = try? await other.execute("drop table pelikan_ac purge")
        _ = try await other.execute("create table pelikan_ac (n number)")
        defer { Task { _ = try? await other.execute("drop table pelikan_ac purge") } }
        let doc = ws.newDocument(.test, text: "begin\n  insert into :tab values (1);\n  select count(*) into :n from :tab;\nend;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        TestRunner.synchronize(doc)
        doc.testVariables[0].type = .substitution
        doc.testVariables[0].value = "pelikan_ac"
        doc.testVariables[0].isNull = false
        doc.testVariables[1].type = .integer
        _ = try await TestRunner.execute(doc, in: ws)
        #expect(doc.testVariables[1].value == "1")
        var seen = try await other.queryAll("select count(*) from pelikan_ac").rows[0][0].format(.default)
        #expect(seen == "0")
        try await ws.endTransactions(of: [doc], commit: false)
        ws.settings.autoCommitTestWindow = true
        _ = try await TestRunner.execute(doc, in: ws)
        seen = try await other.queryAll("select count(*) from pelikan_ac").rows[0][0].format(.default)
        #expect(seen == "1" && !doc.transactionOpen)
        ws.settings.autoCommitTestWindow = false
    }

    @Test("BFile: wartość KATALOG:plik na wejściu i odczyt lokalizatora przypisanego w bloku (PD-TEST-002)")
    func bfile() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.test, text: "begin\n  :nazwa := case when :wej is null then 'brak' else 'jest' end;\n  :wej := bfilename('NOWY_KAT', 'b.txt');\nend;")
        doc.connectionID = def.id
        doc.connectionPinned = true
        TestRunner.synchronize(doc)
        let i = try #require(doc.testVariables.firstIndex { $0.name == "wej" })
        doc.testVariables[i].type = .bfile
        doc.testVariables[i].value = "KAT:a.txt"
        doc.testVariables[i].isNull = false
        _ = try await TestRunner.execute(doc, in: ws)
        #expect(doc.testVariables.first { $0.name == "nazwa" }?.value == "jest")
        #expect(doc.testVariables[i].value == "NOWY_KAT:b.txt" && doc.testVariables[i].changed)
        await ws.sessions.disconnectAll()
    }

    @Test("Porównanie z obiektem w innym połączeniu: okno programu i obiekt z Object Browsera (PD-PROG-008, PD-OB-022)")
    func compareWithConnection() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let a = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        let b = ConnectionDefinition(name: "dev_test_2", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(a, password: c.password)
        try ws.connections.upsert(b, password: c.password)
        ws.sessions.setMainConnection(a.id)
        let s = try await ws.sessions.session(SessionKey(connectionID: a.id, purpose: .main))
        _ = try await s.execute("create or replace procedure pelikan_cmp_p is begin null; end;")
        defer { Task { _ = try? await s.execute("drop procedure pelikan_cmp_p") } }
        let schema = try await ws.metadata()!.currentSchema()
        ws.selectedObject = DBObject(owner: schema, name: "PELIKAN_CMP_P", type: .procedure)
        let same = try await ws.invoke("ob.compareWithConnection", CommandArguments(["connection": .string("dev_test_2")]))
        #expect(same.message == "Brak różnic")
        let other = try await ws.invoke("ob.compareWithConnection", CommandArguments(["connection": .string("dev_test_2"), "schema": .string("NIE_MA_TAKIEGO")]))
        #expect(other.message != "Brak różnic")
        let doc = ws.newDocument(.program, text: "create or replace procedure pelikan_cmp_p is begin null; /* zmiana */ end;\n/\n")
        doc.connectionID = a.id
        ws.activate(doc.id)
        let prog = try await ws.invoke("prog.compareWithConnection", CommandArguments(["connection": .string("dev_test_2")]))
        guard case .string(let diff)? = prog.value else { Issue.record("brak różnicy"); return }
        #expect(diff.contains("zmiana"))
        await #expect(throws: (any Error).self) { try await ws.invoke("ob.compareWithConnection", CommandArguments(["connection": .string("nie_ma")])) }
        await ws.sessions.disconnectAll()
    }

    @Test("Asercja 26ai: szablon w menu Nowy, folder Object Browsera, DDL, Usuń (PD-OED-011)")
    func assertion() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        _ = try? await s.execute("drop assertion pelikan_as_t_dodatnie")
        _ = try? await s.execute("drop table pelikan_as_t2 purge")
        _ = try await s.execute("create table pelikan_as_t2 (n number)")
        defer { Task { _ = try? await s.execute("drop table pelikan_as_t2 purge") } }
        #expect(ws.registry.command("file.newAssertion") != nil)
        #expect(ws.templates.all.contains { $0.name == "Asercja" && $0.text.contains("create assertion") })
        do {
            _ = try await s.execute("create assertion pelikan_as_t2_dodatnie check (not exists (select 1 from pelikan_as_t2 where n < 0))")
        } catch {
            // Obraz bazy bez asercji (przed 23.26) — test nie ma czego sprawdzić.
            return
        }
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let list = try await m.objects(.assertion, owner: schema)
        let a = try #require(list.first { $0.name == "PELIKAN_AS_T2_DODATNIE" })
        #expect(try await m.ddl(of: a).uppercased().contains("ASSERTION"))
        ws.selectedObject = a
        ui.askAnswer = 0
        try await ws.invoke("ob.drop", CommandArguments())
        #expect(try await m.objects(.assertion, owner: schema).contains { $0.name == "PELIKAN_AS_T2_DODATNIE" } == false)
        await ws.sessions.disconnectAll()
    }

    @Test("Test łącza (pętla do tej samej bazy), DBMS_JOB.RUN i start/stop kolejki AQ z Object Browsera (PD-OB-019)")
    func linkJobQueue() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        let schema = try await ws.metadata()!.currentSchema()
        // Łącze do tej samej bazy (z wnętrza kontenera: port 1521) — hasło testowe tylko w poleceniu do bazy testowej.
        _ = try? await s.execute("drop database link pelikan_loop")
        _ = try await s.execute("create database link pelikan_loop connect to \(c.user) identified by \"\(c.password)\" using 'localhost:1521/FREEPDB1'")
        ws.selectedObject = DBObject(owner: schema, name: "PELIKAN_LOOP", type: .databaseLink)
        let link = try await ws.invoke("ob.testLink", CommandArguments())
        #expect(link.message?.isEmpty == false)
        _ = try? await s.execute("drop database link pelikan_loop")
        // DBMS_JOB: zadanie zgłoszone na jutro, uruchomione teraz — skutek widać w tabeli (23ai: DBMS_JOB to nakładka na
        // Scheduler i nie zapisuje LAST_DATE w USER_JOBS).
        _ = try? await s.execute("drop table pelikan_job_t purge")
        _ = try await s.execute("create table pelikan_job_t (n number)")
        let r = try await s.execute("begin dbms_job.submit(:j, 'insert into pelikan_job_t values (1);', sysdate + 1); commit; end;",
                                    binds: [BindVariable(name: "j", type: .number, direction: .output)])
        let job = try #require(r.outBinds["j"]?.displayText ?? r.outBinds["J"]?.displayText)
        ws.selectedObject = DBObject(owner: schema, name: job, type: .job)
        _ = try await ws.invoke("ob.runJob", CommandArguments())
        let ran = try await s.queryAll("select count(*) from pelikan_job_t")
        #expect(ran.rows.first?.first?.displayText == "1")
        _ = try? await s.execute("drop table pelikan_job_t purge")
        _ = try? await s.execute("begin dbms_job.remove(:j); commit; end;", binds: [BindVariable(name: "j", type: .number, value: .text(job))])
        // Kolejka AQ: start i stop.
        _ = try? await s.execute("begin dbms_aqadm.stop_queue('PELIKAN_Q'); dbms_aqadm.drop_queue('PELIKAN_Q'); end;")
        _ = try? await s.execute("begin dbms_aqadm.drop_queue_table('PELIKAN_QT', force => true); end;")
        _ = try await s.execute("begin dbms_aqadm.create_queue_table('PELIKAN_QT', 'RAW'); dbms_aqadm.create_queue('PELIKAN_Q', 'PELIKAN_QT'); end;")
        ws.selectedObject = DBObject(owner: schema, name: "PELIKAN_Q", type: .queue)
        ui.askAnswer = 0
        _ = try await ws.invoke("ob.startQueue", CommandArguments())
        func state() async throws -> String {
            try await s.queryAll("select trim(enqueue_enabled) || '/' || trim(dequeue_enabled) from user_queues where name = 'PELIKAN_Q'").rows.first?.first?.displayText ?? ""
        }
        #expect(try await state() == "YES/YES")
        _ = try await ws.invoke("ob.stopQueue", CommandArguments(["dequeue": .bool(false)]))
        #expect(try await state() == "NO/YES")
        _ = try? await s.execute("begin dbms_aqadm.stop_queue('PELIKAN_Q'); dbms_aqadm.drop_queue('PELIKAN_Q'); dbms_aqadm.drop_queue_table('PELIKAN_QT'); end;")
        await ws.sessions.disconnectAll()
    }

    @Test("Partycje istniejącej tabeli: dodanie, zmiana nazwy, usunięcie; tworzenie z podpartycjami HASH (PD-OED-006)")
    func partitions() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let m = try #require(ws.metadata())
        let owner = try await m.currentSchema()
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        for x in ["pelikan_part_t", "pelikan_sub_t"] { _ = try? await s.execute("drop table \(x) purge") }
        _ = try await s.execute("""
            create table pelikan_part_t (id number, d date) partition by range (id)
              (partition p1 values less than (100), partition p2 values less than (200))
            """)
        let loaded = try await TableDDL.load(owner: owner, name: "PELIKAN_PART_T", metadata: m)
        #expect(loaded.partitioning?.method == .range && loaded.partitioning?.columns == ["ID"])
        #expect(loaded.partitioning?.partitions.map(\.name) == ["P1", "P2"] && loaded.partitioning?.partitions.first?.values == "100")
        #expect(TableDDL.statements(from: loaded, to: loaded).isEmpty)
        var changed = loaded
        changed.partitioning?.partitions.removeFirst()
        changed.partitioning?.partitions[0].name = "P_DO_200"
        changed.partitioning?.partitions.append(TableDefinition.Partition(name: "P3", values: "300"))
        let sql = TableDDL.statements(from: loaded, to: changed)
        #expect(sql.contains { $0.hasSuffix("DROP PARTITION P1") } && sql.contains { $0.hasSuffix("RENAME PARTITION P2 TO P_DO_200") })
        for x in sql { _ = try await s.execute(x) }
        let after = try await TableDDL.load(owner: owner, name: "PELIKAN_PART_T", metadata: m)
        #expect(after.partitioning?.partitions.map(\.name) == ["P_DO_200", "P3"])
        var sub = TableDefinition(owner: owner, name: "PELIKAN_SUB_T")
        sub.columns = [TableDefinition.Column(name: "ID", type: "NUMBER"), TableDefinition.Column(name: "K", type: "NUMBER")]
        var p = TableDefinition.Partitioning(method: .range, columns: ["ID"])
        p.partitions = [.init(name: "P1", values: "MAXVALUE")]
        p.subpartitionColumns = ["K"]
        p.subpartitionCount = 4
        sub.partitioning = p
        for x in TableDDL.statements(from: nil, to: sub) { _ = try await s.execute(x) }
        let subs = try await s.queryAll("select count(*) from user_tab_subpartitions where table_name = 'PELIKAN_SUB_T'")
        #expect(subs.rows.first?.first?.displayText == "4")
        for x in ["pelikan_part_t", "pelikan_sub_t"] { _ = try? await s.execute("drop table \(x) purge") }
        await ws.sessions.disconnectAll()
    }
}
