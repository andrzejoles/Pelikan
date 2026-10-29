import Foundation
import PelikanLog
import Observation
import PelikanDB
import PelikanSQL

/// Ponowne wczytanie obu stron porównania (Reload w przeglądarce różnic, PD-DIFF-001).
public typealias DiffReload = @MainActor @Sendable () async throws -> (left: String, right: String)

/// Usługi interfejsu, których potrzebują komendy (implementuje aplikacja; w testach — atrapy).
@MainActor
public protocol UIServices: AnyObject {
    func showError(_ message: String)
    func showCommandPalette()
    /// Pytanie z wyborem (np. zapis zmian przy zamykaniu). Zwraca indeks wybranego przycisku albo nil (anuluj).
    func ask(_ title: String, message: String, buttons: [String]) async -> Int?
    /// Pytanie bez dodatkowego przycisku „Anuluj”: Esc wybiera przycisk `escapeButton` (bezpieczny wybór), Enter —
    /// `defaultButton`; `destructiveButton` oznaczony jako niszczący (D197).
    func ask(_ title: String, message: String, buttons: [String], escapeButton: Int, defaultButton: Int, destructiveButton: Int?) async -> Int?
    /// Okno definicji połączenia (nil = nowe).
    func showConnectionEditor(connectionID: UUID?)
    /// Okno logowania (wybór połączenia).
    func showLogon()
    /// Okno „Zmienne” (UG 7.5, 12.3): wartości dla zmiennych &, : i parametrów Jaspera; nil = anulowano.
    func askVariables(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]?
    /// Schowek: tekst i opcjonalnie HTML (wklejanie do Excela/Numbers z formatowaniem).
    func copyToClipboard(_ text: String, html: String?)
    /// Zakończenie edycji komórki siatki (wpisana, niezatwierdzona Enterem wartość trafia do modelu) — przed
    /// zatwierdzaniem, kopiowaniem SQL i anulowaniem zmian siatki (APP2-04).
    func commitPendingEdits()
    /// Druk dokumentu HTML (raport, PD-REP-001).
    func printHTML(_ html: String, title: String)
    /// Okno zapisu pliku; zwraca false przy anulowaniu.
    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool
    /// Large Data Editor (UG 27) dla komórki siatki.
    func showLargeDataEditor(_ model: LargeDataModel)
    /// Pytanie o tekst (np. numer linii); nil — anulowano.
    func askText(_ title: String, message: String, defaultValue: String) async -> String?
    /// Okno Znajdź i zamień dla aktywnego edytora.
    func showFindReplace()
    /// Okno informacji o obiekcie (Opis, Właściwości): tabela kolumn i wierszy tekstu.
    func showObjectInfo(title: String, columns: [String], rows: [[String]])
    /// Ekran pomocy przy braku Oracle Instant Client (pobranie, wskazanie katalogu, sterownik thin).
    func showClientMissingHelp(_ message: String)
    /// Okno historii poleceń (Recall Statement, UG 25.5).
    func showRecallStatement()
    /// Okno wyboru plików do otwarcia.
    func chooseFilesToOpen() async -> [URL]
    /// Okno wyboru jednego pliku o podanych rozszerzeniach (projekt, zestaw testów, moduł JavaScript); nil — anulowano.
    func chooseFile(_ title: String, extensions: [String]) async -> URL?
    /// Okno wyboru nazwy pliku do zapisu; nil — anulowano.
    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL?
    /// Lista podpowiedzi Code Assistant w edytorze dokumentu (UG 25.4).
    func showCompletion(_ result: CompletionResult, for document: Document)
    /// Okno Find Database Objects (UG 24.2) z kryteriami początkowymi.
    func showFindObjects(_ criteria: DatabaseSearchCriteria)
    /// Okno Compile Invalid Objects (UG 24.3).
    func showCompileInvalid()
    /// Przeglądarka różnic (UG 26): lewy i prawy tekst z tytułami.
    func showDiff(left: String, right: String, leftTitle: String, rightTitle: String)
    /// Przeglądarka różnic z ponownym wczytaniem obu stron (Reload, PD-DIFF-001).
    func showDiff(left: String, right: String, leftTitle: String, rightTitle: String, reload: DiffReload?)
    /// Template Window jako osobne, pływające okno (PD-TPL-001).
    func showTemplateWindow()
    /// Edytor definicji tabeli (UG 9.1): `original` nil — nowa tabela.
    func showTableEditor(_ definition: TableDefinition, original: TableDefinition?, connectionID: UUID)
    /// Prosty edytor obiektu (sekwencja, synonim, indeks, użytkownik, rola — UG 9.2–9.11).
    func showObjectEditor(_ editor: SimpleObjectEditor, connectionID: UUID)
    /// Eksplorator testów utPLSQL (UT-EXP-001).
    func showTestExplorer()
    /// Test Manager (PD-TOOL-018).
    func showTestManager()
    /// Otwarcie adresu (przeglądarka, dokumenty — PD-EDIT-027, PD-DOC-002) i pliku w aplikacji (nil — skojarzonej; PD-EDIT-028).
    func openURL(_ url: URL)
    func openInApplication(_ file: URL, application: String?)
    /// Pytanie z polem „Nie pytaj więcej” (PD-PREF-008): odpowiedź (nil — anulowano) i stan pola.
    func askWithSuppression(_ title: String, message: String, buttons: [String]) async -> (Int?, Bool)
    /// Dostosowanie paska narzędzi okna głównego (PD-UI-006) i karta zestawów preferencji (PD-PREF-002).
    func customizeToolbar()
    /// Okno zgłoszenia problemu (PL-INFRA-013).
    func showProblemReport(_ report: ProblemReport)
    /// Pole „Szukaj czynności” na wstążce (PD-UI-012).
    func focusRibbonSearch()
    /// Tekst tajny (fraza szyfrująca eksportu połączeń, D186) w polu bez podglądu; `confirm` — drugie pole do powtórzenia.
    /// nil — anulowano. Nigdy nie trafia do dziennika ani historii.
    func askSecret(_ title: String, message: String, confirm: Bool) async -> String?
    /// Panele narzędzi okna głównego (PD-UI-003): pokazanie albo ukrycie panelu.
    func toggleToolDock(_ placement: ToolPlacement)
    /// Przeniesienie narzędzia (nil — bieżącego) do panelu albo osobnego okna; zwraca klucz narzędzia (nil — brak narzędzia).
    func placeTool(_ key: String?, at placement: ToolPlacement) -> String?
    /// Zamknięcie narzędzia (nil — bieżącego); zwraca klucz zamkniętego narzędzia.
    func closeTool(_ key: String?) -> String?
    func showPreferenceSets()
    /// Raport HTML (AWR, ASH, ADDM, SQL Monitor, Tuning Advisor) i lista SQL Monitor.
    func showHTMLReport(title: String, html: String)
    func showSQLMonitor(connection: UUID)
    /// Koniec długiego wykonania (dźwięk, uwaga aplikacji — PD-SQLW-015).
    func notifyExecutionFinished(title: String, elapsed: String, success: Bool)
    /// Okno Query By Example (PD-SQLW-022) i filtr kolumn (PD-GRID-011) dla karty wyniku.
    func showQueryByExample(_ tab: ResultTab)
    func showColumnFilter(_ tab: ResultTab)
    /// Wybór wartości z listy (lista wartości kolumny ze słownika — PD-GRID-022); nil — anulowano.
    func chooseValue(_ title: String, values: [String]) async -> String?
    /// Kalendarz przy edycji daty (PD-GRID-005): wybrana data (z czasem, gdy `withTime`); nil — anulowano.
    func chooseDate(_ title: String, initial: OracleTimestamp?, withTime: Bool) async -> OracleTimestamp?
    /// Edytor szablonu (PD-TPL-003): folder, nazwa i tekst; nil — anulowano.
    func editTemplate(_ template: CodeTemplate, folders: [String]) async -> CodeTemplate?
    /// Instrukcja użytkownika (PL-INFRA-010).
    func showUserManual()
    /// Okno druku dla dokumentu HTML (PD-SQLW-016).
    func printHTML(title: String, html: String)
    /// Widoki dualności (SD-DV-001), moduły MLE (SD-MLE-001), podgląd przestrzenny (SD-DATA-001).
    func showDualityViews()
    func showMLEModules()
    func showSpatialPreview(title: String, wkt: [String])
    /// Etap 7: Autotrace, porównanie planów, panel DBA, Instance Viewer, Task Monitor, dokumentacja schematu.
    func showAutotrace(_ result: AutotraceResult, sql: String)
    func showPlanComparison(_ comparison: PlanComparison, leftTitle: String, rightTitle: String)
    func showDBAPanel()
    func showInstanceViewer()
    func showTaskMonitor()
    func showSchemaDoc()
    /// Okno projektu (PD-PROJ-001).
    func showProject()
    /// Monitor zdarzeń i test obciążenia (PD-TOOL-014, PD-TOOL-019).
    func showEventMonitor()
    func showLoadTester()
    /// Okna narzędzi siatki (zapytania powiązane, porównania, kolumna do plików).
    func showGridTool(_ request: GridToolRequest)
    /// Biblioteka snippetów (SC-SNIP-001).
    func showSnippets()
    /// Diagram: eksport obrazu (png/pdf), kopia do schowka, druk (PD-DIAG-003); Query Builder (PD-QB-001).
    func exportDiagram(_ doc: Document, format: String)
    func copyDiagramImage(_ doc: Document)
    func printDiagram(_ doc: Document)
    func showQueryBuilder(sql: String?, connectionID: UUID?)
    /// Okna eksportu/importu tabel, importu tekstu i Excela, generatora danych, porównania danych (PD-TOOL-003…013).
    func showDataTransfer(_ tool: DataTransferTool)
    /// Przeglądarka sesji (PD-TOOL-015).
    func showSessionBrowser()
    /// Eksport i porównanie obiektów użytkownika (PD-TOOL-007, PD-TOOL-012).
    func showExportObjects()
    func showCompareObjects()
    /// DBMS Scheduler (PD-SCHED-001).
    func showScheduler()
    /// Okno wykresu z karty wyników okna SQL (PD-GRAPH-001).
    func showGraph(document: Document, tab: ResultTab)
    /// Wyjście narzędzia użytkownika i edycja listy narzędzi (PD-TOOL-017).
    func showToolOutput(title: String, text: String, status: Int32)
    func showUserToolsSettings()
    /// Okno wyników utPLSQL dla przebiegu (PROMPT §6).
    func showUtplsqlResults(_ run: UtplsqlRun)
    /// Okno punktów przerwania (UG 5.10).
    func showBreakpoints()
    /// Okno debugera (stos, zmienne, przyciski kroków) dla okna testu.
    func showDebugger(_ debugger: DebuggerEngine, document: Document)
    /// Formularz zmiennych szablonu (UG 31.2); nil = anulowano.
    func askTemplateValues(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]?
    /// Biblioteka makr, historia schowka, lista zadań To-Do (PD-EDIT-015, PD-EDIT-024, PD-TODO-001).
    func showMacroLibrary()
    func showClipboardHistory()
    func showTodoItems()
    /// Tekst w schowku systemowym (Paste from host language).
    func clipboardText() -> String?
    /// Pokazuje File Browser w lewej kolumnie (UG 22).
    func showFileBrowser()
    /// Karta Obiekty lewej kolumny (Przeglądarka obiektów, PD-OB-001).
    func showObjectBrowser()
    /// Karta Okna lewej kolumny (Lista okien z grupami kart, PD-UI-002, D200).
    func showWindowList()
    /// Wybór katalogu (lokalizacja File Browsera); nil — anulowano.
    func chooseDirectory() async -> URL?
    /// Bieżący układ okna głównego (nil — brak okna).
    func currentLayout() -> WindowLayout?
    /// Przywraca układ okna głównego.
    func applyLayout(_ layout: WindowLayout)
    /// Historia Git (lista zatwierdzeń) w oknie informacji.
    func showGitLog(_ commits: [GitCommit], title: String)
    /// Wyniki Find Usages (DG-USE-001), podgląd refaktoryzacji z różnicami — true: zastosuj (DG-REF-001),
    /// historia lokalna okna (DG-HIST-001), lista problemów analizy kodu (DG-RES-001, DG-INSP-001).
    func showUsages(title: String, hits: [UsageHit])
    /// Wyniki paska wyszukiwania (PD-CA-015) — okno trafień z własnym tytułem.
    func showSearchResults(query: String, hits: [UsageHit])
    /// Search Bar — wyszukiwanie w edytorach i plikach (PD-CA-015).
    func showSearchBar()
    func confirmRefactoring(_ plan: RefactoringPlan) async -> Bool
    func showLocalHistory(document: Document)
    func showProblems(document: Document)
    /// Okna narzędzi etapu 7: raporty predefiniowane, Database Diff, koszyk, kopiowanie schematu, kreator importu,
    /// przenoszenie danych z mapowaniem, zadania lokalne.
    func showStage7Tool(_ tool: Stage7Tool)
    /// Cele SSH zdalnego builda Pro*C: menedżer, Testuj, eksport/import (Etap P).
    func showSSHTargets(_ action: SSHTargetAction)
    /// Wdrożenie Pro*C: pipeline, konsola, historia, blokada, stan git (Etap P).
    func showProCDeploy(_ action: ProCDeployAction)

}

