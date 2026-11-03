import Foundation
import PelikanSQL

/// Standard plików z kodem (D210): kodowanie i znacznik BOM nowych plików oraz pliki programów bez linii „/”.
/// Domyślnie UTF-8 bez BOM i bez „/”. Plik otwarty w innym formacie — pytanie o konwersję.
public struct FileStandard: Codable, Sendable, Hashable {
    /// Nazwa kodowania z `TextFileCodec.encodingNames`.
    public var encoding = "UTF-8"
    /// Znacznik BOM na początku pliku (tylko UTF-8).
    public var byteOrderMark = false
    /// Pliki programów (pakiety, typy, procedury, wyzwalacze…) bez linii z samym „/” — „/” należy do skryptów SQL*Plus,
    /// a w pliku z kodem psuje wdrożenie (D192).
    public var slashFreePrograms = true
    /// Pytanie o konwersję przy otwarciu pliku, który odbiega od standardu.
    public var askOnOpen = true

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FileStandard()
        encoding = (try? c.decodeIfPresent(String.self, forKey: .encoding)) ?? d.encoding
        byteOrderMark = (try? c.decodeIfPresent(Bool.self, forKey: .byteOrderMark)) ?? d.byteOrderMark
        slashFreePrograms = (try? c.decodeIfPresent(Bool.self, forKey: .slashFreePrograms)) ?? d.slashFreePrograms
        askOnOpen = (try? c.decodeIfPresent(Bool.self, forKey: .askOnOpen)) ?? d.askOnOpen
    }

    /// Kodowanie standardu (nieznana nazwa — UTF-8).
    public var textEncoding: String.Encoding { TextFileCodec.encoding(named: encoding) ?? .utf8 }

    /// BOM tylko dla UTF-8 — kodowania jednobajtowe nie mają znacznika.
    public var usesBOM: Bool { byteOrderMark && textEncoding == .utf8 }

    /// Format nowego pliku (zakończenia linii LF, jak w edytorze).
    public var newFileFormat: TextFileFormat {
        var f = TextFileFormat()
        f.encoding = textEncoding
        f.hasBOM = usesBOM
        return f
    }
}

/// Odstępstwo pliku od standardu.
public enum FileStandardIssue: Sendable, Hashable {
    /// Kodowanie pliku (nazwa wyświetlana) inne niż w standardzie.
    case encoding(String)
    /// Plik ma BOM, a standard go nie przewiduje (true) albo odwrotnie (false).
    case byteOrderMark(Bool)
    /// Liczba linii z samym „/”.
    case slashLines(Int)

    public var description: String {
        switch self {
        case .encoding(let name): L10n.tr("kodowanie \(name)")
        case .byteOrderMark(true): L10n.tr("znacznik BOM na początku pliku")
        case .byteOrderMark(false): L10n.tr("brak znacznika BOM")
        case .slashLines(let n): L10n.tr("linie z samym „/”: \(n)")
        }
    }
}

/// Linie z samym „/” (terminator SQL*Plus) poza tekstami i komentarzami.
public enum SlashLines {
    /// Zakresy UTF-16 linii z samym „/”, razem ze znakiem nowej linii za nim.
    public static func ranges(in text: String) -> [Range<Int>] {
        let tokens = Lexer(text).tokenize()
        var out: [Range<Int>] = []
        for (k, t) in tokens.enumerated() where t.kind == .slash {
            var j = k - 1
            while j >= 0, tokens[j].kind == .whitespace { j -= 1 }
            guard j < 0 || tokens[j].kind == .newline else { continue }
            let lineStart = j < 0 ? 0 : tokens[j].end
            j = k + 1
            while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
            if j == tokens.count {
                out.append(lineStart..<tokens[j - 1].end)
            } else if tokens[j].kind == .newline {
                out.append(lineStart..<tokens[j].end)
            }
        }
        return out
    }

    /// Tekst bez linii z samym „/”. Ostatnia linia „/” bez nowej linii za nią usuwa też nową linię przed nią
    /// (plik kończy się wtedy tak jak przed „/”).
    public static func removing(from text: String) -> String {
        let found = ranges(in: text)
        guard !found.isEmpty else { return text }
        let ns = NSMutableString(string: text)
        for r in found.reversed() {
            var range = NSRange(location: r.lowerBound, length: r.count)
            if r.upperBound == ns.length, r.lowerBound > 0, ns.character(at: r.lowerBound - 1) == 0x0A,
               !ns.substring(with: range).hasSuffix("\n") {
                range = NSRange(location: r.lowerBound - 1, length: r.count + 1)
            }
            ns.deleteCharacters(in: range)
        }
        return ns as String
    }
}

