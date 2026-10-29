import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Eksport obiektów „plik na obiekt” (D194): specyfikacja i ciało w osobnych plikach bez „/”, para otwierana w jednym
/// oknie programu.
@MainActor
@Suite("Eksport obiektów: specyfikacja i ciało w osobnych plikach")
struct SpecBodyExportTests {
    let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-pair-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    @Test("Eksport plik na obiekt: .pks/.pkb i .tps/.tpb bez „/”; razem — .pck; opcja „Kończ jednostki znakiem /”; wyzwalacz bez ALTER … ENABLE")
    func exportFiles() {
        let spec = "CREATE OR REPLACE EDITIONABLE PACKAGE \"PKG\" AS\n  PROCEDURE p;\nEND pkg;\n/\n  GRANT EXECUTE ON \"S\".\"PKG\" TO \"SCOTT\";"
        let body = "CREATE OR REPLACE EDITIONABLE PACKAGE BODY \"PKG\" AS\n  PROCEDURE p IS BEGIN NULL; END;\nEND pkg;\n/"
        let trigger = "CREATE OR REPLACE EDITIONABLE TRIGGER \"T\" BEFORE INSERT ON \"X\" FOR EACH ROW\nBEGIN\n  NULL;\nEND;\n/\nALTER TRIGGER \"S\".\"T\" ENABLE;"
        let disabled = trigger.replacingOccurrences(of: "ENABLE;", with: "DISABLE;").replacingOccurrences(of: "\"T\"", with: "\"U\"")
        let parts: [(DBObject, String)] = [(DBObject(owner: "S", name: "PKG", type: .package), spec), (DBObject(owner: "S", name: "PKG", type: .packageBody), body),
                                           (DBObject(owner: "S", name: "PT", type: .type), "CREATE OR REPLACE TYPE \"PT\" AS OBJECT (x NUMBER);\n/"),
                                           (DBObject(owner: "S", name: "PT", type: .typeBody), "CREATE OR REPLACE TYPE BODY \"PT\" AS END;\n/"),
                                           (DBObject(owner: "S", name: "T", type: .trigger), trigger), (DBObject(owner: "S", name: "U", type: .trigger), disabled),
                                           (DBObject(owner: "S", name: "X", type: .table), "CREATE TABLE \"X\" (a NUMBER);")]
        var o = ObjectExportOptions()
        #expect(!o.specAndBodyTogether && !o.terminateUnits)
        o.layout = .filePerObject
        let files = ObjectExport.files(parts, options: o, header: "-- h\n")
        #expect(files.map(\.name) == ["pkg.pks", "pkg.pkb", "pt.tps", "pt.tpb", "t.trg", "u.trg", "x.sql"])
        func lines(_ name: String) -> [String] { files.first { $0.name == name }?.content.components(separatedBy: "\n") ?? [] }
        for name in ["pkg.pks", "pkg.pkb", "pt.tps", "pt.tpb", "t.trg"] { #expect(!lines(name).contains("/"), "\(name)") }
        #expect(lines("pkg.pks").contains { $0.contains("GRANT EXECUTE") })
        #expect(!lines("t.trg").contains { $0.contains("ALTER TRIGGER") })
        // Wyłączony wyzwalacz: ALTER … DISABLE zostaje razem z „/” (bez niego doklejałby się do wyzwalacza).
        #expect(lines("u.trg").contains("/") && lines("u.trg").contains { $0.contains("DISABLE") })
        #expect(lines("x.sql").contains("CREATE TABLE \"X\" (a NUMBER);"))
        // Pliki pakietu otwierają się jako para okna programu.
        o.terminateUnits = true
        #expect(ObjectExport.files(parts, options: o, header: "").first { $0.name == "pkg.pkb" }?.content.contains("\n/") == true)
        o.terminateUnits = false
        o.specAndBodyTogether = true
        #expect(ObjectExport.files(parts, options: o, header: "").map(\.name).prefix(2) == ["pkg.pck", "pt.typ"])
        o.specAndBodyTogether = false
        o.extensions.packageSpec = "sps"
        #expect(ObjectExport.files(parts, options: o, header: "").first?.name == "pkg.sps")
    }

    @Test("Eksport plik na obiekt: para .pks/.pkb otwiera się w jednym oknie i zapisuje bez zmian")
    func exportedPairOpens() async throws {
        let parts: [(DBObject, String)] = [
            (DBObject(owner: "S", name: "PKG", type: .package), "CREATE OR REPLACE EDITIONABLE PACKAGE \"S\".\"PKG\" AS\n  PROCEDURE p;\nEND pkg;\n/"),
            (DBObject(owner: "S", name: "PKG", type: .packageBody), "CREATE OR REPLACE EDITIONABLE PACKAGE BODY \"S\".\"PKG\" AS\n  PROCEDURE p IS BEGIN NULL; END;\nEND pkg;\n/")]
        var o = ObjectExportOptions()
        o.layout = .filePerObject
        for f in ObjectExport.files(parts, options: o, header: "-- Wygenerowane\n") {
            try Data(f.content.utf8).write(to: dir.appendingPathComponent(f.name))
        }
        let ws = Workspace()
        let uiWs = FakeUI()
        ws.ui = uiWs
        let doc = try ws.openFile(dir.appendingPathComponent("pkg.pkb"))
        #expect(doc.unitFiles.count == 2 && doc.activeUnitTab == 1)
        let before = try Data(contentsOf: dir.appendingPathComponent("pkg.pks"))
        try await ws.invoke("file.save")
        #expect(try Data(contentsOf: dir.appendingPathComponent("pkg.pks")) == before)
    }
}
