import Foundation
import Observation
import PelikanDB

/// Model siatki wyników (ADR 0004): kolumny, pobrane wiersze, dociąganie porcjami z kursora sesji.
/// Bez AppKit — interfejs czyta `rowCount`, `columns`, `text(row:column:)`, a przy zbliżeniu do końca woła `fetchMore`.
@MainActor
@Observable
public final class ResultGridModel {
    public let columns: [ColumnInfo]
    public internal(set) var rows: [[OracleValue]] = []
    public private(set) var hasMore: Bool
    public private(set) var isFetching = false
    public private(set) var lastError: String?
    /// Polecenie, z którego pochodzi wynik (odświeżanie, eksport SQL).
    public let sql: String
    @ObservationIgnored private let resultSet: ResultSetID
    @ObservationIgnored var sessionRef: (any DatabaseSession)?
    /// Sesja okna (także po wyczerpaniu kursora) — edycja i zatwierdzanie zmian siatki.
    @ObservationIgnored let session: any DatabaseSession
    /// Edycja danych (UG 7.6) — stan w GridEditing.swift.
    public internal(set) var edit = GridEditState()
    /// Edytor komórki otwarty w interfejsie: wpisana wartość trafi do modelu dopiero po jego zamknięciu
    /// (`UIServices.commitPendingEdits`), więc Zatwierdź, Kopiuj SQL i Anuluj zmiany są już dostępne (APP2-04).
    /// Osobno od `edit` — zmiana nie przeładowuje komórek siatki (to zamknęłoby edytor).
    public var cellEditorOpen = false
    @ObservationIgnored public var format: ValueFormat
    /// Limit rozmiaru wyniku w pamięci (PD-SQLW-026): po przekroczeniu dalsze pobieranie dopiero po potwierdzeniu.
    @ObservationIgnored public var sizeLimitBytes = 0
    @ObservationIgnored public var confirmSizeLimit: (@MainActor (Int) async -> Bool)?
    @ObservationIgnored var sizeLimitAccepted = false
    /// Szacowany rozmiar pobranych wierszy w bajtach.
    public private(set) var approximateBytes = 0
    /// Pobieranie wstrzymane na limicie rozmiaru (odmowa dalszego pobierania).
    public private(set) var stoppedAtSizeLimit = false

    public init(columns: [ColumnInfo], resultSet: ResultSetID, session: any DatabaseSession, sql: String, format: ValueFormat) {
        self.columns = columns
        self.resultSet = resultSet
        sessionRef = session
        self.session = session
        self.sql = sql
        self.format = format
        hasMore = true
    }

    /// Liczba wierszy widoku (z filtrem lokalnym — tylko pasujące; DB-GRID-001).
    public var rowCount: Int { order?.count ?? rows.count }
    /// Liczba pobranych wierszy (bez filtra).
    public var fetchedRowCount: Int { rows.count }

    /// Filtr lokalny na pobranych wierszach (DB-GRID-001); nil — wszystkie.
    public private(set) var filter: GridFilter?

    public func setFilter(_ f: GridFilter?) {
        filter = f
        applySort()
    }

    /// Sortowanie lokalne (UG 7.2): klucze w kolejności ważności; pusta lista — kolejność z bazy.
    public private(set) var sortKeys: [SortKey] = []
    /// Permutacja: wiersz widoku → wiersz danych (nil bez sortowania).
    @ObservationIgnored var order: [Int]?

    public struct SortKey: Sendable, Hashable {
        public var column: Int
        public var ascending: Bool
        public init(column: Int, ascending: Bool) { self.column = column; self.ascending = ascending }
    }

    /// Wiersz danych dla wiersza widoku.
    public func dataRow(_ viewRow: Int) -> Int { order.map { viewRow < $0.count ? $0[viewRow] : viewRow } ?? viewRow }

    public func value(row: Int, column: Int) -> OracleValue {
        let r = dataRow(row)
        guard r < rows.count, column < rows[r].count else { return .null }
        return rows[r][column]
    }

    /// Klik nagłówka: rosnąco → malejąco → bez sortowania; z Shift (`add`) — klucz dodatkowy.
    public func toggleSort(column: Int, add: Bool = false) {
        var keys = add ? sortKeys : sortKeys.filter { $0.column == column }
        if let i = keys.firstIndex(where: { $0.column == column }) {
            if keys[i].ascending { keys[i].ascending = false } else { keys.remove(at: i) }
        } else {
            keys.append(SortKey(column: column, ascending: true))
        }
        sort(keys)
    }

