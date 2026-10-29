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

    /// Rozszerzenia zajęte przez inne rodzaje plików (skrypty, testy, raporty, diagramy, notatniki, pliki z obiema
    /// jednostkami) — nie mogą być rozszerzeniem specyfikacji ani ciała.
    static let reserved: Set<String> = ["sql", "tst", "rep", "pdd", "sqlnb", "pck", "typ", "txt"]

    /// Rozszerzenie wpisane w Preferencjach: bez kropki i spacji, małymi literami; puste, z innymi znakami niż litery,
    /// cyfry i „_” albo zajęte — nil.
    public static func normalized(_ s: String) -> String? {
        let t = String(s.trimmingCharacters(in: .whitespaces).drop { $0 == "." }).lowercased()
        guard !t.isEmpty, t.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" }), !reserved.contains(t) else { return nil }
        return t
    }

    /// Wpisane rozszerzenia, gdy są poprawne: rozszerzenia specyfikacji różne od rozszerzeń ciała (inaczej zapis ciała
    /// nadpisałby specyfikację, a plik nie wiedziałby, którą częścią jest); pakiet i typ mogą mieć wspólne (`.spc`/`.bdy`).
    private var valid: (ps: String, pb: String, ts: String, tb: String)? {
        let v = [packageSpec, packageBody, typeSpec, typeBody].map { Self.normalized($0) }
        // Wspólne rozszerzenie specyfikacji pakietu i typu wymaga wspólnego rozszerzenia ciała (i odwrotnie) — inaczej plik
        // pary dla `x.spc` byłby niejednoznaczny.
        guard let ps = v[0], let pb = v[1], let ts = v[2], let tb = v[3], Set([ps, ts]).isDisjoint(with: [pb, tb]),
              (ps == ts) == (pb == tb) else { return nil }
        return (ps, pb, ts, tb)
    }

    /// Rozszerzenia w użyciu: wpisane, gdy poprawne, inaczej domyślne.
    private var resolved: (ps: String, pb: String, ts: String, tb: String) {
        let def = SpecBodyExtensions()
        return valid ?? (def.packageSpec, def.packageBody, def.typeSpec, def.typeBody)
    }

    /// Wpisane rozszerzenia są niepoprawne (Preferencje pokazują ostrzeżenie; używane są domyślne).
    public var isInvalid: Bool { valid == nil }

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
        for (s, b) in [(r.ps, r.pb), (r.ts, r.tb)] {
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
    /// Skrót bajtów pliku z ostatniego odczytu albo zapisu (FNV-1a) — wykrywanie zmiany na dysku bez dekodowania
    /// (także po zmianie kodowania okna); nil — nieznany (nowy plik), bez sprawdzania.
    public var savedHash: UInt64?
    /// Plik do zapisania przy następnym Zapisz mimo niezmienionej jednostki (zmiana kodowania — Plik › Kodowanie pliku).
    public var needsRewrite = false

    public init(part: Part, url: URL, format: TextFileFormat = TextFileFormat(), ending: String = "\n", savedText: String = "",
                savedHash: UInt64? = nil) {
        self.part = part; self.url = url.standardizedFileURL; self.format = format; self.ending = ending; self.savedText = savedText
        self.savedHash = savedHash
    }

    /// Skrót bajtów pliku (FNV-1a 64).
    public static func fingerprint(_ data: Data) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return h
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

    /// Pierwszy plik (indeks karty), którego treść nie jest dokładnie jedną jednostką karty — tego samego typu i nazwy;
    /// nil — podział poprawny.
    public static func mismatch(_ texts: [String], units: [ProgramUnit]) -> Int? {
        let expected = units.sorted { $0.range.lowerBound < $1.range.lowerBound }
        return texts.indices.first { i in
            let found = ProgramCompiler.units(in: texts[i])
            // Ten sam tekst jednostki co w oknie — podział w środku polecenia (dwie jednostki w jednej linii) daje inny.
            return !(expected.indices.contains(i) && found.count == 1 && found[0].type == expected[i].type && found[0].name == expected[i].name
                     && found[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == expected[i].text.trimmingCharacters(in: .whitespacesAndNewlines))
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
    case splitMismatch(file: String)

    public var errorDescription: String? {
        switch self {
        case let .notAPair(spec, body):
            L10n.tr("Okno jest powiązane z plikami \(spec) i \(body), ale nie zawiera dokładnie specyfikacji i ciała jednego pakietu albo typu — zapis zablokowany. Przywróć jednostki albo zapisz okno w innym pliku (Zapisz jako jeden plik…).")
        case let .splitMismatch(file):
            L10n.tr("Podział okna na pliki dałby w pliku \(file) inny tekst niż jedna jednostka (np. dwie jednostki w jednej linii) — zapis zablokowany. Rozdziel jednostki w osobnych liniach albo zapisz okno w jednym pliku (Zapisz jako jeden plik…).")
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

    /// Pliki z niezapisaną zmianą: w oknie pary tylko plik, którego jednostka się zmieniła (Przeglądarka plików).
    public var modifiedFileURLs: [URL] {
        guard isModified else { return [] }
        if unitFiles.isEmpty { return fileURLs }
        return unitFiles.filter { f in currentText(of: f.url).map { $0 != f.savedText } ?? true }.map(\.url)
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
        let names = (upper ? [p.partner.uppercased(), p.partner] : [p.partner, p.partner.uppercased()]).map { base + "." + $0 }
        // Rzeczywista nazwa pliku z katalogu: na APFS bez rozróżniania wielkości liter „X.PKB” istnieje także jako
        // „x.pkb” — powiązanie musi mieć nazwę z dysku, inaczej ponowne otwarcie nie trafi w okno pary.
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        guard let name = names.first(where: { listing.contains($0) })
                ?? listing.first(where: { f in names.contains { $0.caseInsensitiveCompare(f) == .orderedSame } }) else { return nil }
        let partner = dir.appendingPathComponent(name).standardizedFileURL
        return p.part == .spec ? (url.standardizedFileURL, partner, .spec) : (partner, url.standardizedFileURL, .body)
    }

    /// Otwiera pliki specyfikacji i ciała w jednym oknie programu z kartą `show` (D194). nil — pliki nie są parą jednego
    /// pakietu albo typu (jedna jednostka w każdym) albo podział tekstu okna nie odtwarza ich bez zmian — wtedy plik
    /// otwiera się sam, jak dotąd.
    @discardableResult
    public func openUnitFiles(spec: URL, body: URL, show: UnitFile.Part) throws -> Document? {
        let spec = spec.standardizedFileURL, body = body.standardizedFileURL
        // Plik nieczytelny (np. brak uprawnień do pliku pary) — bez pary; otwierany plik zgłosi błąd sam.
        guard spec != body, let sd = try? Data(contentsOf: spec), let bd = try? Data(contentsOf: body) else { return nil }
        let s = TextFileCodec.decode(sd, preferred: projectEncoding(for: spec))
        let b = TextFileCodec.decode(bd, preferred: projectEncoding(for: body))
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
        // Jednostki i karty policzone przy sprawdzaniu pary — bez ponownego liczenia przy pierwszym rysowaniu.
        doc.cacheProgramUnits(units, forText: text)
        doc.cacheProgramUnitTabs(tabs, forText: text)
        doc.fileFormat = s.format
        doc.unitFiles = [UnitFile(part: .spec, url: spec, format: s.format, ending: endings[0], savedText: s.text, savedHash: UnitFile.fingerprint(sd)),
                         UnitFile(part: .body, url: body, format: b.format, ending: endings[1], savedText: b.text, savedHash: UnitFile.fingerprint(bd))]
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

    /// Pliki, które Zapisz jako nadpisze, a nie należą do okna (pytanie „Zastąpić?” — raz, z listą). `chosen` — plik
    /// wybrany w oknie zapisu, którego zastąpienie okno zapisu już potwierdziło.
    public func filesToReplace(_ doc: Document, spec: URL, body: URL, chosen: URL) -> [URL] {
        [spec, body].filter {
            Self.pathExists($0) && !doc.fileURLs.contains($0) && $0 != chosen.standardizedFileURL
        }
    }

    /// Zapisz jako… dla okna pary: wiąże okno z nowymi plikami specyfikacji i ciała i zapisuje. Format nowego pliku —
    /// format dotychczasowego pliku tej samej części (okno pary), inaczej format okna. Nieudany zapis usuwa pliki,
    /// które ten zapis utworzył, i przywraca powiązanie.
    public func saveUnitFiles(_ doc: Document, spec: URL, body: URL) throws {
        let spec = spec.standardizedFileURL, body = body.standardizedFileURL
        guard spec != body else { throw UnitFilesError.notAPair(spec: spec.lastPathComponent, body: body.lastPathComponent) }
        let previous = doc.unitFiles
        let format = doc.fileFormat
        let keep = { (part: UnitFile.Part, url: URL) -> UnitFile in
            // Ten sam plik co dotąd (zapis pod tą samą nazwą) — z jego formatem i zakończeniem.
            if let f = previous.first(where: { $0.part == part && $0.url == url }) { return f }
            if let f = previous.first(where: { $0.part == part }) { return UnitFile(part: part, url: url, format: f.format, ending: f.ending) }
            return UnitFile(part: part, url: url, format: format)
        }
        // Bez wiszących dowiązań: usuwamy po nieudanym zapisie tylko pliki, których przed zapisem nie było wcale.
        let created = [spec, body].filter { !Self.pathExists($0) }
        doc.unitFiles = [keep(.spec, spec), keep(.body, body)]
        do { try saveUnitFiles(doc) } catch {
            for u in created { try? FileManager.default.removeItem(at: u) }
            doc.unitFiles = previous
            throw error
        }
    }

    /// Pliki pary, które ten zapis zapisze (jednostka zmieniona w oknie), a które zmieniły się na dysku od otwarcia albo
    /// ostatniego zapisu (inny program, git checkout) — pytanie przed zapisem, żeby nie nadpisać cudzej zmiany. Plik,
    /// którego jednostka w oknie się nie zmieniła, nie jest zapisywany, więc nie pyta (i jego `savedText` zostaje — gdy
    /// jednostka zmieni się później, zapis zapyta wtedy). Porównanie skrótu bajtów z ostatniego odczytu albo zapisu — bez
    /// dekodowania (pliki jednobajtowe bez fałszywych alarmów, sprawdzenie działa też po zmianie kodowania okna).
    public func externallyChangedUnitFiles(_ doc: Document) -> [URL] {
        doc.unitFiles.filter { f in
            guard let hash = f.savedHash, f.needsRewrite || doc.currentText(of: f.url).map({ $0 != f.savedText }) == true,
                  let data = try? Data(contentsOf: f.url) else { return false }
            return UnitFile.fingerprint(data) != hash
        }.map(\.url)
    }

    /// Czy ścieżka istnieje (bez podążania za dowiązaniem — wiszące dowiązanie też istnieje).
    nonisolated static func pathExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Zapis okna pary: każda jednostka do jej pliku, w formacie tego pliku, tylko zmienione (D194). Tekst karty
    /// zapisywany bez zmian — bez dopisywania „/”.
    func saveUnitFiles(_ doc: Document) throws {
        if settings.beautifier.beforeSave { autoBeautify(doc) }
        let units = doc.programUnits, tabs = doc.programUnitTabs
        let spec = doc.unitFiles.first { $0.part == .spec }, body = doc.unitFiles.first { $0.part == .body }
        guard let spec, let body, spec.url != body.url, let parts = SpecBodyFiles.parts(units, tabs: tabs) else {
            throw UnitFilesError.notAPair(spec: spec?.url.lastPathComponent ?? "?", body: body?.url.lastPathComponent ?? "?")
        }
        let files = parts.map { $0 == .spec ? spec : body }
        let texts = SpecBodyFiles.fileTexts(doc.text, tabs: tabs, endings: files.map(\.ending))
        // Siatka bezpieczeństwa: każdy plik to dokładnie jedna jednostka swojej części i tego samego obiektu (np. dwie
        // jednostki w jednej linii dzielą się na karty w środku polecenia — taki podział zepsułby oba pliki).
        if let i = SpecBodyFiles.mismatch(texts, units: units) {
            throw UnitFilesError.splitMismatch(file: files[i].url.lastPathComponent)
        }
        // Najpierw kodowanie obu plików: znak spoza kodowania któregokolwiek blokuje zapis, zanim cokolwiek zapisano.
        var data: [Data] = []
        for (f, t) in zip(files, texts) {
            guard let d = TextFileCodec.encode(t, format: f.format) else {
                let bad = TextFileCodec.firstUnencodable(t, encoding: f.format.encoding)
                throw CommandError.notAvailable(L10n.tr("Plik \(f.url.lastPathComponent): \(TextFileError.unencodable(line: bad?.line ?? 0, column: bad?.column ?? 0, character: bad.map { String($0.character) } ?? "?", encoding: f.format.displayName.components(separatedBy: " ").first ?? "").localizedDescription)"))
            }
            data.append(d)
        }
        for (i, f) in files.enumerated() where texts[i] != f.savedText || f.needsRewrite || !FileManager.default.fileExists(atPath: f.url.path) {
            backupBeforeSave(f.url)
            try Self.writeKeepingFile(data[i], to: f.url)
            // Od razu po zapisie pliku: gdy zapis drugiego się nie uda, następne Zapisz nie uzna pierwszego za
            // niezmieniony z nieaktualną treścią, a zmiana na dysku nie wygląda na cudzą.
            if let k = doc.unitFiles.firstIndex(where: { $0.part == f.part }) {
                doc.unitFiles[k].savedText = texts[i]
                doc.unitFiles[k].savedHash = UnitFile.fingerprint(data[i])
                doc.unitFiles[k].needsRewrite = false
            }
        }
        // Historia lokalna okna pary: cały tekst okna pod plikiem specyfikacji (klucz okna — `LocalHistory.key(for:)`).
        localHistory.record(key: LocalHistory.key(file: spec.url), title: spec.url.lastPathComponent, text: doc.text, label: L10n.tr("zapis"))
        doc.fileURL = spec.url
        doc.fileFormat = spec.format
        doc.isModified = false
        rememberRecentFile(spec.url)
    }
}
