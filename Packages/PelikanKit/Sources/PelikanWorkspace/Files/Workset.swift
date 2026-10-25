import Foundation
import Observation
import PelikanSQL

/// Okno zapisane w worksecie (UG 15): plik albo tekst (zmiany niezapisane przetrwają zamknięcie aplikacji).
public struct WorksetDocument: Sendable, Codable, Hashable {
    public var kind: DocumentKind
    public var title: String?
    public var filePath: String?
    /// Tekst okna — gdy okno nie ma pliku albo ma niezapisane zmiany (inaczej plik czytany ponownie).
    public var text: String?
    public var modified: Bool
    public var selectionStart: Int
    public var selectionEnd: Int
    public var connectionID: UUID?
    public var testVariables: [TestVariable]?
    /// Wartości zmiennych `&`/`:` zapamiętane w oknie (PD-VAR-008, jak `.pfi` wzorca).
    public var variables: [String: WorksetVariable]?
}

/// Wartość zmiennej okna w worksecie: tekst albo lista; brak obu — NULL.
public struct WorksetVariable: Sendable, Codable, Hashable {
    public var text: String?
    public var list: [String]?

    public init(_ v: VariableValue) {
        switch v {
        case .null: break
        case .text(let t): text = t
        case .list(let l): list = l
        }
    }

    public var value: VariableValue { list.map { .list($0) } ?? text.map { .text($0) } ?? .null }
}

/// Workset: zestaw okien z kolejnością i oknem aktywnym.
public struct Workset: Sendable, Codable, Hashable {
    public var name: String
    public var documents: [WorksetDocument] = []
    public var activeIndex: Int?
    public var saved = Date()

    public init(name: String, documents: [WorksetDocument] = [], activeIndex: Int? = nil) {
        self.name = name; self.documents = documents; self.activeIndex = activeIndex
    }
}

extension Workset {
    /// Opis tekstowy do porównania worksetów (PD-WSET-001): każde okno z typem, tytułem albo plikiem, stanem i treścią
    /// (tekst okna albo — dla okna bez zmian — treść pliku z dysku).
    public func comparisonText() -> String {
        documents.map { d in
            let name = d.filePath.map { ($0 as NSString).lastPathComponent } ?? d.title ?? L10n.tr("bez nazwy")
            var head = "=== [\(d.kind.rawValue)] \(name)" + (d.modified ? " *" : "")
            if let c = d.connectionID { head += "  @\(c.uuidString.prefix(8))" }
            let body = d.text ?? d.filePath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }.map { TextFileCodec.decode($0).text }
                ?? L10n.tr("(brak pliku)")
            return head + "\n" + body
        }.joined(separator: "\n\n") + "\n"
    }
}

/// Układ okna głównego (UG 23.10 „Autosave desktop/layout”, PD-WSET-002): ramka, szerokość lewej kolumny, karta
/// lewej kolumny, panel agenta.
public struct WindowLayout: Sendable, Codable, Hashable {
    /// Ramka okna w formacie `NSStringFromRect` („{{x, y}, {w, h}}”).
    public var frame: String
    public var sidebarWidth: Double
    public var sidebarPane: Int
    public var agentPaneVisible: Bool

    public init(frame: String, sidebarWidth: Double, sidebarPane: Int, agentPaneVisible: Bool) {
        self.frame = frame; self.sidebarWidth = sidebarWidth; self.sidebarPane = sidebarPane; self.agentPaneVisible = agentPaneVisible
    }
}

/// Worksety i układ w katalogu danych (`Worksets/<nazwa>.json`, `Worksets/state.json`, `layout.json`); pliki 0600 —
/// niezapisany tekst okien może zawierać cokolwiek, co użytkownik wpisał.
@MainActor
@Observable
public final class WorksetStore {
    public static let defaultName = "Domyślny"

    struct State: Codable { var current: String }

    @ObservationIgnored let directory: URL?
    @ObservationIgnored let layoutURL: URL?
    public private(set) var current: String
    public private(set) var names: [String] = []
    /// Zmienia się po zapisie albo usunięciu workseta (lista w menu).
    public private(set) var generation = 0

