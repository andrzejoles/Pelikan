import Foundation
import PelikanDB
import PelikanSQL

/// Typ zmiennej Test Window (UG 5.3).
public enum TestVariableType: String, Sendable, Codable, Hashable, CaseIterable {
    case integer, float, string, date, timestamp, long, longRaw, cursor, clob, blob, plsqlString, char, boolean
    case tempClob, tempBlob, substitution

    public var displayName: String {
        switch self {
        case .integer: "Integer"
        case .float: "Float"
        case .string: "String"
        case .date: "Date"
        case .timestamp: "Timestamp"
        case .long: "Long"
        case .longRaw: "Long Raw"
        case .cursor: "Cursor"
        case .clob: "CLOB"
        case .blob: "BLOB"
        case .plsqlString: "PL/SQL String"
        case .char: "Char"
        case .boolean: "Boolean"
        case .tempClob: "Temporary CLOB"
        case .tempBlob: "Temporary BLOB"
        case .substitution: "Substitution"
        }
    }

    /// Typ zmiennej wiązanej w sterowniku i rozmiar bufora.
    var bind: (OracleType, UInt32) {
        switch self {
        case .integer, .float: (.number, 64)
        case .string: (.varchar2, 4000)
        case .plsqlString, .long: (.varchar2, 32767)
        case .char: (.char, 2000)
        case .date: (.date, 0)
        case .timestamp: (.timestamp, 0)
        case .longRaw: (.raw, 32767)
        case .cursor: (.refCursor, 0)
        case .clob, .tempClob: (.clob, 0)
        case .blob, .tempBlob: (.blob, 0)
        case .boolean: (.boolean, 0)
        case .substitution: (.varchar2, 32767)
        }
    }

    /// Typ zmiennej Test Window dla typu argumentu z ALL_ARGUMENTS (Test z Object Browsera, UG 5.1).
    public static func forArgument(_ dataType: String) -> TestVariableType {
        switch dataType.uppercased() {
        case "NUMBER", "BINARY_INTEGER", "PLS_INTEGER", "INTEGER", "NATURAL", "POSITIVE", "SIMPLE_INTEGER": .integer
        case "BINARY_FLOAT", "BINARY_DOUBLE", "FLOAT": .float
        case "DATE": .date
        case let t where t.hasPrefix("TIMESTAMP"): .timestamp
        case "CLOB", "NCLOB": .clob
        case "BLOB": .blob
        case "REF CURSOR": .cursor
        case "PL/SQL BOOLEAN", "BOOLEAN": .boolean
        case "CHAR", "NCHAR": .char
        case "RAW", "LONG RAW": .longRaw
        default: .plsqlString
        }
    }
}

/// Zmienna Test Window: nazwa (bez dwukropka), typ, wartość tekstowa; po wykonaniu — wartość wynikowa i znacznik zmiany.
public struct TestVariable: Sendable, Hashable, Identifiable, Codable {
    public var id = UUID()
    public var name: String
    public var type: TestVariableType
    public var value: String
    public var isNull: Bool
    /// Wartość zmieniona przez ostatnie wykonanie (żółte tło, UG 5.2).
    public var changed = false
    /// Wynik kursora: kolumny i pierwsze wiersze (tekst).
    public var cursorColumns: [String] = []
    public var cursorRows: [[String]] = []

    public init(name: String, type: TestVariableType = .string, value: String = "", isNull: Bool = true) {
        self.name = name; self.type = type; self.value = value; self.isNull = isNull
    }

    enum CodingKeys: String, CodingKey { case name, type, value, isNull }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        type = (try? c.decode(TestVariableType.self, forKey: .type)) ?? .string
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
        isNull = (try? c.decode(Bool.self, forKey: .isNull)) ?? value.isEmpty
    }
}

/// Ramka stosu błędu wykonania (UG 5.5): jednostka i linia.
public struct ErrorStackFrame: Sendable, Hashable {
    public var owner: String
    public var unit: String
    public var line: Int
}

/// Test Window (UG 5): skanowanie zmiennych `:nazwa`, wykonanie bloku w sesji okna z wartościami IN OUT, odczyt wyników,
/// kursory, czas, stos błędu.
@MainActor
public enum TestRunner {
    /// Nazwy zmiennych wiązanych w bloku (kolejność pierwszego wystąpienia, bez powtórzeń, bez `:new`/`:old`).
    public static func scan(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let ns = text as NSString
        for t in Lexer(text).tokenize() where t.kind == .bindVariable {
            let name = String(ns.substring(with: NSRange(location: t.start + 1, length: t.length - 1)))
            guard !name.isEmpty, name.first?.isNumber == false, !["NEW", "OLD", "PARENT"].contains(name.uppercased()) else { continue }
            if seen.insert(name.uppercased()).inserted { out.append(name) }
        }
        return out
    }

