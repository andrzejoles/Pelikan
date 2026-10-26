import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Worksety bez utraty okien (D176, przegląd D182): start bez przywrócenia workseta, przełączanie z otwartą transakcją,
/// format plików, okno aktywne, nazwa „State”, migawka po awarii, nieczytelne pliki danych.
@MainActor
@Suite("Worksety: bezpieczeństwo okien i plików")
struct WorksetSafetyTests {
    /// Poprzednia sesja: okno bez pliku z niezapisanym tekstem w autozapisanym worksecie.
    func previousSession(_ t: TempDirectory) throws {
        let ws = Workspace(dataDirectory: t.url)
        let doc = ws.newDocument(.sql, text: "select 'z poprzedniej sesji' from dual")
        doc.isModified = true
        try ws.saveCurrentWorkset()
    }

    func texts(_ ws: Workspace, _ name: String) throws -> [String] {
        try #require(try ws.worksets.load(name)).documents.compactMap(\.text)
    }

    @Test("start z workset=Inny: okna nieprzywróconego workseta nie są nadpisywane pustym oknem (R3-01)")
    func startWithOtherWorkset() async throws {
        let t = try TempDirectory()
        try previousSession(t)
        let ws = Workspace(dataDirectory: t.url)
        ws.worksets.keepUnopened(try #require(try ws.worksets.load(ws.worksets.current)))
        ws.newDocument(.sql)   // puste okno SQL ze startu
        try await ws.switchWorkset(to: "Inny")
        #expect(try texts(ws, WorksetStore.defaultName) == ["select 'z poprzedniej sesji' from dual"])
        #expect(try #require(try ws.worksets.load(WorksetStore.defaultName)).documents.count == 1)
        // Powrót do workseta otwiera jego okna; potem zapis już ich nie dopisuje drugi raz.
        try await ws.switchWorkset(to: WorksetStore.defaultName)
        #expect(ws.documents.map(\.text) == ["select 'z poprzedniej sesji' from dual"])
        #expect(ws.worksets.unopened == nil)
        try ws.saveCurrentWorkset()
        #expect(try texts(ws, WorksetStore.defaultName).count == 1)
    }

    @Test("start z noloaddesktop i zwykłe zamknięcie: autozapis dopisuje nowe okna do zapisanych (R3-01)")
    func noLoadDesktopQuit() throws {
        let t = try TempDirectory()
        try previousSession(t)
        let ws = Workspace(dataDirectory: t.url)
        ws.worksets.keepUnopened(try #require(try ws.worksets.load(ws.worksets.current)))
        let doc = ws.newDocument(.sql, text: "select 'nowe' from dual")
        doc.isModified = true
        try ws.saveCurrentWorkset()
        try ws.saveCurrentWorkset()   // kolejny zapis w tej sesji też zachowuje stare okna
        #expect(try texts(ws, WorksetStore.defaultName) == ["select 'nowe' from dual", "select 'z poprzedniej sesji' from dual"])
    }

    @Test("przełączenie workseta z otwartą transakcją: anulowanie pytania zostawia okna i workset (R6-01)")
    func switchCancelledByTransaction() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let ui = FakeUI()
        ws.ui = ui
        ws.settings.logoffWithOpenTransaction = .ask
        let plain = ws.newDocument(.sql, text: "select 1 from dual")
        let tx = ws.newDocument(.sql, text: "update emp set sal = sal")
        tx.transactionOpen = true
        ui.answers = [2]   // Anuluj
        await #expect(throws: CommandError.self) { try await ws.switchWorkset(to: "B") }
        #expect(ws.worksets.current == WorksetStore.defaultName)
        #expect(ws.documents.map(\.id) == [plain.id, tx.id])
        #expect(ui.asked.count == 1)
    }

    @Test("anulowanie przy drugim oknie z transakcją: okno zamknięte wcześniej wraca z migawki (R6-01)")
    func switchCancelledReopensClosed() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let ui = FakeUI()
        ws.ui = ui
        ws.settings.logoffWithOpenTransaction = .ask
        let a = ws.newDocument(.sql, text: "update a set x = 1")
        a.isModified = true
        a.transactionOpen = true
        let b = ws.newDocument(.sql, text: "update b set x = 1")
        b.transactionOpen = true
        ui.answers = [0, 2]   // Zatwierdź pierwsze, Anuluj drugie
        await #expect(throws: CommandError.self) { try await ws.switchWorkset(to: "B") }
        #expect(ws.worksets.current == WorksetStore.defaultName)
        #expect(Set(ws.documents.map(\.text)) == ["update a set x = 1", "update b set x = 1"])
    }