    public init(directory: URL?, layoutURL: URL?) {
        self.directory = directory
        self.layoutURL = layoutURL
        current = Self.defaultName
        if let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            current = s.current
        }
        reloadNames()
    }

    func reloadNames() {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { names = []; return }
        names = files.filter { $0.hasSuffix(".json") && $0 != "state.json" }.map { String($0.dropLast(5)) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Nazwa pliku workseta bez separatorów ścieżki.
    nonisolated static func fileName(_ name: String) throws -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !n.contains("/"), !n.hasPrefix("."), n != "state" else {
            throw CommandError.invalidArgument("name", L10n.tr("nieprawidłowa nazwa workseta"))
        }
        return n + ".json"
    }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func save(_ w: Workset) throws {
        guard let directory else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try write(try enc.encode(w), to: directory.appendingPathComponent(try Self.fileName(w.name)))
        reloadNames()
        generation += 1
    }

    public func load(_ name: String) throws -> Workset? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(try Self.fileName(name))
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Workset.self, from: data)
    }

    public func delete(_ name: String) throws {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(try Self.fileName(name)))
        if current == name { setCurrent(Self.defaultName) }
        reloadNames()
        generation += 1
    }

    public func setCurrent(_ name: String) {
        current = name
        if let directory, let data = try? JSONEncoder().encode(State(current: name)) {
            try? write(data, to: directory.appendingPathComponent("state.json"))
        }
    }

    // MARK: Układ okna

    public func saveLayout(_ layout: WindowLayout) {
        guard let layoutURL, let data = try? JSONEncoder().encode(layout) else { return }
        try? write(data, to: layoutURL)
    }

    public func loadLayout() -> WindowLayout? {
        guard let layoutURL, let data = try? Data(contentsOf: layoutURL) else { return nil }
        return try? JSONDecoder().decode(WindowLayout.self, from: data)
    }
}

extension Workspace {
    /// Stan okien jako workset (bieżąca nazwa).
    public func worksetSnapshot(name: String? = nil) -> Workset {
        let docs: [WorksetDocument] = documents.compactMap { d in
            // Okna planu, raportów, diagramów i notatników mają własne formaty (Etapy 6–7) — pomijane.
            guard [.sql, .program, .test, .command].contains(d.kind) else { return nil }
            let keepText = d.fileURL == nil || d.isModified
            return WorksetDocument(kind: d.kind, title: d.customTitle, filePath: d.fileURL?.path, text: keepText ? d.text : nil,
                                   modified: d.isModified, selectionStart: d.selectedRange.lowerBound, selectionEnd: d.selectedRange.upperBound,
                                   connectionID: d.connectionPinned ? d.connectionID : nil,
                                   testVariables: d.kind == .test && keepText ? d.testVariables : nil,
                                   variables: d.variableValues.isEmpty ? nil : d.variableValues.mapValues(WorksetVariable.init))
        }
        let active = documents.filter { [.sql, .program, .test, .command].contains($0.kind) }.firstIndex { $0.id == activeDocumentID }
        return Workset(name: name ?? worksets.current, documents: docs, activeIndex: active)
    }

    /// Zastępuje okna oknami workseta (bieżące okna trzeba wcześniej zapisać do ich workseta). Plik, którego już nie
    /// ma, a okno nie miało tekstu — pomijany; zwraca listę pominiętych ścieżek.
    @discardableResult
    public func applyWorkset(_ w: Workset) -> [String] {
        for d in documents { close(d.id) }
        return appendWorksetDocuments(w)
    }

    /// Otwiera okna workseta obok bieżących (odzyskiwanie po awarii); zwraca pominięte ścieżki.
    @discardableResult
    public func appendWorksetDocuments(_ w: Workset) -> [String] {
        var missing: [String] = []
        var opened: [Document] = []
        for e in w.documents {
            let url = e.filePath.map { URL(fileURLWithPath: $0) }
            let doc: Document
            if let text = e.text {
                doc = newDocument(e.kind, text: text, fileURL: url)
                if let v = e.testVariables { doc.testVariables = v }
                doc.isModified = e.modified
            } else if let url, FileManager.default.fileExists(atPath: url.path), let d = try? openFile(url, as: e.kind) {
                doc = d
            } else {
                missing.append(e.filePath ?? "")
                continue
            }
            doc.customTitle = e.title
            if let v = e.variables { doc.variableValues = v.mapValues(\.value) }
            if let c = e.connectionID, connections.connection(c) != nil {
                doc.connectionID = c
                doc.connectionPinned = true
            }
            let len = (doc.text as NSString).length
            doc.selectedRange = min(e.selectionStart, len)..<min(max(e.selectionEnd, e.selectionStart), len)
            opened.append(doc)
        }
        if let i = w.activeIndex, i < opened.count { activate(opened[i].id) }
        return missing
    }

    /// Zapis bieżących okien do bieżącego workseta (autozapis przy zamykaniu aplikacji i przełączaniu).
    public func saveCurrentWorkset() throws {
        try worksets.save(worksetSnapshot())
    }

    /// Przełącza na workset: bieżący zapisany, okna zastąpione oknami wskazanego (nowy — pusty).
    @discardableResult
    public func switchWorkset(to name: String) throws -> [String] {
        _ = try WorksetStore.fileName(name)
        try saveCurrentWorkset()
        let target = try worksets.load(name) ?? Workset(name: name)
        worksets.setCurrent(name)
        let missing = applyWorkset(target)
        try worksets.save(worksetSnapshot())
        return missing
    }
}
