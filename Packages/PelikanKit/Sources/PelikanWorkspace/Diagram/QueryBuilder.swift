import Foundation
import PelikanSQL

/// Tabela w Query Builderze (UG 28): nazwa, alias, kolumny, położenie na płótnie.
public struct QBTable: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var owner: String
    public var name: String
    public var alias: String
    public var columns: [SchemaColumn]
    public var position = DiagramPoint(16, 16)
    /// Podzapytanie w FROM (widok wbudowany, PD-QB-001) — wtedy `name` jest tylko etykietą.
    public var subquery: String?

    public init(owner: String, name: String, alias: String, columns: [SchemaColumn]) {
        self.owner = owner; self.name = name; self.alias = alias; self.columns = columns
    }
}

/// Złączenie dwóch tabel po kolumnach (z klucza obcego albo ręczne).
public struct QBJoin: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case inner = "JOIN", left = "LEFT JOIN", right = "RIGHT JOIN", full = "FULL JOIN"
    }
    public var id = UUID()
    public var left: UUID
    public var leftColumns: [String]
    public var right: UUID
    public var rightColumns: [String]
    public var kind: Kind = .inner

    public init(left: UUID, leftColumns: [String], right: UUID, rightColumns: [String], kind: Kind = .inner) {
        self.left = left; self.leftColumns = leftColumns; self.right = right; self.rightColumns = rightColumns; self.kind = kind
    }
}

/// Pole listy SELECT: kolumna tabeli albo wyrażenie; sortowanie i grupowanie.
public struct QBField: Sendable, Codable, Hashable, Identifiable {
    public enum Sort: String, Sendable, Codable, CaseIterable { case none, ascending, descending }
    public var id = UUID()
    public var table: UUID?
    public var expression: String
    public var alias = ""
    public var sort: Sort = .none
    public var groupBy = false

    public init(table: UUID?, expression: String) { self.table = table; self.expression = expression }
}

/// Preferencje formatu generowanego SQL (UG 28 „Preferences”).
public struct QBFormat: Sendable, Codable, Hashable {
    public var uppercaseKeywords = false
    public var columnPerLine = true
    /// Złączenia w klauzuli FROM (ANSI) albo warunki w WHERE.
    public var ansiJoins = true
    public var qualifyWithOwner = false
    public init() {}
}

/// Zapytanie budowane w Query Builderze; generuje SELECT i — dla prostych zapytań — odtwarza model z tekstu.
public struct QueryModel: Sendable, Codable, Hashable {
    public var tables: [QBTable] = []
    public var joins: [QBJoin] = []
    public var fields: [QBField] = []
    public var distinct = false
    public var whereClause = ""
    public var having = ""
    /// Lista zmiennych `INTO` (zapytanie w PL/SQL).
    public var into = ""
    public var format = QBFormat()

    public init() {}

    public func table(_ id: UUID?) -> QBTable? { tables.first { $0.id == id } }

    /// Alias z pierwszych liter członów nazwy (EMP_DEPT_HIST → edh), unikalny w zapytaniu.
    public func uniqueAlias(for name: String) -> String {
        let parts = name.lowercased().split(separator: "_").filter { !$0.isEmpty }
        var base = parts.count > 1 ? String(parts.compactMap(\.first)) : String(name.lowercased().prefix(1))
        if base.isEmpty || !(base.first?.isLetter ?? false) { base = "t" }
        var alias = base, n = 2
        while tables.contains(where: { $0.alias == alias }) || Keywords.reserved.contains(alias.uppercased()) {
            alias = "\(base)\(n)"
            n += 1
        }
        return alias
    }

    /// Dodaje tabelę i złączenia z kluczy obcych do tabel już obecnych (w obie strony).
    @discardableResult
    public mutating func addTable(owner: String, name: String, columns: [SchemaColumn], foreignKeys: [ForeignKey]) -> UUID {
        var t = QBTable(owner: owner, name: name, alias: uniqueAlias(for: name), columns: columns)
        t.position = DiagramPoint(16 + Double(tables.count % 4) * 232, 16 + Double(tables.count / 4) * 220)
        for fk in foreignKeys {
            if fk.childOwner == owner, fk.childTable == name, let p = tables.first(where: { $0.owner == fk.parentOwner && $0.name == fk.parentTable }) {
                joins.append(QBJoin(left: p.id, leftColumns: fk.parentColumns, right: t.id, rightColumns: fk.childColumns))
            } else if fk.parentOwner == owner, fk.parentTable == name, let c = tables.first(where: { $0.owner == fk.childOwner && $0.name == fk.childTable }) {
                joins.append(QBJoin(left: c.id, leftColumns: fk.childColumns, right: t.id, rightColumns: fk.parentColumns))
            }
        }
        tables.append(t)
        return t.id
    }

