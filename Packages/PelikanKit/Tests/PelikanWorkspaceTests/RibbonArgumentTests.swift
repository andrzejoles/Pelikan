import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Interfejs testu: zapamiętuje każde pytanie do użytkownika i odpowiada jak „Anuluj”.
@MainActor
private final class AskingUI: UIServices {
    var asked: [String] = []
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? { asked.append(title); return nil }
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
    func askWithSuppression(_ title: String, message: String, buttons: [String]) async -> (Int?, Bool) { asked.append(title); return (nil, false) }
    func askSecret(_ title: String, message: String, confirm: Bool) async -> String? { asked.append(title); return nil }
    func chooseValue(_ title: String, values: [String]) async -> String? { asked.append(title); return nil }
    func chooseDate(_ title: String, initial: OracleTimestamp?, withTime: Bool) async -> OracleTimestamp? { asked.append(title); return nil }
    func editTemplate(_ template: CodeTemplate, folders: [String]) async -> CodeTemplate? { asked.append("editTemplate"); return nil }
    func askTemplateValues(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { asked.append("templateValues"); return nil }
}

/// Przycisk wstążki wywołuje komendę bez argumentów (zgłoszenia #111, #112: „Wstaw snippet” i „Wstaw szablon” kończyły
/// się „Nieprawidłowy argument”). Komenda wstążki z parametrami wymaganymi musi o brakujący zapytać użytkownika
/// (lista, pole tekstowe, wybór pliku) albo odmówić z innego powodu (brak okna, połączenia) — nie z braku argumentu.
@MainActor
@Suite("Wstążka: komendy bez argumentów")
struct RibbonArgumentTests {
    /// Komendy, które bez argumentu nie mają czego zapytać (wartość wynika z miejsca w interfejsie: przycisk na
    /// elemencie listy, wiersz siatki) — z uzasadnieniem.
    static let contextOnly: [String: String] = [:]

    /// Komendy wstążki, które miały parametr wymagany, a teraz bez argumentu pytają albo biorą zaznaczenie (#111, #112
    /// i następne) — sprawdzane dalej, choć parametr nie jest już `required`.
    static let askWhenMissing: Set<String> = [
        "edit.insertSnippet", "edit.insertTemplate", "connection.newFolder", "fb.newFile", "fb.newFolder", "fb.open", "fb.rename",
        "fb.trash", "fb.removeLocation", "file.encoding", "file.openWithConnection", "grid.copyAs", "grid.numberLayout",
        "ob.generateCode", "project.new", "project.open", "templates.delete", "templates.deleteFolder", "templates.renameFolder",
        "testManager.run", "tools.importMLEModule", "transfer.run",
    ]

    @Test("komenda wstążki bez wymaganego argumentu pyta użytkownika zamiast kończyć się błędem argumentu")
    func missingArgumentsAsk() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = AskingUI()
        ws.ui = ui
        let doc = ws.newDocument(.sql, text: "select 1 from dual")
        ws.activate(doc.id)
        var failures: [String] = []
        let ids = Set(RibbonModel.expand(RibbonModel.tabs.flatMap(\.commands), in: ws.registry))
        #expect(Self.askWhenMissing.subtracting(ids).isEmpty, "poza wstążką: \(Self.askWhenMissing.subtracting(ids).sorted())")
        for id in ids.sorted() where Self.contextOnly[id] == nil {
            guard let c = ws.registry.command(CommandID(rawValue: id)),
                  Self.askWhenMissing.contains(id) || c.descriptor.parameters.contains(where: \.required) else { continue }
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
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
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
    func chooseValue(_ title: String, values: [String]) async -> String? {
        offered = values
        return values.first { $0.contains(choice) }
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
}
