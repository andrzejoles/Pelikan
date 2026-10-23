import Foundation

/// Pomoc kontekstowa w dokumentacji Oracle (PD-EDIT-026, PD-DOC-001): adres strony dla słowa pod kursorem —
/// błąd ORA-/PLS- (Oracle Error Help), pakiet (PL/SQL Packages and Types Reference), widok słownika (Reference),
/// polecenie lub funkcja SQL (SQL Language Reference), polecenie PL/SQL (PL/SQL Language Reference); w pozostałych
/// przypadkach wyszukiwanie w dokumentacji wybranej wersji bazy.
public enum OracleDocs {
    /// Wersje dokumentacji (ścieżka docs.oracle.com/en/database/oracle/oracle-database/<wersja>/).
    public static let releases = ["19", "21", "23", "26"]
    public static let defaultRelease = "19"

    static let base = "https://docs.oracle.com/en/database/oracle/oracle-database/"

    /// Polecenia SQL o stronach `sqlrf/<SŁOWA-Z-MYŚLNIKAMI>.html` (dwa słowa — gdy następne słowo w tekście pasuje).
    static let sqlStatements: Set<String> = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "MERGE", "COMMIT", "ROLLBACK", "SAVEPOINT", "TRUNCATE-TABLE", "COMMENT",
        "CREATE-TABLE", "ALTER-TABLE", "DROP-TABLE", "CREATE-INDEX", "ALTER-INDEX", "DROP-INDEX", "CREATE-VIEW", "ALTER-VIEW",
        "DROP-VIEW", "CREATE-SEQUENCE", "ALTER-SEQUENCE", "DROP-SEQUENCE", "CREATE-SYNONYM", "DROP-SYNONYM", "CREATE-USER",
        "ALTER-USER", "DROP-USER", "CREATE-ROLE", "GRANT", "REVOKE", "ALTER-SESSION", "ALTER-SYSTEM", "LOCK-TABLE",
        "SET-TRANSACTION", "EXPLAIN-PLAN", "CREATE-MATERIALIZED-VIEW", "CREATE-TYPE", "CREATE-PROCEDURE", "CREATE-FUNCTION",
        "CREATE-PACKAGE", "CREATE-TRIGGER", "FLASHBACK-TABLE", "PURGE", "RENAME", "ANALYZE", "AUDIT", "NOAUDIT", "CALL",
    ]

    /// Funkcje SQL o stronach `sqlrf/<NAZWA>.html`.
    static let sqlFunctions: Set<String> = [
        "NVL", "NVL2", "DECODE", "COALESCE", "NULLIF", "SUBSTR", "INSTR", "LENGTH", "REPLACE", "TRANSLATE", "TRIM", "LTRIM",
        "RTRIM", "LPAD", "RPAD", "UPPER", "LOWER", "INITCAP", "CONCAT", "ROUND", "TRUNC", "MOD", "ABS", "CEIL", "FLOOR",
        "POWER", "SQRT", "SIGN", "GREATEST", "LEAST", "SYSDATE", "SYSTIMESTAMP", "ADD_MONTHS", "MONTHS_BETWEEN", "LAST_DAY",
        "NEXT_DAY", "EXTRACT", "TO_DATE", "TO_TIMESTAMP", "TO_NUMBER", "CAST", "COUNT", "SUM", "AVG", "MIN", "MAX",
        "LISTAGG", "ROW_NUMBER", "RANK", "DENSE_RANK", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE", "NTILE", "REGEXP_LIKE",
        "REGEXP_SUBSTR", "REGEXP_REPLACE", "REGEXP_INSTR", "REGEXP_COUNT", "SYS_CONTEXT", "USER", "UID", "ROWNUM",
        "JSON_VALUE", "JSON_QUERY", "JSON_TABLE", "JSON_OBJECT", "JSON_ARRAY", "XMLTYPE", "STANDARD_HASH", "ORA_HASH",
    ]

    /// Polecenia PL/SQL o stronach `lnpls/<NAZWA>-statement.html`.
    static let plsqlStatements: Set<String> = [
        "FORALL", "LOOP", "WHILE", "FOR", "IF", "CASE", "EXIT", "CONTINUE", "GOTO", "RAISE", "RETURN", "NULL", "OPEN", "FETCH",
        "CLOSE", "PIPE-ROW", "EXECUTE-IMMEDIATE", "SELECT-INTO",
    ]

    /// Oracle Error Help dla kodu ORA-/PLS-/TNS- (numer dopełniany do 5 cyfr).
    public static func errorURL(_ code: String) -> URL? {
        guard let m = code.uppercased().firstMatch(of: #/^(ORA|PLS|TNS)-?(\d{1,5})$/#) else { return nil }
        let n = String(repeating: "0", count: max(0, 5 - m.2.count)) + m.2
        return URL(string: "https://docs.oracle.com/error-help/db/\(m.1.lowercased())-\(n)/")
    }

    /// Adres dokumentacji dla słowa pod kursorem; `next` — następne słowo w tekście (polecenia dwuwyrazowe).
    public static func url(for word: String, next: String? = nil, release: String = defaultRelease) -> URL? {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
        guard !w.isEmpty else { return nil }
        let rel = releases.contains(release) ? release : defaultRelease
        let upper = w.uppercased()
        if let e = errorURL(upper) { return e }
        // Pakiet (także pakiet.procedura) — strona pakietu.
        let first = upper.split(separator: ".").map(String.init)
        let head = first.count > 1 && !["SYS", "PUBLIC"].contains(first[0]) || first.count == 1 ? first[0] : first[1]
        if head.range(of: #"^(DBMS|UTL|OWA|HTP|HTF|CTX|SDO|APEX)_[A-Z0-9_]+$"#, options: .regularExpression) != nil {
            return URL(string: base + rel + "/arpls/" + head + ".html")
        }
        if head.range(of: #"^G?V\$[A-Z0-9_]+$"#, options: .regularExpression) != nil {
            return URL(string: base + rel + "/refrn/" + head.replacingOccurrences(of: "$", with: "-") + ".html")
        }
        if head.range(of: #"^(ALL|DBA|USER|CDB)_[A-Z0-9_]+$"#, options: .regularExpression) != nil {
            return URL(string: base + rel + "/refrn/" + head + ".html")
        }
        if let n = next?.uppercased(), sqlStatements.contains(head + "-" + n) { return URL(string: base + rel + "/sqlrf/" + head + "-" + n + ".html") }
        if let n = next?.uppercased(), plsqlStatements.contains(head + "-" + n) { return URL(string: base + rel + "/lnpls/" + head + "-" + n + "-statement.html") }
        if sqlStatements.contains(head) || sqlFunctions.contains(head) { return URL(string: base + rel + "/sqlrf/" + head + ".html") }
        if plsqlStatements.contains(head) { return URL(string: base + rel + "/lnpls/" + head + "-statement.html") }
        var c = URLComponents(string: "https://docs.oracle.com/search/")!
        c.queryItems = [URLQueryItem(name: "q", value: w), URLQueryItem(name: "category", value: "database"),
                        URLQueryItem(name: "product", value: "en/database/oracle/oracle-database/" + rel)]
        return c.url
    }

    /// Słowo pod kursorem (z kropkami i `$`, np. V$SESSION, DBMS_OUTPUT.PUT_LINE, ORA-01403) i następne słowo.
    public static func word(at offset: Int, in text: String) -> (word: String, next: String?)? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$#.-"))
        func isWord(_ i: Int) -> Bool { i >= 0 && i < ns.length && UnicodeScalar(ns.character(at: i)).map { allowed.contains($0) } == true }
        var s = min(max(0, offset), ns.length)
        if !isWord(s), isWord(s - 1) { s -= 1 }
        guard isWord(s) else { return nil }
        var a = s, b = s
        while isWord(a - 1) { a -= 1 }
        while isWord(b + 1) { b += 1 }
        var word = ns.substring(with: NSRange(location: a, length: b - a + 1))
        // Myślnik tylko w kodach błędów (ORA-01403); w innych słowach to operator.
        if word.range(of: #"^(?i)(ORA|PLS|TNS)-\d+"#, options: .regularExpression) == nil, let dash = word.firstIndex(of: "-") {
            let left = String(word[..<dash])
            let cut = left.count
            if offset - a <= cut { word = left } else { word = String(word[word.index(after: dash)...]) }
        }
        word = word.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        var i = b + 1
        while i < ns.length, let u = UnicodeScalar(ns.character(at: i)), CharacterSet.whitespacesAndNewlines.contains(u) { i += 1 }
        var j = i
        while j < ns.length, let u = UnicodeScalar(ns.character(at: j)), CharacterSet.letters.contains(u) { j += 1 }
        let next = j > i ? ns.substring(with: NSRange(location: i, length: j - i)) : nil
        return word.isEmpty ? nil : (word, next)
    }
}
