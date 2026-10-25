import Foundation
import PelikanDB

/// Możliwości słownika danych serwera (PD-OB-026): wersja i obecność widoków zależnych od wydania. Foldery
/// Object Browsera i zapytania wybierane są wg tego opisu — na 19c/21c bez widoków 23ai, na 23ai bez asercji
/// (dopiero 23.26), na starszych bazach bez kolumn dodanych w 12c.
public struct DictionaryFeatures: Sendable, Hashable {
    public var major: Int
    public var minor: Int
    /// Widoki słownika (z listy `probedViews`) obecne na serwerze; nil — nie sprawdzono (wnioskowanie z wersji).
    public var views: Set<String>?

    /// Widoki, od których zależą foldery.
    public static let probedViews = ["ALL_MLE_MODULES", "ALL_MLE_ENVS", "ALL_DOMAINS", "ALL_PROPERTY_GRAPHS", "ALL_ANNOTATIONS", "ALL_ASSERTIONS"]

    public init(major: Int, minor: Int = 0, views: Set<String>? = nil) {
        self.major = major; self.minor = minor; self.views = views
    }

    /// Widok wymagany przez folder typu (nil — folder ogólny, ALL_OBJECTS).
    static func requiredView(_ t: DBObjectType) -> String? {
        switch t {
        case .mleModule: "ALL_MLE_MODULES"
        case .mleEnvironment: "ALL_MLE_ENVS"
        case .domain: "ALL_DOMAINS"
        case .property: "ALL_PROPERTY_GRAPHS"
        case .annotation: "ALL_ANNOTATIONS"
        case .assertion: "ALL_ASSERTIONS"
        default: nil
        }
    }

    public func supports(_ t: DBObjectType) -> Bool {
        guard t.minimumServerMajor <= major else { return false }
        guard let view = Self.requiredView(t) else { return true }
        if let views { return views.contains(view) }
        // Bez sprawdzenia widoków: asercje dopiero od 23.26 (Release Update 23.26 = Oracle AI Database 26ai).
        return t == .assertion ? (major > 23 || minor >= 26) : true
    }

    /// Foldery Object Browsera w kolejności wzorca.
    public var availableTypes: [DBObjectType] { DBObjectType.browserOrder.filter(supports) }
}

/// Zapytania słownika z wariantami zapasowymi (PD-OB-026): następny wariant, gdy widok albo kolumna nie istnieje.
public enum DictionaryQuery {
    /// ORA-00942 (brak tabeli/widoku), ORA-00904 (nieprawidłowy identyfikator), ORA-04043 (obiekt nie istnieje).
    public static func isMissingDictionaryObject(_ error: any Error) -> Bool {
        guard let e = error as? OracleError else { return false }
        return [942, 904, 4043].contains(e.code)
    }

    /// Pierwszy wariant zapytania, który się wykona; błąd inny niż brak widoku/kolumny przerywa od razu.
    public static func queryAll(_ alternatives: [String], binds: [BindVariable] = [], limit: Int = 100_000,
                                in s: any DatabaseSession) async throws -> (columns: [ColumnInfo], rows: [[OracleValue]]) {
        var last: (any Error)?
        for sql in alternatives {
            do {
                return try await s.queryAll(sql, binds: binds, limit: limit)
            } catch where isMissingDictionaryObject(error) {
                last = error
            }
        }
        throw last ?? CommandError.notAvailable(L10n.tr("Brak zapytania słownika"))
    }

    /// Opis możliwości słownika z sesji: wersja z `SessionInfo`, widoki z ALL_VIEWS (błąd — wnioskowanie z wersji).
    public static func features(in s: any DatabaseSession) async -> DictionaryFeatures {
        let v = s.info.server
        var f = DictionaryFeatures(major: v.major, minor: v.minor)
        guard v.major >= 23 else { return f }
        let list = DictionaryFeatures.probedViews.map { "'\($0)'" }.joined(separator: ", ")
        if let (_, rows) = try? await s.queryAll("select view_name from all_views where owner = 'SYS' and view_name in (\(list))", limit: 100) {
            f.views = Set(rows.compactMap { $0.first?.displayText })
        }
        return f
    }
}
