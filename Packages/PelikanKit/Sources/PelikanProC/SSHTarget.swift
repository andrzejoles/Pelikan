import Foundation
import Observation
import PelikanRemote
import PelikanWorkspace

/// Środowisko celu zdalnego builda (kolor w drzewie, konsoli i tytule; PROD — potwierdzenie nazwą celu).
public enum SSHTargetEnvironment: String, Sendable, Codable, CaseIterable {
    case uat = "UAT", prod = "PROD"
}

/// Sposób logowania SSH. Hasło SSH i hasło klucza — wyłącznie w Pęku kluczy (nigdy w pliku celów).
public enum SSHAuthMethod: String, Sendable, Codable, CaseIterable {
    /// Plik klucza prywatnego (opcjonalnie z hasłem klucza w Pęku kluczy).
    case keyFile
    /// Agent SSH (`SSH_AUTH_SOCK`), bez sekretu w Pelikanie.
    case agent
    /// Hasło SSH (Pęk kluczy).
    case password
}

/// Zmienna środowiska zdalnego (prolog ksh88 `NAZWA='wartość'; export NAZWA;`).
public struct SSHEnvironmentVariable: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var value: String
    public init(name: String, value: String) { self.name = name; self.value = value }
}

/// Folder w drzewie celów.
public struct SSHTargetFolder: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var parentID: UUID?
    public init(name: String, parentID: UUID? = nil) { self.name = name; self.parentID = parentID }
}

/// Cel zdalnego builda Pro*C (zadanie Pro*C, „Menedżer połączeń SSH”; D54). Zapisywany bez sekretów.
public struct PelikanSSHTarget: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var folderID: UUID?
    public var host: String
    public var port: Int = 22
    public var user: String
    public var auth: SSHAuthMethod = .keyFile
    public var keyFile: String = ""
    /// Stare algorytmy (AIX 6.1 i podobne serwery).
    public var legacyAlgorithms = false
    /// Kodowanie nazw i poleceń.
    public var nameEncoding: NameEncoding = .utf8
    /// Kodowanie wyjścia konsoli (build, wdrożenie).
    public var consoleEncoding: NameEncoding = .utf8
    public var kshPath = "/usr/bin/ksh"
    public var oracleHome = ""
    public var libPath = ""
    public var path = ""
    public var extraEnvironment: [SSHEnvironmentVariable] = []
    /// Katalog bazowy (wymagany) — zawiera `src` i `bin`.
    public var baseDirectory: String
    /// Nazwy podkatalogów (ustawienia zaawansowane).
    public var sourceFolderName = "src"
    public var binaryFolderName = "bin"
    /// Katalog backupów (wymagany, może leżeć gdziekolwiek).
    public var backupDirectory: String
    /// Working copy gita na serwerze; pusty — `<baza>/src`.
    public var workingCopyDirectory = ""
    /// Gałąź (porównanie dokładne, z wielkością liter) i nazwa remote.
    public var branch = "MASTER"
    public var remote = "origin"
    /// Komenda builda (makefile ma całą logikę; Pelikan nie wywołuje `proc` ani `xlc`).
    public var buildCommand = "make"
    /// Binarki instalowane do `bin` (D54 p.3); puste — jedna, o nazwie celu.
    public var binaries: [String] = []
    public var environment: SSHTargetEnvironment = .uat

    public init(name: String, host: String, user: String, baseDirectory: String, backupDirectory: String) {
        self.name = name; self.host = host; self.user = user; self.baseDirectory = baseDirectory; self.backupDirectory = backupDirectory
    }

    nonisolated static func join(_ a: String, _ b: String) -> String {
        a.hasSuffix("/") ? a + b : a + "/" + b
    }

    public var sourceDirectory: String { Self.join(baseDirectory, sourceFolderName) }
    public var binaryDirectory: String { Self.join(baseDirectory, binaryFolderName) }
    public var effectiveWorkingCopy: String { workingCopyDirectory.isEmpty ? sourceDirectory : workingCopyDirectory }
    /// Katalog roboczy Pelikana (blokada, skrypty) — zawsze poza working copy.
    public var pelikanDirectory: String { Self.join(backupDirectory, ".pelikan") }
    /// Podpowiedź katalogu backupów.
    public static func suggestedBackupDirectory(base: String) -> String { join(base, "backup") }
    public var effectiveBinaries: [String] { binaries.isEmpty ? [name] : binaries }

    /// Zmienne prologu środowiska (puste pomijane).
    public var remoteEnvironment: [(name: String, value: String)] {
        var out: [(name: String, value: String)] = []
        if !oracleHome.isEmpty { out.append(("ORACLE_HOME", oracleHome)) }
        if !libPath.isEmpty { out.append(("LIBPATH", libPath)) }
        if !path.isEmpty { out.append(("PATH", path)) }
        out += extraEnvironment.filter { !$0.name.isEmpty }.map { ($0.name, $0.value) }
        return out
    }

    /// Błędy walidacji (puste — cel poprawny).
    public var validationErrors: [String] {
        var e: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { e.append(L10n.tr("Podaj nazwę celu")) }
        if host.trimmingCharacters(in: .whitespaces).isEmpty { e.append(L10n.tr("Podaj host")) }
        if !baseDirectory.hasPrefix("/") { e.append(L10n.tr("Katalog bazowy musi być ścieżką bezwzględną")) }
        if !backupDirectory.hasPrefix("/") { e.append(L10n.tr("Katalog backupów musi być ścieżką bezwzględną")) }
        let wc = effectiveWorkingCopy
        if pelikanDirectory == wc || pelikanDirectory.hasPrefix(Self.join(wc, "")) {
            e.append(L10n.tr("Katalog backupów nie może leżeć w working copy (pliki Pelikana pojawiłyby się w git status)"))
        }
        if auth == .keyFile, keyFile.isEmpty { e.append(L10n.tr("Wskaż plik klucza")) }
        if !(1...65535).contains(port) { e.append(L10n.tr("Port spoza zakresu 1–65535")) }
        return e + gitNameErrors
    }

    /// Nazwa remote albo gałęzi przekazywana do gita: litery, cyfry, `._/-`, bez wiodącego `-` — cel z cudzego pliku
    /// z `remote = "--upload-pack=…"` zamieniałby argument w opcję gita (R8-09).
    public static func isSafeGitName(_ s: String) -> Bool {
        !s.isEmpty && !s.hasPrefix("-") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._/-".contains($0)) }
    }

    /// Błędy nazw remote i gałęzi (walidacja celu i import).
    public var gitNameErrors: [String] {
        var e: [String] = []
        if !Self.isSafeGitName(remote) { e.append(L10n.tr("Nieprawidłowa nazwa remote gita (dozwolone litery, cyfry, . _ / -)")) }
        if !Self.isSafeGitName(branch) { e.append(L10n.tr("Nieprawidłowa nazwa gałęzi gita (dozwolone litery, cyfry, . _ / -)")) }
        return e
    }

    /// Kopia z nową tożsamością (Duplikuj).
    public func duplicated() -> PelikanSSHTarget {
        var c = self
        c.id = UUID()
        c.name = L10n.tr("\(name) (kopia)")
        return c
    }
}

