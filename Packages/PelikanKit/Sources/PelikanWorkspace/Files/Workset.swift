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
    /// Treść okien diagramu, notatnika i raportu bez pliku albo ze zmianami (D176).
    public var diagram: Diagram?
    public var notebook: Notebook?
    public var report: ReportDefinition?
    public var testWatches: [String]?
    /// Konsola połączenia (tekst konsoli trzyma `QueryConsoles`).
    public var consoleConnectionID: UUID?
    /// Format pliku okna z niezapisanymi zmianami (D55, R6-04): kodowanie (`String.Encoding.rawValue`), BOM i zakończenia
    /// wierszy. Starsze worksety ich nie mają — format czytany wtedy z pliku na dysku.
    public var encoding: UInt?
    public var bom: Bool?
    public var lineEnding: String?
    /// Okno programu powiązane z plikami specyfikacji i ciała (D194) — `filePath` to plik specyfikacji.
    public var unitFiles: [WorksetUnitFile]?

    /// Format zapisany w worksecie (nil — starszy workset).
    var fileFormat: TextFileFormat? {
        guard let encoding else { return nil }
        return TextFileFormat(encodingRaw: encoding, bom: bom, lineEnding: lineEnding)
    }

    /// Puste okno edytora bez pliku (np. okno SQL otwarte przy starcie) — nie warto go dopisywać do cudzego workseta.
    var isBlank: Bool {
        filePath == nil && consoleConnectionID == nil && !modified && (text ?? "").isEmpty && [.sql, .program, .command].contains(kind)
    }
}

/// Plik jednostki okna pary w worksecie (D194): ścieżka, część, format i zakończenie treści pliku.
public struct WorksetUnitFile: Sendable, Codable, Hashable {
    public var part: UnitFile.Part
    public var path: String
    public var encoding: UInt
    public var bom: Bool
    public var lineEnding: String
    public var ending: String

    init(_ f: UnitFile) {
        part = f.part
        path = f.url.path
        encoding = f.format.encoding.rawValue
        bom = f.format.hasBOM
        lineEnding = f.format.lineEnding.rawValue
        ending = f.ending
    }

    /// Plik jednostki; treść zapisana — z pliku na dysku (zapis pomija niezmienione pliki), brak pliku — pusta.
    var unitFile: UnitFile {
        let url = URL(fileURLWithPath: path)
        let format = TextFileFormat(encodingRaw: encoding, bom: bom, lineEnding: lineEnding)
        let saved = (try? Data(contentsOf: url)).map { TextFileCodec.decode($0).text } ?? ""
        return UnitFile(part: part, url: url, format: format, ending: ending, savedText: saved)
    }
}

