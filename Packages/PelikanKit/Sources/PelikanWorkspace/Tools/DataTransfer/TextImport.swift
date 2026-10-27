import Foundation
import PelikanDB
import PelikanSQL

/// Format pliku tekstowego (UG 24.7): separator, cudzysłów, nagłówek, komentarze, zakres linii.
public struct TextFormat: Sendable, Codable, Hashable {
    /// Separator pól („,”, „;”, tabulator, „|”).
    public var delimiter: String = ","
    /// Znak cudzysłowu (pusty — bez).
    public var quote: String = "\""
    /// Pierwsza linia zawiera nazwy pól.
    public var header = true
    public var skipEmptyLines = true
    /// Linie zaczynające się od tego tekstu są pomijane (pusty — brak).
    public var commentPrefix = ""
    /// Pierwsza i ostatnia linia danych (od 1, po nagłówku; 0 — bez ograniczenia).
    public var firstLine = 0
    public var lastLine = 0

    public init() {}
}

/// Typ pola importu i sposób konwersji.
public enum ImportFieldType: String, Sendable, Codable, CaseIterable { case string, number, date }

/// Przypisanie pola pliku do kolumny tabeli (UG 24.7): typ, format daty i funkcja SQL z `#` (np. `upper(#)`).
public struct FieldMapping: Sendable, Codable, Hashable, Identifiable {
    public var column: String
    /// Indeks pola w pliku (nil — kolumna pominięta).
    public var field: Int?
    public var type: ImportFieldType = .string
    public var dateFormat = "YYYY-MM-DD HH24:MI:SS"
    public var function = ""
    public var id: String { column }

    public init(column: String, field: Int?, type: ImportFieldType = .string, dateFormat: String = "YYYY-MM-DD HH24:MI:SS", function: String = "") {
        self.column = column; self.field = field; self.type = type; self.dateFormat = dateFormat; self.function = function
    }
}

/// Cel importu: tabela, mapowanie, czyszczenie, duplikaty, filtr SQL z `:pole`, Commit co n wierszy.
public struct ImportTarget: Sendable, Codable, Hashable {
    public enum Clear: String, Sendable, Codable, CaseIterable { case none, delete, truncate }
    public enum Duplicates: String, Sendable, Codable, CaseIterable { case error, ignore, overwrite }
    public var owner: String
    public var table: String
    public var mappings: [FieldMapping]
    public var clear: Clear = .none
    public var duplicates: Duplicates = .error
    /// Warunek SQL (bez WHERE) z odwołaniami `:NAZWA_POLA` — wiersz importowany, gdy spełniony.
    public var filter = ""
    public var commitEvery = 1000

    public init(owner: String, table: String, mappings: [FieldMapping]) {
        self.owner = owner; self.table = table; self.mappings = mappings
    }
}

public struct ImportResult: Sendable, Equatable {
    public var inserted = 0
    public var updated = 0
    public var deleted = 0
    public var skipped = 0
    public var errors: [String] = []
}

/// Text Importer i Excel Importer (PD-TOOL-008, PD-TOOL-009): wspólne mapowanie i import do tabeli albo skryptu.
public enum TextImport {
    /// Tekst z danych: BOM UTF-8/UTF-16, poprawne UTF-8, potem Windows-1250/ISO-8859-2 (polskie pliki z Excela) —
    /// reguły wspólne z plikami skryptów (`TextFileCodec`).
    public static func decode(_ data: Data) -> (text: String, encoding: String.Encoding) {
        let (text, format) = TextFileCodec.decode(data)
        return (text, format.encoding)
    }

