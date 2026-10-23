import Foundation
import PelikanDB
import PelikanSQL

/// Element listy podpowiedzi Code Assistant (UG 25.4).
public struct CompletionItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case column, table, view, synonym, package, procedure, function, sequence, type, trigger, schema, object
        case variable, constant, parameter, cursor, localType, exception, field, alias, keyword, pseudoColumn, databaseLink
    }
    public var label: String
    public var insertText: String
    public var kind: Kind
    public var detail: String
    public var id: String { "\(kind.rawValue):\(label)" }

    public init(label: String, insertText: String? = nil, kind: Kind, detail: String = "") {
        self.label = label; self.insertText = insertText ?? label; self.kind = kind; self.detail = detail
    }
}

/// Wynik podpowiedzi: zakres tekstu do zastąpienia i elementy (już przefiltrowane prefiksem).
public struct CompletionResult: Sendable, Hashable {
    public var replaceRange: Range<Int>
    public var prefix: String
    public var items: [CompletionItem]
}

/// Code Assistant (UG 25.4, PD-CA-001…004): elementy po `obiekt.` (kolumny tabeli i aliasu, elementy pakietu,
/// pola rekordu, %ROWTYPE, kursora, rekordu pętli, `:new`/`:old`, NEXTVAL/CURRVAL, obiekty schematu), a bez
/// kwalifikatora — deklaracje w zasięgu, aliasy i kolumny tabel instrukcji, obiekty schematu i słowa kluczowe.
@MainActor
public enum CodeAssistant {
    /// Minimalna liczba znaków prefiksu dla obiektów schematu i słów kluczowych bez kwalifikatora.
    public static let minimumPrefix = 1

    public static func complete(text: String, offset: Int, metadata: MetadataProvider?) async -> CompletionResult? {
        let c = CompletionContext.analyze(text, offset: offset)
        guard !c.inLiteralOrComment else { return nil }
        var items: [CompletionItem] = []
        if c.afterAt {
            items = (try? await metadata?.databaseLinks())?.map { CompletionItem(label: $0, kind: .databaseLink) } ?? []
        } else if !c.qualifier.isEmpty {
            items = await members(of: c, metadata: metadata)
        } else {
            items = await unqualified(c, metadata: metadata)
        }
        let filtered = filter(items, prefix: c.prefix)
        guard !filtered.isEmpty else { return nil }
        return CompletionResult(replaceRange: c.replaceRange, prefix: c.prefix, items: filtered.map { applyCase($0, prefix: c.prefix) })
    }

    /// Filtr „zaczyna się od” bez rozróżniania wielkości liter, bez duplikatów, kolejność źródeł zachowana.
    static func filter(_ items: [CompletionItem], prefix: String) -> [CompletionItem] {
        let p = prefix.uppercased()
        var seen = Set<String>()
        return items.filter { i in
            guard p.isEmpty || i.label.uppercased().hasPrefix(p) else { return false }
            return seen.insert(i.label.uppercased() + "|" + i.kind.rawValue).inserted
        }
    }

    /// Wielkość liter wstawianego tekstu jak we wpisanym prefiksie (małe → małe, wielkie → wielkie); bez prefiksu —
    /// nazwy słownikowe małymi, deklaracje lokalne w oryginalnej postaci (D23).
    static func applyCase(_ item: CompletionItem, prefix: String) -> CompletionItem {
        var i = item
        let local: Set<CompletionItem.Kind> = [.variable, .constant, .parameter, .cursor, .localType, .exception, .alias]
        if local.contains(i.kind), prefix.isEmpty { return i }
        let hasLetters = prefix.contains { $0.isLetter }
        if hasLetters, prefix == prefix.uppercased() {
            i.insertText = i.insertText.uppercased()
        } else if i.insertText == i.insertText.uppercased() {
            // Nazwy wymagające cudzysłowu (małe litery w słowniku) pozostają bez zmian.
            i.insertText = i.insertText.lowercased()
        }
        return i
    }

    // MARK: Po kropce

