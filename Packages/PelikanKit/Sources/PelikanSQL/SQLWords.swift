/// Grupy słów dla reguł wielkości liter formatera (D174): typy danych, funkcje wbudowane SQL i PL/SQL, pakiety
/// dostarczane z bazą. Nazwy z dokumentacji Oracle („Data Types”, „SQL Functions”, „PL/SQL Packages and Types”).
public enum SQLWords {
    public static let dataTypes: Set<String> = [
        "NUMBER", "NUMERIC", "DECIMAL", "DEC", "INTEGER", "INT", "SMALLINT", "FLOAT", "REAL", "DOUBLE", "PRECISION",
        "BINARY_FLOAT", "BINARY_DOUBLE", "PLS_INTEGER", "BINARY_INTEGER", "SIMPLE_INTEGER", "NATURAL", "NATURALN",
        "POSITIVE", "POSITIVEN", "SIGNTYPE", "SIMPLE_FLOAT", "SIMPLE_DOUBLE", "BOOLEAN", "VARCHAR2", "VARCHAR",
        "NVARCHAR2", "CHAR", "NCHAR", "CHARACTER", "VARYING", "STRING", "LONG", "RAW", "CLOB", "NCLOB", "BLOB", "BFILE",
        "DATE", "TIMESTAMP", "INTERVAL", "ROWID", "UROWID", "XMLTYPE", "JSON", "VECTOR", "SYS_REFCURSOR", "ANYDATA",
        "ANYTYPE", "ANYDATASET", "SDO_GEOMETRY", "MLSLABEL",
    ]

    /// Funkcje wbudowane — gdy po nazwie jest „(”.
    public static let functions: Set<String> = [
        // Liczbowe
        "ABS", "ACOS", "ASIN", "ATAN", "ATAN2", "BITAND", "CEIL", "COS", "COSH", "EXP", "FLOOR", "LN", "LOG", "MOD",
        "NANVL", "POWER", "REMAINDER", "ROUND", "SIGN", "SIN", "SINH", "SQRT", "TAN", "TANH", "TRUNC", "WIDTH_BUCKET",
        // Znakowe
        "ASCII", "CHR", "CONCAT", "INITCAP", "INSTR", "INSTRB", "LENGTH", "LENGTHB", "LOWER", "LPAD", "LTRIM", "NLS_INITCAP",
        "NLS_LOWER", "NLS_UPPER", "NLSSORT", "REGEXP_COUNT", "REGEXP_INSTR", "REGEXP_LIKE", "REGEXP_REPLACE",
        "REGEXP_SUBSTR", "REPLACE", "RPAD", "RTRIM", "SOUNDEX", "SUBSTR", "SUBSTRB", "TRANSLATE", "TRIM", "UPPER",
        "UNISTR",
        // Daty
        "ADD_MONTHS", "CURRENT_DATE", "CURRENT_TIMESTAMP", "EXTRACT", "FROM_TZ", "LAST_DAY", "LOCALTIMESTAMP",
        "MONTHS_BETWEEN", "NEW_TIME", "NEXT_DAY", "NUMTODSINTERVAL", "NUMTOYMINTERVAL", "SYS_EXTRACT_UTC", "TO_DSINTERVAL",
        "TO_YMINTERVAL", "TZ_OFFSET",
        // Konwersje
        "CAST", "CHARTOROWID", "CONVERT", "HEXTORAW", "RAWTOHEX", "ROWIDTOCHAR", "TO_BINARY_DOUBLE", "TO_BINARY_FLOAT",
        "TO_BLOB", "TO_CHAR", "TO_CLOB", "TO_DATE", "TO_LOB", "TO_MULTI_BYTE", "TO_NCHAR", "TO_NCLOB", "TO_NUMBER",
        "TO_SINGLE_BYTE", "TO_TIMESTAMP", "TO_TIMESTAMP_TZ", "VALIDATE_CONVERSION",
        // Porównania i NULL
        "COALESCE", "DECODE", "GREATEST", "LEAST", "LNNVL", "NULLIF", "NVL", "NVL2",
        // Agregujące i analityczne
        "AVG", "COLLECT", "CORR", "COUNT", "COVAR_POP", "COVAR_SAMP", "CUME_DIST", "DENSE_RANK", "FIRST_VALUE",
        "LAG", "LAST_VALUE", "LEAD", "LISTAGG", "MAX", "MEDIAN", "MIN", "NTH_VALUE", "NTILE", "PERCENT_RANK",
        "PERCENTILE_CONT", "PERCENTILE_DISC", "RANK", "RATIO_TO_REPORT", "REGR_SLOPE", "ROW_NUMBER", "STDDEV", "SUM",
        "VAR_POP", "VAR_SAMP", "VARIANCE", "APPROX_COUNT_DISTINCT", "GROUPING", "GROUPING_ID",
        // Pozostałe
        "SYS_CONTEXT", "SYS_GUID", "USERENV", "ORA_HASH", "STANDARD_HASH", "DUMP", "VSIZE", "EMPTY_BLOB", "EMPTY_CLOB",
        "JSON_VALUE", "JSON_QUERY", "JSON_TABLE", "JSON_OBJECT", "JSON_ARRAY", "JSON_OBJECTAGG", "JSON_ARRAYAGG",
        "JSON_EXISTS", "JSON_SERIALIZE", "XMLAGG", "XMLELEMENT", "XMLFOREST", "XMLQUERY", "XMLTABLE", "XMLCAST",
        "SQLCODE", "SQLERRM", "RAISE_APPLICATION_ERROR",
    ]

    /// Pakiet dostarczany z bazą (`DBMS_OUTPUT` w `DBMS_OUTPUT.PUT_LINE`).
    public static func isPackage(_ upper: String) -> Bool {
        upper.hasPrefix("DBMS_") || upper.hasPrefix("UTL_") || upper.hasPrefix("APEX_") || upper.hasPrefix("OWA_") || upper.hasPrefix("CTX_")
            || upper.hasPrefix("SDO_") || ["HTP", "HTF", "OWA", "WPG_DOCLOAD", "STANDARD"].contains(upper)
    }
}
