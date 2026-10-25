import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu: zapisuje otwierane adresy i aplikacje, odpowiada na pytania z „Nie pytaj więcej”.
@MainActor
final class ExternalToolsUI: UIServices {
    var answers: [Int?] = []
    var suppress = false
    var asked: [String] = []
    var opened: [URL] = []
    var openedIn: [(URL, String?)] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? {
        asked.append(title)
        return answers.isEmpty ? nil : answers.removeFirst()
    }
    func askWithSuppression(_ title: String, message: String, buttons: [String]) async -> (Int?, Bool) {
        (await ask(title, message: message, buttons: buttons), suppress)
    }
    func openURL(_ url: URL) { opened.append(url) }
    func openInApplication(_ file: URL, application: String?) { openedIn.append((file, application)) }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { [:] }
    func copyToClipboard(_ text: String, html: String?) {}
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { true }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { nil }
}

/// Zapis wywołań programu zewnętrznego (bez uruchamiania).
final class LaunchLog: @unchecked Sendable {
    var calls: [(String, [String])] = []
}

@MainActor
@Suite("Narzędzia zewnętrzne edytora, kopie zapasowe, odzyskiwanie, pytania „Nie pytaj więcej”, dokumenty")
struct EditorExternalToolsTests {
    @Test("Web Search: kodowanie tekstu w %s, tylko http(s), zaznaczenie albo słowo pod kursorem, wybór wyszukiwania")
    func webSearch() async throws {
        let g = WebSearch(name: "G", url: "https://example.invalid/s?q=%s&lang=pl")
        #expect(g.url(for: " dbms_output.put_line & a+b ")?.absoluteString == "https://example.invalid/s?q=dbms_output.put_line%20%26%20a%2Bb&lang=pl")
        #expect(WebSearch(name: "x", url: "file:///etc/passwd?%s").url(for: "a") == nil)
        #expect(WebSearch(name: "x", url: "https://example.invalid/q=").url(for: "ORA-01403")?.absoluteString == "https://example.invalid/q=ORA-01403")

        let ws = Workspace()
        let ui = ExternalToolsUI()
        ws.ui = ui
        ws.settings.webSearches = [g, WebSearch(name: "Drugie", url: "https://example.invalid/d?%s")]
        let doc = ws.newDocument(.sql, text: "select * from scott.emp")
        doc.selectedRange = 17..<17
        #expect(ws.searchText(in: doc) == "scott.emp")
        ui.answers = [1]
        try await ws.invoke("edit.webSearch")
        #expect(ui.opened.last?.absoluteString == "https://example.invalid/d?scott.emp")
        doc.selectedRange = 0..<6
        try await ws.invoke("edit.webSearch", CommandArguments(["engine": "g"]))
        #expect(ui.opened.last?.absoluteString == "https://example.invalid/s?q=select&lang=pl")
        await #expect(throws: (any Error).self) { try await ws.invoke("edit.webSearch", CommandArguments(["engine": "brak"])) }
    }