extension UIServices {
    public func ask(_ title: String, message: String, buttons: [String], escapeButton: Int, defaultButton: Int, destructiveButton: Int?) async -> Int? {
        await ask(title, message: message, buttons: buttons) ?? escapeButton
    }
    public func ask(_ title: String, message: String, buttons: [String], escapeButton: Int, defaultButton: Int = 0) async -> Int? {
        await ask(title, message: message, buttons: buttons, escapeButton: escapeButton, defaultButton: defaultButton, destructiveButton: nil)
    }
    public func showStage7Tool(_ tool: Stage7Tool) {}
    public func showCompletion(_ result: CompletionResult, for document: Document) {}
    public func showUsages(title: String, hits: [UsageHit]) {}
    public func showSearchResults(query: String, hits: [UsageHit]) { showUsages(title: query, hits: hits) }
    public func showSearchBar() {}
    public func confirmRefactoring(_ plan: RefactoringPlan) async -> Bool { false }
    public func showLocalHistory(document: Document) {}
    public func showProblems(document: Document) {}
    public func showMacroLibrary() {}
    public func showClipboardHistory() {}
    public func showTodoItems() {}
    public func clipboardText() -> String? { nil }
    public func commitPendingEdits() {}
    public func showFindObjects(_ criteria: DatabaseSearchCriteria) {}
    public func showCompileInvalid() {}
    public func showDebugger(_ debugger: DebuggerEngine, document: Document) {}
    public func showBreakpoints() {}
    public func showUtplsqlResults(_ run: UtplsqlRun) {}
    public func showTestExplorer() {}
    public func showTestManager() {}
    public func customizeToolbar() {}
    public func showProblemReport(_ report: ProblemReport) {}
    public func focusRibbonSearch() {}
    public func askSecret(_ title: String, message: String, confirm: Bool) async -> String? { nil }
    public func toggleToolDock(_ placement: ToolPlacement) {}
    public func placeTool(_ key: String?, at placement: ToolPlacement) -> String? { nil }
    public func closeTool(_ key: String?) -> String? { nil }
    public func showPreferenceSets() {}
    public func showHTMLReport(title: String, html: String) {}
    public func openURL(_ url: URL) {}
    public func openInApplication(_ file: URL, application: String?) {}
    public func askWithSuppression(_ title: String, message: String, buttons: [String]) async -> (Int?, Bool) {
        (await ask(title, message: message, buttons: buttons), false)
    }
    public func showSQLMonitor(connection: UUID) {}
    public func notifyExecutionFinished(title: String, elapsed: String, success: Bool) {}
    public func showQueryByExample(_ tab: ResultTab) {}
    public func showColumnFilter(_ tab: ResultTab) {}
    public func chooseValue(_ title: String, values: [String]) async -> String? { nil }
    public func chooseDate(_ title: String, initial: OracleTimestamp?, withTime: Bool) async -> OracleTimestamp? { nil }
    public func editTemplate(_ template: CodeTemplate, folders: [String]) async -> CodeTemplate? { nil }
    public func showUserManual() {}
    public func printHTML(title: String, html: String) {}
    public func showDualityViews() {}
    public func showMLEModules() {}
    public func showSpatialPreview(title: String, wkt: [String]) {}
    public func showAutotrace(_ result: AutotraceResult, sql: String) {}
    public func showPlanComparison(_ comparison: PlanComparison, leftTitle: String, rightTitle: String) {}
    public func showDBAPanel() {}
    public func showInstanceViewer() {}
    public func showTaskMonitor() {}
    public func showSchemaDoc() {}
    public func showProject() {}
    public func showEventMonitor() {}
    public func showLoadTester() {}
    public func showGridTool(_ request: GridToolRequest) {}
    public func showSnippets() {}
    public func printHTML(_ html: String, title: String) {}
    public func exportDiagram(_ doc: Document, format: String) {}
    public func copyDiagramImage(_ doc: Document) {}
    public func printDiagram(_ doc: Document) {}
    public func showQueryBuilder(sql: String?, connectionID: UUID?) {}
    public func showDataTransfer(_ tool: DataTransferTool) {}
    public func showSessionBrowser() {}
    public func showExportObjects() {}
    public func showCompareObjects() {}
    public func showScheduler() {}
    public func showGraph(document: Document, tab: ResultTab) {}
    public func showToolOutput(title: String, text: String, status: Int32) {}
    public func showUserToolsSettings() {}
    public func showObjectEditor(_ editor: SimpleObjectEditor, connectionID: UUID) {}
    public func showTableEditor(_ definition: TableDefinition, original: TableDefinition?, connectionID: UUID) {}
    public func showDiff(left: String, right: String, leftTitle: String, rightTitle: String) {}
    public func showDiff(left: String, right: String, leftTitle: String, rightTitle: String, reload: DiffReload?) {
        showDiff(left: left, right: right, leftTitle: leftTitle, rightTitle: rightTitle)
    }
    public func showTemplateWindow() {}
    public func showFileBrowser() {}
    public func showObjectBrowser() {}
    public func showWindowList() {}
    public func chooseDirectory() async -> URL? { nil }
    public func chooseFile(_ title: String, extensions: [String]) async -> URL? { await chooseFilesToOpen().first }
    public func currentLayout() -> WindowLayout? { nil }
    public func applyLayout(_ layout: WindowLayout) {}
    public func showSSHTargets(_ action: SSHTargetAction) {}
    public func showProCDeploy(_ action: ProCDeployAction) {}
    public func showGitLog(_ commits: [GitCommit], title: String) {
        showObjectInfo(title: title, columns: [L10n.tr("Zatwierdzenie"), L10n.tr("Autor"), L10n.tr("Data"), L10n.tr("Opis")],
                       rows: commits.map { [String($0.hash.prefix(10)), $0.author, $0.date.map { ISO8601DateFormatter().string(from: $0) } ?? "", $0.subject] })
    }
    public func askTemplateValues(_ requests: [VariableRequest], document: Document) async -> [String: VariableValue]? {
        await askVariables(requests, document: document)
    }
}