    static func members(of c: CompletionContext, metadata m: MetadataProvider?) async -> [CompletionItem] {
        let q = c.qualifier
        // :new / :old w wyzwalaczu — kolumny tabeli wyzwalacza.
        if c.bindQualifier, ["NEW", "OLD"].contains(q.last ?? ""), let t = c.triggerTable {
            return await columnItems(owner: t.owner, name: t.name, metadata: m)
        }
        if q.count == 1 {
            let name = q[0]
            // 1. Alias albo nazwa tabeli w instrukcji.
            if let t = c.tables.first(where: { $0.matches(name) }) {
                if let sub = t.subquery { return selectItems(sub, context: c) }
                return await columnItems(owner: t.owner, name: t.name, metadata: m)
            }
            // 2. Rekord pętli FOR.
            if let src = c.loopRecords[name] {
                return await recordSource(src, context: c, metadata: m)
            }
            // 3. Deklaracja lokalna (zmienna rekordowa, %ROWTYPE, kursor, obiekt).
            if let d = c.declarations.first(where: { $0.name.uppercased() == name }) {
                let r = await declarationMembers(d, context: c, metadata: m)
                if !r.isEmpty { return r }
            }
        }
        // 4. Obiekt bazy: [schemat.]obiekt albo schemat.
        guard let m else { return [] }
        let owner = q.count >= 2 ? q[q.count - 2] : nil
        if let o = try? await m.resolve(owner: owner, name: q.last ?? "") {
            return await objectMembers(o, metadata: m)
        }
        if q.count == 1, let names = try? await m.objectNames(owner: q[0]), !names.isEmpty {
            return names.map { CompletionItem(label: $0.name, kind: kind(ofObjectType: $0.type), detail: $0.type.lowercased()) }
        }
        return []
    }

    static func objectMembers(_ o: DBObject, metadata m: MetadataProvider) async -> [CompletionItem] {
        switch o.type {
        case .table, .view, .materializedView:
            return ((try? await m.columns(of: o)) ?? []).map { CompletionItem(label: $0.name, kind: .column, detail: $0.detail) }
        case .sequence:
            return [CompletionItem(label: "NEXTVAL", kind: .pseudoColumn), CompletionItem(label: "CURRVAL", kind: .pseudoColumn)]
        case .package, .type:
            let children = (try? await m.children(of: o)) ?? []
            return children.filter { $0.kind == .subprogram || $0.kind == .attribute }.map {
                CompletionItem(label: $0.name, kind: $0.kind == .attribute ? .field : .procedure, detail: $0.detail)
            }
        default:
            return []
        }
    }

    static func columnItems(owner: String?, name: String, metadata m: MetadataProvider?) async -> [CompletionItem] {
        guard let m, let o = try? await m.resolve(owner: owner, name: name) else { return [] }
        return await objectMembers(o, metadata: m)
    }

    /// Kolumny z listy SELECT podzapytania (alias albo nazwa kolumny).
    static func selectItems(_ query: String, context: CompletionContext) -> [CompletionItem] {
        SelectListParser.items(query).compactMap { ($0.alias ?? $0.column).map { CompletionItem(label: $0, kind: .field) } }
    }

    /// Pola rekordu z kursora (nazwa) albo zapytania.
    static func recordSource(_ src: String, context c: CompletionContext, metadata m: MetadataProvider?) async -> [CompletionItem] {
        if src.uppercased().contains("SELECT") { return await queryFields(src, metadata: m) }
        if let cur = c.declarations.first(where: { $0.kind == .cursor && $0.name.uppercased() == src }) {
            return await cursorFields(cur, context: c, metadata: m)
        }
        return []
    }

    static func cursorFields(_ cur: OutlineNode, context c: CompletionContext, metadata m: MetadataProvider?) async -> [CompletionItem] {
        guard let q = c.cursorQueries[cur.name.uppercased()] else { return [] }
        return await queryFields(q, metadata: m)
    }

    /// Pola wyniku zapytania: nazwy z listy SELECT, a dla `*` / `t.*` — kolumny tabel z FROM.
    static func queryFields(_ query: String, metadata m: MetadataProvider?) async -> [CompletionItem] {
        var out: [CompletionItem] = []
        let ctx = CompletionContext.analyze(query, offset: (query as NSString).length)
        for item in SelectListParser.items(query) {
            if item.isStar {
                for t in ctx.tables where item.qualifier == nil || t.matches(item.qualifier!) {
                    out += await columnItems(owner: t.owner, name: t.name, metadata: m).map { var x = $0; x.kind = .field; return x }
                }
            } else if let n = item.alias ?? item.column {
                out.append(CompletionItem(label: n, kind: .field))
            }
        }
        return out
    }

