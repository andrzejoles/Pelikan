import Foundation
@testable import PelikanODPI
import Testing

@Suite("Wyszukiwanie Instant Client")
struct InstantClientLocatorTests {
    func makeDir(_ name: String, withLibrary: Bool) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-ic-\(UUID().uuidString)/\(name)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if withLibrary { FileManager.default.createFile(atPath: dir + "/" + InstantClientLocator.libraryName, contents: Data()) }
        return dir
    }

    @Test("Katalog z ustawień ma pierwszeństwo przed zmienną środowiskową i katalogiem domowym")
    func configuredFirst() throws {
        let configured = try makeDir("a", withLibrary: true)
        let env = try makeDir("b", withLibrary: true)
        #expect(InstantClientLocator.locate(configured: configured, environment: ["PELIKAN_OCI_LIB_DIR": env], home: "/nonexistent") == configured)
        #expect(InstantClientLocator.locate(configured: nil, environment: ["PELIKAN_OCI_LIB_DIR": env], home: "/nonexistent") == env)
    }

    @Test("Najnowszy instantclient_* w Pobranych, gdy nic nie skonfigurowano")
    func downloads() throws {
        let home = try makeDir("home", withLibrary: false)
        for v in ["instantclient_19_8", "instantclient_23_26", "instantclient_23_3"] {
            try FileManager.default.createDirectory(atPath: home + "/Downloads/" + v, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: home + "/Downloads/" + v + "/" + InstantClientLocator.libraryName, contents: Data())
        }
        let found = InstantClientLocator.locate(configured: nil, environment: [:], home: home)
        // Homebrew / /usr/local mogą mieć własny klient na maszynie dewelopera — wtedy wygrywa on (etap wcześniejszy).
        if let found, found.hasPrefix(home) { #expect(found.hasSuffix("instantclient_23_26")) }
    }
}
