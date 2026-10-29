import Foundation
import Observation
import PelikanSQL

/// Rodzaj okna dokumentu (odpowiedniki okien PL/SQL Developer).
public enum DocumentKind: String, Sendable, Codable, CaseIterable {
    case sql, program, test, command, explainPlan, report, diagram, notebook

    public var displayName: String {
        switch self {
        case .sql: L10n.tr("Okno SQL")
        case .program: L10n.tr("Okno programu")
        case .test: L10n.tr("Okno testu")
        case .command: L10n.tr("Konsola SQL*Plus")
        case .explainPlan: L10n.tr("Okno planu")
        case .report: L10n.tr("Okno raportu")
        case .diagram: L10n.tr("Okno diagramu")
        case .notebook: L10n.tr("Notatnik SQL")
        }
    }

    /// Krótka forma („Short Text” w Window List wzorca).
    public var shortName: String {
        switch self {
        case .sql: "S"
        case .program: "P"
        case .test: "T"
        case .command: "C"
        case .explainPlan: "E"
        case .report: "R"
        case .diagram: "D"
        case .notebook: "N"
        }
    }

    /// Domyślne rozszerzenie pliku (UG 4.2, 5.4, 7.13, 23.29).
    public var defaultExtension: String {
        switch self {
        case .sql, .command: "sql"
        case .program: "pck"
        case .test: "tst"
        case .explainPlan: "sql"
        case .report: "rep"
        case .diagram: "pdd"
        case .notebook: "sqlnb"
        }
    }

    /// Okno z panelem Zawartość kodu obok edytora (D199): okno programu, SQL i testu.
    public var hasCodeContents: Bool { [.sql, .program, .test].contains(self) }
}

public struct DocumentID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: UUID
    public init() { raw = UUID() }
    public var description: String { raw.uuidString }
}

/// Okno dokumentu w modelu. Treść edytora jest tu (a nie w widoku), żeby API agenta i komendy widziały ten sam stan.
@MainActor
@Observable
public final class Document: Identifiable {
    public let id: DocumentID
    public let kind: DocumentKind
    /// Kolejny numer okna danego typu (do tytułu „Okno SQL – nowe 2”).
    public let ordinal: Int
    public var customTitle: String?
    public var fileURL: URL?
    /// Kodowanie i zakończenia linii pliku (zapis w tym samym formacie, w jakim plik otwarto).
    public var fileFormat = TextFileFormat()
    /// Okno programu powiązane z plikami specyfikacji i ciała (D194): każda jednostka zapisywana do swojego pliku;
    /// `fileURL` to wtedy plik specyfikacji (klucz stanu okna, historii lokalnej, workseta). Puste — jeden plik okna.
    public var unitFiles: [UnitFile] = []
    /// Stan plików okna na dysku z otwarcia, zapisu albo wczytania ponownego (D197) — wykrywanie zmian przez inny program.
    @ObservationIgnored public var diskStamps: [URL: FileStamp] = [:]
    /// Skrót bajtów pliku okna (bez pary) z otwarcia albo zapisu — zapis ostrzega, gdy plik zmienił się na dysku.
    @ObservationIgnored public var savedFileHash: UInt64?
    /// Ostatnie porównanie treści pliku na woluminie nielokalnym (co najwyżej co 5 s na plik, D197).
    @ObservationIgnored public var contentChecks: [URL: Date] = [:]
    /// Zapis okna w toku (pytania, okno wyboru nazwy) — drugi zapis w tym czasie jest pomijany.
    @ObservationIgnored public var isSaving = false
    public var text: String {
        didSet {
            if text != oldValue {
                textRevision &+= 1
                isModified = true
                if kind == .program { isCompileStale = true }
                if !foldedStarts.isEmpty { foldedStarts = CodeFolding.shift(foldedStarts, from: oldValue, to: text) }
                if !bookmarks.isEmpty || !colorMarks.isEmpty || editSessionMarks.contains(where: { $0.range != nil }) {
                    let d = EditorShift.Change(old: oldValue, new: text)
                    editSessionMarks = editSessionMarks.map { m in
                        var m = m
                        m.range = m.range.flatMap { d.shift($0) }
                        return m
                    }
                    bookmarks = bookmarks.map { var b = $0; b.offset = d.shift(b.offset); return b }
                    colorMarks = colorMarks.compactMap { m in d.shift(m.range).map { ColorMark(range: $0, color: m.color) } }
                }
            }
        }
    }
    /// Numer wersji tekstu (rośnie przy każdej zmianie) — klucz pamięci podręcznej jednostek programu.
    @ObservationIgnored public private(set) var textRevision = 0
    @ObservationIgnored private var unitsCache: (revision: Int, units: [ProgramUnit])?

