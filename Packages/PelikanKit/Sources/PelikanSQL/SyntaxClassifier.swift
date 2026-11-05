/// Kategoria kolorowania składni (D227): SQL, PL/SQL, SQL*Plus i Pro*C (C z wstawkami EXEC SQL).
public enum SyntaxStyle: String, CaseIterable, Codable, Sendable {
    case plain, keyword, dataType, function, package, string, number, comment, hint, variable, quotedIdentifier
    case `operator`, directive
}

/// Kategoria tokenu leksera SQL (D227): słowa kluczowe dzielone na typy danych, funkcje wbudowane (nazwa przed „(”)
/// i pakiety dostarczane z bazą (`DBMS_OUTPUT` przed „.”) według `SQLWords`.
public enum SyntaxClassifier {
    public static func style(_ t: Token, in text: [UInt16]) -> SyntaxStyle? {
        switch t.kind {
        case .keyword, .identifier:
            guard t.length <= 40 else { return t.kind == .keyword ? .keyword : nil }
            let word = upper(text, t)
            if SQLWords.dataTypes.contains(word) { return .dataType }   // także VARCHAR2(30), NUMBER(10, 2)
            let n = next(text, after: t.end)
            if n == 40, SQLWords.functions.contains(word) { return .function }
            if n == 46, SQLWords.isPackage(word) { return .package }
            return t.kind == .keyword ? .keyword : nil
        case .directive: return .directive
        case .string: return .string
        case .lineComment, .blockComment: return .comment
        case .hint: return .hint
        case .number: return .number
        case .bindVariable, .substitution, .jasperParameter: return .variable
        case .quotedIdentifier: return .quotedIdentifier
        case .operator, .semicolon, .slash, .comma, .leftParen, .rightParen, .dot: return .operator
        default: return nil
        }
    }

    /// Pierwszy znak po `offset` poza spacjami i tabulacjami (0 — koniec tekstu albo nowa linia).
    static func next(_ text: [UInt16], after offset: Int) -> UInt16 {
        var i = offset
        while i < text.count, text[i] == 32 || text[i] == 9 { i += 1 }
        return i < text.count ? text[i] : 0
    }

    static func upper(_ text: [UInt16], _ t: Token) -> String {
        var out = ""
        out.unicodeScalars.reserveCapacity(t.length)
        for i in t.start..<min(t.end, text.count) {
            var c = text[i]
            if c >= 97 && c <= 122 { c -= 32 }
            guard let u = Unicode.Scalar(c) else { return "" }
            out.unicodeScalars.append(u)
        }
        return out
    }
}
