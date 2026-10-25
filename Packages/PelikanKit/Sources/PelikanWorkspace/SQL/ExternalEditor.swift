import Foundation

/// Edycja komórki w edytorze zewnętrznym (UG 27.2, PD-LDE-002): treść w pliku tymczasowym (0600) z rozszerzeniem
/// wg formatu (np. `.rtf` dla RTF), zmiany wykrywane po dacie modyfikacji i wczytywane do modelu.
@MainActor
public final class ExternalLargeDataEdit {
    public let model: LargeDataModel
    public private(set) var url: URL?
    private var lastModified: Date?

    public init(model: LargeDataModel) { self.model = model }

    /// Zapisuje treść do pliku tymczasowego i zwraca jego adres (do otwarcia programem skojarzonym z rozszerzeniem).
    public func start() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-lde-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = model.columnName.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let file = dir.appendingPathComponent("\(name.isEmpty ? "wartosc" : name).\(model.format.fileExtension)")
        _ = FileManager.default.createFile(atPath: file.path, contents: model.fileData, attributes: [.posixPermissions: 0o600])
        url = file
        lastModified = modificationDate(file)
        return file
    }

    private func modificationDate(_ u: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
    }

    /// Wczytuje plik, jeśli zmienił się od ostatniego sprawdzenia; `true` — model zaktualizowany.
    @discardableResult
    public func checkForChanges() -> Bool {
        guard let u = url, let m = modificationDate(u), m != lastModified, let data = try? Data(contentsOf: u) else { return false }
        lastModified = m
        if model.isBinary || !model.format.isText {
            model.setBytes(data)
        } else {
            model.setText(String(decoding: data, as: UTF8.self))
        }
        return true
    }

    /// Usuwa plik tymczasowy (zamknięcie edytora dużych danych).
    public func finish() {
        if let u = url { try? FileManager.default.removeItem(at: u.deletingLastPathComponent()) }
        url = nil
    }
}
