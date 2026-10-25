import Foundation
import PelikanDB
import PelikanSQL

/// Definicja tabeli generatora danych (UG 24.10, PD-TOOL-011).
public struct GeneratorTable: Sendable, Codable, Hashable, Identifiable {
    public struct Field: Sendable, Codable, Hashable, Identifiable {
        public var name: String
        /// Typ kolumny (NUMBER, VARCHAR2, DATE…) — decyduje o literale w skrypcie.
        public var type: String
        public var definition: String
        public var id: String { name }
        public init(name: String, type: String, definition: String) { self.name = name; self.type = type; self.definition = definition }
    }
    public var name: String
    /// Liczba rekordów: stała albo zakres (dla tabeli podrzędnej — na każdy rekord nadrzędny).
    public var minRecords: Int
    public var maxRecords: Int
    public var fields: [Field]
    /// Tabela nadrzędna (master/detail) — nazwa innej tabeli definicji.
    public var parent: String?
    public var id: String { name }

    public init(name: String, minRecords: Int, maxRecords: Int, fields: [Field], parent: String? = nil) {
        self.name = name; self.minRecords = minRecords; self.maxRecords = maxRecords; self.fields = fields; self.parent = parent
    }
}

/// Generator danych testowych. Składnia definicji pola:
/// - tekst dosłowny, łączony z innymi częściami: `Klient [0000]`;
/// - wzorzec w nawiasach kwadratowych: `a` mała litera, `A` wielka, `@` dowolna litera, `#` litera lub cyfra,
///   `*` dowolny znak drukowalny, `0` cyfra, `1` cyfra 1–9, `9` cyfra lub spacja; po znaku powtórzenie `(n)` albo
///   `(min..max)`; tekst w apostrofach dosłownie, np. `[A(1)a(3..8)' '0(2)]`;
/// - funkcje: `Random(min, max)` (liczby całkowite, dziesiętne albo daty `'RRRR-MM-DD'`), `Sequence(start[, krok][, WithinParent])`,
///   `List('x'(waga), 'y', …)`, `List(select …)` (zapytanie wykonywane raz), `SQL(wyrażenie z :pole)` (dla każdego
///   rekordu), `Text(maks. słów)`, `Uppercase(…)`, `Lowercase(…)`, `InitCaps(…)`, `Parent(pole)`, `Field(pole)`;
/// - zbiory: `Firstname`, `Lastname`, `Company`, `Address1`, `Address2`, `ZIP`, `City`, `State`, `Country`, `Email`.
public struct DataGenerator {
    public indirect enum Part: Sendable, Hashable {
        case literal(String)
        case pattern([PatternItem])
        case function(String, [String])
    }

    public struct PatternItem: Sendable, Hashable {
        public var set: String
        public var min: Int
        public var max: Int
    }

