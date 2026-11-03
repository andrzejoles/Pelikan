import Foundation
import PelikanSQL

/// Konwencje nazw PL/SQL (PD-PROG-005, D215): przedrostki parametrów (osobno IN, OUT i IN OUT), zmiennych lokalnych
/// i pakietu (osobno w ciele i w specyfikacji), stałych, kursorów i typów. Pole może mieć kilka przedrostków po
/// przecinku (`IO_, O_`); puste — bez sprawdzania, a puste OUT / IN OUT / zmienne specyfikacji — jak IN / zmienne ciała.
public struct NamingConventions: Sendable, Codable, Hashable {
    public var enabled = false
    /// Parametry IN (i bez trybu).
    public var parameter = "p_"
    public var parameterOut = ""
    public var parameterInOut = ""
    public var local = "l_"
    /// Zmienne pakietu w ciele (prywatne).
    public var global = "g_"
    /// Zmienne pakietu w specyfikacji (publiczne).
    public var publicGlobal = ""
    public var constant = "c_"
    public var cursor = "cur_"
    public var type = "t_"
    public init() {}

    /// Konwencja pakietów Oracle Retail (RMS) — przedrostki najczęstsze w pakietach repozytorium właściciela (D215):
    /// `I_item IN`, `O_error_message IN OUT`, `O_exists OUT`, `L_count`, `LP_vdate` (ciało), `GP_…` (specyfikacja),
    /// kursory `C_…`; stałe bez jednego przedrostka (`K_`, `GP_`, `CON_`), typy — `TYP_`, `T_`.
    public static var rms: NamingConventions {
        var c = NamingConventions()
        c.enabled = true
        c.parameter = "I_"
        c.parameterOut = "O_"
        c.parameterInOut = "O_, IO_"
        c.local = "L_"
        c.global = "LP_"
        c.publicGlobal = "GP_"
        c.constant = ""
        c.cursor = "C_"
        c.type = ""
        return c
    }

    enum CodingKeys: String, CodingKey { case enabled, parameter, parameterOut, parameterInOut, local, global, publicGlobal, constant, cursor, type }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NamingConventions()
        func v(_ k: CodingKeys, _ def: String) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) .flatMap { $0 } ?? def }
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)).flatMap { $0 } ?? d.enabled
        parameter = v(.parameter, d.parameter); parameterOut = v(.parameterOut, d.parameterOut); parameterInOut = v(.parameterInOut, d.parameterInOut)
        local = v(.local, d.local); global = v(.global, d.global); publicGlobal = v(.publicGlobal, d.publicGlobal)
        constant = v(.constant, d.constant); cursor = v(.cursor, d.cursor); type = v(.type, d.type)
    }

    /// Przedrostki pola (po przecinku, bez pustych).
    static func prefixes(_ field: String) -> [String] {
        field.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Tryb parametru ze szczegółów węzła zarysu („IN OUT NOCOPY NUMBER”, „OUT …”, typ bez trybu — IN).
    public enum Mode: Sendable { case `in`, out, inOut }

    public static func mode(_ detail: String) -> Mode {
        let words = detail.uppercased().split(whereSeparator: { $0.isWhitespace })
        guard let first = words.first else { return .in }
        if first == "OUT" { return .out }
        if first == "IN", words.count > 1, words[1] == "OUT" { return .inOut }
        return .in
    }

    /// Przedrostki parametru w trybie (puste OUT / IN OUT — jak IN).
    public func parameterPrefix(_ m: Mode) -> String {
        switch m {
        case .in: parameter
        case .out: parameterOut.trimmingCharacters(in: .whitespaces).isEmpty ? parameter : parameterOut
        case .inOut: parameterInOut.trimmingCharacters(in: .whitespaces).isEmpty ? parameter : parameterInOut
        }
    }
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
        func check(_ n: OutlineNode, field: String, what: String) {
            let list = NamingConventions.prefixes(field)
            guard !list.isEmpty, !list.contains(where: { n.name.lowercased().hasPrefix($0.lowercased()) }) else { return }
            out.append((n.nameOffset, L10n.tr("\(what) „\(n.name)” nie zaczyna się od „\(list.joined(separator: "”, „"))”")))
        }
        /// `scope`: nil — podprogram (lokalne), true — specyfikacja pakietu, false — ciało pakietu.
        func walk(_ nodes: [OutlineNode], spec: Bool?) {
            for n in nodes {
                switch n.kind {
                case .parameter:
                    switch NamingConventions.mode(n.detail) {
                    case .in: check(n, field: c.parameterPrefix(.in), what: L10n.tr("Parametr IN"))
                    case .out: check(n, field: c.parameterPrefix(.out), what: L10n.tr("Parametr OUT"))
                    case .inOut: check(n, field: c.parameterPrefix(.inOut), what: L10n.tr("Parametr IN OUT"))
                    }
                case .variable:
                    switch spec {
                    case nil: check(n, field: c.local, what: L10n.tr("Zmienna lokalna"))
                    case true?: check(n, field: c.publicGlobal.trimmingCharacters(in: .whitespaces).isEmpty ? c.global : c.publicGlobal,
                                      what: L10n.tr("Zmienna pakietu (specyfikacja)"))
                    case false?: check(n, field: c.global, what: L10n.tr("Zmienna pakietu"))
                    }
                case .constant: check(n, field: c.constant, what: L10n.tr("Stała"))
                case .cursor: check(n, field: c.cursor, what: L10n.tr("Kursor"))
                case .typeDeclaration: check(n, field: c.type, what: L10n.tr("Typ"))
                default: break
                }
                // Deklaracje bezpośrednio w pakiecie (specyfikacja i ciało) są zmiennymi pakietu; w podprogramach — lokalne.
                let childScope: Bool? = n.kind == .package ? true : n.kind == .packageBody ? false : (n.kind == .declareSection ? spec : nil)
                walk(n.children, spec: childScope)
            }
        }
        walk(PLSQLOutline.parse(text), spec: nil)
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
