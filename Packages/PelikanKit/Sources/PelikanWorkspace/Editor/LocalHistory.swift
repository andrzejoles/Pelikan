import Foundation

/// Wersja tekstu w historii lokalnej (DG-HIST-001).
public struct LocalHistoryEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    /// Zdarzenie: zapis pliku, kompilacja obiektu, przed przywróceniem, przed refaktoryzacją…
    public var label: String
    public var text: String

    public init(id: UUID = UUID(), date: Date = Date(), label: String, text: String) {
        self.id = id; self.date = date; self.label = label; self.text = text
    }
}

/// Historia jednego pliku albo obiektu bazy.
public struct LocalHistoryItem: Codable, Sendable, Hashable, Identifiable {
    public var key: String
    public var title: String
    /// Najnowsze na końcu.
    public var entries: [LocalHistoryEntry]
    public var id: String { key }
}

/// Lokalna historia plików i obiektów: wersje z czasem przy zapisie, kompilacji, refaktoryzacji i przywróceniu;
/// porównanie i przywracanie. Przechowywana w katalogu danych aplikacji (jeden plik JSON na plik/obiekt), bez bazy.
@MainActor
@Observable
public final class LocalHistory {
    public static let maxEntries = 50
    public static let maxAge: TimeInterval = 30 * 24 * 3600

    let directory: URL?
    @ObservationIgnored private var cache: [String: LocalHistoryItem] = [:]
    /// Licznik zmian (odświeżanie okna historii).
    public private(set) var revision = 0

    public init(directory: URL?) { self.directory = directory }

    // MARK: Klucze

    public static func key(file url: URL) -> String { "file:" + url.standardizedFileURL.path }

    public static func key(object owner: String, type: String, name: String, connection: UUID?) -> String {
        "object:\(connection?.uuidString ?? "-")/\(owner.uppercased()).\(type.uppercased()).\(name.uppercased())"
    }

    public static func key(console connection: UUID) -> String { "console:" + connection.uuidString }

    /// Klucz historii okna: plik, konsola połączenia albo (okno programu bez pliku) pierwsza jednostka obiektu
    /// (bez właściciela w nagłówku — schemat bieżący połączenia, jak przy kompilacji).
    public func key(for doc: Document, connection: UUID?, schema: String? = nil) -> (key: String, title: String)? {
        if let u = doc.fileURL { return (Self.key(file: u), u.lastPathComponent) }
        if let c = doc.consoleConnectionID { return (Self.key(console: c), doc.title) }
        if doc.kind == .program, let u = ProgramCompiler.units(in: doc.text).first {
            let owner = u.owner ?? schema
            return (Self.key(object: owner ?? "-", type: u.type.rawValue, name: u.name, connection: connection),
                    "\(owner.map { "\($0)." } ?? "")\(u.name) (\(u.type.rawValue))")
        }
        return nil
    }

    // MARK: Zapis i odczyt

    /// Nazwa pliku z klucza: czytelny początek + skrót FNV-1a (klucze zawierają ścieżki i znaki specjalne).
    static func fileName(_ key: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        let readable = String(key.split(separator: "/").last ?? "").filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
        return "\(readable.prefix(40))-\(String(h, radix: 16)).json"
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func url(_ key: String) -> URL? { directory?.appendingPathComponent(Self.fileName(key)) }

    public func item(_ key: String) -> LocalHistoryItem? {
        if let c = cache[key] { return c }
        guard let u = url(key), let data = try? Data(contentsOf: u),
              let item = try? Self.decoder.decode(LocalHistoryItem.self, from: data), item.key == key else { return nil }
        cache[key] = item
        return item
    }

    /// Wersje od najnowszej.
    public func entries(_ key: String) -> [LocalHistoryEntry] { (item(key)?.entries ?? []).reversed() }

    /// Dopisanie wersji (pomijane, gdy tekst jak w ostatniej); najstarsze ponad limit liczby i wieku są usuwane.
    public func record(key: String, title: String, text: String, label: String, date: Date = Date()) {
        var item = item(key) ?? LocalHistoryItem(key: key, title: title, entries: [])
        if item.entries.last?.text == text { return }
        item.title = title
        item.entries.append(LocalHistoryEntry(date: date, label: label, text: text))
        item.entries = Array(item.entries.filter { date.timeIntervalSince($0.date) <= Self.maxAge }.suffix(Self.maxEntries))
        cache[key] = item
        revision += 1
        guard let u = url(key) else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(item) { try? data.write(to: u, options: .atomic) }
    }


    /// Wszystkie pozycje historii (od ostatnio zmienianej).
    public func allItems() -> [LocalHistoryItem] {
        if let dir = directory, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let dec = Self.decoder
            for f in files where f.pathExtension == "json" {
                if let data = try? Data(contentsOf: f), let item = try? dec.decode(LocalHistoryItem.self, from: data), cache[item.key] == nil {
                    cache[item.key] = item
                }
            }
        }
        return cache.values.sorted { ($0.entries.last?.date ?? .distantPast) > ($1.entries.last?.date ?? .distantPast) }
    }

    public func clear(_ key: String) {
        cache[key] = nil
        if let u = url(key) { try? FileManager.default.removeItem(at: u) }
        revision += 1
    }
}

extension Workspace {
    /// Klucz historii lokalnej okna (połączenie i schemat okna).
    public func historyKey(for doc: Document) -> (key: String, title: String)? {
        let c = effectiveConnection(of: doc)
        return localHistory.key(for: doc, connection: c, schema: sessions.connectedSchema(c))
    }

    /// Wersja okna w historii (klucz z pliku, konsoli albo obiektu); okno bez klucza — pominięte.
    public func recordHistory(_ doc: Document, text: String? = nil, label: String) {
        guard let (key, title) = historyKey(for: doc) else { return }
        localHistory.record(key: key, title: title, text: text ?? doc.text, label: label)
    }

    /// Przywrócenie wersji w oknie (bieżący tekst trafia do historii, więc przywrócenie da się cofnąć).
    public func restore(_ entry: LocalHistoryEntry, in doc: Document) {
        recordHistory(doc, label: L10n.tr("przed przywróceniem"))
        doc.text = entry.text
        doc.selectedRange = 0..<0
    }
}
