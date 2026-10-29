import Foundation
import PelikanLog

/// Stan pliku na dysku z chwili otwarcia, zapisu albo wczytania ponownego (D197): data modyfikacji, rozmiar i skrót
/// bajtów. Zmiana daty bez zmiany treści (`touch`) nie jest zmianą.
public struct FileStamp: Sendable, Hashable, Codable {
    public var modified: Date?
    public var size: Int
    public var hash: UInt64
    /// Czas zmiany metadanych (ctime) i identyfikator pliku (i-węzeł) — podmiana pliku z tą samą datą i rozmiarem.
    public var changed: Date?
    public var resourceID: String?

    public init(modified: Date?, size: Int, hash: UInt64, changed: Date? = nil, resourceID: String? = nil) {
        self.modified = modified; self.size = size; self.hash = hash; self.changed = changed; self.resourceID = resourceID
    }

    /// Metadane pliku bez odczytu treści (dowiązanie — plik docelowy); nil — pliku nie ma.
    nonisolated static func metadata(_ url: URL) -> (modified: Date?, size: Int, changed: Date?, resourceID: String?)? {
        let target = url.resolvingSymlinksInPath()
        guard let a = try? FileManager.default.attributesOfItem(atPath: target.path) else { return nil }
        var changed: Date?, id: String?
        #if canImport(Darwin)
        if let v = try? target.resourceValues(forKeys: [.attributeModificationDateKey, .fileResourceIdentifierKey]) {
            changed = v.attributeModificationDate
            id = v.fileResourceIdentifier.map { String(describing: $0) }
        }
        #endif
        return (a[.modificationDate] as? Date, (a[.size] as? NSNumber)?.intValue ?? -1, changed, id)
    }

    /// Stan pliku po odczycie albo zapisie danych `data`.
    public static func of(_ url: URL, data: Data) -> FileStamp {
        // Dowiązanie symboliczne — stan pliku docelowego (zapis przez dowiązanie zapisuje cel).
        let m = metadata(url)
        return FileStamp(modified: m?.modified, size: data.count, hash: UnitFile.fingerprint(data), changed: m?.changed, resourceID: m?.resourceID)
    }

    /// Te same metadane (data, rozmiar, a gdy znane — ctime i identyfikator pliku).
    func sameMetadata(_ m: (modified: Date?, size: Int, changed: Date?, resourceID: String?)) -> Bool {
        modified == m.modified && size == m.size
            && (changed == nil || m.changed == nil || changed == m.changed)
            && (resourceID == nil || m.resourceID == nil || resourceID == m.resourceID)
    }
}

