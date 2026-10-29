import Foundation
import PelikanLog

/// Stan pliku na dysku z chwili otwarcia, zapisu albo wczytania ponownego (D197): data modyfikacji, rozmiar i skrót
/// bajtów. Zmiana daty bez zmiany treści (`touch`) nie jest zmianą.
public struct FileStamp: Sendable, Hashable, Codable {
    public var modified: Date?
    public var size: Int
    public var hash: UInt64

    public init(modified: Date?, size: Int, hash: UInt64) {
        self.modified = modified; self.size = size; self.hash = hash
    }

    /// Stan pliku po odczycie albo zapisie danych `data`.
    public static func of(_ url: URL, data: Data) -> FileStamp {
        // Dowiązanie symboliczne — stan pliku docelowego (zapis przez dowiązanie zapisuje cel).
        let a = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
        return FileStamp(modified: a?[.modificationDate] as? Date, size: data.count, hash: UnitFile.fingerprint(data))
    }
}

/// Zmiana pliku okna wykonana przez inny program (agent, git, edytor zewnętrzny).
public struct ExternalFileChange: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case modified, deleted }
    public var url: URL
    public var kind: Kind
    /// Okno (albo karta pliku w oknie pary) ma niezapisane zmiany.
    public var windowModified: Bool
}

extension Document {
    /// Czy tekst okna dla pliku `url` różni się od zapisanego (okno pary — karta pliku, inaczej całe okno).
    func hasUnsavedChanges(for url: URL) -> Bool {
        guard isModified else { return false }
        guard let f = unitFiles.first(where: { $0.url == url.standardizedFileURL }) else { return true }
        return f.needsRewrite || currentText(of: f.url).map { $0 != f.savedText } ?? true
    }
}

extension Workspace {
    /// Zapamiętuje stan pliku okna po odczycie albo zapisie (`data` — bajty pliku) — wykrywanie zmian na dysku (D197).
    func rememberDiskState(_ doc: Document, url: URL, data: Data) {
        let u = url.standardizedFileURL
        doc.diskStamps[u] = FileStamp.of(u, data: data)
        if doc.unitFiles.isEmpty { doc.savedFileHash = UnitFile.fingerprint(data) }
    }

    /// Pliki okna zmienione albo usunięte przez inny program od ostatniego odczytu, zapisu albo „Zostaw”. Zmiana samej
    /// daty modyfikacji (`touch`) uaktualnia zapamiętany stan bez zgłoszenia.
    public func externalChanges(of doc: Document) -> [ExternalFileChange] {
        var out: [ExternalFileChange] = []
        for url in doc.fileURLs {
            guard let stamp = doc.diskStamps[url] else { continue }
            // `fileExists` podąża za dowiązaniem — wiszące dowiązanie (cel usunięty) to plik usunięty.
            guard FileManager.default.fileExists(atPath: url.path),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path) else {
                out.append(ExternalFileChange(url: url, kind: .deleted, windowModified: doc.hasUnsavedChanges(for: url)))
                continue
            }
            let modified = attrs[.modificationDate] as? Date
            let size = (attrs[.size] as? NSNumber)?.intValue ?? -1
            // Wolumin sieciowy (SMB, NFS): daty bywają zaokrąglane albo z innego zegara — zawsze porównanie treści.
            if modified == stamp.modified, size == stamp.size, Self.isLocalVolume(url) { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let hash = UnitFile.fingerprint(data)
            if hash == stamp.hash {
                // Tylko data (touch, git bez zmiany treści) — nowy stan bez pytania.
                doc.diskStamps[url] = FileStamp(modified: modified, size: data.count, hash: hash)
                continue
            }
            out.append(ExternalFileChange(url: url, kind: .modified, windowModified: doc.hasUnsavedChanges(for: url)))
        }
        return out
    }

