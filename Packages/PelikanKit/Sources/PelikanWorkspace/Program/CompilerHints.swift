import Foundation
import PelikanSQL

/// Konwencje nazw PL/SQL (PD-PROG-005): przedrostki parametrów, zmiennych lokalnych i globalnych (pakietu), stałych,
/// kursorów i typów; puste — bez sprawdzania danej kategorii.
public struct NamingConventions: Sendable, Codable, Hashable {
    public var enabled = false
    public var parameter = "p_"
    public var local = "l_"
    public var global = "g_"
    public var constant = "c_"
    public var cursor = "cur_"
    public var type = "t_"
    public init() {}
}

/// Podpowiedzi kompilatora Pelikana (PD-PROG-005): inspekcje kodu (nieużywane deklaracje, kod martwy, DML bez WHERE,
/// niejawne konwersje, długie identyfikatory) i konwencje nazw, po udanej kompilacji jako komunikaty „hint”.
/// Komentarz `-- Ignore` w linii wycisza podpowiedzi tej linii.
public enum CompilerHints {
    static func ignoredLines(_ text: String) -> Set<Int> {
        var out = Set<Int>()
        for (i, line) in text.components(separatedBy: "\n").enumerated() where line.range(of: #"--\s*ignore\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            out.insert(i)
        }
        return out
    }

    /// Naruszenia konwencji nazw: (offset nazwy, komunikat).
    public static func namingViolations(_ text: String, conventions c: NamingConventions) -> [(offset: Int, message: String)] {
        guard c.enabled else { return [] }
        var out: [(Int, String)] = []
        func check(_ n: OutlineNode, prefix: String, what: String) {
            guard !prefix.isEmpty, !n.name.lowercased().hasPrefix(prefix.lowercased()) else { return }
            out.append((n.nameOffset, L10n.tr("\(what) „\(n.name)” nie zaczyna się od „\(prefix)”")))
        }
        func walk(_ nodes: [OutlineNode], inPackage: Bool) {
            for n in nodes {
                switch n.kind {
                case .parameter: check(n, prefix: c.parameter, what: L10n.tr("Parametr"))
                case .variable: check(n, prefix: inPackage ? c.global : c.local, what: inPackage ? L10n.tr("Zmienna globalna") : L10n.tr("Zmienna lokalna"))
                case .constant: check(n, prefix: c.constant, what: L10n.tr("Stała"))
                case .cursor: check(n, prefix: c.cursor, what: L10n.tr("Kursor"))
                case .typeDeclaration: check(n, prefix: c.type, what: L10n.tr("Typ"))
                default: break
                }
                // Deklaracje bezpośrednio w pakiecie (specyfikacja i ciało) są globalne; w podprogramach — lokalne.
                let packageLevel = [.package, .packageBody].contains(n.kind)
                walk(n.children, inPackage: packageLevel || (inPackage && [.declareSection].contains(n.kind)))
            }
        }
        walk(PLSQLOutline.parse(text), inPackage: false)
        return out
    }

    /// Podpowiedzi dla jednostki: linie liczone od 1 w ramach jednostki.
    public static func hints(for unit: String, conventions: NamingConventions, identifierLimit: Int = 30) -> [(line: Int, column: Int, text: String)] {
        let ignored = ignoredLines(unit)
        func position(_ offset: Int) -> (Int, Int) {
            let prefix = (unit as NSString).substring(to: min(offset, (unit as NSString).length))
            let lines = prefix.components(separatedBy: "\n")
            return (lines.count, (lines.last?.count ?? 0) + 1)
        }
        var out: [(Int, Int, String)] = []
        for d in CodeInspections.inspect(unit, identifierLimit: identifierLimit) {
            let (l, c) = position(d.range.lowerBound)
            if !ignored.contains(l - 1) { out.append((l, c, d.message)) }
        }
        for v in namingViolations(unit, conventions: conventions) {
            let (l, c) = position(v.offset)
            if !ignored.contains(l - 1) { out.append((l, c, v.message)) }
        }
        return out.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
    }
}
