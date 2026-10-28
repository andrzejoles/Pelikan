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

    @Test("komenda wstążki bez wymaganego argumentu pyta użytkownika zamiast kończyć się błędem argumentu")
    func missingArgumentsAsk() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let ui = AskingUI()
        ws.ui = ui
        let doc = ws.newDocument(.sql, text: "select 1 from dual")
        ws.activate(doc.id)
        var failures: [String] = []
        let ids = Set(RibbonModel.expand(RibbonModel.tabs.flatMap(\.commands), in: ws.registry))
        for id in ids.sorted() where Self.contextOnly[id] == nil {
            guard let c = ws.registry.command(CommandID(rawValue: id)), c.descriptor.parameters.contains(where: \.required) else { continue }
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
