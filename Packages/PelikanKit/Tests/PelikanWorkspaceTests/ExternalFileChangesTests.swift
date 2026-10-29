import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Pliki okien zmienione przez inny program (D197): wykrywanie przy aktywacji, touch bez zmiany treści, para
/// specyfikacja/ciało, plik usunięty, preferencje, „Zachowaj moje zmiany”, komenda file.reload.
@MainActor
@Suite("Pliki zmienione na dysku przez inny program")
struct ExternalFileChangesTests {
    let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-ext-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func write(_ text: String, _ name: String) throws -> URL {
        let u = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: u)
        return u
    }

    func text(_ url: URL) throws -> String { TextFileCodec.decode(try Data(contentsOf: url)).text }

    @Test("Okno bez zmian: pytanie „Wczytaj ponownie / Zostaw”; Zostaw — bez ponownego pytania do następnej zmiany")
    func unmodifiedWindow() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "a.sql")
        let doc = try ws.openFile(u)
        #expect(await ws.checkExternalChanges(of: doc) == 0 && ui.asked.isEmpty)
        try Data("select 2 from dual;\n".utf8).write(to: u)
        ui.answers = [1]                                     // Zostaw
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(ui.asked.count == 1 && ui.asked[0].contains("a.sql") && doc.text == "select 1 from dual;\n")
        #expect(await ws.checkExternalChanges(of: doc) == 0 && ui.asked.count == 1)
        try Data("select 3 from dual;\n".utf8).write(to: u)
        ui.answers = [0]                                     // Wczytaj ponownie
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(doc.text == "select 3 from dual;\n" && !doc.isModified)
        // Własny zapis nie jest zmianą z zewnątrz.
        doc.text += "-- x\n"
        try await ws.invoke("file.save")
        #expect(await ws.checkExternalChanges(of: doc) == 0 && ui.asked.count == 2)
    }

    @Test("Touch bez zmiany treści — bez pytania; preferencja wyłączona — bez sprawdzania; tryb skryptu — bez pytań")
    func touchAndPreferences() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "t.sql")
        let doc = try ws.openFile(u)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: u.path)
        #expect(await ws.externalChanges(of: doc).isEmpty)
        #expect(doc.diskStamps[u.standardizedFileURL]?.modified == Date(timeIntervalSince1970: 1_000_000_000))
        try Data("select 2 from dual;\n".utf8).write(to: u)
        ws.settings.detectExternalFileChanges = false
        #expect(await ws.checkExternalChanges(of: doc) == 0)
        ws.settings.detectExternalFileChanges = true
        ws.externalChangePromptsEnabled = false
        #expect(await ws.checkExternalChanges(of: doc) == 0)
        ws.externalChangePromptsEnabled = true
        // Wczytanie bez pytania, gdy okno nie ma zmian.
        ws.settings.reloadExternalChangesSilently = true
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(ui.asked.isEmpty && doc.text == "select 2 from dual;\n")
        // Okno ze zmianami — pytanie mimo preferencji.
        doc.text += "-- moje\n"
        try Data("select 3 from dual;\n".utf8).write(to: u)
        ui.answers = [1]                                     // Zachowaj moje zmiany
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(ui.asked.count == 1 && doc.text.contains("-- moje") && doc.isModified)
    }

    @Test("Zachowaj moje zmiany: bez ponownego pytania, ale ⌘S ostrzega przed nadpisaniem zmiany z dysku")
    func keepMineThenSave() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "k.sql")
        let doc = try ws.openFile(u)
        doc.text = "select 'moje' from dual;\n"
        try Data("select 'agent' from dual;\n".utf8).write(to: u)
        ui.answers = [1]
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(await ws.checkExternalChanges(of: doc) == 0)
        ui.answers = [1]                                     // Anuluj zapis
        try await ws.invoke("file.save")
        #expect(ui.asked.last?.contains("k.sql") == true)
        #expect(try text(u) == "select 'agent' from dual;\n")
        ui.answers = [0]                                     // Zapisz mimo to
        try await ws.invoke("file.save")
        #expect(try text(u) == "select 'moje' from dual;\n" && !doc.isModified)
    }

    @Test("Okno ze zmianami: Wczytaj ponownie (utracisz zmiany) — tekst z dysku, poprzedni w historii lokalnej")
    func reloadDiscardingChanges() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "r.sql")
        let doc = try ws.openFile(u)
        doc.text = "select 'moje' from dual;\n"
        try Data("select 'agent' from dual;\n".utf8).write(to: u)
        ui.answers = [0]
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(doc.text == "select 'agent' from dual;\n" && !doc.isModified)
    }

    @Test("Plik usunięty: Zachowaj w oknie — okno zmienione, bez ponownego pytania; Zamknij okno — okno zamknięte")
    func deletedFile() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "d.sql")
        let doc = try ws.openFile(u)
        try FileManager.default.removeItem(at: u)
        #expect(await ws.externalChanges(of: doc).first?.kind == .deleted)
        ui.answers = [0]
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(doc.isModified && ws.documents.contains { $0.id == doc.id })
        #expect(await ws.checkExternalChanges(of: doc) == 0)
        let u2 = try write("select 2 from dual;\n", "e.sql")
        let d2 = try ws.openFile(u2)
        try FileManager.default.removeItem(at: u2)
        ui.answers = [1]
        #expect(await ws.checkExternalChanges(of: d2) == 1)
        #expect(!ws.documents.contains { $0.id == d2.id })
    }

    @Test("Para .pks/.pkb: wczytanie ponowne tylko zmienionego pliku; niezapisana zmiana drugiej karty zostaje")
    func pairReloadsOnlyChangedFile() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let spec = "CREATE OR REPLACE PACKAGE k AS\n  PROCEDURE p;\nEND k;\n"
        let body = "CREATE OR REPLACE PACKAGE BODY k AS\n  PROCEDURE p IS BEGIN NULL; END;\nEND k;\n"
        let s = try write(spec, "k.pks"), b = try write(body, "k.pkb")
        let doc = try ws.openFile(s)
        #expect(doc.unitFiles.count == 2)
        // Niezapisana zmiana w specyfikacji, git zmienia ciało.
        doc.text = doc.text.replacingOccurrences(of: "PROCEDURE p;\n", with: "PROCEDURE p;\n  PROCEDURE q;\n")
        let newBody = body.replacingOccurrences(of: "NULL;", with: "DBMS_OUTPUT.PUT_LINE('git');")
        try Data(newBody.utf8).write(to: b)
        let changes = await ws.externalChanges(of: doc)
        #expect(changes.map(\.url) == [b.standardizedFileURL] && changes.first?.windowModified == false)
        ui.answers = [0]
        let mark = doc.editSessionMark.serial
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(doc.currentText(of: b) == newBody)
        #expect(doc.currentText(of: s)?.contains("PROCEDURE q;") == true && doc.isModified)
        // Nowa sesja edycji (formatowanie przy Enter, D205) tylko w zakresie wczytanego ciała.
        let bodyStart = (doc.text as NSString).range(of: "CREATE OR REPLACE PACKAGE BODY").location
        #expect(doc.editSessionMark.serial == mark + 1 && doc.editSessionMark.range?.contains(bodyStart) == true)
        #expect(doc.editSessionMark.range?.contains((doc.text as NSString).range(of: "PROCEDURE q;").location) == false)
        #expect(doc.editSessionMark.revision == doc.textRevision)
        // Zapis: tylko specyfikacja (ciało już jak na dysku), bez pytania o zmianę ciała.
        try await ws.invoke("file.save")
        #expect(try text(s).contains("PROCEDURE q;"))
        #expect(try text(b) == newBody && !doc.isModified)
        #expect(ui.asked.count == 1)
    }

    @Test("file.reload: wczytuje plik okna; okno ze zmianami — pytanie użytkownika, agent odmawia")
    func reloadCommand() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "c.sql")
        let doc = try ws.openFile(u)
        try Data("select 2 from dual;\n".utf8).write(to: u)
        try await ws.invoke("file.reload")
        #expect(doc.text == "select 2 from dual;\n" && ui.asked.isEmpty)
        doc.text = "select 'moje' from dual;\n"
        ui.answers = [1]
        await #expect(throws: CommandError.cancelledByUser) { try await ws.invoke("file.reload") }
        #expect(doc.text == "select 'moje' from dual;\n")
        ui.answers = [0]
        try await ws.invoke("file.reload")
        #expect(doc.text == "select 2 from dual;\n" && !doc.isModified)
        // W trakcie zapisu — bez pytań o zmiany na dysku.
        try Data("select 3 from dual;\n".utf8).write(to: u)
        ws.savingDocuments += 1
        #expect(await ws.checkExternalChanges(of: doc) == 0)
        ws.savingDocuments -= 1
        #expect(await ws.checkExternalChanges(of: doc) == 1)
    }

    @Test("Workset: okno ze zmianami — plik zmieniony po zapisie workseta wykryty przy aktywacji")
    func worksetDetectsLaterChange() async throws {
        let ws = Workspace()
        let u = try write("select 1 from dual;\n", "w.sql")
        let doc = try ws.openFile(u)
        doc.text = "select 'moje' from dual;\n"
        let saved = try JSONDecoder().decode(Workset.self, from: JSONEncoder().encode(ws.worksetSnapshot()))
        #expect(saved.documents.first?.fileHash != nil)
        try Data("select 'git' from dual;\n".utf8).write(to: u)
        let r = Workspace()
        let ui = FakeUI()
        r.ui = ui
        r.appendWorksetDocuments(saved)
        let d = try #require(r.documents.first)
        #expect(await r.externalChanges(of: d).first?.windowModified == true)
    }

    @Test("Para: plik, który po zmianie nie daje się wczytać do karty (komentarz za END) — odmowa, bez ponownego pytania")
    func pairReloadRefusedOnSplitChange() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let spec = "CREATE OR REPLACE PACKAGE k AS\n  PROCEDURE p;\nEND k;\n"
        let body = "CREATE OR REPLACE PACKAGE BODY k AS\n  PROCEDURE p IS BEGIN NULL; END;\nEND k;\n"
        let s = try write(spec, "k.pks")
        _ = try write(body, "k.pkb")
        let doc = try ws.openFile(s)
        let before = doc.text
        try Data((spec + "-- koniec specyfikacji\n").utf8).write(to: s)
        ui.answers = [0]                                     // Wczytaj ponownie
        #expect(throws: (any Error).self) { try ws.reloadFromDisk(doc, url: s) }
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(doc.text == before)
        #expect(await ws.checkExternalChanges(of: doc) == 0)
        // Tryb bez pytania — ta sama odmowa, bez pytania przy każdej aktywacji.
        ws.settings.reloadExternalChangesSilently = true
        try Data((spec + "-- inny komentarz\n").utf8).write(to: s)
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        #expect(await ws.checkExternalChanges(of: doc) == 0 && doc.text == before)
    }

    @Test("⌘S: preferencja wykrywania wyłączona — bez ostrzeżenia; tryb skryptu — zapis bez pytania (wpis w dzienniku)")
    func saveWarningRespectsPreferenceAndScriptMode() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "p.sql")
        let doc = try ws.openFile(u)
        doc.text = "select 'moje' from dual;\n"
        try Data("select 'git' from dual;\n".utf8).write(to: u)
        ws.settings.detectExternalFileChanges = false
        try await ws.invoke("file.save")
        #expect(ui.asked.isEmpty)
        #expect(try text(u) == "select 'moje' from dual;\n")
        ws.settings.detectExternalFileChanges = true
        try Data("select 'git' from dual;\n".utf8).write(to: u)
        doc.text = "select 'skrypt' from dual;\n"
        ws.externalChangePromptsEnabled = false
        try await ws.invoke("file.save")
        #expect(ui.asked.isEmpty && !doc.isModified)
        #expect(try text(u) == "select 'skrypt' from dual;\n")
    }

    @Test("Wiszące dowiązanie (cel usunięty) — plik usunięty")
    func danglingLinkIsDeleted() async throws {
        let ws = Workspace()
        let target = try write("select 1 from dual;\n", "cel.sql")
        let link = dir.appendingPathComponent("link.sql")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let doc = try ws.openFile(link)
        #expect(await ws.externalChanges(of: doc).isEmpty)
        try FileManager.default.removeItem(at: target)
        #expect(await ws.externalChanges(of: doc).first?.kind == .deleted)
    }

    @Test("Podmiana pliku z tą samą datą i rozmiarem (nowy i-węzeł) — wykryta; drugi ⌘S w trakcie zapisu — komunikat, bez zapisu")
    func replacedFileSameDateAndSize() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "i.sql")
        let doc = try ws.openFile(u)
        let stamp = try #require(doc.diskStamps[u.standardizedFileURL])
        try Data("select 9 from dual;\n".utf8).write(to: u, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: stamp.modified!], ofItemAtPath: u.path)
        #expect(await ws.externalChanges(of: doc).map(\.kind) == [.modified])
        // Zapis w toku — drugi zapis tego okna nic nie robi.
        doc.text = "select 'moje' from dual;\n"
        doc.isSaving = true
        await #expect(throws: CommandError.self) { try await ws.invoke("file.save") }
        #expect(try text(u) == "select 9 from dual;\n" && doc.isModified)
        doc.isSaving = false
    }

    @Test("Zostaw przy pliku nie do odczytu: data i rozmiar z atrybutów — bez pytania do następnej zmiany")
    func acceptUnreadableFile() async throws {
        let ws = Workspace()
        let u = try write("select 1 from dual;\n", "n.sql")
        let doc = try ws.openFile(u)
        try Data("select 22 from dual;\n".utf8).write(to: u)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: u.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: u.path) }
        let before = doc.diskStamps[u.standardizedFileURL]?.hash
        ws.acceptDiskState(doc, url: u)
        #expect(doc.diskStamps[u.standardizedFileURL]?.size == 21 && doc.diskStamps[u.standardizedFileURL]?.hash == before)
        #expect(await ws.externalChanges(of: doc).isEmpty)
    }

    @Test("Wiszące dowiązanie: Zachowaj w oknie i zapis — plik docelowy utworzony, dowiązanie zostaje")
    func saveThroughDanglingLink() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let target = try write("select 1 from dual;\n", "cel2.sql")
        let link = dir.appendingPathComponent("link2.sql")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let doc = try ws.openFile(link)
        try FileManager.default.removeItem(at: target)
        ui.answers = [0]                                     // Zachowaj w oknie
        #expect(await ws.checkExternalChanges(of: doc) == 1)
        try await ws.invoke("file.save")
        #expect(try text(target) == "select 1 from dual;\n")
        #expect((try FileManager.default.attributesOfItem(atPath: link.path))[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(await ws.externalChanges(of: doc).isEmpty)
    }

    @Test("Własny zapis w trakcie odczytu przy wykrywaniu — bez fałszywego alarmu; dwa wyzwalacze naraz — jedno pytanie")
    func saveDuringReadAndConcurrentTriggers() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "s.sql")
        let doc = try ws.openFile(u)
        doc.text = "select 'moje' from dual;\n"
        try Data("select 'agent' from dual;\n".utf8).write(to: u)
        // Zapis okna po odczycie pliku, przed porównaniem: odczytana treść („agent”) jest już nieaktualna.
        ws.afterExternalRead = { try? ws.save(doc, to: u) }
        #expect(await ws.externalChanges(of: doc).isEmpty)
        ws.afterExternalRead = nil
        #expect(try text(u) == "select 'moje' from dual;\n")
        // Dwa sprawdzenia naraz (aktywacja okna i aplikacji) — jedno pytanie.
        try Data("select 'git' from dual;\n".utf8).write(to: u)
        ui.answers = [1, 1]
        async let a = ws.checkExternalChanges(of: doc)
        async let b = ws.checkExternalChanges(of: doc)
        let (ra, rb) = await (a, b)
        #expect(ra + rb == 1 && ui.asked.count == 1)
    }

    @Test("Plik odłączony w trakcie zapisu — Zapisz jako zamiast starej ścieżki; zamknięcie czeka na zapis w toku")
    func detachedDuringSave() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let u = try write("select 1 from dual;\n", "o.sql")
        let doc = try ws.openFile(u)
        doc.text = "select 'moje' from dual;\n"
        try Data("select 'agent' from dual;\n".utf8).write(to: u)
        // Pytanie „Pliki zmieniły się na dysku” — w jego trakcie plik zostaje odłączony (usunięty w Przeglądarce plików).
        try FileManager.default.removeItem(at: u)
        doc.fileURL = nil
        doc.diskStamps = [:]
        ui.saveURL = dir.appendingPathComponent("nowy.sql")
        try await ws.invoke("file.save")
        #expect(!FileManager.default.fileExists(atPath: u.path))
        #expect(try text(ui.saveURL!) == "select 'moje' from dual;\n")
        // Zapis w toku: drugi zapis — komunikat; zamknięcie czeka na koniec zapisu.
        doc.isSaving = true
        await #expect(throws: CommandError.self) { try await ws.invoke("file.save") }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            doc.isSaving = false
        }
        try await ws.invoke("file.close")
        #expect(!ws.documents.contains { $0.id == doc.id })
    }

    @Test("Łańcuch dowiązań bez celu — zapis tworzy plik na końcu łańcucha, dowiązania zostają")
    func saveThroughLinkChain() async throws {
        let ws = Workspace()
        let target = try write("select 1 from dual;\n", "cel3.sql")
        let mid = dir.appendingPathComponent("mid.sql"), link = dir.appendingPathComponent("link3.sql")
        try FileManager.default.createSymbolicLink(atPath: mid.path, withDestinationPath: "cel3.sql")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "mid.sql")
        let doc = try ws.openFile(link)
        try FileManager.default.removeItem(at: target)
        doc.text = "select 2 from dual;\n"
        try ws.save(doc, to: link)
        #expect(try text(target) == "select 2 from dual;\n")
        for l in [mid, link] {
            #expect((try FileManager.default.attributesOfItem(atPath: l.path))[.type] as? FileAttributeType == .typeSymbolicLink)
        }
    }

    @Test("Inne okno aktywowane w trakcie pytania — sprawdzone po zakończeniu bieżącego")
    func recheckActiveWindowAfterwards() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let a = try write("select 1 from dual;\n", "pa.sql"), b = try write("select 1 from dual;\n", "pb.sql")
        let da = try ws.openFile(a)
        let db = try ws.openFile(b)
        try Data("select 2 from dual;\n".utf8).write(to: a)
        try Data("select 2 from dual;\n".utf8).write(to: b)
        ws.activate(db.id)
        ui.answers = [1, 1]
        #expect(await ws.checkExternalChanges(of: da) == 1)
        for _ in 0..<50 where ui.asked.count < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(ui.asked.count == 2 && ui.asked[1].contains("pb.sql"))
    }

    @Test("Pętla dowiązań — zapis kończy się błędem, dowiązania zostają")
    func linkLoopFails() throws {
        let ws = Workspace()
        let a = dir.appendingPathComponent("la.sql"), b = dir.appendingPathComponent("lb.sql")
        try FileManager.default.createSymbolicLink(atPath: a.path, withDestinationPath: "lb.sql")
        try FileManager.default.createSymbolicLink(atPath: b.path, withDestinationPath: "la.sql")
        let doc = ws.newDocument(.sql, text: "select 1 from dual;\n")
        #expect(throws: (any Error).self) { try ws.save(doc, to: a) }
        for l in [a, b] {
            #expect((try FileManager.default.attributesOfItem(atPath: l.path))[.type] as? FileAttributeType == .typeSymbolicLink)
        }
    }
}