/// Potwierdzenie operacji na celu PROD (zadanie Pro*C): użytkownik wpisuje nazwę celu. Pipeline wdrożenia pyta
/// przez `ask` (aplikacja: okno z polem tekstowym) przed każdą operacją zmieniającą serwer.
public enum ProductionConfirmation {
    public static func isRequired(for target: PelikanSSHTarget) -> Bool { target.environment == .prod }

    /// Wpisana nazwa zgadza się dokładnie (z wielkością liter; spacje na brzegach pomijane).
    public static func accepts(_ typed: String, for target: PelikanSSHTarget) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines) == target.name
    }

    /// Prośba o potwierdzenie (`ask` zwraca wpisany tekst albo nil — anulowano). Dla UAT bez pytania.
    @MainActor
    public static func confirm(_ target: PelikanSSHTarget, operation: String,
                               ask: @MainActor (_ message: String) async -> String?) async -> Bool {
        guard isRequired(for: target) else { return true }
        let message = L10n.tr("Cel „\(target.name)” to PRODUKCJA. Operacja: \(operation). Aby kontynuować, wpisz nazwę celu.")
        guard let typed = await ask(message) else { return false }
        return accepts(typed, for: target)
    }
}

/// Plik celów (`ssh-targets.json`) — bez sekretów.
public struct SSHTargetsFile: Sendable, Codable, Hashable {
    public var format = "pelikan-ssh-targets"
    public var version = 1
    public var folders: [SSHTargetFolder] = []
    public var targets: [PelikanSSHTarget] = []
    public init() {}
}

/// Cele SSH: zapis w katalogu danych bez sekretów, sekrety (hasło SSH albo hasło klucza) w `SecretStore`
/// (aplikacja: Pęk kluczy, usługa `<bundle id>.ssh`, konto = id celu).
@MainActor
@Observable
public final class SSHTargetStore {
    public private(set) var folders: [SSHTargetFolder] = []
    public private(set) var targets: [PelikanSSHTarget] = []
    @ObservationIgnored public let fileURL: URL?
    @ObservationIgnored let secrets: any SecretStore
    /// Sekrety podane bez zapamiętania — tylko w pamięci do zamknięcia aplikacji.
    @ObservationIgnored private var sessionSecrets: [UUID: String] = [:]

    /// Nazwa pliku celów w katalogu danych.
    public static let fileName = "ssh-targets.json"

    /// Usługa Pęku kluczy dla sekretów SSH — osobna od haseł baz (`<bundle id>.connection`); nazwa marki tylko
    /// w identyfikatorze pakietu (Config/Brand.xcconfig).
    public nonisolated static func keychainService(bundleIdentifier: String) -> String { bundleIdentifier + ".ssh" }

