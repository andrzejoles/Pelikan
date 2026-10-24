import Foundation
import PelikanSQL

/// Szablon kodu (UG 31): folder, nazwa, tekst ze zmiennymi.
public struct CodeTemplate: Sendable, Hashable, Identifiable {
    public var folder: String
    public var name: String
    public var text: String
    public var isBuiltIn: Bool
    public var id: String { folder + "/" + name }

    public init(folder: String, name: String, text: String, isBuiltIn: Bool = false) {
        self.folder = folder; self.name = name; self.text = text; self.isBuiltIn = isBuiltIn
    }
}

/// Zmienna szablonu: `[Nazwa]`, `[Nazwa=domyślna]`, `[Nazwa=*a,b,c]` (wybór z listy).
public struct TemplateVariable: Sendable, Hashable {
    public var name: String
    public var defaultValue: String
    public var choices: [String]
}

/// Składnia szablonów: zmienne w nawiasach kwadratowych (każda nazwa pytana raz), `[#]` — pozycja kursora po
/// wstawieniu, `[[` — dosłowny `[`, zmienne wbudowane `$OSUSER $DBUSER $DATE $TIME`.
public enum TemplateEngine {
    struct Part { var literal: String?; var variable: TemplateVariable?; var cursor = false }

    static func parse(_ text: String) -> [Part] {
        var parts: [Part] = []
        var buf = ""
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "[" {
                let next = text.index(after: i)
                if next < text.endIndex, text[next] == "[" { buf.append("["); i = text.index(after: next); continue }
                if let close = text[next...].firstIndex(of: "]"), !text[next..<close].contains("\n") {
                    let body = String(text[next..<close])
                    if !buf.isEmpty { parts.append(Part(literal: buf)); buf = "" }
                    if body == "#" {
                        parts.append(Part(cursor: true))
                    } else {
                        let pieces = body.split(separator: "=", maxSplits: 1).map(String.init)
                        let name = pieces[0].trimmingCharacters(in: .whitespaces)
                        var def = pieces.count > 1 ? pieces[1] : ""
                        var choices: [String] = []
                        if def.hasPrefix("*") {
                            choices = def.dropFirst().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            def = choices.first ?? ""
                        }
                        parts.append(Part(variable: TemplateVariable(name: name, defaultValue: def, choices: choices)))
                    }
                    i = text.index(after: close)
                    continue
                }
            }
            buf.append(c)
            i = text.index(after: i)
        }
        if !buf.isEmpty { parts.append(Part(literal: buf)) }
        return parts
    }

    /// Zmienne do formularza (kolejność pierwszego wystąpienia, bez powtórzeń).
    public static func variables(_ text: String) -> [TemplateVariable] {
        var seen = Set<String>()
        return parse(text).compactMap(\.variable).filter { seen.insert($0.name.uppercased()).inserted }
    }

    /// Tekst z podstawionymi wartościami (brak wartości — domyślna) i pozycja kursora (UTF-16) albo nil.
    public static func apply(_ text: String, values: [String: String], builtins: [String: String] = [:]) -> (text: String, cursor: Int?) {
        var out = ""
        var cursor: Int?
        let upperValues = Dictionary(values.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        for p in parse(text) {
            if p.cursor { cursor = (out as NSString).length; continue }
            if let v = p.variable { out += upperValues[v.name.uppercased()] ?? v.defaultValue; continue }
            out += p.literal ?? ""
        }
        // Zmienne wbudowane — dłuższe nazwy najpierw.
        for (k, v) in builtins.sorted(by: { $0.key.count > $1.key.count }) {
            let before = cursor.map { (out as NSString).substring(to: $0) }
            out = out.replacingOccurrences(of: "$" + k, with: v)
            if let before { cursor = (before.replacingOccurrences(of: "$" + k, with: v) as NSString).length }
        }
        return (out, cursor)
    }

    /// Zmienne wbudowane dla połączenia (użytkownik bazy) i bieżącego czasu.
    public static func builtins(databaseUser: String?, now: Date = Date()) -> [String: String] {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = "yyyy-MM-dd"
        let t = DateFormatter()
        t.locale = Locale(identifier: "en_US_POSIX")
        t.dateFormat = "HH:mm:ss"
        return ["OSUSER": NSUserName(), "DBUSER": databaseUser ?? "", "DATE": d.string(from: now), "TIME": t.string(from: now)]
    }
}

/// Biblioteka szablonów: wbudowane (własne teksty Pelikana) i użytkownika (`Templates/<folder>/<nazwa>.tpl`
/// w katalogu danych); szablon użytkownika o tej samej ścieżce zastępuje wbudowany.
@MainActor
public final class TemplateLibrary {
    public static let fileExtension = "tpl"
    let directory: URL?