extension TextFileFormat {
    init(encodingRaw: UInt, bom: Bool?, lineEnding: String?) {
        self.init()
        encoding = String.Encoding(rawValue: encodingRaw)
        hasBOM = bom ?? false
        self.lineEnding = lineEnding.flatMap(LineEnding.init(rawValue:)) ?? .lf
    }
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
    /// Zapisany workset, którego okien nie otwarto w tej sesji (start z `noloaddesktop` albo `workset=…`, R3-01): jego
    /// okna są dopisywane przy każdym zapisie workseta o tej nazwie, żeby autozapis ich nie nadpisał.
    public private(set) var unopened: Workset?
    /// Worksety, których nieczytelnego pliku nie udało się przenieść do kopii — zapis w ich miejsce zablokowany.
    @ObservationIgnored var damaged: Set<String> = []
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
        names = files.filter { $0.hasSuffix(".json") && $0.lowercased() != "state.json" }.map { String($0.dropLast(5)) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Nazwa istniejącego workseta bez względu na wielkość liter: na APFS „domyślny.json” to ten sam plik co
    /// „Domyślny.json”, więc nazwy różniące się tylko wielkością liter wskazują ten sam workset.
    public func existingName(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        return names.first { $0.caseInsensitiveCompare(n) == .orderedSame }
    }

    /// Nazwa pliku workseta bez separatorów ścieżki.
    nonisolated static func fileName(_ name: String) throws -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        // `State.json` to na APFS bez rozróżniania wielkości liter ten sam plik co `state.json` (R6-18).
        guard !n.isEmpty, !n.contains("/"), !n.hasPrefix("."), n.lowercased() != "state" else {
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
        let file = try Self.fileName(w.name)
        guard !damaged.contains(file) else { throw CommandError.notAvailable(L10n.tr("Plik „\(file)” jest uszkodzony albo pochodzi z nowszej wersji aplikacji — zmiany nie będą w nim zapisywane.")) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try write(try enc.encode(merged(w)), to: directory.appendingPathComponent(file))
        reloadNames()
        generation += 1
    }

    /// Workset z dopisanymi oknami nieotwartymi w tej sesji (`unopened`): bez pustych okien bieżących i bez plików już
    /// otwartych.
    func merged(_ w: Workset) -> Workset {
        guard let u = unopened, u.name.caseInsensitiveCompare(w.name) == .orderedSame else { return w }
        var m = w
        m.documents = []
        m.activeIndex = nil
        for (i, d) in w.documents.enumerated() where !d.isBlank {
            if i == w.activeIndex { m.activeIndex = m.documents.count }
            m.documents.append(d)
        }
        let paths = Set(m.documents.compactMap(\.filePath))
        m.documents += u.documents.filter { $0.filePath.map { !paths.contains($0) } ?? true }
        return m
    }

    /// Zapamiętuje zapisany workset, którego okien nie otwarto przy starcie (R3-01).
    public func keepUnopened(_ w: Workset) {
        unopened = w.documents.isEmpty ? nil : w
    }

    /// Okna workseta zostały otwarte — dopisywanie przy zapisie niepotrzebne.
    func clearUnopened(_ name: String) {
        if unopened?.name.caseInsensitiveCompare(name) == .orderedSame { unopened = nil }
    }

    /// Zapisany workset; nil — nie ma. Nieczytelny plik (uszkodzony albo z nowszej wersji) jest przenoszony do kopii
    /// `.bad-…` i zgłaszany błędem — autozapis nie nadpisze go oknami bieżącej sesji (R6-11).
    public func load(_ name: String) throws -> Workset? {
        guard let directory else { return nil }
        let file = try Self.fileName(name)
        let url = directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode(Workset.self, from: data)
        } catch {
            let (message, preserved) = DamagedFile.preserve(url)
            if !preserved { damaged.insert(file) }
            reloadNames()
            throw CommandError.notAvailable(message)
        }
    }

    public func delete(_ requested: String) throws {
        guard let directory else { return }
        let name = existingName(requested) ?? requested
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(try Self.fileName(name)))
        clearUnopened(name)
        if current.caseInsensitiveCompare(name) == .orderedSame { setCurrent(Self.defaultName) }
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
        // Wszystkie rodzaje okien (D176): okno bez pliku albo ze zmianami — z treścią (tekst, diagram, notatnik,
        // raport); okno z niezmienionym plikiem — sam plik, czytany ponownie przy otwarciu.
        let docs: [WorksetDocument] = documents.map { d in
            let keepText = d.fileURL == nil || d.isModified
            var e = WorksetDocument(kind: d.kind, title: d.customTitle, filePath: d.fileURL?.path, text: keepText ? d.text : nil,
                                    modified: d.isModified, selectionStart: d.selectedRange.lowerBound, selectionEnd: d.selectedRange.upperBound,
                                    connectionID: d.connectionPinned ? d.connectionID : nil,
                                    testVariables: d.kind == .test && keepText ? d.testVariables : nil,
                                    variables: d.variableValues.isEmpty ? nil : d.variableValues.mapValues(WorksetVariable.init))
            if keepText {
                if d.kind == .diagram { e.diagram = d.diagram }
                if d.kind == .notebook { e.notebook = d.notebook }
                if d.kind == .report { e.report = d.report }
                if d.kind == .test, !d.testWatches.isEmpty { e.testWatches = d.testWatches }
                if d.fileURL != nil {
                    e.encoding = d.fileFormat.encoding.rawValue
                    e.bom = d.fileFormat.hasBOM
                    e.lineEnding = d.fileFormat.lineEnding.rawValue
                }
            }
            if !d.unitFiles.isEmpty { e.unitFiles = d.unitFiles.map(WorksetUnitFile.init) }
            if let c = d.consoleConnectionID {
                e.consoleConnectionID = c
                e.text = nil
            }
            return e
        }
        let active = documents.firstIndex { $0.id == activeDocumentID }
        return Workset(name: name ?? worksets.current, documents: docs, activeIndex: active)
    }

    /// Zastępuje okna oknami workseta (bieżące okna trzeba wcześniej zapisać do ich workseta). Plik, którego już nie
    /// ma, a okno nie miało tekstu — pomijany; zwraca listę pominiętych ścieżek. Anulowanie pytania o transakcję albo
    /// okno w trakcie wykonania przerywa zmianę (błąd).
    @discardableResult
    public func applyWorkset(_ w: Workset) async throws -> [String] {
        try await closeDocumentsForWorkset()
        worksets.clearUnopened(w.name)
        return appendWorksetDocuments(w)
    }

