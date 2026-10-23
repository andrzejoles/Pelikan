import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Projekty na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ProjectTests {
    @Test("Build i Make (pominięte aktualne, błędy, zatrzymanie po błędzie), Find in Project, pulpit, zapis i odczyt")
    func project() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "t", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-prj-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "create or replace procedure pelikan_proj_p is begin null; end;\n/\n".write(to: dir.appendingPathComponent("src/p.prc"), atomically: true, encoding: .utf8)
        try "create or replace function pelikan_proj_f return number is begin return x; end;\n/\n".write(to: dir.appendingPathComponent("src/f.fnc"), atomically: true, encoding: .utf8)
        let url = dir.appendingPathComponent("demo.prj")
        try await ws.invoke("project.new", CommandArguments(["file": .string(url.path)]))
        ws.project?.items = [.file("src/p.prc"), .file("src/f.fnc", group: "Funkcje"), .object(DBObject(owner: c.user.uppercased(), name: "EMP_API", type: .packageBody)),
                             .note("TODO: pelikan_proj_p do przeglądu")]
        ws.project?.options.haltOnFirstError = false
        let build = try await ws.invoke("project.build")
        #expect(build.message?.contains("Skompilowano: 2") == true && build.message?.contains("błędy: 1") == true, "\(build.message ?? "")")
        #expect(ws.projectBuildResults.first { $0.title == "f.fnc" }?.messages.first?.contains("PELIKAN_PROJ_F") == true)
        let make = try await ws.invoke("project.make")
        #expect(make.message?.contains("pominięto: 2") == true, "\(make.message ?? "")")
        ws.project?.options.haltOnFirstError = true
        ws.project?.items.swapAt(0, 1)
        let halted = try await ws.invoke("project.build")
        #expect(halted.message?.contains("Skompilowano: 0") == true && ws.projectBuildResults.count == 1)
        let found = try await ws.invoke("project.find", CommandArguments(["text": "pelikan_proj_p"]))
        #expect(found.value?.arrayValue?.count == 2)
        _ = try ws.openFile(dir.appendingPathComponent("src/p.prc"))
        try await ws.invoke("project.saveDesktop")
        #expect(ws.project?.desktop.first?.path == "src/p.prc")
        try await ws.invoke("project.close")
        try await ws.invoke("project.open", CommandArguments(["file": .string(url.path)]))
        #expect(ws.project?.items.count == 4 && ws.project?.groups == ["Funkcje"] && ws.project?.lastBuild.isEmpty == false)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        for o in ["procedure pelikan_proj_p", "function pelikan_proj_f"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}
