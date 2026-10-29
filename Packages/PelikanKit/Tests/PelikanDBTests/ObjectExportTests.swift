import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Eksport i porównanie obiektów na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct ObjectExportTests {
    @Test("Eksport DDL: jeden plik w kolejności wykonalnej i plik na obiekt (pakiet razem albo .pks/.pkb)")
    func export() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let schema = TestDatabase.config!.user.uppercased()
        let all = try await ObjectExport.objects(owner: schema, in: s)
        let pick = all.filter { ["DEPT", "EMP_API"].contains($0.name) && [.table, .package, .packageBody].contains($0.type) }
        #expect(pick.count == 3)
        let single = try await ObjectExport.export(pick, options: ObjectExportOptions(), in: s)
        #expect(single.count == 1)
        let text = single[0].content.uppercased()
        let table = try #require(text.range(of: "CREATE TABLE"))
        let pkg = try #require(text.range(of: "PACKAGE \"EMP_API\""))
        #expect(table.lowerBound < pkg.lowerBound && !text.contains("\"\(schema)\".\"DEPT\""))
        var o = ObjectExportOptions()
        o.layout = .filePerObject
        o.specAndBodyTogether = true
        #expect(try await ObjectExport.export(pick, options: o, in: s).map(\.name).sorted() == ["dept.sql", "emp_api.pck"])
        o.specAndBodyTogether = false
        o.includeOwner = true
        let files = try await ObjectExport.export(pick, options: o, in: s)
        #expect(files.map(\.name).sorted() == ["dept.sql", "emp_api.pkb", "emp_api.pks"])
        #expect(files.first { $0.name == "dept.sql" }?.content.contains("\"\(schema)\".\"DEPT\"") == true)
        // Uprawnienia tylko przy obiektach, które je mają (lista z TAB_PRIVS zamiast GET_DEPENDENT_DDL dla każdego — D164).
        _ = try await s.execute("grant select on dept to public")
        let withGrant: [ExportedFile]
        do { withGrant = try await ObjectExport.export(pick, options: o, in: s) } catch {
            _ = try? await s.execute("revoke select on dept from public")
            throw error
        }
        _ = try await s.execute("revoke select on dept from public")
        #expect(withGrant.first { $0.name == "dept.sql" }?.content.uppercased().contains("GRANT SELECT ON") == true)
        #expect(withGrant.first { $0.name == "emp_api.pks" }?.content.uppercased().contains("GRANT ") == false)
        #expect(await ObjectExport.grantedObjects(owner: schema, name: "EMP_API", in: s)?.isEmpty == true)
    }

    @Test("Eksport EMP_API plik na obiekt (D194): emp_api.pks i emp_api.pkb bez „/”; para otwarta w jednym oknie i skompilowana F8 — VALID")
    func exportPairCompiles() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "dev_test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        defer { Task { await ws.sessions.disconnectAll() } }
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        let schema = c.user.uppercased()
        let pick = try await ObjectExport.objects(owner: schema, in: s).filter { $0.name == "EMP_API" }
        #expect(Set(pick.map(\.type)) == [.package, .packageBody])
        var o = ObjectExportOptions()
        o.layout = .filePerObject
        let files = try await ObjectExport.export(pick, options: o, in: s)
        #expect(files.map(\.name).sorted() == ["emp_api.pkb", "emp_api.pks"])
        for f in files { #expect(!f.content.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "/" }, "\(f.name)") }
        // Jeden plik (skrypt SQL*Plus) — z „/” jak dotąd.
        let script = try await ObjectExport.export(pick, options: ObjectExportOptions(), in: s)
        #expect(script.first?.content.components(separatedBy: "\n").contains("/") == true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for f in files { try Data(f.content.utf8).write(to: dir.appendingPathComponent(f.name)) }
        let doc = try ws.openFile(dir.appendingPathComponent("emp_api.pkb"))
        #expect(doc.unitFiles.count == 2 && doc.programUnitTabs.count == 2 && doc.activeUnitTab == 1)
        ws.bind(doc, to: def.id)
        let r = try await ProgramCompiler.compile(doc, in: ws)
        #expect(r.ok && r.compiled == 2, "\(r.messages)")
        let (_, rows) = try await s.queryAll("select object_type, status from user_objects where object_name = 'EMP_API' order by object_type", limit: 10)
        #expect(rows.map { $0.map(\.displayText) } == [["PACKAGE", "VALID"], ["PACKAGE BODY", "VALID"]])
    }

    @Test("Porównanie schematów: tylko w źródle, różne, tylko w celu; skrypt wyrównujący wyrównuje kod")
    func compare() async throws {
        let c = TestDatabase.config!
        let sys = try await ODPISession.connect(target: ConnectionTarget(user: "SYSTEM", connectString: c.connectString),
                                                credentials: Credentials(password: c.systemPassword), options: ConnectOptions())
        defer { Task { _ = try? await sys.execute("drop user pelikan_cmp cascade"); await sys.close() } }
        _ = try? await sys.execute("drop user pelikan_cmp cascade")
        _ = try await sys.execute("create user pelikan_cmp no authentication quota 10m on users")
        let src = try await TestDatabase.connect()
        defer { Task { await src.close() } }
        _ = try await src.execute("create or replace function pelikan_cmp_f return number is begin return 1; end;")
        _ = try await src.execute("create or replace function pelikan_cmp_g return number is begin return 1; end;")
        _ = try await sys.execute("create or replace function pelikan_cmp.pelikan_cmp_f return number is begin return 2; end;")
        _ = try await sys.execute("create or replace function pelikan_cmp.pelikan_cmp_x return number is begin return 0; end;")
        let schema = c.user.uppercased()
        let objs = try await ObjectExport.objects(owner: schema, in: src).filter { $0.name.hasPrefix("PELIKAN_CMP") }
        var opt = CompareOptions()
        opt.dropExtra = true
        let diffs = try await ObjectCompare.compare(objs, source: src, targetOwner: "PELIKAN_CMP", target: sys, options: opt)
        #expect(diffs.first { $0.name == "PELIKAN_CMP_F" }?.status == .different)
        #expect(diffs.first { $0.name == "PELIKAN_CMP_G" }?.status == .onlySource)
        #expect(diffs.first { $0.name == "PELIKAN_CMP_X" }?.status == .onlyTarget)
        _ = try await sys.execute("alter session set current_schema = pelikan_cmp")
        for st in ScriptSplitter.split(ObjectCompare.script(diffs)) {
            var t = st.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !st.isPLSQL { while t.hasSuffix(";") { t.removeLast() } }
            if t.hasSuffix("/") { t.removeLast() }
            _ = try await sys.execute(t)
        }
        #expect(try await ObjectCompare.compare(objs, source: src, targetOwner: "PELIKAN_CMP", target: sys, options: opt).isEmpty)
        for f in ["pelikan_cmp_f", "pelikan_cmp_g"] { _ = try? await src.execute("drop function \(f)") }
    }
}
