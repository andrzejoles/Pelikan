import Foundation

/// Preferencje kompilatora (UG 23.3, PD-PROG-013): parametry sesji kompilacji ustawiane przed kompilacją okna programu.
/// Puste — ustawienie serwera (parametr nie jest zmieniany).
public struct CompilerOptions: Sendable, Codable, Hashable {
    /// PLSQL_OPTIMIZE_LEVEL 0–3 (nil — serwer).
    public var optimizeLevel: Int?
    /// PLSQL_CODE_TYPE: INTERPRETED albo NATIVE (puste — serwer).
    public var codeType = ""
    /// PLSCOPE_SETTINGS, np. `IDENTIFIERS:ALL` albo `IDENTIFIERS:ALL, STATEMENTS:ALL` (puste — serwer).
    public var plscope = ""
    /// PLSQL_CCFLAGS — flagi kompilacji warunkowej, np. `debug:TRUE, poziom:2` (puste — serwer).
    public var ccflags = ""

    public init() {}

    static let codeTypes = ["INTERPRETED", "NATIVE"]
    /// Bezpieczne wartości parametrów (bez apostrofów i średników — idą do literału ALTER SESSION).
    static func isSafe(_ s: String) -> Bool { s.range(of: #"^[A-Za-z0-9_$#:, ()]+$"#, options: .regularExpression) != nil }

    /// Polecenia ALTER SESSION dla sesji kompilacji: ostrzeżenia (preferencja PLSQL_WARNINGS) i parametry kompilatora.
    /// Wartości spoza dozwolonego zestawu znaków są pomijane.
    public func statements(warnings: String) -> [String] {
        var out: [String] = []
        let w = warnings.trimmingCharacters(in: .whitespaces)
        if !w.isEmpty, Self.isSafe(w) { out.append("ALTER SESSION SET PLSQL_WARNINGS = '\(w)'") }
        if let l = optimizeLevel, (0...3).contains(l) { out.append("ALTER SESSION SET PLSQL_OPTIMIZE_LEVEL = \(l)") }
        let ct = codeType.trimmingCharacters(in: .whitespaces).uppercased()
        if Self.codeTypes.contains(ct) { out.append("ALTER SESSION SET PLSQL_CODE_TYPE = \(ct)") }
        let ps = plscope.trimmingCharacters(in: .whitespaces)
        if !ps.isEmpty, Self.isSafe(ps) { out.append("ALTER SESSION SET PLSCOPE_SETTINGS = '\(ps.uppercased())'") }
        let cc = ccflags.trimmingCharacters(in: .whitespaces)
        if !cc.isEmpty, Self.isSafe(cc) { out.append("ALTER SESSION SET PLSQL_CCFLAGS = '\(cc)'") }
        return out
    }
}
