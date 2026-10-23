import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Tytuł okna, katalogi startowe i rozszerzenia plików")
struct WorkspaceTitlesTests {
    @Test("Tytuł z połączeniem głównym i worksetem; podtytuł z połączeniem okna, gdy inne niż główne")
    func titles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("titles-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(dataDirectory: dir)
        #expect(ws.windowTitle(appName: "Pelikan") == "Pelikan")
        let a = ConnectionDefinition(name: "dev", target: ConnectionTarget(user: "hr", connectString: "db1"))
        let b = ConnectionDefinition(name: "prod", target: ConnectionTarget(user: "hr", connectString: "db2"))
        try ws.connections.upsert(a)
        try ws.connections.upsert(b)
        ws.sessions.setMainConnection(a.id)
        #expect(ws.windowTitle(appName: "Pelikan") == "Pelikan — dev")
        try ws.switchWorkset(to: "Raporty")
        #expect(ws.windowTitle(appName: "Pelikan") == "Pelikan — dev — Raporty")
        let d = ws.newDocument(.sql)
        #expect(ws.windowSubtitle() == d.fullTitle)
        d.connectionID = b.id
        d.connectionPinned = true
        #expect(ws.windowSubtitle() == d.fullTitle + " @ prod")
    }

    @Test("Katalog startowy z Preferencji (istniejący), inaczej katalog projektu; rozszerzenia programów i testów")
    func directoriesAndExtensions() throws {
        let ws = Workspace()
        let tmp = FileManager.default.temporaryDirectory
        ws.settings.startDirectories = ["program": tmp.path, "test": "/nie/ma/takiego"]
        #expect(ws.startDirectory(for: "program")?.standardizedFileURL.path == tmp.standardizedFileURL.path)
        #expect(ws.startDirectory(for: "test") == nil && ws.startDirectory(for: "sql") == nil)
        #expect(ws.documentKind(for: URL(fileURLWithPath: "/a/x.pls")) == .sql)
        ws.settings.programExtensions = ["pls", "plb"]
        ws.settings.testExtensions = ["pt"]
        #expect(ws.documentKind(for: URL(fileURLWithPath: "/a/x.PLS")) == .program)
        #expect(ws.documentKind(for: URL(fileURLWithPath: "/a/x.pt")) == .test)
        #expect(ws.documentKind(for: URL(fileURLWithPath: "/a/x.pck")) == .program)
    }
}