    public func sort(_ keys: [SortKey]) {
        sortKeys = keys
        applySort()
    }

    func applySort() {
        guard !sortKeys.isEmpty || filter != nil else { order = nil; return }
        let keys = sortKeys
        let cols = columns
        let data = rows
        let fmt = format
        let visible = filter.map { f in data.indices.filter { f.matches(data[$0], columns: cols, format: fmt) } } ?? Array(data.indices)
        guard !keys.isEmpty else { order = visible; return }
        // Sortowanie stabilne: przy równych kluczach kolejność z bazy.
        order = visible.sorted { a, b in
            for k in keys {
                let c = Self.compare(data[a][k.column], data[b][k.column], type: cols[k.column].type, caseSensitive: false)
                if c != .orderedSame { return k.ascending ? c == .orderedAscending : c == .orderedDescending }
            }
            return a < b
        }
    }

    /// Porównanie wartości: liczby numerycznie, daty chronologicznie, tekst bez rozróżniania wielkości liter
    /// (chyba że `caseSensitive`), NULL na końcu przy rosnącym.
    nonisolated static func compare(_ x: OracleValue, _ y: OracleValue, type: OracleType, caseSensitive: Bool) -> ComparisonResult {
        switch (x, y) {
        case (.null, .null): return .orderedSame
        case (.null, _): return .orderedDescending
        case (_, .null): return .orderedAscending
        case (.number(let a), .number(let b)):
            if let da = Decimal(string: a, locale: Locale(identifier: "en_US_POSIX")), let db = Decimal(string: b, locale: Locale(identifier: "en_US_POSIX")) {
                return da == db ? .orderedSame : (da < db ? .orderedAscending : .orderedDescending)
            }
            return a.compare(b)
        case (.double(let a), .double(let b)): return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        case (.timestamp(let a, _), .timestamp(let b, _)):
            let ka = [Int(a.year), Int(a.month), Int(a.day), Int(a.hour), Int(a.minute), Int(a.second), Int(a.fsecond)]
            let kb = [Int(b.year), Int(b.month), Int(b.day), Int(b.hour), Int(b.minute), Int(b.second), Int(b.fsecond)]
            for (p, q) in zip(ka, kb) where p != q { return p < q ? .orderedAscending : .orderedDescending }
            return .orderedSame
        default:
            let a = x.format(.default), b = y.format(.default)
            return caseSensitive ? a.compare(b, locale: Locale.current) : a.compare(b, options: [.caseInsensitive], locale: Locale.current)
        }
    }

    /// Dane do eksportu/kopiowania: wiersze widoku (nil — wszystkie pobrane) i kolumny w kolejności widoku.
    public func exportData(rows viewRows: [Int]? = nil, columns cols: [Int]? = nil, title: String) -> ExportData {
        let c = cols ?? Array(columns.indices)
        let r = viewRows ?? Array(0..<rowCount)
        return ExportData(title: title, columns: c.map { columns[$0] }, rows: r.map { row in c.map { value(row: row, column: $0) } },
                          tableName: ResultExporter.tableName(fromQuery: sql), sql: sql)
    }

    /// Tekst komórki (siatka pokazuje LOB/LONG jako `<CLOB>` itd. jak wzorzec — UG 7.2).
    public func text(row: Int, column: Int) -> String {
        let v = value(row: row, column: column)
        switch v {
        case .lob(let l): return "<\(l.kind.rawValue)>"
        case .cursor: return "<Cursor>"
        case .object(let t, _): return "<\(t)>"
        case .text(let s) where columns[column].type == .long: return s.isEmpty ? "" : "<Long>"
        case .raw where columns[column].type == .longRaw: return "<Long Raw>"
        default: return v.format(format)
        }
    }

    /// Dociąga kolejne `count` wierszy (nic nie robi, gdy kursor wyczerpany albo trwa pobieranie).
    public func fetchMore(_ count: Int) async { await fetchMore(count, resort: true) }

