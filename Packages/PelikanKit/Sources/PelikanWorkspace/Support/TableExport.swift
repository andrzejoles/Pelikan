import Foundation
import PelikanDB

/// Kopiowanie i eksport dowolnej tabeli okna (D214): komórki jako tekst pokazany w tabeli, kolumny liczbowe (każda
/// niepusta wartość jest liczbą) jako liczby — w xlsx, JSON i wyrównaniu do prawej.
public enum TableExport {
    /// Formaty eksportu tabel: tekst, CSV, Excel, JSON, XML, HTML i TSV.
    public static let formats: [ExportFormat] = [.text, .csv, .xlsx, .json, .xml, .html, .tsv]

    /// Dane eksportu z nagłówków i tekstu komórek; puste komórki — NULL.
    public static func data(title: String, columns: [String], rows: [[String]]) -> ExportData {
        let numeric = columns.indices.map { i in
            var any = false
            for r in rows where i < r.count && !r[i].isEmpty {
                guard isNumber(r[i]) else { return false }
                any = true
            }
            return any
        }
        let infos = columns.enumerated().map { i, n in
            numeric[i] ? ColumnInfo(name: n, type: .number, typeName: "NUMBER") : ColumnInfo(name: n, type: .varchar2, typeName: "VARCHAR2")
        }
        let values: [[OracleValue]] = rows.map { r in
            columns.indices.map { i in
                let s = i < r.count ? r[i] : ""
                if s.isEmpty { return .null }
                return numeric[i] ? .number(s) : .text(s)
            }
        }
        return ExportData(title: title, columns: infos, rows: values)
    }

    /// Liczba w zapisie z kropką dziesiętną (tak jak liczby w tabelach), bez separatorów tysięcy — i bez straty przy
    /// zapisie jako liczba: bez zer wiodących (kody „0012”) i najwyżej 15 cyfr znaczących (identyfikatory jak DBID,
    /// FORCE_MATCHING_SIGNATURE zostają tekstem — Excel i JSON zaokrągliłyby je).
    static func isNumber(_ s: String) -> Bool {
        guard s.range(of: #"^-?(0|[1-9][0-9]*)?(\.[0-9]*)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { return false }
        // Część przed wykładnikiem musi mieć cyfrę („E1”, „e5” to kody, nie liczby).
        let mantissa = s.prefix { $0 != "e" && $0 != "E" }
        guard mantissa.contains(where: \.isNumber) else { return false }
        let digits = mantissa.filter(\.isNumber).drop { $0 == "0" }
        return digits.count <= 15
    }

    /// Plik eksportu w formacie.
    public static func file(_ format: ExportFormat, _ data: ExportData) -> Data {
        format == .xlsx ? ResultExporter.xlsx([data]) : Data(ResultExporter.text(format, data).utf8)
    }

    /// Tekst do schowka (tabulatory — wkleja się do arkusza i edytora) i HTML z tą samą tabelą.
    public static func clipboard(_ data: ExportData, header: Bool) -> (text: String, html: String) {
        var o = ExportOptions()
        o.includeHeader = header
        return (ResultExporter.text(.tsv, data, options: o), ResultExporter.htmlTable(data, options: o))
    }
}

extension SortKey {
    /// Tekst wartości klucza — gdy kolumna nie podaje tekstu do kopii i eksportu: liczby całkowite bez części
    /// dziesiętnej, daty `YYYY-MM-DD HH24:MI:SS` (bez czasu, gdy północ), pusta wartość — pusty tekst.
    public var text: String {
        switch self {
        case .none: return ""
        case .text(let s): return s
        case .number(let d):
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return String(d)
        case .date(let d):
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            if c.hour == 0, c.minute == 0, c.second == 0 { return day }
            return day + String(format: " %02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        }
    }
}
