import Foundation
import Observation

/// Lokalizacja File Browsera (UG 22): katalog z nazwą, filtrem plików, kolorem i miejscem w hierarchii lokalizacji.
public struct FileLocation: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String
    /// Maski plików rozdzielone `;`, np. `*.sql;*.pck` (puste — wszystkie).
    public var filter: String
    public var color: RGBColor?
    /// Lokalizacja nadrzędna (grupowanie na liście lokalizacji).
    public var parentID: UUID?

    public init(id: UUID = UUID(), name: String, path: String, filter: String = "", color: RGBColor? = nil, parentID: UUID? = nil) {
        self.id = id; self.name = name; self.path = path; self.filter = filter; self.color = color; self.parentID = parentID
    }

    public var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true) }
}

/// Filtr listy plików (UG 22.3): nazwa (maski), stan (otwarty / zmieniony w Pelikanie), stan Git, rozmiar, data zmiany.
public struct FileFilter: Sendable, Codable, Hashable {
    public enum Status: String, Sendable, Codable, CaseIterable { case any, open, modified }
    public var name = ""
    public var status: Status = .any
    /// Stany Git do pokazania (puste — dowolny).
    public var vcs: Set<GitFileState> = []
    public var minSize: Int64?
    public var maxSize: Int64?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?

    public init() {}

    public var isEmpty: Bool { self == FileFilter() }
}

/// Element listy plików.
public struct FileEntry: Sendable, Hashable, Identifiable {
    public var url: URL
    public var isDirectory: Bool
    public var size: Int64
    public var modified: Date?
    public var git: GitFileState?
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
}

/// Maski plików w stylu `*.sql;*.p?k` (bez rozróżniania wielkości liter).
public enum FileMask {
    public static func matches(_ name: String, masks: String) -> Bool {
        let list = masks.split(whereSeparator: { $0 == ";" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !list.isEmpty else { return true }
        // Maska bez znaków wieloznacznych — fragment nazwy (pole filtra „Nazwa”).
        return list.contains { m in
            let p = m.lowercased()
            return p.contains("*") || p.contains("?") ? glob(name.lowercased(), p) : name.lowercased().contains(p)
        }
    }

    static func glob(_ s: String, _ p: String) -> Bool {
        let s = Array(s), p = Array(p)
        var si = 0, pi = 0, star = -1, mark = 0
        while si < s.count {
            if pi < p.count, p[pi] == "?" || p[pi] == s[si] { si += 1; pi += 1 }
            else if pi < p.count, p[pi] == "*" { star = pi; mark = si; pi += 1 }
            else if star >= 0 { pi = star + 1; mark += 1; si = mark }
            else { return false }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

/// Stan File Browsera zapisywany w katalogu danych (`file-browser.json`): lokalizacje i historia filtrów.
public struct FileBrowserState: Sendable, Codable, Hashable {
    public var locations: [FileLocation] = []
    public var filterHistory: [String] = []
    public var showHidden = false
    public init() {}
}

/// Model File Browsera (PD-FB-001, PD-FB-002).
@MainActor
@Observable
public final class FileBrowser {
    public private(set) var state = FileBrowserState()
    @ObservationIgnored let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(FileBrowserState.self, from: data) {
            state = s
        }
    }

    public var locations: [FileLocation] { state.locations }

    func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public func upsert(_ location: FileLocation) {
        if let i = state.locations.firstIndex(where: { $0.id == location.id }) { state.locations[i] = location } else { state.locations.append(location) }
        save()
    }

    /// Usuwa lokalizację; podrzędne przechodzą do jej rodzica.
    public func remove(_ id: UUID) {
        let parent = state.locations.first { $0.id == id }?.parentID
        state.locations.removeAll { $0.id == id }
        for i in state.locations.indices where state.locations[i].parentID == id { state.locations[i].parentID = parent }
        save()
    }

    public func children(of parent: UUID?) -> [FileLocation] {
        state.locations.filter { $0.parentID == parent }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var showHidden: Bool {
        get { state.showHidden }
        set { state.showHidden = newValue; save() }
    }

    /// Zapamiętuje maskę nazw w historii filtra (najnowsza pierwsza, do 20).
    public func remember(filter name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        state.filterHistory.removeAll { $0 == n }
        state.filterHistory.insert(n, at: 0)
        if state.filterHistory.count > 20 { state.filterHistory.removeLast(state.filterHistory.count - 20) }
        save()
    }

    public var filterHistory: [String] { state.filterHistory }

    public func clearFilterHistory() {
        state.filterHistory = []
        save()
    }

    /// Zawartość katalogu: katalogi pierwsze, potem pliki; maska lokalizacji i filtr dotyczą plików.
    public nonisolated static func entries(in directory: URL, locationMask: String = "", filter: FileFilter = FileFilter(), showHidden: Bool = false,
                                           git: GitStatus? = nil, openFiles: Set<String> = [], modifiedFiles: Set<String> = []) -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: options) else { return [] }
        var out: [FileEntry] = []
        for u in urls {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let dir = v?.isDirectory ?? false
            let std = u.standardizedFileURL
            let e = FileEntry(url: std, isDirectory: dir, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate,
                              git: dir ? nil : git?.state(of: std))
            if !dir {
                guard FileMask.matches(e.name, masks: locationMask), FileMask.matches(e.name, masks: filter.name) else { continue }
                switch filter.status {
                case .any: break
                case .open: guard openFiles.contains(std.path) else { continue }
                case .modified: guard modifiedFiles.contains(std.path) else { continue }
                }
                if !filter.vcs.isEmpty { guard filter.vcs.contains(e.git ?? .unmodified) else { continue } }
                if let m = filter.minSize, e.size < m { continue }
                if let m = filter.maxSize, e.size > m { continue }
                if let d = filter.modifiedAfter, (e.modified ?? .distantPast) < d { continue }
                if let d = filter.modifiedBefore, (e.modified ?? .distantFuture) > d { continue }
            }
            out.append(e)
        }
        return out.sorted { a, b in
            a.isDirectory != b.isDirectory ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: Operacje na plikach

    /// Nazwa pliku albo katalogu bez separatorów ścieżki i bez `.`/`..` (zmiana nazwy, nowy element).
    nonisolated static func validName(_ name: String) throws -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !n.contains("/"), n != ".", n != ".." else {
            throw CommandError.invalidArgument("name", L10n.tr("nieprawidłowa nazwa pliku"))
        }
        return n
    }

    @discardableResult
    public nonisolated static func rename(_ url: URL, to name: String) throws -> URL {
        let target = url.deletingLastPathComponent().appendingPathComponent(try validName(name))
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    @discardableResult
    public nonisolated static func createFolder(in directory: URL, name: String) throws -> URL {
        let target = directory.appendingPathComponent(try validName(name), isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        return target
    }

    @discardableResult
    public nonisolated static func createFile(in directory: URL, name: String) throws -> URL {
        let target = directory.appendingPathComponent(try validName(name))
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw CommandError.notAvailable(L10n.tr("Plik już istnieje: \(target.lastPathComponent)"))
        }
        try Data().write(to: target)
        return target
    }

    /// Przenosi do Kosza (macOS); bez Kosza (Linux) — błąd zamiast trwałego usunięcia.
    public nonisolated static func trash(_ url: URL) throws {
        #if os(macOS)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        throw CommandError.notAvailable(L10n.tr("Kosz jest niedostępny w tym systemie"))
        #endif
    }
}