    init(directory: URL?) { self.directory = directory }

    public var all: [CodeTemplate] {
        var byID = Dictionary(uniqueKeysWithValues: Self.builtIn.map { ($0.id, $0) })
        for t in userTemplates() { byID[t.id] = t }
        return byID.values.sorted { ($0.folder, $0.name) < ($1.folder, $1.name) }
    }

    public func template(_ id: String) -> CodeTemplate? {
        all.first { $0.id.caseInsensitiveCompare(id) == .orderedSame } ?? all.first { $0.name.caseInsensitiveCompare(id) == .orderedSame }
    }

    func userTemplates() -> [CodeTemplate] {
        guard let dir = directory, let folders = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [CodeTemplate] = []
        for f in folders where (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let files = (try? FileManager.default.contentsOfDirectory(at: f, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == Self.fileExtension {
                if let text = try? String(contentsOf: file, encoding: .utf8) {
                    out.append(CodeTemplate(folder: f.lastPathComponent, name: file.deletingPathExtension().lastPathComponent, text: text))
                }
            }
        }
        return out
    }

    /// Zapis szablonu użytkownika (UG 31.3); nazwy folderu i szablonu bez znaków ścieżki.
    public func save(_ t: CodeTemplate) throws {
        guard let dir = directory else { throw CommandError.notAvailable(L10n.tr("Brak katalogu danych")) }
        let folder = Self.safe(t.folder), name = Self.safe(t.name)
        guard !folder.isEmpty, !name.isEmpty else { throw CommandError.invalidArgument("name", L10n.tr("pusta nazwa")) }
        let f = dir.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        try t.text.write(to: f.appendingPathComponent(name).appendingPathExtension(Self.fileExtension), atomically: true, encoding: .utf8)
    }

    public func delete(_ t: CodeTemplate) throws {
        guard let dir = directory else { return }
        let url = dir.appendingPathComponent(Self.safe(t.folder)).appendingPathComponent(Self.safe(t.name)).appendingPathExtension(Self.fileExtension)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// Edycja szablonu (PD-TPL-003): zapis pod nowym folderem/nazwą i usunięcie starego pliku użytkownika. Szablon
    /// wbudowany zostaje — edycja tworzy szablon użytkownika (o tej samej ścieżce zastępuje wbudowany).
    public func update(_ old: CodeTemplate, to new: CodeTemplate) throws {
        try save(new)
        if !old.isBuiltIn, Self.safe(old.folder) != Self.safe(new.folder) || Self.safe(old.name) != Self.safe(new.name) {
            try delete(old)
        }
    }

    /// Foldery szablonów: wbudowane i użytkownika (także puste).
    public var folders: [String] {
        var set = Set(Self.builtIn.map(\.folder))
        if let dir = directory, let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for f in items where (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { set.insert(f.lastPathComponent) }
        }
        return set.sorted()
    }

    /// Nowy (pusty) folder użytkownika.
    public func createFolder(_ name: String) throws {
        guard let dir = directory else { throw CommandError.notAvailable(L10n.tr("Brak katalogu danych")) }
        let n = Self.safe(name)
        guard !n.isEmpty else { throw CommandError.invalidArgument("folder", L10n.tr("pusta nazwa")) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(n, isDirectory: true), withIntermediateDirectories: true)
    }

    /// Zmiana nazwy folderu użytkownika (szablony przechodzą razem z nim); folder docelowy nie może istnieć.
    public func renameFolder(_ old: String, to new: String) throws {
        guard let dir = directory else { throw CommandError.notAvailable(L10n.tr("Brak katalogu danych")) }
        let from = dir.appendingPathComponent(Self.safe(old), isDirectory: true), to = dir.appendingPathComponent(Self.safe(new), isDirectory: true)
        guard !Self.safe(new).isEmpty else { throw CommandError.invalidArgument("name", L10n.tr("pusta nazwa")) }
        guard FileManager.default.fileExists(atPath: from.path) else {
            throw CommandError.invalidArgument("folder", L10n.tr("Folder „\(old)” nie ma szablonów użytkownika"))
        }
        guard !FileManager.default.fileExists(atPath: to.path) else {
            throw CommandError.invalidArgument("name", L10n.tr("Folder „\(new)” już istnieje"))
        }
        try FileManager.default.moveItem(at: from, to: to)
    }

    /// Usuwa folder użytkownika z jego szablonami (szablony wbudowane w folderze o tej nazwie zostają).
    public func deleteFolder(_ name: String) throws {
        guard let dir = directory else { return }
        let url = dir.appendingPathComponent(Self.safe(name), isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    nonisolated static func safe(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "/\\:\0")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
