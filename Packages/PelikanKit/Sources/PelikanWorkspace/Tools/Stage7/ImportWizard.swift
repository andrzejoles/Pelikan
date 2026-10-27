import Foundation
import PelikanDB
import PelikanSQL

/// Stan kreatora importu danych (SD-IMP-001): źródło (CSV/rozdzielany, stała szerokość, XLSX), kodowanie, nagłówek,
/// cel (nowa albo istniejąca tabela), mapowanie i opcje. Zapisywany jako profil do ponownego użycia.
public struct ImportWizardState: Sendable, Codable, Hashable {
    public enum SourceKind: String, Sendable, Codable, CaseIterable { case delimited, fixedWidth, excel }
    public var source: SourceKind = .delimited
    public var text = TextFormat()
    /// Kodowanie pliku tekstowego: „auto” albo nazwa (UTF-8, ISO-8859-2, Windows-1250, Windows-1252, UTF-16).
    public var encoding = "auto"
    /// Stała szerokość: pozycje początku kolumn (od 0, rosnąco).
    public var fixedStarts: [Int] = []
    /// Arkusz XLSX (od 0).
    public var sheet = 0
    /// Nagłówek w pierwszym wierszu (stała szerokość, XLSX; dla rozdzielanego — `text.header`).
    public var header = true
    public var owner = ""
    public var table = ""
    public var createTable = false
    public var mappings: [FieldMapping] = []
    public var clear: ImportTarget.Clear = .none
    public var duplicates: ImportTarget.Duplicates = .error
    public var commitEvery = 1000
    public init() {}

    public var target: ImportTarget {
        var t = ImportTarget(owner: ResultExporter.dictionaryName(owner), table: ResultExporter.dictionaryName(table), mappings: mappings)
        t.clear = clear
        t.duplicates = duplicates
        t.commitEvery = commitEvery
        t.excelSerialDates = source == .excel
        return t
    }
}

/// Dane wejściowe po odczycie: nazwy pól i wiersze tekstowe.
public struct ImportSourceData: Sendable, Hashable {
    public var fieldNames: [String]
    public var rows: [[String]]
    public var encoding: String
}

public enum ImportWizard {
    public static let encodings = ["auto", "UTF-8", "UTF-16", "ISO-8859-2", "Windows-1250", "Windows-1252"]

    static func encoding(_ name: String) -> String.Encoding? {
        switch name.uppercased() {
        case "UTF-16": .utf16
        case "WINDOWS-1252", "CP1252": .windowsCP1252
        case "UTF-8", "UTF8": .utf8
        case "ISO-8859-2", "LATIN2": .isoLatin2
        case "WINDOWS-1250", "CP1250": .windowsCP1250
        default: nil
        }
    }

    static func encodingName(_ e: String.Encoding) -> String {
        switch e {
        case .utf8: "UTF-8"
        case .utf16, .utf16LittleEndian, .utf16BigEndian: "UTF-16"
        case .isoLatin2: "ISO-8859-2"
        case .windowsCP1250: "Windows-1250"
        case .windowsCP1252: "Windows-1252"
        default: "ISO-8859-1"
        }
    }

    /// Tekst pliku w wybranym kodowaniu (auto — BOM, UTF-8, potem jak w edytorze: Windows-1250/ISO-8859-2).
    public static func decode(_ data: Data, encoding name: String) -> (text: String, encoding: String) {
        if name != "auto", let e = encoding(name) {
            var d = data
            if e == .utf8, d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
            if let s = String(data: d, encoding: e) { return (s, name) }
        }
        let (text, format) = TextFileCodec.decode(data)
        return (text, encodingName(format.encoding))
    }

    /// Propozycja ustawień dla pliku (rodzaj po rozszerzeniu, separator i nagłówek z treści).
    public static func suggest(fileName: String, data: Data) -> ImportWizardState {
        var s = ImportWizardState()
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "xlsx" { s.source = .excel; return s }
        let (text, _) = decode(data, encoding: "auto")
        s.text = TextImport.detect(text)
        if ext == "txt" || ext == "dat" || ext == "prn", s.text.delimiter == ",", !text.prefix(2000).contains(",") {
            s.source = .fixedWidth
            s.fixedStarts = guessFixedStarts(text)
        }
        let base = ((fileName as NSString).lastPathComponent as NSString).deletingPathExtension
        s.table = TextImport.fieldName(base, index: 0)
        return s
    }

    /// Kolumny stałej szerokości: początki pól po kolumnach spacji wspólnych dla pierwszych linii.
    public static func guessFixedStarts(_ text: String, sample: Int = 50) -> [Int] {
        let lines = text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\r", with: "") }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(sample)
        guard let width = lines.map(\.count).max(), width > 0 else { return [0] }
        var blank = Array(repeating: true, count: width)
        for l in lines {
            for (i, ch) in l.enumerated() where ch != " " { blank[i] = false }
        }
        var starts: [Int] = []
        for i in 0..<width where !blank[i] && (i == 0 || blank[i - 1]) { starts.append(i) }
        return starts.isEmpty ? [0] : starts
    }

