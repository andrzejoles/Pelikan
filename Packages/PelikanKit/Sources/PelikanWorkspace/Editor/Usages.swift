import Foundation
import PelikanDB
import PelikanSQL

/// Użycie obiektu albo kolumny (DG-USE-001): zależność w bazie, linia kodu obiektu (źródło, PL/Scope), linia okna albo pliku.
public struct UsageHit: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable { case dependency, source, plscope, document, file }
    public var kind: Kind
    /// Obiekt bazy (zależność, źródło, PL/Scope).
    public var owner: String?
    public var name: String?
    public var type: String?
    public var line: Int
    public var text: String
    public var fileURL: URL?
    public var document: DocumentID?
    /// Tytuł do listy (obiekt, plik albo okno).
    public var title: String
    public var id: String { "\(kind.rawValue):\(title):\(line):\(text.prefix(40))" }
}

/// Wyszukiwanie użyć: w bazie (ALL_DEPENDENCIES, ALL_SOURCE obiektów zależnych, ALL_IDENTIFIERS z PL/Scope) i w tekstach
/// (otwarte okna, pliki projektu) — tylko w identyfikatorach, bez komentarzy i literałów.
public enum UsageFinder {
    /// Linie tekstu, w których występuje identyfikator `name` (tokeny — bez komentarzy i literałów). Z właścicielem:
    /// nazwa kwalifikowana innym schematem (`INNY.NAZWA`) nie jest użyciem; kolumna — dowolny kwalifikator (alias).
    public static func lines(in text: String, name: String, owner: String? = nil) -> [(line: Int, text: String)] {
        let up = name.uppercased(), o = owner?.uppercased()
        let tokens = SQLToken.significant(text)
        let ns = text as NSString
        var lines = Set<Int>()
        var counter = LineCounter(ns)
        for (i, tk) in tokens.enumerated() where tk.isWord && tk.name == up {
            if let o, i >= 2, tokens[i - 1].kind == .dot, tokens[i - 2].name != o { continue }
            lines.insert(counter.line(at: tk.start))
        }
        let all = text.components(separatedBy: "\n")
        return lines.sorted().map { ($0, $0 - 1 < all.count ? all[$0 - 1].trimmingCharacters(in: .whitespaces) : "") }
    }

    /// Linie poleceń SQL odwołujących się do tabeli `table`, w których występuje kolumna `column`.
    public static func columnLines(in text: String, table: String, column: String) -> [(line: Int, text: String)] {
        let t = SQLToken.significant(text), tab = table.uppercased(), col = column.uppercased()
        let ns = text as NSString
        var lines = Set<Int>()
        var counter = LineCounter(ns)
        for st in NameResolver.statements(t) where NameResolver.relations(t, st).contains(where: { $0.name == tab }) {
            for tk in t[st] where tk.isWord && tk.name == col {
                lines.insert(counter.line(at: tk.start))
            }
        }
        let all = text.components(separatedBy: "\n")
        return lines.sorted().map { ($0, $0 - 1 < all.count ? all[$0 - 1].trimmingCharacters(in: .whitespaces) : "") }
    }

    static func find(_ text: String, name: String, owner: String?, column: String?) -> [(line: Int, text: String)] {
        column.map { columnLines(in: text, table: name, column: $0) } ?? lines(in: text, name: name, owner: owner)
    }

    /// Użycia w otwartych oknach i plikach (bez bazy); pliki czytane poza wątkiem głównym, w kodowaniu projektu (D55).
    @MainActor
    public static func inTexts(name: String, owner: String? = nil, column: String? = nil, documents: [Document], files: [URL],
                               encoding: @escaping @Sendable (URL) -> String.Encoding? = { _ in nil }) async -> [UsageHit] {
        var out: [UsageHit] = []
        var seen = Set<URL>()
        for d in documents {
            if let u = d.fileURL { seen.insert(u.standardizedFileURL) }
            for (line, text) in find(d.text, name: name, owner: owner, column: column) {
                out.append(UsageHit(kind: .document, line: line, text: text, fileURL: d.fileURL, document: d.id, title: d.fullTitle))
            }
        }
        let rest = files.filter { !seen.contains($0.standardizedFileURL) }
        out += await Task.detached { inFiles(name: name, owner: owner, column: column, files: rest, encoding: encoding) }.value
        return out
    }