    /// Jednostki okna programu (`ProgramCompiler.units`) liczone raz na zmianę tekstu, nie przy każdym rysowaniu
    /// marginesu czy walidacji wstążki (pakiet 50 000 linii — R4-01). Odczyt rejestruje obserwację `text`.
    public var programUnits: [ProgramUnit] {
        let current = text
        if let c = unitsCache, c.revision == textRevision { return c.units }
        let units = ProgramCompiler.units(in: current)
        unitsCache = (textRevision, units)
        return units
    }

    /// Jednostki policzone w tle dla tekstu `forText` — trafiają do pamięci, gdy tekst okna się od tego czasu nie zmienił.
    public func cacheProgramUnits(_ units: [ProgramUnit], forText: String) {
        guard text == forText else { return }
        unitsCache = (textRevision, units)
    }

    @ObservationIgnored private var tabsCache: (revision: Int, tabs: [ProgramUnitTab])?

    /// Karty jednostek okna programu (D192): odcinki tekstu jednostek; mniej niż dwie jednostki — pusto.
    public var programUnitTabs: [ProgramUnitTab] {
        guard kind == .program else { return [] }
        let units = programUnits
        if let c = tabsCache, c.revision == textRevision { return c.tabs }
        let tabs = ProgramUnitTabs.tabs(units, in: text)
        tabsCache = (textRevision, tabs)
        return tabs
    }

    /// Liczba kart z ostatniego podziału (także sprzed ostatniej zmiany tekstu) — do walidacji menu i wstążki bez
    /// dzielenia tekstu na wątku głównym przy każdym znaku (R4-01); pierwszy raz liczona.
    public var unitTabCount: Int {
        guard kind == .program else { return 0 }
        if let c = tabsCache { return c.tabs.count }
        return programUnitTabs.count
    }

    /// Zapisuje karty policzone w tle dla tekstu `forText` (okno programu po analizie).
    public func cacheProgramUnitTabs(_ tabs: [ProgramUnitTab], forText: String) {
        guard text == forText else { return }
        tabsCache = (textRevision, tabs)
    }

    /// Zakres pozycji kursora na karcie z kursorem (okno programu z kartami; nil — bez kart), liczony z modelu w chwili
    /// wywołania — nie z widoku, który przełącza kartę dopiero po zmianie zaznaczenia (agent albo makro zmienia
    /// zaznaczenie i od razu wywołuje komendę edycji). Komendy edycji i dodatkowe kursory nie wychodzą poza niego.
    public var unitEditBounds: ClosedRange<Int>? {
        // Okno z jedną jednostką (według pamięci kart) — bez dzielenia tekstu przy każdej komendzie edycji.
        guard unitTabCount > 1 else { return nil }
        let tabs = programUnitTabs
        guard let i = ProgramUnitTabs.index(of: selectedRange.lowerBound, in: tabs) else { return nil }
        let ns = text as NSString
        return min(tabs[i].segment.lowerBound, ns.length)...ProgramUnitTabs.caretLimit(tabs[i], isLast: i == tabs.count - 1, in: ns)
    }

    /// Karta aktywna — karta odcinka z kursorem (nil — okno bez kart).
    public var activeUnitTab: Int? { ProgramUnitTabs.index(of: selectedRange.lowerBound, in: programUnitTabs) }

    /// Karta widoczna w edytorze okna programu (ustawia widok przy zmianie karty) — do odczytu w śledzonym odświeżaniu
    /// bez obserwacji tekstu i kursora.
    public var shownUnitTab: Int?

