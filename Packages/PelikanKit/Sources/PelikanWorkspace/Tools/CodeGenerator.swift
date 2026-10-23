import Foundation
import PelikanDB

/// Generowanie kodu z obiektu bazy (SD-GEN-001): SQL dla tabel i widoków, wywołanie programu, fragmenty Java JDBC
/// i Python (python-oracledb) ze zmiennymi wiązanymi zamiast wartości. Łańcuch połączenia w kodzie: alias połączenia
/// (bez hasła, hosta i użytkownika — uzupełnia programista).
public enum CodeGenerator {
    public enum Kind: String, Sendable, CaseIterable {
        case select, insert, update, delete, call, javaSelect, javaInsert, pythonSelect, pythonInsert

        public var displayName: String {
            switch self {
            case .select: "SELECT"
            case .insert: "INSERT"
            case .update: "UPDATE"
            case .delete: "DELETE"
            case .call: L10n.tr("Wywołanie programu")
            case .javaSelect: L10n.tr("Java JDBC: zapytanie")
            case .javaInsert: L10n.tr("Java JDBC: INSERT")
            case .pythonSelect: L10n.tr("Python: zapytanie")
            case .pythonInsert: L10n.tr("Python: INSERT")
            }
        }

        public var needsColumns: Bool { self != .call }
    }

    public struct Column: Sendable, Hashable {
        public var name: String
        public var type: String
        public var isKey: Bool
        public init(name: String, type: String, isKey: Bool = false) { self.name = name; self.type = type; self.isKey = isKey }
    }

    static func ident(_ n: String) -> String { ResultExporter.identifier(n) }

    /// Nazwa zmiennej wiązanej / pola z nazwy kolumny (małe litery, znaki niedozwolone → `_`).
    static func variable(_ n: String) -> String {
        let s = n.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let v = String(s)
        return v.first?.isLetter == true ? v : "c_" + v
    }

    static func camel(_ n: String) -> String {
        let parts = variable(n).split(separator: "_").map(String.init)
        guard let first = parts.first else { return "value" }
        return first + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// Typ JDBC getter dla typu Oracle.
    static func jdbcGetter(_ type: String) -> (String, String) {
        let t = type.uppercased()
        if t.hasPrefix("NUMBER") || t.hasPrefix("INTEGER") || t.hasPrefix("FLOAT") || t.hasPrefix("BINARY") { return ("java.math.BigDecimal", "getBigDecimal") }
        if t.hasPrefix("DATE") || t.hasPrefix("TIMESTAMP") { return ("java.sql.Timestamp", "getTimestamp") }
        if t.hasPrefix("CLOB") || t.hasPrefix("NCLOB") { return ("String", "getString") }
        if t.hasPrefix("BLOB") || t.hasPrefix("RAW") { return ("byte[]", "getBytes") }
        return ("String", "getString")
    }

    public static func generate(_ kind: Kind, object o: DBObject, columns: [Column], connectionAlias: String = "ALIAS") -> String {
        let table = "\(ident(o.owner)).\(ident(o.name))"
        let cols = columns.map(\.name)
        let keys = columns.filter(\.isKey).map(\.name)
        let whereCols = keys.isEmpty ? Array(cols.prefix(1)) : keys
        let colList = cols.map(ident).joined(separator: ", ")
        let binds = cols.map { ":" + variable($0) }.joined(separator: ", ")
        let whereClause = whereCols.map { "\(ident($0)) = :\(variable($0))" }.joined(separator: " AND ")
        let selectSQL = "SELECT \(cols.map(ident).joined(separator: ",\n       "))\n  FROM \(table)"
        let insertSQL = "INSERT INTO \(table) (\(colList))\nVALUES (\(binds))"
        switch kind {
        case .select:
            return selectSQL + "\n WHERE \(whereClause);\n"
        case .insert:
            return insertSQL + ";\n"
        case .update:
            let sets = cols.filter { !whereCols.contains($0) }.map { "\(ident($0)) = :\(variable($0))" }.joined(separator: ",\n       ")
            return "UPDATE \(table)\n   SET \(sets.isEmpty ? "/* " + L10n.tr("brak kolumn poza kluczem") + " */" : sets)\n WHERE \(whereClause);\n"
        case .delete:
            return "DELETE FROM \(table)\n WHERE \(whereClause);\n"
        case .call:
            return ""
        case .javaSelect:
            let sqlLit = "SELECT \(colList) FROM \(table) WHERE \(whereClause.replacingOccurrences(of: #":\w+"#, with: "?", options: .regularExpression))"
            var j = "// \(L10n.tr("Połączenie: alias")) \(connectionAlias) — \(L10n.tr("dane logowania z konfiguracji aplikacji, nie w kodzie"))\n"
            j += "String sql = \"\(sqlLit)\";\n"
            j += "try (PreparedStatement ps = connection.prepareStatement(sql)) {\n"
            for (i, w) in whereCols.enumerated() { j += "    ps.setObject(\(i + 1), \(camel(w)));\n" }
            j += "    try (ResultSet rs = ps.executeQuery()) {\n        while (rs.next()) {\n"
            for c in columns {
                let (type, getter) = jdbcGetter(c.type)
                j += "            \(type) \(camel(c.name)) = rs.\(getter)(\"\(c.name)\");\n"
            }
            j += "        }\n    }\n}\n"
            return j
        case .javaInsert:
            let qs = cols.map { _ in "?" }.joined(separator: ", ")
            var j = "String sql = \"INSERT INTO \(table) (\(colList)) VALUES (\(qs))\";\n"
            j += "try (PreparedStatement ps = connection.prepareStatement(sql)) {\n"
            for (i, c) in cols.enumerated() { j += "    ps.setObject(\(i + 1), \(camel(c)));\n" }
            j += "    ps.executeUpdate();\n}\n"
            return j
        case .pythonSelect:
            var p = "# \(L10n.tr("Połączenie: alias")) \(connectionAlias) — oracledb.connect(dsn=\"\(connectionAlias)\", …)\n"
            p += "sql = \"\"\"\n\(selectSQL)\n WHERE \(whereClause)\n\"\"\"\n"
            p += "with connection.cursor() as cur:\n"
            p += "    cur.execute(sql, {\(whereCols.map { "\"\(variable($0))\": \(variable($0))" }.joined(separator: ", "))})\n"
            p += "    for \(cols.map(variable).joined(separator: ", ")) in cur:\n        pass\n"
            return p
        case .pythonInsert:
            var p = "sql = \"\"\"\n\(insertSQL)\n\"\"\"\n"
            p += "with connection.cursor() as cur:\n"
            p += "    cur.execute(sql, {\(cols.map { "\"\(variable($0))\": \(variable($0))" }.joined(separator: ", "))})\n"
            p += "connection.commit()\n"
            return p
        }
    }
}