    /// Lista zmiennych dokumentu po zmianie tekstu: nowe dopisane (typ String), istniejące zachowane, nieużywane usunięte.
    public static func synchronize(_ doc: Document) {
        let names = scan(doc.text)
        var byName = Dictionary(doc.testVariables.map { ($0.name.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        doc.testVariables = names.map { n in byName.removeValue(forKey: n.uppercased()) ?? TestVariable(name: n, type: guessType(n, in: doc.text)) }
    }

    /// Typ nowej zmiennej z kontekstu: `OPEN :x FOR` — kursor; w pozostałych przypadkach String.
    static func guessType(_ name: String, in text: String) -> TestVariableType {
        let pattern = "(?i)\\bopen\\s+:" + NSRegularExpression.escapedPattern(for: name) + "\\s+for\\b"
        return text.range(of: pattern, options: .regularExpression) != nil ? .cursor : .string
    }

    /// Wartość zmiennej jako wartość sterownika.
    static func value(_ v: TestVariable) throws -> OracleValue {
        if v.isNull || v.type == .cursor { return .null }
        switch v.type {
        case .integer, .float:
            let s = v.value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            guard Double(s) != nil else { throw CommandError.invalidArgument(v.name, L10n.tr("„\(v.value)” nie jest liczbą")) }
            return .number(s)
        case .date, .timestamp:
            guard let t = OracleTimestamp.parse(v.value, mask: "YYYY-MM-DD HH24:MI:SS") ?? OracleTimestamp.parse(v.value, mask: "YYYY-MM-DD") else {
                throw CommandError.invalidArgument(v.name, L10n.tr("„\(v.value)” nie jest datą (RRRR-MM-DD GG:MI:SS)"))
            }
            return .timestamp(t, v.type == .date ? .date : .timestamp)
        case .boolean:
            let s = v.value.lowercased()
            return .boolean(["true", "1", "t", "y", "tak", "prawda"].contains(s))
        case .longRaw, .blob, .tempBlob:
            return .raw(Data(hex: v.value) ?? Data(v.value.utf8))
        default:
            return .text(v.value)
        }
    }

    /// Wykonuje blok okna testowego w sesji okna. Zwraca czas wykonania; przy błędzie ustawia `doc.errorStack`.
    @discardableResult
    public static func execute(_ doc: Document, in ws: Workspace) async throws -> Duration {
        synchronize(doc)
        let text = doc.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CommandError.notAvailable(L10n.tr("Okno testu jest puste")) }
        // Blok bez końcowego „/” i średnika po END — tak jak w oknie SQL.
        var sql = text
        if sql.hasSuffix("/") { sql = String(sql.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        try await ws.guardModification([sql], connectionID: ws.effectiveConnection(of: doc))
        let binds = try doc.testVariables.map { v -> BindVariable in
            let (t, size) = v.type.bind
            return BindVariable(name: v.name, type: t, direction: v.type == .cursor ? .output : .inputOutput, value: try value(v), maxSize: size)
        }
        let session = try await ws.session(for: doc)
        doc.isExecuting = true
        doc.errorRange = nil
        doc.errorStack = []
        defer { doc.isExecuting = false }
        if doc.outputEnabled && ws.settings.dbmsOutputEnabled {
            if ws.settings.dbmsOutputClearBeforeExecute { doc.output = [] }
            try? await SessionUtilities.enableOutput(session, bufferSize: ws.settings.dbmsOutputBufferSize)
        }
        // Statystyki sesji i profiler wokół wykonania (UG 6.2, 6.3).
        let statsBefore = await Profiler.statistics(session)
        var profileID: Int?
        let profileComment = "Pelikan \(doc.title) \(UUID().uuidString.prefix(8))"
        if let kind = doc.profiler {
            if await Profiler.needsTables(kind, session: session) {
                try await ws.guardModification([kind == .lines ? "CREATE TABLE plsql_profiler_runs" : "BEGIN dbms_hprof.create_tables; END;"],
                                               connectionID: ws.effectiveConnection(of: doc))
            }
            profileID = try await Profiler.start(kind, session: session, comment: profileComment)
        }
        func finishMeasurements() async {
            if let kind = doc.profiler, let id = profileID {
                doc.profilerReport = try? await Profiler.stop(kind, id: id, comment: profileComment, session: session)
                // Tekst linii bloku testu (blok anonimowy nie ma źródła w ALL_SOURCE).
                if var r = doc.profilerReport, r.kind == .lines {
                    let docLines = doc.text.components(separatedBy: "\n")
                    for i in r.lines.indices where r.lines[i].isAnonymous && r.lines[i].text.isEmpty && r.lines[i].line <= docLines.count {
                        r.lines[i].text = docLines[r.lines[i].line - 1].trimmingCharacters(in: .whitespaces)
                        r.lines[i].unitName = L10n.tr("blok testu")
                    }
                    doc.profilerReport = r
                }
            }
            if let before = statsBefore, let after = await Profiler.statistics(session) {
                doc.statistics = Profiler.difference(before, after)
            }
        }
        do {
            let r = try await session.execute(sql, binds: binds)
            await finishMeasurements()
            for i in doc.testVariables.indices {
                let v = doc.testVariables[i]
                let out = r.outBinds[v.name] ?? r.outBinds[v.name.uppercased()] ?? .null
                var n = v
                if case .cursor(let id) = out {
                    // Opis kolumn przed pobraniem — wyczerpany kursor sterownik zamyka.
                    n.cursorColumns = await session.columns(of: id).map(\.name)
                    let batch = try await session.fetch(id, maxRows: 500)
                    n.cursorRows = batch.rows.map { $0.map { $0.format(ws.settings.valueFormat) } }
                    n.isNull = false
                    n.value = L10n.tr("(kursor: \(batch.rows.count) wierszy)")
                    if batch.hasMore { await session.closeResultSet(id) }
                } else {
                    n.isNull = out.isNull
                    n.value = out.isNull ? "" : out.format(ws.settings.valueFormat)
                }
                n.changed = n.value != v.value || n.isNull != v.isNull
                doc.testVariables[i] = n
            }
            if doc.outputEnabled && ws.settings.dbmsOutputEnabled, let lines = try? await SessionUtilities.readOutput(session) {
                doc.output.append(contentsOf: lines)
            }
            doc.statusText = L10n.tr("Wykonano w \(String(format: "%.3f", Double(r.elapsed.components.seconds) + Double(r.elapsed.components.attoseconds) / 1e18)) s")
            return r.elapsed
        } catch let e as OracleError {
            await finishMeasurements()
            doc.errorStack = errorStack(e.message)
            // Linia bloku z błędem (ORA-06512 „at line n” bez jednostki) → kursor.
            if let local = doc.errorStack.first(where: { $0.unit.isEmpty }) {
                let o = ProgramCompiler.offset(line: local.line, column: 1, in: doc.text)
                doc.errorRange = o..<o
            }
            doc.statusText = e.message.components(separatedBy: "\n").first
            throw e
        }
    }

    /// Ramki z komunikatu błędu: `ORA-06512: at "OWNER.UNIT", line n` oraz `at line n` (blok anonimowy).
    public nonisolated static func errorStack(_ message: String) -> [ErrorStackFrame] {
        var out: [ErrorStackFrame] = []
        let pattern = #"ORA-06512: (?:at|w) (?:"([^"]+)\.([^"]+)", )?line (\d+)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = message as NSString
        for m in re.matches(in: message, range: NSRange(location: 0, length: ns.length)) {
            func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
            out.append(ErrorStackFrame(owner: g(1), unit: g(2), line: Int(g(3)) ?? 0))
        }
        return out
    }
}

extension TestRunner {
    /// Skrypt testu podprogramu (UG 5.1): wywołanie w notacji nazwanej ze zmiennymi parametrów i wyniku, typy zmiennych
    /// z ALL_ARGUMENTS; `member` — podprogram pakietu; `overload` — numer przeciążenia (domyślnie pierwsze).
    public static func script(for o: DBObject, member: String? = nil, overload: Int? = nil, metadata m: MetadataProvider) async throws -> (String, [TestVariable]) {
        let s = try await m.session()
        let isPackage = o.type == .package || o.type == .packageBody
        guard isPackage ? member != nil : [.procedure, .function].contains(o.type) else {
            throw CommandError.notAvailable(L10n.tr("Test dotyczy procedury, funkcji albo podprogramu pakietu"))
        }
        let proc = isPackage ? member!.uppercased() : o.name
        var binds = [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "p", value: .text(proc))]
        var sql = """
            select nvl(argument_name, '#RESULT'), data_type, in_out, position, overload, pls_type
            from all_arguments where owner = :o and object_name = :p and data_level = 0
            """
        if isPackage { sql += " and package_name = :k"; binds.append(BindVariable(name: "k", value: .text(o.name))) } else { sql += " and package_name is null" }
        sql += " order by to_number(nvl(overload, '0')), sequence"
        let (_, rows) = try await s.queryAll(sql, binds: binds, limit: 1000)
        let overloads = rows.map { $0[4].displayText ?? "" }
        let chosen = overload.map(String.init) ?? overloads.first ?? ""
        let args = rows.filter { ($0[4].displayText ?? "") == chosen && ($0[1].displayText ?? "").isEmpty == false }
        var vars: [TestVariable] = []
        var params: [String] = []
        var result: String?
        for a in args {
            let name = a[0].displayText ?? ""
            let type = TestVariableType.forArgument(a[5].displayText ?? a[1].displayText ?? "")
            if name == "#RESULT" {
                result = "result"
                vars.insert(TestVariable(name: "result", type: TestVariableType.forArgument(a[1].displayText ?? "")), at: 0)
                continue
            }
            let v = name.lowercased()
            params.append("\(v) => :\(v)")
            vars.append(TestVariable(name: v, type: type))
        }
        let target = (isPackage ? "\(o.owner).\(o.name).\(proc)" : "\(o.owner).\(o.name)").lowercased()
        let call = target + (params.isEmpty ? "" : "(" + params.joined(separator: ",\n" + String(repeating: " ", count: target.count + (result == nil ? 3 : 14))) + ")")
        let body = result.map { ":\($0) := \(call);" } ?? "\(call);"
        return ("begin\n  \(body)\nend;\n", vars)
    }
}

/// Plik okna testu `.tst` (UG 5.4) — format Pelikana: JSON z blokiem i zmiennymi (nazwa, typ, wartość).
public struct TestScriptFile: Codable, Sendable, Equatable {
    public var format = "pelikan-test"
    public var version = 1
    public var block: String
    public var variables: [TestVariable]

    public init(block: String, variables: [TestVariable]) { self.block = block; self.variables = variables }

    public static func == (a: Self, b: Self) -> Bool {
        a.block == b.block && a.variables.map { [$0.name, $0.type.rawValue, $0.value] } == b.variables.map { [$0.name, $0.type.rawValue, $0.value] }
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    /// Plik JSON Pelikana albo zwykły tekst bloku (zmienne ze skanowania).
    public static func decode(_ text: String) -> TestScriptFile {
        if let d = text.data(using: .utf8), let f = try? JSONDecoder().decode(TestScriptFile.self, from: d), f.format == "pelikan-test" { return f }
        return TestScriptFile(block: text, variables: [])
    }

    /// Skrypt SQL*Plus: VARIABLE dla zmiennych, przypisanie wartości, blok, PRINT wyników (UG 5.4).
    public func sqlPlusScript() -> String {
        func decl(_ v: TestVariable) -> String {
            switch v.type {
            case .integer, .float: "NUMBER"
            case .cursor: "REFCURSOR"
            case .clob, .tempClob, .long: "CLOB"
            case .blob, .tempBlob, .longRaw: "BLOB"
            case .boolean: "BOOLEAN"
            case .char: "CHAR(2000)"
            default: "VARCHAR2(4000)"
            }
        }
        var out = "-- " + L10n.tr("Skrypt z okna testu Pelikana") + "\n"
        for v in variables { out += "variable \(v.name) \(decl(v))\n" }
        for v in variables where !v.isNull && v.type != .cursor {
            let lit: String
            switch v.type {
            case .integer, .float: lit = v.value
            case .date: lit = "to_date('\(v.value)', 'YYYY-MM-DD HH24:MI:SS')"
            case .boolean: lit = v.value.lowercased() == "true" ? "true" : "false"
            default: lit = "'" + v.value.replacingOccurrences(of: "'", with: "''") + "'"
            }
            out += "exec :\(v.name) := \(lit)\n"
        }
        let b = block.trimmingCharacters(in: .whitespacesAndNewlines)
        out += b + (b.hasSuffix("/") ? "\n" : "\n/\n")
        for v in variables { out += "print \(v.name)\n" }
        return out
    }
}