    /// Dodaje podzapytanie w FROM z aliasem; kolumny z opisu zapytania (PD-QB-001).
    @discardableResult
    public mutating func addSubquery(_ sql: String, alias: String, columns: [SchemaColumn]) -> UUID {
        var q = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while q.hasSuffix(";") { q = String(q.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        let a = alias.trimmingCharacters(in: .whitespaces).isEmpty ? uniqueAlias(for: "SUBQ") : alias.lowercased()
        var t = QBTable(owner: "", name: a.uppercased(), alias: a, columns: columns)
        t.subquery = q
        t.position = DiagramPoint(16 + Double(tables.count % 4) * 232, 16 + Double(tables.count / 4) * 220)
        tables.append(t)
        return t.id
    }

    public mutating func removeTable(_ id: UUID) {
        tables.removeAll { $0.id == id }
        joins.removeAll { $0.left == id || $0.right == id }
        fields.removeAll { $0.table == id }
    }

    /// Zaznaczenie kolumny tabeli na liście pól (przełącza).
    public mutating func toggleColumn(_ column: String, of table: UUID) {
        if let i = fields.firstIndex(where: { $0.table == table && $0.expression == column }) {
            fields.remove(at: i)
        } else {
            fields.append(QBField(table: table, expression: column))
        }
    }

    public func isSelected(_ column: String, of table: UUID) -> Bool {
        fields.contains { $0.table == table && $0.expression == column }
    }

    // MARK: Generowanie

    func kw(_ s: String) -> String { format.uppercaseKeywords ? s.uppercased() : s.lowercased() }

    func ident(_ s: String) -> String {
        let simple = s.range(of: #"^[A-Z][A-Z0-9_$#]*$"#, options: .regularExpression) != nil && !Keywords.reserved.contains(s.uppercased())
        return simple ? (format.uppercaseKeywords ? s : s.lowercased()) : "\"\(s)\""
    }

    func fieldText(_ f: QBField) -> String {
        guard let t = table(f.table) else { return f.expression }
        return "\(t.alias).\(ident(f.expression))"
    }

    func tableText(_ t: QBTable) -> String {
        if let q = t.subquery {
            let indented = q.components(separatedBy: "\n").map { "         " + $0 }.joined(separator: "\n")
            return "(\n" + indented + "\n     ) " + t.alias
        }
        return (format.qualifyWithOwner && !t.owner.isEmpty ? ident(t.owner) + "." : "") + ident(t.name) + " " + t.alias
    }

    func condition(_ j: QBJoin) -> String {
        guard let l = table(j.left), let r = table(j.right) else { return "" }
        return zip(j.leftColumns, j.rightColumns).map { "\(l.alias).\(ident($0)) = \(r.alias).\(ident($1))" }.joined(separator: " \(kw("and")) ")
    }

    /// Tekst SELECT według modelu i preferencji formatu.
    public func sql() -> String {
        let sep = format.columnPerLine ? ",\n       " : ", "
        let list = fields.isEmpty ? "*" : fields.map { f in fieldText(f) + (f.alias.isEmpty ? "" : " " + f.alias) }.joined(separator: sep)
        var s = kw("select") + (distinct ? " " + kw("distinct") : "") + " " + list
        if !into.trimmingCharacters(in: .whitespaces).isEmpty { s += "\n  " + kw("into") + " " + into }
        var conditions: [String] = []
        if format.ansiJoins {
            // Pierwsza tabela, potem złączenia w kolejności, w jakiej łączą się z już wypisanymi tabelami.
            var placed: [UUID] = []
            var from = ""
            var pending = joins
            for t in tables where !placed.contains(t.id) {
                if placed.isEmpty {
                    from = tableText(t)
                } else if !pending.contains(where: { ($0.left == t.id && placed.contains($0.right)) || ($0.right == t.id && placed.contains($0.left)) }) {
                    from += ",\n     " + tableText(t)
                }
                placed.append(t.id)
                var progress = true
                while progress {
                    progress = false
                    for (i, j) in pending.enumerated() {
                        let lIn = placed.contains(j.left), rIn = placed.contains(j.right)
                        if lIn != rIn, let other = table(lIn ? j.right : j.left) {
                            from += "\n  " + kw(j.kind.rawValue) + " " + tableText(other) + " " + kw("on") + " " + condition(j)
                            placed.append(other.id)
                            pending.remove(at: i)
                            progress = true
                            break
                        } else if lIn && rIn {
                            conditions.append(condition(j))
                            pending.remove(at: i)
                            progress = true
                            break
                        }
                    }
                }
            }
            if !from.isEmpty { s += "\n  " + kw("from") + " " + from }
        } else {
            if !tables.isEmpty { s += "\n  " + kw("from") + " " + tables.map(tableText).joined(separator: ", ") }
            conditions += joins.map(condition)
        }
        let w = whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
        if !w.isEmpty { conditions.append(conditions.isEmpty ? w : "(\(w))") }
        if !conditions.isEmpty { s += "\n " + kw("where") + " " + conditions.joined(separator: "\n   " + kw("and") + " ") }
        let group = fields.filter(\.groupBy)
        if !group.isEmpty { s += "\n " + kw("group by") + " " + group.map(fieldText).joined(separator: ", ") }
        let h = having.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.isEmpty { s += "\n" + kw("having") + " " + h }
        let order = fields.filter { $0.sort != .none }
        if !order.isEmpty {
            s += "\n " + kw("order by") + " " + order.map { fieldText($0) + ($0.sort == .descending ? " " + kw("desc") : "") }.joined(separator: ", ")
        }
        return s
    }

    // MARK: Odczyt istniejącego SELECT (modyfikacja zapytania)

    /// Model z prostego SELECT: lista pól, FROM z tabelami i podzapytaniami (przecinki albo [INNER|LEFT|RIGHT|FULL] JOIN …
    /// ON a.x = b.y), WHERE, GROUP BY, HAVING, ORDER BY. Kolumny tabel z `resolve` (słownik), podzapytań — z `describe`.
    /// Nil — zapytanie spoza tego zakresu (UNION, WITH, CONNECT BY).
    public static func parse(_ sql: String, resolve: (String?, String) -> (owner: String, name: String, columns: [SchemaColumn])?,
                             describe: (String) -> [SchemaColumn] = { _ in [] }) -> QueryModel? {
        var text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast() }
        let ns = text as NSString
        let toks = Lexer(text).tokenize().filter { !$0.isTrivia }
        guard let first = toks.first, ns.substring(with: NSRange(location: first.start, length: first.length)).uppercased() == "SELECT" else { return nil }
        // Klauzule na poziomie 0 nawiasów.
        let clauseWords = ["SELECT", "INTO", "FROM", "WHERE", "GROUP", "HAVING", "ORDER", "UNION", "INTERSECT", "MINUS", "CONNECT", "START", "FETCH", "OFFSET"]
        var depth = 0
        var marks: [(word: String, start: Int, bodyStart: Int)] = []
        var i = 0
        while i < toks.count {
            let t = toks[i]
            if t.kind == .leftParen { depth += 1 } else if t.kind == .rightParen { depth -= 1 }
            let w = ns.substring(with: NSRange(location: t.start, length: t.length)).uppercased()
            if depth == 0, clauseWords.contains(w), t.kind != .quotedIdentifier {
                var bodyStart = t.end
                if (w == "GROUP" || w == "ORDER"), i + 1 < toks.count { bodyStart = toks[i + 1].end; i += 1 }
                marks.append((w, t.start, bodyStart))
            }
            i += 1
        }
        if marks.contains(where: { ["UNION", "INTERSECT", "MINUS", "CONNECT", "START", "FETCH", "OFFSET"].contains($0.word) }) { return nil }
        func body(_ w: String) -> String? {
            guard let k = marks.firstIndex(where: { $0.word == w }) else { return nil }
            let end = k + 1 < marks.count ? marks[k + 1].start : ns.length
            return ns.substring(with: NSRange(location: marks[k].bodyStart, length: end - marks[k].bodyStart)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard var select = body("SELECT"), var from = body("FROM") else { return nil }
        // Podzapytania w FROM (nawiasy najwyższego poziomu zaczynające się od SELECT/WITH) → znaczniki na czas podziału.
        var subqueries: [String] = []
        do {
            let f = from as NSString
            var out = "", depth = 0, start = -1, last = 0
            for i in 0..<f.length {
                let c = f.character(at: i)
                if c == 0x28 { if depth == 0 { start = i }; depth += 1 }
                else if c == 0x29 {
                    depth -= 1
                    if depth == 0, start >= 0 {
                        let inner = f.substring(with: NSRange(location: start + 1, length: i - start - 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let w = inner.split(whereSeparator: \.isWhitespace).first?.uppercased(), w == "SELECT" || w == "WITH" else { return nil }
                        out += f.substring(with: NSRange(location: last, length: start - last)) + " PELIKAN_SUBQ_\(subqueries.count) "
                        subqueries.append(inner)
                        last = i + 1
                    }
                }
            }
            guard depth == 0 else { return nil }
            from = out + f.substring(from: last)
        }
        var m = QueryModel()
        if select.uppercased().hasPrefix("DISTINCT ") { m.distinct = true; select = String(select.dropFirst(9)) }
        m.into = body("INTO") ?? ""
        m.whereClause = body("WHERE") ?? ""
        m.having = body("HAVING") ?? ""

        // FROM: elementy rozdzielone przecinkami; w elemencie ciąg JOIN … ON ….
        var aliasToID: [String: UUID] = [:]
        func addTable(_ spec: String) -> UUID? {
            let words = spec.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let ref = words.first else { return nil }
            if ref.hasPrefix("PELIKAN_SUBQ_"), let n = Int(ref.dropFirst("PELIKAN_SUBQ_".count)), n < subqueries.count {
                let alias = words.count > 1 && words[1].uppercased() != "AS" ? words[1] : words.count > 2 ? words[2] : ""
                let id = m.addSubquery(subqueries[n], alias: alias, columns: describe(subqueries[n]))
                if let t = m.table(id) { aliasToID[t.alias] = id }
                return id
            }
            let parts = ref.split(separator: ".").map { String($0).replacingOccurrences(of: "\"", with: "") }
            guard let found = resolve(parts.count == 2 ? parts[0].uppercased() : nil, (parts.last ?? ref).uppercased()) else { return nil }
            var t = QBTable(owner: found.owner, name: found.name, alias: words.count > 1 && words[1].uppercased() != "AS" ? words[1].lowercased()
                                                                    : words.count > 2 ? words[2].lowercased() : m.uniqueAlias(for: found.name), columns: found.columns)
            t.position = DiagramPoint(16 + Double(m.tables.count % 4) * 232, 16 + Double(m.tables.count / 4) * 220)
            m.tables.append(t)
            aliasToID[t.alias] = t.id
            aliasToID[found.name.lowercased()] = t.id
            return t.id
        }
        let joinRe = try! NSRegularExpression(pattern: #"\s+(INNER\s+JOIN|JOIN|LEFT\s+(?:OUTER\s+)?JOIN|RIGHT\s+(?:OUTER\s+)?JOIN|FULL\s+(?:OUTER\s+)?JOIN)\s+"#, options: .caseInsensitive)
        for element in from.components(separatedBy: ",") {
            let e = element.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
            let matches = joinRe.matches(in: e as String, range: NSRange(location: 0, length: e.length))
            var cursor = 0
            var kinds: [QBJoin.Kind] = []
            var pieces: [String] = []
            for mt in matches {
                pieces.append(e.substring(with: NSRange(location: cursor, length: mt.range.location - cursor)))
                let k = e.substring(with: mt.range(at: 1)).uppercased()
                kinds.append(k.hasPrefix("LEFT") ? .left : k.hasPrefix("RIGHT") ? .right : k.hasPrefix("FULL") ? .full : .inner)
                cursor = NSMaxRange(mt.range)
            }
            pieces.append(e.substring(from: cursor))
            guard addTable(pieces[0].trimmingCharacters(in: .whitespaces)) != nil else { return nil }
            for (k, piece) in zip(kinds, pieces.dropFirst()) {
                let words = piece.split(whereSeparator: \.isWhitespace).map(String.init)
                guard let onIndex = words.firstIndex(where: { $0.uppercased() == "ON" }),
                      let right = addTable(words[..<onIndex].joined(separator: " ")) else { return nil }
                let cond = words[(onIndex + 1)...].joined(separator: " ")
                var lc: [String] = [], rc: [String] = [], leftID: UUID?
                let equalities = cond.replacingOccurrences(of: #"\s+and\s+"#, with: "\u{1}", options: [.regularExpression, .caseInsensitive]).split(separator: "\u{1}").map(String.init)
                for eq in equalities where !eq.isEmpty {
                    let sides = eq.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard sides.count == 2 else { return nil }
                    let a = sides[0].split(separator: "."), b = sides[1].split(separator: ".")
                    guard a.count == 2, b.count == 2, let ida = aliasToID[a[0].lowercased()], let idb = aliasToID[b[0].lowercased()] else { return nil }
                    if idb == right { leftID = ida; lc.append(a[1].uppercased()); rc.append(b[1].uppercased()) } else { leftID = idb; lc.append(b[1].uppercased()); rc.append(a[1].uppercased()) }
                }
                guard let l = leftID else { return nil }
                m.joins.append(QBJoin(left: l, leftColumns: lc, right: right, rightColumns: rc, kind: k))
            }
        }

        // Pola: kolumna z aliasem tabeli (a.kolumna [alias]) albo wyrażenie.
        // Przecinki i nawiasy w literałach ('…', q'[…]'), identyfikatorach "…" i komentarzach nie dzielą listy (tokeny Lexer).
        func splitTop(_ s: String) -> [String] {
            let ns = s as NSString
            var out: [String] = [], from = 0, d = 0
            for t in Lexer(s).tokenize() {
                switch t.kind {
                case .leftParen: d += 1
                case .rightParen: d -= 1
                case .comma where d == 0:
                    out.append(ns.substring(with: NSRange(location: from, length: t.start - from)))
                    from = t.start + t.length
                default: break
                }
            }
            out.append(ns.substring(from: from))
            return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if select != "*" {
            for item in splitTop(select) {
                var words = item.split(whereSeparator: \.isWhitespace).map(String.init)
                var alias = ""
                if words.count >= 2, !item.hasSuffix(")"), words[words.count - 1].range(of: #"^[A-Za-z_][\w$#]*$"#, options: .regularExpression) != nil {
                    alias = words.removeLast()
                    if words.last?.uppercased() == "AS" { words.removeLast() }
                }
                let expr = words.joined(separator: " ")
                let parts = expr.split(separator: ".")
                var f: QBField
                if parts.count == 2, let tid = aliasToID[parts[0].lowercased()], parts[1].range(of: #"^"?[A-Za-z_][\w$#]*"?$"#, options: .regularExpression) != nil {
                    f = QBField(table: tid, expression: parts[1].replacingOccurrences(of: "\"", with: "").uppercased())
                } else {
                    f = QBField(table: nil, expression: expr)
                }
                f.alias = alias
                m.fields.append(f)
            }
        }
        func matchField(_ e: String) -> Int? {
            let s = e.trimmingCharacters(in: .whitespaces)
            return m.fields.firstIndex { m.fieldText($0).lowercased() == s.lowercased() || $0.expression.lowercased() == s.lowercased() || (!$0.alias.isEmpty && $0.alias.lowercased() == s.lowercased()) }
        }
        for g in splitTop(body("GROUP") ?? "") {
            if let i = matchField(g) { m.fields[i].groupBy = true } else { return nil }
        }
        for o in splitTop(body("ORDER") ?? "") {
            var w = o.split(whereSeparator: \.isWhitespace).map(String.init)
            var sort = QBField.Sort.ascending
            if let last = w.last?.uppercased(), last == "DESC" || last == "ASC" { sort = last == "DESC" ? .descending : .ascending; w.removeLast() }
            if let i = matchField(w.joined(separator: " ")) { m.fields[i].sort = sort } else { return nil }
        }
        return m
    }
}
