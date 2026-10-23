/// Dzielenie skryptu na polecenia (SQL Window, Command Window, wykonanie skryptu przez agenta).
///
/// Zasady (docs/research/behaviour.md §1):
/// - polecenie SQL kończy `;` (nie wchodzi do tekstu) albo `/` sam w linii, albo koniec tekstu;
/// - blok PL/SQL (DECLARE, BEGIN, CREATE [OR REPLACE] FUNCTION|PROCEDURE|PACKAGE|TRIGGER|TYPE|LIBRARY|JAVA|MLE MODULE,
///   WITH FUNCTION/PROCEDURE) kończy tylko `/` sam w linii albo koniec tekstu — średniki w środku nie dzielą;
/// - w trybie Command Window polecenia SQL*Plus (SET, PROMPT, @, DEFINE…) są jednoliniowe, z kontynuacją `-`;
/// - `/` bezpośrednio po poleceniu zakończonym `;` nie tworzy pustego polecenia (nie powtarza go).
public struct ScriptStatement: Sendable, Hashable {
    public enum Terminator: Sendable, Hashable { case semicolon, slash, endOfText, endOfLine }

    /// Tekst do wykonania (bez końcowego `;` w SQL; z `END;` w PL/SQL; bez `/`).
    public var text: String
    /// Zakres tekstu polecenia w skrypcie (UTF-16), od pierwszego znaku do końca (bez terminatora).
    public var start: Int
    public var end: Int
    /// Zakres razem z terminatorem — do zaznaczania polecenia pod kursorem.
    public var fullEnd: Int
    /// Numer linii (od 0) pierwszego znaku polecenia — przesunięcie błędów kompilacji.
    public var line: Int
    public var isPLSQL: Bool
    public var terminator: Terminator
    /// Polecenie SQL*Plus (Command Window), np. "SET", "PROMPT", "@".
    public var sqlplusCommand: String?
    public var category: StatementCategory
}

public enum SplitMode: Sendable, Hashable {
    case sqlWindow
    case commandWindow
}

