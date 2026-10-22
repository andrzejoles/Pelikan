import Foundation
import PelikanDB

/// Tryb sesji (UG 20.3).
public enum SessionMode: String, Sendable, Codable, CaseIterable {
    /// Każde okno SQL/Test/Command ma własną sesję; osobna sesja kompilacji.
    case multi
    /// Okna jednego połączenia dzielą sesję; osobna sesja kompilacji.
    case dual
    /// Wszystko w jednej sesji (debuger wyłączony).
    case single

    public var displayName: String {
        switch self {
        case .multi: L10n.tr("Wiele sesji")
        case .dual: L10n.tr("Dwie sesje")
        case .single: L10n.tr("Jedna sesja")
        }
    }
}

/// Zachowanie przy wylogowaniu z otwartą transakcją (UG 23.1; w Pelikanie domyślnie pytanie — D10).
public enum OpenTransactionAction: String, Sendable, Codable, CaseIterable {
    case ask, commit, rollback
}

/// Liczba wierszy pobieranych na stronę w siatce (UG 23.20).
public enum RecordsPerPage: Sendable, Codable, Hashable {
    case automatic
    case fixed(Int)
    case all
}

/// Preferencje aplikacji (odpowiedniki Preferences wzorca; zestawy preferencji — Etap 8).
public struct Settings: Sendable, Codable, Hashable {
    // Oracle — Connection
    public var sessionMode: SessionMode = .multi
    public var logoffWithOpenTransaction: OpenTransactionAction = .ask
    public var checkConnectionIntervalSeconds: Int = 60
    public var pinWindowConnectionsByDefault = false
    public var allowMultipleConnections = true
    public var instantClientDirectory: String?
    // Oracle — Options
    public var confirmCommitRollback = false
    public var useDBAViews = true
    // Oracle — Output
    public var dbmsOutputEnabled = true
    public var dbmsOutputClearBeforeExecute = true
    /// Rozmiar bufora DBMS_OUTPUT w bajtach; 0 = bez limitu.
    public var dbmsOutputBufferSize = 0
    // Window Types — SQL Window
    public var autoCommitSQL = false
    public var autoCommitPostedRecords = false
    public var autoSelectStatement = true   // D12
    public var recordsPerPage: RecordsPerPage = .automatic
    public var maximumResultSetMegabytes = 512
    public var fetchLOBsOnDemand = true
    // UI — NLS Options
    public var dateFormat = "YYYY-MM-DD HH24:MI:SS"
    public var timestampFormat = "YYYY-MM-DD HH24:MI:SS.FF6"
    // UI — Editor
    public var editorFontName = "SF Mono"
    public var editorFontSize: Double = 13
    public var tabSize = 2
    public var useTabCharacter = false
    // Klawiatura
    public var shortcutProfile: ShortcutProfile = .plsqlDeveloper
    public var keyOverrides: [String: String] = [:]

    public init() {}

    public var valueFormat: ValueFormat {
        ValueFormat(dateFormat: dateFormat, timestampFormat: timestampFormat)
    }

    // Dekodowanie odporne na nowe pola (brakujące klucze = wartości domyślne).
    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ cur: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? cur }
        sessionMode = v(.sessionMode, sessionMode)
        logoffWithOpenTransaction = v(.logoffWithOpenTransaction, logoffWithOpenTransaction)
        checkConnectionIntervalSeconds = v(.checkConnectionIntervalSeconds, checkConnectionIntervalSeconds)
        pinWindowConnectionsByDefault = v(.pinWindowConnectionsByDefault, pinWindowConnectionsByDefault)
        allowMultipleConnections = v(.allowMultipleConnections, allowMultipleConnections)
        instantClientDirectory = v(.instantClientDirectory, instantClientDirectory)
        confirmCommitRollback = v(.confirmCommitRollback, confirmCommitRollback)
        useDBAViews = v(.useDBAViews, useDBAViews)
        dbmsOutputEnabled = v(.dbmsOutputEnabled, dbmsOutputEnabled)
        dbmsOutputClearBeforeExecute = v(.dbmsOutputClearBeforeExecute, dbmsOutputClearBeforeExecute)
        dbmsOutputBufferSize = v(.dbmsOutputBufferSize, dbmsOutputBufferSize)
        autoCommitSQL = v(.autoCommitSQL, autoCommitSQL)
        autoCommitPostedRecords = v(.autoCommitPostedRecords, autoCommitPostedRecords)
        autoSelectStatement = v(.autoSelectStatement, autoSelectStatement)
        recordsPerPage = v(.recordsPerPage, recordsPerPage)
        maximumResultSetMegabytes = v(.maximumResultSetMegabytes, maximumResultSetMegabytes)
        fetchLOBsOnDemand = v(.fetchLOBsOnDemand, fetchLOBsOnDemand)
        dateFormat = v(.dateFormat, dateFormat)
        timestampFormat = v(.timestampFormat, timestampFormat)
        editorFontName = v(.editorFontName, editorFontName)
        editorFontSize = v(.editorFontSize, editorFontSize)
        tabSize = v(.tabSize, tabSize)
        useTabCharacter = v(.useTabCharacter, useTabCharacter)
        shortcutProfile = v(.shortcutProfile, shortcutProfile)
        keyOverrides = v(.keyOverrides, keyOverrides)
    }
}