    /// Plik karty widocznej w oknie pary (D194), inaczej plik okna — stan repozytorium na pasku okna. Z pamięci kart,
    /// bez odczytu tekstu: odświeżanie okna głównego nie dzieli tekstu na jednostki przy każdym znaku (R4-01).
    public var shownFileURL: URL? {
        guard unitFiles.count == 2, let i = shownUnitTab, let tabs = tabsCache?.tabs, tabs.indices.contains(i) else { return fileURL }
        let part: UnitFile.Part = tabs[i].key.hasSuffix(" body") ? .body : .spec
        return unitFiles.first { $0.part == part }?.url ?? fileURL
    }

    /// Ostatnia pozycja kursora na karcie (klucz karty → odległość od początku odcinka) — powrót na kartę wraca w to
    /// samo miejsce, jak w oknie programu wzorca.
    @ObservationIgnored public var unitCarets: [String: Int] = [:]

    public var selectedRange: Range<Int> = 0..<0
    public var isModified = false {
        didSet {
            if !isModified {
                baselineText = text
                markEditSession(nil)
            }
        }
    }
    /// Początek nowej sesji edycji (D205): tekst z otwarcia, zapisu albo wczytania (`range` nil — cały tekst, inaczej
    /// zakres pliku wczytanego w oknie pary, w bieżącym tekście) — edytor zapomina zmiany w tym zakresie (formatowanie
    /// przy Enter dotyczy tylko linii zmienionych w sesji).
    public struct EditSessionMark: Sendable, Equatable {
        public var serial = 0
        public var range: Range<Int>?
    }
    /// Kolejka znaczników (najnowsze na końcu; zakresy przesuwane przy zmianach tekstu — kilka wczytań pary przed
    /// synchronizacją edytora). Znacznik całego tekstu zastępuje wcześniejsze.
    public internal(set) var editSessionMarks: [EditSessionMark] = []
    public var editSessionSerial: Int { editSessionMarks.last?.serial ?? 0 }

    func markEditSession(_ range: Range<Int>?) {
        let mark = EditSessionMark(serial: editSessionSerial + 1, range: range)
        editSessionMarks = range == nil ? [mark] : Array((editSessionMarks + [mark]).suffix(32))
    }
    /// Tekst z chwili otwarcia, wczytania z bazy albo zapisu — status linii (PD-EDIT-003) i Revert (PD-PROG-009).
    public internal(set) var baselineText = ""
    /// Zmieniony, nieskompilowany (Program Window).
    public var isCompileStale = false
    public var isExecuting = false
    public var transactionOpen = false
    /// Połączenie okna (nil = połączenie główne) i przypięcie (UG 20.2).
    public var connectionID: UUID?
    /// Po DISCONNECT w Command Window: okno bez połączenia do następnego CONNECT — także dla COMMIT/F10, paska stanu
    /// i innych komend (bez cichego przejścia na połączenie główne).
    public var isDisconnected = false
    public var connectionPinned = false
    /// Własny cel sesji dokumentu spoza listy okien (np. Test Manager) zamiast sesji wg trybu sesji.
    public var sessionPurpose: SessionPurpose?
    /// Konsola zapytań połączenia (DG-CONS-001): tekst zachowywany automatycznie, bez pliku.
    public var consoleConnectionID: UUID?

    // MARK: SQL Window (UG 7)
    /// Karty wyników (przypięte zostają przy kolejnym wykonaniu — UG 7.10).
    public var results: [ResultTab] = []
    public var activeResultID: UUID?