    /// Podział linii stałej szerokości na pola (przycięte).
    public static func splitFixed(_ line: String, starts: [Int]) -> [String] {
        let chars = Array(line)
        return starts.enumerated().map { i, s in
            let e = i + 1 < starts.count ? starts[i + 1] : chars.count
            guard s < chars.count else { return "" }
            return String(chars[s..<min(e, chars.count)]).trimmingCharacters(in: .whitespaces)
        }
    }

    /// Odczyt pliku według stanu kreatora.
    public static func read(_ data: Data, state: ImportWizardState) throws -> ImportSourceData {
        switch state.source {
        case .excel:
            let wb = try XlsxWorkbook(data)
            guard wb.sheets.indices.contains(state.sheet) else { throw CommandError.notAvailable(L10n.tr("Brak arkusza \(state.sheet + 1)")) }
            var rows = try wb.rows(sheet: state.sheet).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
            let names = state.header && !rows.isEmpty ? rows.removeFirst() : (rows.first ?? []).indices.map { "COL\($0 + 1)" }
            return ImportSourceData(fieldNames: names, rows: rows, encoding: "XLSX")
        case .fixedWidth:
            let (text, enc) = decode(data, encoding: state.encoding)
            var lines = text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\r", with: "") }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let starts = state.fixedStarts.isEmpty ? guessFixedStarts(text) : state.fixedStarts.sorted()
            let names = state.header && !lines.isEmpty ? splitFixed(lines.removeFirst(), starts: starts) : starts.indices.map { "COL\($0 + 1)" }
            return ImportSourceData(fieldNames: names, rows: lines.map { splitFixed($0, starts: starts) }, encoding: enc)
        case .delimited:
            let (text, enc) = decode(data, encoding: state.encoding)
            let (header, rows) = TextImport.parse(text, state.text)
            let names = header.isEmpty ? (rows.first ?? []).indices.map { "COL\($0 + 1)" } : header
            return ImportSourceData(fieldNames: names, rows: rows, encoding: enc)
        }
    }

    /// Mapowanie: dla nowej tabeli z typów wykrytych w danych, dla istniejącej — po nazwach kolumn.
    public static func prepareMappings(_ state: inout ImportWizardState, data: ImportSourceData, in s: (any DatabaseSession)?) async throws {
        if state.createTable || s == nil {
            state.mappings = TextImport.createTable(owner: ResultExporter.dictionaryName(state.owner), table: ResultExporter.dictionaryName(state.table),
                                                    fieldNames: data.fieldNames, rows: data.rows).mappings
        } else if let s {
            state.mappings = try await TextImport.defaultMappings(owner: ResultExporter.dictionaryName(state.owner), table: ResultExporter.dictionaryName(state.table),
                                                                 fieldNames: data.fieldNames, in: s)
        }
    }

    /// Polecenia DDL nowej tabeli (z typów mapowania) — podgląd przed importem.
    public static func createTableSQL(_ state: ImportWizardState, data: ImportSourceData) -> String {
        TextImport.createTable(owner: ResultExporter.dictionaryName(state.owner), table: ResultExporter.dictionaryName(state.table),
                               fieldNames: data.fieldNames, rows: data.rows).sql
    }

    /// Import: utworzenie tabeli (gdy nowa), wstawienie wierszy; COMMIT według opcji celu.
    public static func execute(_ state: ImportWizardState, data: ImportSourceData, in s: any DatabaseSession,
                               progress: (@MainActor (Int) -> Void)? = nil) async throws -> ImportResult {
        guard !state.table.isEmpty, !state.owner.isEmpty else { throw CommandError.notAvailable(L10n.tr("Wskaż schemat i tabelę docelową")) }
        if state.createTable { _ = try await s.execute(createTableSQL(state, data: data)) }
        // COMMIT co n wierszy i na końcu wykonuje TextImport.run.
        return try await TextImport.run(data.rows, fieldNames: data.fieldNames, target: state.target, in: s, progress: progress)
    }
}

/// Profile kreatora importu w katalogu danych (`ImportProfiles/*.json`).
public enum ImportProfileStore {
    static func directory(_ base: URL?) -> URL? { base?.appendingPathComponent("ImportProfiles", isDirectory: true) }

    public static func names(in base: URL?) -> [String] {
        guard let d = directory(base), let files = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    public static func save(_ s: ImportWizardState, name: String, in base: URL?) throws {
        guard let d = directory(base) else { return }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(s).write(to: d.appendingPathComponent(safe(name) + ".json"), options: .atomic)
    }

    public static func load(_ name: String, in base: URL?) throws -> ImportWizardState {
        guard let d = directory(base) else { throw CommandError.notAvailable(L10n.tr("Brak katalogu danych")) }
        return try JSONDecoder().decode(ImportWizardState.self, from: Data(contentsOf: d.appendingPathComponent(safe(name) + ".json")))
    }

    static func safe(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " ? $0 : "_" })
    }
}
