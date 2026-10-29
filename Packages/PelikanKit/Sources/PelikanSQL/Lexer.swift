/// Tolerancyjny lekser Oracle SQL / PL/SQL / SQL*Plus.
///
/// Działa na jednostkach UTF-16 (zgodnie z NSString/NSTextView), nie rzuca błędów — niedomknięty
/// tekst albo komentarz kończy się na końcu wejścia. Stan na końcu linii (`LexState`) pozwala leksować
/// przyrostowo: edytor przelicza tylko zmienione linie, dopóki stan na końcu linii się nie zmienia.
public enum TokenKind: UInt8, Sendable, Hashable {
    case whitespace, newline
    case lineComment, blockComment, hint
    case identifier, quotedIdentifier, keyword
    case string, number
    case bindVariable        // :nazwa, :1
    case substitution        // &nazwa, &&nazwa
    case jasperParameter     // JasperReports: $P{nazwa}, $P!{nazwa}, $X{IN, kolumna, param}
    case `operator`          // := => || ** .. <> != ^= ~= <= >= i jednoznakowe
    case semicolon, slash, comma, leftParen, rightParen, dot
    case unknown
    /// Kompilacja warunkowa: `$IF`, `$THEN`, `$ELSIF`, `$ELSE`, `$END`, `$ERROR` i dyrektywy `$$nazwa` — jeden token
    /// (rozdzielone `$ IF`, `$ $nazwa` nie kompilują się — formater nie może ich rozdzielać).
    case directive
}

public struct Token: Sendable, Hashable {
    public var kind: TokenKind
    /// Początek i długość w jednostkach UTF-16.
    public var start: Int
    public var length: Int
    public var end: Int { start + length }

    public init(kind: TokenKind, start: Int, length: Int) {
        self.kind = kind; self.start = start; self.length = length
    }

    public var isTrivia: Bool {
        kind == .whitespace || kind == .newline || kind == .lineComment || kind == .blockComment
    }
}

/// Stan leksera między liniami (dla leksowania przyrostowego).
public enum LexState: Sendable, Hashable {
    case normal
    case blockComment(hint: Bool)
    case string(quote: UInt16?)               // quote != nil: q'…' z ogranicznikiem zamykającym
    case quotedIdentifier
}

public struct Lexer: Sendable {
    public let text: [UInt16]

    public init(_ string: String) { text = Array(string.utf16) }
    public init(utf16: [UInt16]) { text = utf16 }

    /// Wszystkie tokeny (z trywiami), od stanu `start`.
    public func tokenize(from start: LexState = .normal) -> [Token] {
        var tokens: [Token] = []
        tokens.reserveCapacity(text.count / 4)
        _ = scan(range: 0..<text.count, state: start) { tokens.append($0) }
        return tokens
    }