    public init(fileURL: URL?, secrets: any SecretStore) {
        self.fileURL = fileURL
        self.secrets = secrets
        if let url = fileURL, let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(SSHTargetsFile.self, from: data),
           f.format == "pelikan-ssh-targets" {
            folders = f.folders
            targets = f.targets
        }
    }

    var file: SSHTargetsFile {
        var f = SSHTargetsFile()
        f.folders = folders
        f.targets = targets
        return f
    }

    public func save() throws {
        guard let url = fileURL else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(file).write(to: url, options: .atomic)
    }

    public func target(_ id: UUID) -> PelikanSSHTarget? { targets.first { $0.id == id } }

    /// Dodanie albo zmiana celu; `secret` — hasło SSH / hasło klucza (nil — bez zmiany), `remember` — do Pęku kluczy.
    public func upsert(_ t: PelikanSSHTarget, secret: String? = nil, remember: Bool = true) throws {
        if let i = targets.firstIndex(where: { $0.id == t.id }) { targets[i] = t } else { targets.append(t) }
        if let secret {
            if remember {
                try secrets.setPassword(secret, for: t.id.uuidString)
                sessionSecrets[t.id] = nil
            } else {
                try? secrets.deletePassword(for: t.id.uuidString)
                sessionSecrets[t.id] = secret
            }
        }
        try save()
    }

    public func remove(_ id: UUID) throws {
        targets.removeAll { $0.id == id }
        sessionSecrets[id] = nil
        try? secrets.deletePassword(for: id.uuidString)
        try save()
    }

    @discardableResult
    public func duplicate(_ id: UUID) throws -> PelikanSSHTarget? {
        guard let t = target(id) else { return nil }
        let c = t.duplicated()
        try upsert(c)
        return c
    }

    public func upsert(folder: SSHTargetFolder) throws {
        if let i = folders.firstIndex(where: { $0.id == folder.id }) { folders[i] = folder } else { folders.append(folder) }
        try save()
    }

    /// Usunięcie folderu: cele i podfoldery przechodzą do folderu nadrzędnego.
    public func remove(folder id: UUID) throws {
        let parent = folders.first { $0.id == id }?.parentID
        for i in targets.indices where targets[i].folderID == id { targets[i].folderID = parent }
        for i in folders.indices where folders[i].parentID == id { folders[i].parentID = parent }
        folders.removeAll { $0.id == id }
        try save()
    }

    /// Czy jest sekret do użycia (w pamięci albo zapisany) — bez odczytu jego treści.
    public func hasSecret(for id: UUID) -> Bool {
        sessionSecrets[id] != nil || ((try? secrets.hasPassword(for: id.uuidString)) ?? false)
    }

    /// Sekret celu do logowania: z pamięci albo z Pęku kluczy — przy włączonej ochronie (D56) po potwierdzeniu
    /// właściciela (Touch ID / hasło Maca), raz na cel w trakcie działania aplikacji.
    public func secret(for id: UUID, in ws: Workspace) async throws -> String? {
        if let s = sessionSecrets[id] { return s }
        guard (try? secrets.hasPassword(for: id.uuidString)) == true else { return nil }
        if ws.settings.requireOwnerForSavedPasswords {
            let name = target(id)?.name ?? ""
            guard await ws.sessions.prompter?.authenticateOwner(reason: L10n.tr("użyć zapisanego sekretu połączenia SSH „\(name)”")) == true else {
                throw CommandError.cancelledByUser
            }
        }
        let s = try secrets.password(for: id.uuidString)
        if let s { sessionSecrets[id] = s }
        return s
    }

    /// Eksport listy (bez sekretów — te nie należą do modelu).
    public func exportData() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(file)
    }

    /// Import: cele i foldery o nowych identyfikatorach dołączane do istniejących (sekrety trzeba podać ponownie).
    @discardableResult
    public func importData(_ data: Data) throws -> Int {
        let f = try JSONDecoder().decode(SSHTargetsFile.self, from: data)
        guard f.format == "pelikan-ssh-targets" else { throw CommandError.notAvailable(L10n.tr("To nie jest plik celów SSH Pelikana")) }
        if let bad = f.targets.first(where: { !$0.gitNameErrors.isEmpty }) {
            throw CommandError.notAvailable("\(bad.name): " + bad.gitNameErrors.joined(separator: "\n"))
        }
        var folderMap: [UUID: UUID] = [:]
        var added: [SSHTargetFolder] = []
        for var folder in f.folders {
            let old = folder.id
            folder.id = UUID()
            folderMap[old] = folder.id
            added.append(folder)
        }
        for i in added.indices { added[i].parentID = added[i].parentID.flatMap { folderMap[$0] } }
        folders += added
        for var t in f.targets {
            t.id = UUID()
            t.folderID = t.folderID.flatMap { folderMap[$0] }
            targets.append(t)
        }
        try save()
        return f.targets.count
    }
}
