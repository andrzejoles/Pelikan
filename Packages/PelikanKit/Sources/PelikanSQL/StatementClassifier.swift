/// Kategoria polecenia (Oracle SQL Language Reference, „Types of SQL Statements”) — podstawa polityki
/// uprawnień agenta (docs/SECURITY.md): nierozpoznane = najwyższe ryzyko.
public enum StatementCategory: String, Sendable, Hashable, Codable, CaseIterable {
    case query               // SELECT, WITH … SELECT
    case dml                 // INSERT, UPDATE, DELETE, MERGE, LOCK TABLE, EXPLAIN PLAN, CALL? (nie: CALL to PL/SQL)
    case ddl                 // CREATE, ALTER (poza SESSION/SYSTEM), DROP, TRUNCATE, GRANT, REVOKE, COMMENT, …
    case plsql               // BEGIN, DECLARE, CALL, EXEC
    case transactionControl  // COMMIT, ROLLBACK, SAVEPOINT, SET TRANSACTION
    case sessionControl      // ALTER SESSION, SET ROLE
    case systemControl       // ALTER SYSTEM
    case sqlplus             // polecenia SQL*Plus (Command Window)
    case unknown

    /// Ryzyko rośnie: odczyt < transakcja < sesja < DML < PL/SQL < DDL < system < nieznane.
    public var riskRank: Int {
        switch self {
        case .query: 0
        case .transactionControl: 1
        case .sessionControl: 2
        case .dml: 3
        case .plsql: 4
        case .ddl: 5
        case .sqlplus: 6
        case .systemControl: 7
        case .unknown: 8
        }
    }
}

public struct Classification: Sendable, Hashable {
    public var category: StatementCategory
    /// SELECT … FOR UPDATE — blokuje wiersze (dla agenta to nie jest odczyt).
    public var locksRows: Bool
    /// Tekst zawiera więcej niż jedno polecenie (agent: `run_query` przyjmuje dokładnie jedno).
    public var statementCount: Int
    /// Polecenia SQL*Plus wymagające systemu operacyjnego (HOST, !, $, SPOOL, @ plik).
    public var touchesOperatingSystem: Bool
}

public enum StatementClassifier {
    /// Klasyfikacja całego tekstu (może zawierać kilka poleceń — wtedy kategoria najwyższego ryzyka).
    public static func classify(_ sql: String, mode: SplitMode = .sqlWindow) -> Classification {
        let statements = ScriptSplitter.split(sql, mode: mode)
        guard !statements.isEmpty else {
            return Classification(category: .unknown, locksRows: false, statementCount: 0, touchesOperatingSystem: false)
        }
        var cat = StatementCategory.query
        var locks = false
        var os = false
        for s in statements {
            if s.category.riskRank > cat.riskRank { cat = s.category }
            if s.category == .query, Self.hasForUpdate(s.text) { locks = true }
            if let c = s.sqlplusCommand, SQLPlus.osCommands.contains(c) { os = true }
        }
        return Classification(category: cat, locksRows: locks, statementCount: statements.count, touchesOperatingSystem: os)
    }

    /// Klasyfikacja po pierwszych znaczących słowach (wielkie litery).
    public static func classify(words w: [String]) -> StatementCategory {
        guard let first = w.first else { return .unknown }
        let second = w.count > 1 ? w[1] : ""
        switch first {
        case "SELECT", "(": return .query
        case "WITH":
            // WITH … SELECT; WITH FUNCTION … SELECT (12c) — zapytanie z funkcją PL/SQL.
            return second == "FUNCTION" || second == "PROCEDURE" ? .query : .query
        case "INSERT", "UPDATE", "DELETE", "MERGE", "UPSERT": return .dml
        case "LOCK": return .dml
        case "EXPLAIN": return .dml        // zapisuje do PLAN_TABLE
        case "BEGIN", "DECLARE", "CALL", "<<": return .plsql
        case "COMMIT", "ROLLBACK", "SAVEPOINT": return .transactionControl
        case "SET":
            switch second {
            case "TRANSACTION": return .transactionControl
            case "ROLE": return .sessionControl
            case "CONSTRAINT", "CONSTRAINTS": return .transactionControl
            default: return .unknown
            }
        case "ALTER":
            if second == "SESSION" { return .sessionControl }
            if second == "SYSTEM" || second == "DATABASE" || second == "PLUGGABLE" { return .systemControl }
            return .ddl
        case "CREATE", "DROP", "TRUNCATE", "RENAME", "GRANT", "REVOKE", "COMMENT", "ANALYZE", "AUDIT", "NOAUDIT",
             "PURGE", "FLASHBACK", "ASSOCIATE", "DISASSOCIATE", "UNDROP":
            return .ddl
        case "SHUTDOWN", "STARTUP", "ADMINISTER":
            return .systemControl
        default:
            return .unknown
        }
    }

