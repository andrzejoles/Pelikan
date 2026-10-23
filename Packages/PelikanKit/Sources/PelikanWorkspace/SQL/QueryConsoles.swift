import Foundation

/// Konsole zapytań połączeń (DG-CONS-001): jedno okno SQL na połączenie, którego tekst jest zachowywany automatycznie
/// (zamknięcie okna, zakończenie aplikacji, okresowo) w katalogu danych i przywracany przy ponownym otwarciu.
@MainActor
public final class QueryConsoles {
    let directory: URL?
    /// Teksty bez katalogu danych (testy).
    private var memory: [UUID: String] = [:]

    public init(directory: URL?) { self.directory = directory }

    func url(_ connection: UUID) -> URL? { directory?.appendingPathComponent(connection.uuidString + ".sql") }

    public func text(for connection: UUID) -> String {
        if let u = url(connection), let data = try? Data(contentsOf: u) { return TextFileCodec.decode(data).text }
        return memory[connection] ?? ""
    }

    public func save(_ text: String, for connection: UUID) {
        memory[connection] = text
        guard let u = url(connection) else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: u, options: .atomic)
    }

    /// Zapis tekstu okna konsoli (inne okna — bez zmian).
    public func persist(_ doc: Document) {
        guard let c = doc.consoleConnectionID else { return }
        save(doc.text, for: c)
        doc.isModified = false
    }
}

extension Workspace {
    /// Otwiera (albo aktywuje) konsolę połączenia: okno SQL przypięte do połączenia z zachowanym tekstem.
    @discardableResult
    public func openConsole(connection: UUID) -> Document {
        if let d = documents.first(where: { $0.consoleConnectionID == connection }) {
            activeDocumentID = d.id
            return d
        }
        let d = newDocument(.sql, text: consoles.text(for: connection))
        d.consoleConnectionID = connection
        d.connectionID = connection
        d.connectionPinned = true
        let name = connections.connection(connection)?.displayName ?? ""
        d.customTitle = name.isEmpty ? L10n.tr("Konsola") : L10n.tr("Konsola \(name)")
        d.isModified = false
        let end = (d.text as NSString).length
        d.selectedRange = end..<end
        return d
    }

    /// Zapis wszystkich otwartych konsol (zakończenie aplikacji, zapis okresowy).
    public func persistConsoles() {
        for d in documents where d.consoleConnectionID != nil && d.isModified { consoles.persist(d) }
    }
}