    /// Liczba wierszy aktywnej siatki na pasek stanu („600 wierszy (więcej…)”) — aktualna przy dociąganiu.
    public var resultSummary: String? {
        guard let tab = results.first(where: { $0.id == activeResultID }) ?? results.first, let g = tab.grid else { return nil }
        return g.hasMore ? L10n.tr("\(g.rowCount) wierszy (więcej…)") : L10n.tr("\(g.rowCount) wierszy")
    }
    /// Wyjście DBMS_OUTPUT (karta Output).
    public var output: [String] = []
    public var outputEnabled = true
    /// Okno SQL z ukrytym edytorem — same wyniki (PD-GRID-012, „Hide Editor”).
    public var editorHidden = false
    /// Komunikat na pasku stanu okna (czas wykonania, liczba wierszy, błąd).
    public var statusText: String?
    /// Zakres błędu w tekście (UTF-16) do zaznaczenia w edytorze.
    public var errorRange: Range<Int>?
    /// Wartości zmiennych (&, :, Jasper) — zapamiętywane w oknie (UG 23.18).
    public var variableValues: [String: VariableValue] = [:]
    /// Sumy kolumn trwałe po ponownym wykonaniu (PD-GRID-024): nazwa kolumny (wielkie litery) → funkcje.
    public var columnTotals: [String: [ColumnAggregate]] = [:]
    /// Automatyczne odświeżanie wyników co n sekund (PD-SQLW-006); nil — wyłączone.
    public var autoRefreshSeconds: Int?
    @ObservationIgnored public var autoRefreshTask: Task<Void, Never>?
    /// Podstawianie zmiennych włączone (przycisk `&` na pasku stanu — UG 7.5, NF17).
    public var substitutionEnabled = true
    /// Historia poleceń okna (przyciski wstecz/dalej — UG 7.1).
    public var statementHistory: [String] = []
    /// Command Window: wyjście karty Dialog i historia linii poleceń (strzałki w górę/dół).
    public var console: [ConsoleLine] = []
    public var commandLineHistory: [String] = []
    /// Program Window: błędy, ostrzeżenia i podpowiedzi ostatniej kompilacji (UG 4.4).
    public var compileMessages: [CompileMessage] = []
    /// LAST_DDL_TIME obiektów okna programu przy wczytaniu albo kompilacji — wykrywanie zmian w bazie (PD-PROG-011).
    public var objectTimestamps: [String: String] = [:]
    /// Okno diagramu: model i zaznaczone elementy (PD-DIAG-001).
    public var diagram = Diagram()
    /// Notatnik SQL: komórki z wynikami (SD-NB-001).
    public var notebook = Notebook()
    /// Okno raportu: definicja (zapytanie w `text`), wynik HTML i dane, błąd (PD-REP-002).
    public var report = ReportDefinition(title: "", sql: "")
    public var reportHTML: String?
    public var reportData: ReportData?
    public var reportError: String?
    public var diagramSelection: Set<UUID> = []
    /// Okno planu: wynik Explain Plan, cel optymalizatora, błąd (PD-OPT-001).
    public var plan: ExplainPlanResult? {
        willSet { if let p = plan, newValue?.statementID != p.statementID { previousPlan = p } }
        didSet {
            // Pierwszy plan okna albo plan innego polecenia — drzewo rozwinięte (jak we wzorcu); ponowny plan tego samego
            // polecenia zachowuje rozwinięcie użytkownika (bez gałęzi, których nowy plan nie ma).
            guard let p = plan else { return }
            if let old = oldValue, old.sql == p.sql { planExpanded.formIntersection(p.branchIDs) } else { planExpanded = p.branchIDs }
        }
    }
    /// Poprzedni plan okna (porównanie planów, SD-PLAN-003).
    public var previousPlan: ExplainPlanResult?
    public var planGoal: OptimizerGoal = .session
    /// Rozwinięte gałęzie drzewa planu (PLAN_TABLE.ID): nowy plan rozwinięty w całości, ponowny plan tego samego polecenia
    /// zachowuje rozwinięcie.
    public var planExpanded: Set<Int> = []

