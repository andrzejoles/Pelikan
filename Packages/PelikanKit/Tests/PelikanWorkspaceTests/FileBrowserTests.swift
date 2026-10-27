import Foundation
@testable import PelikanWorkspace
import Testing

/// Katalog tymczasowy usuwany po teście (nigdy katalog domowy ani dane aplikacji).
final class TempDirectory {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-fb-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ rel: String, _ text: String = "") throws -> URL {
        let u = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: u)
        return u
    }
}

@MainActor
@Suite("File Browser: maski, filtr, operacje, lokalizacje")
struct FileBrowserTests {
    @Test("Maski plików i fragment nazwy")
    func masks() {
        #expect(FileMask.matches("EMP_API.pck", masks: "*.sql;*.pck"))
        #expect(!FileMask.matches("emp.txt", masks: "*.sql;*.pck"))
        #expect(FileMask.matches("a.pks", masks: "*.p?s"))
        #expect(FileMask.matches("anything", masks: ""))
        #expect(FileMask.matches("raport_kwartalny.sql", masks: "kwart"))
    }

    @Test("Lista: katalogi pierwsze, maska lokalizacji, filtr nazwy, rozmiaru, stanu i ukryte")
    func entries() throws {
        let t = try TempDirectory()
        try t.file("b.sql", "select 1 from dual;")
        try t.file("a.pck", "")
        try t.file("notatki.txt", "x")
        try t.file(".ukryty.sql", "")
        try FileManager.default.createDirectory(at: t.url.appendingPathComponent("zz"), withIntermediateDirectories: true)
        let all = FileBrowser.entries(in: t.url)
        #expect(all.map(\.name) == ["zz", "a.pck", "b.sql", "notatki.txt"])
        #expect(FileBrowser.entries(in: t.url, locationMask: "*.sql;*.pck").map(\.name) == ["zz", "a.pck", "b.sql"])
        var f = FileFilter()
        f.minSize = 1
        #expect(FileBrowser.entries(in: t.url, filter: f).map(\.name) == ["zz", "b.sql", "notatki.txt"])
        f = FileFilter()
        f.status = .open
        let open = t.url.appendingPathComponent("a.pck").standardizedFileURL.path
        #expect(FileBrowser.entries(in: t.url, filter: f, openFiles: [open]).map(\.name) == ["zz", "a.pck"])
        #expect(FileBrowser.entries(in: t.url, showHidden: true).contains { $0.name == ".ukryty.sql" })
    }