    static func inFiles(name: String, owner: String?, column: String?, files: [URL], encoding: (URL) -> String.Encoding?) -> [UsageHit] {
        var out: [UsageHit] = []
        for f in files {
            guard let data = try? Data(contentsOf: f) else { continue }
            let text = TextFileCodec.decode(data, preferred: encoding(f)).text
            for (line, t) in find(text, name: name, owner: owner, column: column) {
                out.append(UsageHit(kind: .file, line: line, text: t, fileURL: f, title: f.lastPathComponent))
            }
        }
        return out
    }

    /// Użycia w bazie: obiekty zależne, linie ich kodu z nazwą (i kolumną) oraz identyfikatory PL/Scope.
    public static func inDatabase(owner: String, name: String, column: String? = nil, session s: any DatabaseSession) async throws -> [UsageHit] {
        let b = [BindVariable(name: "o", value: .text(owner.uppercased())), BindVariable(name: "n", value: .text(name.uppercased()))]
        var out: [UsageHit] = []
        if column == nil {
            let (_, deps) = try await s.queryAll("""
                select owner, name, type from all_dependencies where referenced_owner = :o and referenced_name = :n
                 group by owner, name, type order by owner, name, type
                """, binds: b, limit: 5000)
            for r in deps {
                let o = r[0].displayText ?? "", n = r[1].displayText ?? "", t = r[2].displayText ?? ""
                out.append(UsageHit(kind: .dependency, owner: o, name: n, type: t, line: 0, text: t, title: "\(o).\(n)"))
            }
        }
        let needle = (column ?? name).uppercased()
        let (_, src) = try await s.queryAll("""
            select s.owner, s.name, s.type, s.line, rtrim(s.text, chr(10)) from all_source s
              join (select distinct owner, name, type from all_dependencies where referenced_owner = :o and referenced_name = :n) d
                on s.owner = d.owner and s.name = d.name and s.type = d.type
             where upper(s.text) like '%' || :k || '%' and rownum <= 2000
            """, binds: b + [BindVariable(name: "k", value: .text(needle))], limit: 2000)
        for r in src {
            let text = r[4].displayText ?? ""
            // Linia musi zawierać identyfikator (nie tylko fragment innej nazwy, komentarz albo literał).
            guard !lines(in: text, name: needle).isEmpty else { continue }
            out.append(UsageHit(kind: .source, owner: r[0].displayText, name: r[1].displayText, type: r[2].displayText,
                                line: Int(r[3].displayText ?? "") ?? 0, text: text.trimmingCharacters(in: .whitespaces),
                                title: "\(r[0].displayText ?? "").\(r[1].displayText ?? "")"))
        }
        // PL/Scope (gdy kod skompilowano z PLSCOPE_SETTINGS='IDENTIFIERS:ALL'): odwołania do nazwy obiektu albo kolumny
        // w obiektach zależnych od niego (nie każdy identyfikator o tej nazwie w bazie).
        if let (_, ids) = try? await s.queryAll("""
            select i.owner, i.object_name, i.object_type, i.line, i.usage from all_identifiers i
              join (select distinct owner, name, type from all_dependencies where referenced_owner = :o and referenced_name = :n) d
                on i.owner = d.owner and i.object_name = d.name and i.object_type = d.type
             where i.name = :k and i.usage in ('REFERENCE', 'CALL', 'ASSIGNMENT') and rownum <= 2000
            """, binds: b + [BindVariable(name: "k", value: .text(needle))], limit: 2000) {
            for r in ids {
                let hit = UsageHit(kind: .plscope, owner: r[0].displayText, name: r[1].displayText, type: r[2].displayText,
                                   line: Int(r[3].displayText ?? "") ?? 0, text: r[4].displayText ?? "",
                                   title: "\(r[0].displayText ?? "").\(r[1].displayText ?? "")")
                if !out.contains(where: { $0.kind == .source && $0.title == hit.title && $0.line == hit.line }) { out.append(hit) }
            }
        }
        return out
    }
}

// MARK: - Refaktoryzacja (DG-REF-001)

/// Zmiana tekstu okna albo pliku proponowana przez refaktoryzację (podgląd różnic przed zastosowaniem).
public struct RefactoringChange: Sendable, Hashable, Identifiable {
    public enum Target: Sendable, Hashable { case document(DocumentID), file(URL) }
    public var target: Target
    public var title: String
    public var before: String
    public var after: String
    /// Liczba zamienionych wystąpień.
    public var occurrences: Int
    public var id: String {
        switch target {
        case .document(let d): "doc:\(d)"
        case .file(let u): "file:\(u.path)"
        }
    }
}