/// Rejestr wszystkich komend (kolejność = kolejność w menu i palecie).
public struct CommandRegistry: Sendable {
    public private(set) var commands: [Command] = []
    private var index: [CommandID: Int] = [:]

    public init(_ commands: [Command] = []) {
        for c in commands { register(c) }
    }

    public mutating func register(_ command: Command) {
        if let i = index[command.id] {
            commands[i] = command
        } else {
            index[command.id] = commands.count
            commands.append(command)
        }
    }

    public func command(_ id: CommandID) -> Command? { index[id].map { commands[$0] } }

    public mutating func remove(_ ids: [CommandID]) {
        let drop = Set(ids)
        commands.removeAll { drop.contains($0.id) }
        index = Dictionary(uniqueKeysWithValues: commands.enumerated().map { ($0.element.id, $0.offset) })
    }
    public var descriptors: [CommandDescriptor] { commands.map(\.descriptor) }
}

/// Wpis o wywołaniu komendy (dziennik, panel aktywności agenta, raport testów).
public struct CommandInvocationRecord: Sendable {
    public enum Outcome: Sendable { case success(String?), failure(String) }
    public var command: CommandID
    public var arguments: CommandArguments
    public var invoker: Invoker
    public var started: Date
    public var outcome: Outcome
}

/// Model stanu aplikacji — jedno źródło prawdy dla interfejsu i API agenta (docs/ARCHITECTURE.md §3).
@MainActor
@Observable
public final class Workspace {
    public private(set) var documents: [Document] = []
    public var activeDocumentID: DocumentID? {
        didSet {
            // Kolejność użycia okien — kapsułka grupy aktywuje ostatnio używane okno grupy (D200).
            guard let id = activeDocumentID, id != oldValue else { return }
            activationCounter += 1
            activationTicks[id] = activationCounter
            scheduleTabRepositoryRefresh(full: false)
        }
    }
    /// Grupy kart (D200): grupy ręczne, przydziały okien, tryb „wszystkie karty”.
    public var tabGroupState = TabGroupState()
    /// Repozytoria plików okien (grupy „repozytorium · gałąź”) — wyliczane w tle, z pamięcią per katalog.
    public internal(set) var tabRepositories: [String: RepositoryGroupInfo] = [:]
    @ObservationIgnored var tabRepositoryDirectories: Set<String> = []
    @ObservationIgnored var tabRepositoryRefresh: Task<Void, Never>?
    @ObservationIgnored var tabRepositoryRefreshFull = false
    @ObservationIgnored var lastFullRepositoryCheck: Date?
    /// Sprawdzanie repozytoriów (testy: zaślepka albo nil — bez procesów gita, wyniki deterministyczne).
    @ObservationIgnored public var tabRepositoryProbe: TabRepositoryProbe? = .git
    @ObservationIgnored var tabGroupingMode: TabGroupingMode = .byKind
    @ObservationIgnored public internal(set) var tabPalette = TabColorPalette()
    @ObservationIgnored var activationTicks: [DocumentID: Int] = [:]
    @ObservationIgnored var activationCounter = 0
    public private(set) var registry: CommandRegistry
    public private(set) var keymap: Keymap
    public var shortcutProfile: ShortcutProfile {
        didSet { rebuildKeymap() }
    }
    public var keyOverrides: [String: String] = [:] {
        didSet { rebuildKeymap() }
    }
    public var statusMessage: String?
    /// Obiekt zaznaczony w Object Browserze (cel komend `ob.*`).
    public var selectedObject: DBObject?
    /// Wszystkie obiekty zaznaczone w Object Browserze (PD-OB-011); `selectedObject` — ostatnio kliknięty.
    public var selectedObjects: [DBObject] = []
    /// Połączenie zaznaczonych obiektów (gałąź drzewa Object Browsera z wieloma połączeniami, PD-OB-001; nil — główne).
    public var selectedObjectConnection: UUID?
    /// Filtry nazwane i foldery użytkownika Object Browsera (`browser.json`, PD-OB-007/008) i filtr bieżący.
    public private(set) var browserCustomization = BrowserCustomization()
    public var browserFilter: BrowserFilter?

