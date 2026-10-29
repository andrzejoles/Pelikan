import Foundation
import PelikanDB
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Specyfikacja i ciało w osobnych plikach (D194): okno programu z dwoma plikami, otwieranie pary, zapis każdej
/// jednostki do jej pliku bez „/”, Zapisz jako, worksety i odzyskiwanie, eksport „plik na obiekt”.
@MainActor
@Suite("Okno programu: specyfikacja i ciało w osobnych plikach")
struct SpecBodyFilesTests {
    let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-pair-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static let spec = """
    -- Kadry: specyfikacja
    CREATE OR REPLACE PACKAGE kadry AS
      PROCEDURE zatrudnij(p_nazwisko VARCHAR2);
    END kadry;

    """
    static let body = """
    CREATE OR REPLACE PACKAGE BODY kadry AS
      PROCEDURE zatrudnij(p_nazwisko VARCHAR2) IS
      BEGIN
        NULL; -- Zażółć
      END zatrudnij;
    END kadry;

    """

    /// Plik specyfikacji UTF-8 z LF, plik ciała Windows-1250 z CRLF — każdy zapisywany w swoim formacie.
    func writePair(_ name: String = "kadry") throws -> (spec: URL, body: URL) {
        let s = dir.appendingPathComponent("\(name).pks"), b = dir.appendingPathComponent("\(name).pkb")
        try Data(Self.spec.utf8).write(to: s)
        try Self.body.replacingOccurrences(of: "\n", with: "\r\n").data(using: .windowsCP1250)!.write(to: b)
        return (s, b)
    }

    func text(_ url: URL) throws -> String { TextFileCodec.decode(try Data(contentsOf: url)).text }

    @Test("Otwarcie .pks z parą .pkb: jedno okno, dwie karty, dwa pliki z własnym formatem; .pkb pokazuje kartę ciała")
    func openPair() throws {
        let ws = Workspace()
        let (s, b) = try writePair()
        let doc = try ws.openFile(s)
        #expect(ws.documents.count == 1 && doc.kind == .program && !doc.isModified)
        #expect(doc.programUnitTabs.count == 2)
        #expect(doc.unitFiles.map(\.part) == [.spec, .body])
        #expect(doc.unitFiles.map(\.url) == [s.standardizedFileURL, b.standardizedFileURL])
        #expect(doc.unitFiles[0].format.encoding == .utf8 && doc.unitFiles[0].format.lineEnding == .lf)
        #expect(doc.unitFiles[1].format.encoding == .windowsCP1250 && doc.unitFiles[1].format.lineEnding == .crlf)
        #expect(doc.title == "kadry.pks + .pkb")
        #expect(doc.text == SpecBodyFiles.splitEnding(Self.spec).content + "\n\n" + Self.body)
        #expect(doc.activeUnitTab == 0)
        #expect(doc.currentText(of: b) == Self.body && doc.currentText(of: s) == Self.spec)
        // Ponowne otwarcie ciała — to samo okno, karta ciała.
        #expect(try ws.openFile(b).id == doc.id)
        #expect(doc.activeUnitTab == 1 && doc.activeFileURL == b.standardizedFileURL)
        #expect(ws.documents.count == 1)
        // Linia 3 pliku ciała — linia okna w karcie ciała.
        let o = doc.offset(line: 3, inFile: b)
        #expect((doc.text as NSString).substring(with: (doc.text as NSString).lineRange(for: NSRange(location: o, length: 0))) == "  BEGIN\n")
        #expect(ws.settings.recentFiles.first == s.path)
    }

    @Test("Otwarcie .pkb jako pierwszego: karta ciała; ta sama para z innego okna nie otwiera się drugi raz")
    func openBodyFirst() throws {
        let ws = Workspace()
        let (_, b) = try writePair()
        let doc = try ws.openFile(b)
        #expect(doc.unitFiles.count == 2 && doc.activeUnitTab == 1)
    }

