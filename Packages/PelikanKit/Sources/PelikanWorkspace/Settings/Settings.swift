import Foundation
import PelikanSQL
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

/// Wielkość liter słów kluczowych w edytorze.
public enum KeywordCase: String, Sendable, Codable, Hashable, CaseIterable { case unchanged, upper, lower, initCap }

/// Wygląd aplikacji: jak system, jasny albo ciemny.
public enum AppearanceMode: String, Sendable, Codable, Hashable, CaseIterable { case system, light, dark }

/// Preferencje aplikacji (odpowiedniki Preferences wzorca; zestawy preferencji — Etap 8).
public struct Settings: Sendable, Codable, Hashable {
    // Oracle — Connection
    public var sessionMode: SessionMode = .multi
    public var logoffWithOpenTransaction: OpenTransactionAction = .ask
    public var checkConnectionIntervalSeconds: Int = 60
    public var pinWindowConnectionsByDefault = false
    public var allowMultipleConnections = true
    public var instantClientDirectory: String?
    /// Katalog Oracle Net użytkownika (tnsnames.ora, sqlnet.ora) i portfel magazynu haseł (Oracle Wallet) — trafiają
    /// do katalogu Oracle Net zarządzanego przez Pelikana; zmiana działa po ponownym uruchomieniu (D53).
    public var oracleNetDirectory: String?
    public var walletDirectory: String?
    /// Touch ID albo hasło Maca przed użyciem hasła zapisanego w Pęku kluczy (D56).
    public var requireOwnerForSavedPasswords = false
    // Oracle — Options
    public var confirmCommitRollback = false
    /// Potwierdzanie poleceń zmieniających na połączeniach produkcyjnych (PD-CONN-006).
    public var confirmProductionChanges = true
    /// PLSQL_WARNINGS dla kompilacji (UG 23.3); puste — ustawienie serwera.
    public var plsqlWarnings = "ENABLE:ALL"
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
    /// Wielkość liter słów kluczowych przy pisaniu (UG 23.12 Keyword case).
    public var keywordCase: KeywordCase = .unchanged
    public var highlightCurrentLine = true
    /// Analiza kodu w czasie pisania: nieznane nazwy (ze słownika połączenia) i inspekcje (DG-RES-001, DG-INSP-001).
    public var liveCodeAnalysis = true
    public var useTabCharacter = false
    /// Panel Code Contents obok edytora Program Window (UG 25.15).
    public var showCodeContents = true
    /// Code Assistant (UG 23.14): automatyczna aktywacja po kropce i jej opóźnienie w milisekundach.
    public var codeAssistantAutomatic = true
    public var codeAssistantDelay = 400
    /// Reguły formatera PL/SQL (UG 29).
    public var beautifier = BeautifierOptions()
    /// Kompilacja okna programu z informacją debugowania (UG 23.4 „Add debug information when compiling”).
    public var debugInfoOnCompile = false
    /// Debuger: pomijanie inicjalizacji specyfikacji pakietów i obiektów SYS przy krokowaniu (UG 23.4).
    public var debuggerSkipPackageInit = true
    public var debuggerSkipSys = true
    // Klawiatura
    public var shortcutProfile: ShortcutProfile = .plsqlDeveloper
    public var keyOverrides: [String: String] = [:]
    // UI — Appearance (UG 23.16)
    public var appearance: AppearanceMode = .system
    /// Język interfejsu (pl, en, de, es, uk); nil — jak system. Działa od następnego uruchomienia (AppleLanguages).
    public var language: String?
    /// Quick Access Toolbar: komendy w grupie szybkiego dostępu paska okna głównego (PD-UI-006).
    public var quickAccessCommands: [String] = []
    // Pliki
    public var recentFiles: [String] = []
    /// Pytanie o zapis zmian przy zamykaniu okna bez pliku (nowe okno z tekstem).
    public var confirmSaveNewWindows = true
    /// Autozapis bieżącego workseta przy zamykaniu aplikacji i przywrócenie przy starcie (UG 15).
    public var worksetAutosave = true
    /// Autozapis układu okna głównego (UG 23.10 „Autosave desktop/layout”).
    public var autosaveLayout = true
    // Agenci AI (PROMPT §7)
    public var agent = AgentSettings()
    /// Zapytania standardowe tabel i widoków (UG 7.14).
    public var standardQueries = StandardQuery.standard
    /// Zapytania przeglądarki sesji (Define Session Queries).
    public var sessionQueries = SessionQueries.standard
    /// Raporty przebiegów zadań schedulera z regułami kolorów (UG 10.4).
    public var schedulerReports = Scheduler.RunReport.standard
    /// Narzędzia użytkownika (UG 24.15, PD-TOOL-017).
    public var userTools: [UserTool] = []

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
        recentFiles = v(.recentFiles, recentFiles)
        keywordCase = v(.keywordCase, keywordCase)
        highlightCurrentLine = v(.highlightCurrentLine, highlightCurrentLine)
        liveCodeAnalysis = v(.liveCodeAnalysis, liveCodeAnalysis)
        showCodeContents = v(.showCodeContents, showCodeContents)
        codeAssistantAutomatic = v(.codeAssistantAutomatic, codeAssistantAutomatic)
        codeAssistantDelay = v(.codeAssistantDelay, codeAssistantDelay)
        beautifier = v(.beautifier, beautifier)
        debugInfoOnCompile = v(.debugInfoOnCompile, debugInfoOnCompile)
        debuggerSkipPackageInit = v(.debuggerSkipPackageInit, debuggerSkipPackageInit)
        debuggerSkipSys = v(.debuggerSkipSys, debuggerSkipSys)
        confirmProductionChanges = v(.confirmProductionChanges, confirmProductionChanges)
        plsqlWarnings = v(.plsqlWarnings, plsqlWarnings)
        appearance = v(.appearance, appearance)
        confirmSaveNewWindows = v(.confirmSaveNewWindows, confirmSaveNewWindows)
        worksetAutosave = v(.worksetAutosave, worksetAutosave)
        autosaveLayout = v(.autosaveLayout, autosaveLayout)
        logoffWithOpenTransaction = v(.logoffWithOpenTransaction, logoffWithOpenTransaction)
        checkConnectionIntervalSeconds = v(.checkConnectionIntervalSeconds, checkConnectionIntervalSeconds)
        pinWindowConnectionsByDefault = v(.pinWindowConnectionsByDefault, pinWindowConnectionsByDefault)
        allowMultipleConnections = v(.allowMultipleConnections, allowMultipleConnections)
        instantClientDirectory = v(.instantClientDirectory, instantClientDirectory)
        oracleNetDirectory = v(.oracleNetDirectory, oracleNetDirectory)
        walletDirectory = v(.walletDirectory, walletDirectory)
        requireOwnerForSavedPasswords = v(.requireOwnerForSavedPasswords, requireOwnerForSavedPasswords)
        language = v(.language, language)
        quickAccessCommands = v(.quickAccessCommands, quickAccessCommands)
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
        agent = v(.agent, agent)
        standardQueries = v(.standardQueries, standardQueries)
        sessionQueries = v(.sessionQueries, sessionQueries)
        schedulerReports = v(.schedulerReports, schedulerReports)
        userTools = v(.userTools, userTools)
    }
}
