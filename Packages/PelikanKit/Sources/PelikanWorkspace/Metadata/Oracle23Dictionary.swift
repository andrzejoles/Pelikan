import Foundation
import PelikanDB

/// DDL asercji i adnotacji 23ai/26ai ze słownika (DBMS_METADATA ich nie obsługuje — ORA-31600), PD-OB-002.
enum Oracle23Dictionary {
    static func ddl(of o: DBObject, in s: any DatabaseSession) async throws -> String {
        let b = [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name))]
        if o.type == .assertion {
            // DEFINITION_SQL zawiera całe polecenie CREATE ASSERTION z odroczeniem i stanem.
            let (_, rows) = try await s.queryAll("select definition_sql from all_assertions where owner = :o and assertion_name = :n", binds: b, limit: 1)
            guard let text = rows.first?.first?.displayText else {
                throw CommandError.notAvailable(L10n.tr("Brak asercji \(o.qualifiedName)"))
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines) + ";"
        }
        let (_, rows) = try await s.queryAll("""
            select object_type, object_name, column_name, annotation_value from all_annotations_usage
            where annotation_owner = :o and annotation_name = :n order by object_type, object_name, column_name
            """, binds: b, limit: 10_000)
        let usages = rows.map { Usage(objectType: $0[0].displayText ?? "", object: $0[1].displayText ?? "", column: $0[2].displayText,
                                      value: $0[3].displayText) }
        return annotationScript(name: o.name, owner: o.owner, usages: usages)
    }

    struct Usage: Sendable, Hashable {
        var objectType: String
        var object: String
        var column: String?
        var value: String?
    }

    /// Skrypt nadający adnotację tam, gdzie jest używana (ALTER … ANNOTATIONS (ADD …)).
    static func annotationScript(name: String, owner: String, usages: [Usage]) -> String {
        let id = ResultExporter.identifier
        let annotation = id(name) + " " // wartość opcjonalna
        var lines = ["-- " + L10n.tr("Adnotacja \(name): użycie w schemacie \(owner)")]
        for u in usages {
            let value = u.value.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" } ?? ""
            let add = "ANNOTATIONS (ADD " + (annotation + value).trimmingCharacters(in: .whitespaces) + ")"
            let target = "\(id(owner)).\(id(u.object))"
            if let c = u.column {
                lines.append(u.objectType == "DOMAIN" ? "ALTER DOMAIN \(target) \(add);" : "ALTER TABLE \(target) MODIFY (\(id(c)) \(add));")
            } else {
                lines.append("ALTER \(u.objectType) \(target) \(add);")
            }
        }
        if usages.isEmpty { lines.append("-- " + L10n.tr("(nieużywana)")) }
        return lines.joined(separator: "\n")
    }
}
