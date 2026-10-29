import Foundation
import PelikanDB
import PelikanSQL

/// Rozszerzenia plików specyfikacji i ciała pakietu i typu (D194, Preferencje › Ogólne). W repozytoriach właściciela
/// specyfikacja i ciało leżą w osobnych plikach, bez „/” na końcu.
public struct SpecBodyExtensions: Sendable, Hashable, Codable {
    public var packageSpec = "pks"
    public var packageBody = "pkb"
    public var typeSpec = "tps"
    public var typeBody = "tpb"

    public init() {}

    // Dekodowanie odporne na brakujące pola (starsze ustawienia).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packageSpec = (try? c.decodeIfPresent(String.self, forKey: .packageSpec)) ?? packageSpec
        packageBody = (try? c.decodeIfPresent(String.self, forKey: .packageBody)) ?? packageBody
        typeSpec = (try? c.decodeIfPresent(String.self, forKey: .typeSpec)) ?? typeSpec
        typeBody = (try? c.decodeIfPresent(String.self, forKey: .typeBody)) ?? typeBody
    }

    /// Rozszerzenie wpisane w Preferencjach: bez kropki i spacji, małymi literami; puste — domyślne.
    public static func normalized(_ s: String, default d: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces).drop { $0 == "." }.lowercased()
        return t.isEmpty || t.contains("/") ? d : t
    }

    private var resolved: (ps: String, pb: String, ts: String, tb: String) {
        let def = SpecBodyExtensions()
        return (Self.normalized(packageSpec, default: def.packageSpec), Self.normalized(packageBody, default: def.packageBody),
                Self.normalized(typeSpec, default: def.typeSpec), Self.normalized(typeBody, default: def.typeBody))
    }

    /// Rozszerzenia pary dla typu obiektu (pakiet albo typ — specyfikacja lub ciało); inne typy — nil.
    public func pair(for type: DBObjectType) -> (spec: String, body: String)? {
        let r = resolved
        switch type {
        case .package, .packageBody: return (r.ps, r.pb)
        case .type, .typeBody: return (r.ts, r.tb)
        default: return nil
        }
    }

    /// Wszystkie cztery rozszerzenia (otwierane jako okno programu).
    public var all: [String] { let r = resolved; return [r.ps, r.pb, r.ts, r.tb] }

    /// Rozszerzenie pliku pary i część, którą jest plik o rozszerzeniu `ext` (bez wielkości liter).
    public func partner(of ext: String) -> (partner: String, part: UnitFile.Part)? {
        let e = ext.lowercased()
        let r = resolved
        for (s, b) in [(r.ps, r.pb), (r.ts, r.tb)] where s != b {
            if e == s { return (b, .spec) }
            if e == b { return (s, .body) }
        }
        return nil
    }
}

/// Plik jednostki okna programu (D194): specyfikacja albo ciało pakietu/typu w osobnym pliku. Każdy plik ma własny
/// format (kodowanie, BOM, zakończenia linii) i zakończenie treści.
public struct UnitFile: Sendable, Hashable {
    public enum Part: String, Sendable, Codable, Hashable { case spec, body }
    public var part: Part
    public var url: URL
    public var format: TextFileFormat
    /// Białe znaki za ostatnim znakiem treści pliku (zwykle „\n”) — przywracane przy zapisie.
    public var ending: String
    /// Treść pliku (LF) z ostatniego odczytu albo zapisu — zapis pomija pliki, których jednostka się nie zmieniła.
    public var savedText: String

    public init(part: Part, url: URL, format: TextFileFormat = TextFileFormat(), ending: String = "\n", savedText: String = "") {
        self.part = part; self.url = url.standardizedFileURL; self.format = format; self.ending = ending; self.savedText = savedText
    }
}

/// Podział tekstu okna programu na pliki specyfikacji i ciała (D194). Okno pokazuje karty jednostek (D192); tekst
/// każdej karty to treść jej pliku: specyfikacja bez końcowych pustych linii + pusta linia + ciało. Zapis zdejmuje
/// tę pustą linię (początek karty ciała) i przywraca zakończenie pliku — niezmienione okno daje pliki bajt w bajt.
public enum SpecBodyFiles {
    /// Części kart okna w kolejności tekstu, gdy okno ma dokładnie specyfikację i ciało tego samego pakietu albo typu.
    public static func parts(_ units: [ProgramUnit], tabs: [ProgramUnitTab]) -> [UnitFile.Part]? {
        let units = units.sorted { $0.range.lowerBound < $1.range.lowerBound }
        guard units.count == 2, tabs.count == 2, units[0].name == units[1].name,
              (units[0].owner ?? "") == (units[1].owner ?? "") else { return nil }
        let kinds = Set(units.map(\.type))
        guard kinds == [.package, .packageBody] || kinds == [.type, .typeBody] else { return nil }
        return units.map { [.package, .type].contains($0.type) ? .spec : .body }
    }