    /// Zamyka wszystkie okna tą samą drogą co zamykanie okna (R6-01): odmowa przy wykonaniu, zatrzymanie debugera,
    /// pytanie o otwartą transakcję, zamknięcie sesji okna i debugera — bez pytania o zapis (treść okien jest już
    /// w zapisanym worksecie). Anulowanie przerywa zmianę workseta; okna zamknięte do tej chwili wracają z migawki.
    func closeDocumentsForWorkset() async throws {
        let docs = documents
        let entries = worksetSnapshot().documents
        // Najpierw okna, które mogą odmówić albo zapytać — wcześniej nic nie jest zamykane bez potrzeby.
        let asks = { (d: Document) in d.transactionOpen || self.debuggers[d.id] != nil }
        let order = docs.indices.filter { docs[$0].isExecuting }
            + docs.indices.filter { !docs[$0].isExecuting && asks(docs[$0]) }
            + docs.indices.filter { !docs[$0].isExecuting && !asks(docs[$0]) }
        var closed: [WorksetDocument] = []
        do {
            for i in order {
                guard try await BuiltinCommands.closeDocument(docs[i], in: self, askToSave: false) else { throw CommandError.cancelledByUser }
                closed.append(entries[i])
            }
        } catch {
            if !closed.isEmpty { appendWorksetDocuments(Workset(name: worksets.current, documents: closed)) }
            throw error
        }
    }

    /// Otwiera okna workseta obok bieżących (odzyskiwanie po awarii); zwraca pominięte ścieżki.
    @discardableResult
    public func appendWorksetDocuments(_ w: Workset) -> [String] {
        var missing: [String] = []
        // Indeks wpisu → otwarte okno: pominięte wpisy nie przesuwają okna aktywnego (R6-14).
        var opened: [Int: Document] = [:]
        for (i, e) in w.documents.enumerated() {
            let url = e.filePath.map { URL(fileURLWithPath: $0) }
            let doc: Document
            if let c = e.consoleConnectionID {
                guard connections.connection(c) != nil else { continue }
                opened[i] = openConsole(connection: c)
                continue
            } else if let text = e.text {
                doc = newDocument(e.kind, text: text, fileURL: url)
                // Kodowanie, BOM i zakończenia wierszy pliku (D55): z workseta, w starszych worksetach — z pliku na dysku.
                if let url {
                    doc.fileFormat = e.fileFormat
                        ?? (try? Data(contentsOf: url)).map { TextFileCodec.decode($0, preferred: projectEncoding(for: url)).format }
                        ?? TextFileFormat()
                }
                if let v = e.testVariables { doc.testVariables = v }
                if let w = e.testWatches { doc.testWatches = w }
                if let x = e.diagram { doc.diagram = x }
                if let x = e.notebook { doc.notebook = x }
                if let x = e.report { doc.report = x }
                if let files = e.unitFiles, e.kind == .program { doc.unitFiles = files.map(\.unitFile) }
                doc.isModified = e.modified
            } else if let files = e.unitFiles, let spec = files.first(where: { $0.part == .spec }), let body = files.first(where: { $0.part == .body }),
                      let d = try? openUnitFiles(spec: URL(fileURLWithPath: spec.path), body: URL(fileURLWithPath: body.path), show: .spec) {
                // Okno pary bez zmian (D194): oba pliki czytane ponownie, niezależnie od preferencji otwierania pary.
                doc = d
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
            opened[i] = doc
        }
        if let i = w.activeIndex, let d = opened[i] { activate(d.id) }
        return missing
    }

    /// Zapis bieżących okien do bieżącego workseta (autozapis przy zamykaniu aplikacji i przełączaniu).
    public func saveCurrentWorkset() throws {
        try worksets.save(worksetSnapshot())
    }

    /// Przełącza na workset: bieżący zapisany, okna zastąpione oknami wskazanego (nowy — pusty). Anulowane pytanie
    /// o transakcję albo okno w trakcie wykonania — bez zmiany workseta (błąd).
    @discardableResult
    public func switchWorkset(to requested: String) async throws -> [String] {
        _ = try WorksetStore.fileName(requested)
        // Istniejący workset pod nazwą z pliku — inna wielkość liter nie tworzy drugiej nazwy tego samego pliku.
        let name = worksets.existingName(requested) ?? requested.trimmingCharacters(in: .whitespaces)
        try saveCurrentWorkset()
        let target = try worksets.load(name) ?? Workset(name: name)
        let missing = try await applyWorkset(target)
        worksets.setCurrent(name)
        try worksets.save(worksetSnapshot())
        return missing
    }
}
