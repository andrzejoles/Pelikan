import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Proste edytory P2 — DDL bez bazy (PD-OED-008, PD-OED-009, PD-OED-010)")
struct P2ObjectEditorTests {
    @Test("Biblioteka, katalog, profil, łącze (hasło maskowane, zmiana wymaga hasła), widok")
    func ddl() {
        let lib = SimpleObjectEditor(kind: .library, owner: "HR", values: ["name": "LIB_X", "file": "/opt/lib/x.so"])
        #expect(lib.statements() == ["CREATE OR REPLACE LIBRARY HR.LIB_X AS '/opt/lib/x.so'"])
        let dir = SimpleObjectEditor(kind: .directory, owner: "HR", values: ["name": "KAT", "path": "/u01/Dane"], original: ["name": "KAT", "path": "/u01/dane"])
        #expect(dir.statements() == ["CREATE OR REPLACE DIRECTORY KAT AS '/u01/Dane'"])
        var prof = SimpleObjectEditor(kind: .profile, owner: "", values: ["name": "P1", "limits": "SESSIONS_PER_USER:2, FAILED_LOGIN_ATTEMPTS:5"])
        #expect(prof.statements() == ["CREATE PROFILE P1 LIMIT FAILED_LOGIN_ATTEMPTS 5 SESSIONS_PER_USER 2"])
        prof.original = prof.values
        prof.values["limits"] = "FAILED_LOGIN_ATTEMPTS:3"
        #expect(prof.statements() == ["ALTER PROFILE P1 LIMIT FAILED_LOGIN_ATTEMPTS 3 SESSIONS_PER_USER DEFAULT"])
        var link = SimpleObjectEditor(kind: .databaseLink, owner: "HR", values: ["name": "ZDALNA", "user": "SCOTT", "password": "ta\"jne", "connect": "db2/svc"])
        #expect(link.statements(masked: true) == ["CREATE DATABASE LINK ZDALNA CONNECT TO SCOTT IDENTIFIED BY ******** USING 'db2/svc'"])
        #expect(link.statements() == ["CREATE DATABASE LINK ZDALNA CONNECT TO SCOTT IDENTIFIED BY \"tajne\" USING 'db2/svc'"])
        link.original = ["name": "ZDALNA", "user": "SCOTT", "connect": "db2/svc", "public": "N"]
        link.values = ["name": "ZDALNA", "user": "SCOTT", "connect": "db3/svc", "public": "N"]
        #expect(link.statements().isEmpty && link.issue != nil)
        link.values["password"] = "x"
        #expect(link.statements(masked: true) == ["DROP DATABASE LINK ZDALNA", "CREATE DATABASE LINK ZDALNA CONNECT TO SCOTT IDENTIFIED BY ******** USING 'db3/svc'"])
        let view = SimpleObjectEditor(kind: .view, owner: "HR", values: ["name": "V1", "query": "select * from emp;", "readOnly": "Y", "comments": "Pracownicy"])
        #expect(view.statements() == ["CREATE OR REPLACE VIEW HR.V1 AS\nselect * from emp\nWITH READ ONLY", "COMMENT ON TABLE HR.V1 IS 'Pracownicy'"])
        #expect(SimpleObjectEditor.stripViewClauses("select a from t\nwith check option constraint \"SYS_C001\"") == "select a from t")
        #expect(SimpleObjectEditor.stripViewClauses("select a from t with read only ") == "select a from t")
        #expect(SimpleObjectEditor.stripViewClauses("with x as (select 1 a from dual) select a from x") == "with x as (select 1 a from dual) select a from x")
    }

    @Test("Kolejka: tabela, kolejka i start; zmiana — ALTER_QUEUE i STOP_QUEUE; zadanie przez DBMS_SCHEDULER; uprawnienia obiektowe")
    func queueJobGrants() {
        var q = SimpleObjectEditor(kind: .queue, owner: "HR", values: ["name": "Q1", "queueTable": "Q1_TAB", "createTable": "Y", "payload": "RAW",
                                                                        "maxRetries": "3", "enqueue": "Y", "dequeue": "Y"])
        let s = q.statements()[0]
        #expect(s.contains("dbms_aqadm.create_queue_table(queue_table => 'HR.Q1_TAB', queue_payload_type => 'RAW')"))
        #expect(s.contains("dbms_aqadm.create_queue(queue_name => 'HR.Q1', queue_table => 'HR.Q1_TAB', max_retries => 3)"))
        #expect(s.contains("dbms_aqadm.start_queue(queue_name => 'HR.Q1', enqueue => true, dequeue => true)"))
        q.original = q.values
        q.values["maxRetries"] = "5"
        q.values["dequeue"] = "N"
        let a = q.statements()[0]
        #expect(a.contains("alter_queue(queue_name => 'HR.Q1', max_retries => 5)") && a.contains("stop_queue(queue_name => 'HR.Q1', enqueue => false, dequeue => true)"))
        #expect(!a.contains("create_queue"))
        var job = SimpleObjectEditor(kind: .job, owner: "HR", values: ["name": "J1", "jobType": "PLSQL_BLOCK", "action": "begin null; end;", "repeat": "FREQ=DAILY", "enabled": "N"])
        #expect(job.statements()[0].contains("dbms_scheduler.create_job(") && job.statements()[0].contains("enabled => false"))
        job.original = job.values
        job.values["enabled"] = "Y"
        #expect(job.statements() == ["begin\n  dbms_scheduler.enable('HR.J1');\nend;"])
        let role = SimpleObjectEditor(kind: .role, owner: "", values: ["name": "R1", "objectPrivileges": "SELECT ON HR.EMP, EXECUTE ON HR.PKG"],
                                      original: ["name": "R1", "objectPrivileges": "SELECT ON HR.EMP, UPDATE ON HR.DEPT"])
        #expect(role.statements() == ["GRANT EXECUTE ON HR.PKG TO R1", "REVOKE UPDATE ON HR.DEPT FROM R1"])
        #expect(SimpleObjectEditor.objectGrant("BEZ ON") == nil)
    }
}
