import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("SQL Window — wybór poleceń i tytuły kart")
struct SQLExecutorUnitTests {
    let script = "select 1 from dual;\nselect 2 from dual;\nupdate t set x = 1;"

    @Test("Hasło w poleceniu: CONNECT u/… i IDENTIFIED BY tak, CONNECT bez hasła i EZConnect z „/” po „@” nie")
    func passwordDetection() {
        #expect(SQLExecutor.containsPassword("connect app/haslo@db"))
        #expect(SQLExecutor.containsPassword("conn app/haslo"))
        #expect(SQLExecutor.containsPassword("alter user app identified by haslo"))
        #expect(!SQLExecutor.containsPassword("connect dev_agent_test"))
        #expect(!SQLExecutor.containsPassword("connect app@host:1521/svc"))
    }

    @Test("Zaznaczenie wykonuje tylko zaznaczony tekst (z przesunięciem pozycji)")
    func selection() {
        let s = SQLExecutor.statements(text: script, selection: 20..<38, scope: .standard, autoSelect: true)
        #expect(s.map(\.text) == ["select 2 from dual"])
        #expect(s[0].start == 20)
        #expect(s[0].line == 1)
    }

    @Test("Bez zaznaczenia: AutoSelect → polecenie pod kursorem; Ctrl+F8 → wszystkie (i odwrotnie)")
    func autoSelect() {
        #expect(SQLExecutor.statements(text: script, selection: 25..<25, scope: .standard, autoSelect: true).map(\.text) == ["select 2 from dual"])
        #expect(SQLExecutor.statements(text: script, selection: 25..<25, scope: .alternate, autoSelect: true).count == 3)
        #expect(SQLExecutor.statements(text: script, selection: 25..<25, scope: .standard, autoSelect: false).count == 3)
        #expect(SQLExecutor.statements(text: script, selection: 25..<25, scope: .alternate, autoSelect: false).map(\.text) == ["select 2 from dual"])
    }

    @Test("Tytuł karty: dyrektywa -- tab= z &Count albo „Select <tabela>”")
    func titles() {
        let s1 = ScriptSplitter.split("-- tab=Działy (&Count wierszy)\nselect * from dept")[0]
        #expect(SQLExecutor.tabTitle(for: s1, rowCount: 4) == "Działy (4 wierszy)")
        #expect(SQLExecutor.tabTitle(for: ScriptSplitter.split("SELECT e.* FROM emp e")[0]) == "Select emp")
        #expect(SQLExecutor.tabTitle(for: ScriptSplitter.split("update emp set sal = 1")[0]) == "Update emp")
        #expect(SQLExecutor.tabTitle(for: ScriptSplitter.split("create or replace package body p as begin null; end;\n/")[0]) == "Create p")
        #expect(SQLExecutor.directive("records", in: "-- Records=1000\nselect 1 from dual") == "1000")
    }

    @Test("Polecenia z hasłami nie trafiają do historii")
    func passwords() {
        let ws = Workspace()
        ws.recordHistory("alter user scott identified by tiger")
        ws.recordHistory("create database link l connect to u identified by p using 'x'")
        ws.recordHistory("select 1 from dual")
        #expect(ws.history.map(\.text) == ["select 1 from dual"])
    }

    @Test("Plik historii poleceń tylko dla właściciela (0600)")
    func historyPermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hist-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        ws.recordHistory("select 1 from dual")
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("history.json").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Czas wykonania: sekundy, powyżej 100 s jako hh:mm:ss")
    func timeFormat() {
        #expect(SQLExecutor.format(.milliseconds(1234)) == "1.234 s")
        #expect(SQLExecutor.format(.seconds(3725)) == "01:02:05")
    }
}