/// Plan refaktoryzacji: zmiany tekstów i opcjonalny skrypt DDL (nie wykonywany — do okna SQL).
public struct RefactoringPlan: Sendable, Hashable {
    public var title: String
    public var changes: [RefactoringChange]
    public var ddl: String?
}

public enum Refactoring {
    static func isIdentifier(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z][A-Za-z0-9_$#]{0,127}$"#, options: .regularExpression) != nil
    }

    /// Zamiana tokenów identyfikatora (bez komentarzy i literałów) spełniających warunek; zwraca nowy tekst i liczbę zmian.
    static func replace(_ text: String, newName: String, where match: ([SQLToken], Int) -> Bool) -> (String, Int) {
        let tokens = SQLToken.significant(text)
        let ns = NSMutableString(string: text)
        var n = 0
        for (i, tk) in tokens.enumerated().reversed() where match(tokens, i) {
            ns.replaceCharacters(in: NSRange(location: tk.start, length: tk.end - tk.start), with: newName)
            n += 1
        }
        return (ns as String, n)
    }

    /// Zmiana nazwy zmiennej, stałej albo parametru pod kursorem w jego zakresie (podprogram/blok); bez nazw po kropce
    /// (pola innych obiektów) i bez notacji nazwanej `nazwa =>` (parametr wołanego podprogramu).
    public static func renameLocal(in text: String, at offset: Int, to newName: String) throws -> (text: String, occurrences: Int) {
        guard isIdentifier(newName) else { throw CommandError.invalidArgument("newName", L10n.tr("niepoprawny identyfikator")) }
        let tokens = SQLToken.significant(text)
        guard let tk = tokens.first(where: { $0.isWord && $0.start <= offset && offset <= $0.end }) else {
            throw CommandError.notAvailable(L10n.tr("Kursor nie stoi na identyfikatorze"))
        }
        let outline = PLSQLOutline.parse(text)
        guard let decl = PLSQLOutline.declaration(of: tk.name, at: offset, in: outline), [.variable, .constant, .parameter].contains(decl.kind) else {
            throw CommandError.notAvailable(L10n.tr("\(tk.text) nie jest zmienną ani parametrem w tym miejscu"))
        }
        let scope = PLSQLOutline.path(at: decl.nameOffset, in: outline).last?.range ?? 0..<(text as NSString).length
        let up = tk.name, newUp = newName.uppercased()
        // Deklaracja widoczna w pozycji tylko w zakresach ją obejmujących (bez szukania w całym tekście).
        func visible(_ name: String, at offset: Int) -> OutlineNode? {
            for s in PLSQLOutline.path(at: offset, in: outline).reversed() {
                if let d = s.children.first(where: { $0.name.uppercased() == name }) { return d }
            }
            return nil
        }
        func renamed(_ t: [SQLToken], _ i: Int) -> Bool {
            let x = t[i]
            guard x.isWord, x.name == up, scope.contains(x.start) else { return false }
            if i > 0, t[i - 1].kind == .dot { return false }
            if i + 1 < t.count, t[i + 1].text == "=>" { return false }
            // Zagnieżdżony blok z własną deklaracją o tej nazwie — to inna zmienna.
            return visible(up, at: x.start)?.nameOffset == decl.nameOffset
        }
        // Nowa nazwa nie może przesłonić ani zostać przesłonięta: deklaracja o tej nazwie widoczna w którymkolwiek
        // miejscu zmiany albo ta nazwa użyta już w zakresie (np. kolumna albo zmienna zewnętrzna) zmieniłaby znaczenie.
        if newUp != up {
            let tokens = SQLToken.significant(text)
            let clash = tokens.indices.contains { i in renamed(tokens, i) && visible(newUp, at: tokens[i].start) != nil }
                || tokens.indices.contains { i in tokens[i].isWord && tokens[i].name == newUp && scope.contains(tokens[i].start)
                    && !(i > 0 && tokens[i - 1].kind == .dot) && !(i + 1 < tokens.count && tokens[i + 1].text == "=>") }
            if clash { throw CommandError.notAvailable(L10n.tr("Nazwa \(newName) jest już używana w tym zakresie — zmiana nazwy zmieniłaby znaczenie kodu")) }
        }
        return replace(text, newName: newName, where: renamed)
    }

