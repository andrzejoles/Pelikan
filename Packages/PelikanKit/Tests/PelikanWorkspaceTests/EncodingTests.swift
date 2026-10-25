import Foundation
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Kodowanie plików (Pro*C)")
struct EncodingTests {
    let latin2 = Data([0x7A, 0xB1, 0x62, 0x6B, 0x61, 0x0A, 0xB6, 0x77, 0x69, 0xEA, 0x74, 0x79])   // „ząbka\nświęty” w ISO-8859-2

    @Test("Rozpoznanie ISO-8859-2 i Windows-1250; wykrywanie kodowania projektu")
    func detect() throws {
        let (text, f) = TextFileCodec.decode(latin2)
        #expect(f.encoding == .isoLatin2 && text == "ząbka\nświęty")
        #expect(TextFileCodec.decode(Data([0x9C, 0x77])).format.encoding == .windowsCP1250)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-enc-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("ascii".utf8).write(to: dir.appendingPathComponent("a.h"))
        try latin2.write(to: dir.appendingPathComponent("b.pc"))
        #expect(TextFileCodec.detectEncoding(of: [dir.appendingPathComponent("a.h"), dir.appendingPathComponent("b.pc")]) == "ISO-8859-2")
        #expect(TextFileCodec.detectEncoding(of: [dir.appendingPathComponent("a.h")]) == "UTF-8")
    }

    @Test("Zapis ISO-8859-2: „” blokuje zapis z linią i kolumną; plik nie przechodzi po cichu na UTF-8; jawna zmiana kodowania")
    func save() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-enc-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("prog.pc")
        try latin2.write(to: file)
        let ws = Workspace()
        let doc = try ws.openFile(file)
        doc.text += "\nprintf(\u{201E}tekst\u{201D});"
        #expect(throws: TextFileError.unencodable(line: 3, column: 8, character: "\u{201E}", encoding: "ISO-8859-2")) { try ws.save(doc, to: file) }
        #expect(try Data(contentsOf: file) == latin2)
        doc.text = doc.text.replacingOccurrences(of: "\u{201E}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"") + " /* źle */"
        try ws.save(doc, to: file)
        let saved = try Data(contentsOf: file)
        #expect(String(data: saved, encoding: .utf8) == nil && String(data: saved, encoding: .isoLatin2)?.hasSuffix("/* źle */") == true)
        ws.activate(doc.id)
        try awaitInvoke(ws, "UTF-8")
        try ws.save(doc, to: file)
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8)?.contains("ząbka") == true)
    }

    @Test("Kodowanie projektu: plik ASCII w projekcie ISO-8859-2 zapisany z polskimi literami zostaje w ISO-8859-2")
    func projectEncoding() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-enc-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("nowy.h")
        try Data("int x;\n".utf8).write(to: file)
        let ws = Workspace()
        ws.project = Project(name: "pc")
        ws.project?.options.encoding = "ISO-8859-2"
        ws.projectURL = dir.appendingPathComponent("pc.prj")
        let doc = try ws.openFile(file)
        #expect(doc.fileFormat.encoding == .isoLatin2)
        doc.text += "/* łódź */\n"
        try ws.save(doc, to: file)
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == nil)
    }

    @Test("Szukanie w projekcie czyta pliki w kodowaniu projektu (ISO-8859-2) i bez CR z CRLF")
    func projectFind() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-enc-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try latin2.write(to: dir.appendingPathComponent("b.pc"))
        try Data([0x78, 0x0D, 0x0A, 0x2D, 0x2D, 0x20, 0xB6, 0x77, 0x69, 0xEA, 0x74, 0x79, 0x0D, 0x0A]).write(to: dir.appendingPathComponent("c.sql"))  // CRLF
        var project = Project(name: "pc")
        project.options.encoding = "ISO-8859-2"
        project.items = [.file("b.pc"), .file("c.sql")]
        let matches = try await ProjectEngine.find("ŚWIĘTY", in: project, projectURL: dir.appendingPathComponent("pc.prj"), ws: Workspace())
        #expect(matches.map(\.text) == ["święty", "-- święty"])
        #expect(matches.map(\.line) == [2, 2])
    }

    func awaitInvoke(_ ws: Workspace, _ enc: String) throws {
        let doc = ws.activeDocument!
        doc.fileFormat.encoding = TextFileCodec.encoding(named: enc)!
    }
}
