import Foundation
import PelikanDB

/// Zmiana nazwy i duplikowanie obiektów z Object Browsera (PD-OB-016).
public enum ObjectRename {
    static func ident(_ s: String) -> String { ResultExporter.identifier(s) }

    /// Nazwa wpisana przez użytkownika: `abc` → `ABC`, `"Abc"` — dosłownie; nil — niepoprawna.
    public static func normalizedName(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 3, s.hasPrefix("\""), s.hasSuffix("\"") {
            let inner = String(s.dropFirst().dropLast())
            return inner.contains("\"") || inner.utf8.count > 128 ? nil : inner
        }
        guard s.range(of: #"^[A-Za-z][A-Za-z0-9_$#]{0,127}$"#, options: .regularExpression) != nil else { return nil }
        return s.uppercased()
    }

    /// Typy, którym można zmienić nazwę.
    public static let renamable: Set<DBObjectType> = [.table, .view, .sequence, .synonym, .index, .trigger]

    /// Polecenie zmiany nazwy obiektu. Widoki, sekwencje i synonimy prywatne — `RENAME` (tylko we własnym schemacie).
    public static func statement(_ o: DBObject, to newName: String, currentSchema: String) throws -> String {
        let new = ident(newName)
        switch o.type {
        case .table: return "ALTER TABLE \(o.qualifiedName) RENAME TO \(new)"
        case .index: return "ALTER INDEX \(o.qualifiedName) RENAME TO \(new)"
        case .trigger: return "ALTER TRIGGER \(o.qualifiedName) RENAME TO \(new)"
        case .view, .sequence, .synonym:
            guard o.owner == currentSchema else {
                throw CommandError.notAvailable(L10n.tr("RENAME działa tylko w bieżącym schemacie (\(currentSchema))"))
            }
            return "RENAME \(ident(o.name)) TO \(new)"
        default:
            throw CommandError.notAvailable(L10n.tr("Zmiana nazwy nie jest dostępna dla \(o.type.rawValue)"))
        }
    }

    /// Zmiana nazwy elementu tabeli: kolumny, więzu albo indeksu.
    public static func childStatement(table: DBObject, kind: DBObjectChild.Kind, name: String, to newName: String) throws -> String {
        let new = ident(newName)
        switch kind {
        case .column: return "ALTER TABLE \(table.qualifiedName) RENAME COLUMN \(ident(name)) TO \(new)"
        case .constraint: return "ALTER TABLE \(table.qualifiedName) RENAME CONSTRAINT \(ident(name)) TO \(new)"
        case .index: return "ALTER INDEX \(ident(table.owner)).\(ident(name)) RENAME TO \(new)"
        case .trigger: return "ALTER TRIGGER \(ident(table.owner)).\(ident(name)) RENAME TO \(new)"
        default: throw CommandError.notAvailable(L10n.tr("Zmiana nazwy nie jest dostępna dla tego elementu"))
        }
    }

    /// Skrypt kopii obiektu pod nową nazwą: nazwa w nagłówku CREATE zastąpiona; w tabeli nazwy więzów zawierające
    /// starą nazwę dostają nową (inaczej prefiks nowej nazwy), żeby nie kolidowały z oryginałem.
    public static func duplicateScript(_ script: String, object o: DBObject, newName: String) throws -> String {
        let typeWords = (o.type == .packageBody ? "PACKAGE\\s+BODY" : o.type == .typeBody ? "TYPE\\s+BODY"
                         : o.type.rawValue.split(separator: " ").joined(separator: "\\s+"))
        let pattern = #"(?i)^(\s*CREATE\s+(?:OR\s+REPLACE\s+)?(?:(?:NON)?EDITIONABLE\s+|NO\s+FORCE\s+|FORCE\s+|(?:GLOBAL|PRIVATE)\s+TEMPORARY\s+|UNIQUE\s+|BITMAP\s+|PUBLIC\s+|IMMUTABLE\s+|BLOCKCHAIN\s+|SHARDED\s+|DUPLICATED\s+)*"#
            + typeWords + #"\s+(?:IF\s+NOT\s+EXISTS\s+)?)((?:"[^"]+"|[A-Za-z0-9_$#]+)\s*\.\s*)?("[^"]+"|[A-Za-z0-9_$#]+)"#
        let re = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let ns = script as NSString
        guard let m = re.firstMatch(in: script, range: NSRange(location: 0, length: ns.length)) else {
            throw CommandError.notAvailable(L10n.tr("Nie rozpoznano nagłówka CREATE w DDL \(o.qualifiedName)"))
        }
        let ownerPart = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
        var out = ns.replacingCharacters(in: NSRange(location: m.range.location, length: m.range.length),
                                         with: ns.substring(with: m.range(at: 1)) + ownerPart + ident(newName))
        // Koniec ciała pakietu/typu: END nazwa; → END nowa_nazwa;
        if o.type.isProgram {
            let endRe = try NSRegularExpression(pattern: #"(?i)(\bEND\s+)("?)"# + NSRegularExpression.escapedPattern(for: o.name) + #"\2(\s*;)"#)
            let all = NSRange(location: 0, length: (out as NSString).length)
            out = endRe.stringByReplacingMatches(in: out, range: all, withTemplate: "$1" + NSRegularExpression.escapedTemplate(for: ident(newName)) + "$3")
        }
        if o.type == .table {
            let cRe = try NSRegularExpression(pattern: #"(?i)(\bCONSTRAINT\s+)"([^"]+)""#)
            let matches = cRe.matches(in: out, range: NSRange(location: 0, length: (out as NSString).length)).reversed()
            for c in matches {
                let old = (out as NSString).substring(with: c.range(at: 2))
                var renamed = old.contains(o.name) ? old.replacingOccurrences(of: o.name, with: newName) : newName + "_" + old
                if renamed.utf8.count > 128 { renamed = String(renamed.prefix(128)) }
                out = (out as NSString).replacingCharacters(in: c.range(at: 2), with: renamed)
            }
        }
        return out
    }
}

/// Upuszczenie obiektu z Object Browsera (PD-OB-010, UG 23.11 Drag and Drop): tekst w edytorze albo akcja na obszarze okien.
public enum BrowserDropAction: String, Codable, CaseIterable, Sendable {
    /// Menu z wyborem (jak przy przeciąganiu z klawiszem Control).
    case ask
    case name, qualifiedName, columns, select, insert, update, delete, call, ddl

    public var displayName: String {
        switch self {
        case .ask: L10n.tr("Pytaj (menu)")
        case .name: L10n.tr("Nazwa")
        case .qualifiedName: L10n.tr("Nazwa z właścicielem")
        case .columns: L10n.tr("Lista kolumn")
        case .select: "SELECT"
        case .insert: "INSERT"
        case .update: "UPDATE"
        case .delete: "DELETE"
        case .call: L10n.tr("Wywołanie programu")
        case .ddl: L10n.tr("DDL / źródło")
        }
    }

    /// Akcje sensowne dla typu obiektu (pozycje menu po upuszczeniu).
    public static func actions(for t: DBObjectType) -> [BrowserDropAction] {
        var out: [BrowserDropAction] = [.name, .qualifiedName]
        if [.table, .view, .materializedView, .synonym].contains(t) { out += [.columns, .select, .insert, .update, .delete] }
        if [.procedure, .function].contains(t) { out.append(.call) }
        out.append(.ddl)
        return out
    }

    /// Rodzaj kodu generatora (SD-GEN-001) dla akcji SQL.
    var codeKind: CodeGenerator.Kind? {
        switch self {
        case .select: .select
        case .insert: .insert
        case .update: .update
        case .delete: .delete
        case .call: .call
        default: nil
        }
    }
}

/// Akcja upuszczenia obiektu na obszar okien (poza edytorem) — komenda Object Browsera.
public enum BrowserWorkspaceDrop: String, Codable, CaseIterable, Sendable {
    case edit, queryData, ddl, describe, properties

    public var displayName: String {
        switch self {
        case .edit: L10n.tr("Edytuj")
        case .queryData: L10n.tr("Pokaż dane")
        case .ddl: L10n.tr("DDL")
        case .describe: L10n.tr("Opis")
        case .properties: L10n.tr("Właściwości")
        }
    }

    public var command: CommandID { CommandID(rawValue: "ob." + rawValue) }

    /// Akcja dla typu: programy i obiekty bez danych nie mają „Pokaż dane” — wtedy Edytuj.
    public func command(for t: DBObjectType) -> CommandID {
        self == .queryData && !t.hasData ? "ob.edit" : command
    }
}

public enum BrowserDrop {
    /// Folder upuszczony w edytorze: nazwy elementów po przecinku (UG 21.1).
    public static func namesList(_ names: [String]) -> String {
        names.map(ResultExporter.displayIdentifier).joined(separator: ", ")
    }

    /// Nazwa obiektu do wstawienia: bez właściciela w bieżącym schemacie.
    public static func name(_ o: DBObject, currentSchema: String, qualified: Bool) -> String {
        qualified || o.owner != currentSchema ? ResultExporter.displayQualified(owner: o.owner, name: o.name) : ResultExporter.displayIdentifier(o.name)
    }
}