    /// Typ specyfikacji (pakiet albo typ), gdy tekst okna to para specyfikacja + ciało; inaczej nil.
    public static func pairType(_ units: [ProgramUnit], tabs: [ProgramUnitTab]) -> DBObjectType? {
        guard parts(units, tabs: tabs) != nil else { return nil }
        return units.first { [.package, .type].contains($0.type) }?.type
    }

    /// Treść pliku bez końcowych białych znaków i same te znaki.
    public static func splitEnding(_ s: String) -> (content: String, ending: String) {
        var content = Substring(s)
        while let c = content.last, c.isWhitespace { content.removeLast() }
        return (String(content), String(s[content.endIndex...]))
    }

    /// Tekst okna z plików pary (specyfikacja pierwsza).
    public static func join(spec: String, body: String) -> String {
        splitEnding(spec).content + "\n\n" + body
    }

    /// Treść plików kart (w kolejności kart): odcinek karty, bez pustej linii oddzielającej od poprzedniej karty,
    /// z zakończeniem pliku `endings[i]`.
    public static func fileTexts(_ text: String, tabs: [ProgramUnitTab], endings: [String]) -> [String] {
        let ns = text as NSString
        return tabs.enumerated().map { i, t in
            let r = NSRange(location: min(t.segment.lowerBound, ns.length), length: min(t.segment.upperBound, ns.length) - min(t.segment.lowerBound, ns.length))
            var s = ns.substring(with: r)
            if i > 0, s.hasPrefix("\n") { s.removeFirst() }
            return splitEnding(s).content + (i < endings.count ? endings[i] : "\n")
        }
    }

    /// Linia (od 1) okna dla linii pliku karty `tab` (od 1) — skok do linii z listy wyników albo projektu.
    public static func documentLine(_ fileLine: Int, tab: Int, tabs: [ProgramUnitTab], in text: String) -> Int {
        guard tabs.indices.contains(tab) else { return fileLine }
        let ns = text as NSString
        let start = min(tabs[tab].segment.lowerBound, ns.length)
        // Linia początku odcinka (od 0) + pusta linia oddzielająca kartę ciała + linia pliku (od 1).
        var line = TextEditing.line(containing: start, in: text)
        if tab > 0, start < ns.length, ns.character(at: start) == 0x0A { line += 1 }
        return line + fileLine
    }
}

/// Błąd zapisu okna powiązanego z plikami specyfikacji i ciała.
public enum UnitFilesError: Error, LocalizedError, Equatable {
    case notAPair(spec: String, body: String)

    public var errorDescription: String? {
        switch self {
        case let .notAPair(spec, body):
            L10n.tr("Okno jest powiązane z plikami \(spec) i \(body), ale nie zawiera dokładnie specyfikacji i ciała jednego pakietu albo typu — zapis zablokowany. Przywróć jednostki albo zapisz okno w innym pliku (Zapisz jako jeden plik…).")
        }
    }
}

extension Document {
    /// Pliki okna: pliki jednostek (para specyfikacja/ciało) albo plik okna.
    public var fileURLs: [URL] {
        if !unitFiles.isEmpty { return unitFiles.map(\.url) }
        return fileURL.map { [$0.standardizedFileURL] } ?? []
    }

    /// Plik karty z kursorem (okno pary), inaczej plik okna — stan Git, porównanie z HEAD.
    public var activeFileURL: URL? {
        guard unitFiles.count == 2, let i = activeUnitTab, let parts = SpecBodyFiles.parts(programUnits, tabs: programUnitTabs),
              let f = unitFiles.first(where: { $0.part == parts[i] }) else { return fileURL }
        return f.url
    }

    /// Indeks karty jednostki zapisywanej w pliku `url` (okno pary; nil — inny plik albo tekst nie jest parą).
    func unitTab(for url: URL) -> Int? {
        let u = url.standardizedFileURL
        guard let f = unitFiles.first(where: { $0.url == u }), let parts = SpecBodyFiles.parts(programUnits, tabs: programUnitTabs) else { return nil }
        return parts.firstIndex(of: f.part)
    }

