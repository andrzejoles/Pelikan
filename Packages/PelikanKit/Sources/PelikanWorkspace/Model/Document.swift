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
            }
        }
    }
    public var selectedRange: Range<Int> = 0..<0
    public var isModified = false
    /// Zmieniony, nieskompilowany (Program Window).
    public var isCompileStale = false
    public var isExecuting = false
    public var transactionOpen = false
    /// Połączenie okna (nil = połączenie główne) i przypięcie (UG 20.2).
    public var connectionID: UUID?
    public var connectionPinned = false

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
    /// Podstawianie zmiennych włączone (przycisk `&` na pasku stanu — UG 7.5, NF17).
    public var substitutionEnabled = true
    /// Historia poleceń okna (przyciski wstecz/dalej — UG 7.1).
    public var statementHistory: [String] = []
    /// Command Window: wyjście karty Dialog i historia linii poleceń (strzałki w górę/dół).
    public var console: [ConsoleLine] = []
    public var commandLineHistory: [String] = []
    /// Program Window: błędy, ostrzeżenia i podpowiedzi ostatniej kompilacji (UG 4.4).
    public var compileMessages: [CompileMessage] = []
    /// Zmienne okna testowego (UG 5.1) i stos ostatniego błędu wykonania (UG 5.5).
    public var testVariables: [TestVariable] = []
    public var errorStack: [ErrorStackFrame] = []
    /// Linia (od 1), w której zatrzymał się debuger — wyróżniona w edytorze (UG 5.10).
    public var executionLine: Int?
    /// Zwinięte obszary kodu (UG 25.17) — początki struktur (`FoldRegion.start`), przesuwane przy zmianach tekstu.
    public var foldedStarts: Set<Int> = []
    public var historyPosition: Int?

    public init(kind: DocumentKind, ordinal: Int, text: String = "", fileURL: URL? = nil) {
        id = DocumentID()
        self.kind = kind
        self.ordinal = ordinal
        self.text = text
        self.fileURL = fileURL
        isModified = false
    }

    public var title: String {
        if let customTitle { return customTitle }
        if let fileURL { return fileURL.lastPathComponent }
        return ordinal > 1 ? L10n.tr("Nowe \(ordinal)") : L10n.tr("Nowe")
    }

    /// Pełny tytuł jak w Window List wzorca: „Okno SQL – nowe”.
    public var fullTitle: String { "\(kind.displayName) – \(title)" }
}
