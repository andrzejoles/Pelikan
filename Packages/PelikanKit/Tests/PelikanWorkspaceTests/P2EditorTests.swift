import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Edytor P2 — bez bazy (PD-PROG-013/015, PD-EDIT-018/020, PD-CA-011, PD-TPL-003, PD-FILE-001, PD-GRID-012, PD-PREF-005, UT-CA-002)")
struct P2EditorTests {
    /// Tekst ze znacznikiem kursora `|` → (tekst, pozycja UTF-16).
    func marked(_ s: String) -> (String, Int) {
        let r = (s as NSString).range(of: "|")
        return (s.replacingOccurrences(of: "|", with: ""), r.location)
    }

    func sub(_ text: String, _ r: Range<Int>) -> String { (text as NSString).substring(with: NSRange(location: r.lowerBound, length: r.count)) }

    @Test("Parametry kompilatora: ALTER SESSION tylko dla ustawionych, bezpiecznych wartości")
    func compilerOptions() {
        var o = CompilerOptions()
        #expect(o.statements(warnings: "") == [])
        #expect(o.statements(warnings: "ENABLE:ALL") == ["ALTER SESSION SET PLSQL_WARNINGS = 'ENABLE:ALL'"])
        o.optimizeLevel = 3
        o.codeType = "native"
        o.plscope = "identifiers:all"
        o.ccflags = "debug:TRUE, poziom:2"
        #expect(o.statements(warnings: "") == ["ALTER SESSION SET PLSQL_OPTIMIZE_LEVEL = 3", "ALTER SESSION SET PLSQL_CODE_TYPE = NATIVE",
                                               "ALTER SESSION SET PLSCOPE_SETTINGS = 'IDENTIFIERS:ALL'",
                                               "ALTER SESSION SET PLSQL_CCFLAGS = 'debug:TRUE, poziom:2'"])
        o.optimizeLevel = 7
        o.codeType = "x"
        o.ccflags = "a:1'; drop table t; --"
        #expect(o.statements(warnings: "ENABLE:ALL'; x") == ["ALTER SESSION SET PLSCOPE_SETTINGS = 'IDENTIFIERS:ALL'"])
    }

    @Test("Polecenia transakcyjne: COMMIT/ROLLBACK/SAVEPOINT na początku polecenia; ON COMMIT i ROLLBACK SEGMENT nie")
    func transactions() {
        let text = """
            begin
              update emp set sal = 1;
              savepoint s1;
              if x then rollback to savepoint s1; else commit; end if;
            exception when others then rollback;
            end;
            create global temporary table t (a number) on commit preserve rows;
            alter rollback segment r online;
            -- commit w komentarzu
            """
        let found = PairMatcher.transactionStatements(text).map { sub(text, $0).lowercased() }
        #expect(found == ["savepoint s1", "rollback to savepoint s1", "commit", "rollback"])
    }

    @Test("Wystąpienia nazwy pod kursorem i zaznaczonego słowa; słowa kluczowe, literały i komentarze pomijane")
    func occurrences() {
        let (text, o) = marked("declare v_su|m number; begin v_sum := 1; dbms_output.put_line(V_SUM || 'v_sum'); end; -- v_sum")
        let hits = PairMatcher.occurrences(text, selection: o..<o)
        #expect(hits.count == 3 && hits.allSatisfy { sub(text, $0).lowercased() == "v_sum" })
        let w = (text as NSString).range(of: "dbms_output")
        #expect(PairMatcher.occurrences(text, selection: w.location..<(w.location + w.length)).isEmpty)  // jedno wystąpienie
        let (t2, o2) = marked("sel|ect 1 from dual")
        #expect(PairMatcher.occurrences(t2, selection: o2..<o2).isEmpty)
    }

    @Test("INSERT ↔ VALUES: kolumna i odpowiadająca wartość (także wyrażenia z nawiasami)")
    func insertValues() {
        let (text, o) = marked("insert into emp (empno, en|ame, hiredate) values (1, upper('a, b'), to_date('2020', 'yyyy'));")
        #expect(PairMatcher.insertValuesPair(text, offset: o).map { sub(text, $0) } == ["ename", "upper('a, b')"])
        let (t2, o2) = marked("insert into emp (empno, ename, hiredate) values (1, 'x', to_date('2020', |'yyyy'));")
        #expect(PairMatcher.insertValuesPair(t2, offset: o2).map { sub(t2, $0) } == ["hiredate", "to_date('2020', 'yyyy')"])
        let (t3, o3) = marked("insert into emp (empno, ename) values (1|);")
        #expect(PairMatcher.insertValuesPair(t3, offset: o3).isEmpty)  // różna liczba elementów
    }

    @Test("Usuń następne słowo i pierwszy znak w linii")
    func editing() {
        let (text, o) = marked("select |  emp_name, sal from emp")
        let e = TextEditing.deleteNextWord(text, selection: o..<o)
        #expect(e.text == "select , sal from emp" && e.selection == o..<o)
        #expect(TextEditing.deleteNextWord("a|.b".replacingOccurrences(of: "|", with: ""), selection: 1..<1).text == "ab")
        let (t2, o2) = marked("x\n    begin|\n")
        let first = TextEditing.firstCharacterOnLine(t2, selection: o2..<o2)
        #expect(first.selection.lowerBound == 6)
        #expect(TextEditing.firstCharacterOnLine(t2, selection: 6..<6).selection.lowerBound == 2)
    }

    @Test("Code Hierarchy: zaznaczenie i przejście do poziomu ścieżki")
    func hierarchy() async throws {
        let ws = Workspace()
        let (text, o) = marked("create or replace package body p as\n  procedure a is\n  begin\n    nu|ll;\n  end;\nend;\n/\n")
        let doc = ws.newDocument(.program, text: text)
        doc.selectedRange = o..<o
        _ = try await ws.invoke("codeHierarchy.select", CommandArguments(["level": .int(1)]))
        #expect(sub(text, doc.selectedRange).contains("procedure a is") && sub(text, doc.selectedRange).contains("end;"))
        doc.selectedRange = o..<o
        _ = try await ws.invoke("codeHierarchy.goto", CommandArguments(["level": .int(0)]))
        #expect(sub(text, doc.selectedRange.lowerBound..<(doc.selectedRange.lowerBound + 1)).lowercased() == "p")
        doc.selectedRange = o..<o
        await #expect(throws: (any Error).self) { try await ws.invoke("codeHierarchy.select", CommandArguments(["level": .int(9)])) }
    }

    @Test("Szablony: edycja wbudowanego tworzy szablon użytkownika, zmiana nazwy i folderu, foldery puste, zmiana nazwy i usuwanie folderu")
    func templates() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tpl-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        let builtin = try #require(ws.templates.all.first { $0.isBuiltIn })
        _ = try await ws.invoke("templates.edit", CommandArguments(["template": .string(builtin.id), "text": .string("zmieniony")]))
        #expect(ws.templates.template(builtin.id)?.text == "zmieniony" && ws.templates.template(builtin.id)?.isBuiltIn == false)
        _ = try await ws.invoke("templates.edit", CommandArguments(["folder": .string("Moje"), "name": .string("a"), "text": .string("[x]")]))
        _ = try await ws.invoke("templates.edit", CommandArguments(["template": .string("Moje/a"), "folder": .string("Inne"), "name": .string("b")]))
        #expect(ws.templates.template("Moje/a") == nil && ws.templates.template("Inne/b")?.text == "[x]")
        _ = try await ws.invoke("templates.newFolder", CommandArguments(["folder": .string("Pusty")]))
        #expect(ws.templates.folders.contains("Pusty"))
        _ = try await ws.invoke("templates.renameFolder", CommandArguments(["folder": .string("Inne"), "name": .string("Nowe")]))
        #expect(ws.templates.template("Nowe/b") != nil)
        await #expect(throws: (any Error).self) {
            try await ws.invoke("templates.renameFolder", CommandArguments(["folder": .string("Nowe"), "name": .string("Pusty")]))
        }
        _ = try await ws.invoke("templates.deleteFolder", CommandArguments(["folder": .string("Nowe")]))
        #expect(ws.templates.template("Nowe/b") == nil && !ws.templates.folders.contains("Nowe"))
    }

    @Test("Szablony: „..”, „.” i pusta nazwa folderu nie usuwają ani nie przenoszą całego katalogu szablonów")
    func templateFolderTraversal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tpl-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        _ = try await ws.invoke("templates.edit", CommandArguments(["folder": .string("Moje"), "name": .string("a"), "text": .string("[x]")]))
        for bad in ["..", ".", "", " "] {
            await #expect(throws: (any Error).self) { try await ws.invoke("templates.deleteFolder", CommandArguments(["folder": .string(bad)])) }
            await #expect(throws: (any Error).self) {
                try await ws.invoke("templates.renameFolder", CommandArguments(["folder": .string(bad), "name": .string("Nowe")]))
            }
        }
        #expect(ws.templates.template("Moje/a")?.text == "[x]")
    }

    @Test("Migawka odzyskiwania przed wykonaniem: tylko z opcją, najwyżej jedna na 5 s")
    func recoveryOnExecute() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        let now = Date()
        #expect(!ws.saveRecoverySnapshotBeforeExecute(now: now))
        ws.settings.recoveryOnExecute = true
        #expect(ws.saveRecoverySnapshotBeforeExecute(now: now))
        #expect(!ws.saveRecoverySnapshotBeforeExecute(now: now.addingTimeInterval(2)))
        #expect(ws.saveRecoverySnapshotBeforeExecute(now: now.addingTimeInterval(6)))
    }

    @Test("Wysokość wierszy wg treści i ręcznie; ukrycie edytora okna SQL")
    func gridRows() async throws {
        let columns = [ColumnInfo(name: "A", type: .varchar2, typeName: "VARCHAR2(100)")]
        let g = ResultGridModel(columns: columns, resultSet: ResultSetID(1), session: RowsSession([[.text("jeden")], [.text("a\nb\nc")]]),
                                sql: "select a from t", format: ValueFormat())
        await g.fetchAll()
        #expect(GridAlign.rowLines(g) == 3 && GridAlign.rowLines(g, maxLines: 2) == 2)
        let ws = Workspace()
        let doc = ws.newDocument(.sql)
        _ = try await ws.invoke("sql.toggleEditor", CommandArguments())
        #expect(doc.editorHidden)
        _ = try await ws.invoke("sql.toggleEditor", CommandArguments())
        #expect(!doc.editorHidden)
    }

    @Test("Kolory czcionek: domyślnie systemowe; zapis i odczyt ustawień")
    func colors() throws {
        var s = PelikanWorkspace.Settings()
        #expect(s.editorColors.isSystem && s.gridColors.isSystem && s.browserColors.isSystem)
        s.gridColors.background = RGBColor(red: 0.1, green: 0.2, blue: 0.3)
        let back = try JSONDecoder().decode(PelikanWorkspace.Settings.self, from: JSONEncoder().encode(s))
        #expect(back.gridColors.background == RGBColor(red: 0.1, green: 0.2, blue: 0.3) && back.editorColors.isSystem)
    }

    @Test("Adnotacje utPLSQL: lista procedur, --%test bez --%suite, niesparowane konteksty")
    func annotations() {
        let spec = """
            create or replace package test_emp as
              --%beforeall(przygotuj, nie_ma, inny_pakiet.setup)
              --%context(grupa)
              --%test
              procedure t1;
              --%endcontext
              --%endcontext
              --%nieznana
              procedure przygotuj;
            end;
            """
        let p = UtplsqlExplorer.annotationProblems(in: spec)
        #expect(p.contains { $0.line == 2 && $0.message.contains("nie_ma") })
        #expect(!p.contains { $0.message.contains("przygotuj") || $0.message.contains("inny_pakiet") })
        #expect(p.contains { $0.line == 4 && $0.message.contains("--%suite") })
        #expect(p.contains { $0.line == 7 && $0.message.contains("--%endcontext") })
        #expect(p.contains { $0.line == 8 && $0.message.contains("nieznana") })
        #expect(UtplsqlExplorer.annotationProblems(in: "create package p as\n--%suite\n--%context\n--%test\nprocedure t;\nend;").contains { $0.message.contains("Brak --%endcontext") })
    }
}
