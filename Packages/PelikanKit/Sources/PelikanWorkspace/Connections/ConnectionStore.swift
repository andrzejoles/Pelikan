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
    /// Komunikat o nieczytelnym pliku przy odczycie (plik przeniesiony do kopii `.bad-…`, R6-11) — aplikacja go pokazuje.
    @ObservationIgnored public private(set) var loadProblem: String?
    /// Kopia nieczytelnego pliku się nie udała — zapis zablokowany, żeby nie nadpisać oryginału.
    @ObservationIgnored private var saveBlocked = false

    private struct Snapshot: Codable {
        var version = 1
        var folders: [ConnectionFolder]
        var connections: [ConnectionDefinition]
        /// Hasła w pliku eksportu (D186) — tylko eksport z hasłami; plik `connections.json` nigdy ich nie ma.
        var secrets: ConnectionTransfer.Envelope?
    }

    /// - Parameter fileURL: nil = bez zapisu (testy, `Workspace(persists: false)`).
    public init(fileURL: URL?, secrets: any SecretStore) {
        self.fileURL = fileURL
        self.secrets = secrets
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            if let snap = try? JSONDecoder.pelikan.decode(Snapshot.self, from: data) {
                folders = snap.folders
                connections = snap.connections
            } else {
                // Uszkodzony albo nowszy plik: zachowany obok, zanim pierwszy zapis nadpisze go pustą listą.
                let (message, preserved) = DamagedFile.preserve(fileURL)
                loadProblem = message
                saveBlocked = !preserved
            }
        }
    }

    public func save() throws {
        guard let fileURL else { return }
        guard !saveBlocked else { throw CommandError.notAvailable(loadProblem ?? "") }
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
        try def.sshTunnel?.validate()
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
        try? secrets.deletePassword(for: Self.sshAccount(id))
        try save()
    }

    /// Konto hasła SSH tunelu w Pęku kluczy (DB-SSH-001): osobne od hasła bazy.
    nonisolated static func sshAccount(_ id: UUID) -> String { id.uuidString + ".ssh" }

    /// Hasło SSH tunelu (tylko Pęk kluczy; nil — brak).
    public func sshPassword(for id: UUID) -> String? { try? secrets.password(for: Self.sshAccount(id)) }

    /// Zapisuje (albo usuwa — pusty tekst) hasło SSH tunelu w Pęku kluczy.
    public func setSSHPassword(_ password: String, for id: UUID) throws {
        if password.isEmpty { try secrets.deletePassword(for: Self.sshAccount(id)) } else { try secrets.setPassword(password, for: Self.sshAccount(id)) }
    }

    /// Czy jest hasło do użycia (w pamięci sesji albo zapisane w Pęku kluczy) — bez odczytu zapisanego sekretu.
    public func hasStoredPassword(for id: UUID) -> Bool {
        if sessionPasswords[id] != nil { return true }
        guard let def = connection(id), def.savePassword else { return false }
        return (try? secrets.hasPassword(for: id.uuidString)) ?? false
    }

    /// Hasło tylko z pamięci sesji (bez Pęku kluczy).
    public func sessionPassword(for id: UUID) -> String? { sessionPasswords[id] }

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

    /// Połączenia widoczne w folderze: jawnie przypisane + pasujące do reguły (UG 19.2), alfabetycznie.
    public func connections(in folderID: UUID?) -> [ConnectionDefinition] {
        let explicit = connections.filter { $0.folderID == folderID }
        let visible: [ConnectionDefinition]
        if let folderID {
            if let folder = folders.first(where: { $0.id == folderID }), folder.hasRule {
                visible = explicit + connections.filter { $0.folderID != folderID && folder.matches($0) }
            } else {
                visible = explicit
            }
        } else {
            // W korzeniu bez połączeń pokazanych już w folderze z regułą (inaczej byłyby dwa razy).
            visible = explicit.filter { c in !folders.contains { $0.matches(c) } }
        }
        return visible.sorted(by: Self.alphabetical)
    }

    /// Podfoldery alfabetycznie (jak w Finderze: bez wielkości liter, liczby w nazwach naturalnie).
    public func subfolders(of parentID: UUID?) -> [ConnectionFolder] {
        folders.filter { $0.parentID == parentID }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Kolejność połączeń na liście, w Object Browserze i w menu: alfabetycznie po nazwie wyświetlanej.
    nonisolated public static func alphabetical(_ a: ConnectionDefinition, _ b: ConnectionDefinition) -> Bool {
        switch a.displayName.localizedStandardCompare(b.displayName) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: a.id.uuidString < b.id.uuidString
        }
    }

    /// Przenosi połączenie do folderu (nil — poziom główny listy).
    public func move(_ id: UUID, to folderID: UUID?) throws {
        guard let i = connections.firstIndex(where: { $0.id == id }) else { throw Self.notOnList(id, temporary: temporary[id] != nil) }
        if let folderID, !folders.contains(where: { $0.id == folderID }) {
            throw CommandError.invalidArgument("folder", L10n.tr("nieznany folder"))
        }
        guard connections[i].folderID != folderID else { return }
        connections[i].folderID = folderID
        try save()
    }

    /// Kopia definicji pod inną nazwą (nowy identyfikator, unikalna nazwa) razem z zapisanymi hasłami bazy i tunelu SSH;
    /// bez historii użycia i bez łączenia przy starcie (dwa połączenia z tą samą bazą). Hasło podane tylko w tej sesji też
    /// przechodzi — tylko do pamięci, jak w oryginale. Każdy błąd wycofuje kopię razem z jej hasłami.
    @discardableResult
    public func duplicate(_ id: UUID, name: String) throws -> ConnectionDefinition {
        guard var copy = connections.first(where: { $0.id == id }) else { throw Self.notOnList(id, temporary: temporary[id] != nil) }
        guard !connections.contains(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw CommandError.invalidArgument("name", L10n.tr("połączenie o nazwie „\(name)” już istnieje"))
        }
        copy.id = UUID()
        copy.name = name
        copy.lastUsed = nil
        copy.connectOnStartup = false
        do {
            if copy.savePassword, let p = try? secrets.password(for: id.uuidString) {
                try secrets.setPassword(p, for: copy.id.uuidString)
            }
            if let p = sessionPasswords[id] { sessionPasswords[copy.id] = p }
            if let p = sshPassword(for: id) { try secrets.setPassword(p, for: Self.sshAccount(copy.id)) }
            connections.append(copy)
            try save()
        } catch {
            // Bez osieroconych haseł w Pęku kluczy, gdy kopii nie udało się zapisać w całości.
            connections.removeAll { $0.id == copy.id }
            sessionPasswords[copy.id] = nil
            try? secrets.deletePassword(for: copy.id.uuidString)
            try? secrets.deletePassword(for: Self.sshAccount(copy.id))
            throw error
        }
        return copy
    }

    private static func notOnList(_ id: UUID, temporary: Bool) -> CommandError {
        temporary ? .notAvailable(L10n.tr("Połączenia tymczasowego (CONNECT w oknie poleceń) nie można skopiować ani przenieść"))
            : .invalidArgument("connection", L10n.tr("nieznane połączenie"))
    }

    // MARK: Eksport / import (hasła tylko w pliku eksportu z hasłami, D186)

    public func exportDefinitions(secrets: ConnectionTransfer.Envelope? = nil) throws -> Data {
        try JSONEncoder.pelikan.encode(Snapshot(folders: folders, connections: connections, secrets: secrets))
    }

    /// Plik eksportu z sekcją haseł dla definicji wyeksportowanych wcześniej (`exportDefinitions()`) — te same definicje,
    /// które uwierzytelnia szyfrowanie, choć lista mogła się w międzyczasie zmienić.
    static func addingSecrets(_ secrets: ConnectionTransfer.Envelope, to definitions: Data) throws -> Data {
        var snap = try JSONDecoder.pelikan.decode(Snapshot.self, from: definitions)
        snap.secrets = secrets
        return try JSONEncoder.pelikan.encode(snap)
    }

    /// Definicje z pliku importu, które coś uruchamiają przy połączeniu (tunel SSH — proces `ssh`, skrypt
    /// inicjalizacji — polecenia w bazie): nazwy do ostrzeżenia przed importem z niezaufanego źródła.
    public static func definitionsRunningCode(in data: Data) throws -> [String] {
        try JSONDecoder.pelikan.decode(Snapshot.self, from: data).connections
            .filter { $0.sshTunnel != nil || !$0.initScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.displayName)
    }

    /// Import dopisuje definicje (nowe id przy konflikcie); bez haseł z pliku trzeba je podać przy pierwszym połączeniu.
    /// Tunel z hostem albo użytkownikiem wyglądającym jak opcja `ssh` odrzuca cały plik.
    /// - Parameter secrets: hasła z pliku (identyfikatory z pliku) — zapisywane w Pęku kluczy; definicja z hasłem bazy
    ///   dostaje „zapisz hasło” (D186). Błąd zapisu hasła albo pliku wycofuje cały import (zapisane hasła i dopisane
    ///   definicje) — ponowny import nie tworzy duplikatów.
    public func importDefinitions(_ data: Data, secrets: [String: ConnectionSecrets] = [:]) throws -> Int {
        let snap = try JSONDecoder.pelikan.decode(Snapshot.self, from: data)
        for c in snap.connections { try c.sshTunnel?.validate() }
        let before = (folders, connections)
        var folderMap: [UUID: UUID] = [:]
        let firstImported = folders.count
        for var f in snap.folders {
            let newID = folders.contains(where: { $0.id == f.id }) ? UUID() : f.id
            folderMap[f.id] = newID
            f.id = newID
            folders.append(f)
        }
        // Tylko foldery z importu: istniejący folder o id kolidującym z importowanym zachowuje swoje podfoldery.
        for i in firstImported..<folders.count { if let p = folders[i].parentID, let m = folderMap[p] { folders[i].parentID = m } }
        var count = 0
        var stored: [(UUID, ConnectionSecrets)] = []
        for var c in snap.connections {
            let fileID = c.id
            if connections.contains(where: { $0.id == c.id }) { c.id = UUID() }
            if let f = c.folderID { c.folderID = folderMap[f] ?? f }
            c.lastUsed = nil
            if let s = secrets[fileID.uuidString] {
                if s.password != nil { c.savePassword = true }
                stored.append((c.id, s))
            }
            connections.append(c)
            count += 1
        }
        var written: [String] = []
        do {
            for (id, s) in stored {
                if let p = s.password {
                    written.append(id.uuidString)
                    try self.secrets.setPassword(p, for: id.uuidString)
                }
                if let p = s.sshPassword {
                    written.append(Self.sshAccount(id))
                    try setSSHPassword(p, for: id)
                }
            }
            try save()
        } catch {
            for account in written { try? self.secrets.deletePassword(for: account) }
            (folders, connections) = before
            throw error
        }
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