public enum ScriptSplitter {
    public static func split(_ script: String, mode: SplitMode = .sqlWindow) -> [ScriptStatement] {
        let lexer = Lexer(script)
        let text = lexer.text
        var tokens = lexer.tokenize()
        var out: [ScriptStatement] = []
        var ti = 0
        let lineStarts = Self.lineStarts(text)

        func lineOf(_ pos: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts[mid] <= pos { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }
        func lineEnd(_ pos: Int) -> Int {
            var i = pos
            while i < text.count, text[i] != 0x0A, text[i] != 0x0D { i += 1 }
            return i
        }
        func nextLineStart(_ pos: Int) -> Int {
            var i = lineEnd(pos)
            if i < text.count, text[i] == 0x0D { i += 1 }
            if i < text.count, text[i] == 0x0A { i += 1 }
            return i
        }
        /// Czy token `/` stoi sam w linii (tylko białe znaki przed i po).
        func isLoneSlash(_ k: Int) -> Bool {
            guard tokens[k].kind == .slash else { return false }
            var j = k - 1
            while j >= 0, tokens[j].kind == .whitespace { j -= 1 }
            if j >= 0, tokens[j].kind != .newline { return false }
            j = k + 1
            while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
            return j >= tokens.count || tokens[j].kind == .newline
        }
        var lastWasSemicolonTerminated = false

        while ti < tokens.count {
            // Pomiń białe znaki i puste linie między poleceniami.
            while ti < tokens.count, tokens[ti].kind == .whitespace || tokens[ti].kind == .newline { ti += 1 }
            guard ti < tokens.count else { break }

            // Samotny `/` po poleceniu zakończonym `;` — tylko separator. W Command Window w innym miejscu (na początku,
            // po poleceniu SQL*Plus, po bloku) wykonuje bufor SQL, jak w SQL*Plus (np. GET plik, potem `/`).
            if isLoneSlash(ti), mode == .commandWindow, !lastWasSemicolonTerminated {
                let t = tokens[ti]
                out.append(ScriptStatement(text: "/", start: t.start, end: t.end, fullEnd: t.end, line: lineOf(t.start),
                                           isPLSQL: false, terminator: .endOfLine, sqlplusCommand: nil, category: .sqlplus))
                ti += 1
                continue
            }
            if isLoneSlash(ti) {
                ti += 1
                lastWasSemicolonTerminated = false
                continue
            }

            let stmtStartToken = ti
            let start = tokens[ti].start
            // Pierwsze znaczące słowa (po komentarzach) do rozpoznania rodzaju polecenia.
            var words: [String] = []
            var k = ti
            while k < tokens.count, words.count < 8 {
                let t = tokens[k]
                if !t.isTrivia {
                    words.append(t.kind == .identifier || t.kind == .keyword ? lexer.upper(t) : lexer.string(t))
                }
                k += 1
            }
            guard !words.isEmpty else { break }   // same komentarze do końca

            // Polecenie SQL*Plus (Command Window): cała linia z kontynuacjami `-`.
            if mode == .commandWindow, let cmd = SQLPlus.command(words: words, firstTokenText: lexer.string(firstSignificant(tokens, from: ti))) {
                let cmdStart = firstSignificant(tokens, from: ti).start
                var e = lineEnd(cmdStart)
                while e > cmdStart, Self.endsWithContinuation(text, cmdStart, e) {
                    let n = nextLineStart(e)
                    if n >= text.count { break }
                    e = lineEnd(n)
                }
                let body = String(decoding: text[cmdStart..<e], as: UTF16.self)
                out.append(ScriptStatement(text: body, start: cmdStart, end: e, fullEnd: e, line: lineOf(cmdStart),
                                           isPLSQL: false, terminator: .endOfLine, sqlplusCommand: cmd,
                                           category: .sqlplus))
                lastWasSemicolonTerminated = false
                let resume = nextLineStart(e)
                // Treść linii (np. PROMPT z apostrofem) mogła zaburzyć tokeny — leksuj resztę od nowa, jeśli trzeba.
                ti = tokens.firstIndex { $0.start >= resume } ?? tokens.count
                if ti < tokens.count, tokens[ti].start != resume || (ti > 0 && tokens[ti - 1].end > resume) {
                    var rest: [Token] = []
                    lexer.scan(range: resume..<text.count, state: .normal) { rest.append($0) }
                    tokens = Array(tokens[..<ti].filter { $0.end <= resume }) + rest
                    ti = tokens.firstIndex { $0.start >= resume } ?? tokens.count
                } else if ti == tokens.count, resume < text.count, let last = tokens.last, last.end > resume {
                    var rest: [Token] = []
                    lexer.scan(range: resume..<text.count, state: .normal) { rest.append($0) }
                    tokens = Array(tokens.filter { $0.end <= resume }) + rest
                    ti = tokens.firstIndex { $0.start >= resume } ?? tokens.count
                }
                continue
            }

            let plsql = Self.isPLSQLBlock(words)
            var end = text.count
            var fullEnd = text.count
            var terminator = ScriptStatement.Terminator.endOfText
            var depth = 0
            k = stmtStartToken
            while k < tokens.count {
                let t = tokens[k]
                if t.kind == .leftParen { depth += 1 }
                else if t.kind == .rightParen { depth = max(0, depth - 1) }
                else if isLoneSlash(k) {
                    end = t.start; fullEnd = t.end; terminator = .slash
                    k += 1
                    break
                } else if !plsql, t.kind == .semicolon, depth == 0 {
                    end = t.start; fullEnd = t.end; terminator = .semicolon
                    k += 1
                    break
                }
                k += 1
            }
            ti = k
            // Bez końcowych białych znaków.
            var e = end
            while e > start, [0x20, 0x09, 0x0A, 0x0D].contains(text[e - 1]) { e -= 1 }
            let body = String(decoding: text[start..<e], as: UTF16.self)
            if terminator == .slash && lastWasSemicolonTerminated && body.isEmpty { continue }
            out.append(ScriptStatement(text: body, start: start, end: e, fullEnd: fullEnd, line: lineOf(start),
                                       isPLSQL: plsql, terminator: terminator, sqlplusCommand: nil,
                                       category: StatementClassifier.classify(words: words)))
            lastWasSemicolonTerminated = terminator == .semicolon
        }
        return out
    }

    /// Polecenie zawierające pozycję kursora (albo najbliższe przed nią) — „AutoSelect statement”.
    public static func statement(at offset: Int, in statements: [ScriptStatement]) -> ScriptStatement? {
        if let s = statements.first(where: { offset >= $0.start && offset <= $0.fullEnd }) { return s }
        return statements.last { $0.fullEnd <= offset } ?? statements.first
    }

    static func firstSignificant(_ tokens: [Token], from i: Int) -> Token {
        var k = i
        while k < tokens.count, tokens[k].isTrivia { k += 1 }
        return k < tokens.count ? tokens[k] : tokens[i]
    }

    static func endsWithContinuation(_ text: [UInt16], _ start: Int, _ end: Int) -> Bool {
        var e = end
        while e > start, text[e - 1] == 0x20 || text[e - 1] == 0x09 { e -= 1 }
        return e > start && text[e - 1] == 0x2D   // -
    }

    static func lineStarts(_ text: [UInt16]) -> [Int] {
        var starts = [0]
        var i = 0
        while i < text.count {
            if text[i] == 0x0A { starts.append(i + 1) }
            else if text[i] == 0x0D {
                if i + 1 < text.count, text[i + 1] == 0x0A { i += 1 }
                starts.append(i + 1)
            }
            i += 1
        }
        return starts
    }

    /// Czy polecenie to blok PL/SQL (kończony `/`).
    public static func isPLSQLBlock(_ w: [String]) -> Bool {
        guard let first = w.first else { return false }
        if first == "DECLARE" || first == "BEGIN" || first == "<<" { return true }
        if first == "WITH", w.count > 1, w[1] == "FUNCTION" || w[1] == "PROCEDURE" { return true }
        guard first == "CREATE" else { return false }
        var i = 1
        if i < w.count, w[i] == "OR", i + 1 < w.count, w[i + 1] == "REPLACE" { i += 2 }
        while i < w.count, ["EDITIONABLE", "NONEDITIONABLE", "EDITIONING", "FORCE", "NOFORCE", "AND", "RESOLVE",
                            "COMPILE", "NOT", "IF", "EXISTS", "SHARING", "=", "METADATA", "NONE", "DATA"].contains(w[i]) { i += 1 }
        guard i < w.count else { return false }
        switch w[i] {
        case "FUNCTION", "PROCEDURE", "PACKAGE", "TRIGGER", "TYPE", "LIBRARY", "JAVA": return true
        case "MLE": return true   // CREATE MLE MODULE … AS <kod JavaScript>
        default: return false
        }
    }
}
