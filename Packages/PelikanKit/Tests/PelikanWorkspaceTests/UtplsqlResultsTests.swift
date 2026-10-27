import Foundation
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("utPLSQL — wyniki i pokrycie bez bazy (UT-RES-001, UT-RES-002, UT-COV-001, UT-COV-002)")
struct UtplsqlResultsTests {
    @Test("R5-05: raport pokrycia HTML bez skryptów i zasobów z sieci, treść widoczna, kolory pokrycia lokalnie")
    func localCoverageDocument() {
        let a = "https://utplsql.github.io/utPLSQL-coverage-html/assets/"
        let html = "<!DOCTYPE html><html><head><title>Code coverage</title><script src='\(a)application.js'></script>"
            + "<link href='\(a)application.css' media='screen, print' rel='stylesheet' type='text/css'/><link rel=\"icon\" type=\"image/png\" href=\"\(a)favicon_red.png\" /></head>"
            + "<body><div id=\"loading\"><img src=\"\(a)loading.gif\" alt=\"loading\"/></div><div id=\"wrapper\" style=\"display:none;\">"
            + "<ol><li class=\"covered\" data-hits=\"1\"><code class=\"sql\">x := 1;</code></li></ol></div></body></html>"
        let doc = UtplsqlRunner.localCoverageDocument(html)
        #expect(!doc.contains("http") && !doc.lowercased().contains("<script") && !doc.contains("<link") && !doc.contains("display:none"))
        #expect(doc.contains("<div id=\"wrapper\">") && doc.contains("li.covered") && doc.contains("x := 1;"))
    }

    @Test("Porównanie: wartość skalarna i różnice wierszy kursora")
    func comparison() throws {
        let scalar = UtExpectation(description: "", message: "Actual: 2 (number) was expected to equal: 3 (number)", caller: "")
        let c = try #require(scalar.comparison)
        #expect(c.actual == "2 (number)" && c.expected == "3 (number)")
        let notNull = UtExpectation(description: "", message: "Actual: NULL (varchar2) was expected not to be null", caller: "")
        #expect(notNull.comparison?.actual == "NULL (varchar2)")
        let cursor = UtExpectation(description: "", message: """
            Actual: refcursor [ count = 2 ] was expected to equal: refcursor [ count = 2 ]
            Diff:
            Rows: [ 1 differences ]
              Row No. 2 - Actual:   <ENAME>FORD</ENAME>
              Row No. 2 - Expected: <ENAME>SCOTT</ENAME>
            """, caller: "")
        let r = try #require(cursor.comparison)
        #expect(r.actual == "Row No. 2:<ENAME>FORD</ENAME>" && r.expected == "Row No. 2:<ENAME>SCOTT</ENAME>")
        #expect(UtExpectation(description: "", message: "Some error", caller: "").comparison == nil)
    }

    @Test("Sortowanie drzewa: nazwa, czas malejąco, status (błędy najpierw), w głąb")
    func sorting() {
        func t(_ n: String, _ s: UtStatus, _ time: Double) -> UtNode {
            var x = UtNode(id: n, kind: .test, name: n, description: "", owner: "", objectName: "", procedureName: n)
            x.status = s
            x.executionTime = time
            return x
        }
        var suite = UtNode(id: "s", kind: .suite, name: "s", description: "", owner: "", objectName: "", procedureName: "")
        suite.children = [t("b", .success, 0.1), t("c", .error, 0.05), t("a", .failure, 0.3)]
        #expect(UtSortOrder.name.sorted([suite])[0].children!.map(\.name) == ["a", "b", "c"])
        #expect(UtSortOrder.time.sorted([suite])[0].children!.map(\.name) == ["a", "b", "c"])
        #expect(UtSortOrder.status.sorted([suite])[0].children!.map(\.name) == ["c", "a", "b"])
        #expect(UtSortOrder.execution.sorted([suite])[0].children!.map(\.name) == ["b", "c", "a"])
    }

    @Test("Sonar: linie częściowo pokryte; parametry include/exclude w wywołaniu")
    func partialAndOptions() {
        let xml = """
            <coverage version="1"><file path="package body pelikan_test.emp_api">
            <lineToCover lineNumber="3" covered="true"/>
            <lineToCover lineNumber="4" covered="true" branchesToCover="2" coveredBranches="1"/>
            <lineToCover lineNumber="5" covered="false"/></file></coverage>
            """
        let c = UtplsqlRunner.parseSonarCoverage(xml)["PACKAGE BODY PELIKAN_TEST.EMP_API"]
        #expect(c?.covered == [3, 4] && c?.partial == [4] && c?.uncovered == [5])
        #expect(UtplsqlRunner.coverageOptions(include: ["emp_api"], exclude: []) == ", a_include_objects => ut_varchar2_list('EMP_API')")
        #expect(UtplsqlRunner.coverageOptions(include: [], exclude: ["a", "b"]) == ", a_exclude_objects => ut_varchar2_list('A', 'B')")
        #expect(UtplsqlRunner.coverageOptions(include: [], exclude: []).isEmpty)
    }

    @Test("Skrypt CLI: użytkownik z $ i apostrofem nie jest rozwijany przez sh; PELIKAN_UT_CONNECT nadpisuje")
    func cliScriptQuoting() throws {
        let shell = UtplsqlRunner.cliScript(paths: ["APP$OWN"], user: "APP$OWN", connectString: "db:1521/o'k").shell
        // Tylko przypisania z prologu (bez uruchamiania sqlplus).
        let prolog = shell.split(separator: "\n").filter { $0.contains("CONNECT=") }.joined(separator: "\n")
        func connect(_ env: [String: String]) throws -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", prolog + "\nprintf %s \"$CONNECT\""]
            p.environment = env
            let out = Pipe()
            p.standardOutput = out
            try p.run()
            p.waitUntilExit()
            return String(decoding: (try? out.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)
        }
        #expect(try connect(["OWN": "x"]) == "APP$OWN@db:1521/o'k")
        #expect(try connect(["PELIKAN_UT_CONNECT": "u@d"]) == "u@d")
    }
}
