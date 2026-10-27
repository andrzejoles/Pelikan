import Foundation


/// Zmienne w tekście polecenia, o które okno „Zmienne” pyta przed wykonaniem:
/// - zmienne podstawiania SQL*Plus `&nazwa` / `&&nazwa` (tekst wstawiany do SQL),
/// - zmienne wiązane `:nazwa` (wartość przekazywana do bazy),
/// - parametry JasperReports (decyzja właściciela, D6): `$P{nazwa}` (wartość — jak zmienna wiązana),
///   `$P!{nazwa}` (tekst wstawiany do SQL — jak `&`), `$X{FUNKCJA, kolumna, param[, param2]}` (warunek
///   rozwijany do SQL: IN, NOTIN, EQUAL, NOTEQUAL, LESS, LESS], GREATER, [GREATER, BETWEEN, [BETWEEN, BETWEEN], [BETWEEN]).
public enum VariableKind: String, Sendable, Hashable, Codable {
    case substitution        // &nazwa
    case bind                // :nazwa
    case jasperValue         // $P{nazwa}
    case jasperText          // $P!{nazwa}
    case jasperClause        // parametr użyty w $X{…}
    case literalAmpersand    // `&&` w SQL Window = dosłowny znak & (UG 12.3); w SQL*Plus to zmienna zapamiętywana
}

/// Składnia zmiennych: SQL Window i raporty (`&&` = dosłowne `&`) albo SQL*Plus (`&&x` = zmienna zapamiętywana).
public enum VariableSyntax: Sendable, Hashable { case sqlWindow, sqlplus }

public struct VariableOccurrence: Sendable, Hashable {
    public var name: String
    public var kind: VariableKind
    /// Zakres w tekście (UTF-16) całego wystąpienia (np. `&&x.`, `$X{IN, c, p}`).
    public var start: Int
    public var length: Int
    /// `&&nazwa` — wartość zapamiętywana na resztę sesji (DEFINE).
    public var persistent: Bool
    /// Dla `$X{…}`: funkcja i kolumna.
    public var clause: JasperClause?
    /// Opcje zmiennej `&<…>` (UG 12.3); dla prostych `&x` — sama nazwa.
    public var options: VariableOptions?

    public init(name: String, kind: VariableKind, start: Int, length: Int, persistent: Bool, clause: JasperClause? = nil) {
        self.name = name; self.kind = kind; self.start = start; self.length = length
        self.persistent = persistent; self.clause = clause
    }
}

public struct JasperClause: Sendable, Hashable {
    public var function: String      // IN, NOTIN, EQUAL, …, [BETWEEN] (wielkie litery)
    public var column: String
    public var parameters: [String]

    public init(function: String, column: String, parameters: [String]) {
        self.function = function; self.column = column; self.parameters = parameters
    }
}

/// Wartość podana przez użytkownika dla zmiennej.
public enum VariableValue: Sendable, Hashable {
    case null
    case text(String)
    /// Kolekcja (dla `$X{IN …}` / `$X{NOTIN …}`).
    case list([String])
}

public enum Variables {
    /// Wszystkie wystąpienia zmiennych w poleceniu. Zmienne wiązane w CREATE TRIGGER (`:new`, `:old`) pomijane,
    /// podobnie jak `:=` i nazwy w literałach i komentarzach. Zmienne podstawiania wykrywane także w literałach
    /// (jak w SQL*Plus), ale nie w komentarzach.
    public static func find(in sql: String, syntax: VariableSyntax = .sqlWindow, scanSubstitutionInStrings: Bool = true) -> [VariableOccurrence] {
        let lexer = Lexer(sql)
        let tokens = lexer.tokenize()
        let isTrigger = Self.isCreateTrigger(lexer, tokens)
        var out: [VariableOccurrence] = []
        for t in tokens {
            switch t.kind {
            case .substitution:
                let raw = lexer.string(t)
                if syntax == .sqlWindow, raw.hasPrefix("&&") {
                    out.append(VariableOccurrence(name: "&", kind: .literalAmpersand, start: t.start, length: 2, persistent: false))
                    continue
                }
                let options = VariableOptions.parse(raw)
                var occ = VariableOccurrence(name: options.name, kind: .substitution, start: t.start, length: t.length,
                                             persistent: raw.hasPrefix("&&"))
                occ.options = options
                out.append(occ)
            case .string where scanSubstitutionInStrings:
                out += substitutionsInLiteral(lexer, t, syntax: syntax)
            case .bindVariable where !isTrigger:
                var name = String(lexer.string(t).dropFirst())
                if name.hasPrefix("\"") { name = String(name.dropFirst().dropLast()) }
                out.append(VariableOccurrence(name: name, kind: .bind, start: t.start, length: t.length, persistent: false))
            case .jasperParameter:
                out += jasper(lexer.string(t), start: t.start, length: t.length)
            default:
                break
            }
        }
        return out
    }

