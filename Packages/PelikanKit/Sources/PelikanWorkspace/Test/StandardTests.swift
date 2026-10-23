import Foundation

/// Testy standardowe (PD-TEST-009): szablony okna testu (`.tst`) w katalogu danych `StandardTests/`, stosowane do
/// procedury albo funkcji z menu obiektu. Wywołanie programu (notacja nazwana, jak „Testuj”) trafia w miejsce znacznika
/// `%CALL%` w bloku szablonu, a bez znacznika — na koniec; zmienne szablonu dochodzą do zmiennych wywołania.
public struct StandardTestStore: Sendable {
    public static let marker = "%CALL%"
    public let directory: URL?

    public init(dataDirectory: URL?) {
        directory = dataDirectory?.appendingPathComponent("StandardTests", isDirectory: true)
    }

    public var names: [String] {
        guard let d = directory, let files = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { return [] }
        return files.filter { $0.hasSuffix(".tst") }.map { String($0.dropLast(4)) }.sorted()
    }

    func url(_ name: String) throws -> URL {
        guard let d = directory else { throw CommandError.notAvailable(L10n.tr("Brak katalogu danych")) }
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { throw CommandError.invalidArgument("name", name) }
        return d.appendingPathComponent(name + ".tst")
    }

    public func load(_ name: String) throws -> TestScriptFile {
        TestScriptFile.decode(TextFileCodec.decode(try Data(contentsOf: url(name))).text)
    }

    public func save(_ name: String, _ file: TestScriptFile) throws {
        let u = try url(name)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.encoded().write(to: u, options: .atomic)
    }

    public func delete(_ name: String) throws { try FileManager.default.removeItem(at: url(name)) }

    /// Blok i zmienne testu standardowego dla wygenerowanego wywołania.
    public static func apply(_ template: TestScriptFile, call: String, variables: [TestVariable]) -> (String, [TestVariable]) {
        let block = template.block.contains(marker) ? template.block.replacingOccurrences(of: marker, with: call)
            : template.block.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + call
        var vars = variables
        for v in template.variables where !vars.contains(where: { $0.name.caseInsensitiveCompare(v.name) == .orderedSame }) { vars.append(v) }
        return (block, vars)
    }
}
