import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

/// Czwarta runda przeglądu (D189), grupa debuger i edytory obiektów — testy na bazie testowej.
@MainActor
@Suite("Przegląd 4: debuger, kompilator, edytory obiektów (baza)", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(2)))
struct Review4DebugEditorsDBTests {
    func workspace(_ mode: SessionMode = .multi) throws -> (Workspace, UUID) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.settings.sessionMode = mode
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, def.id)
    }

    func system() async throws -> ODPISession {
        let c = TestDatabase.config!
        return try await ODPISession.connect(target: ConnectionTarget(user: "SYSTEM", connectString: c.connectString),
                                             credentials: Credentials(password: c.systemPassword), options: ConnectOptions())
    }

    @Test("Tryby Dual i Single: krok do procedury ze zmiennymi (rekord %ROWTYPE, kolekcja) bez zawieszenia — słownik w sesji nadzorującej (WS2-02)",
          arguments: [SessionMode.dual, .single])
    func debuggerSharedSession(_ mode: SessionMode) async throws {
        let (ws, id) = try workspace(mode)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        _ = try await s.execute("""
            create or replace procedure pelikan_r4_dbg(n number) is
              type t_tab is table of number index by pls_integer;
              v number := 0;
              tab t_tab;
              r dept%rowtype;
            begin
              select * into r from dept where rownum = 1;
              for i in 1 .. n loop
                v := v + i;
                tab(i) := v;
              end loop;
            end;
            """)
        _ = try await s.execute("alter procedure pelikan_r4_dbg compile debug")
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_r4_dbg(2);\nend;")
        #expect(ws.sessionKey(for: doc)?.purpose == .main)
        let d = ws.debugger(for: doc)
        try await d.start()
        try await d.step(.into)
        #expect(d.location?.name == "PELIKAN_R4_DBG")
        for _ in 0..<6 where d.state == .paused { try await d.step(.over) }
        #expect(d.variables.contains { $0.name == "v" })
        #expect(d.variables.first { $0.name == "r" }?.children?.contains { $0.name == "deptno" } == true)
        #expect(d.variables.first { $0.name == "tab" }?.children?.isEmpty == false)
        try await d.step(.run)
        #expect(d.state == .finished)
        // Sesja okna wolna po debugowaniu (DEBUG_OFF obsłużony).
        #expect(try await ws.session(for: doc).scalar("select 1 from dual") == "1")
        if mode == .single { _ = try? await ws.session(for: doc).execute("drop procedure pelikan_r4_dbg") } else { _ = try? await s.execute("drop procedure pelikan_r4_dbg") }
        await ws.sessions.disconnectAll()
    }

    @Test("Blok z błędem kompilacji (ORA-06550) kończy debugowanie błędem w kilka sekund, sesja okna wolna (WS2-09)")
    func debuggerCompileError() async throws {
        let (ws, _) = try workspace()
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_r4_brak_takiej_procedury;\nend;")
        let d = ws.debugger(for: doc)
        let started = ContinuousClock.now
        try await d.start()
        #expect(ContinuousClock.now - started < .seconds(30))
        #expect(d.state == .finished)
        #expect(d.message?.contains("06550") == true, "\(d.message ?? "")")
        #expect(!doc.isExecuting)
        #expect(try await ws.session(for: doc).scalar("select 1 from dual") == "1")
        await ws.sessions.disconnectAll()
    }

    @Test("DBMS_OUTPUT ponad 32 KB między zatrzymaniami trafia w całości do wyjścia (WS2-11); SQL w sesji debugowanej ze strażnikiem zmian (APP2-06)")
    func debuggerOutputAndGuard() async throws {
        let (ws, id) = try workspace()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        // Procedura bez informacji debugowania: jeden krok nad jej wywołaniem = ponad 50 KB wyjścia do jednego odczytu.
        _ = try await s.execute("""
            create or replace procedure pelikan_r4_out is
            begin
              for i in 1 .. 500 loop dbms_output.put_line(rpad('x', 100, 'x') || i); end loop;
              dbms_output.put_line('koniec');
            end;
            """)
        let doc = ws.newDocument(.test, text: "begin\n  pelikan_r4_out;\n  null;\nend;")
        let d = ws.debugger(for: doc)
        try await d.start()
        #expect(d.location?.line == 2)
        try await d.step(.over)
        #expect(d.state == .paused && d.location?.line == 3)
        let lines = doc.output.filter { $0.hasPrefix("xxxx") }
        #expect(lines.count == 500, "\(lines.count)")
        #expect(doc.output.contains("koniec"))
        // Zapytanie przechodzi, zmiana na połączeniu tylko do odczytu — zablokowana.
        #expect(try await d.executeInTarget("select 'ok' as wynik from dual") == ["ok"])
        ws.startupReadOnlyPatterns = ["*"]
        await #expect(throws: (any Error).self) { _ = try await d.executeInTarget("begin dbms_output.put_line('zmiana'); end;") }
        ws.startupReadOnlyPatterns = []
        try await d.step(.run)
        #expect(d.state == .finished)
        _ = try? await s.execute("drop procedure pelikan_r4_out")
        await ws.sessions.disconnectAll()
    }

    @Test("Kompilacja z CREATE OR REPLACE w osobnej linii: linia błędu w dokumencie (WS2-10)")
    func compileErrorLine() async throws {
        let (ws, id) = try workspace()
        let doc = ws.newDocument(.program, text: """
            CREATE OR REPLACE
            PACKAGE pelikan_r4_pkg AS
              procedure p;
            END;
            /
            CREATE OR REPLACE
            PACKAGE BODY pelikan_r4_pkg AS
              procedure p is
              begin
                pelikan_r4_x := 1;
              end;
            END;
            /
            """)
        ws.bind(doc, to: id)
        let r = try await ProgramCompiler.compile(doc, in: ws)
        let e = try #require(r.messages.first { $0.severity == .error })
        #expect(e.line == 10, "\(e.line) \(e.text)")
        #expect(!doc.isExecuting)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        _ = try? await s.execute("drop package pelikan_r4_pkg")
        await ws.sessions.disconnectAll()
    }

    @Test("Pakiet bez „/” (D192): F8 kompiluje specyfikację i ciało osobno — oba VALID; ob.edit bez „/”")
    func compileWithoutSlash() async throws {
        let (ws, id) = try workspace()
        let doc = ws.newDocument(.program, text: """
            CREATE OR REPLACE PACKAGE pelikan_noslash_pkg AS
              FUNCTION f RETURN NUMBER;
            END pelikan_noslash_pkg;

            CREATE OR REPLACE PACKAGE BODY pelikan_noslash_pkg AS
              FUNCTION f RETURN NUMBER IS
              BEGIN
                RETURN 1;
              END f;
            END pelikan_noslash_pkg;
            """)
        ws.bind(doc, to: id)
        let r = try await ProgramCompiler.compile(doc, in: ws)
        #expect(r.ok && r.compiled == 2, "\(r.messages)")
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        let (_, rows) = try await s.queryAll("select object_type, status from user_objects where object_name = 'PELIKAN_NOSLASH_PKG' order by object_type", limit: 10)
        #expect(rows.map { $0.map(\.displayText) } == [["PACKAGE", "VALID"], ["PACKAGE BODY", "VALID"]])
        // Otwarcie z bazy: specyfikacja i ciało w jednym oknie, bez „/” (domyślnie).
        ws.activate(doc.id)
        try await ws.invoke("ob.edit", CommandArguments(["object": .string("PELIKAN_NOSLASH_PKG")]))
        let opened = try #require(ws.activeDocument)
        #expect(opened !== doc && !opened.text.components(separatedBy: "\n").contains("/"))
        #expect(opened.programUnitTabs.count == 2)
        _ = try? await s.execute("drop package pelikan_noslash_pkg")
        await ws.sessions.disconnectAll()
    }

    @Test("Widok dłuższy niż 4000 znaków: pełny tekst, zapis komentarza bez CREATE (WS2-04)")
    func longView() async throws {
        let (ws, id) = try workspace()
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        let columns = (1...300).map { "'wartosc_\($0)' as kolumna_widoku_\(String(format: "%04d", $0))" }.joined(separator: ", ")
        _ = try await s.execute("create or replace view pelikan_r4_v as select \(columns) from dual")
        let length = Int(try await s.scalar("select text_length from user_views where view_name = 'PELIKAN_R4_V'") ?? "") ?? 0
        #expect(length > 4000)
        var e = try await SimpleObjectEditor.load(.view, owner: schema, name: "PELIKAN_R4_V", metadata: m)
        #expect(e.value("query").contains("kolumna_widoku_0300"))
        #expect(e.value("query").utf8.count >= length - 10)
        #expect(e.statements().isEmpty)
        e.values["comments"] = "długi widok"
        let sql = e.statements()
        #expect(sql.count == 1 && sql[0].hasPrefix("COMMENT ON TABLE"))
        _ = try? await s.execute("drop view pelikan_r4_v")
        await ws.sessions.disconnectAll()
    }

    @Test("Edytor tabeli: DATA_DEFAULT (LONG), kolumna wirtualna, CHECK; wyzwalacz z innego schematu włączany/wyłączany po właścicielu (WS2-03, APP2-14)")
    func tableDefinitionAndForeignTrigger() async throws {
        let c = TestDatabase.config!
        let (ws, id) = try workspace()
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: id))
        let sys = try await system()
        func cleanUp() async {
            _ = try? await sys.execute("drop user pelikan_r4_audit cascade")
            _ = try? await sys.execute("revoke alter any trigger from \(c.user)")
            for o in ["table pelikan_r4_t purge", "table pelikan_r4_t2 purge"] { _ = try? await s.execute("drop \(o)") }
        }
        await cleanUp()
        _ = try await s.execute("""
            create table pelikan_r4_t (id number default on null 5, nazwa varchar2(20) default 'abc', podwojone number as (id * 2),
              constraint pelikan_r4_chk check (nazwa <> 'zakazana'))
            """)
        _ = try await s.execute("create table pelikan_r4_t2 (id number)")
        _ = try await s.execute("create trigger pelikan_r4_trg before insert on pelikan_r4_t2 for each row begin null; end;")
        _ = try await sys.execute("create user pelikan_r4_audit no authentication")
        _ = try await sys.execute("create trigger pelikan_r4_audit.pelikan_r4_trg before insert on \(schema).pelikan_r4_t for each row begin null; end;")
        _ = try await sys.execute("grant alter any trigger to \(c.user)")
        let d = try await TableDDL.load(owner: schema, name: "PELIKAN_R4_T", metadata: m)
        #expect(d.columns.first { $0.name == "ID" }?.defaultValue == "5" && d.columns.first { $0.name == "ID" }?.defaultOnNull == true)
        #expect(d.columns.first { $0.name == "NAZWA" }?.defaultValue == "'abc'")
        #expect(d.columns.first { $0.name == "PODWOJONE" }?.virtualExpression.contains("ID") == true)
        #expect(d.checks.first { $0.name == "PELIKAN_R4_CHK" }?.condition.contains("zakazana") == true)
        let trg = try #require(d.triggers.first)
        #expect(d.triggers.count == 1 && trg.owner == "PELIKAN_R4_AUDIT" && trg.name == "PELIKAN_R4_TRG")
        try await ws.invoke("ob.disable", CommandArguments(["object": .string("\"\(trg.owner)\".\"\(trg.name)\""), "type": .string("TRIGGER"),
                                                         "connection": .string(id.uuidString)]))
        let (_, rows) = try await sys.queryAll("select owner, status from dba_triggers where trigger_name = 'PELIKAN_R4_TRG' order by owner")
        let status = Dictionary(uniqueKeysWithValues: rows.map { ($0[0].displayText ?? "", $0[1].displayText ?? "") })
        #expect(status["PELIKAN_R4_AUDIT"] == "DISABLED" && status[schema] == "ENABLED")
        await cleanUp()
        await sys.close()
        await ws.sessions.disconnectAll()
    }
}