    static func hasForUpdate(_ sql: String) -> Bool {
        let lexer = Lexer(sql)
        let words = lexer.tokenize().filter { !$0.isTrivia }.map { lexer.upper($0) }
        for i in 0..<max(0, words.count - 1) where words[i] == "FOR" && words[i + 1] == "UPDATE" { return true }
        return false
    }
}

/// Polecenia SQL*Plus / SQLcl rozpoznawane w Command Window.
public enum SQLPlus {
    /// Słowa (i ich skróty) poleceń SQL*Plus. Uwaga: SET TRANSACTION / SET ROLE / SET CONSTRAINTS to SQL.
    static let commands: [String: String] = {
        var m: [String: String] = [:]
        // (pełna nazwa, minimalny skrót) wg „SQL*Plus User's Guide and Reference”, rozdz. 12.
        let list: [(String, Int)] = [
            ("ACCEPT", 3), ("APPEND", 1), ("ARCHIVE", 7), ("ATTRIBUTE", 4), ("BREAK", 3), ("BTITLE", 3), ("CHANGE", 1),
            ("CLEAR", 2), ("COLUMN", 3), ("COMPUTE", 4), ("CONNECT", 4), ("COPY", 4), ("DEFINE", 3), ("DEL", 3),
            ("DESCRIBE", 4), ("DISCONNECT", 4), ("EDIT", 2), ("EXECUTE", 4), ("EXIT", 4), ("GET", 3), ("HELP", 4),
            ("HISTORY", 4), ("HOST", 3), ("INPUT", 1), ("LIST", 1), ("PASSWORD", 5), ("PAUSE", 3), ("PRINT", 3),
            ("PROMPT", 3), ("QUIT", 4), ("RECOVER", 7), ("REMARK", 3), ("REPFOOTER", 5), ("REPHEADER", 5), ("RUN", 1),
            ("SAVE", 3), ("SET", 3), ("SHOW", 3), ("SHUTDOWN", 8), ("SPOOL", 3), ("START", 3), ("STARTUP", 7),
            ("STORE", 4), ("TIMING", 4), ("TTITLE", 3), ("UNDEFINE", 5), ("VARIABLE", 3), ("WHENEVER", 8),
            ("XQUERY", 6),
            // SQLcl
            ("INFO", 4), ("DDL", 3), ("LOAD", 4), ("FORMAT", 6), ("ALIAS", 5), ("SCRIPT", 6), ("LIQUIBASE", 2),
            ("LB", 2), ("SODA", 4), ("APEX", 4), ("CD", 2), ("REPEAT", 6), ("SSHTUNNEL", 9), ("TNSPING", 7), ("OERR", 4),
        ]
        for (name, min) in list {
            for len in min...name.count { m[String(name.prefix(len))] = name }
        }
        // LIST/INPUT/RUN/DEL/APPEND/CHANGE skracane do 1 litery kolidowałyby z identyfikatorami — tylko dłuższe formy.
        for single in ["A", "C", "I", "L", "R"] { m.removeValue(forKey: single) }
        m["R"] = "RUN"
        return m
    }()

    /// Polecenia, które dotykają systemu plików lub systemu operacyjnego.
    public static let osCommands: Set<String> = ["HOST", "!", "$", "SPOOL", "@", "@@", "START", "GET", "SAVE", "STORE",
                                                 "EDIT", "CD", "LOAD", "SCRIPT", "COPY"]

    /// Nazwa polecenia SQL*Plus dla pierwszych słów polecenia albo nil (to SQL/PL/SQL).
    static func command(words: [String], firstTokenText: String) -> String? {
        guard let first = words.first else { return nil }
        if first == "@" { return words.count > 1 && words[1] == "@" ? "@@" : "@" }
        if first == "!" || first == "$" { return first }
        if first == "/" { return nil }
        let second = words.count > 1 ? words[1] : ""
        if first == "SET", ["TRANSACTION", "ROLE", "CONSTRAINT", "CONSTRAINTS"].contains(second) { return nil }
        // „DESC” jako słowo SQL występuje tylko w środku polecenia, więc na początku to DESCRIBE.
        guard let cmd = commands[first] else { return nil }
        // „SHOW” vs SQL „SHOW” nie istnieje; „EXEC” → EXECUTE; COMMENT/COMMIT nie są tu (to SQL).
        return cmd
    }
}