    @Test("Zmiana nazwy, nowy katalog i plik; nazwy ze ścieżką odrzucone")
    func operations() throws {
        let t = try TempDirectory()
        let f = try t.file("x.sql")
        let renamed = try FileBrowser.rename(f, to: "y.sql")
        #expect(FileManager.default.fileExists(atPath: renamed.path) && !FileManager.default.fileExists(atPath: f.path))
        let dir = try FileBrowser.createFolder(in: t.url, name: "skrypty")
        _ = try FileBrowser.createFile(in: dir, name: "nowy.sql")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("nowy.sql").path))
        #expect(throws: (any Error).self) { try FileBrowser.createFile(in: dir, name: "nowy.sql") }
        for bad in ["../x", "a/b", "..", ""] { #expect(throws: (any Error).self) { try FileBrowser.rename(renamed, to: bad) } }
        #if os(macOS)
        try FileBrowser.trash(renamed)
        #expect(!FileManager.default.fileExists(atPath: renamed.path))
        #endif
    }

    @Test("Lokalizacje z hierarchią i historia filtra zapisane w pliku stanu")
    func persistence() throws {
        let t = try TempDirectory()
        let state = t.url.appendingPathComponent("file-browser.json")
        let fb = FileBrowser(fileURL: state)
        let parent = FileLocation(name: "Projekty", path: t.url.path)
        fb.upsert(parent)
        fb.upsert(FileLocation(name: "SQL", path: t.url.path, filter: "*.sql", color: RGBColor(red: 1, green: 0, blue: 0), parentID: parent.id))
        for n in ["*.sql", "emp", "*.sql"] { fb.remember(filter: n) }
        let again = FileBrowser(fileURL: state)
        #expect(again.children(of: nil).map(\.name) == ["Projekty"] && again.children(of: parent.id).first?.filter == "*.sql")
        #expect(again.filterHistory == ["*.sql", "emp"])
        again.remove(parent.id)
        #expect(again.children(of: nil).map(\.name) == ["SQL"])
    }

    @Test("Komendy: nowy plik otwiera okno, zmiana nazwy przenosi okno, otwórz jako")
    func commands() async throws {
        let t = try TempDirectory()
        let ws = Workspace()
        try await ws.invoke("fb.newFile", CommandArguments(["directory": .string(t.url.path), "name": "proc.prc"]))
        #expect(ws.activeDocument?.kind == .program)
        let path = t.url.appendingPathComponent("proc.prc").path
        try await ws.invoke("fb.rename", CommandArguments(["path": .string(path), "name": "proc2.prc"]))
        #expect(ws.activeDocument?.fileURL?.lastPathComponent == "proc2.prc")
        try await ws.invoke("fb.open", CommandArguments(["path": .string(t.url.appendingPathComponent("proc2.prc").path), "kind": "sql"]))
        #expect(ws.activeDocument?.kind == .program)    // już otwarty — aktywacja istniejącego okna
        let loc = try await ws.invoke("fb.addLocation", CommandArguments(["path": .string(t.url.path), "filter": "*.prc"]))
        #expect(ws.fileBrowser.locations.first?.id.uuidString == loc.value?.stringValue)
    }

    @Test("Przenieś do Kosza katalogu: okna plików z jego wnętrza zostają oknami bez pliku (R6-17)")
    func trashDetachesNested() throws {
        let t = try TempDirectory()
        let ws = Workspace()
        let inner = try ws.openFile(try t.file("dir/sub/a.sql", "select 1 from dual"))
        let sibling = try ws.openFile(try t.file("dir2/b.sql", "select 2 from dual"))
        FileCommands.detachDocuments(under: t.url.appendingPathComponent("dir").standardizedFileURL, in: ws)
        #expect(inner.fileURL == nil && inner.isModified)
        #expect(sibling.fileURL != nil && !sibling.isModified)
    }

    @Test("Zapis okna przez dowiązanie symboliczne: dowiązanie zostaje, plik docelowy ma nowy tekst i dawne uprawnienia (R6-19)")
    func saveKeepsSymlinkAndPermissions() throws {
        let t = try TempDirectory()
        let fm = FileManager.default
        let real = try t.file("real/deploy.sql", "select 1 from dual;\n")
        try fm.setAttributes([.posixPermissions: 0o750], ofItemAtPath: real.path)
        let link = t.url.appendingPathComponent("link.sql")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        let ws = Workspace()
        let doc = try ws.openFile(link)
        doc.text = "select 2 from dual;\n"
        try ws.save(doc, to: link)
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8) == "select 2 from dual;\n")
        #expect((try fm.attributesOfItem(atPath: real.path)[.posixPermissions] as? NSNumber)?.intValue == 0o750)
        #expect(doc.fileURL == link.standardizedFileURL)
    }
}

@Suite("Git: parser stanu")
struct GitParserTests {
    @Test("porcelain v2 -z: gałąź, ahead/behind, zmienione, dodane, przemianowane, konflikt, nieśledzone, ignorowane")
    func parse() {
        let root = URL(fileURLWithPath: "/repo")
        let out = [
            "# branch.oid 0123", "# branch.head main", "# branch.upstream origin/main", "# branch.ab +2 -1",
            "1 .M N... 100644 100644 100644 aaa bbb src/emp api.sql",
            "1 A. N... 000000 100644 100644 000 ccc nowy.pck",
            "1 D. N... 100644 000000 000000 ddd 000 stary.sql",
            "2 R. N... 100644 100644 100644 eee eee R100 nowa_nazwa.sql", "stara_nazwa.sql",
            "u UU N... 100644 100644 100644 100644 a b c konflikt.sql",
            "? tmp/", "? luzny.sql", "! build/",
        ].joined(separator: "\0") + "\0"
        let s = GitStatus.parse(out, root: root)
        #expect(s.branch == "main" && s.ahead == 2 && s.behind == 1)
        #expect(s.files["src/emp api.sql"] == .modified && s.files["nowy.pck"] == .added && s.files["stary.sql"] == .deleted)
        #expect(s.files["nowa_nazwa.sql"] == .renamed && s.files["stara_nazwa.sql"] == nil)
        #expect(s.files["konflikt.sql"] == .conflicted && s.files["luzny.sql"] == .untracked && s.files["build/"] == .ignored)
        #expect(s.state(of: URL(fileURLWithPath: "/repo/tmp/a.sql")) == .untracked)
        #expect(s.state(of: URL(fileURLWithPath: "/inne/a.sql")) == nil)
    }
}