    /// Unikalne zmienne w kolejności pierwszego wystąpienia (lista w oknie „Zmienne”).
    public static func distinct(_ occ: [VariableOccurrence]) -> [(name: String, kind: VariableKind)] {
        var seen = Set<String>()
        var out: [(String, VariableKind)] = []
        for o in occ where o.kind != .literalAmpersand {
            let key = (o.kind == .bind || o.kind == .jasperValue || o.kind == .jasperClause ? "v:" : "s:") + o.name.uppercased()
            if seen.insert(key).inserted { out.append((o.name, o.kind)) }
        }
        return out
    }

    static func isCreateTrigger(_ lexer: Lexer, _ tokens: [Token]) -> Bool {
        let words = tokens.lazy.filter { !$0.isTrivia }.prefix(8).map { lexer.upper($0) }
        guard words.first == "CREATE" else { return false }
        return words.contains("TRIGGER")
    }

    /// `&x` wewnątrz literału '…' (SQL*Plus podstawia także tam).
    static func substitutionsInLiteral(_ lexer: Lexer, _ t: Token, syntax: VariableSyntax) -> [VariableOccurrence] {
        var out: [VariableOccurrence] = []
        var i = t.start
        let end = t.end
        let text = lexer.text
        while i < end {
            if text[i] == 0x26 {
                if syntax == .sqlWindow, i + 1 < end, text[i + 1] == 0x26 {
                    out.append(VariableOccurrence(name: "&", kind: .literalAmpersand, start: i, length: 2, persistent: false))
                    i += 2
                    continue
                }
                var j = i + 1
                if j < end, text[j] == 0x26 { j += 1 }
                let nameStart = j
                while j < end, lexer.isIdentPart(text[j]) { j += 1 }
                if j > nameStart, lexer.isIdentStart(text[nameStart]) || lexer.isDigit(text[nameStart]) {
                    let name = String(decoding: text[nameStart..<j], as: UTF16.self)
                    if j < end, text[j] == 0x2E { j += 1 }
                    out.append(VariableOccurrence(name: name, kind: .substitution, start: i, length: j - i,
                                                  persistent: text[i + 1] == 0x26))
                    i = j
                    continue
                }
            }
            i += 1
        }
        return out
    }

