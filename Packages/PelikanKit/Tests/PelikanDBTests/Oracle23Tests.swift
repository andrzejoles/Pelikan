import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@Suite("Dane przestrzenne i MLE bez bazy")
struct Oracle23OfflineTests {
    @Test("WKT: punkt, linia, wielokąt z otworem, multi i kolekcja")
    func wkt() {
        #expect(Spatial.parse("POINT (1 2)") == [Spatial.Shape(kind: .point, parts: [[(1, 2)]])])
        #expect(Spatial.parse("LINESTRING (0 0, 1 1, 2 0)").first?.parts.first?.count == 3)
        let poly = Spatial.parse("POLYGON ((0 0, 10 0, 10 10, 0 0), (2 2, 3 2, 3 3, 2 2))")
        #expect(poly.count == 1 && poly[0].kind == .polygon && poly[0].parts.count == 2)
        #expect(Spatial.parse("MULTIPOLYGON (((0 0, 1 0, 1 1, 0 0)), ((5 5, 6 5, 6 6, 5 5)))").count == 2)
        #expect(Spatial.parse("GEOMETRYCOLLECTION (POINT (1 1), LINESTRING (0 0, 1 1))").map(\.kind) == [.point, .line])
        #expect(Spatial.parse("bzdura").isEmpty)
    }

    @Test("DDL modułu i środowiska MLE")
    func mleDDL() {
        #expect(MLE.createModuleDDL(name: "my-mod", source: "export function f(){}", version: "1.0")
                == "create or replace mle module MYMOD language javascript version '1.0' as\nexport function f(){}")
        #expect(MLE.createEnvironmentDDL(name: "env1", imports: [("lib", "my_mod")]) == "create or replace mle env ENV1 imports ('lib' module MY_MOD)")
    }
}

@Suite("Widoki dualności, MLE i SDO na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized, .timeLimit(.minutes(3)))
struct Oracle23Tests {
    @Test("Widok dualności z DEPT i EMP: DDL, lista, dokumenty, struktura")
    func duality() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let owner = try #require(try await s.scalar("select user from dual"))
        let ddl = try await DualityViews.generateDDL(view: "dept_dv", owner: owner, rootTable: "DEPT", children: ["EMP"], in: s)
        #expect(ddl.contains("'_id' : r.DEPTNO") && ddl.contains("'emp' : [select json"))
        _ = try? await s.execute("drop view dept_dv")
        _ = try await s.execute(ddl)
        let views = try await DualityViews.list(owner: owner, in: s)
        let v = try #require(views.first { $0.name == "DEPT_DV" })
        #expect(v.rootTable == "DEPT" && v.allowInsert)
        let docs = try await DualityViews.documents(v, limit: 5, in: s)
        #expect(!docs.isEmpty && docs[0].contains("\"_id\""))
        let guide = try await DualityViews.dataGuide(v, in: s)
        #expect(guide.contains { $0.path.contains("emp") })
        _ = try await s.execute("drop view dept_dv")
    }

    @Test("Moduł MLE: utworzenie, lista, źródło, środowisko")
    func mle() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let owner = try #require(try await s.scalar("select user from dual"))
        _ = try await s.execute(MLE.createModuleDDL(name: "pelikan_mod", source: "export function twice(a) { return a * 2; }\n", version: "1.0"))
        _ = try await s.execute(MLE.createEnvironmentDDL(name: "pelikan_env", imports: [("twice", "pelikan_mod")]))
        let m = try #require(try await MLE.modules(owner: owner, in: s).first { $0.name == "PELIKAN_MOD" })
        #expect(m.language == "JAVASCRIPT" && m.version == "1.0")
        #expect(try await MLE.source(owner: owner, name: "PELIKAN_MOD", in: s).contains("twice"))
        #expect(try await MLE.environments(owner: owner, in: s).contains("PELIKAN_ENV"))
        _ = try await s.execute("drop mle env pelikan_env")
        _ = try await s.execute("drop mle module pelikan_mod")
    }

    @Test("SDO_GEOMETRY jako WKT z zapytania")
    func spatial() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let w = try await Spatial.wkt(query: "select sdo_geometry(2003, null, null, sdo_elem_info_array(1, 1003, 1), sdo_ordinate_array(0,0, 4,0, 4,3, 0,0)) g from dual;", column: "g", in: s)
        let text = try #require(w.first ?? nil)
        #expect(text.hasPrefix("POLYGON"))
        #expect(Spatial.parse(text).first?.parts.first?.count == 4)
    }
}