extension Workspace {
    /// Odstępstwa okna od standardu plików. Dotyczy też plików projektu z ustawionym kodowaniem (np. źródeł Pro*C,
    /// D213) — kodowanie projektu mówi, jak plik czytać, a standard — jak go zapisać.
    public func fileStandardIssues(_ doc: Document) -> [FileStandardIssue] {
        guard [.sql, .program].contains(doc.kind) else { return [] }
        let std = settings.fileStandard
        let formats: [(format: TextFileFormat, url: URL?)] = doc.unitFiles.isEmpty
            ? [(doc.fileFormat, doc.fileURL)] : doc.unitFiles.map { ($0.format, $0.url) }
        var issues: [FileStandardIssue] = []
        for (f, _) in formats {
            if f.encoding != std.textEncoding {
                let name = f.displayName.components(separatedBy: " · ").first.map { $0.replacingOccurrences(of: " BOM", with: "") } ?? ""
                if !issues.contains(.encoding(name)) { issues.append(.encoding(name)) }
            } else if f.encoding == .utf8, f.hasBOM != std.usesBOM, !issues.contains(.byteOrderMark(f.hasBOM)) {
                issues.append(.byteOrderMark(f.hasBOM))
            }
        }
        if doc.kind == .program, std.slashFreePrograms {
            let n = SlashLines.ranges(in: doc.text).count
            if n > 0 { issues.append(.slashLines(n)) }
        }
        return issues
    }

    /// Konwersja okna do standardu: kodowanie i BOM zapisu (także obu plików okna pary) i usunięcie linii „/” z pliku
    /// programu. Zmienia okno, nie plik — zapis jak po każdej edycji (⌘S). Tekst okna jest już odczytany w kodowaniu
    /// pliku (`TextFileCodec.decode`), więc zapis w UTF-8 zachowuje każdą literę.
    public func conformToFileStandard(_ doc: Document) {
        let std = settings.fileStandard
        func apply(_ f: inout TextFileFormat) {
            f.encoding = std.textEncoding
            f.hasBOM = f.encoding == .utf8 && std.usesBOM
        }
        apply(&doc.fileFormat)
        for i in doc.unitFiles.indices {
            apply(&doc.unitFiles[i].format)
            doc.unitFiles[i].needsRewrite = true
        }
        if doc.kind == .program, std.slashFreePrograms {
            let t = SlashLines.removing(from: doc.text)
            if t != doc.text {
                let caret = min(doc.selectedRange.lowerBound, (t as NSString).length)
                doc.text = t
                doc.selectedRange = caret..<caret
            }
        }
        doc.isModified = true
    }

    /// Pytanie o konwersję otwartego pliku do standardu (po kolei, gdy otwiera się kilka plików). Bez pytania przy
    /// przywracaniu workseta i pulpitu projektu, bez interfejsu i gdy pytanie jest wyłączone w Ustawieniach.
    func checkFileStandard(_ doc: Document) {
        guard fileStandardChecksSuspended == 0, settings.fileStandard.askOnOpen, ui != nil, !fileStandardIssues(doc).isEmpty else { return }
        fileStandardQueue.append(doc.id)
        guard !fileStandardAsking else { return }
        fileStandardAsking = true
        Task { @MainActor in
            while !fileStandardQueue.isEmpty {
                let id = fileStandardQueue.removeFirst()
                guard let d = documents.first(where: { $0.id == id }), d.fileURL != nil else { continue }
                let issues = fileStandardIssues(d)
                guard !issues.isEmpty else { continue }
                let std = settings.fileStandard
                let target = std.encoding + (std.usesBOM ? L10n.tr(" z BOM") : L10n.tr(" bez BOM"))
                    + (d.kind == .program && std.slashFreePrograms ? L10n.tr(", bez linii „/”") : "")
                let message = L10n.tr("Odbiega od standardu plików: \(issues.map(\.description).joined(separator: "; ")). Po konwersji okno zostanie zapisane jako \(target) przy następnym zapisie (Ustawienia › Ogólne › Standard plików).")
                let answer = await askSuppressible(.convertFileStandard, title: L10n.tr("Przekonwertować „\(d.title)” do standardu plików?"),
                                                   message: message, buttons: [L10n.tr("Konwertuj"), L10n.tr("Zostaw bez zmian")])
                // Okno mogło zostać zamknięte w trakcie pytania.
                if answer == 0, documents.contains(where: { $0.id == id }) { conformToFileStandard(d) }
            }
            fileStandardAsking = false
        }
    }

    /// Otwieranie plików bez pytań o standard (przywracanie workseta, pulpitu projektu).
    public func withoutFileStandardChecks<T>(_ body: () throws -> T) rethrows -> T {
        fileStandardChecksSuspended += 1
        defer { fileStandardChecksSuspended -= 1 }
        return try body()
    }
}
