import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Interfejs testu: zapamiętuje każde pytanie do użytkownika i odpowiada jak „Anuluj”.
@MainActor
private final class AskingUI: UIServices {
    var asked: [String] = []
    var messages: [String] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { asked.append(title); messages.append(message); return nil }
    func showConnectionEditor(connectionID: UUID?) { asked.append("connectionEditor") }
    func showLogon() { asked.append("logon") }
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { asked.append("variables"); return nil }
    func copyToClipboard(_ text: String, html: String?) {}
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { asked.append("saveFile"); return false }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { asked.append("open"); return [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { asked.append(title); return nil }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { asked.append("saveURL"); return nil }
    func printHTML(title: String, html: String) {}
    func askWithSuppression(_ title: String, message: String, buttons: [String]) async -> (Int?, Bool) {
        asked.append(title)
        messages.append(message)
        return (nil, false)
    }
    func askSecret(_ title: String, message: String, confirm: Bool) async -> String? { asked.append(title); return nil }
    func chooseValue(_ title: String, values: [String]) async -> String? { asked.append(title); return nil }
    func chooseDate(_ title: String, initial: OracleTimestamp?, withTime: Bool) async -> OracleTimestamp? { asked.append(title); return nil }
    func editTemplate(_ template: CodeTemplate, folders: [String]) async -> CodeTemplate? { asked.append("editTemplate"); return nil }
    func askTemplateValues(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { asked.append("templateValues"); return nil }
}

/// Przycisk wstążki wywołuje komendę bez argumentów (zgłoszenia #111, #112: „Wstaw snippet” i „Wstaw szablon” kończyły
/// się „Nieprawidłowy argument”). Każda komenda wstążki z parametrami (wymaganymi albo nie — zdjęcie `required` nie
/// wyłącza kontroli) musi o brakujący argument zapytać użytkownika (lista, pole tekstowe, wybór pliku), wziąć wartość
/// domyślną albo odmówić z innego powodu (brak okna, połączenia) — nie z braku argumentu. Parametry opcjonalne
/// z wartością domyślną (np. „domyślnie zaznaczenie”) przechodzą same: komenda bez nich nie zgłasza błędu argumentu.
@MainActor
@Suite("Wstążka: komendy bez argumentów")
struct RibbonArgumentTests {
    /// Komendy, które bez argumentu nie mają czego zapytać (wartość wynika z miejsca w interfejsie: przycisk na
    /// elemencie listy, wiersz siatki) — z uzasadnieniem.
    static let contextOnly: [String: String] = [:]

    /// Komendy wstążki, które miały parametr wymagany, a teraz bez argumentu pytają albo biorą zaznaczenie (#111, #112
    /// i następne) — muszą zostać na wstążce i przy wywołaniu bez argumentu pytać albo odmówić z komunikatem.
    static let askWhenMissing: Set<String> = [
        "edit.insertSnippet", "edit.insertTemplate", "file.newFromTemplate", "connection.newFolder", "fb.newFile", "fb.newFolder",
        "fb.open", "fb.rename", "fb.trash", "fb.removeLocation", "file.encoding", "file.openWithConnection", "grid.copyAs",
        "grid.numberLayout", "ob.generateCode", "project.new", "project.open", "templates.delete", "templates.deleteFolder",
        "templates.renameFolder", "testManager.run", "tools.importMLEModule", "transfer.run",
    ]

    @Test("komenda wstążki z parametrami bez argumentów pyta użytkownika zamiast kończyć się błędem argumentu")
    func missingArgumentsAsk() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = AskingUI()
        ws.ui = ui
        let doc = ws.newDocument(.sql, text: "select 1 from dual")
        ws.activate(doc.id)
        var failures: [String] = []
        var checked = Set<String>()
        let ids = Set(RibbonModel.expand(RibbonModel.tabs.flatMap(\.commands), in: ws.registry))
        #expect(Self.askWhenMissing.subtracting(ids).isEmpty, "poza wstążką: \(Self.askWhenMissing.subtracting(ids).sorted())")
        for id in ids.sorted() where Self.contextOnly[id] == nil {
            guard let c = ws.registry.command(CommandID(rawValue: id)), !c.descriptor.parameters.isEmpty else { continue }
            checked.insert(id)
            ui.asked = []
            do {
                _ = try await c.run(CommandContext(workspace: ws, invoker: .user, arguments: .empty))
            } catch let e as CommandError {
                switch e {
                case .missingArgument, .invalidArgument:
                    if ui.asked.isEmpty { failures.append("\(id): \(e)") }
                default: break
                }
            } catch {}
            if ws.activeDocument == nil { ws.activate(ws.newDocument(.sql, text: "select 1 from dual").id) }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(Self.askWhenMissing.isSubset(of: checked), "\(Self.askWhenMissing.subtracting(checked).sorted())")
    }

    @Test("etykiety listy wyboru bez powtórzeń — wybór powtórzonej etykiety daje jej wartość")
    func uniqueLabels() {
        #expect(CommandContext.uniqueLabels(["a", "b", "a", "a"]) == ["a", "b", "a (2)", "a (3)"])
        #expect(CommandContext.uniqueLabels(["a (2)", "a", "a"]) == ["a (2)", "a", "a (3)"])
    }
}

/// Interfejs testu z odpowiedziami: wybiera etykietę zawierającą `choice`, wpisuje `text`.
@MainActor
private final class AnsweringUI: UIServices {
    var choice = ""
    var text: String?
    var offered: [String] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { 0 }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { nil }
    func copyToClipboard(_ text: String, html: String?) {}
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { false }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { [] }
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { text }
    func showFindReplace() {}
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {}
    func showClientMissingHelp(_ message: String) {}
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { nil }
    func printHTML(title: String, html: String) {}
    var chooseCount = 0
    var variables: [String: VariableValue]?
    func chooseValue(_ title: String, values: [String]) async -> String? {
        offered = values
        chooseCount += 1
        return values.first { $0 == choice } ?? values.first { $0.contains(choice) }
    }
    func askTemplateValues(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? {
        chooseCount += 1
        return variables
    }
}

@MainActor
@Suite("Wstążka: argumenty z wyboru i zaznaczenia")
struct RibbonChoiceTests {
    func run(_ ws: Workspace, _ id: String, invoker: Invoker = .user) async throws -> CommandResult {
        let c = try #require(ws.registry.command(CommandID(rawValue: id)))
        return try await c.run(CommandContext(workspace: ws, invoker: invoker, arguments: .empty))
    }

    @Test("wybór etykiety z listy daje wartość; agent bez argumentu nadal dostaje błąd argumentu")
    func labelsMapToValues() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = AnsweringUI()
        ws.ui = ui
        ui.choice = NumberLayout.thousands.displayName
        _ = try await run(ws, "grid.numberLayout")
        #expect(ws.settings.gridNumberLayout == .thousands)
        #expect(ui.offered == NumberLayout.allCases.map(\.displayName))

        let doc = ws.newDocument(.sql, text: "select 1 from dual")
        ws.activate(doc.id)
        ui.choice = "Windows-1250"
        _ = try await run(ws, "file.encoding")
        #expect(doc.fileFormat.encoding == TextFileCodec.encoding(named: "Windows-1250"))

        await #expect(throws: CommandError.missingArgument("layout")) {
            _ = try await run(ws, "grid.numberLayout", invoker: .agent(sessionID: "s", agentName: "a"))
        }
    }

    @Test("Przeglądarka plików: zaznaczenie jest domyślnym argumentem, bez zaznaczenia — komunikat, co zaznaczyć")
    func fileBrowserSelection() async throws {
        let t = try TempDirectory()
        let f = try t.file("a.sql", "select 1 from dual;")
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = AnsweringUI()
        ws.ui = ui

        await #expect(throws: CommandError.notAvailable(L10n.tr("Zaznacz plik albo katalog w Przeglądarce plików"))) {
            _ = try await run(ws, "fb.trash")
        }

        ws.fileBrowser.selectedURL = f
        ui.text = "nowy"
        let made = try await run(ws, "fb.newFolder")
        #expect(made.value == .string(t.url.appendingPathComponent("nowy").standardizedFileURL.path))

        ui.text = "b.sql"
        _ = try await run(ws, "fb.rename")
        let renamed = t.url.appendingPathComponent("b.sql").standardizedFileURL
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(ws.fileBrowser.selectedURL?.standardizedFileURL == renamed)

        // Agent i skrypty nie korzystają z zaznaczenia panelu.
        await #expect(throws: CommandError.missingArgument("path")) {
            _ = try await run(ws, "fb.rename", invoker: .agent(sessionID: "s", agentName: "a"))
        }
    }

