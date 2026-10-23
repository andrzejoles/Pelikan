import Foundation
import PelikanSQL

/// Błąd refaktoryzacji (komunikat dla użytkownika).
public struct RefactoringError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Refaktoryzacje kodu PL/SQL (PD-CA-014): wydzielenie stałej lokalnej i globalnej, wydzielenie procedury (parametry
/// z używanych deklaracji), zamiana przypisania na inicjalizację. Zmiana nazwy — `edit.refactorRename` (DG-REF-001).
public enum CodeRefactoring {
    static let containerKinds: [OutlineNode.Kind] = [.procedure, .function, .block, .trigger]

    /// Najgłębszy podprogram albo blok obejmujący pozycję.
    static func container(at offset: Int, in nodes: [OutlineNode], kinds: [OutlineNode.Kind] = containerKinds) -> OutlineNode? {
        for n in nodes where n.range.contains(offset) || n.range.upperBound == offset {
            if let inner = container(at: offset, in: n.children, kinds: kinds) { return inner }
            if kinds.contains(n.kind) { return n }
        }
        return nil
    }

    /// Słowo BEGIN ciała jednostki (poza zagnieżdżonymi podprogramami) i czy jednostka ma sekcję deklaracji.
    static func bodyBegin(of c: OutlineNode, tokens: [SQLToken]) -> (begin: SQLToken, hasDeclare: Bool)? {
        let nested = c.children.filter { $0.isContainer }.map(\.range)
        let own = tokens.filter { t in c.range.contains(t.start) && !nested.contains { $0.contains(t.start) } }
        guard let begin = own.first(where: { $0.upper == "BEGIN" }) else { return nil }
        let first = own.first
        return (begin, !(c.kind == .block && first?.upper == "BEGIN"))
    }

    static func lineStart(_ offset: Int, _ ns: NSString) -> Int { ns.lineRange(for: NSRange(location: offset, length: 0)).location }

    static func indent(atLineOf offset: Int, _ ns: NSString) -> String {
        let s = lineStart(offset, ns)
        return String(ns.substring(from: s).prefix { $0 == " " || $0 == "\t" })
    }

    static func checkName(_ name: String) throws -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard n.range(of: #"^[A-Za-z][A-Za-z0-9_$#]{0,127}$"#, options: .regularExpression) != nil, !Keywords.reserved.union(Keywords.plsql).contains(n.uppercased()) else {
            throw RefactoringError(L10n.tr("Niepoprawna nazwa: \(name)"))
        }
        return n
    }

    /// Typ stałej z wyrażenia: liczba → NUMBER, literał tekstowy → VARCHAR2(długość), DATE '…' → DATE.
    static func inferType(_ expr: String) -> String? {
        let e = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.range(of: #"^-?\d+(\.\d+)?([eE][+-]?\d+)?$"#, options: .regularExpression) != nil { return "NUMBER" }
        if e.hasPrefix("'"), e.hasSuffix("'"), e.count >= 2 { return "VARCHAR2(\(max(1, e.dropFirst().dropLast().replacingOccurrences(of: "''", with: "'").utf8.count)))" }
        if e.uppercased().hasPrefix("DATE '") { return "DATE" }
        if e.uppercased().hasPrefix("TIMESTAMP '") { return "TIMESTAMP" }
        return nil
    }

    static func selectedExpression(_ text: String, _ selection: Range<Int>) throws -> String {
        let ns = text as NSString
        guard !selection.isEmpty, selection.upperBound <= ns.length else { throw RefactoringError(L10n.tr("Zaznacz wyrażenie")) }
        let expr = ns.substring(with: NSRange(location: selection.lowerBound, length: selection.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty, !expr.contains(";") else { throw RefactoringError(L10n.tr("Zaznacz wyrażenie (bez średnika)")) }
        return expr
    }

    /// Wstawia deklarację przed BEGIN ciała (w bloku bez DECLARE — razem z DECLARE) i zastępuje zaznaczenie tekstem.
    static func insertDeclaration(_ declaration: String, in text: String, container c: OutlineNode, replacing selection: Range<Int>,
                                  with replacement: String) throws -> TextEdit {
        let ns = text as NSString
        let tokens = SQLToken.significant(text)
        guard let body = bodyBegin(of: c, tokens: tokens), body.begin.start <= selection.lowerBound else {
            throw RefactoringError(L10n.tr("Zaznaczenie musi być w ciele podprogramu albo bloku (po BEGIN)"))
        }
        let at = lineStart(body.begin.start, ns)
        let ind = indent(atLineOf: body.begin.start, ns)
        let block = (body.hasDeclare ? "" : ind + "DECLARE\n") + ind + "  " + declaration + "\n"
        let m = NSMutableString(string: text)
        m.replaceCharacters(in: NSRange(location: selection.lowerBound, length: selection.count), with: replacement)
        m.insert(block, at: at)
        let pos = selection.lowerBound + (block as NSString).length
        return TextEdit(text: m as String, selection: pos..<(pos + (replacement as NSString).length))
    }

    /// Wydziela zaznaczone wyrażenie do stałej lokalnej podprogramu lub bloku.
    public static func extractLocalConstant(_ text: String, selection: Range<Int>, name: String, type: String? = nil) throws -> TextEdit {
        let expr = try selectedExpression(text, selection)
        let n = try checkName(name)
        guard let t = type.flatMap({ $0.isEmpty ? nil : $0 }) ?? inferType(expr) else { throw RefactoringError(L10n.tr("Podaj typ stałej")) }
        guard let c = container(at: selection.lowerBound, in: PLSQLOutline.parse(text)) else {
            throw RefactoringError(L10n.tr("Zaznaczenie nie jest w podprogramie ani bloku PL/SQL"))
        }
        return try insertDeclaration("\(n) CONSTANT \(t) := \(expr);", in: text, container: c, replacing: selection, with: n)
    }

    /// Wydziela zaznaczone wyrażenie do stałej pakietu (na początku specyfikacji albo ciała pakietu).
    public static func extractGlobalConstant(_ text: String, selection: Range<Int>, name: String, type: String? = nil) throws -> TextEdit {
        let expr = try selectedExpression(text, selection)
        let n = try checkName(name)
        guard let t = type.flatMap({ $0.isEmpty ? nil : $0 }) ?? inferType(expr) else { throw RefactoringError(L10n.tr("Podaj typ stałej")) }
        guard let pkg = PLSQLOutline.parse(text).first(where: { [.package, .packageBody].contains($0.kind) && $0.range.contains(selection.lowerBound) }) else {
            throw RefactoringError(L10n.tr("Stała globalna wymaga pakietu"))
        }
        let ns = text as NSString
        guard let isAs = SQLToken.significant(text).first(where: { pkg.range.contains($0.start) && ["IS", "AS"].contains($0.upper) }) else {
            throw RefactoringError(L10n.tr("Nie znaleziono IS/AS nagłówka pakietu"))
        }
        let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: isAs.start, length: 0)))
        let decl = "  \(n) CONSTANT \(t) := \(expr);\n"
        let m = NSMutableString(string: text)
        m.replaceCharacters(in: NSRange(location: selection.lowerBound, length: selection.count), with: n)
        // Zaznaczenie jest za nagłówkiem — wstawienie przed nim nie zmienia pozycji zamienionego tekstu.
        m.insert(lineEnd >= ns.length && !text.hasSuffix("\n") ? "\n" + decl : decl, at: lineEnd)
        let pos = selection.lowerBound + (decl as NSString).length
        return TextEdit(text: m as String, selection: pos..<(pos + (n as NSString).length))
    }

    /// Typ deklaracji bez wartości domyślnej, trybu parametru i CONSTANT.
    static func plainType(_ detail: String) -> String {
        var d = detail
        for sep in [":=", " DEFAULT "] { if let r = d.range(of: sep, options: .caseInsensitive) { d = String(d[..<r.lowerBound]) } }
        let words = d.split(whereSeparator: \.isWhitespace).filter { !["IN", "OUT", "NOCOPY", "CONSTANT"].contains($0.uppercased()) }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ";")).trimmingCharacters(in: .whitespaces)
    }

    /// Wydziela zaznaczone instrukcje (całe linie) do procedury lokalnej; zmienne, stałe i parametry jednostki użyte w
    /// zaznaczeniu stają się parametrami (IN; przypisywane — IN OUT).
    public static func extractProcedure(_ text: String, selection: Range<Int>, name: String) throws -> TextEdit {
        let n = try checkName(name)
        let ns = text as NSString
        guard !selection.isEmpty, selection.upperBound <= ns.length else { throw RefactoringError(L10n.tr("Zaznacz instrukcje")) }
        let lines = ns.lineRange(for: NSRange(location: selection.lowerBound, length: selection.count))
        let body = ns.substring(with: lines)
        guard body.contains(";") else { throw RefactoringError(L10n.tr("Zaznacz pełne instrukcje")) }
        guard let c = container(at: selection.lowerBound, in: PLSQLOutline.parse(text)) else {
            throw RefactoringError(L10n.tr("Zaznaczenie nie jest w podprogramie ani bloku PL/SQL"))
        }
        let declared = c.children.filter { [.variable, .constant, .parameter].contains($0.kind) }
        let tokens = SQLToken.significant(text).filter { $0.start >= lines.location && $0.start < NSMaxRange(lines) }
        var params: [(name: String, mode: String, type: String)] = []
        for t in tokens where t.isWord {
            guard let d = declared.first(where: { $0.name.uppercased() == t.name }), !params.contains(where: { $0.name.uppercased() == t.name }) else { continue }
            let assigned = tokens.enumerated().contains { j, x in
                x.name == t.name && (j + 1 < tokens.count && tokens[j + 1].text == ":=" || (j > 0 && tokens[j - 1].upper == "INTO"))
            }
            let isOutParam = d.kind == .parameter && d.detail.uppercased().contains("OUT")
            let mode = d.kind == .constant ? "IN" : (assigned || isOutParam ? "IN OUT" : "IN")
            params.append((d.name, mode, plainType(d.detail)))
        }
        let ind = indent(atLineOf: lines.location, ns)
        let signature = params.isEmpty ? "" : "(" + params.map { "\($0.name) \($0.mode) \($0.type)" }.joined(separator: ", ") + ")"
        let bodyLines = body.components(separatedBy: "\n")
        let tokensAll = SQLToken.significant(text)
        guard let b = bodyBegin(of: c, tokens: tokensAll), b.begin.start <= selection.lowerBound else {
            throw RefactoringError(L10n.tr("Zaznaczenie musi być w ciele podprogramu albo bloku (po BEGIN)"))
        }
        let declIndent = indent(atLineOf: b.begin.start, ns)
        let procBody = bodyLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { l -> String in
            let stripped = l.hasPrefix(ind) ? String(l.dropFirst(ind.count)) : l.trimmingCharacters(in: .whitespaces)
            return declIndent + "    " + stripped
        }.joined(separator: "\n")
        let procedure = "PROCEDURE \(n)\(signature) IS\n" + declIndent + "  BEGIN\n" + procBody + "\n" + declIndent + "  END \(n);"
        let call = ind + n + (params.isEmpty ? "" : "(" + params.map(\.name).joined(separator: ", ") + ")") + ";" + (body.hasSuffix("\n") ? "\n" : "")
        return try insertDeclaration(procedure, in: text, container: c, replacing: lines.location..<NSMaxRange(lines), with: call)
    }

    /// Przypisanie `zmienna := wyrażenie;` na najwyższym poziomie ciała → inicjalizacja w deklaracji zmiennej.
    public static func replaceAssignmentWithInitialization(_ text: String, at offset: Int) throws -> TextEdit {
        let ns = text as NSString
        let tokens = SQLToken.significant(text)
        guard let c = container(at: offset, in: PLSQLOutline.parse(text)), let b = bodyBegin(of: c, tokens: tokens) else {
            throw RefactoringError(L10n.tr("Kursor nie jest w podprogramie ani bloku PL/SQL"))
        }
        guard let i = tokens.lastIndex(where: { $0.start <= offset && $0.start >= b.begin.start }) else {
            throw RefactoringError(L10n.tr("Ustaw kursor na przypisaniu"))
        }
        var s = i
        while s > 0, tokens[s - 1].text != ";", tokens[s - 1].start > b.begin.start { s -= 1 }
        guard let e = tokens[s...].firstIndex(where: { $0.text == ";" }), e > s + 2, tokens[s].isWord, tokens[s + 1].text == ":=" else {
            throw RefactoringError(L10n.tr("Ustaw kursor na przypisaniu „zmienna := wyrażenie;”"))
        }
        // Tylko instrukcja na najwyższym poziomie ciała (nie w IF/LOOP/CASE/bloku).
        var depth = 0
        var k = tokens.firstIndex(where: { $0.start == b.begin.start })! + 1
        while k < s {
            let u = tokens[k].upper
            if ["IF", "LOOP", "CASE", "BEGIN"].contains(u) && !(k > 0 && tokens[k - 1].upper == "END") { depth += 1 }
            if u == "END" { depth -= 1 }
            k += 1
        }
        guard depth == 0 else { throw RefactoringError(L10n.tr("Przypisanie jest wewnątrz instrukcji złożonej")) }
        let name = tokens[s].name
        guard let d = c.children.first(where: { $0.kind == .variable && $0.name.uppercased() == name }) else {
            throw RefactoringError(L10n.tr("Zmienna \(tokens[s].text) nie jest zadeklarowana w tej jednostce"))
        }
        let declText = ns.substring(with: NSRange(location: d.range.lowerBound, length: min(d.range.count + 1, ns.length - d.range.lowerBound)))
        guard declText.range(of: ":=") == nil, declText.range(of: " DEFAULT ", options: .caseInsensitive) == nil,
              let semi = declText.firstIndex(of: ";") else {
            throw RefactoringError(L10n.tr("Zmienna ma już wartość początkową"))
        }
        let expr = ns.substring(with: NSRange(location: tokens[s + 2].start, length: tokens[e].start - tokens[s + 2].start)).trimmingCharacters(in: .whitespacesAndNewlines)
        let semiOffset = d.range.lowerBound + (String(declText[..<semi]) as NSString).length
        // Usunięcie instrukcji: cała linia, gdy nic więcej w niej nie ma.
        let stmt = NSRange(location: tokens[s].start, length: tokens[e].end - tokens[s].start)
        let line = ns.lineRange(for: stmt)
        let rest = ns.substring(with: line).replacingOccurrences(of: ns.substring(with: stmt), with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let removal = rest.isEmpty ? line : stmt
        let m = NSMutableString(string: text)
        m.deleteCharacters(in: removal)
        let insertion = " := " + expr
        m.insert(insertion, at: semiOffset)
        return TextEdit(text: m as String, selection: d.range.lowerBound..<(semiOffset + (insertion as NSString).length + 1))
    }
}
