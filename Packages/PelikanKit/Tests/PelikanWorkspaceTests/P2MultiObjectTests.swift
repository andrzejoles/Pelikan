import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Wiele obiektów w Object Browserze — bez bazy (PD-OB-011)")
struct P2MultiObjectTests {
    @Test("Nazwy po przecinku (bieżący schemat bez kwalifikacji), DROP wg typu, lista obiektów z argumentu i błędny wpis")
    func names() async throws {
        let objs = [DBObject(owner: "HR", name: "EMP", type: .table), DBObject(owner: "SCOTT", name: "PKG", type: .packageBody)]
        #expect(MultiObjectCommands.commaSeparated(objs, currentSchema: "HR") == "emp, scott.pkg")
        #expect(MultiObjectCommands.dropStatement(objs[0]) == "DROP TABLE HR.EMP CASCADE CONSTRAINTS")
        #expect(MultiObjectCommands.dropStatement(objs[1]) == "DROP PACKAGE BODY SCOTT.PKG")
        let ws = Workspace()
        ws.selectedObjects = objs
        ws.selectedObject = objs[0]
        let r = try await ws.invoke("ob.copyNames", CommandArguments())
        #expect(r.value == .string("hr.emp, scott.pkg"))
        let r2 = try await ws.invoke("ob.copyNames", CommandArguments(["objects": .string("hr.dept:TABLE, hr.v1:view")]))
        #expect(r2.value == .string("hr.dept, hr.v1"))
        await #expect(throws: (any Error).self) { try await ws.invoke("ob.copyNames", CommandArguments(["objects": .string("dept")])) }
    }
}
