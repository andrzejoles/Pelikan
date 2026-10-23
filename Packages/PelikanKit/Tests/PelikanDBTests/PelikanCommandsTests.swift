import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Polecenia własne okna poleceń na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct PelikanCommandsTests {
    @Test("CD/DIR, EXPORT TABLES i OBJECTS, BEAUTIFY, ZIP, RECOMPILE, QUERYDATA, INFO, EDIT bez argumentu")
    func commands() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-cw-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "select 1 from dual".write(to: dir.appendingPathComponent("a.sql"), atomically: true, encoding: .utf8)
        let doc = ws.newDocument(.command)
        doc.connectionID = def.id
        let e = ws.sqlplusEngine(for: doc)
        let script = """
            cd \(dir.path)
            dir *.sql
            export tables file=dept.sql tables=dept create=y
            export objects file=obj.sql objects=EMP_API
            beautify a.sql
            zip pak.zip a.sql dept.sql
            recompile emp_api
            info
            querydata dept
            """
        let outcome = await e.run(script)
        let out = doc.console.map(\.text)
        #expect(outcome == .finished, "\(out.suffix(10))")
        #expect(!doc.console.contains { $0.kind == .error }, "\(doc.console.filter { $0.kind == .error }.map(\.text))")
        #expect(out.contains("a.sql"))
        let dept = try String(contentsOf: dir.appendingPathComponent("dept.sql"), encoding: .utf8).uppercased()
        #expect(dept.contains("CREATE TABLE") && dept.contains("INSERT INTO"))
        #expect(try String(contentsOf: dir.appendingPathComponent("obj.sql"), encoding: .utf8).uppercased().contains("PACKAGE \"EMP_API\""))
        #expect(try String(contentsOf: dir.appendingPathComponent("a.sql"), encoding: .utf8) != "select 1 from dual")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("pak.zip").path))
        #expect(out.contains { $0.hasPrefix("Użytkownik: \(c.user.uppercased())") })
        #expect(ws.documents.contains { $0.kind == .sql && $0.text.lowercased().contains("dept") })
        await ws.sessions.disconnectAll()
    }
}
