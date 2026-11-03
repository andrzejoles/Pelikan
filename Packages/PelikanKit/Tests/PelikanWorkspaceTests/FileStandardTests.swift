import Foundation
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Standard plików: UTF-8 bez BOM, programy bez „/” (D210)")
struct FileStandardTests {
    func dir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-std-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Czeka, aż kolejka pytań o standard się opróżni.
    func settle(_ ws: Workspace) async {
        for _ in 0..<200 where ws.fileStandardAsking || !ws.fileStandardQueue.isEmpty { await Task.yield() }
    }

    @Test("Linie z samym „/” poza tekstami i komentarzami; usunięcie zachowuje resztę tekstu")
    func slashLines() {
        let text = "create or replace package p is\nend;\n/\n  /  \nx := a / b;\n'\n/\n' /* \n/\n */\ncreate package body p is\nend;\n/"
        #expect(SlashLines.ranges(in: text).count == 3)
        #expect(SlashLines.removing(from: text) == "create or replace package p is\nend;\nx := a / b;\n'\n/\n' /* \n/\n */\ncreate package body p is\nend;")
        #expect(SlashLines.removing(from: "end;\n/\n") == "end;\n")
        #expect(SlashLines.removing(from: "select 1 from dual") == "select 1 from dual")
    }

    @Test("Domyślnie UTF-8 bez BOM; nowe okno w formacie ze standardu")
    func defaults() {
        let ws = Workspace()
        #expect(ws.settings.fileStandard == FileStandard())
        #expect(ws.settings.fileStandard.encoding == "UTF-8" && !ws.settings.fileStandard.byteOrderMark
                && ws.settings.fileStandard.slashFreePrograms && ws.settings.fileStandard.askOnOpen)
        #expect(ws.newDocument(.sql).fileFormat == TextFileFormat())
        ws.settings.fileStandard.byteOrderMark = true
        #expect(ws.newDocument(.program).fileFormat.hasBOM)
        ws.settings.fileStandard.encoding = "Windows-1250"
        let d = ws.newDocument(.sql)
        #expect(d.fileFormat.encoding == .windowsCP1250 && !d.fileFormat.hasBOM)
        // Stare ustawienia bez pola — wartości domyślne.
        let decoded = try? JSONDecoder().decode(FileStandard.self, from: Data(#"{"askOnOpen":false}"#.utf8))
        #expect(decoded?.encoding == "UTF-8" && decoded?.slashFreePrograms == true && decoded?.askOnOpen == false)
    }

    @Test("Odstępstwa: kodowanie, BOM, „/” tylko w plikach programów; plik zgodny — bez pytania")
    func issues() throws {
        let d = try dir()
        defer { try? FileManager.default.removeItem(at: d) }
        let ws = Workspace()
        let ok = d.appendingPathComponent("ok.pkb")
        try Data("create package body p is\nend;\n".utf8).write(to: ok)
        #expect(ws.fileStandardIssues(try ws.openFile(ok)).isEmpty)
        let bom = d.appendingPathComponent("bom.sql")
        try Data([0xEF, 0xBB, 0xBF] + Array("begin null; end;\n/\n".utf8)).write(to: bom)
        // Skrypt SQL może mieć „/” — tylko BOM.
        #expect(ws.fileStandardIssues(try ws.openFile(bom)) == [.byteOrderMark(true)])
        let cp = d.appendingPathComponent("cp.prc")
        try Data([0x9C] + Array(" procedure p is begin null; end;\n/\n".utf8)).write(to: cp)
        #expect(ws.fileStandardIssues(try ws.openFile(cp)) == [.encoding("Windows-1250"), .slashLines(1)])
        ws.settings.fileStandard.slashFreePrograms = false
        #expect(ws.fileStandardIssues(ws.documents.last!) == [.encoding("Windows-1250")])
    }

    @Test("Konwersja: UTF-8 bez BOM i bez „/”, okno zmienione, zapis w standardzie")
    func convert() throws {
        let d = try dir()
        defer { try? FileManager.default.removeItem(at: d) }
        let ws = Workspace()
        let u = d.appendingPathComponent("p.pck")
        try Data([0xEF, 0xBB, 0xBF] + Array("create package p is\nend;\n/\ncreate package body p is\nend;\n/\n".utf8)).write(to: u)
        let doc = try ws.openFile(u)
        ws.conformToFileStandard(doc)
        #expect(doc.isModified && !doc.fileFormat.hasBOM && doc.text == "create package p is\nend;\ncreate package body p is\nend;\n")
        #expect(ws.fileStandardIssues(doc).isEmpty)
        try ws.save(doc, to: u)
        #expect(try Data(contentsOf: u) == Data("create package p is\nend;\ncreate package body p is\nend;\n".utf8))
    }

    @Test("Kodowanie z projektu (D55) nie jest odstępstwem i zostaje po konwersji")
    func projectEncoding() throws {
        let d = try dir()
        defer { try? FileManager.default.removeItem(at: d) }
        let ws = Workspace()
        ws.project = Project(name: "pc")
        ws.project?.options.encoding = "ISO-8859-2"
        ws.projectURL = d.appendingPathComponent("pc.prj")
        let u = d.appendingPathComponent("a.sql")
        try Data([0x7A, 0xB1, 0x0A]).write(to: u)
        let doc = try ws.openFile(u)
        #expect(doc.fileFormat.encoding == .isoLatin2 && ws.fileStandardIssues(doc).isEmpty)
        ws.conformToFileStandard(doc)
        #expect(doc.fileFormat.encoding == .isoLatin2)
    }

    @Test("Pytanie przy otwarciu: Konwertuj / Zostaw, po kolei; bez pytania przy przywracaniu i gdy wyłączone")
    func askOnOpen() async throws {
        let d = try dir()
        defer { try? FileManager.default.removeItem(at: d) }
        let ws = Workspace()
        let ui = ExternalToolsUI()
        ws.ui = ui
        let a = d.appendingPathComponent("a.sql"), b = d.appendingPathComponent("b.sql")
        try Data([0xEF, 0xBB, 0xBF] + Array("select 1 from dual;\n".utf8)).write(to: a)
        try Data([0xEF, 0xBB, 0xBF] + Array("select 2 from dual;\n".utf8)).write(to: b)
        ui.answers = [0, 1]
        let da = try ws.openFile(a), db = try ws.openFile(b)
        await settle(ws)
        #expect(ui.asked.count == 2 && ui.asked[0].contains("a.sql") && ui.asked[1].contains("b.sql"))
        #expect(!da.fileFormat.hasBOM && da.isModified && db.fileFormat.hasBOM && !db.isModified)

        ws.close(da.id)
        ws.close(db.id)
        ws.withoutFileStandardChecks { _ = try? ws.openFile(a) }
        await settle(ws)
        #expect(ui.asked.count == 2)
        ws.close(ws.documents.last!.id)
        ws.settings.fileStandard.askOnOpen = false
        _ = try ws.openFile(b)
        await settle(ws)
        #expect(ui.asked.count == 2)
    }
}