    @Test("Edytor zewnętrzny: okno bez pliku → plik 0600 w katalogu danych; zmiana pliku wczytana po powrocie")
    func externalEditor() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let ui = ExternalToolsUI()
        ws.ui = ui
        ws.settings.externalEditor = "Visual Studio Code"
        let doc = ws.newDocument(.sql, text: "select 1 from dual;")
        try await ws.invoke("edit.openInExternalEditor")
        let (url, app) = try #require(ui.openedIn.first)
        #expect(app == "Visual Studio Code" && url.path.hasPrefix(t.url.appendingPathComponent("External").path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect((attrs[.posixPermissions] as? Int) == 0o600 && written == "select 1 from dual;")
        #expect(ws.checkExternalEdits() == 0)
        try Data("select 2 from dual;".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        #expect(ws.checkExternalEdits() == 1 && doc.text == "select 2 from dual;" && doc.isModified)

        // Okno z plikiem: niezapisane zmiany zapisane przed przekazaniem; po zmianie — wczytane, okno niezmienione.
        let f = try t.file("skrypt.sql", "a")
        let fd = try ws.openFile(f)
        fd.text = "b"
        fd.isModified = true
        ws.settings.externalEditor = nil
        try await ws.invoke("edit.openInExternalEditor")
        #expect(ui.openedIn.last?.0.lastPathComponent == "skrypt.sql" && ui.openedIn.last?.1 == nil)
        let saved = try String(contentsOf: f, encoding: .utf8)
        #expect(saved == "b" && !fd.isModified)
        try Data("c".utf8).write(to: f)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: f.path)
        #expect(ws.checkExternalEdits() == 1 && fd.text == "c" && !fd.isModified)
    }

    @Test("Zewnętrzna przeglądarka różnic: dyrektywy %1–%4, pliki 0600, bez wbudowanej przeglądarki")
    func externalDiff() async throws {
        #expect(ExternalDiffTool.split(#"--diff "%1" '%2' --title=%3\ x """#) == ["--diff", "%1", "%2", "--title=%3 x", ""])
        #expect(ExternalDiffTool.split(ExternalDiffTool.join(["a b", #"c"d"#, "", "e"])) == ["a b", #"c"d"#, "", "e"])
        let tool = ExternalDiffTool(program: "/usr/bin/true", arguments: ["-L", "%3", "-L", "%4", "%1", "%2"])
        #expect(tool.expandedArguments(left: "/l", right: "/r", leftTitle: "A", rightTitle: "B") == ["-L", "A", "-L", "B", "/l", "/r"])

        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let log = LaunchLog()
        ws.launchProgram = { exe, args in log.calls.append((exe.path, args)) }
        let ui = ExternalToolsUI()
        ws.ui = ui
        ws.settings.externalDiff = tool
        let lf = try t.file("l.txt", "x\n"), rf = try t.file("r.txt", "y\n")
        try await ws.invoke("tools.compareFiles", CommandArguments(["left": .string(lf.path), "right": .string(rf.path)]))
        let call = try #require(log.calls.first)
        #expect(call.0 == "/usr/bin/true" && call.1.count == 6)
        let lt = try String(contentsOfFile: call.1[4], encoding: .utf8), rt = try String(contentsOfFile: call.1[5], encoding: .utf8)
        #expect(lt == "x\n" && rt == "y\n" && call.1[1] == "l.txt" && call.1[3] == "r.txt")
        let attrs = try FileManager.default.attributesOfItem(atPath: call.1[4])
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        ws.settings.externalDiff = ExternalDiffTool(program: "nie-ma-takiego-programu-pelikan")
        #expect(throws: (any Error).self) { try ws.openExternalDiff(ws.settings.externalDiff!, left: "", right: "", leftTitle: "", rightTitle: "") }
    }

    @Test("Kopia zapasowa plik.~ext przy zapisie (opcja); bez rozszerzenia — plik~")
    func backups() throws {
        #expect(FileBackup.backupURL(for: URL(fileURLWithPath: "/a/emp.sql")).path == "/a/emp.~sql")
        #expect(FileBackup.backupURL(for: URL(fileURLWithPath: "/a/makefile")).path == "/a/makefile~")
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let f = try t.file("emp.sql", "stara")
        let doc = try ws.openFile(f)
        doc.text = "nowa"
        try ws.save(doc, to: f)
        #expect(!FileManager.default.fileExists(atPath: t.url.appendingPathComponent("emp.~sql").path))
        ws.settings.backupOnSave = true
        doc.text = "najnowsza"
        try ws.save(doc, to: f)
        #expect(try String(contentsOf: t.url.appendingPathComponent("emp.~sql"), encoding: .utf8) == "nowa")
        #expect(try String(contentsOf: f, encoding: .utf8) == "najnowsza")
    }

    @Test("Odzyskiwanie: migawka niezapisanych okien, nieczyste zamknięcie → okna do przywrócenia; czyste — nic")
    func recovery() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        #expect(ws.recovery.begin() == nil)
        let a = ws.newDocument(.sql, text: "select 'niezapisane' from dual")
        a.isModified = true
        _ = ws.newDocument(.sql, text: "")
        ws.saveRecoverySnapshot()
        let attrs = try FileManager.default.attributesOfItem(atPath: t.url.appendingPathComponent("Recovery/windows.json").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        // Bez end(): drugi start widzi poprzednie uruchomienie jako nieczyste.
        let ws2 = Workspace(dataDirectory: t.url)
        let previous = try #require(ws2.recovery.begin())
        #expect(previous.documents.count == 1 && previous.documents[0].text == "select 'niezapisane' from dual")
        ws2.pendingRecovery = previous
        try await ws2.invoke("file.restoreRecovery")
        #expect(ws2.documents.contains { $0.text == "select 'niezapisane' from dual" } && ws2.pendingRecovery == nil)
        ws2.recovery.end()
        #expect(Workspace(dataDirectory: t.url).recovery.begin() == nil)
    }

    @Test("Nie pytaj więcej: zapamiętana odpowiedź zastępuje pytanie; anulowanie nie jest zapamiętywane; reset")
    func suppression() async throws {
        let ws = Workspace()
        let ui = ExternalToolsUI()
        ws.ui = ui
        ui.answers = [nil]
        ui.suppress = true
        #expect(await ws.askSuppressible(.moveToTrash, title: "T", message: "", buttons: ["Tak"]) == nil)
        #expect(ws.settings.suppressedDialogs.isEmpty)
        ui.answers = [0]
        #expect(await ws.askSuppressible(.moveToTrash, title: "T", message: "", buttons: ["Tak"]) == 0)
        #expect(ws.settings.suppressedDialogs[SuppressibleDialog.moveToTrash.rawValue] == 0)
        let count = ui.asked.count
        #expect(await ws.askSuppressible(.moveToTrash, title: "T", message: "", buttons: ["Tak"]) == 0 && ui.asked.count == count)
        ws.settings.suppressedDialogs = [:]
        ui.answers = [nil]
        ui.suppress = false
        #expect(await ws.askSuppressible(.moveToTrash, title: "T", message: "", buttons: ["Tak"]) == nil && ui.asked.count == count + 1)
        #expect(Set(SuppressibleDialog.allCases.map(\.rawValue)).count == SuppressibleDialog.allCases.count)
    }

    @Test("Dokumenty użytkownika: http(s) i istniejące pliki, inne schematy odrzucone; komenda otwiera wybrany")
    func documents() async throws {
        let t = try TempDirectory()
        let f = try t.file("notatki.txt", "x")
        #expect(UserDocument(title: "a", location: "https://example.invalid/doc").url != nil)
        #expect(UserDocument(title: "b", location: f.path).url == f)
        #expect(UserDocument(title: "c", location: "javascript:alert(1)").url == nil)
        #expect(UserDocument(title: "d", location: "/nie/ma/pliku").url == nil)
        let ws = Workspace()
        let ui = ExternalToolsUI()
        ws.ui = ui
        ws.settings.userDocuments = [UserDocument(title: "Standardy", location: f.path), UserDocument(title: "Wiki", location: "https://example.invalid/wiki")]
        try await ws.invoke("tools.documents", CommandArguments(["title": "wiki"]))
        #expect(ui.opened.last?.absoluteString == "https://example.invalid/wiki")
        ui.answers = [0]
        try await ws.invoke("tools.documents")
        #expect(ui.opened.last == f)
    }
}