    /// Czy plik leży na woluminie lokalnym (na Linuksie i przy braku informacji — tak).
    nonisolated static func isLocalVolume(_ url: URL) -> Bool {
        #if canImport(Darwin)
        return (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? true
        #else
        return true
        #endif
    }

    /// „Zostaw” / „Zachowaj moje zmiany”: obecny stan dysku jako znany — bez ponownego pytania do następnej zmiany;
    /// zapis (⌘S) nadal ostrzega, bo treść zapisana okna się nie zmienia.
    public func acceptDiskState(_ doc: Document, url: URL) {
        let u = url.standardizedFileURL
        if let data = try? Data(contentsOf: u) { doc.diskStamps[u] = FileStamp.of(u, data: data) }
    }

    /// Wczytuje ponownie z dysku plik okna `url` (okno pary — tylko kartę tego pliku; pozostałe karty bez zmian).
    /// Kursor zostaje w tym samym miejscu karty, jeśli się da. Historia lokalna dostaje tekst sprzed wczytania, gdy okno
    /// miało zmiany.
    public func reloadFromDisk(_ doc: Document, url: URL? = nil) throws {
        let target = (url ?? doc.fileURL)?.standardizedFileURL
        guard let target, doc.fileURLs.contains(target) else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie ma pliku")) }
        let data = try Data(contentsOf: target)
        // Tekst sprzed wczytania zawsze w historii lokalnej (także okno bez zmian i wczytanie bez pytania).
        recordHistory(doc, text: doc.text, label: L10n.tr("przed: wczytanie z dysku"))
        if doc.unitFiles.isEmpty {
            try reloadSingleFile(doc, url: target, data: data)
        } else {
            try reloadUnitFile(doc, url: target, data: data)
        }
        Log.files.info("Plik okna wczytany ponownie z dysku: \(target.lastPathComponent, privacy: .hash)")
    }

    private func reloadSingleFile(_ doc: Document, url: URL, data: Data) throws {
        let caret = doc.selectedRange.lowerBound
        switch doc.kind {
        case .report:
            let r = try ReportDefinition.decode(data)
            doc.report = r
            doc.text = r.sql
        case .diagram:
            doc.diagram = try Diagram.decode(data)
        case .notebook:
            doc.notebook = try Notebook.decode(data)
        case .test where url.pathExtension.lowercased() == "tst":
            let (text, format) = TextFileCodec.decode(data, preferred: projectEncoding(for: url))
            let f = TestScriptFile.decode(text)
            doc.text = f.block
            doc.testVariables = f.variables
            doc.testWatches = f.watches ?? []
            doc.fileFormat = format
            TestRunner.synchronize(doc)
        default:
            let (text, format) = TextFileCodec.decode(data, preferred: projectEncoding(for: url))
            doc.text = text
            doc.fileFormat = format
        }
        let len = (doc.text as NSString).length
        doc.selectedRange = min(caret, len)..<min(caret, len)
        doc.isModified = false
        rememberDiskState(doc, url: url, data: data)
    }

    private func reloadUnitFile(_ doc: Document, url: URL, data: Data) throws {
        let tabs = doc.programUnitTabs
        guard let parts = SpecBodyFiles.parts(doc.programUnits, tabs: tabs), let k = doc.unitFiles.firstIndex(where: { $0.url == url }) else {
            throw UnitFilesError.notAPair(spec: doc.unitFiles.first?.url.lastPathComponent ?? "?", body: doc.unitFiles.last?.url.lastPathComponent ?? "?")
        }
        let decoded = TextFileCodec.decode(data, preferred: projectEncoding(for: url))
        // Teksty kart: plik wczytany z dysku, pozostałe — jak w oknie (także niezapisane).
        let texts = parts.map { p in p == doc.unitFiles[k].part ? decoded.text : doc.unitFiles.first { $0.part == p }.flatMap { doc.currentText(of: $0.url) } ?? "" }
        let text = SpecBodyFiles.join(spec: texts[0], body: texts[1])
        let units = ProgramCompiler.units(in: text)
        let newTabs = ProgramUnitTabs.tabs(units, in: text)
        // Obieg jak przy otwarciu pary: podział nowego tekstu na karty musi dać te same pliki (np. komentarz za END
        // specyfikacji przeszedłby do karty ciała), a każdy plik — jedną jednostkę swojej karty.
        let endings = parts.map { p in p == doc.unitFiles[k].part ? SpecBodyFiles.splitEnding(decoded.text).ending : doc.unitFiles.first { $0.part == p }?.ending ?? "\n" }
        guard SpecBodyFiles.parts(units, tabs: newTabs) == parts,
              SpecBodyFiles.fileTexts(text, tabs: newTabs, endings: endings) == texts,
              SpecBodyFiles.mismatch(texts, units: units) == nil else {
            throw CommandError.notAvailable(L10n.tr("Pliku \(url.lastPathComponent) nie da się wczytać do karty okna pary (inny podział na jednostki) — otwórz go osobno."))
        }
        // Kursor w tej samej karcie i w tym samym miejscu karty.
        let tab = doc.activeUnitTab ?? 0
        let rel = doc.selectedRange.lowerBound - (tabs.indices.contains(tab) ? tabs[tab].segment.lowerBound : 0)
        doc.unitFiles[k].format = decoded.format
        doc.unitFiles[k].ending = SpecBodyFiles.splitEnding(decoded.text).ending
        doc.unitFiles[k].savedText = decoded.text
        doc.unitFiles[k].savedHash = UnitFile.fingerprint(data)
        doc.unitFiles[k].needsRewrite = false
        let wasModified = doc.unitFiles.indices.contains { $0 != k && doc.hasUnsavedChanges(for: doc.unitFiles[$0].url) }
        doc.text = text
        doc.cacheProgramUnits(units, forText: text)
        doc.cacheProgramUnitTabs(newTabs, forText: text)
        if newTabs.indices.contains(tab) {
            let seg = newTabs[tab].segment
            let o = min(seg.lowerBound + max(0, rel), ProgramUnitTabs.caretLimit(newTabs[tab], isLast: tab == newTabs.count - 1, in: text as NSString))
            doc.selectedRange = o..<o
        }
        doc.isModified = wasModified
        doc.diskStamps[url] = FileStamp.of(url, data: data)
    }

    /// Sprawdza pliki okna przy aktywacji okna, karty albo aplikacji (D197) i pyta o każdą zmianę po kolei: okno bez
    /// zmian — „Wczytaj ponownie / Zostaw” (albo wczytanie bez pytania z preferencją), okno ze zmianami — ostrzeżenie
    /// o utracie zmian, plik usunięty — „Zachowaj w oknie / Zamknij okno”. Jedno sprawdzenie naraz, nie w trakcie
    /// zapisu, nie bez interfejsu (tryb skryptu). Zwraca liczbę obsłużonych zmian.
    @discardableResult
    public func checkExternalChanges(of doc: Document) async -> Int {
        guard settings.detectExternalFileChanges, externalChangePromptsEnabled, savingDocuments == 0, !checkingExternalChanges,
              documents.contains(where: { $0.id == doc.id }), let ui else { return 0 }
        let changes = externalChanges(of: doc)
        guard !changes.isEmpty else { return 0 }
        checkingExternalChanges = true
        defer { checkingExternalChanges = false }
        var handled = 0
        for c in changes {
            guard documents.contains(where: { $0.id == doc.id }) else { break }
            let name = c.url.lastPathComponent
            handled += 1
            switch c.kind {
            case .deleted:
                Log.files.notice("Plik okna usunięty albo przeniesiony poza Pelikanem: \(name, privacy: .hash)")
                let choice = await ui.ask(L10n.tr("Plik „\(name)” nie istnieje na dysku"),
                                          message: L10n.tr("Inny program usunął albo przeniósł plik. Tekst zostaje w oknie — zapis utworzy plik ponownie."),
                                          buttons: [L10n.tr("Zachowaj w oknie"), L10n.tr("Zamknij okno")], escapeButton: 0)
                doc.diskStamps[c.url] = nil
                if choice == 1 {
                    // Okno ze zmianami — zwykłe pytanie o zapis (zapis utworzy plik ponownie).
                    _ = try? await BuiltinCommands.closeDocument(doc, in: self, askToSave: doc.isModified)
                    return handled
                }
                doc.isModified = true
            case .modified:
                Log.files.info("Plik okna zmieniony przez inny program: \(name, privacy: .hash)")
                var reload = !c.windowModified && settings.reloadExternalChangesSilently
                if !reload {
                    // Bez dodatkowego „Anuluj”: Esc — bezpieczny wybór (Zostaw / Zachowaj moje zmiany).
                    let choice: Int?
                    if c.windowModified {
                        choice = await ui.ask(L10n.tr("Plik „\(name)” został zmieniony przez inny program. Wczytać go ponownie?"),
                                              message: L10n.tr("Okno ma niezapisane zmiany."),
                                              buttons: [L10n.tr("Wczytaj ponownie (utracisz zmiany)"), L10n.tr("Zachowaj moje zmiany")], escapeButton: 1)
                    } else {
                        choice = await ui.ask(L10n.tr("Plik „\(name)” został zmieniony przez inny program. Wczytać go ponownie?"),
                                              message: L10n.tr("Okno nie ma niezapisanych zmian."),
                                              buttons: [L10n.tr("Wczytaj ponownie"), L10n.tr("Zostaw")], escapeButton: 1)
                    }
                    reload = choice == 0
                }
                guard reload else {
                    acceptDiskState(doc, url: c.url)
                    continue
                }
                do { try reloadFromDisk(doc, url: c.url) } catch {
                    // Nieudane wczytanie (także bez pytania): stan dysku jako znany — bez pytania przy każdej aktywacji;
                    // błąd widoczny dla użytkownika i w dzienniku.
                    acceptDiskState(doc, url: c.url)
                    Log.files.error("Nie udało się wczytać ponownie pliku okna \(name, privacy: .hash): \(error)")
                    ui.showError(error.localizedDescription)
                }
            }
        }
        return handled
    }
}
