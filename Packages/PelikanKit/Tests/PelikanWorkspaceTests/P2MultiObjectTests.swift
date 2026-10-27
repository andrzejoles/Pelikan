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
        #expect(try MultiObjectCommands.dropStatement(objs[0]) == "DROP TABLE HR.EMP CASCADE CONSTRAINTS")
        #expect(try MultiObjectCommands.dropStatement(objs[0], cascadeConstraints: false) == "DROP TABLE HR.EMP")
        #expect(try MultiObjectCommands.dropStatement(objs[1]) == "DROP PACKAGE BODY SCOTT.PKG")
        #expect(try MultiObjectCommands.dropStatement(DBObject(owner: "PUBLIC", name: "DUAL2", type: .synonym)) == "DROP PUBLIC SYNONYM DUAL2")
        #expect(try MultiObjectCommands.dropStatement(DBObject(owner: "HR", name: "REMOTE.WORLD", type: .databaseLink)) == "DROP DATABASE LINK REMOTE.WORLD")
        #expect(try MultiObjectCommands.dropStatement(DBObject(owner: "SYS", name: "DATA_DIR", type: .directory)) == "DROP DIRECTORY DATA_DIR")
        #expect(throws: (any Error).self) { try MultiObjectCommands.dropStatement(DBObject(owner: "HR", name: "J", type: .job)) }
        let ws = Workspace()
        ws.selectedObjects = objs
        ws.selectedObject = objs[0]
        let r = try await ws.invoke("ob.copyNames", CommandArguments())
        #expect(r.value == .string("hr.emp, scott.pkg"))
        let r2 = try await ws.invoke("ob.copyNames", CommandArguments(["objects": .string("hr.dept:TABLE, hr.v1:view")]))
        #expect(r2.value == .string("hr.dept, hr.v1"))
        // Nazwy w cudzysłowie: wielkość liter zachowana w argumencie i w skopiowanym tekście (R6-09).
        let r3 = try await ws.invoke("ob.copyNames", CommandArguments(["objects": .string("HR.\"MyTab\":TABLE, \"Ab\".x:VIEW")]))
        #expect(r3.value == .string("hr.\"MyTab\", \"Ab\".x"))
        #expect(MultiObjectCommands.commaSeparated([DBObject(owner: "HR", name: "MixedCase", type: .table)], currentSchema: "HR") == "\"MixedCase\"")
        await #expect(throws: (any Error).self) { try await ws.invoke("ob.copyNames", CommandArguments(["objects": .string("dept")])) }
    }
}
