import Foundation

/// Opcje zmiennej podstawiania w składni wzorca (UG 12.3): `&"Nazwa"` albo
/// `&<name="Nazwa" hint="…" type="string" required="yes" default="…" ifempty="…" uppercase="yes" lowercase="yes"
///  readonly="yes" hidden="yes" list="a, b | select …" description="yes" restricted="yes" multiselect="yes"
///  checkbox="wł, wył" prefix="…" suffix="…" lines="4" editor="plain|sql|xml">`.
public struct VariableOptions: Sendable, Hashable {
    public enum ValueType: String, Sendable, Hashable { case none, string, integer, float, date }

    public var name: String
    public var hint: String?
    public var type: ValueType = .none
    public var required = false
    /// Wartość domyślna albo zapytanie (`select …`) zwracające jedną wartość.
    public var defaultValue: String?
    public var ifEmpty: String?
    public var uppercase = false
    public var lowercase = false
    public var readOnly = false
    public var hidden = false
    /// Lista wartości (elementy po przecinku) albo zapytanie (`select …`).
    public var list: String?
    /// Lista ma pary (wartość, opis).
    public var description = false
    public var restricted = false
    public var multiSelect = false
    /// Pole wyboru: (wartość zaznaczona, wartość niezaznaczona).
    public var checkbox: (checked: String, unchecked: String)?
    public var prefix = ""
    public var suffix = ""
    public var lines = 1
    public var editor: String?

    public init(name: String) { self.name = name }

    public static func == (a: Self, b: Self) -> Bool { a.name == b.name && a.list == b.list && a.type == b.type && a.defaultValue == b.defaultValue }
    public func hash(into h: inout Hasher) { h.combine(name) }

    public var listIsQuery: Bool { list?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("select") ?? false }
    public var defaultIsQuery: Bool { defaultValue?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("select") ?? false }

    /// Elementy listy stałej: [(wartość, opis)].
    public var listItems: [(value: String, label: String)] {
        guard let list, !listIsQuery else { return [] }
        let parts = Self.splitList(list)
        if description {
            return stride(from: 0, to: parts.count - 1, by: 2).map { (parts[$0], parts[$0 + 1]) }
        }
        return parts.map { ($0, $0) }
    }

    /// Nazwa zmiennej wiązanej, którą zapytania list zależnych widzą tę zmienną (spacje → podkreślenia, ≤30 znaków).
    public var bindName: String {
        String(name.lowercased().map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" }.prefix(30))
    }

    static func splitList(_ s: String) -> [String] {
        s.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Parsowanie tekstu wystąpienia: `&nazwa`, `&&nazwa.`, `&"Nazwa"`, `&<…>`.
    public static func parse(_ raw: String) -> VariableOptions {
        var body = raw.drop(while: { $0 == "&" })
        if body.hasSuffix(".") { body = body.dropLast() }
        if body.hasPrefix("\""), body.hasSuffix("\""), body.count >= 2 {
            return VariableOptions(name: String(body.dropFirst().dropLast()))
        }
        guard body.hasPrefix("<"), body.hasSuffix(">") else { return VariableOptions(name: String(body)) }
        let attrs = attributes(String(body.dropFirst().dropLast()))
        var o = VariableOptions(name: attrs["name"] ?? attrs[""] ?? "")
        func yes(_ k: String) -> Bool { ["yes", "true", "y", "1"].contains((attrs[k] ?? "").lowercased()) }
        o.hint = attrs["hint"]
        o.type = attrs["type"].flatMap { ValueType(rawValue: $0.lowercased()) } ?? .none
        o.required = yes("required")
        o.defaultValue = attrs["default"]
        o.ifEmpty = attrs["ifempty"]
        o.uppercase = yes("uppercase")
        o.lowercase = yes("lowercase")
        o.readOnly = yes("readonly")
        o.hidden = yes("hidden")
        o.list = attrs["list"]
        o.description = yes("description")
        o.restricted = yes("restricted")
        o.multiSelect = yes("multiselect")
        if let cb = attrs["checkbox"] {
            let p = splitList(cb)
            o.checkbox = (p.first ?? "", p.count > 1 ? p[1] : "")
        }
        o.prefix = attrs["prefix"] ?? ""
        o.suffix = attrs["suffix"] ?? ""
        o.lines = attrs["lines"].flatMap(Int.init) ?? 1
        o.editor = attrs["editor"]
        return o
    }

    /// Atrybuty `klucz="wartość"` (cudzysłowy proste lub typograficzne ” “); pierwszy goły token = nazwa.
    static func attributes(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        let chars = Array(s)
        var i = 0
        func isQuote(_ c: Character) -> Bool { c == "\"" || c == "”" || c == "“" }
        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }
            var key = ""
            while i < chars.count, chars[i] != "=", !chars[i].isWhitespace { key.append(chars[i]); i += 1 }
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            if i < chars.count, chars[i] == "=" {
                i += 1
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                var value = ""
                if i < chars.count, isQuote(chars[i]) {
                    i += 1
                    while i < chars.count, !isQuote(chars[i]) { value.append(chars[i]); i += 1 }
                    i += 1
                } else {
                    while i < chars.count, !chars[i].isWhitespace { value.append(chars[i]); i += 1 }
                }
                out[key.lowercased()] = value
            } else if !key.isEmpty, out[""] == nil {
                out[""] = key.trimmingCharacters(in: CharacterSet(charactersIn: "\"”“"))
            }
        }
        return out
    }

    /// Tekst wstawiany do SQL dla wartości (typ, wielkość liter, ifempty, prefix/suffix, checkbox).
    public func substitution(for value: VariableValue) -> String {
        var raw: [String]
        switch value {
        case .null: raw = []
        case .text(let t): raw = t.isEmpty ? [] : [t]
        case .list(let l): raw = l
        }
        if let cb = checkbox {
            let on = raw.first.map { ["1", "true", "yes", cb.checked.lowercased()].contains($0.lowercased()) } ?? false
            return on ? cb.checked : cb.unchecked
        }
        if raw.isEmpty, let e = ifEmpty { raw = [e] }
        guard !raw.isEmpty else { return "" }
        let items = raw.map { v -> String in
            var v = v
            if uppercase { v = v.uppercased() }
            if lowercase { v = v.lowercased() }
            return type == .string ? "'" + v.replacingOccurrences(of: "'", with: "''") + "'" : v
        }
        return prefix + items.joined(separator: ", ") + suffix
    }
}
