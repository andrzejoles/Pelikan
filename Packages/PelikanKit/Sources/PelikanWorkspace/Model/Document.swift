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
        case .command: L10n.tr("Okno poleceń")
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
    public var text: String {
        didSet {
            if text != oldValue {
                isModified = true
                if kind == .program { isCompileStale = true }
                if !foldedStarts.isEmpty { foldedStarts = CodeFolding.shift(foldedStarts, from: oldValue, to: text) }
                if !bookmarks.isEmpty || !colorMarks.isEmpty {
                    let d = EditorShift.Change(old: oldValue, new: text)
                    bookmarks = bookmarks.map { var b = $0; b.offset = d.shift(b.offset); return b }
                    colorMarks = colorMarks.compactMap { m in d.shift(m.range).map { ColorMark(range: $0, color: m.color) } }
                }
            }
        }
    }
    public var selectedRange: Range<Int> = 0..<0
    public var isModified = false {
        didSet { if !isModified { baselineText = text } }
    }
    /// Tekst z chwili otwarcia, wczytania z bazy albo zapisu — status linii (PD-EDIT-003) i Revert (PD-PROG-009).
    public internal(set) var baselineText = ""
    /// Zmieniony, nieskompilowany (Program Window).
    public var isCompileStale = false
    public var isExecuting = false
    public var transactionOpen = false
    /// Połączenie okna (nil = połączenie główne) i przypięcie (UG 20.2).
    public var connectionID: UUID?
    public var connectionPinned = false
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
    }
    /// Poprzedni plan okna (porównanie planów, SD-PLAN-003).
    public var previousPlan: ExplainPlanResult?
    public var planGoal: OptimizerGoal = .session
    public var planError: String?
    /// Zmienne okna testowego (UG 5.1) i stos ostatniego błędu wykonania (UG 5.5).
    public var testVariables: [TestVariable] = []
    /// Wyrażenia obserwowane debugera okna testu — zapisywane w pliku .tst (PD-TEST-005).
    public var testWatches: [String] = []
    public var errorStack: [ErrorStackFrame] = []
    /// Niejawne wyniki ostatniego wykonania okna testu (UG 5.7).
    public var testResults: [TestResultSet] = []
    /// Profiler przy wykonaniu okna testu (nil — wyłączony) i raport ostatniego przebiegu (UG 6.3).
    public var profiler: ProfilerKind?
    public var profilerReport: ProfilerReport?
    /// Ślad DBMS_TRACE okna testu (PD-OPT-007): poziom (nil — wyłączony), numer i zdarzenia ostatniego przebiegu.
    public var traceLevel: PLSQLTrace.Level?
    public var traceRun: Int?
    public var traceEvents: [PLSQLTrace.Event] = []
    /// Statystyki sesji ostatniego wykonania (różnica V$MYSTAT, UG 6.2) — nazwa i wartość.
    public var statistics: [SessionStatistic] = []
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
        if let fileURL { return fileURL.lastPathComponent }
        return ordinal > 1 ? L10n.tr("Nowe \(ordinal)") : L10n.tr("Nowe")
    }

    /// Pełny tytuł jak w Window List wzorca: „Okno SQL – nowe”.
    public var fullTitle: String { "\(kind.displayName) – \(title)" }
}
