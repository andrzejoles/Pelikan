import Foundation
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Eksport i porównanie obiektów na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct ObjectExportTests {
    @Test("Eksport DDL: jeden plik w kolejności wykonalnej i plik na obiekt (pakiet razem albo .spc/.bdy)")
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
        #expect(try await ObjectExport.export(pick, options: o, in: s).map(\.name).sorted() == ["dept.sql", "emp_api.pck"])
        o.specAndBodyTogether = false
        o.includeOwner = true
        let files = try await ObjectExport.export(pick, options: o, in: s)
        #expect(files.map(\.name).sorted() == ["dept.sql", "emp_api.bdy", "emp_api.spc"])
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
        #expect(withGrant.first { $0.name == "emp_api.spc" }?.content.uppercased().contains("GRANT ") == false)
        #expect(await ObjectExport.grantedObjects(owner: schema, name: "EMP_API", in: s)?.isEmpty == true)
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