    /// Bieżąca treść pliku `url` z tekstu okna (także niezapisana) — porównanie z HEAD, użycia; nil — okno nie ma tego pliku.
    public func currentText(of url: URL) -> String? {
        let u = url.standardizedFileURL
        if unitFiles.isEmpty { return fileURL?.standardizedFileURL == u ? text : nil }
        guard let i = unitTab(for: u) else { return unitFiles.contains { $0.url == u } ? text : nil }
        let tabs = programUnitTabs
        guard let parts = SpecBodyFiles.parts(programUnits, tabs: tabs) else { return nil }
        let endings = parts.map { p in unitFiles.first { $0.part == p }?.ending ?? "\n" }
        return SpecBodyFiles.fileTexts(text, tabs: tabs, endings: endings)[i]
    }

    /// Pozycja w tekście okna dla linii i kolumny (od 1) pliku `url` — w oknie pary linia pliku ciała przeliczona na
    /// linię okna.
    public func offset(line: Int, column: Int = 1, inFile url: URL) -> Int {
        var l = line
        if let i = unitTab(for: url) { l = SpecBodyFiles.documentLine(line, tab: i, tabs: programUnitTabs, in: text) }
        return ProgramCompiler.offset(line: l, column: column, in: text)
    }

    /// Ustawia kursor na początku linii nagłówka karty `tab` (otwarcie pliku ciała pokazuje kartę ciała).
    func showUnitTab(_ tab: Int) {
        let tabs = programUnitTabs
        guard tabs.indices.contains(tab), activeUnitTab != tab else { return }
        let ns = text as NSString
        let o = ns.lineRange(for: NSRange(location: min(tabs[tab].sourceOffset, ns.length), length: 0)).location
        selectedRange = o..<o
    }
}