    public func saveBrowserCustomization(_ c: BrowserCustomization) throws {
        try c.save(to: dataDirectory)
        browserCustomization = c
        if let f = browserFilter, !c.filters.contains(where: { $0.id == f.id }) { browserFilter = nil }
        refreshOpenMetadata()
    }
    /// Ostatnie wyszukiwanie (Znajdź następne — F3).
    public var lastSearch: TextSearch?
    /// Globalna historia wykonanych poleceń (Recall Statement, UG 25.5).
    public private(set) var history: [HistoryEntry] = []
    /// Preferencje obowiązujące: wartości wbudowane z nałożonymi zestawami (PD-PREF-002). Zmiana trafia do zestawu
    /// edytowanego (`preferenceEditTarget`; domyślnie osobisty użytkownika) i jest zapisywana.
    public var settings: Settings {
        didSet {
            if settings.shortcutProfile != oldValue.shortcutProfile { shortcutProfile = settings.shortcutProfile }
            if settings.keyOverrides != oldValue.keyOverrides { keyOverrides = settings.keyOverrides }
            if settings.userTools != oldValue.userTools { refreshUserToolCommands(previous: oldValue.userTools) }
            guard !applyingPreferenceSets else { settingsBox.value = settings; return }
            recordPreferenceChange(from: oldValue, to: settings)
        }
    }
    /// Zestawy preferencji domyślne i połączeniowe (`Preferences/sets.json`).
    public private(set) var preferenceSets: [PreferenceSet] = []
    /// Zestaw osobisty użytkownika (`settings.json`, tylko wartości ustawione przez użytkownika).
    public private(set) var personalPreferences: [String: JSONValue] = [:]
    /// Zestaw, do którego trafiają zmiany z Preferencji (nil — osobisty użytkownika).
    public var preferenceEditTarget: UUID?
    /// Połączenia tylko do odczytu w tym uruchomieniu (parametr startowy `readonly=`, PD-CLI-001).
    public var startupReadOnlyPatterns: [String] = []
    @ObservationIgnored private var applyingPreferenceSets = false
    @ObservationIgnored private var preferenceStore: PreferenceSetStore
    /// Nieczytelne pliki danych przy starcie (settings.json, history.json, zestawy preferencji) zachowane jako `.bad-…`
    /// — komunikaty dla użytkownika (D182).
    @ObservationIgnored public private(set) var loadProblems: [String] = []
    /// Kopia nieczytelnego settings.json / history.json się nie udała — zapis zablokowany, żeby nie nadpisać oryginału.
    @ObservationIgnored private var settingsSaveBlocked = false
    @ObservationIgnored private var historySaveBlocked = false
    public let connections: ConnectionStore
    public let sessions: SessionManager
    /// Katalog danych aplikacji (nil = bez zapisu: testy, `persists: false`).
    public let dataDirectory: URL?
    /// Szablony kodu (UG 31): wbudowane i użytkownika z katalogu danych.
    @ObservationIgnored public private(set) lazy var templates = TemplateLibrary(directory: dataDirectory?.appendingPathComponent("Templates", isDirectory: true))
    /// Snippety (SC-SNIP-001): wbudowane i własne w `Snippets/snippets.json`.
    @ObservationIgnored public private(set) lazy var snippets = SnippetLibrary(directory: dataDirectory?.appendingPathComponent("Snippets", isDirectory: true))
    /// Lokalna historia plików i obiektów (DG-HIST-001) i konsole zapytań połączeń (DG-CONS-001).
    @ObservationIgnored public private(set) lazy var localHistory = LocalHistory(directory: dataDirectory?.appendingPathComponent("LocalHistory", isDirectory: true))
    @ObservationIgnored var nameSources: [NameSourceKey: CachedNameSource] = [:]
    /// Stany okien plików (PD-EDIT-029).
    @ObservationIgnored public private(set) lazy var fileStates = FileStateStore(directory: dataDirectory?.appendingPathComponent("WindowState", isDirectory: true))
    @ObservationIgnored public private(set) lazy var consoles = QueryConsoles(directory: dataDirectory?.appendingPathComponent("Consoles", isDirectory: true))
    /// Pytania o pliki zmienione przez inny program (D197): wyłączone w trybie skryptu (bez okien dialogowych), jedno
    /// sprawdzenie naraz, żadne w trakcie zapisu okna.
    @ObservationIgnored public var externalChangePromptsEnabled = true
    @ObservationIgnored public internal(set) var savingDocuments = 0
    @ObservationIgnored var checkingExternalChanges = false
    /// Punkt zaczepienia testów: wywoływany po odczycie plików przy wykrywaniu zmian (zapis w trakcie odczytu).
    @ObservationIgnored var afterExternalRead: (() -> Void)?
    /// Okna edytowane programem zewnętrznym (PD-EDIT-028) i odzyskiwanie po awarii (PD-FILE-001).
    @ObservationIgnored public var externalEdits: [DocumentID: ExternalDocumentEdit] = [:]
    @ObservationIgnored public private(set) lazy var recovery = RecoveryStore(directory: dataDirectory?.appendingPathComponent("Recovery", isDirectory: true))
    /// Czas ostatniej migawki odzyskiwania przed wykonaniem (PD-FILE-001) — co najwyżej jedna na kilka sekund.
    @ObservationIgnored var lastExecuteSnapshot: Date?
    /// Okna z poprzedniego, nieczysto zakończonego uruchomienia — do przywrócenia (Plik › Odzyskaj okna).
    public var pendingRecovery: Workset?
    /// Uruchomienie programu zewnętrznego bez powłoki (argumenty jako tablica); w testach podmieniane.
    @ObservationIgnored public var launchProgram: @Sendable (URL, [String]) throws -> Void = { exe, args in
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PELIKAN_") }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }
    /// Problemy edytora z rozwiązywania nazw i inspekcji (DG-RES-001, DG-INSP-001) według okna.
    public var diagnostics: [DocumentID: [EditorDiagnostic]] = [:]
    /// Panel wartości obok siatki wyników (DB-PANEL-001).
    public var valuePanelVisible = false
    /// File Browser (UG 22): lokalizacje i historia filtrów z katalogu danych.
    @ObservationIgnored public private(set) lazy var fileBrowser = FileBrowser(fileURL: dataDirectory?.appendingPathComponent("file-browser.json"))
    /// Worksety (UG 15) i zapisany układ okna (UG 23.10).
    @ObservationIgnored public private(set) lazy var worksets = WorksetStore(directory: dataDirectory?.appendingPathComponent("Worksets", isDirectory: true),
                                                                             layoutURL: dataDirectory?.appendingPathComponent("layout.json"))
    /// Zmienia się po zapisie lub usunięciu szablonu (Template Window przeładowuje listę).
    public var templatesGeneration = 0
    /// Punkty przerwania (UG 5.10) i debugery okien testu.
    public var breakpoints: [Breakpoint] = []
    /// Punkty, których DBMS_DEBUG nie przyjął w ostatniej sesji (pusty znacznik na marginesie, PD-DBG-007).
    public var unappliedBreakpoints: Set<UUID> = []
    /// Punkty przerwania na kodach błędów Oracle (bez „ORA-”, np. 1403).
    public var errorBreakpoints: [Int] = []
    /// Ostatni przebieg testów utPLSQL (okno wyników, pokrycie na marginesie).
    public var lastUtplsqlRun: UtplsqlRun? {
        didSet {
            // Historia przebiegów (UT-RES-003), najnowszy pierwszy, do 20.
            if let r = lastUtplsqlRun, utplsqlHistory.first?.id != r.id {
                utplsqlHistory.insert(r, at: 0)
                if utplsqlHistory.count > 20 { utplsqlHistory.removeLast() }
            }
        }
    }
    public private(set) var utplsqlHistory: [UtplsqlRun] = []
    /// Bramka uprawnień agentów (PelikanAgent); nil — wywołania agentów są odrzucane.
    @ObservationIgnored public weak var agentGate: (any AgentInvocationGate)?
    /// Zmiany edytorów wykonane przez agentów (cofanie sesji agenta).
    public internal(set) var agentEdits: [AgentEdit] = []
    /// Otwarty projekt (UG 14), jego plik i wynik ostatniego budowania.
    public var project: Project?
    public var projectURL: URL?
    public var projectBuildResults: [ProjectBuildResult] = []
    /// Zadania w tle (Task Monitor, SD-MON-002).
    public let tasks = WorkspaceTaskCenter()
    /// Zadania lokalne według harmonogramu (DB-TASK-001); definicje w katalogu danych `Tasks/`.
    @ObservationIgnored public private(set) lazy var localTasks = LocalTaskScheduler(directory: dataDirectory?.appendingPathComponent("Tasks", isDirectory: true))
    /// Kod obiektów przed i po zmianach agentów (cofanie sesji agenta).
    public internal(set) var agentCodeChanges: [AgentCodeChange] = []
    /// Liczba wierszy zmienionych przez niezatwierdzone DML agenta (sesja|połączenie) — podgląd zgody na COMMIT.
    public internal(set) var agentPendingRows: [String: UInt64] = [:]
    /// Ostatnie wywołanie w kolejce sesji bazy agenta (`agentSerialized`).
    @ObservationIgnored var agentQueue: [String: Task<Void, Never>] = [:]
    /// Ostrzeżenie o pokryciu kodu pokazane w tej sesji aplikacji.
    public var coverageWarningShown = false
    /// Zmienia się po kompilacji jednostek (eksplorator testów przeładowuje drzewo).
    public var compileGeneration = 0
    @ObservationIgnored var debuggers: [DocumentID: DebuggerEngine] = [:]
    /// Historia skoków (UG 25.20) — Wstecz / Naprzód.
    public internal(set) var navigationBack: [NavigationPoint] = []
    public internal(set) var navigationForward: [NavigationPoint] = []

    @ObservationIgnored public weak var ui: (any UIServices)?
    @ObservationIgnored private var invocationObservers: [@MainActor (CommandInvocationRecord) -> Void] = []
    /// Nagrywane makro (nil — nie trwa nagrywanie) i bieżące makro F12 (PD-EDIT-015).
    public internal(set) var macroRecorder: MacroRecorder?
    public internal(set) var currentMacro: Macro?
    @ObservationIgnored var isPlayingMacro = false
    /// Biblioteka makr z katalogu danych.
    public internal(set) var macroLibrary = MacroLibrary()
    /// Historia schowka (PD-EDIT-024).
    public internal(set) var clipboardHistory = ClipboardHistory()
    @ObservationIgnored private var ordinals: [DocumentKind: Int] = [:]
    /// Silniki SQL*Plus okien Command Window (stan SET/DEFINE/VARIABLE trwa przez życie okna).
    @ObservationIgnored private var sqlplusEngines: [DocumentID: SQLPlusEngine] = [:]
    /// Metadane słownika per połączenie (Object Browser, Code Assistant).
    @ObservationIgnored var metadataProviders: [UUID: MetadataProvider] = [:]

    public func sqlplusEngine(for doc: Document) -> SQLPlusEngine {
        if let e = sqlplusEngines[doc.id] { return e }
        let e = SQLPlusEngine(workspace: self, document: doc)
        sqlplusEngines[doc.id] = e
        return e
    }


    /// - Parameters:
    ///   - dataDirectory: katalog danych (`~/Library/Application Support/Pelikan`); nil = nic nie jest zapisywane.
    ///   - secrets: przechowywanie haseł (aplikacja: Pęk kluczy; testy: pamięć).
    ///   - drivers: sterowniki bazy wstrzykiwane przez aplikację.
    public init(profile: ShortcutProfile? = nil, commands: [Command]? = nil, dataDirectory: URL? = nil,
                secrets: any SecretStore = MemorySecretStore(), drivers: [DriverKind: any DatabaseDriver] = [:]) {
        self.dataDirectory = dataDirectory
        var setStore = PreferenceSetStore(directory: dataDirectory)
        let sets = setStore.load()
        preferenceStore = setStore
        var problems = [setStore.loadProblem].compactMap(\.self)
        var personal: [String: JSONValue] = [:]
        // Nieczytelny plik (uszkodzony, poprawiony ręcznie, z nowszej wersji) — zachowany obok, zanim pierwsza zmiana
        // preferencji albo wykonane polecenie nadpisze go pustą zawartością.
        var blocked: (settings: Bool, history: Bool) = (false, false)
        if let dir = dataDirectory, let data = try? Data(contentsOf: dir.appendingPathComponent("settings.json")) {
            if case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data) {
                personal = o
            } else {
                let (message, preserved) = DamagedFile.preserve(dir.appendingPathComponent("settings.json"))
                problems.append(message)
                blocked.settings = !preserved
            }
        }
        if let profile { personal["shortcutProfile"] = .string(profile.rawValue) }
        // Przy starcie bez połączenia: zestawy globalne i osobisty użytkownika.
        let loaded = PreferenceSets.merge(sets.filter { !$0.kind.isConnection }
                                          + [PreferenceSet(name: "", kind: .personalUser, values: personal)])
        preferenceSets = sets
        personalPreferences = personal
        settings = loaded
        shortcutProfile = loaded.shortcutProfile
        keyOverrides = loaded.keyOverrides
        let all = commands ?? BuiltinCommands.all
        registry = CommandRegistry(all)
        keymap = Keymap(commands: all.map(\.descriptor), profile: loaded.shortcutProfile, overrides: loaded.keyOverrides)
        let store = ConnectionStore(fileURL: dataDirectory?.appendingPathComponent("connections.json"), secrets: secrets)
        connections = store
        browserCustomization = BrowserCustomization.load(from: dataDirectory)
        let box = SettingsBox()
        sessions = SessionManager(store: store, drivers: drivers, settings: { box.value })
        box.value = loaded
        settingsBox = box
        if let dir = dataDirectory, let data = try? Data(contentsOf: dir.appendingPathComponent("history.json")) {
            if let h = try? JSONDecoder.pelikan.decode([HistoryEntry].self, from: data) {
                history = h
            } else {
                let (message, preserved) = DamagedFile.preserve(dir.appendingPathComponent("history.json"))
                problems.append(message)
                blocked.history = !preserved
            }
        }
        loadProblems = problems
        settingsSaveBlocked = blocked.settings
        historySaveBlocked = blocked.history
        // Komendy z plików użytkownika: makra z biblioteki i własne formaty Special Copy.
        macroLibrary = MacroLibrary.load(from: dataDirectory)
        if commands == nil {
            registerMacroCommands()
            registerCopyFormatCommands()
            registerUserToolCommands()
            registerUserReports()
        }
        sessions.onMainConnectionChange = { [weak self] in self?.applyPreferenceSets() }
    }