@Suite("Git: tymczasowe repozytorium", .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")), .serialized)
struct GitRepositoryTests {
    @Test("Stan, add, commit (komunikat przez stdin), HEAD i historia")
    func workflow() throws {
        let t = try TempDirectory()
        let dir = t.url
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "Test"], ["config", "user.email", "test@example.invalid"],
                     ["config", "commit.gpgsign", "false"]] {
            try GitRepository.run(args, in: dir)
        }
        let f = try t.file("emp.sql", "select 1 from dual;\n")
        let repo = try #require(GitRepository.discover(for: f))
        #expect(try repo.status().state(of: f) == .untracked)
        #expect(try repo.log().isEmpty)
        try repo.add([f])
        #expect(try repo.status().state(of: f) == .added)
        let hash = try repo.commit(message: "Pierwszy skrypt — zażółć")
        #expect(!hash.isEmpty)
        #expect(try repo.status().state(of: f) == .unmodified && repo.status().branch == "main")
        try Data("select 2 from dual;\n".utf8).write(to: f)
        #expect(try repo.status().state(of: f) == .modified)
        #expect(try repo.headContent(of: f) == Data("select 1 from dual;\n".utf8))
        #expect(try repo.headContent(of: try t.file("nowy.sql")) == nil)
        let log = try repo.log(file: f)
        #expect(log.count == 1 && log[0].subject == "Pierwszy skrypt — zażółć" && log[0].author == "Test")
        #expect(throws: (any Error).self) { try repo.commit(message: "  ") }
        // Plik ISO-8859-2: treść z HEAD w bajtach, bez strat (dekodowanie jak pliku na dysku).
        let latin2 = Data([0x2D, 0x2D, 0x20, 0xB6, 0x77, 0x69, 0xEA, 0x74, 0x79, 0x0A])   // „-- święty”
        let l = try t.file("pl.sql")
        try latin2.write(to: l)
        try repo.add([l])
        _ = try repo.commit(message: "latin2")
        #expect(try repo.headContent(of: l) == latin2)
        #expect(TextFileCodec.decode(try #require(try repo.headContent(of: l))).text == "-- święty\n")
    }

    @Test("Stan Git plików projektu: gałąź, zmieniony, nieśledzony, bez zmian; projekt poza repozytorium — nil")
    @MainActor func projectStatus() throws {
        let t = try TempDirectory()
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "Test"], ["config", "user.email", "test@example.invalid"],
                     ["config", "commit.gpgsign", "false"]] {
            try GitRepository.run(args, in: t.url)
        }
        let a = try t.file("src/a.sql", "select 1 from dual;\n")
        let b = try t.file("src/b.sql", "select 2 from dual;\n")
        let repo = try #require(GitRepository.discover(for: a))
        try repo.add([a, b])
        _ = try repo.commit(message: "start")
        try Data("select 3 from dual;\n".utf8).write(to: b)
        _ = try t.file("src/c.sql", "nowy")
        var p = Project(name: "p")
        p.items = [.file("src/a.sql"), .file("src/b.sql"), .file("src/c.sql"), .note("n")]
        let projectURL = t.url.appendingPathComponent("p.pelikanproj")
        let s = try #require(ProjectEngine.gitStatus(of: p, projectURL: projectURL))
        #expect(s.branch == "main")
        #expect(s.items[p.items[0].id] == .unmodified && s.items[p.items[1].id] == .modified && s.items[p.items[2].id] == .untracked)
        #expect(s.items[p.items[3].id] == nil)
        let outside = try TempDirectory()
        #expect(ProjectEngine.gitStatus(of: p, projectURL: outside.url.appendingPathComponent("p.pelikanproj")) == nil)
    }
}