    /// Leksuje fragment (np. jedną linię) i zwraca stan na jego końcu.
    @discardableResult
    public func scan(range: Range<Int>, state: LexState, _ emit: (Token) -> Void) -> LexState {
        let end = min(range.upperBound, text.count)
        var i = min(range.lowerBound, end)
        var st = state

        // Kontynuacja konstrukcji z poprzedniej linii.
        switch st {
        case .normal: break
        case .blockComment(let hint):
            let s = i
            if let close = find("*/", from: i, end: end) {
                i = close + 2; st = .normal
            } else { i = end }
            emit(Token(kind: hint ? .hint : .blockComment, start: s, length: i - s))
        case .string(let q):
            let s = i
            let (stop, closed) = q.map { scanQEnd(from: i, end: end, close: $0) } ?? scanStringEnd(from: i, end: end)
            i = stop
            if closed { st = .normal }
            emit(Token(kind: .string, start: s, length: i - s))
        case .quotedIdentifier:
            let s = i
            if let close = findChar(0x22, from: i, end: end) { i = close + 1; st = .normal } else { i = end }
            emit(Token(kind: .quotedIdentifier, start: s, length: i - s))
        }

        while i < end {
            let c = text[i]
            let s = i
            switch c {
            case 0x0A, 0x0D:   // \n \r
                i += 1
                if c == 0x0D, i < end, text[i] == 0x0A { i += 1 }
                emit(Token(kind: .newline, start: s, length: i - s))
            case 0x20, 0x09, 0x0C, 0xA0:
                while i < end, [0x20, 0x09, 0x0C, 0xA0].contains(text[i]) { i += 1 }
                emit(Token(kind: .whitespace, start: s, length: i - s))
            case 0x2D where peek(i + 1, end) == 0x2D:  // --
                while i < end, text[i] != 0x0A, text[i] != 0x0D { i += 1 }
                emit(Token(kind: .lineComment, start: s, length: i - s))
            case 0x2F where peek(i + 1, end) == 0x2A:  // /*
                let hint = peek(i + 2, end) == 0x2B   // /*+
                if let close = find("*/", from: i + 2, end: end) {
                    i = close + 2
                } else {
                    i = end; st = .blockComment(hint: hint)
                }
                emit(Token(kind: hint ? .hint : .blockComment, start: s, length: i - s))
            case 0x27:  // '
                let (stop, closed) = scanStringEnd(from: i + 1, end: end)
                i = stop
                if !closed { st = .string(quote: nil) }
                emit(Token(kind: .string, start: s, length: i - s))
            case 0x22:  // "
                if let close = findChar(0x22, from: i + 1, end: end) { i = close + 1 } else { i = end; st = .quotedIdentifier }
                emit(Token(kind: .quotedIdentifier, start: s, length: i - s))
            case _ where isQuoteOperatorStart(i, end):
                // q'[…]', Q'…', nq'…', Nq'…'
                var j = i
                if text[j] == 0x6E || text[j] == 0x4E { j += 1 }   // n/N
                j += 2                                            // q'
                guard j < end else { i = end; emit(Token(kind: .string, start: s, length: i - s)); continue }
                let open = text[j]
                let close = Self.closingDelimiter(open)
                let (stop, closed) = scanQEnd(from: j + 1, end: end, close: close)
                i = stop
                if !closed { st = .string(quote: close) }
                emit(Token(kind: .string, start: s, length: i - s))
            case _ where (c == 0x6E || c == 0x4E) && peek(i + 1, end) == 0x27:  // N'…'
                let (stop, closed) = scanStringEnd(from: i + 2, end: end)
                i = stop
                if !closed { st = .string(quote: nil) }
                emit(Token(kind: .string, start: s, length: i - s))
            case 0x30...0x39:
                i = scanNumber(from: i, end: end)
                emit(Token(kind: .number, start: s, length: i - s))
            case 0x2E where isDigit(peek(i + 1, end)):   // .5
                i = scanNumber(from: i, end: end)
                emit(Token(kind: .number, start: s, length: i - s))
            case 0x3A:  // :
                if peek(i + 1, end) == 0x3D { i += 2; emit(Token(kind: .operator, start: s, length: 2)); continue }   // :=
                let n = peek(i + 1, end)
                if isIdentStart(n) || isDigit(n) {
                    i += 1
                    while i < end, isIdentPart(text[i]) { i += 1 }
                    emit(Token(kind: .bindVariable, start: s, length: i - s))
                } else if n == 0x22, let close = findChar(0x22, from: i + 2, end: end) {   // :"Nazwa"
                    i = close + 1
                    emit(Token(kind: .bindVariable, start: s, length: i - s))
                } else {
                    i += 1
                    emit(Token(kind: .operator, start: s, length: 1))
                }
            case 0x26:  // &
                var j = i + 1
                if peek(j, end) == 0x26 { j += 1 }
                if peek(j, end) == 0x3C, let close = optionsEnd(from: j, end: end) {   // &<name="…" …>
                    i = close
                    emit(Token(kind: .substitution, start: s, length: i - s))
                } else if peek(j, end) == 0x22, let close = findChar(0x22, from: j + 1, end: end) {   // &"Nazwa ze spacjami"
                    i = close + 1
                    emit(Token(kind: .substitution, start: s, length: i - s))
                } else if isIdentStart(peek(j, end)) || isDigit(peek(j, end)) {
                    while j < end, isIdentPart(text[j]) { j += 1 }
                    if j < end, text[j] == 0x2E { j += 1 }   // &nazwa. — kropka kończy nazwę i jest pochłaniana
                    i = j
                    emit(Token(kind: .substitution, start: s, length: i - s))
                } else {
                    i += 1
                    emit(Token(kind: .operator, start: s, length: 1))
                }
            case 0x24 where jasperParameterEnd(from: i, end: end) != nil:   // $P{…} $P!{…} $X{…}
                i = jasperParameterEnd(from: i, end: end)!
                emit(Token(kind: .jasperParameter, start: s, length: i - s))
            case 0x24 where directiveEnd(from: i, end: end) != nil:   // $IF … $END, $$PLSQL_UNIT
                i = directiveEnd(from: i, end: end)!
                emit(Token(kind: .directive, start: s, length: i - s))
            case 0x3B: i += 1; emit(Token(kind: .semicolon, start: s, length: 1))
            case 0x2C: i += 1; emit(Token(kind: .comma, start: s, length: 1))
            case 0x28: i += 1; emit(Token(kind: .leftParen, start: s, length: 1))
            case 0x29: i += 1; emit(Token(kind: .rightParen, start: s, length: 1))
            case 0x2F: i += 1; emit(Token(kind: .slash, start: s, length: 1))
            case 0x2E:
                if peek(i + 1, end) == 0x2E { i += 2; emit(Token(kind: .operator, start: s, length: 2)) }
                else { i += 1; emit(Token(kind: .dot, start: s, length: 1)) }
            case _ where isIdentStart(c):
                i += 1
                while i < end, isIdentPart(text[i]) { i += 1 }
                let kind: TokenKind = Keywords.isKeyword(text, s, i - s) ? .keyword : .identifier
                emit(Token(kind: kind, start: s, length: i - s))
            default:
                // Operatory trzyznakowe (odległości wektorów 23ai), dwuznakowe, potem jednoznakowe.
                let three: [UInt16] = i + 2 < end ? [c, text[i + 1], text[i + 2]] : []
                let two: [UInt16] = i + 1 < end ? [c, text[i + 1]] : []
                if !three.isEmpty, Self.threeCharOperators.contains(three) {
                    i += 3
                    emit(Token(kind: .operator, start: s, length: 3))
                } else if !two.isEmpty, Self.twoCharOperators.contains(two) {
                    i += 2
                    emit(Token(kind: .operator, start: s, length: 2))
                } else if Self.oneCharOperators.contains(c) {
                    i += 1
                    emit(Token(kind: .operator, start: s, length: 1))
                } else {
                    i += (c >= 0xD800 && c <= 0xDBFF && i + 1 < end) ? 2 : 1
                    emit(Token(kind: .unknown, start: s, length: i - s))
                }
            }
        }
        return st
    }