    /// Zmiana nazwy obiektu w tekstach (okna i pliki): `NAZWA` i `WŁAŚCICIEL.NAZWA`, bez innych kwalifikowanych nazw.
    public static func renameObject(_ name: String, owner: String?, to newName: String, texts: [(RefactoringChange.Target, String, String)]) throws -> [RefactoringChange] {
        guard isIdentifier(newName) else { throw CommandError.invalidArgument("newName", L10n.tr("niepoprawny identyfikator")) }
        let up = name.uppercased(), o = owner?.uppercased()
        return texts.compactMap { target, title, text in
            let (after, n) = replace(text, newName: newName) { t, i in
                let x = t[i]
                guard x.isWord, x.name == up else { return false }
                if i > 0, t[i - 1].kind == .dot {
                    // Kwalifikowana: tylko właściciel obiektu (albo dowolny, gdy właściciel nieznany).
                    guard i >= 2, t[i - 2].isWord else { return false }
                    if i >= 3, t[i - 3].kind == .dot { return false }
                    return o == nil || t[i - 2].name == o
                }
                // NAZWA.coś: nazwa obiektu jako kwalifikator (pakiet.procedura, tabela.kolumna) — też zmieniamy.
                return true
            }
            return n > 0 ? RefactoringChange(target: target, title: title, before: text, after: after, occurrences: n) : nil
        }
    }

    /// Skrypt DDL zmiany nazwy w bazie (do przejrzenia i wykonania przez użytkownika — Pelikan go nie wykonuje).
    public static func renameDDL(owner: String, name: String, type: DBObjectType, newName: String, column: String? = nil) -> String? {
        let q = "\(ResultExporter.identifier(owner.uppercased())).\(ResultExporter.identifier(name.uppercased()))"
        if let column {
            return "alter table \(q) rename column \(ResultExporter.identifier(column.uppercased())) to \(ResultExporter.identifier(newName.uppercased()));"
        }
        switch type {
        case .table: return "alter table \(q) rename to \(ResultExporter.identifier(newName.uppercased()));"
        case .view, .sequence, .synonym: return "rename \(ResultExporter.identifier(name.uppercased())) to \(ResultExporter.identifier(newName.uppercased()));"
        case .index: return "alter index \(q) rename to \(ResultExporter.identifier(newName.uppercased()));"
        default: return nil
        }
    }
}

extension Workspace {
    /// Zastosowanie planu refaktoryzacji: teksty okien (z historią lokalną) i pliki; okno z DDL bez wykonania.
    @discardableResult
    public func apply(_ plan: RefactoringPlan) throws -> Int {
        // Plik nie zmienia po cichu kodowania (D55): znak spoza kodowania któregokolwiek pliku blokuje całą zmianę,
        // zanim cokolwiek zostanie zmienione.
        for c in plan.changes {
            guard case .file(let url) = c.target, let data = try? Data(contentsOf: url) else { continue }
            let (text, format) = TextFileCodec.decode(data, preferred: projectEncoding(for: url))
            guard text == c.before, TextFileCodec.encode(c.after, format: format) == nil else { continue }
            let bad = TextFileCodec.firstUnencodable(c.after, encoding: format.encoding)
            let error = TextFileError.unencodable(line: bad?.line ?? 0, column: bad?.column ?? 0, character: bad.map { String($0.character) } ?? "?",
                                                  encoding: format.displayName.components(separatedBy: " ").first ?? "")
            throw CommandError.notAvailable(L10n.tr("Plik \(url.lastPathComponent): \(error.localizedDescription)"))
        }
        var n = 0
        for c in plan.changes {
            switch c.target {
            case .document(let id):
                guard let d = documents.first(where: { $0.id == id }), d.text == c.before else { continue }
                recordHistory(d, text: c.before, label: L10n.tr("przed: \(plan.title)"))
                d.text = c.after
                n += 1
            case .file(let url):
                guard let data = try? Data(contentsOf: url) else { continue }
                let (text, format) = TextFileCodec.decode(data, preferred: projectEncoding(for: url))
                guard text == c.before, let encoded = TextFileCodec.encode(c.after, format: format) else { continue }
                localHistory.record(key: LocalHistory.key(file: url), title: url.lastPathComponent, text: text, label: L10n.tr("przed: \(plan.title)"))
                try encoded.write(to: url, options: .atomic)
                n += 1
            }
        }
        if let ddl = plan.ddl {
            let d = newDocument(.sql, text: ddl)
            d.customTitle = L10n.tr("Zmiana nazwy w bazie")
        }
        return n
    }
}