    @Test("szablony użytkownika i ich foldery: wybór z listy; bez nich — odmowa zamiast błędu argumentu")
    func templateChoices() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url, secrets: MemorySecretStore(), drivers: [:])
        let ui = AnsweringUI()
        ws.ui = ui
        await #expect(throws: CommandError.notAvailable(L10n.tr("Brak folderów szablonów użytkownika"))) {
            _ = try await run(ws, "templates.deleteFolder")
        }
        try ws.templates.save(CodeTemplate(folder: "Moje", name: "pętla", text: "loop null; end loop;"))
        ui.choice = "Moje/pętla"
        _ = try await run(ws, "templates.delete")
        #expect(ws.templates.template("Moje/pętla") == nil)
        #expect(ws.templates.userFolders == ["Moje"])
    }

    @Test("Wstaw snippet i Wstaw szablon: wybór z listy wstawia wybrany fragment w miejscu kursora")
    func insertChosenSnippetAndTemplate() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url, secrets: MemorySecretStore(), drivers: [:])
        let ui = AnsweringUI()
        ws.ui = ui
        try ws.snippets.save(Snippet(category: "Moje", name: "licznik", text: "select count(*) from dual"))
        try ws.templates.save(CodeTemplate(folder: "Moje", name: "pętla", text: "loop null; end loop;"))
        let doc = ws.newDocument(.sql, text: "")
        ws.activate(doc.id)
        ui.choice = "Moje/licznik"
        _ = try await run(ws, "edit.insertSnippet")
        #expect(doc.text == "select count(*) from dual")
        #expect(ui.offered.contains("Moje/licznik") && ui.offered.count == ws.snippets.all.count)
        doc.text = ""
        doc.selectedRange = 0..<0
        ui.choice = "Moje/pętla"
        _ = try await run(ws, "edit.insertTemplate")
        #expect(doc.text == "loop null; end loop;")
        #expect(ui.offered.contains("Moje/pętla"))
    }

    @Test("makro nagrywa argumenty wybrane w oknie — odtworzenie nie pyta ponownie")
    func macroRecordsResolvedArguments() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url, secrets: MemorySecretStore(), drivers: [:])
        let ui = AnsweringUI()
        ws.ui = ui
        try ws.snippets.save(Snippet(category: "Moje", name: "x", text: "X"))
        try ws.templates.save(CodeTemplate(folder: "Moje", name: "zmienna", text: "select [kolumna] from dual"))
        let doc = ws.newDocument(.sql, text: "")
        ws.activate(doc.id)
        ws.toggleMacroRecording()
        ui.choice = "Moje/x"
        try await ws.invoke("edit.insertSnippet")
        ui.choice = "Windows-1250"
        try await ws.invoke("file.encoding")
        ui.choice = "Moje/zmienna"
        ui.variables = ["kolumna": .text("dummy")]
        try await ws.invoke("edit.insertTemplate")
        ws.toggleMacroRecording()
        let macro = try #require(ws.currentMacro)
        #expect(macro.steps == [
            .command("edit.insertSnippet", CommandArguments(["id": .string("Moje/x")])),
            .command("file.encoding", CommandArguments(["encoding": .string("Windows-1250")])),
            .command("edit.insertTemplate", CommandArguments(["template": .string("Moje/zmienna"), "values": .object(["kolumna": .string("dummy")])])),
        ])
        let recorded = doc.text
        #expect(recorded == "Xselect dummy from dual")
        ui.chooseCount = 0
        ui.choice = "—"
        try await ws.play(macro)
        #expect(ui.chooseCount == 0)
        #expect(doc.text == recorded + recorded)
    }

    @Test("Rekord: przełącza widok karty wyniku (wł./wył.); dane rekordu bez zmiany widoku nie trafiają do makra")
    func toggleRecordView() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.sql, text: "select * from t")
        ws.activate(doc.id)
        let g = ResultGridModel(columns: [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER")], resultSet: ResultSetID(1),
                                session: RowsSession([[.number("1")], [.number("2")]]), sql: "select * from t", format: ValueFormat())
        await g.fetchAll()
        let tab = ResultTab(title: "t", statementRange: 0..<15, grid: g)
        doc.results = [tab]
        doc.activeResultID = tab.id
        #expect(!tab.showsRecord)
        ws.toggleMacroRecording()
        try await ws.invoke("grid.toggleRecordView")
        #expect(tab.showsRecord)
        let fields = try await ws.invoke("grid.recordView")
        #expect(fields.value?.arrayValue?.count == 1 && tab.showsRecord)
        try await ws.invoke("grid.toggleRecordView")
        #expect(!tab.showsRecord)
        ws.toggleMacroRecording()
        #expect(ws.currentMacro?.steps == [.command("grid.toggleRecordView", .empty), .command("grid.toggleRecordView", .empty)])
        #expect(ws.registry.command("grid.recordView")?.descriptor.effect == CommandEffect.none)
    }

    @Test("Przeglądarka plików: zaznaczenie niewidocznego panelu nie jest argumentem; Kosz z zaznaczenia pyta zawsze, z pełną ścieżką")
    func fileBrowserVisibilityAndTrash() async throws {
        let t = try TempDirectory()
        let f = try t.file("a.sql", "select 1 from dual;")
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = AskingUI()
        ws.ui = ui
        ws.fileBrowser.selectedURL = f
        // Zwinięta lewa kolumna albo inna karta — zaznaczenie panelu nie jest używane.
        ws.fileBrowser.isPaneVisible = { false }
        await #expect(throws: CommandError.notAvailable(L10n.tr("Zaznacz plik albo katalog w Przeglądarce plików"))) {
            _ = try await run(ws, "fb.trash")
        }
        #expect(ui.asked.isEmpty)
        ws.fileBrowser.isPaneVisible = { true }
        // Wyłączone potwierdzenie Kosza nie dotyczy elementu z zaznaczenia.
        ws.settings.suppressedDialogs[SuppressibleDialog.moveToTrash.rawValue] = 0
        await #expect(throws: CommandError.cancelledByUser) { _ = try await run(ws, "fb.trash") }
        #expect(ui.asked == [L10n.tr("Przenieść do Kosza?")])
        #expect(ui.messages == [(f.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath])
        #expect(FileManager.default.fileExists(atPath: f.path))
    }

    @Test("Nowy folder połączeń: pusta nazwa w oknie to rezygnacja")
    func emptyConnectionFolderName() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = AnsweringUI()
        ws.ui = ui
        ui.text = "  "
        await #expect(throws: CommandError.cancelledByUser) { _ = try await run(ws, "connection.newFolder") }
        #expect(ws.connections.folders.isEmpty)
    }
}