    static func jasper(_ raw: String, start: Int, length: Int) -> [VariableOccurrence] {
        let inner = raw.drop(while: { $0 != "{" }).dropFirst().dropLast()
        if raw.hasPrefix("$P!") {
            return [VariableOccurrence(name: inner.trimmingCharacters(in: .whitespaces), kind: .jasperText,
                                       start: start, length: length, persistent: false)]
        }
        if raw.hasPrefix("$P") {
            return [VariableOccurrence(name: inner.trimmingCharacters(in: .whitespaces), kind: .jasperValue,
                                       start: start, length: length, persistent: false)]
        }
        // $X{FUNKCJA, kolumna, param[, param2]}
        let parts = inner.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return [] }
        let clause = JasperClause(function: parts[0].uppercased(), column: parts[1], parameters: Array(parts[2...]))
        return clause.parameters.map {
            VariableOccurrence(name: $0, kind: .jasperClause, start: start, length: length, persistent: false, clause: clause)
        }
    }

    /// Wynik przygotowania polecenia: tekst do wykonania i zmienne wiązane (nazwa → wartość).
    public struct Prepared: Sendable, Hashable {
        public var sql: String
        public var binds: [(name: String, value: VariableValue)]

        public init(sql: String, binds: [(name: String, value: VariableValue)]) {
            self.sql = sql
            self.binds = binds
        }

        public static func == (a: Prepared, b: Prepared) -> Bool {
            a.sql == b.sql && a.binds.map(\.name) == b.binds.map(\.name) && a.binds.map(\.value) == b.binds.map(\.value)
        }
        public func hash(into h: inout Hasher) { h.combine(sql) }
    }

    /// Podstawia wartości: `&` i `$P!{}` jako tekst, `$P{}` i `:x` jako zmienne wiązane, `$X{}` rozwija do warunku
    /// ze zmiennymi wiązanymi (`:jx1`, `:jx2`, …). Zmienne bez wartości zostają bez zmian (`:x` → wartość NULL).
    public static func prepare(_ sql: String, values: [String: VariableValue], syntax: VariableSyntax = .sqlWindow) -> Prepared {
        let occ = find(in: sql, syntax: syntax)
        let utf16 = Array(sql.utf16)
        var out = ""
        var cursor = 0
        var binds: [(String, VariableValue)] = []
        var bindNames = Set<String>()
        var jx = 0
        func value(_ name: String) -> VariableValue? {
            values[name] ?? values.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        func addBind(_ name: String, _ v: VariableValue) {
            if bindNames.insert(name.uppercased()).inserted { binds.append((name, v)) }
        }
        func newBind(_ v: VariableValue) -> String {
            jx += 1
            let n = "jx\(jx)"
            binds.append((n, v))
            return ":" + n
        }
        var handledClauses = Set<Int>()
        for o in occ {
            guard o.start >= cursor else { continue }
            if o.kind == .bind {
                addBind(o.name, value(o.name) ?? .null)
                continue   // :x zostaje w tekście
            }
            if o.kind == .jasperClause && handledClauses.contains(o.start) { continue }
            out += String(decoding: utf16[cursor..<o.start], as: UTF16.self)
            cursor = o.start + o.length
            switch o.kind {
            case .substitution:
                if let v = value(o.name) {
                    out += (o.options ?? VariableOptions(name: o.name)).substitution(for: v)
                } else {
                    out += String(decoding: utf16[o.start..<cursor], as: UTF16.self)
                }
            case .literalAmpersand:
                out += "&"
            case .jasperText:
                if case .text(let t)? = value(o.name) { out += t }
                else if case .list(let l)? = value(o.name) { out += l.joined(separator: ", ") }
                else { out += String(decoding: utf16[o.start..<cursor], as: UTF16.self) }
            case .jasperValue:
                let name = Self.bindName(for: o.name)
                out += ":" + name
                addBind(name, value(o.name) ?? .null)
            case .jasperClause:
                handledClauses.insert(o.start)
                // Nieznana funkcja (literówka) zostaje w tekście — Oracle zgłosi błąd składni zamiast warunku `0 = 0`,
                // który w DELETE/UPDATE objąłby wszystkie wiersze (JasperReports też zgłasza błąd).
                if let c = o.clause, let e = expand(c, value: value, newBind: newBind) { out += e }
                else { out += String(decoding: utf16[o.start..<cursor], as: UTF16.self) }
            case .bind:
                break
            }
        }
        out += String(decoding: utf16[cursor...], as: UTF16.self)
        return Prepared(sql: out, binds: binds)
    }

    /// Nazwa zmiennej wiązanej dla `$P{nazwa}` (nazwy Jaspera mogą mieć znaki niedozwolone w Oracle).
    static func bindName(for jasperName: String) -> String {
        let ok = jasperName.unicodeScalars.allSatisfy { ($0.properties.isAlphabetic || $0 == "_" || ("0"..."9").contains($0)) && $0.isASCII }
        if ok, let f = jasperName.unicodeScalars.first, f.properties.isAlphabetic, jasperName.count <= 30 { return jasperName }
        let cleaned = jasperName.unicodeScalars.map { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) ? Character($0) : "_" }
        return "p_" + String(String(cleaned).prefix(28))
    }

    /// Rozwinięcie `$X{…}` jak w JasperReports: brak wartości (NULL / pusta kolekcja) → warunek zawsze prawdziwy `0 = 0`.
    /// Nieznana funkcja → nil (wystąpienie zostaje bez zmian).
    static func expand(_ c: JasperClause, value: (String) -> VariableValue?, newBind: (VariableValue) -> String) -> String? {
        let col = c.column
        let p1 = c.parameters.first.flatMap(value) ?? .null
        let p2 = c.parameters.count > 1 ? (value(c.parameters[1]) ?? .null) : .null
        func isNull(_ v: VariableValue) -> Bool {
            switch v {
            case .null: true
            case .list(let l): l.isEmpty
            case .text: false
            }
        }
        switch c.function {
        case "IN", "NOTIN":
            let items: [String] = switch p1 {
            case .list(let l): l
            case .text(let t): [t]
            case .null: []
            }
            if items.isEmpty { return "0 = 0" }
            let placeholders = items.map { newBind(.text($0)) }.joined(separator: ", ")
            return "\(col) \(c.function == "IN" ? "IN" : "NOT IN") (\(placeholders))"
        case "EQUAL":
            return isNull(p1) ? "\(col) IS NULL" : "\(col) = \(newBind(p1))"
        case "NOTEQUAL":
            return isNull(p1) ? "\(col) IS NOT NULL" : "\(col) <> \(newBind(p1))"
        case "LESS", "LESS]", "GREATER", "[GREATER":
            if isNull(p1) { return "0 = 0" }
            let op = ["LESS": "<", "LESS]": "<=", "GREATER": ">", "[GREATER": ">="][c.function]!
            return "\(col) \(op) \(newBind(p1))"
        case "BETWEEN", "[BETWEEN", "BETWEEN]", "[BETWEEN]":
            let lo = c.function.hasPrefix("[") ? ">=" : ">"
            let hi = c.function.hasSuffix("]") ? "<=" : "<"
            switch (isNull(p1), isNull(p2)) {
            case (true, true): return "0 = 0"
            case (false, true): return "\(col) \(lo) \(newBind(p1))"
            case (true, false): return "\(col) \(hi) \(newBind(p2))"
            case (false, false): return "\(col) \(lo) \(newBind(p1)) AND \(col) \(hi) \(newBind(p2))"
            }
        default:
            return nil
        }
    }
}
