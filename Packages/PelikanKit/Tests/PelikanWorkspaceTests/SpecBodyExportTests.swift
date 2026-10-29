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

    @Test("Eksport plik na obiekt: .pks/.pkb i .tps/.tpb bez „/”; razem — .pck z „/”; opcja „Kończ jednostki znakiem /”; wyzwalacz bez ALTER")
    func exportFiles() {
        let spec = "CREATE OR REPLACE EDITIONABLE PACKAGE \"PKG\" AS\n  PROCEDURE p;\nEND pkg;\n/"
        let body = "CREATE OR REPLACE EDITIONABLE PACKAGE BODY \"PKG\" AS\n  PROCEDURE p IS BEGIN NULL; END;\nEND pkg;\n/"
        let trigger = "CREATE OR REPLACE EDITIONABLE TRIGGER \"T\" BEFORE INSERT ON \"X\" FOR EACH ROW\nBEGIN\n  NULL;\nEND;\n/\nALTER TRIGGER \"S\".\"T\" ENABLE;"
        let disabled = trigger.replacingOccurrences(of: "ENABLE;", with: "DISABLE;").replacingOccurrences(of: "\"T\"", with: "\"U\"")
        let parts: [ExportPart] = [
            ExportPart(object: DBObject(owner: "S", name: "PKG", type: .package), ddl: spec, grants: "GRANT EXECUTE ON \"S\".\"PKG\" TO \"SCOTT\";"),
            ExportPart(object: DBObject(owner: "S", name: "PKG", type: .packageBody), ddl: body),
            ExportPart(object: DBObject(owner: "S", name: "PT", type: .type), ddl: "CREATE OR REPLACE TYPE \"PT\" AS OBJECT (x NUMBER);\n/"),
            ExportPart(object: DBObject(owner: "S", name: "PT", type: .typeBody), ddl: "CREATE OR REPLACE TYPE BODY \"PT\" AS END;\n/"),
            ExportPart(object: DBObject(owner: "S", name: "T", type: .trigger), ddl: trigger),
            ExportPart(object: DBObject(owner: "S", name: "U", type: .trigger), ddl: disabled),
            ExportPart(object: DBObject(owner: "S", name: "X", type: .table), ddl: "CREATE TABLE \"X\" (a NUMBER);", grants: "GRANT SELECT ON \"S\".\"X\" TO \"SCOTT\";")]
        var o = ObjectExportOptions()
        #expect(!o.specAndBodyTogether && !o.terminateUnits && !o.dateHeader && o.grantPlacement == .separateFile)
        o.layout = .filePerObject
        let files = ObjectExport.files(parts, options: o, header: "")
        #expect(files.map(\.name) == ["pkg.pks", "pkg.grants.sql", "pkg.pkb", "pt.tps", "pt.tpb", "t.trg", "u.trg", "x.sql", "x.grants.sql"])
        func content(_ name: String) -> String { files.first { $0.name == name }?.content ?? "" }
        func lines(_ name: String) -> [String] { content(name).components(separatedBy: "\n") }
        for name in ["pkg.pks", "pkg.pkb", "pt.tps", "pt.tpb", "t.trg", "u.trg"] { #expect(!lines(name).contains("/"), "\(name)") }
        // Pliki DDL zawierają wyłącznie CREATE — uprawnienia w osobnym pliku z „;” (decyzja właściciela, D194).
        #expect(!files.filter { !$0.name.hasSuffix(".grants.sql") }.contains { $0.content.uppercased().contains("GRANT ") })
        #expect(content("pkg.grants.sql") == "GRANT EXECUTE ON \"S\".\"PKG\" TO \"SCOTT\";\n")
        #expect(content("pkg.pks").hasPrefix("CREATE OR REPLACE EDITIONABLE PACKAGE"))         // bez nagłówka z datą
        #expect(files.allSatisfy { !$0.keepsSlash })
        #expect(!content("t.trg").contains("ALTER TRIGGER"))
        // Wyłączony wyzwalacz: klauzula DISABLE w CREATE TRIGGER zamiast ALTER … DISABLE i „/”.
        #expect(content("u.trg").contains("FOR EACH ROW\nDISABLE BEGIN") && !content("u.trg").contains("ALTER TRIGGER"))
        #expect(lines("x.sql").contains("CREATE TABLE \"X\" (a NUMBER);"))
        // Uprawnienia pominięte.
        o.grantPlacement = .omit
        #expect(!ObjectExport.files(parts, options: o, header: "").contains { $0.name.hasSuffix(".grants.sql") })
        o.grantPlacement = .separateFile
        o.terminateUnits = true
        #expect(ObjectExport.files(parts, options: o, header: "").first { $0.name == "pkg.pkb" }?.content.contains("\n/") == true)
        o.terminateUnits = false
        // Razem w .pck/.typ — z „/” (konwencja PL/SQL Developera); nagłówek z datą na życzenie.
        o.specAndBodyTogether = true
        let together = ObjectExport.files(parts, options: o, header: "-- h\n")
        #expect(together.map(\.name).prefix(3) == ["pkg.pck", "pkg.grants.sql", "pt.typ"])
        #expect(together.first { $0.name == "pkg.pck" }?.content.components(separatedBy: "\n").filter { $0 == "/" }.count == 2)
        #expect(together.first { $0.name == "pkg.pck" }?.content.hasPrefix("-- h\n") == true)
        o.specAndBodyTogether = false
        o.extensions.packageSpec = "sps"
        #expect(ObjectExport.files(parts, options: o, header: "").map(\.name).contains("pkg.sps"))
    }

    @Test("Eksport: ALTER TYPE za typem zostawia „/” i ostrzeżenie; klauzula stanu wyzwalacza przed WHEN")
    func exportKeepsSlashWarning() {
        let evolved = "CREATE OR REPLACE TYPE \"PT\" AS OBJECT (x NUMBER);\n/\nALTER TYPE \"PT\" ADD ATTRIBUTE (y NUMBER) CASCADE;"
        var o = ObjectExportOptions()
        o.layout = .filePerObject
        let f = ObjectExport.files([ExportPart(object: DBObject(owner: "S", name: "PT", type: .type), ddl: evolved)], options: o, header: "")
        #expect(f.first?.keepsSlash == true && f.first?.content.components(separatedBy: "\n").contains("/") == true)
        let when = "CREATE OR REPLACE TRIGGER t BEFORE UPDATE OF a ON x FOR EACH ROW\nWHEN (new.a > 0)\nBEGIN NULL; END;"
        #expect(ObjectExport.triggerStateClauseOffset(when) == (when as NSString).range(of: "WHEN").location)
        #expect(ObjectExport.triggerStateClauseOffset("CREATE TRIGGER t AFTER LOGON ON DATABASE DISABLE BEGIN NULL; END;") == nil)
        // Etykieta bloku przed BEGIN — klauzula przed etykietą.
        let label = "CREATE TRIGGER t BEFORE INSERT ON x FOR EACH ROW\n<<blk>>\nBEGIN NULL; END blk;"
        #expect(ObjectExport.triggerStateClauseOffset(label) == (label as NSString).range(of: "<<").location)
        let compound = "CREATE TRIGGER t FOR UPDATE ON x COMPOUND TRIGGER\n  AFTER STATEMENT IS BEGIN NULL; END AFTER STATEMENT;\nEND t;"
        #expect(ObjectExport.triggerStateClauseOffset(compound) == (compound as NSString).range(of: "COMPOUND").location)
    }

    @Test("Eksport kilku schematów: przedrostek schematu w nazwie każdego pliku; jeden schemat — bez przedrostka")
    func exportManySchemas() {
        func p(_ owner: String, _ t: DBObjectType) -> ExportPart {
            let kind = t == .package ? "PACKAGE" : "PACKAGE BODY"
            return ExportPart(object: DBObject(owner: owner, name: "PKG", type: t), ddl: "CREATE OR REPLACE \(kind) \"\(owner)\".\"PKG\" AS END;\n/")
        }
        var o = ObjectExportOptions()
        o.layout = .filePerObject
        // Kolejność jak po sortowaniu eksportu (typ, właściciel, nazwa): specyfikacje obu schematów, potem ciała.
        let files = ObjectExport.files([p("S1", .package), p("S2", .package), p("S1", .packageBody), p("S2", .packageBody)], options: o, header: "")
        #expect(files.map(\.name) == ["s1.pkg.pks", "s2.pkg.pks", "s1.pkg.pkb", "s2.pkg.pkb"])
        #expect(files.first { $0.name == "s2.pkg.pks" }?.content.contains("\"S2\"") == true)
        #expect(files.first { $0.name == "s2.pkg.pkb" }?.content.contains("\"S2\"") == true)
        #expect(files.first { $0.name == "s1.pkg.pkb" }?.content.contains("\"S1\"") == true)
        // Uprawnienia też z przedrostkiem; nazwy niezależne od wyboru obiektów innego schematu.
        var g = p("S2", .package)
        g.grants = "GRANT EXECUTE ON \"S2\".\"PKG\" TO \"A\";"
        #expect(ObjectExport.files([p("S1", .package), g], options: o, header: "").map(\.name) == ["s1.pkg.pks", "s2.pkg.pks", "s2.pkg.grants.sql"])
        #expect(ObjectExport.files([p("S2", .package), p("S2", .packageBody)], options: o, header: "").map(\.name) == ["pkg.pks", "pkg.pkb"])
        // Para z przedrostkiem schematu otwiera się w jednym oknie (nazwa bazowa z kropką).
        for f in files { try? Data(f.content.utf8).write(to: dir.appendingPathComponent(f.name)) }
        let ws = Workspace()
        let doc = try? ws.openFile(dir.appendingPathComponent("s2.pkg.pkb"))
        #expect(doc?.unitFiles.map { $0.url.lastPathComponent } == ["s2.pkg.pks", "s2.pkg.pkb"])
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