    /// Dopisuje polecenie do historii (bez poleceń z hasłami, bez duplikatu ostatniego), limit 200 (UG 23.26).
    public func recordHistory(_ sql: String, limit: Int = 200) {
        let text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !SQLExecutor.containsPassword(text) else { return }
        if history.first?.text == text { history.removeFirst() }
        let user = sessions.mainConnectionID.flatMap { connections.connection($0)?.target.driverUserName } ?? ""
        history.insert(HistoryEntry(date: Date(), user: user, text: text), at: 0)
        if history.count > limit { history.removeLast(history.count - limit) }
        guard let dir = dataDirectory, !historySaveBlocked else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pelikan.encode(history) {
            // Tekst wykonanych poleceń może zawierać cokolwiek — tylko dla właściciela (jak worksety), od chwili utworzenia pliku.
            _ = try? PrivateFile.write(data, to: dir.appendingPathComponent("history.json"))
        }
    }

    @ObservationIgnored private var settingsBox: SettingsBox

    private func saveSettings() {
        settingsBox.value = settings
        guard let dir = dataDirectory, !settingsSaveBlocked else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pelikan.encode(JSONValue.object(personalPreferences)) {
            try? data.write(to: dir.appendingPathComponent("settings.json"), options: [.atomic])
        }
    }