@MainActor
@Suite("Worksety i układ okna")
struct WorksetTests {
    @Test("Przełączanie zachowuje niezapisane okna; pliki otwierane ponownie; przywracanie i usuwanie")
    func switching() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let f = try t.file("plik.sql", "select 1 from dual;")
        try ws.openFile(f)
        let scratch = ws.newDocument(.program, text: "create package p as end;")
        scratch.selectedRange = 3..<5
        try await ws.invoke("workset.new", CommandArguments(["name": "Raporty"]))
        #expect(ws.documents.isEmpty && ws.worksets.current == "Raporty")
        _ = ws.newDocument(.sql, text: "select 'raport' from dual")
        try await ws.invoke("workset.open", CommandArguments(["name": .string(WorksetStore.defaultName)]))
        #expect(ws.documents.count == 2)
        #expect(ws.documents.contains { $0.fileURL?.lastPathComponent == "plik.sql" && !$0.isModified })
        let restored = try #require(ws.documents.first { $0.kind == .program })
        #expect(restored.text == "create package p as end;" && restored.fileURL == nil && restored.selectedRange == 3..<5)
        #expect(ws.worksets.names.sorted() == ["Domyślny", "Raporty"].sorted())
        // Nowy Workspace na tym samym katalogu danych widzi bieżący workset i jego okna.
        let ws2 = Workspace(dataDirectory: t.url)
        #expect(ws2.worksets.current == WorksetStore.defaultName)
        let saved = try #require(try ws2.worksets.load("Raporty"))
        #expect(saved.documents.first?.text == "select 'raport' from dual")
        // Przywrócenie zapisanego stanu odrzuca późniejsze zmiany.
        restored.text = "zmiana"
        try await ws.invoke("workset.revert")
        #expect(ws.documents.first { $0.kind == .program }?.text == "create package p as end;")
        try await ws.invoke("workset.delete", CommandArguments(["name": "Raporty"]))
        #expect(!ws.worksets.names.contains("Raporty"))
        await #expect(throws: (any Error).self) { try await ws.invoke("workset.new", CommandArguments(["name": "../x"])) }
    }

    @Test("Porównanie worksetów: z bieżącymi oknami i dwóch zapisanych; treść pliku z dysku")
    func compare() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let f = try t.file("a.sql", "select 1 from dual;")
        try ws.openFile(f)
        _ = ws.newDocument(.sql, text: "select 'tylko w domyślnym' from dual")
        try ws.saveCurrentWorkset()
        try await ws.invoke("workset.new", CommandArguments(["name": "Drugi"]))
        try ws.openFile(f)
        _ = ws.newDocument(.sql, text: "select 'tylko w drugim' from dual")
        let current = try await ws.invoke("workset.compare", CommandArguments(["name": .string(WorksetStore.defaultName)]))
        guard case .string(let diff)? = current.value else { Issue.record("brak różnicy"); return }
        #expect(diff.contains("-select 'tylko w drugim' from dual") && diff.contains("+select 'tylko w domyślnym' from dual"))
        #expect(!diff.contains("-select 1 from dual;"))
        try ws.saveCurrentWorkset()
        let saved = try await ws.invoke("workset.compare", CommandArguments(["name": "Drugi", "with": "Drugi"]))
        #expect(saved.message == "Brak różnic")
        let d = try #require(try ws.worksets.load("Drugi"))
        #expect(d.comparisonText().contains("=== [sql] a.sql\nselect 1 from dual;"))
    }

    @Test("Brakujący plik pomijany; pliki workseta z uprawnieniami 0600; układ okna zapisany i odczytany")
    func missingAndLayout() async throws {
        let t = try TempDirectory()
        let ws = Workspace(dataDirectory: t.url)
        let f = try t.file("zniknie.sql", "x")
        try ws.openFile(f)
        try ws.saveCurrentWorkset()
        let attrs = try FileManager.default.attributesOfItem(atPath: t.url.appendingPathComponent("Worksets/Domyślny.json").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        try FileManager.default.removeItem(at: f)
        let missing = try await ws.applyWorkset(try #require(try ws.worksets.load(WorksetStore.defaultName)))
        #expect(missing.count == 1 && ws.documents.isEmpty)
        let layout = WindowLayout(frame: "{{10, 20}, {1200, 800}}", sidebarWidth: 260, sidebarPane: 4, agentPaneVisible: true)
        ws.worksets.saveLayout(layout)
        #expect(Workspace(dataDirectory: t.url).worksets.loadLayout() == layout)
    }
}