extension Workspace {
    /// Plik pary dla pliku specyfikacji albo ciała (rozszerzenia z Preferencji) — tylko gdy istnieje obok.
    func specBodyPartner(of url: URL) -> (spec: URL, body: URL, part: UnitFile.Part)? {
        guard let p = settings.specBodyExtensions.partner(of: url.pathExtension) else { return nil }
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        // Wielkość liter rozszerzenia jak w otwieranym pliku (EMP_API.PKS ↔ EMP_API.PKB), potem małe litery.
        let upper = url.pathExtension == url.pathExtension.uppercased() && url.pathExtension != url.pathExtension.lowercased()
        let names = upper ? [p.partner.uppercased(), p.partner] : [p.partner, p.partner.uppercased()]
        guard let partner = names.map({ dir.appendingPathComponent(base + "." + $0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })?.standardizedFileURL else { return nil }
        return p.part == .spec ? (url.standardizedFileURL, partner, .spec) : (partner, url.standardizedFileURL, .body)
    }

    /// Otwiera pliki specyfikacji i ciała w jednym oknie programu z kartą `show` (D194). nil — pliki nie są parą jednego
    /// pakietu albo typu (jedna jednostka w każdym) albo podział tekstu okna nie odtwarza ich bez zmian — wtedy plik
    /// otwiera się sam, jak dotąd.
    @discardableResult
    public func openUnitFiles(spec: URL, body: URL, show: UnitFile.Part) throws -> Document? {
        let spec = spec.standardizedFileURL, body = body.standardizedFileURL
        let s = TextFileCodec.decode(try Data(contentsOf: spec), preferred: projectEncoding(for: spec))
        let b = TextFileCodec.decode(try Data(contentsOf: body), preferred: projectEncoding(for: body))
        let text = SpecBodyFiles.join(spec: s.text, body: b.text)
        let units = ProgramCompiler.units(in: text)
        let tabs = ProgramUnitTabs.tabs(units, in: text)
        let endings = [SpecBodyFiles.splitEnding(s.text).ending, SpecBodyFiles.splitEnding(b.text).ending]
        guard SpecBodyFiles.parts(units, tabs: tabs) == [.spec, .body],
              SpecBodyFiles.fileTexts(text, tabs: tabs, endings: endings) == [s.text, b.text] else { return nil }
        if let active = activeDocument, active.fileURL == nil, !active.isModified, active.text.isEmpty, active.kind == .program {
            close(active.id)
        }
        let doc = newDocument(.program, text: text, fileURL: spec)
        doc.fileFormat = s.format
        doc.unitFiles = [UnitFile(part: .spec, url: spec, format: s.format, ending: endings[0], savedText: s.text),
                         UnitFile(part: .body, url: body, format: b.format, ending: endings[1], savedText: b.text)]
        doc.isModified = false
        restoreWindowState(doc)
        doc.showUnitTab(show == .spec ? 0 : 1)
        rememberRecentFile(show == .spec ? spec : body)
        return doc
    }

    /// Typ specyfikacji, gdy okno programu zawiera dokładnie specyfikację i ciało (Zapisz jako tworzy parę plików).
    public func specBodyPairType(_ doc: Document) -> DBObjectType? {
        guard doc.kind == .program else { return nil }
        return SpecBodyFiles.pairType(doc.programUnits, tabs: doc.programUnitTabs)
    }

    /// Pliki pary dla nazwy wybranej w oknie zapisu: ten sam katalog i nazwa bez rozszerzenia, rozszerzenia z Preferencji.
    public func specBodyURLs(for chosen: URL, type: DBObjectType) -> (spec: URL, body: URL)? {
        guard let ext = settings.specBodyExtensions.pair(for: type) else { return nil }
        let dir = chosen.deletingLastPathComponent()
        let base = chosen.pathExtension.isEmpty ? chosen.lastPathComponent : chosen.deletingPathExtension().lastPathComponent
        return (dir.appendingPathComponent(base + "." + ext.spec).standardizedFileURL, dir.appendingPathComponent(base + "." + ext.body).standardizedFileURL)
    }

    /// Zapisz jako… dla okna pary: wiąże okno z nowymi plikami specyfikacji i ciała (format plików — format okna) i zapisuje.
    public func saveUnitFiles(_ doc: Document, spec: URL, body: URL) throws {
        let previous = doc.unitFiles
        let format = doc.fileFormat
        let keep = { (part: UnitFile.Part, url: URL) -> UnitFile in
            // Ten sam plik co dotąd (zapis pod tą samą nazwą) — z jego formatem i zakończeniem.
            if let f = previous.first(where: { $0.part == part && $0.url == url.standardizedFileURL }) { return f }
            return UnitFile(part: part, url: url, format: format)
        }
        doc.unitFiles = [keep(.spec, spec), keep(.body, body)]
        do { try saveUnitFiles(doc) } catch {
            doc.unitFiles = previous
            throw error
        }
    }

    /// Zapis okna pary: każda jednostka do jej pliku, w formacie tego pliku, tylko zmienione (D194). Tekst karty
    /// zapisywany bez zmian — bez dopisywania „/”.
    func saveUnitFiles(_ doc: Document) throws {
        if settings.beautifier.beforeSave { autoBeautify(doc) }
        let units = doc.programUnits, tabs = doc.programUnitTabs
        let spec = doc.unitFiles.first { $0.part == .spec }, body = doc.unitFiles.first { $0.part == .body }
        guard let spec, let body, let parts = SpecBodyFiles.parts(units, tabs: tabs) else {
            throw UnitFilesError.notAPair(spec: spec?.url.lastPathComponent ?? "?", body: body?.url.lastPathComponent ?? "?")
        }
        let files = parts.map { $0 == .spec ? spec : body }
        let texts = SpecBodyFiles.fileTexts(doc.text, tabs: tabs, endings: files.map(\.ending))
        // Najpierw kodowanie obu plików: znak spoza kodowania któregokolwiek blokuje zapis, zanim cokolwiek zapisano.
        var data: [Data] = []
        for (f, t) in zip(files, texts) {
            guard let d = TextFileCodec.encode(t, format: f.format) else {
                let bad = TextFileCodec.firstUnencodable(t, encoding: f.format.encoding)
                throw CommandError.notAvailable(L10n.tr("Plik \(f.url.lastPathComponent): \(TextFileError.unencodable(line: bad?.line ?? 0, column: bad?.column ?? 0, character: bad.map { String($0.character) } ?? "?", encoding: f.format.displayName.components(separatedBy: " ").first ?? "").localizedDescription)"))
            }
            data.append(d)
        }
        var saved = doc.unitFiles
        for (i, f) in files.enumerated() where texts[i] != f.savedText || !FileManager.default.fileExists(atPath: f.url.path) {
            backupBeforeSave(f.url)
            try Self.writeKeepingFile(data[i], to: f.url)
            if let k = saved.firstIndex(where: { $0.part == f.part }) { saved[k].savedText = texts[i] }
        }
        // Historia lokalna okna pary: cały tekst okna pod plikiem specyfikacji (klucz okna — `LocalHistory.key(for:)`).
        localHistory.record(key: LocalHistory.key(file: spec.url), title: spec.url.lastPathComponent, text: doc.text, label: L10n.tr("zapis"))
        doc.unitFiles = saved
        doc.fileURL = spec.url
        doc.fileFormat = spec.format
        doc.isModified = false
        rememberRecentFile(spec.url)
    }
}
