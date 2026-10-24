import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Edytory P2 na bazie: biblioteka, katalog, zadanie, kolejka, profil, łącze, widok, uprawnienia obiektowe",
       .enabled(if: TestDatabase.isAvailable), .serialized)
struct P2ObjectEditorDBTests {
    func workspace() throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    func roundTrip(_ e: SimpleObjectEditor, _ ws: Workspace, _ id: UUID, _ m: MetadataProvider) async throws -> SimpleObjectEditor {
        let r = try await e.apply(in: ws, connectionID: id)
        #expect(r.error == nil, "\(e.kind): \(r.failed ?? "") \(r.error ?? "")")
        let loaded = try await SimpleObjectEditor.load(e.kind, owner: e.owner, name: e.value("name").uppercased(), metadata: m)
        #expect(loaded.statements().isEmpty, "\(e.kind): \(loaded.statements())")
        return loaded
    }

    @Test("Utworzenie, wczytanie bez zmian i zmiana dla każdego rodzaju")
    func editors() async throws {
        let (ws, id) = try workspace()
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        for d in ["library pelikan_p2_lib", "directory pelikan_p2_dir", "profile pelikan_p2_prof", "database link pelikan_p2_link",
                  "view pelikan_p2_v", "role pelikan_p2_role"] { _ = try? await s.execute("drop \(d)") }
        _ = try? await s.execute("begin dbms_scheduler.drop_job('PELIKAN_P2_JOB', true); end;")
        _ = try? await s.execute("begin dbms_aqadm.stop_queue('PELIKAN_P2_Q'); dbms_aqadm.drop_queue('PELIKAN_P2_Q'); end;")
        _ = try? await s.execute("begin dbms_aqadm.drop_queue_table('PELIKAN_P2_QT', true); end;")

        var lib = try await roundTrip(SimpleObjectEditor(kind: .library, owner: schema, values: ["name": "PELIKAN_P2_LIB", "file": "/tmp/pelikan.so"]), ws, id, m)
        #expect(lib.value("file") == "/tmp/pelikan.so")
        lib.values["file"] = "/tmp/inna.so"
        _ = try await roundTrip(lib, ws, id, m)

        var dir = try await roundTrip(SimpleObjectEditor(kind: .directory, owner: schema, values: ["name": "PELIKAN_P2_DIR", "path": "/tmp/Pelikan"]), ws, id, m)
        #expect(dir.value("path") == "/tmp/Pelikan")
        dir.values["path"] = "/tmp/pelikan2"
        _ = try await roundTrip(dir, ws, id, m)

        var job = try await roundTrip(SimpleObjectEditor(kind: .job, owner: schema, values: ["name": "PELIKAN_P2_JOB", "jobType": "PLSQL_BLOCK",
                                                                                           "action": "begin null; end;", "repeat": "FREQ=DAILY", "enabled": "N", "comments": "test"]), ws, id, m)
        #expect(job.value("repeat") == "FREQ=DAILY" && job.value("enabled") == "N")
        job.values["repeat"] = "FREQ=HOURLY"
        _ = try await roundTrip(job, ws, id, m)

        var q = try await roundTrip(SimpleObjectEditor(kind: .queue, owner: schema, values: ["name": "PELIKAN_P2_Q", "queueTable": "PELIKAN_P2_QT", "createTable": "Y",
                                                                                           "payload": "RAW", "maxRetries": "3", "retryDelay": "0", "enqueue": "Y", "dequeue": "Y", "comments": "kolejka"]), ws, id, m)
        #expect(q.value("payload") == "RAW" && q.value("maxRetries") == "3" && q.value("enqueue") == "Y")
        q.values["maxRetries"] = "7"
        q.values["dequeue"] = "N"
        q = try await roundTrip(q, ws, id, m)
        #expect(q.value("maxRetries") == "7" && q.value("dequeue") == "N")

        var prof = try await roundTrip(SimpleObjectEditor(kind: .profile, owner: schema, values: ["name": "PELIKAN_P2_PROF", "limits": "FAILED_LOGIN_ATTEMPTS:5, SESSIONS_PER_USER:3"]), ws, id, m)
        #expect(prof.value("limits").contains("SESSIONS_PER_USER:3"))
        prof.values["limits"] = "FAILED_LOGIN_ATTEMPTS:4"
        prof = try await roundTrip(prof, ws, id, m)
        #expect(prof.value("limits") == "FAILED_LOGIN_ATTEMPTS:4")

        let c = TestDatabase.config!
        let link = try await roundTrip(SimpleObjectEditor(kind: .databaseLink, owner: schema, values: ["name": "PELIKAN_P2_LINK", "user": c.user,
                                                                                                    "password": c.password, "connect": "//localhost:1521/FREEPDB1"]), ws, id, m)
        #expect(link.value("connect") == "//localhost:1521/FREEPDB1" && link.value("user") == c.user.uppercased())

        var view = try await roundTrip(SimpleObjectEditor(kind: .view, owner: schema, values: ["name": "PELIKAN_P2_V", "query": "select empno, ename from emp",
                                                                                             "readOnly": "Y", "comments": "widok P2"]), ws, id, m)
        #expect(view.value("readOnly") == "Y" && view.value("comments") == "widok P2")
        view.values["readOnly"] = "N"
        view.values["checkOption"] = "Y"
        view = try await roundTrip(view, ws, id, m)
        #expect(view.value("checkOption") == "Y")

        var role = try await roundTrip(SimpleObjectEditor(kind: .role, owner: schema, values: ["name": "PELIKAN_P2_ROLE",
                                                                                             "objectPrivileges": "SELECT ON \(schema).EMP, UPDATE ON \(schema).DEPT"]), ws, id, m)
        #expect(role.value("objectPrivileges").contains("SELECT ON \(schema).EMP"))
        role.values["objectPrivileges"] = "SELECT ON \(schema).EMP"
        role = try await roundTrip(role, ws, id, m)
        #expect(!role.value("objectPrivileges").contains("UPDATE"))

        for d in ["library pelikan_p2_lib", "directory pelikan_p2_dir", "profile pelikan_p2_prof", "database link pelikan_p2_link",
                  "view pelikan_p2_v", "role pelikan_p2_role"] { _ = try? await s.execute("drop \(d)") }
        _ = try? await s.execute("begin dbms_scheduler.drop_job('PELIKAN_P2_JOB', true); end;")
        _ = try? await s.execute("begin dbms_aqadm.stop_queue('PELIKAN_P2_Q'); dbms_aqadm.drop_queue('PELIKAN_P2_Q'); end;")
        _ = try? await s.execute("begin dbms_aqadm.drop_queue_table('PELIKAN_P2_QT', true); end;")
        await ws.sessions.disconnectAll()
    }
}
