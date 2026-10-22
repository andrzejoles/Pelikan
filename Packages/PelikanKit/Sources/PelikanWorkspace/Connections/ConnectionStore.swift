import Foundation
import Observation
import PelikanDB

/// Lista połączeń (UG 19): foldery, definicje, połączenia ostatnio używane. Zapis do `connections.json` w katalogu danych
/// aplikacji — **bez haseł** (hasła w `SecretStore`).
@MainActor
@Observable
public final class ConnectionStore {
    public private(set) var folders: [ConnectionFolder] = []
    public private(set) var connections: [ConnectionDefinition] = []
    /// Hasła podane w tej sesji aplikacji dla połączeń bez zapisu hasła (tylko pamięć).
    @ObservationIgnored private var sessionPasswords: [UUID: String] = [:]
    /// Połączenia tymczasowe (CONNECT w Command Window z hasłem w poleceniu) — nie trafiają do listy ani do pliku.
    @ObservationIgnored private var temporary: [UUID: ConnectionDefinition] = [:]
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let fileURL: URL?

    private struct Snapshot: Codable {
        var version = 1
        var folders: [ConnectionFolder]
        var connections: [ConnectionDefinition]
    }

    /// - Parameter fileURL: nil = bez zapisu (testy, `Workspace(persists: false)`).
    public init(fileURL: URL?, secrets: any SecretStore) {
        self.fileURL = fileURL
        self.secrets = secrets
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let snap = try? JSONDecoder.pelikan.decode(Snapshot.self, from: data) {
            folders = snap.folders
            connections = snap.connections
        }
    }

    public func save() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.pelikan.encode(Snapshot(folders: folders, connections: connections))
        try data.write(to: fileURL, options: [.atomic])
    }

    // MARK: Definicje

    public func connection(_ id: UUID) -> ConnectionDefinition? { connections.first { $0.id == id } ?? temporary[id] }

    /// Rejestruje połączenie tymczasowe (tylko pamięć, hasło nie trafia do Pęku kluczy ani do pliku).
    public func registerTemporary(_ def: ConnectionDefinition, password: String?) {
        var d = def
        d.savePassword = false
        temporary[d.id] = d
        if let password { sessionPasswords[d.id] = password }
    }

    public func removeTemporary(_ id: UUID) {
        temporary[id] = nil
        sessionPasswords[id] = nil
    }

    /// Dodaje lub aktualizuje definicję; hasło (opcjonalne) trafia do Pęku kluczy albo do pamięci sesji.
    public func upsert(_ def: ConnectionDefinition, password: String? = nil) throws {
        if let i = connections.firstIndex(where: { $0.id == def.id }) {
            connections[i] = def
        } else {
            connections.append(def)
        }
        if let password {
            if def.savePassword {
                try secrets.setPassword(password, for: def.id.uuidString)
            } else {
                sessionPasswords[def.id] = password
                try secrets.deletePassword(for: def.id.uuidString)
            }
        } else if !def.savePassword {
            try secrets.deletePassword(for: def.id.uuidString)
        }
        try save()
    }

    public func remove(_ id: UUID) throws {
        connections.removeAll { $0.id == id }
        sessionPasswords[id] = nil
        try secrets.deletePassword(for: id.uuidString)
        try save()
    }

    /// Hasło: z Pęku kluczy (savePassword) albo podane wcześniej w tej sesji. nil = trzeba zapytać.
    public func password(for id: UUID) -> String? {
        if let p = sessionPasswords[id] { return p }
        guard let def = connection(id), def.savePassword else { return nil }
        return try? secrets.password(for: id.uuidString)
    }

    /// Zapamiętuje hasło podane w oknie logowania (do Pęku kluczy, jeśli definicja tak każe).
    public func rememberPassword(_ password: String, for id: UUID) throws {
        guard let def = connection(id) else { return }
        if def.savePassword { try secrets.setPassword(password, for: id.uuidString) } else { sessionPasswords[id] = password }
    }

    public func markUsed(_ id: UUID, at date: Date = Date()) {
        guard temporary[id] == nil, let i = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[i].lastUsed = date
        try? save()
    }

    /// Ostatnio używane (folder Recent), najnowsze pierwsze.
    public func recent(limit: Int = 10) -> [ConnectionDefinition] {
        connections.filter { $0.lastUsed != nil }.sorted { $0.lastUsed! > $1.lastUsed! }.prefix(limit).map { $0 }
    }

    // MARK: Foldery

    public func upsert(folder: ConnectionFolder) throws {
        if let i = folders.firstIndex(where: { $0.id == folder.id }) { folders[i] = folder } else { folders.append(folder) }
        try save()
    }

    /// Usuwa folder; jego połączenia i podfoldery trafiają do folderu nadrzędnego.
    public func remove(folder id: UUID) throws {
        guard let f = folders.first(where: { $0.id == id }) else { return }
        for i in connections.indices where connections[i].folderID == id { connections[i].folderID = f.parentID }
        for i in folders.indices where folders[i].parentID == id { folders[i].parentID = f.parentID }
        folders.removeAll { $0.id == id }
        try save()
    }

    /// Połączenia widoczne w folderze: jawnie przypisane + pasujące do reguły (UG 19.2).
    public func connections(in folderID: UUID?) -> [ConnectionDefinition] {
        let explicit = connections.filter { $0.folderID == folderID }
        // W korzeniu bez połączeń pokazanych już w folderze z regułą (inaczej byłyby dwa razy).
        guard let folderID else { return explicit.filter { c in !folders.contains { $0.matches(c) } } }
        guard let folder = folders.first(where: { $0.id == folderID }), folder.hasRule else { return explicit }
        let matched = connections.filter { $0.folderID != folderID && folder.matches($0) }
        return explicit + matched
    }

    public func subfolders(of parentID: UUID?) -> [ConnectionFolder] { folders.filter { $0.parentID == parentID } }

    // MARK: Eksport / import (bez haseł)

    public func exportDefinitions() throws -> Data {
        try JSONEncoder.pelikan.encode(Snapshot(folders: folders, connections: connections))
    }

    /// Import dopisuje definicje (nowe id przy konflikcie), hasła trzeba podać ponownie.
    public func importDefinitions(_ data: Data) throws -> Int {
        let snap = try JSONDecoder.pelikan.decode(Snapshot.self, from: data)
        var folderMap: [UUID: UUID] = [:]
        for var f in snap.folders {
            let newID = folders.contains(where: { $0.id == f.id }) ? UUID() : f.id
            folderMap[f.id] = newID
            f.id = newID
            folders.append(f)
        }
        for i in folders.indices { if let p = folders[i].parentID, let m = folderMap[p] { folders[i].parentID = m } }
        var count = 0
        for var c in snap.connections {
            if connections.contains(where: { $0.id == c.id }) { c.id = UUID() }
            if let f = c.folderID { c.folderID = folderMap[f] ?? f }
            c.lastUsed = nil
            connections.append(c)
            count += 1
        }
        try save()
        return count
    }
}

extension JSONEncoder {
    static var pelikan: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var pelikan: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