    // MARK: Zestawy preferencji (PD-PREF-002)

    /// Wszystkie zestawy z osobistym użytkownika (do listy w Preferencjach).
    public var allPreferenceSets: [PreferenceSet] {
        (preferenceSets + [PreferenceSet(id: Self.personalSetID, name: L10n.tr("Osobisty"), kind: .personalUser, values: personalPreferences)])
            .sorted { ($0.kind.rank, $0.name) < ($1.kind.rank, $1.name) }
    }

    public static let personalSetID = UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!

    /// Zestawy obowiązujące dla połączenia głównego (z osobistym użytkownika).
    public var activePreferenceSets: [PreferenceSet] {
        let names = PreferenceSets.candidates(for: sessions.mainConnectionID.flatMap { connections.connection($0) })
        return allPreferenceSets.filter { $0.applies(to: names) }
    }

    /// Zestaw, z którego pochodzi wartość pola w obecnym połączeniu (nil — wartość wbudowana).
    public func preferenceSource(of key: String) -> PreferenceSet? {
        PreferenceSets.source(of: key, in: activePreferenceSets)
    }

    /// Przelicza preferencje po zmianie zestawów albo połączenia głównego.
    public func applyPreferenceSets() {
        let merged = PreferenceSets.merge(activePreferenceSets)
        guard merged != settings else { settingsBox.value = settings; return }
        applyingPreferenceSets = true
        settings = merged
        applyingPreferenceSets = false
    }

    private func recordPreferenceChange(from old: Settings, to new: Settings) {
        let changed = PreferenceSets.difference(new, from: old)
        guard !changed.isEmpty else { saveSettings(); return }
        if let id = preferenceEditTarget, let i = preferenceSets.firstIndex(where: { $0.id == id }) {
            for (k, v) in changed { preferenceSets[i].values[k] = v }
            try? preferenceStore.save(preferenceSets)
        } else {
            for (k, v) in changed { personalPreferences[k] = v }
        }
        saveSettings()
        applyPreferenceSets()
    }

    /// Dodaje albo zastępuje zestaw (domyślny albo połączeniowy) i przelicza preferencje.
    public func savePreferenceSet(_ set: PreferenceSet) throws {
        guard set.kind != .personalUser else { personalPreferences = set.values; saveSettings(); applyPreferenceSets(); return }
        if let i = preferenceSets.firstIndex(where: { $0.id == set.id }) { preferenceSets[i] = set } else { preferenceSets.append(set) }
        try preferenceStore.save(preferenceSets)
        applyPreferenceSets()
    }

    public func deletePreferenceSet(_ id: UUID) throws {
        preferenceSets.removeAll { $0.id == id }
        if preferenceEditTarget == id { preferenceEditTarget = nil }
        try preferenceStore.save(preferenceSets)
        applyPreferenceSets()
    }

    /// Usuwa wartość pola z zestawu — wraca wartość dziedziczona z zestawu niższego (albo wbudowana).
    public func inheritPreference(_ key: String, in setID: UUID) throws {
        if setID == Self.personalSetID {
            personalPreferences[key] = nil
            saveSettings()
        } else if let i = preferenceSets.firstIndex(where: { $0.id == setID }) {
            preferenceSets[i].values[key] = nil
            try preferenceStore.save(preferenceSets)
        }
        applyPreferenceSets()
    }