    @Test("okno w trakcie wykonania blokuje przełączenie workseta; nic nie jest zamykane (R6-01)")
    func switchRefusedWhileExecuting() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let a = ws.newDocument(.sql, text: "select 1 from dual")
        let busy = ws.newDocument(.sql, text: "select count(*) from big")
        busy.isExecuting = true
        await #expect(throws: CommandError.self) { try await ws.switchWorkset(to: "B") }
        #expect(ws.documents.map(\.id) == [a.id, busy.id])
        #expect(ws.worksets.current == WorksetStore.defaultName)
    }

    @Test("zmieniony plik ISO-8859-2 z CRLF wraca z workseta z tym samym formatem; starszy workset — format z dysku (R6-04)")
    func fileFormatRestored() async throws {
        let t = try TempDirectory()
        let file = t.url.appendingPathComponent("aix.pc")
        try Data("/* zażółć */\r\nselect 1 from dual;\r\n".data(using: .isoLatin2)!).write(to: file)
        let ws = Workspace(dataDirectory: t.url)
        let doc = try ws.openFile(file)
        let format = doc.fileFormat
        #expect(format.encoding != .utf8 && format.lineEnding == .crlf)
        doc.text += "-- zmiana\n"
        doc.isModified = true
        try ws.saveCurrentWorkset()

        let back = Workspace(dataDirectory: t.url)
        let saved = try #require(try back.worksets.load(back.worksets.current))
        try await back.applyWorkset(saved)
        #expect(back.documents.first?.fileFormat == format && back.documents.first?.isModified == true)

        // Workset sprzed poprawki (bez pól formatu): format z pliku na dysku.
        var old = saved
        old.documents = old.documents.map { var e = $0; e.encoding = nil; e.bom = nil; e.lineEnding = nil; return e }
        let older = Workspace(dataDirectory: t.url)
        try await older.applyWorkset(old)
        #expect(older.documents.first?.fileFormat == format)
        let json = #"{"name":"X","documents":[{"kind":"sql","filePath":"/nie/ma.sql","text":"x","modified":true,"selectionStart":0,"selectionEnd":0}],"saved":0}"#
        #expect(try JSONDecoder().decode(Workset.self, from: Data(json.utf8)).documents.first?.fileFormat == nil)
    }

    @Test("okno aktywne po pominięciu brakującego pliku i konsoli usuniętego połączenia (R6-14)")
    func activeAfterSkipped() throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let entries = [
            WorksetDocument(kind: .sql, filePath: t.url.appendingPathComponent("brak.sql").path, modified: false, selectionStart: 0, selectionEnd: 0),
            WorksetDocument(kind: .sql, text: "pierwsze", modified: true, selectionStart: 0, selectionEnd: 0),
            WorksetDocument(kind: .sql, modified: false, selectionStart: 0, selectionEnd: 0, consoleConnectionID: UUID()),
            WorksetDocument(kind: .sql, text: "aktywne", modified: true, selectionStart: 0, selectionEnd: 0),
            WorksetDocument(kind: .sql, text: "ostatnie", modified: true, selectionStart: 0, selectionEnd: 0),
        ]
        let missing = ws.appendWorksetDocuments(Workset(name: "X", documents: entries, activeIndex: 3))
        #expect(missing.count == 1 && ws.documents.count == 3)
        #expect(ws.activeDocument?.text == "aktywne")
    }

    @Test("nazwa „State” w dowolnej wielkości liter odrzucona; plik stanu poza listą worksetów (R6-18)")
    func stateName() throws {
        for n in ["state", "State", "STATE"] { #expect(throws: CommandError.self) { try WorksetStore.fileName(n) } }
        #expect(try WorksetStore.fileName("Stan") == "Stan.json")
        let t = try TempDirectory()
        try t.file("Worksets/STATE.json", #"{"current":"Domyślny"}"#)
        try t.file("Worksets/Raporty.json", "{}")
        let store = WorksetStore(directory: t.url.appendingPathComponent("Worksets"), layoutURL: nil)
        #expect(store.names == ["Raporty"])
    }

    @Test("migawka po awarii obejmuje zmieniony diagram i notatnik bez tekstu (R3-15)")
    func recoveryDiagramNotebook() throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let d = ws.newDocument(.diagram)
        d.diagram.items = [DiagramItem(kind: .note, frame: DiagramRect(x: 0, y: 0, width: 10, height: 10))]
        d.isModified = true
        let n = ws.newDocument(.notebook)
        n.notebook.cells = [NotebookCell(kind: .sql, text: "select 1 from dual")]
        n.isModified = true
        ws.newDocument(.diagram)   // bez zmian — pomijany
        #expect(ws.recoverySnapshot().documents.map(\.kind) == [.diagram, .notebook])
    }

    @Test("nieczytelny connections.json: kopia .bad, komunikat, zapis nie niszczy oryginału (R6-11)")
    func damagedConnections() throws {
        let t = try TempDirectory()
        let url = try t.file("connections.json", #"{"version":1,"folders":[],"connections":[{"driver":"przyszły"}]}"#)
        let store = ConnectionStore(fileURL: url, secrets: MemorySecretStore())
        #expect(store.connections.isEmpty && store.loadProblem != nil)
        let bad = try #require(try FileManager.default.contentsOfDirectory(atPath: t.url.path).first { $0.hasPrefix("connections.json.bad-") })
        try store.upsert(ConnectionDefinition(name: "dev_nowe", target: ConnectionTarget(user: "u", connectString: "dev")))
        #expect(try String(contentsOf: t.url.appendingPathComponent(bad), encoding: .utf8).contains("przyszły"))
        #expect(ConnectionStore(fileURL: url, secrets: MemorySecretStore()).connections.map(\.name) == ["dev_nowe"])
    }

    @Test("nieczytelny plik workseta: kopia .bad i błąd zamiast cichego nadpisania (R6-11)")
    func damagedWorkset() throws {
        let t = try TempDirectory()
        try t.file("Worksets/Domyślny.json", "{ uszkodzony")
        let ws = Workspace(dataDirectory: t.url)
        #expect(throws: CommandError.self) { try ws.worksets.load(WorksetStore.defaultName) }
        let files = try FileManager.default.contentsOfDirectory(atPath: t.url.appendingPathComponent("Worksets").path)
        #expect(files.contains { $0.hasPrefix("Domyślny.json.bad-") } && !files.contains("Domyślny.json"))
        #expect(try ws.worksets.load(WorksetStore.defaultName) == nil)
    }
}