    /// Rozwija gałęzie nad krokiem planu, żeby zaznaczony krok był widoczny w drzewie (nawigacja, powrót z Diagramu).
    public func revealPlanLine(_ id: Int) {
        guard let p = plan else { return }
        let missing = p.ancestors(of: id).filter { !planExpanded.contains($0) }
        if !missing.isEmpty { planExpanded.formUnion(missing) }
    }
    public var planError: String?
    /// Zmienne okna testowego (UG 5.1) i stos ostatniego błędu wykonania (UG 5.5).
    public var testVariables: [TestVariable] = []
    /// Wyrażenia obserwowane debugera okna testu — zapisywane w pliku .tst (PD-TEST-005).
    public var testWatches: [String] = []
    public var errorStack: [ErrorStackFrame] = []
    /// Niejawne wyniki ostatniego wykonania okna testu (UG 5.7).
    public var testResults: [TestResultSet] = []
    /// HTP Output okna testu (PD-TEST-008): zbieranie strony HTP/HTF przy wykonaniu i jej treść z ostatniego wykonania.
    public var htpEnabled = false
    public var htpOutput: String?
    /// Profiler przy wykonaniu okna testu (nil — wyłączony) i raport ostatniego przebiegu (UG 6.3).
    public var profiler: ProfilerKind?
    public var profilerReport: ProfilerReport?
    /// Ślad DBMS_TRACE okna testu (PD-OPT-007): poziom (nil — wyłączony), numer i zdarzenia ostatniego przebiegu.
    public var traceLevel: PLSQLTrace.Level?
    public var traceRun: Int?
    public var traceEvents: [PLSQLTrace.Event] = []
    /// Statystyki sesji ostatniego wykonania (różnica V$MYSTAT, UG 6.2) — nazwa i wartość.
    public var statistics: [SessionStatistic] = []
    /// Suma różnic statystyk wszystkich wykonań okna (kolumna „Suma”, PD-OPT-004).
    public var statisticTotals: [String: Double] = [:]

    /// Zapisuje statystyki ostatniego wykonania i dolicza je do sumy okna.
    public func recordStatistics(_ s: [SessionStatistic]) {
        statistics = s
        for x in s { statisticTotals[x.name, default: 0] += x.value }
    }
    /// Linia (od 1), w której zatrzymał się debuger — wyróżniona w edytorze (UG 5.10).
    public var executionLine: Int?
    /// Zwinięte obszary kodu (UG 25.17) — początki struktur (`FoldRegion.start`), przesuwane przy zmianach tekstu.
    public var foldedStarts: Set<Int> = []
    /// Zakładki 0–9 (PD-EDIT-011) i znaczniki kolorów (PD-EDIT-012) — przesuwane przy zmianach tekstu.
    public var bookmarks: [Bookmark] = []
    public var colorMarks: [ColorMark] = []
    /// Dodatkowe kursory i zaznaczenia poza `selectedRange` (PD-EDIT-007, PD-EDIT-023).
    public var additionalSelections: [Range<Int>] = []
    /// Okno tylko do odczytu (PD-FILE-003) i drugi widok tego samego tekstu (PD-EDIT-014).
    public var isReadOnly = false
    public var splitEditor = false
    /// Panel Zawartość kodu w tym oknie (D199): nil — jak w Ustawieniach (`showCodeContents`), inaczej wybór
    /// użytkownika w oknie (komenda `view.codeContents`), zapamiętany w worksecie.
    public var codeContentsVisible: Bool?
    public var historyPosition: Int?

    public init(kind: DocumentKind, ordinal: Int, text: String = "", fileURL: URL? = nil) {
        id = DocumentID()
        self.kind = kind
        self.ordinal = ordinal
        self.text = text
        self.fileURL = fileURL
        isModified = false
        baselineText = text
    }

    public var title: String {
        if let customTitle { return customTitle }
        if unitFiles.count == 2, let s = unitFiles.first(where: { $0.part == .spec }), let b = unitFiles.first(where: { $0.part == .body }) {
            // Para plików: „emp_api.pks + .pkb” (ta sama nazwa), inaczej obie nazwy.
            let same = s.url.deletingPathExtension().lastPathComponent == b.url.deletingPathExtension().lastPathComponent
            return s.url.lastPathComponent + " + " + (same ? "." + b.url.pathExtension : b.url.lastPathComponent)
        }
        if let fileURL { return fileURL.lastPathComponent }
        return ordinal > 1 ? L10n.tr("Nowe \(ordinal)") : L10n.tr("Nowe")
    }

    /// Pełny tytuł jak w Window List wzorca: „Okno SQL – nowe”.
    public var fullTitle: String { "\(kind.displayName) – \(title)" }
}
