import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Katalog danych dla przebiegu zrzutów w tle (scripts/screenshots.sh, D30): połączenie z bazą testową przez portfel
/// z magazynem haseł (SEPS) — bez hasła w plikach, środowisku i Pęku kluczy. Uruchamiany tylko z PELIKAN_SCREENSHOT_FIXTURE.
@MainActor
@Suite("Dane przebiegu zrzutów", .enabled(if: ProcessInfo.processInfo.environment["PELIKAN_SCREENSHOT_FIXTURE"] != nil))
struct ScreenshotFixtureTests {
    @Test("Katalog danych z ustawieniami Oracle Net i połączeniem portfelowym")
    func fixture() throws {
        let env = ProcessInfo.processInfo.environment
        let dir = URL(fileURLWithPath: env["PELIKAN_SCREENSHOT_FIXTURE"]!)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../.testdb").standardizedFileURL
        let ws = Workspace(dataDirectory: dir)
        ws.settings.oracleNetDirectory = root.appendingPathComponent("oracle-net-user").path
        ws.settings.walletDirectory = root.appendingPathComponent("wallet").path
        // Kopia Instant Client poza chronionym folderem Pobrane (bez pytania macOS o dostęp — przebieg nie może przerywać pracy).
        ws.settings.instantClientDirectory = root.appendingPathComponent("instantclient").path
        ws.settings.worksetAutosave = false
        ws.settings.recoveryEnabled = false
        var target = ConnectionTarget(user: "", connectString: "dev_pelikan_seps")
        target.walletAuth = true
        var def = ConnectionDefinition(name: "dev_baza_testowa", target: target, connectOnStartup: true)
        def.environment = .test
        try ws.connections.upsert(def)
        // Drugie połączenie do tej samej bazy — drzewo Object Browsera z kilkoma połączeniami (D185, scenariusz 62).
        var second = ConnectionDefinition(name: "dev_baza_druga", target: target)
        second.environment = .development
        try ws.connections.upsert(second)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("connections.json").path))
    }
}
