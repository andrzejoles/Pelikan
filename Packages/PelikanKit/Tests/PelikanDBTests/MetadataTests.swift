import Foundation
import PelikanDB
import PelikanODPI
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Metadane słownika na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct MetadataTests {
    func provider() throws -> (Workspace, MetadataProvider) {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        return (ws, ws.metadata()!)
    }

    @Test("Foldery wg wersji (MLE i domeny na 23ai+), obiekty schematu, niepoprawny pakiet, filtr nazw i Status=")
    func objects() async throws {
        let (ws, m) = try provider()
        let types = try await m.availableTypes()
        #expect(types.contains(.mleModule) && types.contains(.domain))
        let schema = try await m.currentSchema()
        let tables = try await m.objects(.table, owner: schema)
        #expect(Set(tables.map(\.name)).isSuperset(of: ["DEPT", "EMP", "DOCS", "BIG_ROWS"]))
        let bodies = try await m.objects(.packageBody, owner: schema)
        #expect(bodies.first { $0.name == "BROKEN_PKG" }?.isValid == false)
        #expect(try await m.objects(.table, owner: schema, filter: ObjectFilter("DE%, emp")).map(\.name).sorted() == ["DEPT", "EMP", "EMP_AUDIT"])
        #expect(try await m.objects(.packageBody, owner: schema, filter: ObjectFilter("status=invalid")).map(\.name) == ["BROKEN_PKG"])
        #expect(try await m.objects(.package, owner: schema, filter: ObjectFilter("source=raise_salary")).map(\.name).contains("EMP_API"))
        #expect(!(try await m.objects(.package, owner: schema, filter: ObjectFilter("source=raise_salary")).map(\.name).contains("BROKEN_PKG")))
        #expect(try await m.objects(.mleModule, owner: schema).map(\.name) == ["GREET_MOD"])
        #expect(try await m.objects(.domain, owner: schema).map(\.name) == ["EMAIL_D"])
        #expect(try await m.users().contains(schema))
        await ws.sessions.disconnectAll()
    }

    @Test("Elementy tabeli i pakietu: kolumny z typami, PK/FK, indeksy, wyzwalacz, podprogramy, zależności")
    func children() async throws {
        let (ws, m) = try provider()
        let schema = try await m.currentSchema()
        let emp = DBObject(owner: schema, name: "EMP", type: .table)
        let c = try await m.children(of: emp)
        #expect(c.contains { $0.kind == .column && $0.name == "EMPNO" && $0.detail.hasPrefix("NUMBER(6)") && $0.detail.contains("NOT NULL") })
        #expect(c.contains { $0.kind == .constraint && $0.detail.hasPrefix("PRIMARY KEY") })
        #expect(c.contains { $0.kind == .constraint && $0.detail.hasPrefix("FOREIGN KEY") })
        #expect(c.contains { $0.kind == .trigger && $0.name == "EMP_SAL_TRG" })
        #expect(c.contains { $0.kind == .referencedBy && $0.name.hasSuffix("EMP_API") })
        let pkg = try await m.children(of: DBObject(owner: schema, name: "EMP_API", type: .package))
        #expect(pkg.contains { $0.kind == .subprogram && $0.name == "RAISE_SALARY" })
        await ws.sessions.disconnectAll()
    }

    @Test("Źródło (CREATE OR REPLACE), DDL z DBMS_METADATA, właściwości, wyszukanie po nazwie, Recent")
    func sourceDDL() async throws {
        let (ws, m) = try provider()
        let schema = try await m.currentSchema()
        let spec = DBObject(owner: schema, name: "EMP_API", type: .package)
        let src = try await m.source(of: spec)
        #expect(src.uppercased().hasPrefix("CREATE OR REPLACE PACKAGE EMP_API"))
        let ddl = try await m.ddl(of: DBObject(owner: schema, name: "DEPT", type: .table))
        #expect(ddl.contains("CREATE TABLE") && ddl.contains("\"DEPT\"") && ddl.hasSuffix(";"))
        let props = try await m.properties(of: DBObject(owner: schema, name: "DEPT", type: .table))
        #expect(props.contains { $0.0 == "STATUS" && $0.1 == "VALID" })
        let found = try await m.find("emp_api")
        #expect(found?.type == .package)
        m.touch(spec)
        #expect(m.recent.first == spec)
        await ws.sessions.disconnectAll()
    }
}
