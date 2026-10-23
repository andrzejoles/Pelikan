import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Atrapa interfejsu dla testów bez bazy.
@MainActor
final class FakeUI: UIServices {
    var answers: [Int?] = []
    var asked: [String] = []
    var openURLs: [URL] = []
    var saveURL: URL?
    func showError(_ message: String) {}
    func showCommandPalette() {}
    func ask(_ title: String, message: String, buttons: [String]) async -> Int? {
        asked.append(title)
        return answers.isEmpty ? nil : answers.removeFirst()
    }
    func showConnectionEditor(connectionID: UUID?) {}
    func showLogon() {}
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? { [:] }
    func copyToClipboard(_ text: String, html: String?) {}
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool { true }
    func showLargeDataEditor(_ model: LargeDataModel) {}
    func chooseFilesToOpen() async -> [URL] { openURLs }
    var textAnswer: String?
    func askText(_ title: String, message: String, defaultValue: String) async -> String? { textAnswer }
    func showFindReplace() {}
    var objectInfo: (String, [[String]])?
    func showObjectInfo(title: String, columns: [String], rows: [[String]]) { objectInfo = (title, rows) }
    var clientHelp: String?
    func showClientMissingHelp(_ message: String) { clientHelp = message }
    func showRecallStatement() {}
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? { saveURL }
}

@MainActor
@Suite("Pliki skryptów: kodowanie, otwieranie, zapis, zamykanie")
struct DocumentFilesTests {
    let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-files-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    @Test("UTF-8, UTF-8 z BOM, UTF-16 LE, Windows-1250 (polskie znaki), CRLF — odczyt i zapis bez zmian")
    func codec() {
        let text = "select 'Zażółć gęślą jaźń' from dual;\n"
        let utf8 = Data(text.utf8)
        #expect(TextFileCodec.decode(utf8).format.encoding == .utf8)
        let bom = Data([0xEF, 0xBB, 0xBF]) + utf8
        let (t1, f1) = TextFileCodec.decode(bom)
        #expect(t1 == text && f1.hasBOM)
        #expect(TextFileCodec.encode(t1, format: f1) == bom)
        let cp = text.replacingOccurrences(of: "\n", with: "\r\n").data(using: .windowsCP1250)!
        let (t2, f2) = TextFileCodec.decode(cp)
        #expect(t2 == text)
        #expect(f2.encoding == .windowsCP1250 && f2.lineEnding == .crlf)
        #expect(TextFileCodec.encode(t2, format: f2) == cp)
        let u16 = Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!
        #expect(TextFileCodec.decode(u16).text == text)
        // Znak spoza Windows-1250 — zapis wymaga UTF-8.
        #expect(TextFileCodec.encode("emoji 🐦", format: f2) == nil)
    }

    @Test("Otwarcie: typ okna z rozszerzenia, ponowne otwarcie aktywuje okno, puste okno SQL zastąpione, lista ostatnich")
    func open() throws {
        let ws = Workspace()
        _ = ws.newDocument(.sql)
        let sql = dir.appendingPathComponent("raport.sql")
        let pck = dir.appendingPathComponent("emp_api.pck")
        try "select 1 from dual;".write(to: sql, atomically: true, encoding: .utf8)
        try "create or replace package emp_api as end;".write(to: pck, atomically: true, encoding: .utf8)
        let d1 = try ws.openFile(sql)
        #expect(ws.documents.count == 1)                  // puste „Nowe” zastąpione
        #expect(d1.kind == .sql && d1.title == "raport.sql" && !d1.isModified)
        let d2 = try ws.openFile(pck)
        #expect(d2.kind == .program)
        #expect(try ws.openFile(sql).id == d1.id)
        #expect(ws.activeDocument?.id == d1.id)
        #expect(ws.settings.recentFiles.prefix(2) == [pck.path, sql.path])     // najnowszy pierwszy
    }

    @Test("Zapisz (nowe okno — wybór nazwy), Zapisz jako, zachowanie kodowania pliku")
    func save() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let doc = ws.newDocument(.sql)
        doc.text = "select 'ąę' from dual;"
        ui.saveURL = dir.appendingPathComponent("nowy.sql")
        try await ws.invoke("file.save")
        #expect(!doc.isModified && doc.fileURL?.lastPathComponent == "nowy.sql")
        #expect(try String(contentsOf: ui.saveURL!, encoding: .utf8) == "select 'ąę' from dual;")
        // Plik w Windows-1250 z CRLF zostaje w tym formacie.
        let legacy = dir.appendingPathComponent("stary.sql")
        try "select 'łódź' from dual;\r\n".data(using: .windowsCP1250)!.write(to: legacy)
        let d2 = try ws.openFile(legacy)
        d2.text += "-- zmiana\n"
        try await ws.invoke("file.save")
        let data = try Data(contentsOf: legacy)
        #expect(String(data: data, encoding: .windowsCP1250) == "select 'łódź' from dual;\r\n-- zmiana\r\n")
    }

    @Test("Zamknięcie zmienionego okna: Zapisz / Nie zapisuj / Anuluj; puste nowe okno bez pytania")
    func closePrompts() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        _ = ws.newDocument(.sql)
        try await ws.invoke("file.close")
        #expect(ui.asked.isEmpty && ws.documents.isEmpty)
        let doc = ws.newDocument(.sql)
        doc.text = "select 1 from dual"
        ui.answers = [2]                          // Anuluj
        await #expect(throws: CommandError.cancelledByUser) { try await ws.invoke("file.close") }
        #expect(ws.documents.count == 1)
        ui.answers = [1]                          // Nie zapisuj
        try await ws.invoke("file.close")
        #expect(ws.documents.isEmpty)
        let d2 = ws.newDocument(.sql)
        d2.text = "x"
        ui.answers = [0]                          // Zapisz → wybór nazwy
        ui.saveURL = dir.appendingPathComponent("zamkniety.sql")
        try await ws.invoke("file.close")
        #expect(FileManager.default.fileExists(atPath: ui.saveURL!.path))
        #expect(ws.documents.isEmpty)
    }

    @Test("Otwórz ponownie tylko z listy ostatnich plików")
    func reopen() async throws {
        let ws = Workspace()
        await #expect(throws: CommandError.self) { try await ws.invoke("file.reopen", CommandArguments(["path": .string("/etc/hosts")])) }
    }
}

@MainActor
@Suite("Zamykanie grup okien")
struct CloseManyTests {
    @Test("Zamknij pozostałe / z lewej / z prawej; zmienione okno pyta, Anuluj przerywa")
    func closeMany() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let docs = (0..<5).map { _ in ws.newDocument(.sql) }
        ws.activate(docs[2].id)
        try await ws.invoke("file.closeLeft")
        #expect(ws.documents.map(\.id) == [docs[2].id, docs[3].id, docs[4].id])
        docs[4].text = "zmiana"
        ui.answers = [2]                         // Anuluj przy zmienionym oknie
        await #expect(throws: CommandError.cancelledByUser) { try await ws.invoke("file.closeRight") }
        #expect(ws.documents.count == 2)          // docs[3] zamknięte, docs[4] zostało
        ui.answers = [1]
        try await ws.invoke("file.closeOthers")
        #expect(ws.documents.map(\.id) == [docs[2].id] && ws.activeDocumentID == docs[2].id)
        try await ws.invoke("file.closeWindow", CommandArguments(["document": .string(docs[2].id.description)]))
        #expect(ws.documents.isEmpty)
    }
}