/// Zmiana pliku okna wykonana przez inny program (agent, git, edytor zewnętrzny).
public struct ExternalFileChange: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case modified, deleted }
    public var url: URL
    public var kind: Kind
    /// Okno (albo karta pliku w oknie pary) ma niezapisane zmiany.
    public var windowModified: Bool
    /// Stan pliku znany oknu w chwili wykrycia — zmieniony do chwili pytania (np. własny zapis) — zmiana nieaktualna.
    var known: FileStamp?
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
    /// daty modyfikacji (`touch`) uaktualnia zapamiętany stan bez zgłoszenia. Treść czytana tylko przy zmianie metadanych
    /// (data, rozmiar, ctime, identyfikator pliku); na woluminie nielokalnym (daty zaokrąglane albo z innego zegara)
    /// także bez zmiany metadanych, ale nie częściej niż co 5 s na plik. Odczyt i skrót poza wątkiem głównym.
    public func externalChanges(of doc: Document, now: Date = Date()) async -> [ExternalFileChange] {
        var out: [ExternalFileChange] = []
        var toRead: [URL] = []
        for url in doc.fileURLs {
            guard let stamp = doc.diskStamps[url] else { continue }
            // `fileExists` podąża za dowiązaniem — wiszące dowiązanie (cel usunięty) to plik usunięty.
            guard FileManager.default.fileExists(atPath: url.path), let m = FileStamp.metadata(url) else {
                out.append(ExternalFileChange(url: url, kind: .deleted, windowModified: doc.hasUnsavedChanges(for: url), known: stamp))
                continue
            }
            if stamp.sameMetadata(m) {
                if Self.isLocalVolume(url) { continue }
                if let last = doc.contentChecks[url], now.timeIntervalSince(last) < 5 { continue }
            }
            toRead.append(url)
        }
        guard !toRead.isEmpty else { return out }
        let list = toRead
        // Stan sprzed odczytu: własny zapis (albo wczytanie) w trakcie odczytu zmienia go — wtedy odczytana treść jest
        // nieaktualna i nie jest zmianą z zewnątrz.
        let before = Dictionary(uniqueKeysWithValues: list.map { ($0, doc.diskStamps[$0]) })
        let read = await Task.detached { () -> [(URL, Data?)] in list.map { ($0, try? Data(contentsOf: $0)) } }.value
        afterExternalRead?()
        for (url, data) in read {
            doc.contentChecks[url] = now
            guard let data, let stamp = doc.diskStamps[url], stamp == before[url] ?? nil else { continue }
            let hash = UnitFile.fingerprint(data)
            if hash == stamp.hash {
                // Bez zmiany treści (touch, git bez zmiany) — nowy stan bez pytania.
                doc.diskStamps[url] = FileStamp.of(url, data: data)
                continue
            }
            out.append(ExternalFileChange(url: url, kind: .modified, windowModified: doc.hasUnsavedChanges(for: url), known: stamp))
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
        if let data = try? Data(contentsOf: u) {
            doc.diskStamps[u] = FileStamp.of(u, data: data)
        } else if let m = FileStamp.metadata(u) {
            // Plik nie do odczytu: data i rozmiar z atrybutów, skrót dotychczasowy (nieznany) — bez pytania przy każdej
            // aktywacji, do następnej zmiany metadanych.
            doc.diskStamps[u] = FileStamp(modified: m.modified, size: m.size, hash: doc.diskStamps[u]?.hash ?? 0, changed: m.changed, resourceID: m.resourceID)
        }
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
        // Flaga przed pierwszym await — drugi wyzwalacz w tym czasie (aktywacja okna i aplikacji naraz) nie pyta drugi raz.
        checkingExternalChanges = true
        defer {
            checkingExternalChanges = false
            // Aktywacja innego okna w trakcie (jego sprawdzenie odbiło się od blokady) — sprawdzenie okna aktywnego teraz.
            if let active = activeDocument, active.id != doc.id, active.fileURL != nil {
                Task { await self.checkExternalChanges(of: active) }
            }
        }
        let changes = await externalChanges(of: doc)
        guard !changes.isEmpty else { return 0 }
        var handled = 0
        for var c in changes {
            // Po każdym await: zapis w toku, okno zamknięte albo stan pliku zmieniony w międzyczasie (własny zapis,
            // wczytanie) — bez pytania o nieaktualną zmianę.
            guard savingDocuments == 0, documents.contains(where: { $0.id == doc.id }) else { break }
            guard doc.diskStamps[c.url] == c.known else { continue }
            c.windowModified = doc.hasUnsavedChanges(for: c.url)
            let name = c.url.lastPathComponent
            handled += 1
            switch c.kind {
            case .deleted:
                Log.files.notice("Plik okna usunięty albo przeniesiony poza Pelikanem: \(name, privacy: .hash)")
                let choice = await ui.ask(L10n.tr("Plik „\(name)” nie istnieje na dysku"),
                                          message: L10n.tr("Inny program usunął albo przeniósł plik. Tekst zostaje w oknie — zapis utworzy plik ponownie."),
                                          buttons: [L10n.tr("Zachowaj w oknie"), L10n.tr("Zamknij okno")], escapeButton: 0, defaultButton: 0)
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
                                              buttons: [L10n.tr("Wczytaj ponownie (utracisz zmiany)"), L10n.tr("Zachowaj moje zmiany")],
                                              escapeButton: 1, defaultButton: 1, destructiveButton: 0)
                    } else {
                        choice = await ui.ask(L10n.tr("Plik „\(name)” został zmieniony przez inny program. Wczytać go ponownie?"),
                                              message: L10n.tr("Okno nie ma niezapisanych zmian."),
                                              buttons: [L10n.tr("Wczytaj ponownie"), L10n.tr("Zostaw")], escapeButton: 1, defaultButton: 0)
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
