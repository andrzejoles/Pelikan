import Foundation
import Observation

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
    nonisolated public static let maxEntries = 50
    nonisolated public static let maxAge: TimeInterval = 30 * 24 * 3600

    let directory: URL?
    /// Pozycje otwarte w oknie historii (i wszystkie, gdy historia jest tylko w pamięci, bez katalogu). Zapis wersji
    /// pozycji spoza pamięci nie wczytuje jej na wątku głównym ani nie zostawia w pamięci do końca sesji.
    @ObservationIgnored private var cache: [String: LocalHistoryItem] = [:]
    /// Odczyty do dopisania wersji i zapisy na dysk po kolei poza głównym wątkiem (do 50 pełnych wersji dużego
    /// pakietu to dziesiątki MB JSON — dekodowanie, kodowanie i zapis przy każdym ⌘S i kompilacji blokowałyby interfejs).
    @ObservationIgnored private let writes = DispatchQueue(label: "LocalHistory.writes", qos: .utility)
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

    nonisolated static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func url(_ key: String) -> URL? { directory?.appendingPathComponent(Self.fileName(key)) }

    /// Pozycja (okno historii): po zaplanowanych zapisach, z dysku do pamięci podręcznej.
    public func item(_ key: String) -> LocalHistoryItem? {
        if let c = cache[key] { return c }
        guard let u = url(key) else { return nil }
        writes.sync {}
        guard let item = Self.read(u, key: key) else { return nil }
        cache[key] = item
        return item
    }

    nonisolated static func read(_ u: URL, key: String) -> LocalHistoryItem? {
        guard let data = try? Data(contentsOf: u), let item = try? decoder.decode(LocalHistoryItem.self, from: data), item.key == key else { return nil }
        return item
    }

    /// Wersje od najnowszej.
    public func entries(_ key: String) -> [LocalHistoryEntry] { (item(key)?.entries ?? []).reversed() }

    /// Dopisanie wersji (pomijane, gdy tekst jak w ostatniej); najstarsze ponad limit liczby i wieku są usuwane.
    /// Pozycja spoza pamięci jest wczytywana i uzupełniana w kolejce zapisów, nie na wątku głównym.
    public func record(key: String, title: String, text: String, label: String, date: Date = Date()) {
        let entry = LocalHistoryEntry(date: date, label: label, text: text)
        let u = url(key)
        if u == nil || cache[key] != nil {
            var item = cache[key] ?? LocalHistoryItem(key: key, title: title, entries: [])
            if item.entries.last?.text == text { return }
            item.title = title
            item.entries = Self.appending(entry, to: item.entries)
            cache[key] = item
            revision += 1
            guard let u else { return }
            let saved = item
            writes.async { Self.write(saved, to: u) }
            return
        }
        guard let u else { return }
        writes.async {
            var item = Self.read(u, key: key) ?? LocalHistoryItem(key: key, title: title, entries: [])
            guard item.entries.last?.text != text else { return }
            item.title = title
            item.entries = Self.appending(entry, to: item.entries)
            Self.write(item, to: u)
        }
        revision += 1
    }

    nonisolated static func appending(_ entry: LocalHistoryEntry, to entries: [LocalHistoryEntry]) -> [LocalHistoryEntry] {
        Array((entries + [entry]).filter { entry.date.timeIntervalSince($0.date) <= maxAge }.suffix(maxEntries))
    }

    /// Czeka na zapis wszystkich wersji na dysk (zamknięcie aplikacji, testy).
    public func flush() { writes.sync {} }

    nonisolated static func write(_ item: LocalHistoryItem, to u: URL) {
        // Pełny tekst okien — katalog i plik tylko dla właściciela.
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(item) {
            try? data.write(to: u, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
        }
    }

    public func clear(_ key: String) {
        cache[key] = nil
        revision += 1
        guard let u = url(key) else { return }
        // Po zaplanowanych zapisach — inaczej zapis w toku odtworzyłby usunięty plik.
        writes.async { try? FileManager.default.removeItem(at: u) }
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