    /// Wykrycie formatu z pierwszych linii: separator o stałej, największej liczbie wystąpień poza cudzysłowami;
    /// nagłówek, gdy pierwszy wiersz nie zawiera liczb, a kolejne tak, albo wszystkie jego pola są różnymi nazwami.
    public static func detect(_ text: String) -> TextFormat {
        var f = TextFormat()
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(100)
        var best: (String, Int) = (",", 0)
        for d in [",", ";", "\t", "|"] {
            var probe = f
            probe.delimiter = d
            probe.header = false
            let counts = lines.map { parseLine($0, probe).count }
            guard let first = counts.first, first > 1 else { continue }
            let consistent = counts.filter { $0 == first }.count
            let score = consistent * first
            if score > best.1 { best = (d, score) }
        }
        f.delimiter = best.0
        f.header = false
        let rows = lines.map { parseLine($0, f) }
        if rows.count >= 2 {
            let isNumber = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) != nil }
            let firstHasNumbers = rows[0].contains(where: isNumber)
            let restHasNumbers = rows.dropFirst().contains { $0.contains(where: isNumber) }
            let distinctNames = Set(rows[0]).count == rows[0].count && rows[0].allSatisfy { !$0.isEmpty && $0.first?.isLetter == true }
            f.header = (!firstHasNumbers && restHasNumbers) || (distinctNames && !firstHasNumbers && rows[0] != rows[1])
        }
        return f
    }

    /// Pola jednej linii (cudzysłów podwojony wewnątrz pola = znak cudzysłowu).
    static func parseLine(_ line: String, _ f: TextFormat) -> [String] {
        parse(line, f).rows.first ?? []
    }

    /// Nazwy pól i wiersze danych (pola w cudzysłowach mogą zawierać separator i nowe linie).
    /// Wiersze arkusza Excela jako nagłówek i dane: `headerLine` (od 1; 0 — bez nagłówka, nazwy POLEn),
    /// `lastLine` (0 — do końca arkusza). Puste nazwy w nagłówku — POLEn.
    public static func sheetTable(_ all: [[String]], headerLine: Int, lastLine: Int) -> (header: [String], rows: [[String]]) {
        var all = all
        if lastLine > 0, lastLine < all.count { all = Array(all.prefix(lastLine)) }
        if headerLine > 0, headerLine <= all.count {
            return (all[headerLine - 1].enumerated().map { $1.isEmpty ? "POLE\($0 + 1)" : $1 }, Array(all.dropFirst(headerLine)))
        }
        return ((0..<(all.map(\.count).max() ?? 0)).map { "POLE\($0 + 1)" }, all)
    }

    public static func parse(_ text: String, _ f: TextFormat) -> (header: [String], rows: [[String]]) {
        // Separator wieloznakowy (pole tekstowe kreatora) — liczy się pierwszy znak.
        let delim = f.delimiter.first ?? ","
        let quote = f.quote.first
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        // „\r\n” to w Swifcie jeden znak (klaster grafemów) — osobny przypadek końca wiersza niżej.
        var chars = Array(text)
        if chars.last != "\n", chars.last != "\r\n", chars.last != "\r" { chars.append("\n") }
        var i = 0
        func endRow() {
            row.append(field)
            field = ""
            let empty = row.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            let comment = !f.commentPrefix.isEmpty && (row.first ?? "").hasPrefix(f.commentPrefix)
            if !(f.skipEmptyLines && empty), !comment { rows.append(row) }
            row = []
        }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == quote {
                    if i + 1 < chars.count, chars[i + 1] == quote { field.append(c); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == quote, field.isEmpty {
                inQuotes = true
            } else if c == delim {
                row.append(field)
                field = ""
            } else if c == "\r" {
                // CR LF albo samo CR — koniec wiersza.
                if i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                endRow()
            } else if c == "\n" || c == "\r\n" {
                endRow()
            } else {
                field.append(c)
            }
            i += 1
        }
        var header: [String] = []
        if f.header, !rows.isEmpty { header = rows.removeFirst() }
        if f.firstLine > 0 || f.lastLine > 0 {
            let lo = max(0, f.firstLine - 1)
            let hi = f.lastLine > 0 ? min(rows.count, f.lastLine) : rows.count
            rows = lo < hi ? Array(rows[lo..<hi]) : []
        }
        let width = max(header.count, rows.map(\.count).max() ?? 0)
        if header.count < width { header += (header.count..<width).map { "POLE\($0 + 1)" } }
        return (header, rows)
    }

    /// Nazwa kolumny z nagłówka pola: litery, cyfry, `_`, wielkie litery (inaczej `POLEn`).
    static func fieldName(_ header: String, index: Int) -> String {
        let s = header.uppercased().map { $0.isLetter || $0.isNumber || $0 == "_" ? String($0) : "_" }.joined()
        guard let f = s.first, f.isLetter, s.count <= 30 else { return "POLE\(index + 1)" }
        return s
    }

    /// Nazwa zmiennej wiązanej pola (dla filtra `:NAZWA`): jak nazwa kolumny, słowa zastrzeżone (DATE, LEVEL, SIZE…)
    /// z przyrostkiem `_` — inaczej ORA-01745.
    public static func bindName(_ header: String, index: Int) -> String {
        let s = fieldName(header, index: index)
        return Keywords.reserved.contains(s) ? s + "_" : s
    }

    /// Wartość pola przygotowana do wiązania: liczba z kropką dziesiętną bez spacji; data z liczby Excela
    /// (dni od 1899-12-30) zamieniana na `YYYY-MM-DD HH24:MI:SS`.
    static func prepared(_ value: String, _ m: FieldMapping) -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        switch m.type {
        case .string: return value
        case .number: return v.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: ",", with: ".")
        case .date:
            if let serial = Double(v), v.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil, serial > 0, serial < 2_958_466 {
                let seconds = (serial * 86_400).rounded()
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "UTC")!
                let base = cal.date(from: DateComponents(year: 1899, month: 12, day: 30))!
                let d = base.addingTimeInterval(seconds)
                let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
                return String(format: "%04d-%02d-%02d %02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
            }
            return v
        }
    }

    /// Format daty dla wartości przygotowanej z liczby Excela.
    static func dateFormat(_ value: String, _ m: FieldMapping) -> String {
        value.trimmingCharacters(in: .whitespaces).range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil ? "YYYY-MM-DD HH24:MI:SS" : m.dateFormat
    }

    /// Wyrażenie SQL kolumny: konwersja typu, potem funkcja z `#`.
    static func expression(_ m: FieldMapping, bind: String, dateFormat: String) -> String {
        let base: String = switch m.type {
        case .string: ":\(bind)"
        // Liczba wiązana jako NUMBER (tekst z kropką dziesiętną) — bez zależności od NLS sesji.
        case .number: ":\(bind)"
        case .date: "TO_DATE(:\(bind), '\(dateFormat.replacingOccurrences(of: "'", with: "''"))')"
        }
        let f = m.function.trimmingCharacters(in: .whitespaces)
        return f.contains("#") ? f.replacingOccurrences(of: "#", with: base) : base
    }

    static func q(_ s: String) -> String { ResultExporter.identifier(s.uppercased()) }

    /// Blok PL/SQL importu jednego wiersza: INSERT … SELECT … FROM dual WHERE filtr; duplikaty klucza pomijane albo
    /// nadpisywane (UPDATE po kluczu głównym); `:n_` — liczba wstawionych (1/0), `:u_` — zaktualizowanych.
    public static func rowStatement(_ t: ImportTarget, fieldNames: [String], keyColumns: [String], dateFormats: [String: String] = [:]) -> String {
        let used = t.mappings.filter { $0.field != nil }
        let table = "\(q(t.owner)).\(q(t.table))"
        let exprs = used.map { expression($0, bind: bindName(fieldNames[$0.field!], index: $0.field!), dateFormat: dateFormats[$0.column] ?? $0.dateFormat) }
        let cols = used.map { q($0.column) }
        let filter = t.filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let insert = "insert into \(table) (\(cols.joined(separator: ", "))) select \(exprs.joined(separator: ", ")) from dual\(filter.isEmpty ? "" : " where \(filter)")"
        var handler = ""
        switch t.duplicates {
        case .error: break
        case .ignore: handler = " exception when dup_val_on_index then :n_ := 0;"
        case .overwrite:
            let keys = Set(keyColumns.map { $0.uppercased() })
            let sets = zip(used, exprs).filter { !keys.contains($0.0.column.uppercased()) }.map { "\(q($0.0.column)) = \($0.1)" }
            let wheres = zip(used, exprs).filter { keys.contains($0.0.column.uppercased()) }.map { "\(q($0.0.column)) = \($0.1)" }
            if !sets.isEmpty, !wheres.isEmpty {
                handler = " exception when dup_val_on_index then :n_ := 0; update \(table) set \(sets.joined(separator: ", ")) where \(wheres.joined(separator: " and ")); :u_ := sql%rowcount;"
            } else {
                handler = " exception when dup_val_on_index then :n_ := 0;"
            }
        }
        return "begin :u_ := 0; \(insert); :n_ := sql%rowcount;\(handler) end;"
    }

    /// Kolumny klucza głównego tabeli.
    public static func primaryKey(owner: String, table: String, in s: any DatabaseSession) async throws -> [String] {
        let (_, rows) = try await s.queryAll("""
            select cc.column_name from all_constraints c join all_cons_columns cc on cc.owner = c.owner and cc.constraint_name = c.constraint_name
             where c.owner = :o and c.table_name = :t and c.constraint_type = 'P' order by cc.position
            """, binds: [BindVariable(name: "o", value: .text(owner.uppercased())), BindVariable(name: "t", value: .text(table.uppercased()))])
        return rows.compactMap { $0.first?.displayText }
    }

    /// Kolumny tabeli z typami — domyślne mapowanie po nazwie (bez względu na wielkość liter) albo po kolejności.
    public static func defaultMappings(owner: String, table: String, fieldNames: [String], in s: any DatabaseSession) async throws -> [FieldMapping] {
        let (_, rows) = try await s.queryAll("select column_name, data_type from all_tab_columns where owner = :o and table_name = :t order by column_id",
                                             binds: [BindVariable(name: "o", value: .text(owner.uppercased())), BindVariable(name: "t", value: .text(table.uppercased()))])
        let upper = fieldNames.map { $0.uppercased().trimmingCharacters(in: .whitespaces) }
        return rows.enumerated().map { i, r in
            let col = r[0].displayText ?? ""
            let type = r[1].displayText ?? ""
            let field = upper.firstIndex(of: col) ?? (upper.allSatisfy { $0.hasPrefix("POLE") } && i < fieldNames.count ? i : nil)
            let t: ImportFieldType = type.contains("DATE") || type.hasPrefix("TIMESTAMP") ? .date : ["NUMBER", "FLOAT", "BINARY_DOUBLE", "BINARY_FLOAT", "INTEGER"].contains(type) ? .number : .string
            return FieldMapping(column: col, field: field, type: t)
        }
    }

    /// Import wierszy w sesji (osobnej od okien): czyszczenie tabeli, wiersz po wierszu z filtrem i obsługą duplikatów,
    /// COMMIT co n wierszy i na końcu. Błędne wiersze trafiają do raportu (numer wiersza danych od 1).
    public static func run(_ rows: [[String]], fieldNames: [String], target t: ImportTarget, in s: any DatabaseSession,
                           progress: (@MainActor (Int) -> Void)? = nil) async throws -> ImportResult {
        let keys = t.duplicates == .overwrite ? try await primaryKey(owner: t.owner, table: t.table, in: s) : []
        switch t.clear {
        case .none: break
        case .delete: _ = try await s.execute("delete from \(q(t.owner)).\(q(t.table))")
        case .truncate: _ = try await s.execute("truncate table \(q(t.owner)).\(q(t.table))")
        }
        var result = ImportResult()
        let used = t.mappings.filter { $0.field != nil }
        let filterBinds = Set(Lexer(t.filter).tokenize().filter { $0.kind == .bindVariable }.map {
            (t.filter as NSString).substring(with: NSRange(location: $0.start + 1, length: $0.length - 1)).uppercased()
        })
        for (i, row) in rows.enumerated() {
            var formats: [String: String] = [:]
            for m in used where m.type == .date { formats[m.column] = dateFormat(row.indices.contains(m.field!) ? row[m.field!] : "", m) }
            let sql = rowStatement(t, fieldNames: fieldNames, keyColumns: keys, dateFormats: formats)
            var binds: [String: BindVariable] = [:]
            for m in used {
                let name = bindName(fieldNames[m.field!], index: m.field!)
                let raw = row.indices.contains(m.field!) ? row[m.field!] : ""
                let v = prepared(raw, m)
                binds[name] = m.type == .number
                    ? BindVariable(name: name, type: .number, value: v.isEmpty ? .null : .number(v))
                    : BindVariable(name: name, value: v.isEmpty ? .null : .text(v))
            }
            for (fi, fname) in fieldNames.enumerated() {
                let name = bindName(fname, index: fi)
                if filterBinds.contains(name), binds[name] == nil {
                    // Pole tylko w filtrze: liczba (także z przecinkiem dziesiętnym) wiązana jako NUMBER, reszta jako tekst.
                    let v = row.indices.contains(fi) ? row[fi] : ""
                    let n = prepared(v, FieldMapping(column: "", field: fi, type: .number))
                    binds[name] = v.isEmpty ? BindVariable(name: name, value: .null)
                        : Double(n) != nil ? BindVariable(name: name, type: .number, value: .number(n)) : BindVariable(name: name, value: .text(v))
                }
            }
            binds["n_"] = BindVariable(name: "n_", type: .number, direction: .output)
            binds["u_"] = BindVariable(name: "u_", type: .number, direction: .output)
            do {
                let r = try await s.execute(sql, binds: Array(binds.values))
                let n = Int(r.outBinds["n_"]?.displayText ?? r.outBinds["N_"]?.displayText ?? "0") ?? 0
                let u = Int(r.outBinds["u_"]?.displayText ?? r.outBinds["U_"]?.displayText ?? "0") ?? 0
                result.inserted += n
                result.updated += u
                if n == 0, u == 0 { result.skipped += 1 }
            } catch {
                result.errors.append(L10n.tr("Wiersz \(i + 1): \(error.localizedDescription)"))
                if result.errors.count > 1000 { break }
            }
            if t.commitEvery > 0, (i + 1) % t.commitEvery == 0 { try await s.commit() }
            if i % 100 == 0 { await progress?(i + 1) }
        }
        try await s.commit()
        return result
    }

    /// „Import to Script”: polecenia INSERT z literałami zamiast zmiennych (wiersze i filtr jak przy imporcie).
    public static func script(_ rows: [[String]], fieldNames: [String], target t: ImportTarget) -> String {
        let used = t.mappings.filter { $0.field != nil }
        let table = "\(q(t.owner)).\(q(t.table))"
        var out = "-- " + L10n.tr("Import do \(t.owner).\(t.table) — wygenerowane przez Pelikana") + "\n"
        switch t.clear {
        case .none: break
        case .delete: out += "delete from \(table);\n"
        case .truncate: out += "truncate table \(table);\n"
        }
        for (i, row) in rows.enumerated() {
            func lit(_ fi: Int, _ m: FieldMapping?) -> String {
                let raw = row.indices.contains(fi) ? row[fi] : ""
                let v = m.map { prepared(raw, $0) } ?? raw
                if v.isEmpty { return "NULL" }
                if m?.type == .number, Double(v) != nil { return v }
                return ResultExporter.quote(v)
            }
            var exprs: [String] = []
            for m in used {
                let df = m.type == .date ? dateFormat(row.indices.contains(m.field!) ? row[m.field!] : "", m) : m.dateFormat
                let e = expression(m, bind: "X_", dateFormat: df)
                exprs.append(e.replacingOccurrences(of: ":X_", with: lit(m.field!, m)))
            }
            var filter = t.filter.trimmingCharacters(in: .whitespacesAndNewlines)
            for (fi, fname) in fieldNames.enumerated() {
                filter = filter.replacingOccurrences(of: ":\(bindName(fname, index: fi))", with: lit(fi, nil), options: .caseInsensitive)
            }
            out += "insert into \(table) (\(used.map { q($0.column) }.joined(separator: ", "))) select \(exprs.joined(separator: ", ")) from dual\(filter.isEmpty ? "" : " where \(filter)");\n"
            if t.commitEvery > 0, (i + 1) % t.commitEvery == 0 { out += "commit;\n" }
        }
        return out + "commit;\n"
    }

    /// CREATE TABLE z pól pliku: liczby → NUMBER, daty `RRRR-MM-DD[ GG:MI[:SS]]` → DATE, tekst → VARCHAR2 z zapasem.
    public static func createTable(owner: String, table: String, fieldNames: [String], rows: [[String]]) -> (sql: String, mappings: [FieldMapping]) {
        var cols: [String] = []
        var maps: [FieldMapping] = []
        for (i, name) in fieldNames.enumerated() {
            let values = rows.map { $0.indices.contains(i) ? $0[i].trimmingCharacters(in: .whitespaces) : "" }.filter { !$0.isEmpty }
            let col = fieldName(name, index: i)
            let numeric = !values.isEmpty && values.allSatisfy { Double($0.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) != nil }
            let dates = !values.isEmpty && values.allSatisfy { $0.range(of: #"^\d{4}-\d{2}-\d{2}( \d{2}:\d{2}(:\d{2})?)?$"#, options: .regularExpression) != nil }
            if dates {
                cols.append("\(q(col)) DATE")
                let withTime = values.contains { $0.count > 10 }
                maps.append(FieldMapping(column: col, field: i, type: .date, dateFormat: withTime ? (values.first!.count > 16 ? "YYYY-MM-DD HH24:MI:SS" : "YYYY-MM-DD HH24:MI") : "YYYY-MM-DD"))
            } else if numeric {
                cols.append("\(q(col)) NUMBER")
                maps.append(FieldMapping(column: col, field: i, type: .number))
            } else {
                let len = max(10, min(4000, Int((Double(values.map { $0.utf8.count }.max() ?? 10) * 1.5).rounded(.up))))
                cols.append("\(q(col)) VARCHAR2(\(len) CHAR)")
                maps.append(FieldMapping(column: col, field: i, type: .string))
            }
        }
        return ("create table \(q(owner)).\(q(table)) (\n  " + cols.joined(separator: ",\n  ") + "\n)", maps)
    }
}