    private func fetchMore(_ count: Int, resort: Bool) async {
        guard hasMore, !isFetching, let s = sessionRef else { return }
        isFetching = true
        defer { isFetching = false }
        if sizeLimitBytes > 0, approximateBytes >= sizeLimitBytes, !sizeLimitAccepted {
            if let confirm = confirmSizeLimit, await confirm(approximateBytes) {
                sizeLimitAccepted = true
                stoppedAtSizeLimit = false
            } else {
                stoppedAtSizeLimit = true
                return
            }
        }
        do {
            let batch = try await s.fetch(resultSet, maxRows: count)
            approximateBytes += batch.rows.reduce(0) { $0 + ResultSize.bytes($1) }
            rows.append(contentsOf: batch.rows)
            hasMore = batch.hasMore
            if resort, !sortKeys.isEmpty || filter != nil { applySort() }   // sortowane są pobrane wiersze — po dociągnięciu na nowo
            if !batch.hasMore { sessionRef = nil }
        } catch let e as OracleError {
            lastError = e.message
            hasMore = false
        } catch {
            lastError = error.localizedDescription
            hasMore = false
        }
    }

    /// Pobiera wszystkie wiersze („Last Page”), z limitem bezpieczeństwa.
    public func fetchAll(limit: Int = 5_000_000) async {
        while hasMore, rows.count < limit, !stoppedAtSizeLimit {
            let before = rows.count
            await fetchMore(10_000, resort: false)
            if rows.count == before { break }
        }
        if !sortKeys.isEmpty || filter != nil { applySort() }
    }

    /// Zamyka kursor (zamknięcie karty, ponowne wykonanie).
    public func close() async {
        guard hasMore, let s = sessionRef else { return }
        hasMore = false
        sessionRef = nil
        await s.closeResultSet(resultSet)
    }
}

/// Karta wyniku w SQL Window (UG 7.1): wynik zapytania albo komunikat polecenia.
@MainActor
@Observable
public final class ResultTab: Identifiable {
    public let id = UUID()
    public var title: String
    /// Zakres polecenia w tekście okna (UTF-16) — podświetlenie po wybraniu karty.
    public var statementRange: Range<Int>
    public var grid: ResultGridModel?
    public var message: String?
    public var pinned = false
    public var elapsed: Duration = .zero
    /// Zaznaczenie w siatce (wiersze widoku; nil — brak) i kolejność kolumn po przeciąganiu — ustawia interfejs.
    public var selectedRows: [Int]?
    /// Kolumny bloku komórek (PD-GRID-007); nil — całe wiersze.
    public var selectedColumns: [Int]?
    public var columnOrder: [Int]?
    /// Kolumna do pokazania (np. z błędem po zatwierdzaniu zmian — NF12).
    public var focusedColumn: Int?
    /// Bieżąca komórka (ostatnio kliknięta kolumna) — Large Data Editor, widok rekordu.
    public var currentColumn: Int?
    /// Wiersz widoku do zaznaczenia i pokazania (np. następna zmiana oczekująca — DG-GRID-001); interfejs zeruje po użyciu.
    public var revealRow: Int?
    /// Kolumny ukryte filtrem kolumn (PD-GRID-011) i aktywny filtr.
    public var hiddenColumns: Set<Int> = []
    public var columnFilter: ColumnFilter?
    /// Szerokości kolumn w znakach po „Align” (PD-GRID-012); nil — szerokości domyślne.
    public var columnWidths: [Int: Int]?
    /// Linie tekstu na wiersz siatki (PD-GRID-012, „Align › wysokość”): 1 — jedna linia; więcej — zawijanie.
    public var rowLines = 1
    /// Sumy kolumn (PD-GRID-024): kolumna → funkcje.
    public var totals: [Int: [ColumnAggregate]] = [:]
    /// Kolor naprzemiennych wierszy z dyrektywy `AltRowColor=` (PD-SQLW-011), np. `#F0F0FF` albo nazwa.
    public var altRowColor: String?
    /// Kryteria Query By Example (PD-SQLW-022): kolumna → wyrażenie.
    public var qbeCriteria: [Int: String] = [:]
    /// Tekst polecenia wyniku (przed podstawieniem zmiennych) — odświeżanie karty (PD-SQLW-006).
    public var statementText: String?
    /// Informacje słownika o kolumnach tabeli wyniku (PD-GRID-022), wczytywane przy pierwszym użyciu.
    public var columnInfo: [Int: ColumnDictionaryInfo]?
    /// Widok pojedynczego rekordu zamiast tabeli (PD-GRID-010) — przełącza `grid.toggleRecordView`.
    public var showsRecord = false

    public init(title: String, statementRange: Range<Int>, grid: ResultGridModel? = nil, message: String? = nil) {
        self.title = title
        self.statementRange = statementRange
        self.grid = grid
        self.message = message
    }
}