    // MARK: - Pomocnicze

    static let twoCharOperators: Set<[UInt16]> = [
        Array("=>".utf16), Array("||".utf16), Array("**".utf16), Array("<>".utf16), Array("!=".utf16),
        Array("^=".utf16), Array("~=".utf16), Array("<=".utf16), Array(">=".utf16), Array("<<".utf16), Array(">>".utf16),
    ]
    /// `<=>` (COSINE), `<->` (EUCLIDEAN), `<#>` (DOT) — operatory odległości wektorów (Oracle 23ai).
    static let threeCharOperators: Set<[UInt16]> = [Array("<=>".utf16), Array("<->".utf16), Array("<#>".utf16)]
    static let oneCharOperators: Set<UInt16> = Set("+-*=<>@%!^~|?$#[]{}\\".utf16)

    @inline(__always) func peek(_ i: Int, _ end: Int) -> UInt16 { i < end ? text[i] : 0 }

    @inline(__always) func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }

    @inline(__always) func isIdentStart(_ c: UInt16) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0xC0 && c != 0xD7 && c != 0xF7 && !(c >= 0x2000 && c <= 0x206F))
    }

    @inline(__always) func isIdentPart(_ c: UInt16) -> Bool {
        isIdentStart(c) || isDigit(c) || c == 0x5F || c == 0x24 || c == 0x23   // _ $ #
    }

    func isQuoteOperatorStart(_ i: Int, _ end: Int) -> Bool {
        var j = i
        let c = text[j]
        if c == 0x6E || c == 0x4E { j += 1 }
        guard j + 1 < end else { return false }
        return (text[j] == 0x71 || text[j] == 0x51) && text[j + 1] == 0x27   // q' Q'
    }

    /// Koniec opcji zmiennej `&<…>` (pozycja za `>`), z pominięciem `>` w wartościach w cudzysłowach (UG 12.3).
    func optionsEnd(from lt: Int, end: Int) -> Int? {
        var i = lt + 1
        var quote: UInt16? = nil
        while i < end {
            let c = text[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == 0x22 || c == 0x201D || c == 0x201C {
                quote = c == 0x22 ? 0x22 : 0x201D
            } else if c == 0x3E {
                return i + 1
            } else if c == 0x3B && i == lt + 1 {
                return nil
            }
            i += 1
        }
        return nil
    }

    /// Parametr JasperReports zaczynający się na `i` (`$P{`, `$P!{`, `$X{`) — pozycja za `}` albo nil.
    /// Wielkość liter jak w JasperReports (tylko P i X). Nawias musi się zamknąć w tej samej linii.
    func jasperParameterEnd(from i: Int, end: Int) -> Int? {
        guard peek(i, end) == 0x24 else { return nil }
        var j = i + 1
        let k = peek(j, end)
        guard k == 0x50 || k == 0x58 else { return nil }   // P X
        j += 1
        if k == 0x50, peek(j, end) == 0x21 { j += 1 }      // $P!
        guard peek(j, end) == 0x7B else { return nil }     // {
        j += 1
        while j < end, text[j] != 0x7D, text[j] != 0x0A, text[j] != 0x0D { j += 1 }
        guard j < end, text[j] == 0x7D, j > i + 3 else { return nil }
        return j + 1
    }

    /// Dyrektywa kompilacji warunkowej zaczynająca się na `i`: `$IF`, `$THEN`, `$ELSIF`, `$ELSE`, `$END`, `$ERROR`
    /// (wielkość liter dowolna) albo `$$nazwa` — pozycja za nią albo nil.
    func directiveEnd(from i: Int, end: Int) -> Int? {
        guard peek(i, end) == 0x24 else { return nil }
        var j = i + 1
        let inquiry = peek(j, end) == 0x24
        if inquiry { j += 1 }
        guard isIdentStart(peek(j, end)) else { return nil }
        let w = j
        while j < end, isIdentPart(text[j]) { j += 1 }
        if inquiry { return j }
        let word = String(decoding: text[w..<j], as: UTF16.self).uppercased()
        return Self.directives.contains(word) ? j : nil
    }

    static let directives: Set<String> = ["IF", "THEN", "ELSIF", "ELSE", "END", "ERROR"]

    static func closingDelimiter(_ open: UInt16) -> UInt16 {
        switch open {
        case 0x5B: 0x5D   // [ ]
        case 0x7B: 0x7D   // { }
        case 0x28: 0x29   // ( )
        case 0x3C: 0x3E   // < >
        default: open
        }
    }

    /// Koniec literału '…' (z '' jako cudzysłowem w środku). Zwraca (pozycja za literałem, czy domknięty).
    func scanStringEnd(from start: Int, end: Int) -> (Int, Bool) {
        var i = start
        while i < end {
            if text[i] == 0x27 {
                if i + 1 < end, text[i + 1] == 0x27 { i += 2; continue }
                return (i + 1, true)
            }
            i += 1
        }
        return (end, false)
    }

    /// Koniec q'X…X'.
    func scanQEnd(from start: Int, end: Int, close: UInt16) -> (Int, Bool) {
        var i = start
        while i + 1 < end {
            if text[i] == close, text[i + 1] == 0x27 { return (i + 2, true) }
            i += 1
        }
        return (end, false)
    }

    func scanNumber(from start: Int, end: Int) -> Int {
        var i = start
        while i < end, isDigit(text[i]) { i += 1 }
        if i < end, text[i] == 0x2E, peek(i + 1, end) != 0x2E {   // nie „1..10”
            i += 1
            while i < end, isDigit(text[i]) { i += 1 }
        }
        if i < end, text[i] == 0x65 || text[i] == 0x45 {   // e E
            var j = i + 1
            if j < end, text[j] == 0x2B || text[j] == 0x2D { j += 1 }
            if j < end, isDigit(text[j]) {
                i = j
                while i < end, isDigit(text[i]) { i += 1 }
            }
        }
        if i < end, [0x66, 0x46, 0x64, 0x44].contains(text[i]), !isIdentPart(peek(i + 1, end)) { i += 1 }  // 1.5f / 2d
        return i
    }

    func find(_ s: String, from start: Int, end: Int) -> Int? {
        let p = Array(s.utf16)
        var i = start
        while i + p.count <= end {
            if text[i] == p[0], Array(text[i..<(i + p.count)]) == p { return i }
            i += 1
        }
        return nil
    }

    func findChar(_ c: UInt16, from start: Int, end: Int) -> Int? {
        var i = start
        while i < end { if text[i] == c { return i }; i += 1 }
        return nil
    }

    /// Tekst tokenu.
    public func string(_ t: Token) -> String {
        String(decoding: text[t.start..<t.end], as: UTF16.self)
    }

    /// Tekst tokenu wielkimi literami (słowa kluczowe, identyfikatory bez cudzysłowu).
    public func upper(_ t: Token) -> String { string(t).uppercased() }
}
