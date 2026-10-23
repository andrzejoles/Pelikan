/// Słowa kluczowe do podświetlania (zarezerwowane słowa SQL i PL/SQL z dokumentacji Oracle —
/// „Oracle SQL Reserved Words”, „PL/SQL Reserved Words and Keywords” — oraz najczęstsze słowa kluczowe).
/// Nazwy funkcji wbudowanych i pakietów DBMS_* podświetla osobno edytor (słownik z metadanych).
public enum Keywords {
    public static let reserved: Set<String> = [
        "ACCESS", "ADD", "ALL", "ALTER", "AND", "ANY", "AS", "ASC", "AUDIT", "BETWEEN", "BY", "CHAR", "CHECK",
        "CLUSTER", "COLUMN", "COMMENT", "COMPRESS", "CONNECT", "CREATE", "CURRENT", "DATE", "DECIMAL", "DEFAULT",
        "DELETE", "DESC", "DISTINCT", "DROP", "ELSE", "EXCLUSIVE", "EXISTS", "FILE", "FLOAT", "FOR", "FROM", "GRANT",
        "GROUP", "HAVING", "IDENTIFIED", "IMMEDIATE", "IN", "INCREMENT", "INDEX", "INITIAL", "INSERT", "INTEGER",
        "INTERSECT", "INTO", "IS", "LEVEL", "LIKE", "LOCK", "LONG", "MAXEXTENTS", "MINUS", "MLSLABEL", "MODE",
        "MODIFY", "NOAUDIT", "NOCOMPRESS", "NOT", "NOWAIT", "NULL", "NUMBER", "OF", "OFFLINE", "ON", "ONLINE",
        "OPTION", "OR", "ORDER", "PCTFREE", "PRIOR", "PUBLIC", "RAW", "RENAME", "RESOURCE", "REVOKE", "ROW",
        "ROWID", "ROWNUM", "ROWS", "SELECT", "SESSION", "SET", "SHARE", "SIZE", "SMALLINT", "START", "SUCCESSFUL",
        "SYNONYM", "SYSDATE", "TABLE", "THEN", "TO", "TRIGGER", "UID", "UNION", "UNIQUE", "UPDATE", "USER",
        "VALIDATE", "VALUES", "VARCHAR", "VARCHAR2", "VIEW", "WHENEVER", "WHERE", "WITH",
    ]

    public static let plsql: Set<String> = [
        "BEGIN", "BODY", "CASE", "CLOSE", "CONSTANT", "CURSOR", "DECLARE", "ELSIF", "END", "EXCEPTION", "EXIT",
        "FETCH", "FUNCTION", "GOTO", "IF", "LOOP", "OPEN", "OTHERS", "OUT", "PACKAGE", "PRAGMA", "PROCEDURE",
        "RAISE", "RECORD", "REF", "RETURN", "REVERSE", "ROWTYPE", "SUBTYPE", "TYPE", "WHEN", "WHILE", "FORALL",
        "BULK", "COLLECT", "LIMIT", "PIPELINED", "PIPE", "DETERMINISTIC", "PARALLEL_ENABLE", "RESULT_CACHE",
        "AUTHID", "DEFINER", "AUTONOMOUS_TRANSACTION", "EXCEPTION_INIT", "SERIALLY_REUSABLE", "RESTRICT_REFERENCES",
        "INLINE", "UDF", "NOCOPY", "SAVE", "EXCEPTIONS", "INDICES", "BOOLEAN", "PLS_INTEGER", "BINARY_INTEGER",
        "NATURAL", "NATURALN", "POSITIVE", "POSITIVEN", "SIGNTYPE", "SIMPLE_INTEGER", "VARRAY", "OBJECT",
        "MEMBER", "STATIC", "CONSTRUCTOR", "MAP", "SELF", "OVERRIDING", "FINAL", "INSTANTIABLE", "UNDER",
        "EDITIONABLE", "NONEDITIONABLE", "ACCESSIBLE", "CONTINUE", "CALL", "LANGUAGE", "EXTERNAL", "LIBRARY",
        "MLE", "MODULE", "SIGNATURE", "ENV", "JAVASCRIPT", "TRUE", "FALSE", "SQLCODE", "SQLERRM", "NEXT",
        "TRIGGER", "BEFORE", "AFTER", "INSTEAD", "EACH", "REFERENCING", "FOLLOWS", "PRECEDES", "COMPOUND",
    ]