    @Test("Bez pary: brak pliku obok, preferencja wyłączona, plik pary otwarty osobno, plik z dwiema jednostkami")
    func noPair() throws {
        let ws = Workspace()
        let lonely = dir.appendingPathComponent("sam.pks")
        try Data(Self.spec.replacingOccurrences(of: "kadry", with: "sam").utf8).write(to: lonely)
        let d1 = try ws.openFile(lonely)
        #expect(d1.unitFiles.isEmpty && d1.fileURL == lonely.standardizedFileURL)
        let (s, b) = try writePair()
        ws.settings.openSpecBodyPair = false
        let d2 = try ws.openFile(s)
        #expect(d2.unitFiles.isEmpty)
        ws.settings.openSpecBodyPair = true
        // Specyfikacja otwarta już sama — ciało też samo (jeden plik nie może być w dwóch oknach).
        let d3 = try ws.openFile(b)
        #expect(d3.unitFiles.isEmpty && d3.id != d2.id)
        // Ciało innego pakietu — nie para.
        let ws2 = Workspace()
        let other = dir.appendingPathComponent("inny.pks")
        try Data(Self.spec.utf8).write(to: other)
        try Data(Self.body.replacingOccurrences(of: "kadry", with: "placa").utf8).write(to: dir.appendingPathComponent("inny.pkb"))
        #expect(try ws2.openFile(other).unitFiles.isEmpty)
    }

