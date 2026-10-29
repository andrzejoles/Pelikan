import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Git: pliki zmienione w gałęzi (D201)",
       .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")), .serialized)
struct BranchChangesTests {
    func git(_ args: [String], _ dir: URL) throws { try GitRepository.run(args, in: dir) }

    func repo(_ t: TempDirectory) throws -> URL {
        let dir = t.url.appendingPathComponent("kadry")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "Test"], ["config", "user.email", "test@example.invalid"],
                     ["config", "commit.gpgsign", "false"]] { try git(args, dir) }
        return dir
    }

    @Test("Zmiany gałęzi: od punktu rozgałęzienia z origin/main, niezatwierdzone, nieśledzone; bez usuniętych i binarnych")
    func changedFiles() throws {
        let t = try TempDirectory()
        let dir = try repo(t)
        for f in ["stary.sql", "usuwany.sql", "zmieniany.sql", "pensje.pks", "pensje.pkb"] { try t.file("kadry/" + f, "-- \(f)\n") }
        try git(["add", "."], dir)
        try git(["commit", "-q", "-m", "start"], dir)
        let bare = t.url.appendingPathComponent("zdalne.git")
        try git(["init", "-q", "--bare", bare.path], t.url)
        try git(["remote", "add", "origin", bare.path], dir)
        try git(["push", "-q", "origin", "main"], dir)
        try git(["fetch", "-q", "origin"], dir)
        try git(["checkout", "-q", "-b", "zadanie"], dir)
        // Zatwierdzone w gałęzi.
        try t.file("kadry/nowy_w_galezi.sql", "select 1 from dual;\n")
        try t.file("kadry/pensje.pks", "-- zmiana specyfikacji\n")
        try t.file("kadry/pensje.pkb", "-- zmiana ciała\n")
        try Data([0x00, 0x01, 0x02]).write(to: dir.appendingPathComponent("obraz.bin"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("usuwany.sql"))
        try git(["add", "-A"], dir)
        try git(["commit", "-q", "-m", "zadanie"], dir)
        // Niezatwierdzone i nieśledzone.
        try t.file("kadry/zmieniany.sql", "-- zmieniony\n")
        try t.file("kadry/nieśledzony.sql", "-- nowy\n")
        try Data([0x00, 0xFF]).write(to: dir.appendingPathComponent("binarny.sql"))
        try t.file("kadry/.gitignore", "ignorowany.sql\n")
        try t.file("kadry/ignorowany.sql", "-- ignorowany\n")
        let repo = try #require(GitRepository.discover(for: dir))
        #expect(repo.branchBase() != nil)
        let names = try repo.branchChangedFiles().map(\.lastPathComponent)
        #expect(Set(names) == ["nowy_w_galezi.sql", "pensje.pks", "pensje.pkb", "zmieniany.sql", "nieśledzony.sql", ".gitignore"])
    }

    @Test("Bez zdalnego i bez upstream — tylko zmiany niezatwierdzone")
    func noRemote() throws {
        let t = try TempDirectory()
        let dir = try repo(t)
        try t.file("kadry/a.sql", "-- a\n")
        try git(["add", "."], dir)
        try git(["commit", "-q", "-m", "start"], dir)
        try t.file("kadry/b.sql", "-- b\n")
        try git(["add", "."], dir)
        try git(["commit", "-q", "-m", "b"], dir)
        try t.file("kadry/a.sql", "-- a2\n")
        let repo = try #require(GitRepository.discover(for: dir))
        #expect(repo.branchBase() == nil)
        #expect(try repo.branchChangedFiles().map(\.lastPathComponent) == ["a.sql"])
    }

    @MainActor
    @Test("Komenda: otwiera pozostałe pliki kodu, pomija otwarte; para specyfikacji i ciała — jedno okno")
    func command() async throws {
        let t = try TempDirectory()
        let dir = try repo(t)
        try t.file("kadry/a.sql", "-- a\n")
        try git(["add", "."], dir)
        try git(["commit", "-q", "-m", "start"], dir)
        for f in ["b.sql", "pensje.pks", "pensje.pkb", "opis.md"] {
            try t.file("kadry/" + f, f.hasSuffix(".pks") ? "create or replace package pensje is\nend;\n"
                       : f.hasSuffix(".pkb") ? "create or replace package body pensje is\nend;\n" : "-- \(f)\n")
        }
        try t.file("kadry/a.sql", "-- a2\n")
        let ws = Workspace()
        let a = try ws.openFile(dir.appendingPathComponent("a.sql"))
        let r = try await ws.invoke("vcs.openBranchChanges")
        #expect(r.value == .int(2))
        #expect(ws.documents.count == 3 && ws.activeDocumentID == a.id)
        #expect(ws.documents.contains { $0.unitFiles.count == 2 })
        let again = try await ws.invoke("vcs.openBranchChanges")
        #expect(again.value == .int(0) && ws.documents.count == 3)
    }
}