    public static let sql: Set<String> = [
        "JOIN", "INNER", "OUTER", "LEFT", "RIGHT", "FULL", "CROSS", "NATURAL", "USING", "LATERAL", "APPLY",
        "MERGE", "MATCHED", "TRUNCATE", "COMMIT", "ROLLBACK", "SAVEPOINT", "TRANSACTION", "WORK", "PURGE",
        "FLASHBACK", "EXPLAIN", "PLAN", "STATEMENT_ID", "PARTITION", "SUBPARTITION", "OVER", "WITHIN", "FILTER",
        "FETCH", "FIRST", "NEXT", "ONLY", "OFFSET", "PERCENT", "TIES", "PIVOT", "UNPIVOT", "MODEL", "RETURNING",
        "CONSTRAINT", "PRIMARY", "FOREIGN", "KEY", "REFERENCES", "CASCADE", "ENABLE", "DISABLE", "NOVALIDATE",
        "RELY", "DEFERRABLE", "DEFERRED", "INITIALLY", "SEQUENCE", "MATERIALIZED", "TEMPORARY", "GLOBAL",
        "PRESERVE", "TABLESPACE", "STORAGE", "LOGGING", "NOLOGGING", "CACHE", "NOCACHE", "CYCLE", "NOCYCLE",
        "MAXVALUE", "MINVALUE", "NOMAXVALUE", "NOMINVALUE", "ORDER", "NOORDER", "GENERATED", "ALWAYS", "IDENTITY",
        "VIRTUAL", "INVISIBLE", "VISIBLE", "NULLS", "LAST", "SIBLINGS", "NOCYCLE", "CONNECT_BY_ROOT", "CONNECT_BY_ISLEAF",
        "SYSTIMESTAMP", "CURRENT_DATE", "CURRENT_TIMESTAMP", "LOCALTIMESTAMP", "DBTIMEZONE", "SESSIONTIMEZONE",
        "TIMESTAMP", "INTERVAL", "YEAR", "MONTH", "DAY", "HOUR", "MINUTE", "SECOND", "ZONE", "LOCAL", "TIME",
        "CLOB", "NCLOB", "BLOB", "BFILE", "NCHAR", "NVARCHAR2", "BINARY_FLOAT", "BINARY_DOUBLE", "UROWID", "XMLTYPE",
        "JSON", "VECTOR", "DOMAIN", "ANNOTATIONS", "SHARDED", "DUPLICATED", "BLOCKCHAIN", "IMMUTABLE",
        "EDITION", "EDITIONING", "FORCE", "NOFORCE", "REPLACE", "SYSTEM", "ROLE", "PROFILE", "DIRECTORY",
        "CONTEXT", "DATABASE", "LINK", "SHARED", "NOCOPY", "ANALYZE", "STATISTICS", "COMPUTE", "ESTIMATE",
        "WAIT", "SKIP", "LOCKED", "SEARCH", "DEPTH", "BREADTH", "RECURSIVE", "DIMENSION", "MEASURES", "RULES",
        "KEEP", "DENSE_RANK", "IGNORE", "RESPECT", "PRECEDING", "FOLLOWING", "UNBOUNDED", "RANGE", "GROUPS",
        "EXCLUDE", "NO", "OTHERS", "CUBE", "ROLLUP", "GROUPING", "SETS", "SAMPLE", "SEED", "VERSIONS", "SCN",
        "PERIOD", "EXTRACT", "TREAT", "MULTISET", "THE", "TABLE", "VARYING", "CHARACTER", "BYTE", "CHAR_CS",
        "IF", "INCLUDING", "CONTENTS", "DATAFILES", "QUOTA", "UNLIMITED", "EXPIRE", "ACCOUNT", "UNLOCK",
        "PASSWORD", "ADMIN", "CONTAINER", "PRIVILEGES", "EXECUTE", "DEBUG", "UNDER", "INHERIT", "TRANSLATE",
        "COLUMNS", "NESTED", "PATH", "ORDINALITY", "ERROR", "EMPTY", "ON", "ABSENT", "STRICT", "LAX", "PRETTY",
        "ASCII", "WRAPPER", "WITHOUT", "CONDITIONAL", "UNCONDITIONAL", "ARRAY", "SCALAR", "FORMAT",
    ]

    /// Wszystkie słowa kluczowe jako tablice UTF-16 (szybkie sprawdzanie w lekserze bez tworzenia String).
    static let all: Set<[UInt16]> = Set(reserved.union(plsql).union(sql).map { Array($0.utf16) })
    static let maxLength = all.map(\.count).max() ?? 0

    static func isKeyword(_ text: [UInt16], _ start: Int, _ length: Int) -> Bool {
        guard length <= maxLength else { return false }
        var buf = [UInt16](repeating: 0, count: length)
        for k in 0..<length {
            let c = text[start + k]
            if c >= 0x80 { return false }
            buf[k] = (c >= 0x61 && c <= 0x7A) ? c - 0x20 : c
        }
        return all.contains(buf)
    }

    public static func isKeyword(_ word: String) -> Bool {
        let u = Array(word.utf16)
        return isKeyword(u, 0, u.count)
    }
}