    @Test("Zapis: każda jednostka do swojego pliku bez „/”, w formacie pliku; niezmieniony plik nie jest zapisywany")
    func saveChangedUnitOnly() async throws {
        let ws = Workspace()
        let uiWs = FakeUI()
        ws.ui = uiWs
        let (s, b) = try writePair()
        let doc = try ws.openFile(s)
        let specData = try Data(contentsOf: s), bodyData = try Data(contentsOf: b)
        // Zapis bez zmian — pliki bajt w bajt.
        try await ws.invoke("file.save")
        #expect(try Data(contentsOf: s) == specData)
        #expect(try Data(contentsOf: b) == bodyData)
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: s.path)
        doc.text = doc.text.replacingOccurrences(of: "NULL; -- Zażółć", with: "DBMS_OUTPUT.PUT_LINE('łódź');")
        #expect(doc.isModified)
        try await ws.invoke("file.save")
        #expect(!doc.isModified)
        // Specyfikacja niezmieniona — plik nietknięty.
        #expect((try FileManager.default.attributesOfItem(atPath: s.path)[.modificationDate] as? Date) == old)
        let raw = try Data(contentsOf: b)
        let saved = try #require(String(data: raw, encoding: .windowsCP1250))
        #expect(saved == Self.body.replacingOccurrences(of: "NULL; -- Zażółć", with: "DBMS_OUTPUT.PUT_LINE('łódź');").replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(!saved.components(separatedBy: "\r\n").contains("/"))
        #expect(try text(s) == Self.spec)
        // Zmiana w specyfikacji — zapis specyfikacji.
        doc.text = doc.text.replacingOccurrences(of: "VARCHAR2);\nEND kadry;", with: "VARCHAR2);\n  PROCEDURE zwolnij;\nEND kadry;")
        try await ws.invoke("file.save")
        #expect(try text(s) == Self.spec.replacingOccurrences(of: "VARCHAR2);\nEND kadry;", with: "VARCHAR2);\n  PROCEDURE zwolnij;\nEND kadry;"))
        #expect(try text(s).hasSuffix("END kadry;\n"))
    }

    @Test("Okno pary bez ciała: zapis odmawia zamiast obciąć plik; Zapisz jako jeden plik — .pck bez powiązania z parą")
    func saveNotAPair() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let (s, b) = try writePair()
        let doc = try ws.openFile(s)
        let full = doc.text
        doc.text = Self.spec
        await #expect(throws: UnitFilesError.self) { try await ws.invoke("file.save") }
        #expect(try text(b) == Self.body)
        doc.text = full
        ui.saveURL = dir.appendingPathComponent("kadry.pck")
        try await ws.invoke("file.saveAsSingleFile")
        #expect(doc.unitFiles.isEmpty && doc.fileURL?.lastPathComponent == "kadry.pck")
        #expect(try text(ui.saveURL!) == full)
    }

    @Test("Zapisz jako (nowe okno pakietu): para nazwa.pks + nazwa.pkb z rozszerzeniami z Preferencji, bez „/”; pytanie o istniejące ciało")
    func saveAsPair() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let doc = ws.newDocument(.program)
        doc.text = ProgramText.join([Self.spec, Self.body], slash: false)
        ui.saveURL = dir.appendingPathComponent("kadry.pks")
        try await ws.invoke("file.save")
        let s = dir.appendingPathComponent("kadry.pks"), b = dir.appendingPathComponent("kadry.pkb")
        #expect(doc.unitFiles.map(\.url) == [s.standardizedFileURL, b.standardizedFileURL] && !doc.isModified)
        #expect(try text(s) == Self.spec)
        #expect(try text(b) == Self.body)
        #expect(doc.title == "kadry.pks + .pkb")
        // Zapisz jako pod inną nazwą: ciało już istnieje — Anuluj nic nie zapisuje, Zastąp zapisuje parę.
        try Data("stare ciało".utf8).write(to: dir.appendingPathComponent("nowe.pkb"))
        ui.saveURL = dir.appendingPathComponent("nowe.pks")
        ui.answers = [1]
        try await ws.invoke("file.saveAs")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("nowe.pks").path))
        ui.answers = [0]
        try await ws.invoke("file.saveAs")
        #expect(try text(dir.appendingPathComponent("nowe.pkb")) == Self.body)
        #expect(doc.unitFiles.map { $0.url.lastPathComponent } == ["nowe.pks", "nowe.pkb"])
        // Typ: rozszerzenia z Preferencji (.typs/.typb).
        ws.settings.specBodyExtensions.typeSpec = ".TYPS"
        ws.settings.specBodyExtensions.typeBody = "typb"
        let t = ws.newDocument(.program)
        t.text = "CREATE OR REPLACE TYPE punkt AS OBJECT (x NUMBER, MEMBER FUNCTION d RETURN NUMBER);\n\nCREATE OR REPLACE TYPE BODY punkt AS\n  MEMBER FUNCTION d RETURN NUMBER IS BEGIN RETURN x; END;\nEND;\n"
        ui.saveURL = dir.appendingPathComponent("punkt.typs")
        try await ws.invoke("file.save")
        #expect(t.unitFiles.map { $0.url.lastPathComponent } == ["punkt.typs", "punkt.typb"])
        #expect(ws.documentKind(for: dir.appendingPathComponent("x.typb")) == .program)
        #expect(try text(dir.appendingPathComponent("punkt.typb")).hasPrefix("CREATE OR REPLACE TYPE BODY punkt"))
    }

    @Test("Okno z jedną jednostką albo procedurami: zapis jak dotąd — jeden plik")
    func singleUnitWindow() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let doc = ws.newDocument(.program)
        doc.text = "CREATE OR REPLACE PROCEDURE p IS BEGIN NULL; END;\n\nCREATE OR REPLACE FUNCTION f RETURN NUMBER IS BEGIN RETURN 1; END;\n"
        ui.saveURL = dir.appendingPathComponent("p.prc")
        try await ws.invoke("file.save")
        #expect(doc.unitFiles.isEmpty && doc.fileURL?.lastPathComponent == "p.prc")
        #expect(try text(ui.saveURL!) == doc.text)
    }

    @Test("Workset: okno pary bez zmian wraca jako para; ze zmianami — tekst i oba pliki; odzyskiwanie po awarii")
    func worksetAndRecovery() async throws {
        let ws = Workspace()
        let uiWs = FakeUI()
        ws.ui = uiWs
        let (s, b) = try writePair()
        let doc = try ws.openFile(b)
        var snap = ws.worksetSnapshot()
        #expect(snap.documents.first?.text == nil && snap.documents.first?.unitFiles?.count == 2)
        // JSON workseta zawiera ścieżki obu plików (nowe pole opcjonalne).
        let decoded = try JSONDecoder().decode(Workset.self, from: JSONEncoder().encode(snap))
        let restored = Workspace()
        restored.settings.openSpecBodyPair = false     // para z workseta niezależnie od preferencji
        restored.appendWorksetDocuments(decoded)
        let r1 = try #require(restored.documents.first)
        #expect(r1.unitFiles.map(\.url) == [s.standardizedFileURL, b.standardizedFileURL] && !r1.isModified)
        // Zmiana w ciele — workset z tekstem i plikami; po przywróceniu zapis trafia do pliku ciała w jego formacie.
        doc.text = doc.text.replacingOccurrences(of: "NULL; -- Zażółć", with: "NULL; -- zmiana")
        snap = ws.worksetSnapshot()
        #expect(snap.documents.first?.text != nil && snap.documents.first?.unitFiles?.count == 2)
        let recovery = ws.recoverySnapshot()
        #expect(recovery.documents.first?.unitFiles?.count == 2)
        let r = Workspace()
        let uiR = FakeUI()
        r.ui = uiR
        r.appendWorksetDocuments(try JSONDecoder().decode(Workset.self, from: JSONEncoder().encode(recovery)))
        let r2 = try #require(r.documents.first)
        #expect(r2.isModified && r2.unitFiles.count == 2 && r2.unitFiles[1].format.lineEnding == .crlf)
        let specDate = try FileManager.default.attributesOfItem(atPath: s.path)[.modificationDate] as? Date
        try await r.invoke("file.save")
        #expect(try text(b) == Self.body.replacingOccurrences(of: "NULL; -- Zażółć", with: "NULL; -- zmiana"))
        #expect(String(data: try Data(contentsOf: b), encoding: .windowsCP1250)?.contains("\r\n") == true)
        #expect((try FileManager.default.attributesOfItem(atPath: s.path)[.modificationDate] as? Date) == specDate)
        // Starszy workset bez pola `unitFiles` dekoduje się jak dotąd.
        let legacy = #"{"kind":"program","filePath":"\#(s.path)","modified":false,"selectionStart":0,"selectionEnd":0}"#
        #expect(try JSONDecoder().decode(WorksetDocument.self, from: Data(legacy.utf8)).unitFiles == nil)
    }

    @Test("Kodowanie pliku… w oknie pary zmienia oba pliki; GRANT za specyfikacją należy do karty specyfikacji")
    func encodingAndGrants() async throws {
        let ws = Workspace()
        let uiWs = FakeUI()
        ws.ui = uiWs
        let s = dir.appendingPathComponent("g.pks"), b = dir.appendingPathComponent("g.pkb")
        let spec = Self.spec.replacingOccurrences(of: "kadry", with: "g") + "\nGRANT EXECUTE ON g TO PUBLIC;\n"
        try Data(spec.utf8).write(to: s)
        try Data(Self.body.replacingOccurrences(of: "kadry", with: "g").utf8).write(to: b)
        let doc = try ws.openFile(s)
        #expect(doc.unitFiles.count == 2)
        #expect(doc.currentText(of: s) == spec)
        try await ws.invoke("file.encoding", CommandArguments(["encoding": .string("Windows-1250")]))
        #expect(doc.unitFiles.allSatisfy { $0.format.encoding == .windowsCP1250 })
        try await ws.invoke("file.save")
        #expect(String(data: try Data(contentsOf: b), encoding: .windowsCP1250)?.contains("Zażółć") == true)
        #expect(String(data: try Data(contentsOf: b), encoding: .utf8) == nil)
        #expect(try text(s) == spec)
    }

    @Test("Zmiana nazwy pliku ciała w Przeglądarce plików przenosi powiązanie okna")
    func renameBody() async throws {
        let ws = Workspace()
        let uiWs = FakeUI()
        ws.ui = uiWs
        let (s, b) = try writePair()
        let doc = try ws.openFile(s)
        try await ws.invoke("fb.rename", CommandArguments(["path": .string(b.path), "name": .string("kadry_v2.pkb")]))
        #expect(doc.unitFiles[1].url.lastPathComponent == "kadry_v2.pkb")
        #expect(doc.title == "kadry.pks + kadry_v2.pkb")
    }

    @Test("Podział tekstu okna: niezmienione pliki bajt w bajt (komentarz nagłówka, plik bez końcowego znaku nowej linii)")
    func roundTrip() {
        for (spec, body) in [("CREATE PACKAGE a AS END;", "CREATE PACKAGE BODY a AS END;"),
                             ("-- x\n\nCREATE PACKAGE a AS END;\n\n\n", "\n-- body\nCREATE PACKAGE BODY a AS END;\n")] {
            let text = SpecBodyFiles.join(spec: spec, body: body)
            let units = ProgramCompiler.units(in: text)
            let tabs = ProgramUnitTabs.tabs(units, in: text)
            #expect(SpecBodyFiles.parts(units, tabs: tabs) == [.spec, .body])
            let endings = [SpecBodyFiles.splitEnding(spec).ending, SpecBodyFiles.splitEnding(body).ending]
            #expect(SpecBodyFiles.fileTexts(text, tabs: tabs, endings: endings) == [spec, body])
        }
    }

    // MARK: Poprawki po przeglądzie

    @Test("Zapisz jako z inną nazwą (.pck, sama nazwa, .pkb): jedno pytanie z listą istniejących plików pary spoza okna")
    func saveAsAsksOnceForExistingFiles() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let (s, b) = try writePair("istniejacy")
        let doc = ws.newDocument(.program)
        doc.text = ProgramText.join([Self.spec, Self.body], slash: false)
        // Wpisane .pck: specyfikacja i ciało istnieją — jedno pytanie; Anuluj nic nie zapisuje.
        ui.saveURL = dir.appendingPathComponent("istniejacy.pck")
        ui.answers = [1]
        try await ws.invoke("file.saveAs")
        #expect(ui.asked.count == 1 && ui.asked[0].contains("istniejacy.pks") && ui.asked[0].contains("istniejacy.pkb"))
        #expect(try text(s) == Self.spec && doc.unitFiles.isEmpty)
        // Wpisane .pkb: zastąpienie ciała potwierdziło okno zapisu — pytanie tylko o specyfikację.
        ui.asked = []
        ui.saveURL = b
        ui.answers = [0]
        try await ws.invoke("file.saveAs")
        #expect(ui.asked.count == 1 && ui.asked[0].contains("istniejacy.pks") && !ui.asked[0].contains("istniejacy.pkb"))
        #expect(doc.unitFiles.map(\.url) == [s.standardizedFileURL, b.standardizedFileURL])
        #expect(try text(b) == Self.body)
    }

    @Test("Rozszerzenia z Preferencji: te same dla specyfikacji i ciała albo zajęte — domyślne; zapis nie nadpisze specyfikacji ciałem")
    func invalidExtensions() throws {
        var e = SpecBodyExtensions()
        e.packageBody = "PKS"
        #expect(e.isInvalid && e.pair(for: .package)! == ("pks", "pkb"))
        e.packageBody = "sql"
        #expect(e.isInvalid && e.pair(for: .packageBody)! == ("pks", "pkb"))
        e.packageBody = "a.b"
        #expect(e.isInvalid)
        e.packageBody = ".BDY"
        #expect(!e.isInvalid && e.pair(for: .package)! == ("pks", "bdy"))
        // Pakiet i typ ze wspólnymi rozszerzeniami (.spc/.bdy) — dozwolone; specyfikacja typu = ciało pakietu — nie.
        e.packageSpec = "spc"; e.typeSpec = "spc"; e.typeBody = "bdy"
        #expect(!e.isInvalid && e.pair(for: .type)! == ("spc", "bdy") && e.partner(of: "BDY")! == ("spc", .body))
        e.typeSpec = "bdy"
        #expect(e.isInvalid && e.pair(for: .type)! == ("tps", "tpb"))
        let ws = Workspace()
        let doc = ws.newDocument(.program, text: ProgramText.join([Self.spec, Self.body], slash: false))
        let same = dir.appendingPathComponent("x.pks")
        #expect(throws: UnitFilesError.self) { try ws.saveUnitFiles(doc, spec: same, body: same) }
        #expect(!FileManager.default.fileExists(atPath: same.path) && doc.unitFiles.isEmpty)
    }

    @Test("Dwie jednostki w jednej linii: zapis do pary odmawia zamiast zapisać ucięte pliki")
    func twoUnitsInOneLine() async throws {
        let ws = Workspace()
        let uiWs = FakeUI()
        ws.ui = uiWs
        let (s, b) = try writePair()
        let doc = try ws.openFile(s)
        doc.text = "CREATE OR REPLACE PACKAGE kadry AS\n  PROCEDURE p;\nEND kadry; CREATE OR REPLACE PACKAGE BODY kadry AS\n  PROCEDURE p IS BEGIN NULL; END;\nEND kadry;\n"
        await #expect(throws: (any Error).self) { try await ws.invoke("file.save") }
        #expect(try text(s) == Self.spec)
        #expect(try text(b) == Self.body)
        // Siatka bezpieczeństwa: każdy plik to dokładnie jedna jednostka karty — podział w środku polecenia odrzucony.
        let units = ProgramCompiler.units(in: ProgramText.join([Self.spec, Self.body], slash: false))
        #expect(SpecBodyFiles.mismatch([Self.spec, Self.body], units: units) == nil)
        #expect(SpecBodyFiles.mismatch(["CREATE OR REPLACE PACKAGE kadry AS\n  PROCEDURE p;\n",
                                        "END kadry; CREATE OR REPLACE PACKAGE BODY kadry AS\nEND kadry;\n"], units: units) != nil)
        #expect(SpecBodyFiles.mismatch([Self.spec, Self.spec], units: units) == 1)
    }

    @Test("Okno z samą specyfikacją albo samym ciałem: ⌘S proponuje .pks / .pkb")
    func singleUnitExtension() {
        let ws = Workspace()
        let spec = ws.newDocument(.program, text: Self.spec)
        #expect(BuiltinCommands.suggestedFileName(spec, extensions: ws.settings.specBodyExtensions) == ("kadry", "pks"))
        let body = ws.newDocument(.program, text: Self.body)
        #expect(BuiltinCommands.suggestedFileName(body, extensions: ws.settings.specBodyExtensions) == ("kadry", "pkb"))
        let type = ws.newDocument(.program, text: "CREATE OR REPLACE TYPE BODY punkt AS END;\n")
        #expect(BuiltinCommands.suggestedFileName(type, extensions: ws.settings.specBodyExtensions) == ("punkt", "tpb"))
    }

    @Test("Plik pary zmieniony na dysku: Zapisz pyta; Anuluj nie nadpisuje cudzej zmiany")
    func externalChange() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let (s, b) = try writePair()
        let doc = try ws.openFile(s)
        try Data("-- zmiana z zewnątrz\n".utf8).write(to: b)
        doc.text = doc.text.replacingOccurrences(of: "NULL; -- Zażółć", with: "NULL;")
        ui.answers = [1]
        try await ws.invoke("file.save")
        #expect(ui.asked.count == 1 && ui.asked[0].contains("kadry.pkb"))
        #expect(try text(b) == "-- zmiana z zewnątrz\n" && doc.isModified)
        ui.answers = [0]
        try await ws.invoke("file.save")
        #expect(try text(b).contains("NULL;\n") && !doc.isModified)
    }

    @Test("Zmiana na dysku pliku, którego jednostka w oknie się nie zmieniła — bez pytania i bez zapisu tego pliku; ISO-8859-2 bez fałszywego alarmu")
    func externalChangeOfUnwrittenFile() async throws {
        let ws = Workspace()
        let ui = FakeUI()
        ws.ui = ui
        let (s, b) = try writePair()
        let doc = try ws.openFile(s)
        // git checkout zmienia ciało; użytkownik edytuje tylko specyfikację.
        try Data("-- ciało z repozytorium\n".utf8).write(to: b)
        doc.text = doc.text.replacingOccurrences(of: "VARCHAR2);\nEND kadry;", with: "VARCHAR2);\n  PROCEDURE p;\nEND kadry;")
        try await ws.invoke("file.save")
        #expect(ui.asked.isEmpty && !doc.isModified)
        #expect(try text(b) == "-- ciało z repozytorium\n")
        #expect(try text(s).contains("PROCEDURE p;"))
        // Plik jednobajtowy (ISO-8859-2 — heurystyka bez BOM mogłaby wskazać inne kodowanie): zapis bez pytania.
        let ws2 = Workspace()
        let ui2 = FakeUI()
        ws2.ui = ui2
        let ls = dir.appendingPathComponent("latin.pks"), lb = dir.appendingPathComponent("latin.pkb")
        let latinSpec = Self.spec.replacingOccurrences(of: "kadry", with: "latin").replacingOccurrences(of: "specyfikacja", with: "śćźżąę ŚĆŹŻ")
        try latinSpec.data(using: .isoLatin2)!.write(to: ls)
        try Self.body.replacingOccurrences(of: "kadry", with: "latin").data(using: .isoLatin2)!.write(to: lb)
        let d2 = try ws2.openFile(ls)
        #expect(d2.unitFiles.count == 2)
        d2.text = d2.text.replacingOccurrences(of: "NULL; -- Zażółć", with: "NULL; -- zmiana")
        try await ws2.invoke("file.save")
        #expect(ui2.asked.isEmpty && !d2.isModified)
        #expect(try Data(contentsOf: ls) == latinSpec.data(using: .isoLatin2)!)
    }

    @Test("Nieudane Zapisz jako nie usuwa wiszącego dowiązania w miejscu pliku ciała")
    func failedSaveAsKeepsDanglingLink() throws {
        let ws = Workspace()
        let doc = ws.newDocument(.program, text: ProgramText.join([Self.spec, Self.body], slash: false) + "-- 🐦\n")
        doc.fileFormat.encoding = .windowsCP1250
        let s = dir.appendingPathComponent("link.pks"), b = dir.appendingPathComponent("link.pkb")
        try FileManager.default.createSymbolicLink(atPath: b.path, withDestinationPath: dir.appendingPathComponent("brak/cel.pkb").path)
        #expect(throws: (any Error).self) { try ws.saveUnitFiles(doc, spec: s, body: b) }
        #expect((try? FileManager.default.attributesOfItem(atPath: b.path)) != nil)
        #expect(!FileManager.default.fileExists(atPath: s.path) && doc.unitFiles.isEmpty)
    }

    @Test("Nazwa pliku pary z dysku (APFS bez rozróżniania wielkości liter); plik karty widocznej i zmienione pliki bez czytania tekstu")
    func partnerCaseAndShownFile() throws {
        let ws = Workspace()
        let s = dir.appendingPathComponent("Kadry.pks"), b = dir.appendingPathComponent("kadry.pkb")
        try Data(Self.spec.utf8).write(to: s)
        try Data(Self.body.utf8).write(to: b)
        let doc = try ws.openFile(s)
        #expect(doc.unitFiles.map { $0.url.lastPathComponent } == ["Kadry.pks", "kadry.pkb"])
        #expect(try ws.openFile(b).id == doc.id && ws.documents.count == 1)
        doc.shownUnitTab = 1
        #expect(doc.shownFileURL == b.standardizedFileURL)
        doc.shownUnitTab = 0
        #expect(doc.shownFileURL == s.standardizedFileURL)
        #expect(doc.modifiedFileURLs.isEmpty)
        doc.text = doc.text.replacingOccurrences(of: "NULL; -- Zażółć", with: "NULL;")
        #expect(doc.modifiedFileURLs == [b.standardizedFileURL])
    }

    @Test("GRANT sam w linii i z komentarzem za „;” należy do karty specyfikacji")
    func grantVariants() {
        let text = "CREATE PACKAGE g AS END;\n\nGRANT\n  EXECUTE ON g TO a; -- dla a\nrevoke execute on g from b;\n\n-- ciało\nCREATE PACKAGE BODY g AS END;\n"
        let tabs = ProgramUnitTabs.tabs(ProgramCompiler.units(in: text), in: text)
        #expect(tabs.count == 2)
        let ns = text as NSString
        #expect(tabs[1].segment.lowerBound == NSMaxRange(ns.range(of: "from b;\n")))
    }
}