    var rng: SplitMix
    /// Wyniki zapytań List(select …) i wyrażeń SQL(…) — z bazy (nil — bez bazy).
    let session: (any DatabaseSession)?
    var listCache: [String: [String]] = [:]

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max), session: (any DatabaseSession)? = nil) {
        rng = SplitMix(seed: seed)
        self.session = session
    }

    // MARK: Parser

    /// Części definicji (tekst, wzorce, funkcje); nawiasy i apostrofy zagnieżdżone.
    public static func parse(_ definition: String) -> [Part] {
        var parts: [Part] = []
        let chars = Array(definition)
        var i = 0
        var literal = ""
        func flush() { if !literal.isEmpty { parts.append(.literal(literal)); literal = "" } }
        while i < chars.count {
            let c = chars[i]
            if c == "[" {
                flush()
                var j = i + 1
                var inQuote = false
                while j < chars.count, inQuote || chars[j] != "]" {
                    if chars[j] == "'" { inQuote.toggle() }
                    j += 1
                }
                parts.append(.pattern(parsePattern(String(chars[(i + 1)..<min(j, chars.count)]))))
                i = j + 1
                continue
            }
            if c.isLetter {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                let word = String(chars[i..<j])
                if Self.knownFunctions.contains(word.lowercased()), j < chars.count, chars[j] == "(" {
                    flush()
                    var depth = 0, k = j
                    var inQuote = false
                    repeat {
                        if chars[k] == "'" { inQuote.toggle() }
                        if !inQuote { if chars[k] == "(" { depth += 1 } else if chars[k] == ")" { depth -= 1 } }
                        k += 1
                    } while k < chars.count && depth > 0
                    parts.append(.function(word.lowercased(), splitArguments(String(chars[(j + 1)..<max(j + 1, k - 1)]))))
                    i = k
                    continue
                }
                if Self.dataSets.contains(word.lowercased()), (j >= chars.count || !(chars[j].isLetter)) {
                    flush()
                    parts.append(.function(word.lowercased(), []))
                    i = j
                    continue
                }
                literal += word
                i = j
                continue
            }
            literal.append(c)
            i += 1
        }
        flush()
        return parts
    }

    static let knownFunctions: Set<String> = ["random", "sequence", "list", "sql", "text", "uppercase", "lowercase", "initcaps", "parent", "field"]
    static let dataSets: Set<String> = ["firstname", "lastname", "company", "address1", "address2", "zip", "city", "state", "country", "email"]

    static func parsePattern(_ s: String) -> [PatternItem] {
        var items: [PatternItem] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            var set: String
            if chars[i] == "'" {
                var j = i + 1
                while j < chars.count, chars[j] != "'" { j += 1 }
                set = "'" + String(chars[(i + 1)..<min(j, chars.count)])
                i = j + 1
            } else {
                set = String(chars[i])
                i += 1
            }
            var lo = 1, hi = 1
            if i < chars.count, chars[i] == "(" {
                var j = i + 1
                while j < chars.count, chars[j] != ")" { j += 1 }
                let inner = String(chars[(i + 1)..<min(j, chars.count)])
                let r = inner.components(separatedBy: "..")
                // Liczba powtórzeń nieujemna (`a(-1)` — zero znaków zamiast błędu zakresu).
                lo = max(0, Int(r[0].trimmingCharacters(in: .whitespaces)) ?? 1)
                hi = r.count > 1 ? Int(r[1].trimmingCharacters(in: .whitespaces)) ?? lo : lo
                i = j + 1
            }
            items.append(PatternItem(set: set, min: lo, max: max(lo, hi)))
        }
        return items
    }

    static func splitArguments(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var depth = 0
        var inQuote = false
        for c in s {
            if c == "'" { inQuote.toggle() }
            if !inQuote {
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
                if c == ",", depth == 0 { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            }
            cur.append(c)
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty || !out.isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
        return out
    }

    static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("'"), t.hasSuffix("'"), t.count >= 2 { return String(t.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return t
    }

    // MARK: Wartości

    struct Context {
        var row: [String: String]
        var parent: [String: String]
        var index: Int
        var indexInParent: Int
    }

    mutating func value(_ definition: String, _ ctx: Context, field: String) async throws -> String {
        var out = ""
        for p in Self.parse(definition) { out += try await value(p, ctx, field: field) }
        return out
    }

    mutating func value(_ part: Part, _ ctx: Context, field: String) async throws -> String {
        switch part {
        case .literal(let s): return s
        case .pattern(let items):
            var s = ""
            for it in items {
                let n = Int(rng.next(in: it.min...it.max))
                if it.set.hasPrefix("'") { s += String(repeating: String(it.set.dropFirst()), count: n); continue }
                for _ in 0..<n { s.append(char(it.set)) }
            }
            return s
        case .function(let name, let args):
            switch name {
            case "random": return random(args)
            case "sequence":
                let start = Int(args.first ?? "1") ?? 1
                let step = args.count > 1 ? Int(args[1]) ?? 1 : 1
                let within = args.contains { $0.lowercased() == "withinparent" }
                return String(start + step * (within ? ctx.indexInParent : ctx.index))
            case "list": return try await list(args)
            case "sql": return try await sql(args.joined(separator: ","), ctx)
            case "text": return text(Int(args.first ?? "10") ?? 10)
            case "uppercase": return try await value(args.joined(separator: ","), ctx, field: field).uppercased()
            case "lowercase": return try await value(args.joined(separator: ","), ctx, field: field).lowercased()
            case "initcaps": return try await value(args.joined(separator: ","), ctx, field: field).capitalized
            case "parent": return ctx.parent[(args.first ?? "").uppercased()] ?? ""
            case "field": return ctx.row[(args.first ?? "").uppercased()] ?? ""
            default: return dataSet(name, ctx)
            }
        }
    }

    mutating func char(_ set: String) -> Character {
        let lower = Array("abcdefghijklmnopqrstuvwxyz"), upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), digits = Array("0123456789")
        let pool: [Character] = switch set {
        case "a": lower
        case "A": upper
        case "@": lower + upper
        case "#": lower + upper + digits
        case "*": (33...126).map { Character(UnicodeScalar(UInt8($0))) }
        case "0": digits
        case "1": Array("123456789")
        case "9": digits + [" "]
        default: Array(set)
        }
        return pool[Int(rng.next(in: 0...(pool.count - 1)))]
    }

    mutating func random(_ args: [String]) -> String {
        let a = Self.unquote(args.first ?? "0"), b = Self.unquote(args.count > 1 ? args[1] : "100")
        if a.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd"
            guard let d1 = f.date(from: String(a.prefix(10))), let d2 = f.date(from: String(b.prefix(10))) else { return a }
            let days = Int((d2.timeIntervalSince(d1) / 86_400).rounded())
            return f.string(from: d1.addingTimeInterval(Double(rng.next(in: 0...max(0, days))) * 86_400))
        }
        if let x = Int(a), let y = Int(b) { return String(rng.next(in: Int64(min(x, y))...Int64(max(x, y)))) }
        let x = Double(a) ?? 0, y = Double(b) ?? 100
        let decimals = max(a.split(separator: ".").dropFirst().first?.count ?? 0, b.split(separator: ".").dropFirst().first?.count ?? 0, 2)
        let v = x + (y - x) * Double(rng.next(in: 0...1_000_000)) / 1_000_000
        return String(format: "%.\(decimals)f", v)
    }

    mutating func list(_ args: [String]) async throws -> String {
        if let q = args.first, q.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("select") {
            let query = args.joined(separator: ",")
            if listCache[query] == nil {
                guard let s = session else { throw CommandError.notConnected }
                let (_, rows) = try await s.queryAll(query, limit: 100_000)
                listCache[query] = rows.map { $0.first?.displayText ?? "" }
            }
            let values = listCache[query] ?? []
            return values.isEmpty ? "" : values[Int(rng.next(in: 0...(values.count - 1)))]
        }
        // 'x'(waga): wybór ważony.
        var items: [(String, Int)] = []
        for a in args {
            if let r = a.range(of: #"\((\d+)\)\s*$"#, options: .regularExpression) {
                let w = Int(a[r].filter(\.isNumber)) ?? 1
                items.append((Self.unquote(String(a[..<r.lowerBound])), w))
            } else {
                items.append((Self.unquote(a), 1))
            }
        }
        let total = items.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return "" }
        var pick = Int(rng.next(in: 1...Int64(total)))
        for (v, w) in items {
            pick -= w
            if pick <= 0 { return v }
        }
        return items.last?.0 ?? ""
    }

    func sql(_ expression: String, _ ctx: Context) async throws -> String {
        guard let s = session else { throw CommandError.notConnected }
        let names = Set(Lexer(expression).tokenize().filter { $0.kind == .bindVariable }.map {
            (expression as NSString).substring(with: NSRange(location: $0.start + 1, length: $0.length - 1)).uppercased()
        })
        let binds = names.map { BindVariable(name: $0, value: (ctx.row[$0] ?? ctx.parent[$0]).map { .text($0) } ?? .null) }
        return try await s.scalar("select \(expression) from dual", binds: binds) ?? ""
    }

    static let words = ("dane baza tabela indeks wiersz kolumna klucz raport projekt zadanie wynik plan test kod pakiet procedura funkcja "
        + "zmiana termin klient umowa faktura zamówienie produkt magazyn dostawa płatność system moduł wersja serwer").split(separator: " ").map(String.init)
    static let firstNames = ["Anna", "Piotr", "Maria", "Jan", "Katarzyna", "Tomasz", "Agnieszka", "Paweł", "Ewa", "Michał", "Zofia", "Marek",
                             "Olivia", "James", "Emma", "Lukas", "Sofia", "Mateo", "Hanna", "Noah"]
    static let lastNames = ["Nowak", "Kowalski", "Wiśniewska", "Wójcik", "Kamińska", "Lewandowski", "Zielińska", "Szymański", "Dąbrowska",
                            "Smith", "Müller", "García", "Rossi", "Martin", "Novák", "Johansson"]
    static let companies = ["Delta", "Kormoran", "Bursztyn", "Polaris", "Wisła", "Orion", "Zenit", "Atlas", "Merkury", "Sokół"]
    static let suffixes = ["Sp. z o.o.", "S.A.", "Ltd", "GmbH", "Spółka Jawna"]
    static let streets = ["Długa", "Polna", "Leśna", "Słoneczna", "Kwiatowa", "Ogrodowa", "Lipowa", "Brzozowa", "Main Street", "Oak Avenue"]
    static let cities = ["Warszawa", "Kraków", "Gdańsk", "Wrocław", "Poznań", "Łódź", "Lublin", "Berlin", "Praga", "Wiedeń"]
    static let states = ["mazowieckie", "małopolskie", "pomorskie", "dolnośląskie", "wielkopolskie", "łódzkie", "lubelskie"]
    static let countries = ["Polska", "Niemcy", "Czechy", "Austria", "Słowacja", "Litwa", "Szwecja", "Hiszpania"]

    mutating func pick(_ a: [String]) -> String { a[Int(rng.next(in: 0...(a.count - 1)))] }

    mutating func text(_ maxWords: Int) -> String {
        let n = Int(rng.next(in: 1...max(1, maxWords)))
        var s = (0..<n).map { _ in pick(Self.words) }.joined(separator: " ")
        s = s.prefix(1).uppercased() + s.dropFirst() + "."
        return s
    }

    mutating func dataSet(_ name: String, _ ctx: Context) -> String {
        switch name {
        case "firstname": return pick(Self.firstNames)
        case "lastname": return pick(Self.lastNames)
        case "company": return pick(Self.companies) + " " + pick(Self.suffixes)
        case "address1": return "ul. \(pick(Self.streets)) \(rng.next(in: 1...250))"
        case "address2": return rng.next(in: 0...1) == 0 ? "" : "m. \(rng.next(in: 1...120))"
        case "zip": return String(format: "%02d-%03d", Int(rng.next(in: 0...99)), Int(rng.next(in: 0...999)))
        case "city": return pick(Self.cities)
        case "state": return pick(Self.states)
        case "country": return pick(Self.countries)
        case "email":
            let first = ctx.row.first { ["FIRSTNAME", "FIRST_NAME", "IMIE"].contains($0.key) }?.value ?? pick(Self.firstNames)
            let last = ctx.row.first { ["LASTNAME", "LAST_NAME", "NAZWISKO"].contains($0.key) }?.value ?? pick(Self.lastNames)
            let ascii = { (s: String) in s.folding(options: .diacriticInsensitive, locale: nil).lowercased().replacingOccurrences(of: "ł", with: "l").filter { $0.isLetter } }
            return "\(ascii(first)).\(ascii(last))@\(ascii(pick(Self.companies))).example"
        default: return ""
        }
    }

    // MARK: Generowanie

    /// Wiersze tabel w kolejności definicji (nadrzędne przed podrzędnymi); wartości jako tekst.
    public mutating func generate(_ tables: [GeneratorTable]) async throws -> [String: [[String: String]]] {
        var result: [String: [[String: String]]] = [:]
        let ordered = tables.filter { $0.parent == nil } + tables.filter { $0.parent != nil }
        for t in ordered {
            var rows: [[String: String]] = []
            let parents: [[String: String]] = t.parent.flatMap { result[$0] } ?? [[:]]
            for parent in parents {
                let n = Int(rng.next(in: Int64(t.minRecords)...Int64(max(t.minRecords, t.maxRecords))))
                for k in 0..<n {
                    var ctx = Context(row: [:], parent: parent, index: rows.count, indexInParent: k)
                    for f in t.fields {
                        let v = try await value(f.definition, ctx, field: f.name)
                        ctx.row[f.name.uppercased()] = v
                    }
                    rows.append(ctx.row)
                }
            }
            result[t.name] = rows
        }
        return result
    }

    /// Literał wartości wg typu kolumny (skrypt SQL).
    public static func literal(_ value: String, type: String) -> String {
        if value.isEmpty { return "NULL" }
        let t = type.uppercased()
        if ["NUMBER", "FLOAT", "INTEGER", "BINARY_DOUBLE", "BINARY_FLOAT"].contains(t), Double(value) != nil { return value }
        if t == "DATE" || t.hasPrefix("TIMESTAMP") {
            let fmt = value.count > 10 ? "YYYY-MM-DD HH24:MI:SS" : "YYYY-MM-DD"
            return "TO_DATE(\(ResultExporter.quote(String(value.prefix(19)))), '\(fmt)')"
        }
        return ResultExporter.quote(value)
    }

    /// Skrypt INSERT dla wygenerowanych danych (Create data as SQL).
    public static func script(_ data: [String: [[String: String]]], tables: [GeneratorTable], owner: String, commitEvery: Int = 100) -> String {
        var out = "-- " + L10n.tr("Dane testowe — wygenerowane przez Pelikana") + "\n"
        let ordered = tables.filter { $0.parent == nil } + tables.filter { $0.parent != nil }
        for t in ordered {
            let cols = t.fields.map { ResultExporter.identifier($0.name.uppercased()) }.joined(separator: ", ")
            for (i, row) in (data[t.name] ?? []).enumerated() {
                let values = t.fields.map { literal(row[$0.name.uppercased()] ?? "", type: $0.type) }
                out += "insert into \(ResultExporter.identifier(owner)).\(ResultExporter.identifier(t.name.uppercased())) (\(cols)) values (\(values.joined(separator: ", ")));\n"
                if commitEvery > 0, (i + 1) % commitEvery == 0 { out += "commit;\n" }
            }
        }
        return out + "commit;\n"
    }

    /// Wstawienie wygenerowanych danych do bazy (Create data in DB) z COMMIT co n rekordów.
    public static func insert(_ data: [String: [[String: String]]], tables: [GeneratorTable], owner: String, commitEvery: Int = 100,
                              in s: any DatabaseSession) async throws -> ImportResult {
        var result = ImportResult()
        let ordered = tables.filter { $0.parent == nil } + tables.filter { $0.parent != nil }
        for t in ordered {
            let binds = t.fields.indices.map { "v\($0)" }
            let exprs = zip(t.fields, binds).map { f, b -> String in
                let ty = f.type.uppercased()
                if ty == "DATE" || ty.hasPrefix("TIMESTAMP") {
                    return "TO_DATE(SUBSTR(:\(b), 1, 19), CASE WHEN LENGTH(:\(b)) > 10 THEN 'YYYY-MM-DD HH24:MI:SS' ELSE 'YYYY-MM-DD' END)"
                }
                return ":\(b)"
            }
            let sql = "insert into \(ResultExporter.identifier(owner)).\(ResultExporter.identifier(t.name.uppercased())) (\(t.fields.map { ResultExporter.identifier($0.name.uppercased()) }.joined(separator: ", "))) values (\(exprs.joined(separator: ", ")))"
            for (i, row) in (data[t.name] ?? []).enumerated() {
                let values = zip(t.fields, binds).map { f, b -> BindVariable in
                    let v = row[f.name.uppercased()] ?? ""
                    if ["NUMBER", "FLOAT", "INTEGER"].contains(f.type.uppercased()), Double(v) != nil { return BindVariable(name: b, type: .number, value: .number(v)) }
                    return BindVariable(name: b, value: v.isEmpty ? .null : .text(v))
                }
                do {
                    _ = try await s.execute(sql, binds: values)
                    result.inserted += 1
                } catch {
                    result.errors.append("\(t.name) " + L10n.tr("rekord \(i + 1): \(error.localizedDescription)"))
                }
                if commitEvery > 0, (i + 1) % commitEvery == 0 { try await s.commit() }
            }
        }
        try await s.commit()
        return result
    }

    /// Domyślna definicja tabeli z kolumn słownika (klucz główny — Sequence, liczby — Random, daty — zakres, tekst — wzorzec).
    public static func defaultTable(owner: String, table: String, in s: any DatabaseSession) async throws -> GeneratorTable {
        let pk = Set(try await TextImport.primaryKey(owner: owner, table: table, in: s))
        let (_, rows) = try await s.queryAll("""
            select column_name, data_type, nvl(data_precision, 0), nvl(data_scale, 0), char_length from all_tab_cols
             where owner = :o and table_name = :t and virtual_column = 'NO' and hidden_column = 'NO' order by column_id
            """, binds: [BindVariable(name: "o", value: .text(owner.uppercased())), BindVariable(name: "t", value: .text(table.uppercased()))])
        let fields = rows.map { r -> GeneratorTable.Field in
            let name = r[0].displayText ?? ""
            let type = r[1].displayText ?? ""
            let precision = Int(r[2].displayText ?? "0") ?? 0
            let scale = Int(r[3].displayText ?? "0") ?? 0
            let length = Int(r[4].displayText ?? "10") ?? 10
            let def: String
            if pk.contains(name), type == "NUMBER" {
                def = "Sequence(1)"
            } else if type == "NUMBER" {
                let digits = precision > 0 ? min(9, max(1, precision - scale)) : 4
                def = scale > 0 ? "Random(0, \(Int(pow(10, Double(digits))) - 1).\(String(repeating: "9", count: scale)))" : "Random(0, \(Int(pow(10, Double(digits))) - 1))"
            } else if type == "DATE" || type.hasPrefix("TIMESTAMP") {
                def = "Random('2020-01-01', '2026-12-31')"
            } else if name.contains("MAIL") {
                def = "Email"
            } else {
                def = "[A(1)a(\(min(3, max(1, length - 1)))..\(max(1, min(length - 1, 12))))]"
            }
            return GeneratorTable.Field(name: name, type: type, definition: def)
        }
        return GeneratorTable(name: table.uppercased(), minRecords: 10, maxRecords: 10, fields: fields)
    }
}

/// Deterministyczny generator liczb (powtarzalny podgląd przy tym samym ziarnie).
struct SplitMix: Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func nextRaw() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in r: ClosedRange<Int64>) -> Int64 {
        let width = UInt64(bitPattern: r.upperBound &- r.lowerBound) &+ 1
        if width == 0 { return Int64(bitPattern: nextRaw()) }
        return r.lowerBound &+ Int64(bitPattern: nextRaw() % width)
    }

    mutating func next(in r: ClosedRange<Int>) -> Int64 { next(in: Int64(r.lowerBound)...Int64(r.upperBound)) }
}
