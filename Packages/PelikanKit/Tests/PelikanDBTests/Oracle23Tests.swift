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

    @Test("Specyfikacja debugowania MLE i parsowanie wyniku")
    func mleDebugSpec() {
        #expect(MLEDebugger.spec(owner: "hr", module: "m", points: [.init(line: 3), .init(line: 7, watch: ["a\"b"])])
                == #"{"version":"1.0","debugpoints":[{"at":{"name":"HR.M","line":3},"actions":[{"type":"snapshot"}]},{"at":{"name":"HR.M","line":7},"actions":[{"type":"watch","id":"a\"b"}]}]}"#)
        let hits = MLEDebugger.parse(#"[[{"at":{"frameName":"calc","name":"HR.M","line":4},"values":{"a":20,"s":"t","o":{"k":1}}}]]"#)
        #expect(hits == [MLEDebugger.Hit(frame: "calc", line: 4, values: ["a": "20", "s": "\"t\"", "o": #"{"k":1}"#])])
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

    @Test("Debugowanie MLE po wykonaniu: migawka i obserwacja zmiennych w punkcie")
    func mleDebug() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let owner = try #require(try await s.scalar("select user from dual"))
        _ = try await s.execute(MLE.createModuleDDL(name: "pelikan_dbg", source: "export function calc(a) {\n  let x = a * 2;\n  let y = x + 1;\n  return y;\n}\n"))
        _ = try await s.execute("create or replace function pelikan_dbg_calc(a number) return number as mle module pelikan_dbg signature 'calc(number)';")
        let hits = try await MLEDebugger.run(owner: owner, module: "pelikan_dbg", points: [MLEDebugger.Point(line: 4)],
                                             call: "if pelikan_dbg_calc(20) <> 41 then raise_application_error(-20001, 'zły wynik'); end if;", in: s)
        #expect(hits.count == 1 && hits[0].frame == "calc" && hits[0].values["x"] == "40" && hits[0].values["a"] == "20")
        let watched = try await MLEDebugger.run(owner: owner, module: "pelikan_dbg", points: [MLEDebugger.Point(line: 4, watch: ["y"])],
                                                call: "dbms_output.put_line(pelikan_dbg_calc(1))", in: s)
        #expect(watched.first?.values["y"] == "3")
        // Błąd w kodzie wywołującym: debugowanie wyłączone, wyjątek przekazany.
        await #expect(throws: (any Error).self) {
            _ = try await MLEDebugger.run(owner: owner, module: "pelikan_dbg", points: [MLEDebugger.Point(line: 4)], call: "raise_application_error(-20002, 'test');", in: s)
        }
        #expect(try await s.scalar("select pelikan_dbg_calc(2) from dual") == "5")
        _ = try await s.execute("drop function pelikan_dbg_calc")
        _ = try await s.execute("drop mle module pelikan_dbg")
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

@Suite("ORDS: skrypty i wykrycie")
struct ORDSTests {
    @Test("Skrypty ENABLE_SCHEMA / ENABLE_OBJECT z cytowaniem")
    func scripts() {
        let s = ORDSTools.enableSchemaScript(schema: "hr", urlAlias: "kadry")
        #expect(s.contains("p_schema => 'HR'") && s.contains("p_url_mapping_pattern => 'kadry'") && s.contains("p_auto_rest_auth => true"))
        let o = ORDSTools.enableObjectScript(schema: "hr", object: "o'k", type: "package body")
        #expect(o.contains("p_object => 'O''K'") && o.contains("p_object_type => 'PACKAGE'") && o.contains("p_object_alias => 'o''k'"))
        #expect(ORDSTools.disableObjectScript(schema: "hr", object: "emp").contains("p_enabled => false"))
    }

    @Test("Baza testowa bez ORDS: wykrycie braku", .enabled(if: TestDatabase.isAvailable))
    func detect() async throws {
        let s = try await TestDatabase.connect()
        #expect(try await ORDSTools.isInstalled(s) == false)
        await s.close()
    }
}