    /// Elementy zmiennej: `tabela%ROWTYPE`, `kursor%ROWTYPE`, typ rekordowy lokalny, typ obiektowy bazy.
    static func declarationMembers(_ d: OutlineNode, context c: CompletionContext, metadata m: MetadataProvider?) async -> [CompletionItem] {
        if d.kind == .cursor { return await cursorFields(d, context: c, metadata: m) }
        let type = d.detail.trimmingCharacters(in: .whitespaces)
        let upper = type.uppercased()
        if upper.hasSuffix("%ROWTYPE") {
            let base = String(upper.dropLast("%ROWTYPE".count))
            if let cur = c.declarations.first(where: { $0.kind == .cursor && $0.name.uppercased() == base }) {
                return await cursorFields(cur, context: c, metadata: m)
            }
            let parts = base.split(separator: ".").map(String.init)
            return await columnItems(owner: parts.count > 1 ? parts[0] : nil, name: parts.last ?? base, metadata: m)
        }
        if let decl = c.typeDeclarations[upper] {
            return recordFields(decl).map { CompletionItem(label: $0.name, kind: .field, detail: $0.type) }
        }
        // Typ obiektowy bazy.
        guard let m, !upper.isEmpty, !upper.contains("%"), let o = try? await m.resolve(owner: nil, name: upper), o.type == .type else { return [] }
        return await objectMembers(o, metadata: m)
    }

    /// Pola typu `TYPE t IS RECORD (pole typ, …)`.
    static func recordFields(_ declaration: String) -> [(name: String, type: String)] {
        guard let open = declaration.range(of: "("), declaration.uppercased().contains("RECORD") else { return [] }
        var depth = 0
        var parts: [String] = [""]
        for ch in declaration[open.upperBound...] {
            if ch == "(" { depth += 1 }
            if ch == ")" { if depth == 0 { break }; depth -= 1 }
            if ch == ",", depth == 0 { parts.append("") } else { parts[parts.count - 1].append(ch) }
        }
        return parts.compactMap { p in
            let words = p.split(whereSeparator: { $0.isWhitespace })
            guard let n = words.first else { return nil }
            return (String(n), words.dropFirst().joined(separator: " "))
        }
    }

    // MARK: Bez kwalifikatora

    static func unqualified(_ c: CompletionContext, metadata m: MetadataProvider?) async -> [CompletionItem] {
        var out: [CompletionItem] = []
        for d in c.declarations {
            out.append(CompletionItem(label: d.name, kind: declarationKind(d.kind), detail: d.detail))
        }
        for (name, _) in c.loopRecords.sorted(by: { $0.key < $1.key }) { out.append(CompletionItem(label: name.lowercased(), kind: .variable, detail: "record")) }
        if c.inSQLStatement {
            for t in c.tables {
                if let a = t.alias { out.append(CompletionItem(label: a.lowercased(), kind: .alias, detail: t.name.isEmpty ? "(select …)" : t.name)) }
            }
            // Kolumny tabel instrukcji bez aliasu (UG 25.4: kolumny tabel DML).
            for t in c.tables where t.subquery == nil {
                out += await columnItems(owner: t.owner, name: t.name, metadata: m)
            }
        }
        guard c.prefix.count >= minimumPrefix else { return out }
        if let m, let schema = try? await m.currentSchema(), let names = try? await m.objectNames(owner: schema) {
            let p = c.prefix.uppercased()
            out += names.lazy.filter { $0.name.hasPrefix(p) }.prefix(300).map {
                CompletionItem(label: $0.name, kind: kind(ofObjectType: $0.type), detail: $0.type.lowercased())
            }
        }
        let p = c.prefix.uppercased()
        out += Keywords.reserved.union(Keywords.plsql).union(Keywords.sql).filter { $0.hasPrefix(p) }.sorted().map { CompletionItem(label: $0, kind: .keyword) }
        return out
    }

    static func declarationKind(_ k: OutlineNode.Kind) -> CompletionItem.Kind {
        switch k {
        case .constant: .constant
        case .parameter: .parameter
        case .cursor: .cursor
        case .typeDeclaration: .localType
        case .exception: .exception
        case .procedure: .procedure
        case .function: .function
        default: .variable
        }
    }

    static func kind(ofObjectType t: String) -> CompletionItem.Kind {
        switch t {
        case "TABLE": .table
        case "VIEW", "MATERIALIZED VIEW": .view
        case "SYNONYM": .synonym
        case "PACKAGE": .package
        case "PROCEDURE": .procedure
        case "FUNCTION": .function
        case "SEQUENCE": .sequence
        case "TYPE": .type
        case "TRIGGER": .trigger
        default: .object
        }
    }
}