    /// Wczytuje wartości (np. z pliku eksportu) do zestawu edytowanego.
    public func importPreferences(_ values: [String: JSONValue]) throws {
        if let id = preferenceEditTarget, let i = preferenceSets.firstIndex(where: { $0.id == id }) {
            preferenceSets[i].values.merge(values) { $1 }
            try preferenceStore.save(preferenceSets)
        } else {
            personalPreferences.merge(values) { $1 }
            saveSettings()
        }
        applyPreferenceSets()
    }

    // MARK: Dokumenty

    public var activeDocument: Document? {
        guard let id = activeDocumentID else { return nil }
        return documents.first { $0.id == id }
    }

    @discardableResult
    public func newDocument(_ kind: DocumentKind, text: String = "", fileURL: URL? = nil) -> Document {
        let n = (ordinals[kind] ?? 0) + 1
        ordinals[kind] = n
        let doc = Document(kind: kind, ordinal: n, text: text, fileURL: fileURL)
        // Ustawienia › Ogólne › „Przypinaj połączenie nowych okien” (PD-CONN-019, UG 23.1): nowe okno SQL, programu,
        // testu i poleceń zostaje przy bieżącym połączeniu głównym, gdy główne się zmieni. Bez połączenia głównego okno
        // nie ma czego przypiąć — dostanie główne przy logowaniu, jak nieprzypięte.
        if settings.pinWindowConnectionsByDefault, [.sql, .program, .test, .command].contains(kind), let main = sessions.mainConnectionID {
            doc.connectionID = main
            doc.connectionPinned = true
        }
        documents.append(doc)
        activeDocumentID = doc.id
        return doc
    }

    public func activate(_ id: DocumentID) {
        guard documents.contains(where: { $0.id == id }) else { return }
        activeDocumentID = id
    }

    public func close(_ id: DocumentID) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        // Następne okno tej samej grupy kart (D200): z prawej, inaczej z lewej; grupa bez okien — ostatnio używane.
        let next = activeDocumentID == id ? nextAfterClosing(id) : nil
        saveWindowState(documents[i])
        consoles.persist(documents[i])
        documents.remove(at: i)
        sqlplusEngines[id] = nil
        diagnostics[id] = nil
        debuggers[id] = nil
        activationTicks[id] = nil
        releaseTabGroupAssignment(id)
        if activeDocumentID == id {
            activeDocumentID = next.flatMap { n in documents.contains { $0.id == n } ? n : nil }
                ?? (documents.isEmpty ? nil : documents[min(i, documents.count - 1)].id)
        }
    }

    /// Następne / poprzednie okno (Ctrl+Tab / Ctrl+Shift+Tab, NF11): po oknach bieżącej grupy kart, a na jej końcu —
    /// pierwsze okno następnej grupy (na początku — ostatnie poprzedniej); każde okno osiągalne (D200).
    public func cycleDocuments(forward: Bool) {
        let ids = tabCycleOrder
        guard !ids.isEmpty else { return }
        let i = ids.firstIndex { $0 == activeDocumentID } ?? 0
        let j = (i + (forward ? 1 : ids.count - 1)) % ids.count
        activeDocumentID = ids[j]
    }

    // MARK: Komendy

    func rebuildKeymap() {
        keymap = Keymap(commands: registry.descriptors, profile: shortcutProfile, overrides: keyOverrides)
    }

    public func register(_ commands: [Command]) {
        for c in commands { registry.register(c) }
        rebuildKeymap()
    }

    /// Usuwa komendy dodane w trakcie działania (np. usunięte makro).
    public func unregister(_ ids: [CommandID]) {
        guard !ids.isEmpty else { return }
        registry.remove(ids)
        rebuildKeymap()
    }

    public func onInvocation(_ observer: @escaping @MainActor (CommandInvocationRecord) -> Void) {
        invocationObservers.append(observer)
    }

    /// Czy komenda jest teraz dostępna (stan menu, palety, narzędzia agenta).
    public func isEnabled(_ id: CommandID) -> Bool {
        guard let c = registry.command(id) else { return false }
        return c.validate?(self) ?? true
    }

    /// Jedyny punkt wywołania komendy — menu, skróty, paleta, linia poleceń i agent.
    @discardableResult
    public func invoke(_ id: CommandID, _ arguments: CommandArguments = .empty, invoker: Invoker = .user) async throws -> CommandResult {
        guard let command = registry.command(id) else { throw CommandError.unknownCommand(id) }
        // Stan menu obowiązuje wszystkich wywołujących (także agenta): komenda wyłączona nie wykonuje się. Komenda
        // wywołana z argumentami (np. obiekt wskazany nazwą zamiast zaznaczenia) sama sprawdza swój cel. Klucze
        // wewnętrzne („__…”, np. znacznik run_command) nie są argumentami — nie wyłączają sprawdzenia.
        let explicit = arguments.values.keys.contains { !$0.hasPrefix("__") }
        if !explicit, let validate = command.validate, !validate(self) {
            throw CommandError.notAvailable(L10n.tr("„\(command.descriptor.title)” jest teraz niedostępne"))
        }
        var context = CommandContext(workspace: self, invoker: invoker, arguments: arguments)
        let started = Date()
        let clock = ContinuousClock.now
        do {
            if invoker.isAgent {
                // Agent bez bramki uprawnień (serwer agentów nie działa) nie wykonuje niczego.
                guard let gate = agentGate else { throw AgentDenial.sessionClosed }
                context = CommandContext(workspace: self, invoker: invoker, arguments: try await gate.authorize(command, context: context))
            }
            let result = if let s = invoker.agentSessionID, AgentChanges.serializedCommands.contains(id) {
                try await agentSerialized(s) { try await command.run(context) }
            } else {
                try await command.run(context)
            }
            notify(CommandInvocationRecord(command: id, arguments: arguments, invoker: invoker, started: started, outcome: .success(result.message)),
                   resolved: result.resolvedArguments)
            Log.command.debug("Komenda \(id.rawValue, privacy: .public)\(invoker.isAgent ? " (agent)" : "", privacy: .public): \(ms: clock)")
            return result
        } catch {
            notify(CommandInvocationRecord(command: id, arguments: arguments, invoker: invoker, started: started, outcome: .failure(error.localizedDescription)))
            // Rezygnacja użytkownika to nie błąd; odmowa agenta trafia też do dziennika agentów.
            if case CommandError.cancelledByUser = error {
                Log.command.debug("Komenda \(id.rawValue, privacy: .public) anulowana")
            } else {
                Log.command.notice("Komenda \(id.rawValue, privacy: .public)\(invoker.isAgent ? " (agent)" : "", privacy: .public) nie powiodła się po \(ms: clock): \(error)")
            }
            throw error
        }
    }

    /// Skutki komendy „na sucho” (okno zgody, potwierdzenia).
    public func preview(_ id: CommandID, _ arguments: CommandArguments = .empty, invoker: Invoker = .user) async throws -> EffectPreview {
        guard let command = registry.command(id) else { throw CommandError.unknownCommand(id) }
        let context = CommandContext(workspace: self, invoker: invoker, arguments: arguments)
        if let preview = command.preview {
            if let s = invoker.agentSessionID, AgentChanges.serializedCommands.contains(id) { return try await agentSerialized(s) { try await preview(context) } }
            return try await preview(context)
        }
        return EffectPreview(summary: command.descriptor.summary)
    }

    /// Wywołanie z interfejsu: błędy pokazywane użytkownikowi zamiast rzucane. Zadanie — gdy trzeba poczekać na koniec.
    @discardableResult
    public func perform(_ id: CommandID, _ arguments: CommandArguments = .empty) -> Task<Void, Never> {
        Task {
            do {
                try await invoke(id, arguments)
            } catch CommandError.cancelledByUser {
            } catch DatabaseError.clientMissing(let message) {
                ui?.showClientMissingHelp(message)
            } catch {
                ui?.showError(error.localizedDescription)
            }
        }
    }

    private func notify(_ record: CommandInvocationRecord, resolved: CommandArguments? = nil) {
        recordMacroInvocation(record, resolved: resolved)
        for o in invocationObservers { o(record) }
    }
}

