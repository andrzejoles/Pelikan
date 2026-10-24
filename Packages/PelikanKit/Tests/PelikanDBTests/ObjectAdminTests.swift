import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Operacje na obiektach i okno programu (audyt Etapu 8)", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct ObjectAdminTests {
    func workspace() async throws -> (Workspace, ConnectionDefinition, TestUI, any DatabaseSession) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let ui = TestUI()
        ws.ui = ui
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        return (ws, def, ui, s)
    }

    @Test("Wyzwalacz i wszystkie wyzwalacze tabeli: wyłącz i włącz; flagi kompilacji warunkowej")
    func enableAndFlags() async throws {
        let (ws, _, _, s) = try await workspace()
        _ = try await s.execute("create or replace trigger pelikan_adm_trg before update on dept for each row begin null; end;")
        _ = try await ws.invoke("ob.disable", CommandArguments(["object": "pelikan_adm_trg"]))
        #expect(try await s.scalar("select status from user_triggers where trigger_name = 'PELIKAN_ADM_TRG'") == "DISABLED")
        _ = try await ws.invoke("ob.enable", CommandArguments(["object": "dept", "type": "TABLE"]))
        #expect(try await s.scalar("select status from user_triggers where trigger_name = 'PELIKAN_ADM_TRG'") == "ENABLED")
        _ = try await s.execute("create or replace procedure pelikan_adm_cc is begin $if $$debug $then null; $end null; end;")
        let r = try await ws.invoke("ob.ccflags", CommandArguments(["object": "pelikan_adm_cc", "flags": "debug:TRUE"]))
        #expect(r.value == .string("debug:TRUE"))
        #expect(throws: (any Error).self) { try ObjectAdmin.ccflagsStatement(DBObject(owner: "X", name: "P", type: .procedure), flags: "x'; drop") }
        _ = try await s.execute("drop trigger pelikan_adm_trg")
        _ = try await s.execute("drop procedure pelikan_adm_cc")
        await ws.sessions.disconnectAll()
    }

    @Test("Kosz: lista, przywrócenie pod nową nazwą, trwałe usunięcie")
    func recycleBin() async throws {
        let (ws, _, ui, s) = try await workspace()
        _ = try? await s.execute("drop table pelikan_adm_bin purge")
        _ = try? await s.execute("drop table pelikan_adm_bin2 purge")
        _ = try await s.execute("create table pelikan_adm_bin (id number)")
        _ = try await s.execute("drop table pelikan_adm_bin")
        let list = try await ws.invoke("ob.recycleBin")
        guard case .array(let items)? = list.value else { Issue.record("brak listy"); return }
        #expect(items.contains { if case .object(let o) = $0 { o["originalName"] == .string("PELIKAN_ADM_BIN") } else { false } })
        _ = try await ws.invoke("ob.restoreFromRecycleBin", CommandArguments(["name": "pelikan_adm_bin", "renameTo": "pelikan_adm_bin2"]))
        #expect(try await s.scalar("select count(*) from user_tables where table_name = 'PELIKAN_ADM_BIN2'") == "1")
        _ = try await s.execute("drop table pelikan_adm_bin2")
        ui.askAnswer = 0
        _ = try await ws.invoke("ob.purgeRecycleBin", CommandArguments(["name": "pelikan_adm_bin2"]))
        #expect(try await s.scalar("select count(*) from user_recyclebin where original_name = 'PELIKAN_ADM_BIN2'") == "0")
        await ws.sessions.disconnectAll()
    }

    @Test("Okno programu: kompilacja próbna bez zastępowania, wykrycie zmiany w bazie, blok w oknie testu, plik tylko do odczytu, źródło do edytora")
    func programWindow() async throws {
        let (ws, def, _, s) = try await workspace()
        _ = try await s.execute("create or replace function pelikan_adm_f return number is begin return 1; end;")
        _ = try await ws.invoke("ob.edit", CommandArguments(["object": "pelikan_adm_f"]))
        let doc = try #require(ws.activeDocument)
        #expect(doc.kind == .program && !doc.objectTimestamps.isEmpty)
        doc.text = "create or replace function pelikan_adm_f return number is begin return nieznana; end;\n/\n"
        let safe = try await ws.invoke("prog.safeCompile")
        if case .int(let n)? = safe.value { #expect(n >= 1) } else { Issue.record("brak liczby błędów") }
        #expect(doc.compileMessages.contains { $0.text.uppercased().contains("NIEZNANA") } && !doc.compileMessages.contains { $0.text.contains("PELIKAN$SAFE") })
        #expect(try await s.scalar("select status from user_objects where object_name = 'PELIKAN_ADM_F'") == "VALID")
        #expect(try await s.scalar("select count(*) from user_objects where object_name like 'PELIKAN$SAFE%'") == "0")
        try await Task.sleep(for: .seconds(1.2))
        _ = try await s.execute("alter function pelikan_adm_f compile")
        let changed = try await ws.invoke("prog.checkChanges")
        #expect(changed.value == .array([.string("\(c().user.uppercased()).PELIKAN_ADM_F.FUNCTION")]) && doc.statusText?.hasPrefix("⚠️") == true)
        #expect(await ws.checkProgramWindowChanges() == [doc.id])
        ws.activate(doc.id)
        (ws.ui as? TestUI)?.askAnswer = 0
        _ = try await ws.invoke("prog.reloadFromDatabase")
        #expect(doc.text.lowercased().contains("return 1") && !doc.isModified)
        #expect(try await ws.invoke("prog.checkChanges").value == .array([]))
        doc.text = "begin\n  dbms_output.put_line('blok ' || pelikan_adm_f);\nend;"
        doc.connectionID = def.id
        let run = try await ws.invoke("prog.runBlock")
        #expect(run.value == .array([.string("blok 1")]) && ws.activeDocument?.kind == .test)
        // Plik tylko do odczytu: kompilacja zablokowana preferencją.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-ro-\(UUID().uuidString.prefix(6)).fnc")
        try "create or replace function pelikan_adm_f return number is begin return 2; end;\n/\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path); try? FileManager.default.removeItem(at: file) }
        let ro = try ws.openFile(file, as: .program)
        ro.connectionID = def.id
        await #expect(throws: (any Error).self) { _ = try await ProgramCompiler.compile(ro, in: ws) }
        ws.settings.compileReadOnlyFiles = true
        #expect(try await ProgramCompiler.compile(ro, in: ws).ok)
        // Źródło do edytora w miejscu kursora.
        let target = ws.newDocument(.program, text: "-- tutaj\n")
        target.selectedRange = 9..<9
        ws.activate(target.id)
        _ = try await ws.invoke("ob.addSourceToEditor", CommandArguments(["object": "pelikan_adm_f"]))
        #expect(target.text.hasPrefix("-- tutaj\n") && target.text.lowercased().contains("function pelikan_adm_f"))
        _ = try await s.execute("drop function pelikan_adm_f")
        await ws.sessions.disconnectAll()
    }

    func c() -> TestDatabase.Config { TestDatabase.config! }

    @Test("Widok zmaterializowany: odświeżenie z menu obiektu")
    func refreshMV() async throws {
        let (ws, _, _, s) = try await workspace()
        _ = try? await s.execute("drop materialized view pelikan_adm_mv")
        _ = try await s.execute("create materialized view pelikan_adm_mv refresh complete on demand as select deptno, count(*) n from emp group by deptno")
        _ = try await ws.invoke("ob.refreshMV", CommandArguments(["object": "pelikan_adm_mv", "type": "MATERIALIZED VIEW"]))
        #expect(try await s.scalar("select count(*) from user_mviews where mview_name = 'PELIKAN_ADM_MV' and last_refresh_type = 'COMPLETE'") == "1")
        _ = try await s.execute("drop materialized view pelikan_adm_mv")
        await ws.sessions.disconnectAll()
    }

    @Test("Moduł MLE w oknie programu: źródło z nagłówkiem CREATE MLE MODULE, kompilacja, błąd składni JavaScript")
    func mleInProgramWindow() async throws {
        let (ws, def, _, s) = try await workspace()
        _ = try await s.execute(MLE.createModuleDDL(name: "pelikan_adm_mle", source: "export function f() { return 1; }", version: "1.0"))
        _ = try await ws.invoke("ob.edit", CommandArguments(["object": "pelikan_adm_mle", "type": "MLE MODULE"]))
        let doc = try #require(ws.activeDocument)
        #expect(doc.kind == .program && doc.text.lowercased().hasPrefix("create or replace mle module pelikan_adm_mle language javascript version '1.0' as"))
        #expect(ProgramCompiler.units(in: doc.text).first?.type == .mleModule)
        doc.connectionID = def.id
        doc.text = doc.text.replacingOccurrences(of: "return 1", with: "return 2")
        #expect(try await ProgramCompiler.compile(doc, in: ws).ok)
        #expect(try await MLE.source(owner: try #require(try await s.scalar("select user from dual")), name: "PELIKAN_ADM_MLE", in: s).contains("return 2"))
        doc.text = "create or replace mle module pelikan_adm_mle language javascript as\nexport function f( { return ;\n/\n"
        #expect(try await ProgramCompiler.compile(doc, in: ws).ok == false)
        _ = try await s.execute("drop mle module pelikan_adm_mle")
        await ws.sessions.disconnectAll()
    }
}