/// Bieżące ustawienia dla menedżera sesji (unika cyklu referencji do Workspace).
@MainActor
final class SettingsBox {
    var value = Settings()
}

// MARK: - Połączenia okien

extension Workspace {
    /// Połączenie okna: przypięte albo główne (UG 20.2).
    public func effectiveConnection(of doc: Document) -> UUID? {
        doc.isDisconnected ? nil : doc.connectionID ?? sessions.mainConnectionID
    }

    /// Klucz sesji okna wg trybu sesji (nil — okno bez połączenia).
    public func sessionKey(for doc: Document) -> SessionKey? {
        guard let c = effectiveConnection(of: doc) else { return nil }
        return doc.sessionPurpose.map { SessionKey(connectionID: c, purpose: $0) } ?? sessions.key(forDocument: doc.id, connection: c)
    }

    /// Sesja okna wg trybu sesji (łączy, jeśli trzeba).
    public func session(for doc: Document) async throws -> any DatabaseSession {
        guard let key = sessionKey(for: doc) else { throw CommandError.notConnected }
        sessions.touch(key)
        return try await sessions.session(key)
    }

    /// Po zestawieniu sesji (łączenie, pytania): okno mogło zostać zamknięte w międzyczasie — wtedy jego świeża sesja
    /// (tryb Multi) jest zamykana, a polecenie się nie wykonuje. `wasOpen` — okno było na liście na początku wykonania
    /// (dokumenty spoza listy, np. testy Test Managera, nie są sprawdzane).
    func ensureStillOpen(_ doc: Document, wasOpen: Bool) async throws {
        guard wasOpen, !documents.contains(where: { $0 === doc }) else { return }
        if let key = sessionKey(for: doc), case .document(doc.id) = key.purpose { await sessions.close(key) }
        throw CommandError.cancelledByUser
    }

    /// Sesje okien zajęte wykonaniem albo otwartym kursorem wyniku (dociąganie wierszy).
    var busySessionKeys: Set<SessionKey> {
        Set(documents.filter { d in d.isExecuting || d.results.contains { $0.grid?.hasMore == true } }.compactMap(sessionKey(for:)))
    }

    /// Przebieg sprawdzania połączeń (UG 23.1 „Check connection”, timer aplikacji): zamykanie bezczynnych sesji okien
    /// (PD-CONN-026), zmiany obiektów okien programu (PD-PROG-011) i — gdy interwał > 0 — ping sesji głównych oraz sesji
    /// okien z otwartą transakcją. Interwał 0 wyłącza tylko ping (pozostałe co minutę); zmiana interwału działa od razu.
    /// Kolejny przebieg nie rusza przed końcem poprzedniego. Zwraca komunikat o utraconych połączeniach (nil — brak).
    public func connectionCheckTick(now: Date = Date()) async -> String? {
        let seconds = settings.checkConnectionIntervalSeconds
        let period = TimeInterval(seconds > 0 ? max(15, seconds) : 60)
        guard !sessions.connectionCheckRunning, now.timeIntervalSince(sessions.lastConnectionCheck) >= period - 1 else { return nil }
        sessions.connectionCheckRunning = true
        defer { sessions.connectionCheckRunning = false }
        sessions.lastConnectionCheck = now
        await sessions.closeIdleSessions(olderThan: settings.closeIdleSessionsMinutes, busy: busySessionKeys, now: now)
        await checkProgramWindowChanges()
        guard seconds > 0 else { return nil }
        let withTransaction = Set(documents.filter(\.transactionOpen).compactMap(sessionKey(for:)))
        let lost = Set(await sessions.checkConnections(also: withTransaction, busy: busySessionKeys))
        guard !lost.isEmpty else { return nil }
        // Tylko okna, których sesja przepadła (w trybie Multi inne okna połączenia mają własne, żywe sesje).
        var windows: [String] = []
        for d in documents where d.transactionOpen {
            guard let k = sessionKey(for: d), lost.contains(k) else { continue }
            d.transactionOpen = false
            windows.append(d.title)
        }
        let names = Set(lost.compactMap { connections.connection($0.connectionID)?.displayName }).sorted().joined(separator: ", ")
        var message = L10n.tr("Połączenie utracone: \(names). Kolejne polecenie połączy się ponownie.")
        if !windows.isEmpty { message += " " + L10n.tr("Niezatwierdzone zmiany okien zostały wycofane przez serwer: \(windows.joined(separator: ", ")).") }
        return message
    }

    /// Kończy transakcje okien (COMMIT/ROLLBACK) przed rozłączeniem lub zamknięciem.
    public func endTransactions(of docs: [Document], commit: Bool) async throws {
        for d in docs {
            // Klucz jak przy wykonaniu (także okna z własnym przeznaczeniem sesji), inaczej COMMIT/ROLLBACK trafiłby obok.
            guard let key = sessionKey(for: d), let s = sessions.existingSession(key) else { continue }
            if commit { try await s.commit() } else { try await s.rollback() }
            d.transactionOpen = false
        }
    }

    /// Polecenie okna skończyło się utratą połączenia (ORA-03113, ORA-03114…): martwa sesja znika z mapy, żeby
    /// kolejne polecenie połączyło się ponownie. Sesja szukana po tożsamości, nie po bieżącym kluczu okna — połączenie
    /// okna albo główne mogło się zmienić w trakcie polecenia. Okna tej sesji (Dual/Single: wszystkie na sesji głównej)
    /// tracą otwartą transakcję — wycofał ją serwer.
    @discardableResult
    public func dropLostSession(_ session: any DatabaseSession) -> Bool {
        guard let key = sessions.key(of: session), sessions.dropLost(key) else { return false }
        for d in documents where d.transactionOpen && sessionKey(for: d) == key { d.transactionOpen = false }
        return true
    }
}

/// Wpis historii poleceń.
public struct HistoryEntry: Sendable, Codable, Hashable {
    public var date: Date
    public var user: String
    public var text: String
}
